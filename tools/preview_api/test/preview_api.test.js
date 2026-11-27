const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const { createPreviewServer } = require('../server');

describe('Preview Read-Only API 9.1.2 (Separated Auth/Authz/Data + Real Cursor Pagination + Projections)', function () {
  this.timeout(30000);

  let authApp;
  let dataApp;
  let auth;
  let authzDb;
  let dataDb;
  let server;
  let baseUrl;

  const OWNER_UID = 'preview_owner_uid';
  const OWNER_EMAIL = 'owner@los-padrinos.test';
  const REVOKED_UID = 'preview_revoked_uid';
  const REVOKED_EMAIL = 'revoked@los-padrinos.test';
  const MISSING_EMP_UID = 'preview_missing_emp_uid';

  let ownerIdToken = '';

  async function mintIdTokenForCustomToken(uid) {
    const customToken = await auth.createCustomToken(uid);
    const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
    const res = await fetch(
      `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake-key`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: customToken, returnSecureToken: true }),
      },
    );
    const json = await res.json();
    assert.ok(json.idToken, `Expected idToken for ${uid}, got ${JSON.stringify(json)}`);
    return json.idToken;
  }

  before(async () => {
    if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
      throw new Error('FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST must be set.');
    }

    // Separate Auth/Authz app vs Operational Data app
    authApp = admin.initializeApp({ projectId: 'demo-tacopos-preview-api' }, 'preview-auth-test');
    dataApp = admin.initializeApp({ projectId: 'demo-tacopos-preview-data' }, 'preview-data-test');
    auth = authApp.auth();
    authzDb = authApp.firestore();
    dataDb = dataApp.firestore();

    // Create real users in Firebase Auth Emulator
    for (const u of [
      { uid: OWNER_UID, email: OWNER_EMAIL },
      { uid: REVOKED_UID, email: REVOKED_EMAIL },
      { uid: MISSING_EMP_UID, email: 'missing@los-padrinos.test' },
    ]) {
      try {
        await auth.deleteUser(u.uid);
      } catch (_) {}
      await auth.createUser({ uid: u.uid, email: u.email, password: 'EvalTestOnlyPassword!' });
    }
    ownerIdToken = await mintIdTokenForCustomToken(OWNER_UID);

    // Seed Authz DB (`previewUsers/{uid}` ONLY — completely separated from operational data)
    await authzDb.doc(`previewUsers/${OWNER_UID}`).set({
      uid: OWNER_UID,
      active: true,
      isSuperAdmin: false,
      employeeId: 'emp_owner',
      restaurantId: 'rest_alpha',
      restaurantAccess: ['rest_alpha'],
      branchAccess: ['suc_centro'],
      permissions: { canViewAdmin: true },
    });
    await authzDb.doc(`previewUsers/${REVOKED_UID}`).set({
      uid: REVOKED_UID,
      active: true,
      isSuperAdmin: false,
      employeeId: 'emp_owner',
      restaurantId: 'rest_alpha',
      restaurantAccess: ['rest_alpha'],
      branchAccess: ['suc_centro'],
    });
    await authzDb.doc(`previewUsers/${MISSING_EMP_UID}`).set({
      uid: MISSING_EMP_UID,
      active: true,
      employeeId: 'emp_does_not_exist',
      restaurantId: 'rest_alpha',
      restaurantAccess: ['rest_alpha'],
      branchAccess: ['suc_centro'],
    });

    // Seed Operational Data DB (separate project!)
    await dataDb.doc('restaurants/rest_alpha').set({ name: 'Los Padrinos Real' });
    await dataDb.doc('restaurants/rest_alpha/branches/suc_centro').set({
      id: 'suc_centro',
      name: 'Centro',
      active: true,
      sortOrder: 1,
    });
    await dataDb.doc('restaurants/rest_alpha/branches/suc_norte').set({
      id: 'suc_norte',
      name: 'Norte',
      active: true,
      sortOrder: 2,
    });
    await dataDb.doc('restaurants/rest_alpha/employees/emp_owner').set({
      id: 'emp_owner',
      restaurantId: 'rest_alpha',
      name: 'Propietario',
      active: true,
      pin: 'SECRET_PIN_NEVER_SEND',
      passwordHash: 'SECRET_HASH',
      canViewAdmin: true,
    });
    await dataDb.doc('restaurants/rest_alpha/devices/dev_1').set({
      deviceId: 'dev_1',
      deviceName: 'Caja 1',
      branchId: 'suc_centro',
      fcmToken: 'SECRET_FCM_TOKEN',
      authToken: 'SECRET_AUTH_TOKEN',
      active: true,
    });
    await dataDb.doc('restaurants/rest_alpha/activityLog/log_1').set({
      type: 'order_cancelled',
      restaurantId: 'rest_alpha',
      branchId: 'suc_centro',
      submissionId: 'INTERNAL_SUB_ID',
      localCapture: true,
      payloadHash: 'INTERNAL_HASH',
      message: 'Cancelado',
    });
    await dataDb.doc('restaurants/rest_alpha/settings/secretKeys').set({
      apiKey: 'SHOULD_NOT_BE_EXPOSED',
    });
    await dataDb.doc('restaurants/rest_alpha/orders/ord_centro').set({
      restaurantId: 'rest_alpha',
      branchId: 'suc_centro',
      businessDate: '2026-11-27',
      total: 8000,
      status: 'paid',
    });
    await dataDb.doc('restaurants/rest_alpha/orders/ord_centro/payments/pay_1').set({
      orderId: 'ord_centro',
      method: 'card',
      amount: 8000,
      status: 'paid',
      cardToken: 'SECRET_CARD_TOKEN',
      rawResponse: 'RAW_GATEWAY_SECRET',
    });
    await dataDb.doc('restaurants/rest_alpha/orders/ord_norte').set({
      restaurantId: 'rest_alpha',
      branchId: 'suc_norte',
      businessDate: '2026-11-27',
      total: 900,
      status: 'paid',
    });
    await dataDb.doc('restaurants/rest_alpha/orders/ord_norte/payments/pay_norte').set({
      orderId: 'ord_norte',
      amount: 900,
    });
    await dataDb.doc('restaurants/rest_alpha/orders/ord_ambiguous').set({
      restaurantId: 'rest_alpha',
      businessDate: '2026-11-27',
      total: 100,
    });
    await dataDb.doc('restaurants/rest_alpha/orders/ord_ambiguous/items/it_1').set({
      name: 'Taco',
    });

    // Seed 550 purchaseItems for cursor pagination test (>500 docs)
    let batch = dataDb.batch();
    for (let i = 1; i <= 550; i++) {
      const id = `pi_${String(i).padStart(4, '0')}`;
      batch.set(dataDb.doc(`restaurants/rest_alpha/purchaseItems/${id}`), {
        id,
        name: `Insumo ${i}`,
        active: true,
      });
      if (i % 400 === 0) {
        await batch.commit();
        batch = dataDb.batch();
      }
    }
    await batch.commit();

    server = createPreviewServer({
      auth,
      authzDb,
      dataDb,
      allowedOrigins: ['https://preview.tacopos.test'],
      maxDocsPerQuery: 100,
      maxRequestsPerMin: 60,
      maxConcurrentPerUid: 6,
      maxDaysRange: 31,
    });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(async () => {
    if (server) await new Promise((resolve) => server.close(resolve));
    if (authApp) await authApp.delete();
    if (dataApp) await dataApp.delete();
  });

  async function postJson(path, token, body, origin = 'https://preview.tacopos.test') {
    const headers = { 'Content-Type': 'application/json', Origin: origin };
    if (token) headers.Authorization = `Bearer ${token}`;
    const res = await fetch(`${baseUrl}${path}`, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
    });
    return { status: res.status, data: await res.json() };
  }

  it('bootstraps session via /v1/preview/session from separated authzDb & dataDb', async () => {
    const res = await postJson('/v1/preview/session', ownerIdToken, {
      restaurantId: 'rest_alpha',
    });
    assert.equal(res.status, 200);
    assert.equal(res.data.restaurant.name, 'Los Padrinos Real');
    assert.equal(res.data.branches.length, 1);
    assert.equal(res.data.branches[0].id, 'suc_centro');
  });

  it('enforces parent-doc branch authorization & ambiguous scope denial on subcollections', async () => {
    const ok = await postJson('/v1/preview/query', ownerIdToken, {
      restaurantId: 'rest_alpha',
      collection: 'orders',
      parentDocId: 'ord_centro',
      subcollection: 'payments',
    });
    assert.equal(ok.status, 200);
    assert.equal(ok.data.docs.length, 1);
    assert.equal('cardToken' in ok.data.docs[0], false);
    assert.equal('rawResponse' in ok.data.docs[0], false);

    const deniedNorte = await postJson('/v1/preview/query', ownerIdToken, {
      restaurantId: 'rest_alpha',
      collection: 'orders',
      parentDocId: 'ord_norte',
      subcollection: 'payments',
    });
    assert.equal(deniedNorte.status, 403);
    assert.equal(deniedNorte.data.code, 'PARENT_BRANCH_ACCESS_DENIED');

    const deniedAmbiguous = await postJson('/v1/preview/query', ownerIdToken, {
      restaurantId: 'rest_alpha',
      collection: 'orders',
      parentDocId: 'ord_ambiguous',
      subcollection: 'items',
    });
    assert.equal(deniedAmbiguous.status, 403);
    assert.equal(deniedAmbiguous.data.code, 'AMBIGUOUS_PARENT_SCOPE');

    const badSegment = await postJson('/v1/preview/query', ownerIdToken, {
      restaurantId: 'rest_alpha',
      collection: 'orders',
      parentDocId: '../other',
      subcollection: 'items',
    });
    assert.equal(badSegment.status, 400);
  });

  it('applies explicit secret projections on employees, devices, activityLog, and settings', async () => {
    const empRes = await postJson('/v1/preview/query', ownerIdToken, {
      restaurantId: 'rest_alpha',
      collection: 'employees',
    });
    assert.equal(empRes.status, 200);
    assert.equal('pin' in empRes.data.docs[0], false);
    assert.equal('passwordHash' in empRes.data.docs[0], false);

    const devRes = await postJson('/v1/preview/query', ownerIdToken, {
      restaurantId: 'rest_alpha',
      collection: 'devices',
    });
    assert.equal(devRes.status, 200);
    assert.equal('fcmToken' in devRes.data.docs[0], false);
    assert.equal('authToken' in devRes.data.docs[0], false);

    const actRes = await postJson('/v1/preview/query', ownerIdToken, {
      restaurantId: 'rest_alpha',
      collection: 'activityLog',
    });
    assert.equal(actRes.status, 200);
    assert.equal('submissionId' in actRes.data.docs[0], false);
    assert.equal('localCapture' in actRes.data.docs[0], false);
    assert.equal('payloadHash' in actRes.data.docs[0], false);

    const secSetting = await postJson('/v1/preview/doc', ownerIdToken, {
      restaurantId: 'rest_alpha',
      collection: 'settings',
      docId: 'secretKeys',
    });
    assert.equal(secSetting.status, 200);
    assert.equal(secSetting.data.doc.restricted, true);
    assert.equal('apiKey' in secSetting.data.doc, false);
  });

  it('paginates >500 documents deterministically via nextCursor and rejects tampered cursors', async () => {
    const collectedIds = [];
    let cursor = null;
    let pages = 0;
    do {
      const res = await postJson('/v1/preview/query', ownerIdToken, {
        restaurantId: 'rest_alpha',
        collection: 'purchaseItems',
        limit: 100,
        ...(cursor ? { cursor } : {}),
      });
      assert.equal(res.status, 200);
      for (const d of res.data.docs) collectedIds.push(d.id);
      cursor = res.data.nextCursor;
      pages += 1;
    } while (cursor);

    assert.equal(pages, 6);
    assert.equal(collectedIds.length, 550);
    assert.equal(new Set(collectedIds).size, 550);

    // Tampered cursor with mismatched filterHash MUST fail
    const badCursor = await postJson('/v1/preview/query', ownerIdToken, {
      restaurantId: 'rest_alpha',
      collection: 'purchaseItems',
      limit: 100,
      cursor: { filterHash: 'tampered', lastDocId: 'pi_0100' },
    });
    assert.equal(badCursor.status, 400);
    assert.equal(badCursor.data.code, 'INVALID_CURSOR');
  });

  it('rejects revoked Firebase Auth tokens, missing linked employees, unauthorized CORS, and excessive date ranges', async () => {
    const missingEmpToken = await mintIdTokenForCustomToken(MISSING_EMP_UID);
    const missingEmpRes = await postJson('/v1/preview/session', missingEmpToken, {
      restaurantId: 'rest_alpha',
    });
    assert.equal(missingEmpRes.status, 403);
    assert.equal(missingEmpRes.data.code, 'EMPLOYEE_INACTIVE_OR_MISSING');

    const badOrigin = await postJson('/v1/preview/session', ownerIdToken, {
      restaurantId: 'rest_alpha',
    }, 'https://evil.attacker.test');
    assert.equal(badOrigin.status, 403);

    const bigRange = await postJson('/v1/preview/query', ownerIdToken, {
      restaurantId: 'rest_alpha',
      collection: 'orders',
      startBusinessDate: '2026-01-01',
      endBusinessDate: '2026-11-27',
    });
    assert.equal(bigRange.status, 400);
    assert.equal(bigRange.data.code, 'INVALID_OR_EXCESSIVE_DATE_RANGE');

    // Real Firebase Auth token revocation test
    const revToken = await mintIdTokenForCustomToken(REVOKED_UID);
    const beforeRevoke = await postJson('/v1/preview/session', revToken, {
      restaurantId: 'rest_alpha',
    });
    assert.equal(beforeRevoke.status, 200);

    await new Promise((r) => setTimeout(r, 1100));
    await auth.revokeRefreshTokens(REVOKED_UID);
    const afterRevoke = await postJson('/v1/preview/session', revToken, {
      restaurantId: 'rest_alpha',
    });
    assert.equal(afterRevoke.status, 401);
    assert.equal(afterRevoke.data.code, 'INVALID_OR_REVOKED_TOKEN');
  });
});
