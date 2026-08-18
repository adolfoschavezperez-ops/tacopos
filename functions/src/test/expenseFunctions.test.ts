import * as assert from "assert";
import * as admin from "firebase-admin";
import {
  cancelExpenseRequest,
  cancelExpenseRequestCore,
  submitExpenseRequest,
  submitExpenseRequestCore,
} from "../index";

const db = admin.firestore();
const restaurantId = "test-restaurant";
const branchId = "main";
const uid = "device-1";

describe("secure expense autoapproval functions", () => {
  beforeEach(async () => {
    await clearRestaurant();
    await seedBase();
  });

  it("requires auth", async () => {
    await assert.rejects(
      () => submitExpenseRequestCore(db, baseInput(), {}),
      /Se requiere autenticacion/,
    );
  });

  it("requires App Check", async () => {
    await assert.rejects(
      () => submitExpenseRequestCore(db, baseInput(), {auth: {uid}}),
      /Se requiere App Check/,
    );
  });

  it("rejects consumed App Check token replay", async () => {
    await assert.rejects(
      () => submitExpenseRequestCore(db, baseInput(), {
        auth: {uid},
        app: {appId: "debug-app", alreadyConsumed: true},
      }),
      /Token App Check ya consumido/,
    );
  });

  it("requires active registered device", async () => {
    await restaurant().collection("devices").doc(uid).delete();
    await assert.rejects(
      () => submit(baseInput()),
      /Dispositivo no registrado/,
    );
  });

  it("rejects device from another branch", async () => {
    await restaurant().collection("devices").doc(uid).set({branchId: "other"}, {merge: true});
    await assert.rejects(() => submit(baseInput()), /otra sucursal/);
  });

  it("rejects cross restaurant device", async () => {
    await restaurant().collection("devices").doc(uid).set({restaurantId: "other"}, {merge: true});
    await assert.rejects(() => submit(baseInput()), /otro restaurante/);
  });

  it("rejects missing policy", async () => {
    await assert.rejects(() => submit(baseInput({policyId: "missing"})), /politica de gasto/);
  });

  it("keeps OFF mode pending", async () => {
    await setMode("off");
    const result = await submit(baseInput());
    assert.equal(result.status, "pending");
    assert.equal(result.autoApproved, false);
    assert.equal(result.reasonCode, "mode_off");
  });

  it("SHADOW valid request stays pending and records wouldAutoApprove", async () => {
    await setMode("shadow");
    const result = await submit(baseInput());
    assert.equal(result.status, "pending");
    assert.equal(result.autoApproved, false);
    assert.equal(result.wouldAutoApprove, true);
    const doc = await restaurant().collection("cashWithdrawalRequests").doc(result.requestId).get();
    assert.equal(doc.data()?.wouldAutoApprove, true);
  });

  it("SHADOW invalid request stays pending with policy reason", async () => {
    await setMode("shadow");
    const result = await submit(baseInput({amount: 500}));
    assert.equal(result.status, "pending");
    assert.equal(result.wouldAutoApprove, false);
    assert.equal(result.reasonCode, "max_transaction_amount");
  });

  it("LIVE valid request autoapproves", async () => {
    await setMode("live");
    const result = await submit(baseInput());
    assert.equal(result.status, "approved");
    assert.equal(result.autoApproved, true);
  });

  it("LIVE invalid request stays pending", async () => {
    await setMode("live");
    const result = await submit(baseInput({amount: 500}));
    assert.equal(result.status, "pending");
    assert.equal(result.autoApproved, false);
  });

  it("enforces max transaction", async () => {
    await setMode("live");
    const result = await submit(baseInput({amount: 101}));
    assert.equal(result.reasonCode, "max_transaction_amount");
  });

  it("enforces cumulative amount", async () => {
    await setMode("live");
    await submit(baseInput({amount: 80, clientRequestId: "cumulative-1"}));
    const result = await submit(baseInput({amount: 30, clientRequestId: "cumulative-2"}));
    assert.equal(result.status, "pending");
    assert.equal(result.reasonCode, "max_period_amount");
  });

  it("enforces max uses", async () => {
    await setMode("live");
    await updatePolicy({maxUsesPerPeriod: 1});
    await submit(baseInput({clientRequestId: "uses-1"}));
    const result = await submit(baseInput({clientRequestId: "uses-2"}));
    assert.equal(result.reasonCode, "max_uses");
  });

  it("supports daily period", async () => {
    await setMode("live");
    const result = await submit(baseInput());
    assert.match(result.reasonCode, /auto_approved/);
  });

  it("supports every N days period", async () => {
    await setMode("live");
    await updatePolicy({frequencyType: "everyNDays", frequencyValue: 2});
    const result = await submit(baseInput());
    assert.equal(result.autoApproved, true);
  });

  it("supports weekly period", async () => {
    await setMode("live");
    await updatePolicy({frequencyType: "weekly"});
    const result = await submit(baseInput());
    assert.equal(result.autoApproved, true);
  });

  it("supports every N weeks period", async () => {
    await setMode("live");
    await updatePolicy({frequencyType: "everyNWeeks", frequencyValue: 2});
    const result = await submit(baseInput());
    assert.equal(result.autoApproved, true);
  });

  it("supports monthly period", async () => {
    await setMode("live");
    await updatePolicy({frequencyType: "monthly"});
    const result = await submit(baseInput());
    assert.equal(result.autoApproved, true);
  });

  it("enforces weekdays", async () => {
    await setMode("live");
    await updatePolicy({frequencyType: "specificWeekdays", allowedWeekdays: [1]});
    const result = await submit(baseInput({businessDate: "2026-08-18"}));
    assert.equal(result.reasonCode, "frequency_not_allowed");
  });

  it("enforces receipt", async () => {
    await setMode("live");
    await updatePolicy({receiptRequired: true});
    const result = await submit(baseInput({hasReceipt: false}));
    assert.equal(result.reasonCode, "receipt_required");
  });

  it("enforces supplier", async () => {
    await setMode("live");
    await updatePolicy({supplierRestrictionEnabled: true, allowedSupplierIds: ["supplier-ok"]});
    const result = await submit(baseInput({supplierId: "supplier-bad"}));
    assert.equal(result.reasonCode, "supplier_not_allowed");
  });

  it("enforces payment source", async () => {
    await setMode("live");
    await updatePolicy({allowedPaymentSources: ["card"]});
    const result = await submit(baseInput({paymentSource: "cash"}));
    assert.equal(result.reasonCode, "payment_source_not_allowed");
  });

  it("enforces validity", async () => {
    await setMode("live");
    await updatePolicy({validFrom: "2026-08-19"});
    const result = await submit(baseInput({businessDate: "2026-08-18"}));
    assert.equal(result.reasonCode, "not_yet_valid");
  });

  it("enforces allowed time", async () => {
    await setMode("live");
    await updatePolicy({allowedStartTime: "23:59", allowedEndTime: "23:59"});
    const result = await submit(baseInput());
    assert.equal(result.reasonCode, "time_not_allowed");
  });

  it("handles concurrent requests without overusing quota", async () => {
    await setMode("live");
    await updatePolicy({maxUsesPerPeriod: 1});
    const results = await Promise.all([
      submit(baseInput({clientRequestId: "concurrent-a"})),
      submit(baseInput({clientRequestId: "concurrent-b"})),
    ]);
    assert.equal(results.filter((row) => row.autoApproved).length, 1);
    assert.equal(results.filter((row) => row.status === "pending").length, 1);
  });

  it("is idempotent for duplicate clientRequestId", async () => {
    await setMode("live");
    const first = await submit(baseInput({clientRequestId: "same-id"}));
    const second = await submit(baseInput({clientRequestId: "same-id", amount: 99}));
    assert.equal(second.requestId, first.requestId);
    assert.equal(second.periodUsage, first.periodUsage);
  });

  it("does not duplicate retry after timeout", async () => {
    await setMode("live");
    await submit(baseInput({clientRequestId: "retry-id"}));
    await submit(baseInput({clientRequestId: "retry-id"}));
    const snapshot = await restaurant().collection("cashWithdrawalRequests").get();
    assert.equal(snapshot.size, 1);
  });

  it("usage never exceeds limit", async () => {
    await setMode("live");
    await updatePolicy({maxUsesPerPeriod: 1});
    await Promise.allSettled([
      submit(baseInput({clientRequestId: "limit-a"})),
      submit(baseInput({clientRequestId: "limit-b"})),
    ]);
    const usage = await restaurant().collection("expensePolicyUsage").get();
    assert.equal(usage.docs[0].data().usesUsed, 1);
  });

  it("builds snapshot server-side", async () => {
    await setMode("live");
    const result = await submit(baseInput());
    const doc = await restaurant().collection("cashWithdrawalRequests").doc(result.requestId).get();
    assert.equal(doc.data()?.policySnapshot.policyName, "Hielo");
  });

  it("rejects forged autoApproved", async () => {
    await assert.rejects(
      () => submit(baseInput({autoApproved: true})),
      /Campo no permitido/,
    );
  });

  it("validates cash session", async () => {
    await setMode("live");
    await restaurant().collection("cashSessions").doc("cash-1").set({status: "closed"}, {merge: true});
    await assert.rejects(() => submit(baseInput()), /cerrada/);
  });

  it("rejects closed cut", async () => {
    await setMode("live");
    await restaurant().collection("cashSessions").doc("cash-1").set({closedAt: admin.firestore.Timestamp.now()}, {merge: true});
    await assert.rejects(() => submit(baseInput()), /cerrada/);
  });

  it("cancels without restore when policy disables restore", async () => {
    await setMode("live");
    const result = await submit(baseInput());
    const cancelled = await cancelExpenseRequestCore(db, {
      restaurantId,
      requestId: result.requestId,
      reason: "duplicado",
    }, adminContext());
    assert.equal(cancelled.restored, false);
  });

  it("requires App Check for cancellation", async () => {
    await setMode("live");
    const result = await submit(baseInput());
    await assert.rejects(
      () => cancelExpenseRequestCore(db, {
        restaurantId,
        requestId: result.requestId,
        reason: "duplicado",
      }, {auth: {uid: "admin-uid"}}),
      /Se requiere App Check/,
    );
  });

  it("cancels and restores quota when policy allows restore", async () => {
    await setMode("live");
    await updatePolicy({restoreQuotaOnCancellation: true});
    const result = await submit(baseInput());
    const cancelled = await cancelExpenseRequestCore(db, {
      restaurantId,
      requestId: result.requestId,
      reason: "duplicado",
    }, adminContext());
    assert.equal(cancelled.restored, true);
  });

  it("double cancellation does not restore twice", async () => {
    await setMode("live");
    await updatePolicy({restoreQuotaOnCancellation: true});
    const result = await submit(baseInput());
    await cancelExpenseRequestCore(db, {restaurantId, requestId: result.requestId, reason: "x"}, adminContext());
    const second = await cancelExpenseRequestCore(db, {restaurantId, requestId: result.requestId, reason: "x"}, adminContext());
    assert.equal(second.restored, false);
  });

  it("manual override does not increment policy usage", async () => {
    await setMode("live");
    const result = await submit(baseInput({amount: 500}));
    await restaurant().collection("cashWithdrawalRequests").doc(result.requestId).update({
      status: "approved",
      approvedByEmployeeId: "admin",
    });
    const usage = await restaurant().collection("expensePolicyUsage").get();
    assert.equal(usage.empty, true);
  });

  it("writes activity log", async () => {
    await setMode("live");
    await submit(baseInput());
    const log = await restaurant().collection("activityLog").get();
    assert.equal(log.empty, false);
  });

  it("documents App Check protected callable path", () => {
    assert.ok(submitExpenseRequest);
    assert.ok(cancelExpenseRequest);
  });

  it("fails closed when config is missing", async () => {
    await restaurant().collection("settings").doc("expensePolicies").delete();
    const result = await submit(baseInput());
    assert.equal(result.status, "pending");
  });
});

function submit(input: Record<string, unknown>) {
  return submitExpenseRequestCore(db, input, deviceContext()) as Promise<Record<string, any>>;
}

function deviceContext() {
  return {auth: {uid}, app: {appId: "debug-app"}};
}

function adminContext() {
  return {auth: {uid: "admin-uid"}, app: {appId: "debug-app"}};
}

function baseInput(overrides: Record<string, unknown> = {}) {
  return {
    restaurantId,
    branchId,
    policyId: "hielo",
    amount: 40,
    supplierId: "",
    paymentSource: "cash",
    reason: "Hielo",
    requesterId: "emp-1",
    requesterName: "Empleado",
    requesterRole: "staff",
    businessDate: "2026-08-18",
    cashSessionId: "cash-1",
    clientRequestId: `req-${Math.random()}`,
    hasReceipt: true,
    ...overrides,
  };
}

async function seedBase() {
  await restaurant().collection("devices").doc(uid).set({
    restaurantId,
    branchId,
    active: true,
  });
  await restaurant().collection("authUsers").doc("admin-uid").set({
    active: true,
    isSuperAdmin: true,
  });
  await restaurant().collection("settings").doc("expensePolicies").set({
    expensePoliciesEnabled: false,
    expensePolicyMode: "off",
  });
  await restaurant().collection("cashSessions").doc("cash-1").set({
    id: "cash-1",
    restaurantId,
    branchId,
    businessDate: "2026-08-18",
    status: "open",
  });
  await restaurant().collection("expensePolicies").doc("hielo").set(policyData());
}

async function setMode(mode: string) {
  await restaurant().collection("settings").doc("expensePolicies").set({
    expensePolicyMode: mode,
    expensePoliciesEnabled: mode === "live",
  }, {merge: true});
}

async function updatePolicy(data: Record<string, unknown>) {
  await restaurant().collection("expensePolicies").doc("hielo").set(data, {merge: true});
}

function policyData() {
  return {
    restaurantId,
    branchId,
    name: "Hielo",
    code: "hielo",
    active: true,
    autoApproveEnabled: true,
    maxAmountPerTransaction: 100,
    maxAmountPerPeriod: 100,
    maxUsesPerPeriod: 5,
    frequencyType: "daily",
    frequencyValue: 1,
    receiptRequired: false,
    supplierRestrictionEnabled: false,
    allowedSupplierIds: [],
    allowedPaymentSources: ["cash"],
    requesterRoleRestrictions: [],
    requesterIds: [],
    policyVersion: 1,
  };
}

function restaurant() {
  return db.collection("restaurants").doc(restaurantId);
}

async function clearRestaurant() {
  await admin.firestore().recursiveDelete(restaurant());
}
