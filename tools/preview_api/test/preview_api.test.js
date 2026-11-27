const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const { createPreviewServer } = require('../server');

describe('Preview Read-Only API (Emulator + HTTP Integration)', function () {
  this.timeout(20000);

  let app;
  let db;
  let server;
  let baseUrl;

  const OWNER_UID = 'owner_preview_uid';
  const OWNER_EMAIL = 'owner@los-padrinos.test';
  const OTHER_UID = 'other_user_uid';
  const OTHER_EMAIL = 'staff@los-padrinos.test';
  const REVOKED_UID = 'revoked_owner_uid';
  const REVOKED_EMAIL = 'revoked@los-padrinos.test';

  const fakeAuth = {
    async verifyIdToken(token, checkRevoked) {
      assert.equal(checkRevoked, true);
      if (token === 'token_owner') return { uid: OWNER_UID, email: OWNER_EMAIL };
      if (token === 'token_other') return { uid: OTHER_UID, email: OTHER_EMAIL };
      if (token === 'token_revoked') return { uid: REVOKED_UID, email: REVOKED_EMAIL };
      throw new Error('Invalid token');
    },
  };

  before(async () => {
    if (!process.env.FIRESTORE_EMULATOR_HOST) {
      throw new Error('FIRESTORE_EMULATOR_HOST must be set for Preview API tests.');
    }
    app = admin.initializeApp({ projectId: 'demo-tacopos-preview-api' }, 'preview-api-test');
    db = app.firestore();

    // Seed synthetic data including plaintext PIN on employee doc
    await db.doc('restaurants/rest_alpha').set({ name: 'Los Padrinos' });
    await db.doc(`restaurants/rest_alpha/authUsers/${OWNER_UID}`).set({
      active: true,
      isSuperAdmin: false,
      employeeId: 'emp_owner',
      branchAccess: ['suc_centro'],
      permissions: { canViewAdmin: true },
    });
    await db.doc(`restaurants/rest_alpha/authUsers/${REVOKED_UID}`).set({
      active: true,
      isSuperAdmin: false,
      employeeId: 'emp_revoked',
      branchAccess: ['suc_centro'],
    });
    await db.doc('restaurants/rest_alpha/employees/emp_owner').set({
      id: 'emp_owner',
      restaurantId: 'rest_alpha',
      name: 'Propietario',
      active: true,
      pin: 'SECRET_PIN_DO_NOT_LEAK',
      passwordHash: 'SECRET_HASH',
      canViewAdmin: true,
    });
    await db.doc('restaurants/rest_alpha/employees/emp_revoked').set({
      id: 'emp_revoked',
      restaurantId: 'rest_alpha',
      name: 'Revocado',
      active: false,
      pin: '0000',
    });
    await db.doc('restaurants/rest_alpha/orders/ord_1').set({
      restaurantId: 'rest_alpha',
      branchId: 'suc_centro',
      businessDate: '2026-11-27',
      total: 450,
      status: 'paid',
    });
    await db.doc('restaurants/rest_alpha/orders/ord_norte').set({
      restaurantId: 'rest_alpha',
      branchId: 'suc_norte',
      businessDate: '2026-11-27',
      total: 900,
      status: 'paid',
    });
    await db.doc('restaurants/rest_beta/orders/ord_beta').set({
      restaurantId: 'rest_beta',
      branchId: 'suc_sur',
      businessDate: '2026-11-27',
      total: 300,
    });

    server = createPreviewServer({
      auth: fakeAuth,
      db,
      ownerAllowlist: new Set([OWNER_EMAIL, REVOKED_EMAIL]),
      maxDocsPerQuery: 50,
    });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    const addr = server.address();
    baseUrl = `http://127.0.0.1:${addr.port}`;
  });

  after(async () => {
    if (server) await new Promise((resolve) => server.close(resolve));
    if (app) await app.delete();
  });

  async function postJson(path, token, body) {
    const headers = { 'Content-Type': 'application/json' };
    if (token) headers.Authorization = `Bearer ${token}`;
    const res = await fetch(`${baseUrl}${path}`, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
    });
    return { status: res.status, data: await res.json() };
  }

  it('allows authorized owner to query authorized branch and strips PIN/secrets from employees', async () => {
    const ordersRes = await postJson('/v1/preview/query', 'token_owner', {
      restaurantId: 'rest_alpha',
      collection: 'orders',
      branchId: 'suc_centro',
    });
    assert.equal(ordersRes.status, 200);
    assert.equal(ordersRes.data.docs.length, 1);
    assert.equal(ordersRes.data.docs[0].id, 'ord_1');

    // Employees projection MUST strip pin and passwordHash
    const empRes = await postJson('/v1/preview/query', 'token_owner', {
      restaurantId: 'rest_alpha',
      collection: 'employees',
    });
    assert.equal(empRes.status, 200);
    const ownerEmp = empRes.data.docs.find((e) => e.id === 'emp_owner');
    assert.ok(ownerEmp);
    assert.equal(ownerEmp.name, 'Propietario');
    assert.equal('pin' in ownerEmp, false);
    assert.equal('passwordHash' in ownerEmp, false);
  });

  it('rejects unauthenticated, non-allowlisted, and revoked users', async () => {
    const unauth = await postJson('/v1/preview/query', null, {
      restaurantId: 'rest_alpha',
      collection: 'orders',
    });
    assert.equal(unauth.status, 401);

    const nonOwner = await postJson('/v1/preview/query', 'token_other', {
      restaurantId: 'rest_alpha',
      collection: 'orders',
    });
    assert.equal(nonOwner.status, 403);

    const revoked = await postJson('/v1/preview/query', 'token_revoked', {
      restaurantId: 'rest_alpha',
      collection: 'orders',
      branchId: 'suc_centro',
    });
    assert.equal(revoked.status, 403);
    assert.equal(revoked.data.code, 'EMPLOYEE_REVOKED');
  });

  it('blocks unauthorized restaurant, unauthorized branch, and authUsers collection', async () => {
    const crossRest = await postJson('/v1/preview/query', 'token_owner', {
      restaurantId: 'rest_beta',
      collection: 'orders',
    });
    assert.equal(crossRest.status, 403);

    const crossBranch = await postJson('/v1/preview/query', 'token_owner', {
      restaurantId: 'rest_alpha',
      collection: 'orders',
      branchId: 'suc_norte',
    });
    assert.equal(crossBranch.status, 403);

    const authUsersRes = await postJson('/v1/preview/query', 'token_owner', {
      restaurantId: 'rest_alpha',
      collection: 'authUsers',
    });
    assert.equal(authUsersRes.status, 403);
  });

  it('rejects all HTTP write methods and non-read endpoints', async () => {
    for (const method of ['PUT', 'PATCH', 'DELETE']) {
      const res = await fetch(`${baseUrl}/v1/preview/query`, {
        method,
        headers: {
          Authorization: 'Bearer token_owner',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ restaurantId: 'rest_alpha', collection: 'orders' }),
      });
      assert.equal(res.status, 405);
    }

    const writePath = await postJson('/v1/preview/write', 'token_owner', {
      restaurantId: 'rest_alpha',
      collection: 'orders',
    });
    assert.equal(writePath.status, 404);
  });
});
