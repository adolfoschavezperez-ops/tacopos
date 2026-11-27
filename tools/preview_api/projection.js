/**
 * Server-side collection allowlist, secret projection, and consumption caps
 * for Backoffice 2.0 Preview (Read-Only).
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

/**
 * Strips all credentials, PINs, hashes, tokens, and unnecessary PII from
 * employee documents before returning them to the Preview browser.
 */
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
    branchAccess: Array.isArray(data.branchAccess) ? data.branchAccess : [],
    createdAt: data.createdAt || null,
    updatedAt: data.updatedAt || null,
  };
  for (const key of EMPLOYEE_PERMISSION_KEYS) {
    projected[key] = data[key] === true;
  }
  return projected;
}

function projectDoc(collectionName, id, data) {
  if (collectionName === 'employees') {
    return projectEmployeeDoc(id, data);
  }
  return { id, ...data };
}

function isAllowedCollectionPath(collectionName, subcollectionName) {
  if (!ALLOWED_RESTAURANT_COLLECTIONS.has(collectionName)) {
    return false;
  }
  if (!subcollectionName) return true;
  const allowedSubs = ALLOWED_SUBCOLLECTIONS.get(collectionName);
  return Boolean(allowedSubs && allowedSubs.has(subcollectionName));
}

module.exports = {
  MAX_DOCS_PER_QUERY,
  ALLOWED_RESTAURANT_COLLECTIONS,
  ALLOWED_SUBCOLLECTIONS,
  BRANCH_SCOPED_COLLECTIONS,
  EMPLOYEE_PERMISSION_KEYS,
  projectEmployeeDoc,
  projectDoc,
  isAllowedCollectionPath,
};
