import * as assert from "node:assert/strict";
import {
  buildCashAudit,
  canonicalPaymentAppliedAmount,
  CashAuditOrderInput,
  CashAuditPaymentInput,
  CashAuditSessionInput,
} from "../cash_audit_engine";

describe("cash audit backend parity", () => {
  it("matches the Dart legacy discounted-payment reconciliation case", () => {
    const session = makeSession({
      countedCashAmount: 1542,
      terminalReportedAmount: 1989.05,
      expectedCashAmount: 2429,
      expectedCardChargedAmount: 2128,
      approvedWithdrawalsTotal: 165,
    });
    const orders = [
      makeOrder("employee-order", "Mesa 1", 290, 203),
      makeOrder("partner-order", "Mesa 2", 374, 187),
      makeOrder("normal-order", "Mesa 3", 3802, 3558),
    ];
    const payments = [
      makePayment("employee-payment", "employee-order", 290, {
        appliedAmount: 290,
        appliedDiscountPercent: 30,
        orderGrossSubtotal: 290,
        orderNetTotal: 203,
        cashReceivedAmount: 203,
      }),
      makePayment("partner-payment", "partner-order", 374, {
        method: "card",
        appliedAmount: 374,
        appliedDiscountPercent: 50,
        orderGrossSubtotal: 374,
        orderNetTotal: 187,
      }),
      makePayment("normal-cash", "normal-order", 1804),
      makePayment("normal-card", "normal-order", 1754, {method: "card"}),
    ];

    const report = buildCashAudit({session, orders, payments, generatedAt: "2026-09-09T00:00:00.000Z"});

    assert.equal(report.activeCashPayments, 2007);
    assert.equal(report.activeCardPayments, 1941);
    assert.equal(report.activePaymentTotal, 3948);
    assert.equal(report.paymentNetDifference, 0);
    assert.equal(report.cashDifference, -800);
    assert.equal(report.cardDifference, 48.05);
    assert.equal(report.totalDifference, -751.95);
    assert.equal(report.globalDifference, -751.95);
  });

  it("finds a cash payment that nearly matches the terminal difference", () => {
    const session = makeSession({});
    const orders = [
      makeOrder("card-candidate-order", "#103", 660, 660),
      makeOrder("card-pos-order", "#100", 132, 132),
      makeOrder("net-zero-1", "Mesa 2", 88, 0),
      makeOrder("net-zero-2", "Mesa 4-A", 102, 0),
      makeOrder("cash-change-order", "Mesa 1", 100, 100),
    ];
    const payments = [
      makePayment("cash-as-card-candidate", "card-candidate-order", 660),
      makePayment("card-pos-payment", "card-pos-order", 132, {method: "card"}),
      makePayment("net-zero-payment-1", "net-zero-1", 88),
      makePayment("net-zero-payment-2", "net-zero-2", 102),
      makePayment("received-change", "cash-change-order", 100, {cashReceivedAmount: 200, cashChangeAmount: 100}),
    ];

    const report = buildCashAudit({session, orders, payments, generatedAt: "2026-09-09T00:00:00.000Z"});

    assert.equal(report.cashPos, 2965.4);
    assert.equal(report.cashDifference, 86.6);
    assert.equal(report.cardDifference, 660.76);
    assert.equal(report.cardCandidates[0]?.paymentId, "cash-as-card-candidate");
    assert.equal(report.cardCandidates[0]?.confidence, "Alto");
    assert.equal(report.changeIssues.length, 0);
  });

  it("flags received/change mismatches only when captured", () => {
    const payment = makePayment("bad-change", "cash-order", 100, {
      cashReceivedAmount: 150,
      cashChangeAmount: 20,
    });
    const report = buildCashAudit({
      session: makeSession({}),
      orders: [makeOrder("cash-order", "Mesa 7", 100, 100)],
      payments: [payment],
      generatedAt: "2026-09-09T00:00:00.000Z",
    });

    assert.equal(report.changeIssues.length, 1);
    assert.equal(report.changeIssues[0]?.paymentId, "bad-change");
  });

  it("keeps free meal monetary amount at zero", () => {
    const payment = makePayment("free-meal", "employee-order", 174, {
      method: "employee_consumption",
      appliedDiscountType: "employee_free_meal",
      appliedDiscountName: "Comida empleado del dia",
      discountAmount: 174,
      appliedDiscountPercent: 100,
      chargedAmount: 0,
    });

    assert.equal(canonicalPaymentAppliedAmount(payment), 0);
  });
});

function makeSession(overrides: Partial<CashAuditSessionInput>): CashAuditSessionInput {
  return {
    id: "NkTSfERJPJb0hbRhrStH",
    businessDate: "2026-07-27",
    branchId: "aviacion",
    openingCashAmount: 500,
    countedCashAmount: 3552,
    terminalReportedAmount: 941.76,
    expectedCashAmount: 3465.4,
    expectedCardChargedAmount: 281,
    approvedWithdrawalsTotal: 0,
    ...overrides,
  };
}

function makeOrder(id: string, label: string, total: number, netTotal: number): CashAuditOrderInput {
  return {
    id,
    label,
    orderType: label.startsWith("#") ? "takeout" : "dine_in",
    businessDate: "2026-07-27",
    cashSessionId: "NkTSfERJPJb0hbRhrStH",
    branchId: "aviacion",
    status: "paid",
    paymentStatus: "paid",
    grossSubtotal: total,
    explicitDiscount: Math.max(0, total - netTotal),
    netTotal,
    total,
    paidTotal: total,
    pendingTotal: 0,
  };
}

function makePayment(
  id: string,
  orderId: string,
  amount: number,
  overrides: Partial<CashAuditPaymentInput> = {},
): CashAuditPaymentInput {
  return {
    id,
    orderId,
    method: "cash",
    amount,
    baseAmount: amount,
    chargedAmount: amount,
    type: "full_table",
    status: "active",
    cashSessionId: "NkTSfERJPJb0hbRhrStH",
    businessDate: "2026-07-27",
    branchId: "aviacion",
    createdAt: "2026-07-28T03:00:00.000Z",
    ...overrides,
  };
}
