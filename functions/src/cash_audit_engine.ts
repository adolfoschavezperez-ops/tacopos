export const CASH_AUDIT_ENGINE_VERSION = 1;
export const MONEY_TOLERANCE = 0.02;

export interface CashAuditSessionInput {
  id: string;
  businessDate: string;
  branchId: string;
  openingCashAmount: number;
  countedCashAmount: number;
  terminalReportedAmount: number;
  expectedCashAmount: number;
  expectedCardChargedAmount: number;
  approvedWithdrawalsTotal: number;
}

export interface CashAuditOrderInput {
  id: string;
  label: string;
  orderType?: string;
  businessDate?: string;
  operationalDate?: string;
  cashSessionId?: string;
  branchId?: string;
  status: string;
  paymentStatus: string;
  grossSubtotal?: number;
  explicitDiscount?: number;
  netTotal?: number;
  total: number;
  paidTotal: number;
  pendingTotal: number;
  createdAt?: string;
}

export interface CashAuditPaymentInput {
  id: string;
  orderId: string;
  method: string;
  amount: number;
  baseAmount: number;
  chargedAmount: number;
  appliedAmount?: number | null;
  cashReceivedAmount?: number | null;
  cashChangeAmount?: number | null;
  status: string;
  cancelledAt?: string | null;
  createdAt?: string;
  businessDate?: string;
  cashSessionId?: string;
  branchId?: string;
  employeeName?: string;
  tipAmount?: number;
  discountAmount?: number;
  discountPercent?: number;
  appliedDiscountPercent?: number;
  appliedDiscountType?: string | null;
  appliedDiscountName?: string | null;
  discountSource?: string | null;
  discountCatalogId?: string | null;
  discountName?: string | null;
  totalAfterDiscount?: number;
  subtotalBeforeDiscount?: number;
  orderGrossSubtotal?: number;
  orderNetTotal?: number;
  type?: string;
  cardFeeAbsorbedAmount?: number;
  surchargeAmount?: number;
}

export interface CashAuditPaymentRow {
  paymentId: string;
  orderId: string;
  label: string;
  originalMethod: string;
  normalizedMethod: string;
  baseAmount: number;
  amountForAudit: number;
  receivedAmount?: number | null;
  changeAmount?: number | null;
  status: string;
  cancelledAt?: string | null;
  createdAt?: string;
  businessDate: string;
  orderBusinessDate: string;
  cashSessionId: string;
  orderCashSessionId: string;
  employeeName: string;
  orderNetTotal: number;
  orderStatus: string;
  tipAmount: number;
  included: boolean;
  inclusionReason: string;
}

export interface CashAuditCandidate {
  kind: "cash" | "card" | "change";
  confidence: "Alto" | "Medio" | "Bajo";
  amount: number;
  paymentId: string;
  orderId: string;
  label: string;
  method: string;
  employeeName: string;
  createdAt?: string;
  explanation: string;
}

export interface CashAuditResult {
  engineVersion: number;
  cashSessionId: string;
  businessDate: string;
  branchId: string;
  grossSales: number;
  discountTotal: number;
  netSales: number;
  activePaymentTotal: number;
  activeCashPayments: number;
  activeCardPayments: number;
  paymentNetDifference: number;
  cashPos: number;
  cardPos: number;
  countedCashLessOpening: number;
  cashDifference: number;
  cardDifference: number;
  totalDifference: number;
  observedMoney: number;
  expectedPhysicalMoney: number;
  globalDifference: number;
  shortageAmount: number;
  overAmount: number;
  cardCandidates: CashAuditCandidate[];
  cashCandidates: CashAuditCandidate[];
  changeIssues: CashAuditCandidate[];
  payments: CashAuditPaymentRow[];
  generatedAt: string;
}

export function normalizeCashAuditPaymentMethod(method: string): string {
  const value = method.trim().toLowerCase().replaceAll(" ", "_").replaceAll("-", "_");
  if (value === "cash" || value === "efectivo") return "cash";
  if (["card", "tarjeta", "credit_card", "debit_card", "terminal", "mercado_pago", "mp", "bancaria"].includes(value)) {
    return "card";
  }
  if (value === "platform_paid" || value === "plataforma") return "platform_paid";
  if (value === "employee_consumption" || value === "consumo_empleado") return "employee_consumption";
  return value;
}

export function paymentDiscountAppliedToSale(payment: CashAuditPaymentInput): number {
  if (isFreeMealPayment(payment) && payment.baseAmount > 0) return money(Math.max(0, payment.baseAmount));
  const explicit = Math.max(0, payment.discountAmount ?? 0);
  if (explicit > 0) return money(explicit);
  const rawPercent = (payment.appliedDiscountPercent ?? 0) > 0
    ? payment.appliedDiscountPercent ?? 0
    : payment.discountPercent ?? 0;
  if (rawPercent <= 0 || payment.baseAmount <= 0) return 0;
  const normalized = rawPercent > 1 ? rawPercent / 100 : rawPercent;
  return money(clamp(payment.baseAmount * normalized, 0, payment.baseAmount));
}

export function canonicalPaymentAppliedAmount(payment: CashAuditPaymentInput, tipOverride?: number): number {
  if (isFreeMealPayment(payment)) return 0;
  const tip = Math.max(0, tipOverride ?? payment.tipAmount ?? 0);
  const discount = paymentDiscountAppliedToSale(payment);
  if (payment.appliedAmount !== undefined && payment.appliedAmount !== null && payment.appliedAmount >= 0) {
    if (isLegacyGrossDiscountedPayment(payment, payment.appliedAmount, discount)) {
      return money(legacyDiscountedNetAmount(payment, payment.appliedAmount, discount, tip));
    }
    return money(Math.max(0, payment.appliedAmount));
  }
  const totalAfterDiscount = payment.totalAfterDiscount ?? 0;
  if (totalAfterDiscount > 0) {
    if (isLegacyGrossDiscountedPayment(payment, totalAfterDiscount, discount)) {
      return money(legacyDiscountedNetAmount(payment, totalAfterDiscount, discount, tip));
    }
    return money(Math.max(0, totalAfterDiscount - tip));
  }
  if (payment.chargedAmount > 0 && payment.baseAmount > 0 && payment.chargedAmount < payment.baseAmount - MONEY_TOLERANCE) {
    return money(Math.max(0, payment.chargedAmount - tip));
  }
  const baseNet = payment.baseAmount > 0 ? Math.max(0, payment.baseAmount - discount) : 0;
  if (baseNet > 0 || discount > 0) return money(baseNet);
  const fee = (payment.cardFeeAbsorbedAmount ?? 0) > 0
    ? payment.cardFeeAbsorbedAmount ?? 0
    : payment.surchargeAmount ?? 0;
  return money(Math.max(0, payment.chargedAmount - tip - fee));
}

export function buildCashAudit(input: {
  session: CashAuditSessionInput;
  orders: CashAuditOrderInput[];
  payments: CashAuditPaymentInput[];
  generatedAt?: string;
}): CashAuditResult {
  const {session, orders, payments} = input;
  const orderById = new Map(orders.map((order) => [order.id, order]));
  const paymentRows = payments.map((payment) => paymentRow(session, payment, orderById.get(payment.orderId)));
  const includedPayments = paymentRows.filter((row) => row.included);
  const sessionOrders = orders.filter((order) => orderMatchesSession(order, session));
  const grossSales = money(sessionOrders.filter((order) => !isCancelledStatus(order.status)).reduce((sum, order) => sum + (order.grossSubtotal ?? order.total), 0));
  const discountTotal = money(sessionOrders.filter((order) => !isCancelledStatus(order.status)).reduce((sum, order) => sum + (order.explicitDiscount ?? 0), 0));
  const netSales = money(sessionOrders.filter((order) => !isCancelledStatus(order.status)).reduce((sum, order) => sum + (order.netTotal ?? order.total), 0));
  const cashOverstatement = discountedGrossOverstatement(includedPayments, "cash");
  const cardOverstatement = discountedGrossOverstatement(includedPayments, "card");
  const cashPos = money(session.expectedCashAmount - session.openingCashAmount + session.approvedWithdrawalsTotal - cashOverstatement);
  const countedCashLessOpening = money(session.countedCashAmount - session.openingCashAmount);
  const cashDifference = money(countedCashLessOpening - cashPos + session.approvedWithdrawalsTotal);
  const cardPos = money(session.expectedCardChargedAmount - cardOverstatement);
  const cardDifference = money(session.terminalReportedAmount - cardPos);
  const totalDifference = money(cashDifference + cardDifference);
  const observedMoney = money(countedCashLessOpening + session.terminalReportedAmount);
  const expectedPhysicalMoney = money(netSales - session.approvedWithdrawalsTotal);
  const globalDifference = money(observedMoney - expectedPhysicalMoney);
  const activePaymentTotal = money(includedPayments.reduce((sum, row) => sum + row.amountForAudit, 0));
  const activeCashPayments = money(includedPayments.filter((row) => row.normalizedMethod === "cash").reduce((sum, row) => sum + row.amountForAudit, 0));
  const activeCardPayments = money(includedPayments.filter((row) => row.normalizedMethod === "card").reduce((sum, row) => sum + row.amountForAudit, 0));

  return {
    engineVersion: CASH_AUDIT_ENGINE_VERSION,
    cashSessionId: session.id,
    businessDate: session.businessDate,
    branchId: session.branchId,
    grossSales,
    discountTotal,
    netSales,
    activePaymentTotal,
    activeCashPayments,
    activeCardPayments,
    paymentNetDifference: money(activePaymentTotal - netSales),
    cashPos,
    cardPos,
    countedCashLessOpening,
    cashDifference,
    cardDifference,
    totalDifference,
    observedMoney,
    expectedPhysicalMoney,
    globalDifference,
    shortageAmount: globalDifference < 0 ? money(Math.abs(globalDifference)) : 0,
    overAmount: globalDifference > 0 ? globalDifference : 0,
    cardCandidates: cardCandidates(session, includedPayments, cardOverstatement),
    cashCandidates: cashCandidates(cashDifference, includedPayments),
    changeIssues: changeIssues(includedPayments),
    payments: paymentRows,
    generatedAt: input.generatedAt ?? new Date().toISOString(),
  };
}

function paymentRow(session: CashAuditSessionInput, payment: CashAuditPaymentInput, order?: CashAuditOrderInput): CashAuditPaymentRow {
  const normalizedMethod = normalizeCashAuditPaymentMethod(payment.method);
  const active = payment.status === "active" && !payment.cancelledAt;
  const included = active && (payment.cashSessionId ?? "") === session.id && !isCancelledStatus(order?.status ?? "");
  return {
    paymentId: payment.id,
    orderId: payment.orderId,
    label: order?.label ?? payment.orderId,
    originalMethod: payment.method,
    normalizedMethod,
    baseAmount: payment.baseAmount,
    amountForAudit: canonicalPaymentAppliedAmount(payment, payment.tipAmount),
    receivedAmount: payment.cashReceivedAmount,
    changeAmount: payment.cashChangeAmount,
    status: payment.status,
    cancelledAt: payment.cancelledAt,
    createdAt: payment.createdAt,
    businessDate: payment.businessDate ?? "",
    orderBusinessDate: order?.businessDate ?? order?.operationalDate ?? "",
    cashSessionId: payment.cashSessionId ?? "",
    orderCashSessionId: order?.cashSessionId ?? "",
    employeeName: payment.employeeName ?? "",
    orderNetTotal: order?.netTotal ?? order?.total ?? 0,
    orderStatus: order?.status ?? "",
    tipAmount: payment.tipAmount ?? 0,
    included,
    inclusionReason: included ? "payment.cashSessionId activo coincide con el corte" : exclusionReason(session, payment, order),
  };
}

function discountedGrossOverstatement(rows: CashAuditPaymentRow[], method: string): number {
  return money(rows.filter((row) => row.included && row.normalizedMethod === method).reduce((sum, row) => {
    const overstatement = row.baseAmount - row.amountForAudit;
    return sum + (overstatement > MONEY_TOLERANCE ? overstatement : 0);
  }, 0));
}

function cardCandidates(session: CashAuditSessionInput, rows: CashAuditPaymentRow[], cardOverstatement: number): CashAuditCandidate[] {
  const target = session.terminalReportedAmount - (session.expectedCardChargedAmount - cardOverstatement);
  return rows.filter((row) => row.normalizedMethod === "cash").map((row) => candidate("card", target, row,
    "Pago activo registrado como efectivo; su importe esta cerca de la diferencia de terminal."))
    .sort((a, b) => Math.abs(Math.abs(target) - Math.abs(a.amount)) - Math.abs(Math.abs(target) - Math.abs(b.amount))).slice(0, 12);
}

function cashCandidates(target: number, rows: CashAuditPaymentRow[]): CashAuditCandidate[] {
  return rows.filter((row) => row.normalizedMethod === "cash").map((row) => candidate("cash", target, row,
    "Pago en efectivo cercano a la diferencia de arqueo."))
    .sort((a, b) => Math.abs(Math.abs(target) - Math.abs(a.amount)) - Math.abs(Math.abs(target) - Math.abs(b.amount))).slice(0, 12);
}

function changeIssues(rows: CashAuditPaymentRow[]): CashAuditCandidate[] {
  return rows.filter((row) => {
    if (row.normalizedMethod !== "cash") return false;
    const received = row.receivedAmount;
    const change = row.changeAmount;
    if (received === undefined || received === null || change === undefined || change === null) return false;
    if (received === 0 && change === 0) return false;
    return Math.abs((received - change) - row.amountForAudit) > MONEY_TOLERANCE || received < row.amountForAudit || change < 0;
  }).map((row) => ({
    kind: "change" as const,
    confidence: "Alto" as const,
    amount: row.amountForAudit,
    paymentId: row.paymentId,
    orderId: row.orderId,
    label: row.label,
    method: row.originalMethod,
    employeeName: row.employeeName,
    createdAt: row.createdAt,
    explanation: "receivedAmount - changeAmount no coincide con el importe aplicado.",
  }));
}

function candidate(kind: "cash" | "card", target: number, row: CashAuditPaymentRow, explanation: string): CashAuditCandidate {
  const gap = Math.abs(Math.abs(target) - Math.abs(row.amountForAudit));
  return {
    kind,
    confidence: gap <= 1 ? "Alto" : gap <= 10 ? "Medio" : "Bajo",
    amount: row.amountForAudit,
    paymentId: row.paymentId,
    orderId: row.orderId,
    label: row.label,
    method: row.originalMethod,
    employeeName: row.employeeName,
    createdAt: row.createdAt,
    explanation,
  };
}

function orderMatchesSession(order: CashAuditOrderInput, session: CashAuditSessionInput): boolean {
  if ((order.cashSessionId ?? "") === session.id) return true;
  const cashSessionId = (order.cashSessionId ?? "").trim();
  const date = order.businessDate ?? order.operationalDate ?? "";
  const branch = (order.branchId ?? "").trim();
  return cashSessionId.length === 0 && date === session.businessDate && (branch.length === 0 || branch === session.branchId);
}

function exclusionReason(session: CashAuditSessionInput, payment: CashAuditPaymentInput, order?: CashAuditOrderInput): string {
  if (payment.status !== "active" || payment.cancelledAt) return "payment cancelado o inactivo";
  if ((payment.cashSessionId ?? "") !== session.id) return "cashSessionId distinto o faltante";
  if (order && isCancelledStatus(order.status)) return "orden cancelada";
  return "metodo no considerado por el corte";
}

function isFreeMealPayment(payment: CashAuditPaymentInput): boolean {
  const clean = [payment.appliedDiscountType, payment.appliedDiscountName, payment.discountSource, payment.discountCatalogId, payment.discountName]
    .filter((value): value is string => typeof value === "string").join(" ").trim().toLowerCase();
  return clean.includes("employee_free_meal") || clean.includes("free_meal") || clean.includes("free meal") || clean.includes("comida empleado") || clean.includes("comida de empleado");
}

function isLegacyGrossDiscountedPayment(payment: CashAuditPaymentInput, appliedAmount: number, discount: number): boolean {
  if (discount <= 0 && (payment.appliedDiscountPercent ?? 0) <= 0) return false;
  const grossFieldsMatch = payment.baseAmount > 0 && Math.abs(appliedAmount - payment.baseAmount) <= MONEY_TOLERANCE &&
    ((payment.subtotalBeforeDiscount ?? 0) <= 0 || Math.abs(appliedAmount - (payment.subtotalBeforeDiscount ?? 0)) <= MONEY_TOLERANCE);
  if (!grossFieldsMatch) return false;
  const orderGrossSubtotal = payment.orderGrossSubtotal ?? 0;
  const orderNetTotal = payment.orderNetTotal ?? 0;
  const hasOrderNetEvidence = orderGrossSubtotal > 0 && orderNetTotal >= 0 && orderNetTotal < orderGrossSubtotal - MONEY_TOLERANCE &&
    (payment.type === "full_table" || Math.abs(payment.baseAmount - orderGrossSubtotal) <= MONEY_TOLERANCE);
  const received = payment.cashReceivedAmount;
  const change = payment.cashChangeAmount;
  const hasCashEvidence = payment.method === "cash" && received !== undefined && received !== null && change !== undefined && change !== null &&
    received - change >= 0 && Math.abs((received - change) - appliedAmount) > MONEY_TOLERANCE;
  return hasOrderNetEvidence || hasCashEvidence;
}

function legacyDiscountedNetAmount(payment: CashAuditPaymentInput, appliedAmount: number, discount: number, tip: number): number {
  const orderGrossSubtotal = payment.orderGrossSubtotal ?? 0;
  const orderNetTotal = payment.orderNetTotal ?? 0;
  if (orderNetTotal >= 0 && orderGrossSubtotal > 0 && orderNetTotal < orderGrossSubtotal - MONEY_TOLERANCE) {
    return Math.max(0, orderNetTotal - tip);
  }
  return Math.max(0, appliedAmount - discount - tip);
}

function isCancelledStatus(status: string): boolean {
  return ["cancelled", "canceled", "cancelado", "cancelada", "void", "voided", "anulado", "anulada"].includes(status.trim().toLowerCase());
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function money(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}
