const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'demo-tacopos-backoffice-v2-rules';
const RULES_PATH = path.resolve(
  __dirname,
  '../../firestore.backoffice-v2.rules',
);

describe('Backoffice 2.0 Multi-Tenant & Multi-Branch Isolation Rules', () => {
  let testEnv;

  before(async () => {
    const rules = fs.readFileSync(RULES_PATH, 'utf8');
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { rules },
    });
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();

      // Restaurant Alpha (2 branches)
      await db.doc('restaurants/rest_alpha').set({ name: 'Taqueria Alpha' });
      await db.doc('restaurants/rest_alpha/branches/suc_centro').set({
        id: 'suc_centro',
        name: 'Centro',
        active: true,
        sortOrder: 1,
      });
      await db.doc('restaurants/rest_alpha/branches/suc_norte').set({
        id: 'suc_norte',
        name: 'Norte',
        active: true,
        sortOrder: 2,
      });
      await db.doc('restaurants/rest_alpha/authUsers/alpha_centro_mgr').set({
        active: true,
        isSuperAdmin: false,
        branchAccess: ['suc_centro'],
        permissions: { canViewAdmin: true },
      });
      await db.doc('restaurants/rest_alpha/authUsers/alpha_cash_only').set({
        active: true,
        isSuperAdmin: false,
        branchAccess: ['suc_centro'],
        permissions: {
          canViewAdmin: false,
          canManageCash: true,
          canAuthorizeCashWithdrawals: false,
          canManageKitchenStock: false,
          canViewKitchenReports: false,
        },
      });
      await db.doc('restaurants/rest_alpha/authUsers/alpha_revoked').set({
        active: false,
        isSuperAdmin: true,
        branchAccess: ['suc_centro', 'suc_norte'],
        permissions: {
          canViewAdmin: true,
          canManageCash: true,
          canAuthorizeCashWithdrawals: true,
          canManageKitchenStock: true,
        },
      });
      await db.doc('restaurants/rest_alpha/cashSessions/cs_centro_1').set({
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        businessDate: '2026-11-26',
        status: 'open',
      });
      await db.doc('restaurants/rest_alpha/cashSessions/cs_norte_1').set({
        restaurantId: 'rest_alpha',
        branchId: 'suc_norte',
        businessDate: '2026-11-26',
        status: 'open',
      });
      await db.doc('restaurants/rest_alpha/cashWithdrawalRequests/cw_centro_1').set({
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        businessDate: '2026-11-26',
        status: 'pending',
        amount: 250,
      });
      await db.doc('restaurants/rest_alpha/cashWithdrawalRequests/cw_norte_1').set({
        restaurantId: 'rest_alpha',
        branchId: 'suc_norte',
        businessDate: '2026-11-26',
        status: 'pending',
        amount: 400,
      });
      await db.doc('restaurants/rest_alpha/discountAuthorizationRequests/da_centro_1').set({
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        businessDate: '2026-11-26',
        status: 'pending',
      });
      await db.doc('restaurants/rest_alpha/kitchenSessions/ks_centro_1').set({
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        businessDate: '2026-11-26',
        status: 'open',
      });
      await db.doc('restaurants/rest_alpha/kitchenSessions/ks_centro_1/items/ksi_1').set({
        kitchenStockItemId: 'ksi_1',
        name: 'Carne al Pastor',
      });
      await db.doc('restaurants/rest_alpha/kitchenSessions/ks_norte_1').set({
        restaurantId: 'rest_alpha',
        branchId: 'suc_norte',
        businessDate: '2026-11-26',
        status: 'open',
      });
      await db.doc('restaurants/rest_alpha/kitchenSessions/ks_norte_1/items/ksi_1').set({
        kitchenStockItemId: 'ksi_1',
        name: 'Carne al Pastor',
      });
      await db.doc('restaurants/rest_alpha/kitchenStockItems/ksi_1').set({
        name: 'Carne al Pastor',
        active: true,
      });
      await db.doc('restaurants/rest_alpha/products/prod_1').set({
        name: 'Orden de Pastor',
        active: true,
      });
      await db.doc('restaurants/rest_alpha/productStockOuts/so_centro_1').set({
        branchId: 'suc_centro',
        businessDate: '2026-11-26',
        status: 'active',
      });
      await db.doc('restaurants/rest_alpha/productStockOuts/so_norte_1').set({
        branchId: 'suc_norte',
        businessDate: '2026-11-26',
        status: 'active',
      });
      await db.doc('restaurants/rest_alpha/suppliers/sup_1').set({
        id: 'sup_1',
        commercialName: 'Carnicería El Buen Corte',
        active: true,
      });
      await db.doc('restaurants/rest_alpha/purchaseItems/pi_1').set({
        id: 'pi_1',
        name: 'Carne al Pastor',
        category: 'Carnes',
        unit: 'kg',
        active: true,
      });
      await db.doc('restaurants/rest_alpha/supplierPurchases/sp_centro_1').set({
        id: 'sp_centro_1',
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        supplierId: 'sup_1',
        businessDate: '2026-11-26',
        status: 'pending',
        total: 1200,
        paidTotal: 0,
        balance: 1200,
      });
      await db
        .doc('restaurants/rest_alpha/supplierPurchases/sp_centro_1/items/li_1')
        .set({
          purchaseItemId: 'pi_1',
          purchaseItemName: 'Carne al Pastor',
          quantity: 10,
          unit: 'kg',
          lineTotal: 1200,
        });
      await db.doc('restaurants/rest_alpha/supplierPurchases/sp_norte_1').set({
        id: 'sp_norte_1',
        restaurantId: 'rest_alpha',
        branchId: 'suc_norte',
        supplierId: 'sup_1',
        businessDate: '2026-11-26',
        status: 'pending',
        total: 800,
        paidTotal: 0,
        balance: 800,
      });
      await db.doc('restaurants/rest_alpha/supplierPayments/spay_centro_1').set({
        id: 'spay_centro_1',
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        supplierId: 'sup_1',
        purchaseId: 'sp_centro_1',
        amount: 500,
        status: 'active',
      });
      await db.doc('restaurants/rest_alpha/orders/ord_alpha_centro').set({
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        businessDate: '2026-11-26',
        status: 'paid',
        total: 320,
      });
      await db.doc('restaurants/rest_alpha/orders/ord_alpha_norte').set({
        restaurantId: 'rest_alpha',
        branchId: 'suc_norte',
        businessDate: '2026-11-26',
        status: 'paid',
        total: 480,
      });
      await db
        .doc('restaurants/rest_alpha/orders/ord_alpha_norte/payments/pay_1')
        .set({
          orderId: 'ord_alpha_norte',
          branchId: 'suc_norte',
          chargedAmount: 480,
        });

      // Restaurant Beta
      await db.doc('restaurants/rest_beta').set({ name: 'Taqueria Beta' });
      await db.doc('restaurants/rest_beta/branches/suc_sur').set({
        id: 'suc_sur',
        name: 'Sur',
        active: true,
        sortOrder: 1,
      });
      await db.doc('restaurants/rest_beta/authUsers/beta_admin').set({
        active: true,
        isSuperAdmin: true,
        branchAccess: ['suc_sur'],
        permissions: { canViewAdmin: true },
      });
      await db.doc('restaurants/rest_beta/orders/ord_beta_sur').set({
        restaurantId: 'rest_beta',
        branchId: 'suc_sur',
        businessDate: '2026-11-26',
        status: 'paid',
        total: 900,
      });
    });
  });

  after(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  it('denies unauthenticated reads', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      db.doc('restaurants/rest_alpha/orders/ord_alpha_centro').get(),
    );
  });

  it('denies anonymous auth in Backoffice 2.0', async () => {
    const db = testEnv
      .authenticatedContext('anon_device', {
        firebase: { sign_in_provider: 'anonymous' },
      })
      .firestore();
    await assertFails(
      db.doc('restaurants/rest_alpha/orders/ord_alpha_centro').get(),
    );
  });

  it('allows manager to read authorized branch order in own restaurant', async () => {
    const db = testEnv
      .authenticatedContext('alpha_centro_mgr', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();
    await assertSucceeds(
      db.doc('restaurants/rest_alpha/orders/ord_alpha_centro').get(),
    );
  });

  it('denies manager from reading unauthorized branch in same restaurant', async () => {
    const db = testEnv
      .authenticatedContext('alpha_centro_mgr', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();
    await assertFails(
      db.doc('restaurants/rest_alpha/orders/ord_alpha_norte').get(),
    );
    await assertFails(
      db
        .doc('restaurants/rest_alpha/orders/ord_alpha_norte/payments/pay_1')
        .get(),
    );
  });

  it('denies cross-restaurant access even for superAdmin of another tenant', async () => {
    const db = testEnv
      .authenticatedContext('beta_admin', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();
    await assertSucceeds(
      db.doc('restaurants/rest_beta/orders/ord_beta_sur').get(),
    );
    await assertFails(
      db.doc('restaurants/rest_alpha/orders/ord_alpha_centro').get(),
    );
    await assertFails(
      db.doc('restaurants/rest_alpha/orders/ord_alpha_norte').get(),
    );
  });

  it('denies unscoped collectionGroup payments query across tenants', async () => {
    const db = testEnv
      .authenticatedContext('alpha_centro_mgr', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();
    await assertFails(db.collectionGroup('payments').get());
  });

  it('allows authorized manager to read cash, authorizations, and inventory in own branch', async () => {
    const db = testEnv
      .authenticatedContext('alpha_centro_mgr', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();
    await assertSucceeds(
      db.doc('restaurants/rest_alpha/cashSessions/cs_centro_1').get(),
    );
    await assertSucceeds(
      db.doc('restaurants/rest_alpha/cashWithdrawalRequests/cw_centro_1').get(),
    );
    await assertSucceeds(
      db
        .doc('restaurants/rest_alpha/discountAuthorizationRequests/da_centro_1')
        .get(),
    );
    await assertSucceeds(
      db.doc('restaurants/rest_alpha/kitchenSessions/ks_centro_1').get(),
    );
    await assertSucceeds(
      db
        .doc('restaurants/rest_alpha/kitchenSessions/ks_centro_1/items/ksi_1')
        .get(),
    );
    await assertSucceeds(
      db.doc('restaurants/rest_alpha/kitchenStockItems/ksi_1').get(),
    );
    await assertSucceeds(
      db.doc('restaurants/rest_alpha/products/prod_1').get(),
    );
    await assertSucceeds(
      db.doc('restaurants/rest_alpha/productStockOuts/so_centro_1').get(),
    );
  });

  it('denies cross-branch reads for cash, withdrawals, kitchen sessions, and stock outs', async () => {
    const db = testEnv
      .authenticatedContext('alpha_centro_mgr', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();
    await assertFails(
      db.doc('restaurants/rest_alpha/cashSessions/cs_norte_1').get(),
    );
    await assertFails(
      db.doc('restaurants/rest_alpha/cashWithdrawalRequests/cw_norte_1').get(),
    );
    await assertFails(
      db.doc('restaurants/rest_alpha/kitchenSessions/ks_norte_1').get(),
    );
    await assertFails(
      db
        .doc('restaurants/rest_alpha/kitchenSessions/ks_norte_1/items/ksi_1')
        .get(),
    );
    await assertFails(
      db.doc('restaurants/rest_alpha/productStockOuts/so_norte_1').get(),
    );
  });

  it('denies reads when user lacks module permissions', async () => {
    const db = testEnv
      .authenticatedContext('alpha_cash_only', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();
    await assertSucceeds(
      db.doc('restaurants/rest_alpha/cashSessions/cs_centro_1').get(),
    );
    await assertFails(
      db
        .doc('restaurants/rest_alpha/discountAuthorizationRequests/da_centro_1')
        .get(),
    );
    await assertFails(
      db.doc('restaurants/rest_alpha/kitchenSessions/ks_centro_1').get(),
    );
    await assertFails(
      db.doc('restaurants/rest_alpha/kitchenStockItems/ksi_1').get(),
    );
    await assertFails(
      db.doc('restaurants/rest_alpha/productStockOuts/so_centro_1').get(),
    );
  });

  it('denies cross-tenant reads for Phase 4 collections', async () => {
    const db = testEnv
      .authenticatedContext('beta_admin', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();
    await assertFails(
      db.doc('restaurants/rest_alpha/cashSessions/cs_centro_1').get(),
    );
    await assertFails(
      db.doc('restaurants/rest_alpha/kitchenStockItems/ksi_1').get(),
    );
    await assertFails(
      db.doc('restaurants/rest_alpha/products/prod_1').get(),
    );
  });

  it('denies all operational reads for inactive/revoked authUsers', async () => {
    const db = testEnv
      .authenticatedContext('alpha_revoked', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();
    await assertFails(
      db.doc('restaurants/rest_alpha/orders/ord_alpha_centro').get(),
    );
    await assertFails(
      db.doc('restaurants/rest_alpha/cashSessions/cs_centro_1').get(),
    );
    await assertFails(
      db.doc('restaurants/rest_alpha/kitchenStockItems/ksi_1').get(),
    );
  });

  it('allows authorized manager to read and write purchases/suppliers in own branch and denies cross-branch or missing permissions', async () => {
    const mgrDb = testEnv
      .authenticatedContext('alpha_centro_mgr', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();

    await assertSucceeds(dbDoc(mgrDb, 'restaurants/rest_alpha/suppliers/sup_1').get());
    await assertSucceeds(dbDoc(mgrDb, 'restaurants/rest_alpha/purchaseItems/pi_1').get());
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/supplierPurchases/sp_centro_1').get(),
    );
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/supplierPurchases/sp_centro_1/items/li_1').get(),
    );
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/supplierPayments/spay_centro_1').get(),
    );
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/supplierPurchases/sp_centro_2').set({
        id: 'sp_centro_2',
        branchId: 'suc_centro',
        supplierId: 'sup_1',
        total: 500,
        balance: 500,
      }),
    );
    // Cross-branch denied
    await assertFails(
      dbDoc(mgrDb, 'restaurants/rest_alpha/supplierPurchases/sp_norte_1').get(),
    );
    await assertFails(
      dbDoc(mgrDb, 'restaurants/rest_alpha/supplierPurchases/sp_norte_2').set({
        id: 'sp_norte_2',
        branchId: 'suc_norte',
        supplierId: 'sup_1',
      }),
    );
    // Delete always denied
    await assertFails(
      dbDoc(mgrDb, 'restaurants/rest_alpha/supplierPurchases/sp_centro_1').delete(),
    );

    // User without purchase permissions denied
    const cashOnlyDb = testEnv
      .authenticatedContext('alpha_cash_only', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();
    await assertFails(
      dbDoc(cashOnlyDb, 'restaurants/rest_alpha/supplierPurchases/sp_centro_1').get(),
    );
    await assertFails(
      dbDoc(cashOnlyDb, 'restaurants/rest_alpha/suppliers/sup_1').get(),
    );

    // Cross-tenant denied
    const betaDb = testEnv
      .authenticatedContext('beta_admin', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();
    await assertFails(
      dbDoc(betaDb, 'restaurants/rest_alpha/supplierPurchases/sp_centro_1').get(),
    );
  });
});

function dbDoc(db, p) {
  return db.doc(p);
}
