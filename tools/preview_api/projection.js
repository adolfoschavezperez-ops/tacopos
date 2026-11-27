/**
 * Server-side collection allowlist, explicit document projections,
 * recursive secret stripping, and Timestamp serialization for Preview API.
 */

const MAX_DOCS_PER_QUERY = 500;

const ALLOWED_RESTAURANT_COLLECTIONS = new Set([
  'branches',
  'orders',
  'cashSessions',
  'cashWithdrawalRequests',
  'discountAuthorizationRequests',
  'kitchenSessions',
  'kitchenStockItems',
  'ingredientYieldProfiles',
  'productRecipes',
  'theoreticalProductRecipes',
  'productStockOuts',
  'suppliers',
  'purchaseItems',
  'supplierPurchases',
  'supplierPayments',
  'partners',
  'partnerContributions',
  'expensePolicies',
  'expensePolicyUsage',
  'activityLog',
  'products',
  'productCategories',
  'tables',
  'orderPlatforms',
  'devices',
  'discountUsage',
  'settings',
  'employees',
]);

const ALLOWED_SUBCOLLECTIONS = new Map([
  ['orders', new Set(['items', 'payments'])],
  ['kitchenSessions', new Set(['items'])],
  ['supplierPurchases', new Set(['items'])],
]);

const BRANCH_SCOPED_COLLECTIONS = new Set([
  'orders',
  'cashSessions',
  'cashWithdrawalRequests',
  'discountAuthorizationRequests',
  'kitchenSessions',
  'productStockOuts',
  'supplierPurchases',
  'supplierPayments',
  'partnerContributions',
  'tables',
]);

const EMPLOYEE_PERMISSION_KEYS = [
  'canTakeOrders',
  'canCharge',
  'canViewKitchen',
  'canViewAdmin',
  'canManageProducts',
  'canManageTables',
  'canManagePlatforms',
  'canManageEmployees',
  'canManageCash',
  'canAuthorizeCashWithdrawals',
  'canOpenKitchen',
  'canCloseKitchen',
  'canViewKitchenReports',
  'canViewKitchenHourlySalesComparison',
  'canManageKitchenStock',
  'canCancelOrders',
  'canCancelPayments',
  'canCancelItems',
  'canApproveKitchenCancellations',
  'canViewLiveOperations',
  'canControlLiveOperations',
  'canViewPurchases',
  'canManageSuppliers',
  'canRegisterPurchases',
  'canPaySuppliers',
  'canCancelSupplierPayments',
  'canViewAccountsPayable',
  'canViewPurchaseReports',
];

const SENSITIVE_KEY_PATTERN =
  /^(pin|pinhash|password|passwordhash|secret|token|fcmtoken|authtoken|cardtoken|credential|apikey|privatekey|salt|rawresponse|authorizationsecret|devicetoken)$/i;

const RESERVED_ACTIVITY_FIELDS = new Set([
  'submissionId',
  'localCapture',
  'payloadHash',
]);

function serializeValue(val) {
  if (val === null || val === undefined) return val;
  if (typeof val.toMillis === 'function') {
    return { __previewTsMs: val.toMillis() };
  }
  if (val instanceof Date) {
    return { __previewTsMs: val.getTime() };
  }
  if (Array.isArray(val)) {
    return val.map(serializeValue);
  }
  if (typeof val === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(val)) {
      if (SENSITIVE_KEY_PATTERN.test(k)) continue;
      out[k] = serializeValue(v);
    }
    return out;
  }
  return val;
}

function projectEmployeeDoc(id, data) {
  if (!data || typeof data !== 'object') return null;
  const projected = {
    id: data.id || id,
    restaurantId: data.restaurantId || '',
    name: data.name || '',
    active: data.active === true,
    isSuperAdmin: data.isSuperAdmin === true,
    defaultRestaurantId: data.defaultRestaurantId || '',
    defaultBranchId: data.defaultBranchId || '',
    branchAccess: Array.isArray(data.branchAccess)
      ? serializeValue(data.branchAccess)
      : [],
    createdAt: serializeValue(data.createdAt || null),
    updatedAt: serializeValue(data.updatedAt || null),
  };
  for (const key of EMPLOYEE_PERMISSION_KEYS) {
    projected[key] = data[key] === true;
  }
  return projected;
}

function projectDeviceDoc(id, data) {
  return {
    id,
    deviceId: data.deviceId || id,
    deviceName: data.deviceName || id,
    branchId: data.branchId || '',
    branchName: data.branchName || '',
    role: data.role || 'unknown',
    platform: data.platform || '',
    appVersionName: data.appVersionName || '',
    appVersionCode: typeof data.appVersionCode === 'number' ? data.appVersionCode : 0,
    employeeId: data.employeeId || '',
    employeeName: data.employeeName || '',
    updateStatus: data.updateStatus || 'unknown',
    active: data.active !== false,
    lastSeenAt: serializeValue(data.lastSeenAt || null),
  };
}

function projectActivityLogDoc(id, data) {
  const out = { id };
  for (const [k, v] of Object.entries(data)) {
    if (RESERVED_ACTIVITY_FIELDS.has(k) || SENSITIVE_KEY_PATTERN.test(k)) {
      continue;
    }
    out[k] = serializeValue(v);
  }
  return out;
}

function projectSettingsDoc(id, data) {
  // Only expose safe non-secret settings documents
  const allowedSettingIds = new Set(['discounts', 'appUpdates', 'expensePolicies']);
  if (!allowedSettingIds.has(id)) {
    return { id, restricted: true };
  }
  return { id, ...serializeValue(data) };
}

function projectPaymentDoc(id, data) {
  const out = { id };
  for (const [k, v] of Object.entries(data)) {
    if (SENSITIVE_KEY_PATTERN.test(k)) continue;
    out[k] = serializeValue(v);
  }
  return out;
}

function projectDoc(collectionName, id, data) {
  if (!data || typeof data !== 'object') return null;
  if (collectionName === 'employees') {
    return projectEmployeeDoc(id, data);
  }
  if (collectionName === 'devices') {
    return projectDeviceDoc(id, data);
  }
  if (collectionName === 'activityLog') {
    return projectActivityLogDoc(id, data);
  }
  if (collectionName === 'settings') {
    return projectSettingsDoc(id, data);
  }
  if (collectionName === 'payments') {
    return projectPaymentDoc(id, data);
  }
  return { id, ...serializeValue(data) };
}

function isAllowedCollectionPath(collectionName, subcollectionName) {
  if (!ALLOWED_RESTAURANT_COLLECTIONS.has(collectionName)) {
    return false;
  }
  if (!subcollectionName) return true;
  const allowedSubs = ALLOWED_SUBCOLLECTIONS.get(collectionName);
  return Boolean(allowedSubs && allowedSubs.has(subcollectionName));
}

function isValidPathSegment(seg) {
  if (typeof seg !== 'string') return false;
  const s = seg.trim();
  return s.length > 0 && s.length <= 128 && !s.includes('/') && !s.includes('..') && !/\s/.test(s);
}

module.exports = {
  MAX_DOCS_PER_QUERY,
  ALLOWED_RESTAURANT_COLLECTIONS,
  ALLOWED_SUBCOLLECTIONS,
  BRANCH_SCOPED_COLLECTIONS,
  EMPLOYEE_PERMISSION_KEYS,
  projectEmployeeDoc,
  projectDoc,
  serializeValue,
  isAllowedCollectionPath,
  isValidPathSegment,
};
