import {createHash} from "crypto";
import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";

type Data = Record<string, unknown>;
interface AuthContext { auth?: {uid: string}; app?: unknown }

const CANCELLED = new Set(["cancelled", "canceled", "cancelado", "cancelada", "voided", "anulado", "anulada"]);
const PAID = new Set(["paid", "pagado", "pagada", "closed", "cerrado", "cerrada"]);
const BATCHABLE = new Set(["sent", "cooking", "ready"]);

export async function submitLocalOrderCaptureCore(
  db: admin.firestore.Firestore,
  raw: Data,
  context: AuthContext,
) {
  if (!context.auth?.uid) throw new HttpsError("unauthenticated", "Inicia sesion nuevamente.");
  if (!context.app) throw new HttpsError("failed-precondition", "La app no pudo validar este envio.");
  const uid = context.auth.uid;
  const restaurantId = safeString(raw.restaurantId);
  const branchId = safeString(raw.branchId);
  const orderId = safeString(raw.orderId);
  const submissionId = safeString(raw.id);
  const payloadHash = safeString(raw.payloadHash);
  const payloadJson = safeString(raw.payloadJson);
  const sendToKitchen = raw.sendToKitchen === true;
  if (![restaurantId, branchId, orderId].every(isSafeId) || !isSafeId(submissionId)) {
    throw new HttpsError("invalid-argument", "La solicitud de envio es invalida.");
  }
  if (Buffer.byteLength(payloadJson, "utf8") > 700_000) throw new HttpsError("resource-exhausted", "El envio excede el tamano permitido; conserva el borrador y dividelo en una nueva comanda.");
  let lines: Data[];
  try {
    const parsed: unknown = JSON.parse(payloadJson);
    if (!Array.isArray(parsed) || parsed.some((entry) => !entry || typeof entry !== "object" || Array.isArray(entry))) throw new Error("payload");
    lines = parsed as Data[];
  } catch {
    throw new HttpsError("invalid-argument", "El borrador de envio esta danado.");
  }
  if (lines.length < 1 || lines.length > 350) throw new HttpsError("resource-exhausted", "El envio debe contener entre 1 y 350 renglones.");
  const actualHash = createHash("sha256").update(payloadJson).digest("hex");
  if (actualHash !== payloadHash) throw new HttpsError("invalid-argument", "El contenido del envio no coincide con su identificador.");
  const lineIds = lines.map((line) => safeString(line.id));
  if (new Set(lineIds).size !== lineIds.length || lineIds.some((id) => !isSafeId(id))) {
    throw new HttpsError("invalid-argument", "El envio contiene identificadores duplicados o invalidos.");
  }
  for (const line of lines) validateLineScope(line, {restaurantId, branchId, orderId});

  const restaurant = db.collection("restaurants").doc(restaurantId);
  const orderRef = restaurant.collection("orders").doc(orderId);
  const markerRef = restaurant.collection("activityLog").doc(`capture_submission_${submissionId}`);
  const deviceRef = restaurant.collection("devices").doc(uid);
  let transactionAttempts = 0;
  let totalReadDocuments = 0;
  let totalCollectionQueries = 0;
  const startedAt = Date.now();
  return db.runTransaction(async (tx) => {
    transactionAttempts++;
    const marker = await tx.get(markerRef);
    totalReadDocuments++;
    if (marker.exists) {
      const markerData = marker.data() ?? {};
      if (markerData.payloadHash !== payloadHash || markerData.orderId !== orderId || markerData.branchId !== branchId || markerData.sendToKitchen !== sendToKitchen) {
        throw new HttpsError("already-exists", "Este identificador ya fue utilizado con otro contenido.");
      }
      if (markerData.createdBy !== uid) throw new HttpsError("permission-denied", "Este envio pertenece a otro dispositivo.");
      return markerData.result;
    }

    const [deviceDoc, orderDoc, itemQuery, paymentQuery, cashSessionsQuery] = await Promise.all([
      tx.get(deviceRef),
      tx.get(orderRef),
      tx.get(orderRef.collection("items")),
      tx.get(orderRef.collection("payments")),
      tx.get(restaurant.collection("cashSessions").where("status", "==", "open")),
    ]);
    totalReadDocuments += 2 + itemQuery.size + paymentQuery.size + cashSessionsQuery.size;
    totalCollectionQueries += 3;
    if (!deviceDoc.exists) throw new HttpsError("permission-denied", "El dispositivo no esta registrado.");
    const device = deviceDoc.data() ?? {};
    if (device.active === false || device.restaurantId && device.restaurantId !== restaurantId || device.branchId !== branchId) {
      throw new HttpsError("permission-denied", "El dispositivo no tiene acceso a esta sucursal.");
    }
    const employeeId = safeString(device.employeeId);
    if (!employeeId) throw new HttpsError("permission-denied", "Inicia sesion nuevamente como mesero.");
    const employeeRef = restaurant.collection("employees").doc(employeeId);
    const employeeDoc = await tx.get(employeeRef);
    totalReadDocuments++;
    if (!employeeDoc.exists) throw new HttpsError("permission-denied", "El usuario ya no esta activo.");
    const employee = employeeDoc.data() ?? {};
    if (employee.active === false || !hasBranchOrderPermission(employee, branchId)) {
      throw new HttpsError("permission-denied", "No tienes permiso para levantar pedidos en esta sucursal.");
    }
    for (const line of lines) {
      if (line.deviceUid !== uid || line.employeeId !== employeeId) {
        throw new HttpsError("permission-denied", "El borrador pertenece a otra sesion.");
      }
    }
    if (!orderDoc.exists) throw new HttpsError("not-found", "La orden ya no existe. El borrador local se conserva.");
    const order = orderDoc.data() ?? {};
    if (order.restaurantId && order.restaurantId !== restaurantId || safeString(order.branchId || "aviacion") !== branchId) {
      throw new HttpsError("failed-precondition", "La orden pertenece a otra sucursal.");
    }
    if (!isActiveOrder(order)) throw new HttpsError("failed-precondition", "La orden esta pagada o cancelada. El borrador local se conserva para resolverlo.");

    const existingItemIds = new Set(itemQuery.docs.map((doc) => doc.id));
    if (lineIds.some((id) => existingItemIds.has(id))) {
      throw new HttpsError("already-exists", "Un articulo con este identificador ya existe y no coincide con un envio confirmado.");
    }
    const products = new Map<string, admin.firestore.DocumentSnapshot>();
    const productIds = [...new Set(lines.map((line) => safeString(line.productId)))];
    if (productIds.some((id) => !isSafeId(id))) throw new HttpsError("invalid-argument", "El borrador contiene un producto invalido.");
    for (const productId of productIds) {
      products.set(productId, await tx.get(restaurant.collection("products").doc(productId)));
    }
    totalReadDocuments += productIds.length;
    const activeCashSession = cashSessionsQuery.docs.find((doc) => {
      const data = doc.data();
      return safeString(data.branchId || "aviacion") === branchId;
    });
    const currentBusinessDate = safeString(activeCashSession?.data().businessDate) || dateKeyInMexico();
    const businessDate = safeString(order.businessDate || order.operationalDate) || currentBusinessDate;
    const stockoutRefs = new Map<string, admin.firestore.DocumentReference>();
    for (const line of lines) {
      const productId = safeString(line.productId);
      const productDoc = products.get(productId)!;
      if (!productDoc.exists) throw new HttpsError("failed-precondition", "Un producto ya no esta disponible; el borrador local se conserva.");
      validateProductSnapshot(line, productDoc.data() ?? {}, safeString(order.orderType) === "takeout" ? safeString(order.platformId) : "");
      const stockoutId = `${safeIdPart(branchId)}_${safeIdPart(currentBusinessDate)}_${safeIdPart(productId)}`;
      stockoutRefs.set(stockoutId, restaurant.collection("productStockOuts").doc(stockoutId));
    }
    const stockoutDocs = new Map<string, admin.firestore.DocumentSnapshot>();
    for (const [id, ref] of stockoutRefs) stockoutDocs.set(id, await tx.get(ref));
    totalReadDocuments += stockoutRefs.size;
    for (const line of lines) {
      const id = `${safeIdPart(branchId)}_${safeIdPart(currentBusinessDate)}_${safeIdPart(safeString(line.productId))}`;
      if (stockoutDocs.get(id)?.exists) throw new HttpsError("failed-precondition", "Un producto capturado se agoto antes del envio. El borrador local se conserva.");
    }

    const currentItems = itemQuery.docs.map((doc) => ({id: doc.id, data: doc.data()}));
    const currentPayments = paymentQuery.docs.map((doc) => doc.data());
    const newItemData = lines.map((line) => makeOrderItem(line, employeeId, safeString(employee.name), branchId, safeString(device.branchName)));
    const allForKitchen = [
      ...currentItems.map((item) => ({id: item.id, data: item.data})),
      ...lines.map((line, index) => ({id: lineIds[index], data: newItemData[index]})),
    ];
    const pendingKitchenItems = sendToKitchen ? allForKitchen.filter(({data}) => canSendToKitchen(data)) : [];
    const isExpress = currentItems.some(({data}) => {
      const status = normalize(data.kitchenStatus);
      return data.sendToKitchen === true && !isCancelledItem(data) && BATCHABLE.has(status) && !!safeString(data.kitchenBatchId);
    });
    const sentCount = pendingKitchenItems.length;
    const businessDateForBatch = businessDate;
    const sequenceRef = restaurant.collection("branches").doc(branchId).collection("kitchenDailySequences").doc(businessDateForBatch);
    const sequenceDoc = sentCount > 0 ? await tx.get(sequenceRef) : null;
    if (sequenceDoc) totalReadDocuments++;
    const tableIds = orderTableIds(order);
    const tableRefs = tableIds.map((id) => restaurant.collection("tables").doc(id));
    const tableDocs: admin.firestore.DocumentSnapshot[] = [];
    for (const ref of tableRefs) tableDocs.push(await tx.get(ref));
    totalReadDocuments += tableRefs.length;
    for (let index = 0; index < tableDocs.length; index++) {
      const data = tableDocs[index].data() ?? {};
      if (!tableDocs[index].exists) throw new HttpsError("failed-precondition", "Una mesa vinculada ya no existe. El borrador se conserva.");
      const owner = safeString(data.currentOrderId);
      if (tableDocs[index].exists && owner && owner !== orderId) {
        throw new HttpsError("failed-precondition", "Una mesa vinculada ahora pertenece a otra orden. El borrador se conserva.");
      }
      if (safeString(data.branchId || "aviacion") !== branchId) throw new HttpsError("failed-precondition", "Una mesa vinculada pertenece a otra sucursal.");
    }

    const newLineIds = new Set(lineIds);
    const existingPendingKitchenCount = pendingKitchenItems.filter(({id}) => !newLineIds.has(id)).length;
    const totalWrites = lines.length + existingPendingKitchenCount + (sentCount > 0 ? 2 : 0) + 1 + tableRefs.length + 1;
    if (totalWrites > 450) throw new HttpsError("resource-exhausted", "La orden excede el limite seguro de escrituras. El borrador local se conserva; solicita dividir la comanda.");
    const newTotals = computeOrderAggregates(currentItems.map((item) => item.data).concat(newItemData), currentPayments);
    const sequence = sequenceDoc ? Number(sequenceDoc.data()?.lastSequence ?? 0) + 1 : 1;
    const batchId = sentCount > 0 ? orderRef.collection("kitchenBatches").doc().id : "";
    const batchType = isExpress ? "express" : "initial";
    const batchLabel = isExpress ? "Orden extra" : "Orden inicial";
    const now = admin.firestore.Timestamp.now();

    if (sentCount > 0) {
      for (let index = 0; index < newItemData.length; index++) {
        if (canSendToKitchen(newItemData[index])) {
          Object.assign(newItemData[index], sentKitchenFields({
            batchId,
            batchCreatedAt: now,
            isExpress,
            batchType,
            batchLabel,
            kitchenSequence: sequence,
          }));
        }
      }
    }

    // No writes occur before every validation/query above has completed.
    lines.forEach((line, index) => {
      const itemData = newItemData[index];
      tx.create(orderRef.collection("items").doc(lineIds[index]), {
        ...itemData,
        createdAt: admin.firestore.Timestamp.fromMillis(now.toMillis() + index),
        updatedAt: now,
      });
    });
    if (sentCount > 0) {
      tx.set(sequenceRef, {
        restaurantId,
        branchId,
        businessDate: businessDateForBatch,
        lastSequence: sequence,
        updatedAt: now,
      }, {merge: true});
      tx.create(orderRef.collection("kitchenBatches").doc(batchId), {
        restaurantId,
        restaurantName: safeString(order.restaurantName),
        branchId,
        branchName: safeString(order.branchName),
        orderId,
        businessDate: businessDateForBatch,
        kitchenSequence: sequence,
        status: "sent",
        type: batchType,
        label: batchLabel,
        itemCount: sentCount,
        createdAt: now,
        updatedAt: now,
        createdByEmployeeId: employeeId,
        createdByEmployeeName: safeString(employee.name),
      });
      for (const item of pendingKitchenItems) {
        if (newLineIds.has(item.id)) continue;
        tx.update(orderRef.collection("items").doc(item.id), {
          ...sentKitchenFields({batchId, batchCreatedAt: now, isExpress, batchType, batchLabel, kitchenSequence: sequence}),
          updatedAt: now,
        });
      }
    }
    const orderUpdate: Data = {
      ...newTotals,
      captureRevision: admin.firestore.FieldValue.increment(1),
      updatedAt: now,
    };
    if (sentCount > 0) {
      orderUpdate.status = "sent";
      orderUpdate.kitchenStatus = "sent";
      orderUpdate.lastKitchenBatchId = batchId;
      orderUpdate.lastKitchenBatchType = batchType;
      orderUpdate.lastKitchenBatchLabel = batchLabel;
      if (!order.sentToKitchenAt) orderUpdate.sentToKitchenAt = now;
      orderUpdate.lastSentToKitchenAt = now;
    }
    tx.update(orderRef, orderUpdate);
    for (const ref of tableRefs) {
      tx.set(ref, {
        status: "occupied",
        currentOrderId: orderId,
        currentOrderStatus: sentCount > 0 ? "sent" : safeString(order.status),
        restaurantId,
        restaurantName: safeString(order.restaurantName),
        branchId,
        branchName: safeString(order.branchName),
        updatedAt: now,
      }, {merge: true});
    }
    const result = {
      submissionId,
      payloadHash,
      sendToKitchen,
      acceptedLineCount: lines.length,
      acceptedQty: lines.reduce((total, line) => total + Number(line.qty), 0),
      sentCount,
      kitchenBatchId: batchId || null,
      transactionAttempts,
      collectionQueries: totalCollectionQueries,
      readDocuments: totalReadDocuments,
      writeOperations: totalWrites,
      serverElapsedMs: Date.now() - startedAt,
    };
    tx.create(markerRef, {
      type: "local_order_capture_submitted",
      status: "confirmed",
      restaurantId,
      restaurantName: safeString(order.restaurantName),
      branchId,
      branchName: safeString(order.branchName),
      orderId,
      submissionId,
      payloadHash,
      sendToKitchen,
      acceptedLineCount: lines.length,
      acceptedQty: result.acceptedQty,
      kitchenBatchId: batchId || null,
      createdBy: uid,
      createdByEmployeeId: employeeId,
      createdByEmployeeName: safeString(employee.name),
      createdAt: now,
      result,
    });
    return result;
  });
}

function validateLineScope(line: Data, scope: {restaurantId: string; branchId: string; orderId: string}) {
  if (line.schemaVersion !== 1 || line.restaurantId !== scope.restaurantId || line.branchId !== scope.branchId || line.orderId !== scope.orderId) {
    throw new HttpsError("invalid-argument", "Un articulo del borrador tiene un contexto diferente.");
  }
  const qty = Number(line.qty);
  const price = Number(line.unitPrice);
  if (!Number.isSafeInteger(qty) || qty < 1 || qty > 1000 || !Number.isFinite(price) || price < 0 || price > 1_000_000) {
    throw new HttpsError("invalid-argument", "Un articulo tiene cantidad o precio invalido.");
  }
  const personNumber = Number(line.personNumber);
  if (!Number.isSafeInteger(personNumber) || personNumber < 1) {
    throw new HttpsError("invalid-argument", "El borrador tiene una persona invalida.");
  }
  for (const key of ["productId", "productName", "categoryName", "deviceUid", "employeeId"]) {
    if (!safeString(line[key])) throw new HttpsError("invalid-argument", `Falta ${key} en el borrador.`);
  }
}

function validateProductSnapshot(line: Data, product: Data, platformId: string) {
  if (product.active === false) throw new HttpsError("failed-precondition", "Un producto fue desactivado. El borrador local se conserva.");
  const basePrice = parseNumber(product.price);
  const platformPrices = product.platformPrices && typeof product.platformPrices === "object" ? product.platformPrices as Data : {};
  const effective = platformId && platformPrices[platformId] != null ? parseNumber(platformPrices[platformId]) : basePrice;
  if (Math.abs(effective - numberValue(line.unitPrice)) > 0.000001) {
    throw new HttpsError("failed-precondition", "El precio del menu cambio. El borrador se conserva para confirmar el nuevo precio.");
  }
  if (safeString(product.name) !== safeString(line.productName)) throw new HttpsError("failed-precondition", "El nombre del producto cambio. Actualiza el menu antes de enviar.");
  const category = safeString(product.categoryName || product.category || "General");
  if (category !== safeString(line.categoryName)) throw new HttpsError("failed-precondition", "La categoria del producto cambio. Actualiza el menu antes de enviar.");
  const sendToKitchen = readBool(product.sendToKitchen, category.toLowerCase().trim() !== "bebidas");
  if (sendToKitchen !== (line.sendToKitchen === true)) throw new HttpsError("failed-precondition", "La preparacion del producto cambio. El borrador se conserva.");
  const liveRecipe = normalizedProductRecipe(product).slice(0, 1);
  const capturedRecipe = Array.isArray(line.recipeItems) ? line.recipeItems : [];
  if (JSON.stringify(liveRecipe) !== JSON.stringify(capturedRecipe)) {
    throw new HttpsError("failed-precondition", "La receta del producto cambio. El borrador se conserva para revisarlo.");
  }
  const name = safeString(product.name).toLowerCase().trim();
  const normalizedCategory = category.toLowerCase().trim();
  const defaultStock = normalizedCategory === "tacos" || name.includes("taco") || name.includes("gringa") || normalizedCategory === "bebidas" || name.includes("refresco");
  const affectsStock = readBool(product.affectsKitchenStock, defaultStock) || liveRecipe.length > 0;
  if (affectsStock !== (line.affectsKitchenStock === true)) {
    throw new HttpsError("failed-precondition", "La configuracion de inventario del producto cambio. El borrador se conserva.");
  }
}

function normalizedProductRecipe(product: Data) {
  const result: Data[] = [];
  if (Array.isArray(product.recipeItems)) {
    for (const value of product.recipeItems) {
      if (!value || typeof value !== "object") continue;
      const item = value as Data;
      const id = safeString(item.kitchenStockItemId);
      const factor = parseNumber(item.consumptionFactor);
      if (!id || factor <= 0) continue;
      result.push({
        kitchenStockItemId: id,
        kitchenStockItemName: safeString(item.kitchenStockItemName) || id,
        kitchenStockUnit: safeString(item.kitchenStockUnit) || "kg",
        consumptionFactor: factor,
      });
    }
  }
  if (result.length > 0) return result;
  const legacyId = safeString(product.kitchenStockItemId);
  if (!legacyId) return result;
  const factor = parseNumber(product.stockConsumptionQty ?? product.kitchenConsumptionFactor);
  result.push({
    kitchenStockItemId: legacyId,
    kitchenStockItemName: safeString(product.kitchenStockItemName) || legacyId,
    kitchenStockUnit: safeString(product.kitchenStockUnit) || "kg",
    consumptionFactor: factor > 0 ? factor : 1,
  });
  return result;
}

function makeOrderItem(line: Data, employeeId: string, employeeName: string, branchId: string, branchName: string): Data {
  const qty = Number(line.qty);
  const unitPrice = Number(line.unitPrice);
  const sendToKitchen = line.sendToKitchen === true;
  const recipeItems = Array.isArray(line.recipeItems) ? line.recipeItems : [];
  return {
    personNumber: Number(line.personNumber),
    personName: safeString(line.personName),
    productId: safeString(line.productId),
    productName: safeString(line.productName),
    categoryId: safeString(line.categoryId),
    categoryName: safeString(line.categoryName),
    category: safeString(line.categoryName),
    qty,
    unitPrice,
    total: qty * unitPrice,
    appliedPlatformId: line.appliedPlatformId || null,
    appliedPlatformName: line.appliedPlatformName || null,
    priceSource: safeString(line.priceSource) || "store",
    notes: safeString(line.notes),
    restaurantId: safeString(line.restaurantId),
    restaurantName: safeString(line.restaurantName),
    branchId,
    branchName,
    createdByEmployeeId: employeeId,
    createdByEmployeeName: employeeName,
    sendToKitchen,
    affectsKitchenStock: line.affectsKitchenStock === true,
    recipeItems,
    kitchenStockItemId: line.kitchenStockItemId || null,
    kitchenStockItemName: line.kitchenStockItemName || null,
    kitchenStockUnit: line.kitchenStockUnit || null,
    stockConsumptionQty: line.stockConsumptionQty ?? null,
    kitchenConsumptionFactor: line.stockConsumptionQty ?? null,
    kitchenStatus: sendToKitchen ? "pending" : "not_required",
    kitchenBatchId: null,
    paymentStatus: "pending",
    status: "active",
    cancelStatus: "none",
  };
}

export function computeOrderAggregates(items: Data[], payments: Data[]) {
  const activeItems = items.filter((item) => Number(item.qty) > 0 && !isCancelledItem(item));
  const total = money(activeItems.reduce((sum, item) => sum + numberValue(item.total, Number(item.qty) * numberValue(item.unitPrice)), 0));
  let grossCovered = 0;
  let monetaryPaid = 0;
  let discountAmount = 0;
  for (const rawPayment of payments) {
    const payment = normalizedPayment(rawPayment);
    if (!canonicalActivePayment(payment)) continue;
    const base = numberValue(payment.baseAmount, numberValue(payment.amount));
    const discount = paymentDiscount(payment, base);
    grossCovered += base;
    monetaryPaid += paymentMonetary(payment, base, discount);
    discountAmount += discount;
  }
  grossCovered = money(Math.min(total, Math.max(0, grossCovered)));
  discountAmount = money(Math.min(total, Math.max(0, discountAmount)));
  monetaryPaid = money(monetaryPaid);
  const totalLiquidated = money(monetaryPaid + discountAmount);
  const paidTotal = totalLiquidated > 0 ? Math.min(total, Math.max(0, totalLiquidated)) : grossCovered;
  const pendingTotal = money(Math.max(0, total - paidTotal));
  const netTotal = money(Math.max(0, total - discountAmount));
  return {
    total,
    grossSubtotal: total,
    netTotal,
    discountAmount,
    totalDiscountAmount: discountAmount,
    monetaryPaid,
    totalLiquidated,
    paidTotal,
    pendingTotal,
    paymentStatus: paidTotal <= 0.01 ? "pending" : pendingTotal <= 0.01 ? "paid" : "partial",
  };
}

function canonicalActivePayment(payment: Data) {
  const status = normalize(payment.status || "active");
  return !CANCELLED.has(status) && payment.cancelledAt == null &&
    (paymentMonetary(payment, numberValue(payment.baseAmount, numberValue(payment.amount)), paymentDiscount(payment, numberValue(payment.baseAmount, numberValue(payment.amount)))) > 0 ||
      numberValue(payment.discountAmount) > 0 || numberValue(payment.baseAmount, numberValue(payment.amount)) > 0);
}

function normalizedPayment(data: Data): Data {
  const rawBaseAmount = readMoney(data.baseAmount);
  const baseAmount = rawBaseAmount > 0 ? rawBaseAmount : readMoney(data.subtotalBeforeDiscount);
  const surchargeAmount = readMoney(data.surchargeAmount);
  const method = safeString(data.method) || "cash";
  const chargedAmount = readMoney(data.chargedAmount);
  const cardFeeAbsorbedAmount = numberValue(
    readMoney(data.cardFeeAbsorbedAmount),
    method === "card" && surchargeAmount > 0 ? surchargeAmount : 0,
  );
  return {
    ...data,
    baseAmount,
    surchargeAmount,
    method,
    chargedAmount,
    cardFeeAbsorbedAmount,
    subtotalBeforeDiscount: readMoney(data.subtotalBeforeDiscount),
    totalAfterDiscount: readMoney(data.totalAfterDiscount),
    tipAmount: firstPositiveMoney(data, ["tipAmount", "tip", "tips", "propina", "gratuity", "employeeTip"]),
    status: safeString(data.status) || "active",
    type: safeString(data.type) || "full_table",
    discountAmount: readMoney(data.discountAmount),
    appliedDiscountPercent: readMoney(data.appliedDiscountPercent),
    discountPercent: readMoney(data.discountPercent),
    orderGrossSubtotal: readMoney(data.orderGrossSubtotal),
    orderNetTotal: readMoney(data.orderNetTotal),
  };
}

function paymentDiscount(payment: Data, base: number) {
  if (isFreeMeal(payment) && base > 0) return money(base);
  const explicit = Math.max(0, readMoney(payment.discountAmount));
  if (explicit > 0) return money(explicit);
  const percent = readMoney(payment.appliedDiscountPercent) > 0 ? readMoney(payment.appliedDiscountPercent) : readMoney(payment.discountPercent);
  if (percent <= 0 || base <= 0) return 0;
  const normalized = percent > 1 ? percent / 100 : percent;
  return money(Math.min(base, Math.max(0, base * normalized)));
}

function paymentMonetary(payment: Data, base: number, discount: number) {
  if (isFreeMeal(payment)) return 0;
  // Keep this data-path equivalent to PaymentSettlementInput.fromPaymentData
  // and _paymentDataMonetaryAppliedToSale in order_payment_reconciliation.dart.
  if (Object.prototype.hasOwnProperty.call(payment, "appliedAmount")) {
    return money(Math.max(0, readMoney(payment.appliedAmount)));
  }
  const baseNet = base > 0 ? Math.max(0, base - discount) : 0;
  if (baseNet > 0 || discount > 0) return money(baseNet);
  const tip = firstPositiveMoney(payment, ["tipAmount", "tip", "tips", "propina", "gratuity", "employeeTip"]);
  const fee = readMoney(payment.cardFeeAbsorbedAmount) > 0
    ? readMoney(payment.cardFeeAbsorbedAmount)
    : readMoney(payment.surchargeAmount);
  const afterDiscount = readMoney(payment.totalAfterDiscount);
  if (afterDiscount > 0) return money(Math.max(0, afterDiscount - tip));
  return money(Math.max(0, readMoney(payment.chargedAmount) - tip - fee));
}

function isFreeMeal(payment: Data) {
  const value = [payment.appliedDiscountType, payment.appliedDiscountName, payment.discountSource, payment.discountCatalogId, payment.discountName]
    .filter((entry) => typeof entry === "string").join(" ").toLowerCase();
  return ["employee_free_meal", "free_meal", "free meal", "comida empleado", "comida de empleado"].some((part) => value.includes(part));
}

function isCancelledItem(item: Data) {
  return [item.status, item.kitchenStatus, item.cancelStatus].some((value) => CANCELLED.has(normalize(value))) ||
    normalize(item.cancelStatus) === "accepted" || item.cancelledAt != null || item.cancelAcceptedAt != null;
}

function canSendToKitchen(item: Data) {
  if (isCancelledItem(item) || Number(item.qty) <= 0 || item.sendToKitchen !== true || normalize(item.paymentStatus || "pending") !== "pending") return false;
  const category = normalize(item.categoryName || item.category).replace(/[\s-]+/g, "_");
  if (["bebida", "bebidas", "drink", "drinks", "bar"].includes(category)) return false;
  const status = normalize(item.kitchenStatus || "pending");
  const batchId = safeString(item.kitchenBatchId);
  return (status === "pending" || status === "pendiente") && item.sentToKitchenAt == null && !batchId;
}

function isActiveOrder(order: Data) {
  const status = normalize(order.status);
  const kitchenStatus = normalize(order.kitchenStatus);
  const paymentStatus = normalize(order.paymentStatus);
  if ([status, kitchenStatus, paymentStatus].some((value) => CANCELLED.has(value)) || order.cancelledAt != null || order.canceledAt != null) return false;
  const pending = numberValue(order.pendingTotal);
  const paidAt = order.paidAt != null;
  return !PAID.has(status) && !PAID.has(paymentStatus) && order.closedAt == null && !(paidAt && Math.abs(pending) <= 0.02);
}

function hasBranchOrderPermission(employee: Data, branchId: string) {
  if (employee.isSuperAdmin === true || safeString(employee.id).toLowerCase() === "admin") return true;
  const accesses = Array.isArray(employee.branchAccess) ? employee.branchAccess as Data[] : [];
  const active = accesses.filter((entry) => entry.active !== false && entry.branchId === branchId);
  if (accesses.length > 0) {
    const selected = active[0];
    if (!selected) return false;
    const permissions = selected.permissions && typeof selected.permissions === "object" ? selected.permissions as Data : {};
    return typeof permissions.canTakeOrders === "boolean" ? permissions.canTakeOrders : employee.canTakeOrders === true;
  }
  return employee.canTakeOrders === true;
}

function orderTableIds(order: Data) {
  if (order.orderType !== "dine_in" && order.orderType !== "table") return [];
  if (Array.isArray(order.tableIds) && order.tableIds.length > 0) return [...new Set(order.tableIds.map((id) => safeString(id)).filter(isSafeId))];
  return isSafeId(safeString(order.tableId)) ? [safeString(order.tableId)] : [];
}

function normalize(value: unknown) { return safeString(value).toLowerCase().trim().normalize("NFD").replace(/[\u0300-\u036f]/g, ""); }
function safeString(value: unknown) { return typeof value === "string" ? value.trim() : ""; }
function numberValue(value: unknown, fallback = 0) { return typeof value === "number" && Number.isFinite(value) ? value : fallback; }
function readMoney(value: unknown) {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  if (typeof value === "string") return Number.parseFloat(value.trim().replace(/,/g, "")) || 0;
  return 0;
}
function parseNumber(value: unknown) { if (typeof value === "number") return Number.isFinite(value) ? value : 0; if (typeof value === "string") return Number.parseFloat(value.trim().replace(",", ".")) || 0; return 0; }
function readBool(value: unknown, fallback: boolean) {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return value !== 0;
  if (typeof value === "string") {
    const clean = value.toLowerCase().trim();
    if (["true", "1", "yes", "si"].includes(clean)) return true;
    if (["false", "0", "no"].includes(clean)) return false;
  }
  return fallback;
}
function firstPositiveMoney(data: Data, keys: string[]) { for (const key of keys) { const value = readMoney(data[key]); if (value > 0) return value; } return 0; }
function money(value: number) { return Math.round(value * 100) / 100; }
function isSafeId(value: string) { return value.length > 0 && value.length <= 140 && !value.includes("/"); }
function safeIdPart(value: string) { return value.trim().replace(/[^a-zA-Z0-9_-]+/g, "_").replace(/_+/g, "_"); }
function dateKeyInMexico() { return new Intl.DateTimeFormat("en-CA", {timeZone: "America/Mexico_City", year: "numeric", month: "2-digit", day: "2-digit"}).format(new Date()); }

function sentKitchenFields(input: {batchId: string; batchCreatedAt: admin.firestore.Timestamp; isExpress: boolean; batchType: string; batchLabel: string; kitchenSequence: number}): Data {
  return {
    kitchenStatus: "sent",
    kitchenBatchId: input.batchId,
    kitchenBatchCreatedAt: input.batchCreatedAt,
    batchCreatedAt: input.batchCreatedAt,
    isKitchenExpress: input.isExpress,
    expressReason: input.isExpress ? "Orden extra" : "",
    expressPriority: input.isExpress,
    ...(input.isExpress ? {expressCreatedAt: input.batchCreatedAt} : {}),
    kitchenBatchType: input.batchType,
    kitchenBatchLabel: input.batchLabel,
    kitchenSequence: input.kitchenSequence,
    sentToKitchenAt: input.batchCreatedAt,
  };
}
