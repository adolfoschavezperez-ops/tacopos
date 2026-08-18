import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";

admin.initializeApp();

const db = admin.firestore();
const region = "us-central1";

type Mode = "off" | "shadow" | "live";
type SubmitStatus = "approved" | "pending";

interface CallableAuth {
  uid: string;
}

interface CallableContext {
  auth?: CallableAuth;
  app?: unknown;
}

interface SubmitExpenseData {
  restaurantId?: unknown;
  branchId?: unknown;
  policyId?: unknown;
  amount?: unknown;
  supplierId?: unknown;
  paymentSource?: unknown;
  reason?: unknown;
  additionalNotes?: unknown;
  requesterId?: unknown;
  requesterName?: unknown;
  requesterRole?: unknown;
  businessDate?: unknown;
  cashSessionId?: unknown;
  clientRequestId?: unknown;
  hasReceipt?: unknown;
  receiptReference?: unknown;
}

interface CancelExpenseData {
  restaurantId?: unknown;
  requestId?: unknown;
  reason?: unknown;
}

interface Policy {
  id: string;
  restaurantId: string;
  branchId: string;
  name: string;
  code: string;
  active: boolean;
  autoApproveEnabled: boolean;
  maxAmountPerTransaction: number;
  maxAmountPerPeriod: number;
  maxUsesPerPeriod: number;
  frequencyType: string;
  frequencyValue: number;
  allowedWeekdays: number[];
  periodResetWeekday: number;
  receiptRequired: boolean;
  supplierRestrictionEnabled: boolean;
  allowedSupplierIds: string[];
  allowedPaymentSources: string[];
  requesterRoleRestrictions: string[];
  requesterIds: string[];
  allowedStartTime: string;
  allowedEndTime: string;
  validFrom: string;
  validUntil: string;
  restoreQuotaOnCancellation: boolean;
  requireReason: boolean;
  allowFreeConcept: boolean;
  policyVersion: number;
}

interface Usage {
  amountUsed: number;
  usesUsed: number;
  expenseIds: string[];
}

interface Decision {
  approved: boolean;
  reasonCode: string;
  message: string;
  periodKey: string;
}

export const submitExpenseRequest = onCall(
  {
    region,
    enforceAppCheck: true,
    consumeAppCheckToken: true,
  },
  async (request) => submitExpenseRequestCore(db, request.data, request),
);

export const cancelExpenseRequest = onCall(
  {
    region,
    enforceAppCheck: true,
    consumeAppCheckToken: true,
  },
  async (request) => cancelExpenseRequestCore(db, request.data, request),
);

export async function submitExpenseRequestCore(
  firestore: admin.firestore.Firestore,
  raw: SubmitExpenseData,
  context: CallableContext,
) {
  requireAuth(context);
  const uid = context.auth!.uid;
  const input = parseSubmitInput(raw);
  rejectForgedFields(raw);

  const restaurantRef = firestore.collection("restaurants").doc(input.restaurantId);
  const deviceRef = restaurantRef.collection("devices").doc(uid);
  const settingsRef = restaurantRef.collection("settings").doc("expensePolicies");
  const policyRef = restaurantRef.collection("expensePolicies").doc(input.policyId);
  const sessionRef = restaurantRef.collection("cashSessions").doc(input.cashSessionId);
  const expenseRef = restaurantRef.collection("cashWithdrawalRequests").doc();
  const idempotencyRef = restaurantRef
    .collection("expenseRequestIdempotency")
    .doc(input.clientRequestId);

  return firestore.runTransaction(async (tx) => {
    const existingIdempotency = await tx.get(idempotencyRef);
    if (existingIdempotency.exists) {
      return existingIdempotency.data()?.result;
    }

    const [deviceDoc, settingsDoc, policyDoc, sessionDoc] = await Promise.all([
      tx.get(deviceRef),
      tx.get(settingsRef),
      tx.get(policyRef),
      tx.get(sessionRef),
    ]);

    validateDevice(deviceDoc, input.restaurantId, input.branchId);
    if (!sessionDoc.exists) {
      throw new HttpsError("failed-precondition", "La caja ya no existe.");
    }
    const session = sessionDoc.data() ?? {};
    validateCashSession(session, input.branchId, input.businessDate);

    if (!policyDoc.exists) {
      throw new HttpsError("failed-precondition", "La politica de gasto ya no existe.");
    }
    const policy = policyFromDoc(policyDoc.id, policyDoc.data() ?? {});
    if (policy.restaurantId && policy.restaurantId !== input.restaurantId) {
      throw new HttpsError("permission-denied", "La politica no corresponde al restaurante.");
    }
    if (policy.branchId && policy.branchId !== input.branchId) {
      throw new HttpsError("failed-precondition", "La politica no corresponde a esta sucursal.");
    }

    const settings = settingsDoc.data() ?? {};
    const mode = expensePolicyMode(settings);
    const periodKey = periodKeyFor(policy, input.businessDate);
    const usageRef = restaurantRef
      .collection("expensePolicyUsage")
      .doc(usageDocId(policy.id, policy.branchId, periodKey));
    const usageDoc = await tx.get(usageRef);
    const usage = usageFromDoc(usageDoc.data());
    const decision = evaluatePolicy({
      mode,
      policy,
      usage,
      amount: input.amount,
      businessDate: input.businessDate,
      requestedAt: new Date(),
      paymentSource: input.paymentSource,
      supplierId: input.supplierId,
      requesterRole: input.requesterRole,
      requesterId: input.requesterId,
      hasReceipt: input.hasReceipt || input.receiptReference.length > 0,
    });
    const liveApproved = mode === "live" && decision.approved;
    const shadowWouldApprove = mode === "shadow" && decision.approved;
    const status: SubmitStatus = liveApproved ? "approved" : "pending";
    const now = admin.firestore.FieldValue.serverTimestamp();
    const snapshot = policySnapshot(policy);

    tx.set(expenseRef, {
      id: expenseRef.id,
      cashSessionId: input.cashSessionId,
      businessDate: input.businessDate,
      restaurantId: input.restaurantId,
      branchId: input.branchId,
      amount: input.amount,
      reason: input.reason,
      additionalNotes: input.additionalNotes,
      source: input.paymentSource,
      sourceName: input.paymentSource,
      supplierId: input.supplierId,
      receiptReference: input.receiptReference,
      hasReceipt: input.hasReceipt || input.receiptReference.length > 0,
      requestedByEmployeeId: input.requesterId,
      requestedByEmployeeName: input.requesterName,
      requestedByDeviceId: uid,
      requestedAt: now,
      status,
      authorizedByEmployeeId: liveApproved ? "auto_policy" : null,
      authorizedByEmployeeName: liveApproved ? "Politica de gasto" : null,
      authorizedAt: liveApproved ? now : null,
      adminNotes: null,
      approvedAt: liveApproved ? now : null,
      approvedByEmployeeId: liveApproved ? "auto_policy" : null,
      approvedByEmployeeName: liveApproved ? "Politica de gasto" : null,
      rejectedAt: null,
      rejectedByEmployeeId: null,
      rejectedByEmployeeName: null,
      rejectReason: null,
      policyId: policy.id,
      policyVersion: policy.policyVersion,
      policyName: policy.name,
      policySnapshot: snapshot,
      autoApproved: liveApproved,
      autoApprovedAt: liveApproved ? now : null,
      wouldAutoApprove: shadowWouldApprove,
      policyEvaluationMode: mode,
      policyDecisionReasonCode: decision.reasonCode,
      policyDecisionMessage: decision.message,
      policyEvaluationReason: decision.message,
      createdAt: now,
      updatedAt: now,
    });

    if (liveApproved) {
      tx.set(
        usageRef,
        {
          policyId: policy.id,
          branchId: policy.branchId,
          periodKey,
          amountUsed: money(usage.amountUsed + input.amount),
          usesUsed: usage.usesUsed + 1,
          expenseIds: [...usage.expenseIds, expenseRef.id],
          updatedAt: now,
        },
        {merge: true},
      );
    }

    tx.set(restaurantRef.collection("activityLog").doc(), {
      type: liveApproved
        ? "EXPENSE_AUTO_APPROVED_SERVER"
        : shadowWouldApprove
          ? "EXPENSE_POLICY_SHADOW_MATCH"
          : "EXPENSE_SENT_TO_MANUAL_APPROVAL",
      restaurantId: input.restaurantId,
      branchId: input.branchId,
      expenseId: expenseRef.id,
      policyId: policy.id,
      policyName: policy.name,
      policyVersion: policy.policyVersion,
      policyDecisionReasonCode: decision.reasonCode,
      policyDecisionMessage: decision.message,
      policyEvaluationMode: mode,
      amount: input.amount,
      employeeId: input.requesterId,
      employeeName: input.requesterName,
      deviceId: uid,
      createdAt: now,
    });

    const result = {
      requestId: expenseRef.id,
      expenseId: expenseRef.id,
      status,
      autoApproved: liveApproved,
      wouldAutoApprove: shadowWouldApprove,
      policyId: policy.id,
      policyVersion: policy.policyVersion,
      reason: decision.message,
      reasonCode: decision.reasonCode,
      periodUsage: liveApproved ? money(usage.amountUsed + input.amount) : usage.amountUsed,
      periodLimit: policy.maxAmountPerPeriod,
    };
    tx.set(idempotencyRef, {
      clientRequestId: input.clientRequestId,
      requestId: expenseRef.id,
      result,
      createdAt: now,
      uid,
    });
    return result;
  });
}

export async function cancelExpenseRequestCore(
  firestore: admin.firestore.Firestore,
  raw: CancelExpenseData,
  context: CallableContext,
) {
  requireAuth(context);
  const uid = context.auth!.uid;
  const restaurantId = cleanString(raw.restaurantId);
  const requestId = cleanString(raw.requestId);
  const reason = cleanString(raw.reason);
  if (!restaurantId || !requestId || !reason) {
    throw new HttpsError("invalid-argument", "Faltan datos para cancelar.");
  }
  const restaurantRef = firestore.collection("restaurants").doc(restaurantId);
  const expenseRef = restaurantRef.collection("cashWithdrawalRequests").doc(requestId);
  return firestore.runTransaction(async (tx) => {
    const [adminDoc, expenseDoc] = await Promise.all([
      tx.get(restaurantRef.collection("authUsers").doc(uid)),
      tx.get(expenseRef),
    ]);
    if (!isAdmin(adminDoc.data())) {
      throw new HttpsError("permission-denied", "No tienes permiso para cancelar.");
    }
    if (!expenseDoc.exists) {
      throw new HttpsError("not-found", "La solicitud ya no existe.");
    }
    const expense = expenseDoc.data() ?? {};
    if (expense.cancelledAt) {
      return {requestId, status: "cancelled", restored: false, reason: "already_cancelled"};
    }
    const policyId = cleanString(expense.policyId);
    const policyVersion = Number(expense.policyVersion ?? 0);
    const autoApproved = expense.autoApproved === true;
    let restored = false;
    const now = admin.firestore.FieldValue.serverTimestamp();
    if (policyId && autoApproved) {
      const policyDoc = await tx.get(restaurantRef.collection("expensePolicies").doc(policyId));
      const policy = policyFromDoc(policyDoc.id, policyDoc.data() ?? {});
      const periodKey = periodKeyFor(policy, cleanString(expense.businessDate));
      const usageRef = restaurantRef
        .collection("expensePolicyUsage")
        .doc(usageDocId(policy.id, policy.branchId, periodKey));
      const usageDoc = await tx.get(usageRef);
      const usage = usageFromDoc(usageDoc.data());
      if (policy.restoreQuotaOnCancellation && usage.expenseIds.includes(requestId)) {
        tx.set(
          usageRef,
          {
            amountUsed: Math.max(0, money(usage.amountUsed - Number(expense.amount ?? 0))),
            usesUsed: Math.max(0, usage.usesUsed - 1),
            expenseIds: usage.expenseIds.filter((id) => id !== requestId),
            updatedAt: now,
          },
          {merge: true},
        );
        restored = true;
      }
    }
    tx.update(expenseRef, {
      status: "cancelled",
      cancelledAt: now,
      cancelledByUid: uid,
      cancellationReason: reason,
      quotaRestored: restored,
      cancelledPolicyVersion: policyVersion,
      updatedAt: now,
    });
    tx.set(restaurantRef.collection("activityLog").doc(), {
      type: "EXPENSE_CANCELLED_SERVER",
      expenseId: requestId,
      policyId,
      quotaRestored: restored,
      reason,
      uid,
      createdAt: now,
    });
    return {requestId, status: "cancelled", restored};
  });
}

function requireAuth(context: CallableContext) {
  if (!context.auth?.uid) {
    throw new HttpsError("unauthenticated", "Se requiere autenticacion.");
  }
}

function parseSubmitInput(raw: SubmitExpenseData) {
  const input = {
    restaurantId: cleanString(raw.restaurantId),
    branchId: cleanString(raw.branchId),
    policyId: cleanString(raw.policyId),
    amount: Number(raw.amount),
    supplierId: cleanString(raw.supplierId),
    paymentSource: cleanString(raw.paymentSource) || "cash",
    reason: cleanString(raw.reason),
    additionalNotes: cleanString(raw.additionalNotes),
    requesterId: cleanString(raw.requesterId),
    requesterName: cleanString(raw.requesterName),
    requesterRole: cleanString(raw.requesterRole),
    businessDate: cleanString(raw.businessDate),
    cashSessionId: cleanString(raw.cashSessionId),
    clientRequestId: cleanString(raw.clientRequestId),
    hasReceipt: raw.hasReceipt === true,
    receiptReference: cleanString(raw.receiptReference),
  };
  if (
    !input.restaurantId ||
    !input.branchId ||
    !input.policyId ||
    !input.businessDate ||
    !input.cashSessionId ||
    !input.clientRequestId
  ) {
    throw new HttpsError("invalid-argument", "Faltan datos obligatorios.");
  }
  if (!Number.isFinite(input.amount) || input.amount <= 0) {
    throw new HttpsError("invalid-argument", "Captura un monto valido.");
  }
  if (!input.reason) {
    throw new HttpsError("invalid-argument", "Captura el motivo.");
  }
  return input;
}

function rejectForgedFields(raw: object) {
  for (const key of [
    "approved",
    "autoApproved",
    "policySnapshot",
    "policyVersion",
    "usesUsed",
    "amountUsed",
  ]) {
    if (key in raw) {
      throw new HttpsError("invalid-argument", `Campo no permitido: ${key}`);
    }
  }
}

function validateDevice(
  doc: admin.firestore.DocumentSnapshot,
  restaurantId: string,
  branchId: string,
) {
  if (!doc.exists) {
    throw new HttpsError("permission-denied", "Dispositivo no registrado.");
  }
  const data = doc.data() ?? {};
  if (data.active === false) {
    throw new HttpsError("permission-denied", "Dispositivo desactivado.");
  }
  if (cleanString(data.restaurantId) && cleanString(data.restaurantId) !== restaurantId) {
    throw new HttpsError("permission-denied", "Dispositivo de otro restaurante.");
  }
  if (cleanString(data.branchId) && cleanString(data.branchId) !== branchId) {
    throw new HttpsError("permission-denied", "Dispositivo de otra sucursal.");
  }
}

function validateCashSession(
  session: admin.firestore.DocumentData,
  branchId: string,
  businessDate: string,
) {
  if (cleanString(session.branchId) !== branchId) {
    throw new HttpsError("failed-precondition", "La caja no corresponde a esta sucursal.");
  }
  if (cleanString(session.businessDate) !== businessDate) {
    throw new HttpsError("failed-precondition", "La caja no corresponde al dia operativo.");
  }
  if (cleanString(session.status) !== "open" || session.closedAt) {
    throw new HttpsError("failed-precondition", "La caja ya esta cerrada.");
  }
}

function expensePolicyMode(settings: admin.firestore.DocumentData): Mode {
  const rawMode = cleanString(settings.expensePolicyMode || settings.mode).toLowerCase();
  if (rawMode === "shadow" || rawMode === "live" || rawMode === "off") return rawMode;
  return settings.expensePoliciesEnabled === true ? "live" : "off";
}

function evaluatePolicy(input: {
  mode: Mode;
  policy: Policy;
  usage: Usage;
  amount: number;
  businessDate: string;
  requestedAt: Date;
  paymentSource: string;
  supplierId: string;
  requesterRole: string;
  requesterId: string;
  hasReceipt: boolean;
}): Decision {
  const periodKey = periodKeyFor(input.policy, input.businessDate);
  const manual = (reasonCode: string, message: string): Decision => ({
    approved: false,
    reasonCode,
    message,
    periodKey,
  });
  const policy = input.policy;
  if (input.mode === "off") return manual("mode_off", "Las politicas estan desactivadas.");
  if (!policy.active) return manual("policy_inactive", "La politica no esta activa.");
  if (!policy.autoApproveEnabled) return manual("policy_manual", "La politica requiere autorizacion manual.");
  if (input.amount <= 0) return manual("invalid_amount", "Captura un monto valido.");
  if (policy.maxAmountPerTransaction > 0 && input.amount > policy.maxAmountPerTransaction) {
    return manual("max_transaction_amount", `Supera el monto maximo de $${policy.maxAmountPerTransaction.toFixed(2)}.`);
  }
  if (policy.maxUsesPerPeriod > 0 && input.usage.usesUsed >= policy.maxUsesPerPeriod) {
    return manual("max_uses", "El limite de usos del periodo ya fue alcanzado.");
  }
  if (policy.maxAmountPerPeriod > 0 && money(input.usage.amountUsed + input.amount) > policy.maxAmountPerPeriod) {
    return manual("max_period_amount", "El limite acumulado del periodo ya fue alcanzado.");
  }
  if (policy.receiptRequired && !input.hasReceipt) {
    return manual("receipt_required", "Esta politica requiere comprobante.");
  }
  if (policy.supplierRestrictionEnabled && !policy.allowedSupplierIds.includes(input.supplierId)) {
    return manual("supplier_not_allowed", "El proveedor seleccionado no esta permitido.");
  }
  if (policy.allowedPaymentSources.length > 0 && !policy.allowedPaymentSources.includes(input.paymentSource)) {
    return manual("payment_source_not_allowed", "La fuente de pago no esta permitida.");
  }
  if (policy.requesterRoleRestrictions.length > 0 && !policy.requesterRoleRestrictions.includes(input.requesterRole)) {
    return manual("role_not_verifiable", "La identidad del empleado requiere autorizacion manual.");
  }
  if (policy.requesterIds.length > 0 && !policy.requesterIds.includes(input.requesterId)) {
    return manual("requester_not_verifiable", "El empleado requiere autorizacion manual.");
  }
  if (!businessDateAllowed(policy, input.businessDate)) {
    return manual("frequency_not_allowed", "La politica no esta disponible en esta fecha operativa.");
  }
  if (!timeAllowed(policy, input.requestedAt)) {
    return manual("time_not_allowed", "La solicitud quedo fuera del horario de autorizacion.");
  }
  const date = parseBusinessDate(input.businessDate);
  if (policy.validFrom && date < parseBusinessDate(policy.validFrom)) {
    return manual("not_yet_valid", "La politica aun no esta vigente.");
  }
  if (policy.validUntil && date > parseBusinessDate(policy.validUntil)) {
    return manual("expired", "La politica ya no esta vigente.");
  }
  return {approved: true, reasonCode: "auto_approved", message: "Gasto autorizado automaticamente.", periodKey};
}

function policyFromDoc(id: string, data: admin.firestore.DocumentData): Policy {
  return {
    id,
    restaurantId: cleanString(data.restaurantId),
    branchId: cleanString(data.branchId),
    name: cleanString(data.name),
    code: cleanString(data.code),
    active: data.active !== false,
    autoApproveEnabled: data.autoApproveEnabled === true,
    maxAmountPerTransaction: Number(data.maxAmountPerTransaction ?? 0),
    maxAmountPerPeriod: Number(data.maxAmountPerPeriod ?? 0),
    maxUsesPerPeriod: Number(data.maxUsesPerPeriod ?? 0),
    frequencyType: cleanString(data.frequencyType) || "daily",
    frequencyValue: Number(data.frequencyValue ?? 1),
    allowedWeekdays: numberList(data.allowedWeekdays),
    periodResetWeekday: Number(data.periodResetWeekday ?? 1),
    receiptRequired: data.receiptRequired === true,
    supplierRestrictionEnabled: data.supplierRestrictionEnabled === true,
    allowedSupplierIds: stringList(data.allowedSupplierIds),
    allowedPaymentSources: stringList(data.allowedPaymentSources),
    requesterRoleRestrictions: stringList(data.requesterRoleRestrictions),
    requesterIds: stringList(data.requesterIds),
    allowedStartTime: cleanString(data.allowedStartTime),
    allowedEndTime: cleanString(data.allowedEndTime),
    validFrom: dateString(data.validFrom),
    validUntil: dateString(data.validUntil),
    restoreQuotaOnCancellation: data.restoreQuotaOnCancellation === true,
    requireReason: data.requireReason !== false,
    allowFreeConcept: data.allowFreeConcept === true,
    policyVersion: Number(data.policyVersion ?? 1),
  };
}

function usageFromDoc(data?: admin.firestore.DocumentData): Usage {
  return {
    amountUsed: Number(data?.amountUsed ?? 0),
    usesUsed: Number(data?.usesUsed ?? 0),
    expenseIds: stringList(data?.expenseIds),
  };
}

function policySnapshot(policy: Policy) {
  return {
    policyId: policy.id,
    policyVersion: policy.policyVersion,
    policyName: policy.name,
    policyCode: policy.code,
    maxAmountPerTransactionSnapshot: policy.maxAmountPerTransaction,
    maxAmountPerPeriodSnapshot: policy.maxAmountPerPeriod,
    maxUsesSnapshot: policy.maxUsesPerPeriod,
    frequencySnapshot: policy.frequencyType,
    frequencyValueSnapshot: policy.frequencyValue,
    receiptRequiredSnapshot: policy.receiptRequired,
    supplierRestrictionSnapshot: policy.supplierRestrictionEnabled,
    allowedSupplierIdsSnapshot: policy.allowedSupplierIds,
    allowedPaymentSourcesSnapshot: policy.allowedPaymentSources,
    validFromSnapshot: policy.validFrom,
    validUntilSnapshot: policy.validUntil,
    restoreQuotaOnCancellationSnapshot: policy.restoreQuotaOnCancellation,
  };
}

function periodKeyFor(policy: Policy, businessDate: string): string {
  const date = parseBusinessDate(businessDate);
  const prefix = `${policy.id}_${policy.branchId}`;
  switch (policy.frequencyType) {
    case "everyNDays":
      return `${prefix}:every_${safeFrequency(policy.frequencyValue)}_days:${periodBucket(date, safeFrequency(policy.frequencyValue))}`;
    case "weekly":
      return `${prefix}:week:${dateKey(weekStart(date, policy.periodResetWeekday))}`;
    case "everyNWeeks":
      return `${prefix}:every_${safeFrequency(policy.frequencyValue)}_weeks:${periodBucket(weekStart(date, policy.periodResetWeekday), safeFrequency(policy.frequencyValue) * 7)}`;
    case "monthly":
      return `${prefix}:${date.getUTCFullYear()}-${`${date.getUTCMonth() + 1}`.padStart(2, "0")}`;
    case "specificWeekdays":
    case "daily":
    default:
      return `${prefix}:${dateKey(date)}`;
  }
}

function businessDateAllowed(policy: Policy, businessDate: string): boolean {
  if (policy.frequencyType !== "specificWeekdays") return true;
  return policy.allowedWeekdays.includes(parseBusinessDate(businessDate).getUTCDay() || 7);
}

function timeAllowed(policy: Policy, requestedAt: Date): boolean {
  const start = minutes(policy.allowedStartTime);
  const end = minutes(policy.allowedEndTime);
  if (start == null && end == null) return true;
  const current = requestedAt.getUTCHours() * 60 + requestedAt.getUTCMinutes();
  if (start != null && current < start) return false;
  if (end != null && current > end) return false;
  return true;
}

function usageDocId(policyId: string, branchId: string, periodKey: string): string {
  return `${policyId}|${branchId}|${periodKey}`.replace(/[^A-Za-z0-9_-]/g, "_");
}

function isAdmin(data?: admin.firestore.DocumentData): boolean {
  return data?.active === true &&
    (data.isSuperAdmin === true ||
      data.permissions?.canViewAdmin === true ||
      data.permissions?.canAuthorizeCashWithdrawals === true);
}

function safeFrequency(value: number): number {
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : 1;
}

function periodBucket(date: Date, days: number): number {
  return Math.floor(daysSinceEpoch(date) / days);
}

function daysSinceEpoch(date: Date): number {
  return Math.floor(date.getTime() / 86400000);
}

function weekStart(date: Date, resetWeekday: number): Date {
  const safeReset = resetWeekday >= 1 && resetWeekday <= 7 ? resetWeekday : 1;
  const weekday = date.getUTCDay() || 7;
  const delta = (weekday - safeReset + 7) % 7;
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() - delta));
}

function dateKey(date: Date): string {
  return `${date.getUTCFullYear()}-${`${date.getUTCMonth() + 1}`.padStart(2, "0")}-${`${date.getUTCDate()}`.padStart(2, "0")}`;
}

function parseBusinessDate(value: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) throw new HttpsError("invalid-argument", "Fecha operativa invalida.");
  return new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
}

function minutes(value: string): number | null {
  const match = /^(\d{1,2}):(\d{2})$/.exec(value);
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

function cleanString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function stringList(value: unknown): string[] {
  return Array.isArray(value) ? value.map((item) => `${item}`.trim()).filter(Boolean) : [];
}

function numberList(value: unknown): number[] {
  return Array.isArray(value) ? value.filter((item) => typeof item === "number") : [];
}

function dateString(value: unknown): string {
  if (typeof value === "string") return value.trim();
  if (value instanceof admin.firestore.Timestamp) return dateKey(value.toDate());
  return "";
}

function money(value: number): number {
  return Math.round(value * 100) / 100;
}
