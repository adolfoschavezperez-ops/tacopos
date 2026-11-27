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

  it('enforces server-side write security for Phase 5.1 cancellations, authorizations, kitchen CRUD, and supplier payment cancellations', async () => {
    const mgrDb = testEnv
      .authenticatedContext('alpha_centro_mgr', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();
    const cashOnlyDb = testEnv
      .authenticatedContext('alpha_cash_only', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();

    // Manager can authorize pending withdrawal once; second update fails because status != pending
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/cashWithdrawalRequests/cw_centro_1').update({
        status: 'approved',
        approvedByEmployeeId: 'alpha_centro_mgr',
      }),
    );
    await assertFails(
      dbDoc(mgrDb, 'restaurants/rest_alpha/cashWithdrawalRequests/cw_centro_1').update({
        status: 'rejected',
      }),
    );

    // Cross-branch authorization denied
    await assertFails(
      dbDoc(mgrDb, 'restaurants/rest_alpha/cashWithdrawalRequests/cw_norte_1').update({
        status: 'approved',
      }),
    );

    // Manager can cancel order in own branch; cashOnly cannot
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/orders/ord_alpha_centro').update({
        status: 'cancelled',
      }),
    );
    await assertFails(
      dbDoc(cashOnlyDb, 'restaurants/rest_alpha/orders/ord_alpha_centro').update({
        status: 'cancelled',
      }),
    );

    // Manager can update kitchen stock; cashOnly cannot
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/kitchenStockItems/ksi_1').update({
        active: false,
      }),
    );
    await assertFails(
      dbDoc(cashOnlyDb, 'restaurants/rest_alpha/kitchenStockItems/ksi_1').update({
        active: false,
      }),
    );

    // Manager can cancel active supplier payment once
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/supplierPayments/spay_centro_1').update({
        status: 'cancelled',
      }),
    );
    await assertFails(
      dbDoc(mgrDb, 'restaurants/rest_alpha/supplierPayments/spay_centro_1').update({
        status: 'active',
      }),
    );
  });

  it('Phase 5.1 & 6 integration: simultaneous authorizations, closed-cash-only corrections, recipes, partners, and DEV budgets', async () => {
    const mgrDb = testEnv
      .authenticatedContext('alpha_centro_mgr', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();
    const cashOnlyDb = testEnv
      .authenticatedContext('alpha_cash_only', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();

    // 1. Concurrent authorization race on pending discount request: only 1 succeeds
    const discRef1 = mgrDb.doc(
      'restaurants/rest_alpha/discountAuthorizationRequests/da_centro_1',
    );
    const discRef2 = mgrDb.doc(
      'restaurants/rest_alpha/discountAuthorizationRequests/da_centro_1',
    );
    const raceResults = await Promise.allSettled([
      mgrDb.runTransaction(async (tx) => {
        const snap = await tx.get(discRef1);
        if (snap.data().status !== 'pending') throw new Error('already resolved');
        tx.update(discRef1, { status: 'approved', authorizedByEmployeeId: 'mgr1' });
      }),
      mgrDb.runTransaction(async (tx) => {
        const snap = await tx.get(discRef2);
        if (snap.data().status !== 'pending') throw new Error('already resolved');
        tx.update(discRef2, { status: 'rejected', authorizedByEmployeeId: 'mgr2' });
      }),
    ]);
    const fulfilled = raceResults.filter((r) => r.status === 'fulfilled').length;
    if (fulfilled !== 1) {
      throw new Error(`Expected exactly 1 winner in concurrent authorization race, got ${fulfilled}`);
    }

    // 2. Payment cancellation & audit log creation
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .doc('restaurants/rest_alpha/orders/ord_alpha_centro/payments/pay_1')
        .set({
          orderId: 'ord_alpha_centro',
          method: 'cash',
          status: 'paid',
          chargedAmount: 100,
        });
    });
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/orders/ord_alpha_centro/payments/pay_1').update({
        status: 'cancelled',
      }),
    );
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/activityLog/log_1').set({
        type: 'payment_cancelled',
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
      }),
    );

    // 3. Purchase cancellation, partner contribution, & stock-out clearing
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/supplierPurchases/sp_centro_1').update({
        status: 'cancelled',
      }),
    );
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/partnerContributions/pc_centro_1').set({
        id: 'pc_centro_1',
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        partnerId: 'part_1',
        amount: 500,
        status: 'active',
      }),
    );
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/productStockOuts/so_centro_1').update({
        status: 'cleared',
      }),
    );

    // 4. Theoretical product recipe write (Backoffice 1.0 schema)
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/productRecipes/prod_1').set({
        productId: 'prod_1',
        productName: 'Taco Pastor',
        recipeStatus: 'complete',
        ingredients: [{ stockItemId: 'ksi_1', quantity: 30, unit: 'g', inputStage: 'cooked' }],
      }),
    );

    // 5. Cash correction DENIED on open session, ALLOWED on closed session + historical expense
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('restaurants/rest_alpha/cashSessions/cs_centro_closed').set({
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        businessDate: '2026-11-25',
        status: 'closed',
      });
    });
    await assertFails(
      dbDoc(mgrDb, 'restaurants/rest_alpha/cashSessions/cs_centro_1').update({
        netDifference: 10,
        status: 'open',
      }),
    );
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/cashSessions/cs_centro_closed').update({
        netDifference: 0,
        status: 'closed',
      }),
    );
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/cashWithdrawalRequests/cw_hist_1').set({
        id: 'cw_hist_1',
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        cashSessionId: 'cs_centro_closed',
        isHistorical: true,
        amount: 120,
        status: 'approved',
      }),
    );
    // Non-historical withdrawal creation from Backoffice MUST fail
    await assertFails(
      dbDoc(mgrDb, 'restaurants/rest_alpha/cashWithdrawalRequests/cw_live_bad').set({
        id: 'cw_live_bad',
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        isHistorical: false,
        amount: 120,
        status: 'approved',
      }),
    );

    // 6. Additive DEV-only budgets/targets isolated by branch & role
    await assertSucceeds(
      dbDoc(mgrDb, 'restaurants/rest_alpha/backofficePurchaseTargets/suc_centro_cogs_vs_sales').set({
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        category: 'cogs_vs_sales',
        targetPer100Sales: 32,
      }),
    );
    await assertFails(
      dbDoc(mgrDb, 'restaurants/rest_alpha/backofficePurchaseTargets/suc_norte_cogs_vs_sales').set({
        restaurantId: 'rest_alpha',
        branchId: 'suc_norte',
        category: 'cogs_vs_sales',
        targetPer100Sales: 32,
      }),
    );
    await assertFails(
      dbDoc(cashOnlyDb, 'restaurants/rest_alpha/backofficeFinanceBudgets/suc_centro_expense_budget').set({
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        budgetType: 'expense_budget',
        amount: 15000,
      }),
    );
  });

  it('Phase 8 security: prevents employee self-escalation, restricts appUpdates to superAdmin, and isolates catalogs', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const adminDb = ctx.firestore();
      await adminDb.doc('restaurants/rest_alpha/authUsers/alpha_emp_mgr').set({
        active: true,
        isSuperAdmin: false,
        employeeId: 'emp_self',
        branchAccess: ['suc_centro'],
        permissions: {
          canViewAdmin: true,
          canManageEmployees: true,
          canManageProducts: true,
          canManageTables: true,
          canManagePlatforms: true,
        },
      });
      await adminDb.doc('restaurants/rest_alpha/authUsers/alpha_super').set({
        active: true,
        isSuperAdmin: true,
        employeeId: 'emp_super',
        permissions: { canViewAdmin: true },
      });
      await adminDb.doc('restaurants/rest_alpha/employees/emp_self').set({
        id: 'emp_self',
        name: 'Manager Self',
        active: true,
        isSuperAdmin: false,
        canManageEmployees: true,
      });
      await adminDb.doc('restaurants/rest_alpha/employees/emp_other').set({
        id: 'emp_other',
        name: 'Other Employee',
        active: true,
        isSuperAdmin: false,
        canManageEmployees: false,
      });
    });

    const empMgrDb = testEnv
      .authenticatedContext('alpha_emp_mgr', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();
    const superDb = testEnv
      .authenticatedContext('alpha_super', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();
    const cashOnlyDb = testEnv
      .authenticatedContext('alpha_cash_only', {
        firebase: { sign_in_provider: 'custom' },
      })
      .firestore();

    // Self-escalation to isSuperAdmin MUST fail
    await assertFails(
      dbDoc(empMgrDb, 'restaurants/rest_alpha/employees/emp_self').update({
        isSuperAdmin: true,
      }),
    );
    // Updating another employee succeeds for canManageEmployees, fails for cashOnlyDb
    await assertSucceeds(
      dbDoc(empMgrDb, 'restaurants/rest_alpha/employees/emp_other').update({
        canManageProducts: true,
      }),
    );
    await assertFails(
      dbDoc(cashOnlyDb, 'restaurants/rest_alpha/employees/emp_other').update({
        canManageProducts: true,
      }),
    );

    // Products, categories, tables, platforms
    await assertSucceeds(
      dbDoc(empMgrDb, 'restaurants/rest_alpha/products/prod_new').set({
        id: 'prod_new',
        name: 'Taco Nuevo',
        price: 35,
        active: true,
      }),
    );
    await assertFails(
      dbDoc(cashOnlyDb, 'restaurants/rest_alpha/products/prod_new').set({
        id: 'prod_new',
        name: 'Bad',
        price: 1,
        active: true,
      }),
    );
    await assertSucceeds(
      dbDoc(empMgrDb, 'restaurants/rest_alpha/tables/tbl_1').set({
        id: 'tbl_1',
        name: 'Mesa 1',
        branchId: 'suc_centro',
        active: true,
      }),
    );
    await assertFails(
      dbDoc(empMgrDb, 'restaurants/rest_alpha/tables/tbl_norte').set({
        id: 'tbl_norte',
        name: 'Mesa Norte',
        branchId: 'suc_norte',
        active: true,
      }),
    );

    // appUpdates strictly restricted to isSuperAdmin
    await assertFails(
      dbDoc(empMgrDb, 'restaurants/rest_alpha/settings/appUpdates').set({
        active: true,
        minimumSupportedVersionCode: 99,
      }),
    );
    await assertSucceeds(
      dbDoc(superDb, 'restaurants/rest_alpha/settings/appUpdates').set({
        active: true,
        minimumSupportedVersionCode: 99,
      }),
    );
  });
});

function dbDoc(db, p) {
  return db.doc(p);
}
