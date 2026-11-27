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
});
