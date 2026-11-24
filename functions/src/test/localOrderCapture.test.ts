import * as assert from "assert";
import {createHash} from "crypto";
import * as admin from "firebase-admin";
import {submitLocalOrderCaptureCore} from "../index";

const db = admin.firestore();
const restaurantId = "local-capture-test";
const branchId = "branch-a";
const orderId = "order-a";
const uid = "device-a";
const employeeId = "waiter-a";
const root = db.collection("restaurants").doc(restaurantId);

describe("submitLocalOrderCapture transaction", () => {
  beforeEach(async () => {
    await db.recursiveDelete(root);
    await seedBase();
  });

  it("writes item, totals, batch, and marker atomically", async () => {
    await root.collection("products").doc("taco").update({price: 12});
    const request = requestFor("submission-a", [line("line-a", 3, 12)]);
    const result = await submitLocalOrderCaptureCore(db, request, context()) as Record<string, unknown>;
    const order = await root.collection("orders").doc(orderId).get();
    const items = await root.collection("orders").doc(orderId).collection("items").get();
    const batches = await root.collection("orders").doc(orderId).collection("kitchenBatches").get();
    const marker = await root.collection("activityLog").doc("capture_submission_submission-a").get();
    assert.equal(result.acceptedQty, 3);
    assert.equal(result.sentCount, 1);
    assert.equal(order.data()?.total, 36);
    assert.equal(order.data()?.pendingTotal, 36);
    assert.equal(order.data()?.status, "sent");
    assert.equal(items.size, 1);
    assert.equal(items.docs[0].data().qty, 3);
    assert.equal(items.docs[0].data().kitchenStatus, "sent");
    assert.equal(batches.size, 1);
    assert.equal(marker.exists, true);
  });

  it("same submission retry does not duplicate quantity or batch", async () => {
    await root.collection("products").doc("taco").update({price: 9});
    const request = requestFor("submission-retry", [line("line-retry", 2, 9)]);
    const first = await submitLocalOrderCaptureCore(db, request, context()) as Record<string, unknown>;
    let second: Record<string, unknown> = {};
    for (let retry = 0; retry < 10; retry++) {
      second = await submitLocalOrderCaptureCore(db, request, context()) as Record<string, unknown>;
      assert.deepEqual(second, first);
    }
    const items = await root.collection("orders").doc(orderId).collection("items").get();
    const batches = await root.collection("orders").doc(orderId).collection("kitchenBatches").get();
    assert.deepEqual(second, first);
    assert.equal(items.size, 1);
    assert.equal(items.docs[0].data().qty, 2);
    assert.equal(batches.size, 1);
    assert.equal((await root.collection("activityLog").doc("capture_submission_submission-retry").get()).data()?.sendToKitchen, true);
  });

  it("confirms products that do not require kitchen without creating a kitchen batch", async () => {
    await root.collection("products").doc("soda").set({
      name: "Agua", categoryName: "Bebidas", active: true, sendToKitchen: false,
      affectsKitchenStock: false, price: 8,
    });
    const sodaLine = {
      ...line("line-soda", 2, 8), productId: "soda", productName: "Agua",
      categoryName: "Bebidas", sendToKitchen: false,
    };
    const result = await submitLocalOrderCaptureCore(
      db,
      requestFor("submission-soda", [sodaLine], false),
      context(),
    ) as Record<string, unknown>;
    const item = (await root.collection("orders").doc(orderId).collection("items").doc("line-soda").get()).data()!;
    const batches = await root.collection("orders").doc(orderId).collection("kitchenBatches").get();
    assert.equal(result.acceptedQty, 2);
    assert.equal(result.sentCount, 0);
    assert.equal(result.collectionQueries, 3);
    assert.equal(item.kitchenStatus, "not_required");
    assert.equal(item.sendToKitchen, false);
    assert.equal(batches.size, 0);
    assert.equal((await root.collection("orders").doc(orderId).get()).data()?.total, 16);
  });

  it("preserves a prior partial payment while atomically recalculating the balance", async () => {
    await root.collection("orders").doc(orderId).update({total: 10, grossSubtotal: 10, netTotal: 10, pendingTotal: 10});
    await root.collection("orders").doc(orderId).collection("items").doc("old-item").set({
      qty: 1, unitPrice: 10, total: 10, status: "active", kitchenStatus: "sent", cancelStatus: "none",
    });
    await root.collection("orders").doc(orderId).collection("payments").doc("payment-a").set({
      status: "active", method: "cash", baseAmount: 5, appliedAmount: 5, totalAfterDiscount: 5,
    });
    const result = await submitLocalOrderCaptureCore(db, requestFor("submission-partial", [line("line-partial", 1, 10)]), context()) as Record<string, unknown>;
    const order = (await root.collection("orders").doc(orderId).get()).data()!;
    assert.equal(result.acceptedQty, 1);
    assert.equal(order.total, 20);
    assert.equal(order.paidTotal, 5);
    assert.equal(order.pendingTotal, 15);
    assert.equal(order.paymentStatus, "partial");
  });

  it("serializes two meseros submitting to the same order without overwriting either", async () => {
    const first = requestFor("submission-concurrent-a", [line("line-concurrent-a", 2, 10)]);
    const second = requestFor("submission-concurrent-b", [line("line-concurrent-b", 3, 10)]);
    await Promise.all([
      submitLocalOrderCaptureCore(db, first, context()),
      submitLocalOrderCaptureCore(db, second, context()),
    ]);
    const orderRef = root.collection("orders").doc(orderId);
    const [order, items, batches, sequence] = await Promise.all([
      orderRef.get(), orderRef.collection("items").get(), orderRef.collection("kitchenBatches").get(),
      root.collection("branches").doc(branchId).collection("kitchenDailySequences").doc("2026-11-23").get(),
    ]);
    assert.equal(items.size, 2);
    assert.equal(items.docs.reduce((sum, doc) => sum + Number(doc.data().qty), 0), 5);
    assert.equal(order.data()?.total, 50);
    assert.equal(batches.size, 2);
    assert.equal(sequence.data()?.lastSequence, 2);
    assert.equal(batches.docs.some((doc) => doc.data().type === "express"), true);
  });

  it("rejects reusing submission id with different payload", async () => {
    await submitLocalOrderCaptureCore(db, requestFor("submission-reuse", [line("line-a", 1, 10)]), context());
    await assert.rejects(
      () => submitLocalOrderCaptureCore(db, requestFor("submission-reuse", [line("line-b", 2, 10)]), context()),
      /already-exists|otro contenido/i,
    );
  });

  it("rejects terminal orders without writing", async () => {
    await root.collection("orders").doc(orderId).update({status: "paid", paymentStatus: "paid", pendingTotal: 0});
    await assert.rejects(
      () => submitLocalOrderCaptureCore(db, requestFor("submission-terminal", [line("line-terminal", 1, 10)]), context()),
      /failed-precondition|pagada o cancelada/i,
    );
    assert.equal((await root.collection("orders").doc(orderId).collection("items").get()).size, 0);
    assert.equal((await root.collection("activityLog").doc("capture_submission_submission-terminal").get()).exists, false);
  });

  it("rejects a changed price and preserves the draft", async () => {
    await root.collection("products").doc("taco").update({price: 15});
    await assert.rejects(
      () => submitLocalOrderCaptureCore(db, requestFor("submission-price", [line("line-price", 1, 10)]), context()),
      /failed-precondition|precio.*cambio/i,
    );
    assert.equal((await root.collection("orders").doc(orderId).collection("items").get()).size, 0);
  });

  it("rejects a UTF-8 payload over the safe request size before any write", async () => {
    const oversized = {...line("line-large", 1, 10), notes: "ñ".repeat(350_001)};
    await assert.rejects(
      () => submitLocalOrderCaptureCore(db, requestFor("submission-large", [oversized]), context()),
      /resource-exhausted|tamano permitido/i,
    );
    assert.equal((await root.collection("orders").doc(orderId).collection("items").get()).size, 0);
    assert.equal((await root.collection("activityLog").doc("capture_submission_submission-large").get()).exists, false);
  });

  it("rejects device branch mismatch", async () => {
    await root.collection("devices").doc(uid).update({branchId: "branch-b"});
    await assert.rejects(
      () => submitLocalOrderCaptureCore(db, requestFor("submission-branch", [line("line-branch", 1, 10)]), context()),
      /permission-denied|sucursal/i,
    );
  });
});

async function seedBase() {
  await root.collection("devices").doc(uid).set({active: true, restaurantId, branchId, branchName: "Sucursal A", employeeId});
  await root.collection("employees").doc(employeeId).set({name: "Mesero", active: true, canTakeOrders: true});
  await root.collection("products").doc("taco").set({name: "Taco", categoryName: "Tacos", active: true, sendToKitchen: true, affectsKitchenStock: false, price: 10});
  await root.collection("branches").doc(branchId).set({name: "Sucursal A"});
  await root.collection("tables").doc("table-a").set({name: "Mesa 1", status: "occupied", currentOrderId: orderId, branchId});
  await root.collection("orders").doc(orderId).set({
    restaurantId, restaurantName: "Restaurante", branchId, branchName: "Sucursal A",
    tableId: "table-a", tableName: "Mesa 1", tableIds: ["table-a"], orderType: "dine_in",
    status: "open", kitchenStatus: "pending", paymentStatus: "pending", total: 0,
    grossSubtotal: 0, netTotal: 0, paidTotal: 0, pendingTotal: 0, captureRevision: 0,
    businessDate: "2026-11-23",
  });
}

function line(id: string, qty: number, unitPrice: number) {
  return {
    schemaVersion: 1, id, restaurantId, restaurantName: "Restaurante", branchId,
    branchName: "Sucursal A", orderId, tableId: "table-a", tableName: "Mesa 1",
    tableIds: ["table-a"], tableNames: ["Mesa 1"], tableGroupLabel: "",
    deviceUid: uid, employeeId, employeeName: "Mesero", personNumber: 1,
    personName: "Persona 1", productId: "taco", productName: "Taco",
    categoryId: "tacos", categoryName: "Tacos", qty, unitPrice, notes: "",
    sendToKitchen: true, affectsKitchenStock: false, kitchenStockItemId: null,
    kitchenStockItemName: null, kitchenStockUnit: null, stockConsumptionQty: null,
    recipeItems: [], appliedPlatformId: null, appliedPlatformName: null,
    priceSource: "store", capturedAtMicros: 1_795_411_200_000_000,
  };
}

function requestFor(id: string, lines: Array<Record<string, unknown>>, sendToKitchen = true) {
  const payloadJson = JSON.stringify(lines);
  return {id, restaurantId, branchId, orderId, sendToKitchen, payloadJson,
    payloadHash: createHash("sha256").update(payloadJson).digest("hex")};
}

function context() { return {auth: {uid}, app: {appId: "emulator"}}; }
