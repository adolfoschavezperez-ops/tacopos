const fs = require('fs');
const path = require('path');
const assert = require('node:assert/strict');
require('./safeTestEnvironment');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  updateDoc,
} = require('firebase/firestore');

const restaurantId = 'tacopos-release-compat';
const branchA = 'aviacion';
const branchB = 'centro';
const rulesPath = path.resolve(
  __dirname,
  '../../docs/release-candidates/android-2.0.0-rc.1/production-marker-only.rules',
);
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-tacopos-2rc-production-rules',
    firestore: {rules: fs.readFileSync(rulesPath, 'utf8')},
  });
});

after(async () => env?.cleanup());

beforeEach(async () => env.clearFirestore());

const clientDb = () => env.authenticatedContext('android-31-device').firestore();
const restaurantPath = `restaurants/${restaurantId}`;

describe('RC 2.0 compatibility with deployed Rules baseline plus marker guard', () => {
  it('+31 ordinary activity events remain writable; 2.0 clients cannot forge submission markers', async () => {
    const db = clientDb();
    await assertSucceeds(setDoc(
      doc(db, `${restaurantPath}/activityLog/payment_cancelled_order1_payment1`),
      {restaurantId, branchId: branchA, type: 'payment_cancelled'},
    ));

    await assertFails(setDoc(
      doc(db, `${restaurantPath}/activityLog/capture_submission_forged`),
      {restaurantId, branchId: branchA, orderId: 'order1', payloadHash: 'forged'},
    ));

    const serverMarkerPath = `${restaurantPath}/activityLog/capture_submission_server`;
    await env.withSecurityRulesDisabled((context) => setDoc(
      doc(context.firestore(), serverMarkerPath),
      {restaurantId, branchId: branchA, status: 'committed'},
    ));
    await assertFails(updateDoc(doc(db, serverMarkerPath), {status: 'aborted'}));
    await assertFails(deleteDoc(doc(db, serverMarkerPath)));
    const stored = await getDoc(doc(db, serverMarkerPath));
    assert.equal(stored.data().status, 'committed');
  });

  it('+31 capture, kitchen actions, extras and branch-specific orders remain writable', async () => {
    const db = clientDb();
    const orderAPath = `${restaurantPath}/orders/order-aviacion`;
    const firstItemPath = `${orderAPath}/items/item-first`;
    await assertSucceeds(setDoc(doc(db, orderAPath), {
      restaurantId,
      branchId: branchA,
      status: 'open',
      paymentStatus: 'pending',
      orderType: 'dine_in',
      total: 40,
    }));
    await assertSucceeds(setDoc(doc(db, firstItemPath), {
      restaurantId,
      branchId: branchA,
      productId: 'pastor',
      quantity: 2,
      kitchenBatchId: 'batch-1',
      kitchenStatus: 'pending',
    }));
    await assertSucceeds(updateDoc(doc(db, orderAPath), {status: 'sent'}));
    await assertSucceeds(updateDoc(doc(db, firstItemPath), {kitchenStatus: 'ready'}));

    await assertSucceeds(setDoc(doc(db, `${orderAPath}/items/item-extra`), {
      restaurantId,
      branchId: branchA,
      productId: 'asada',
      quantity: 1,
      kitchenBatchId: 'batch-2',
      kitchenStatus: 'pending',
      isExtra: true,
    }));
    await assertSucceeds(updateDoc(doc(db, orderAPath), {total: 60}));

    const orderBPath = `${restaurantPath}/orders/order-centro`;
    await assertSucceeds(setDoc(doc(db, orderBPath), {
      restaurantId,
      branchId: branchB,
      status: 'open',
      paymentStatus: 'pending',
      orderType: 'takeout',
      total: 20,
    }));
    await assertFails(updateDoc(doc(db, orderAPath), {branchId: branchB}));
  });

  it('+31 partial/final payments and normal cash close remain writable', async () => {
    const db = clientDb();
    const cashSessionPath = `${restaurantPath}/cashSessions/cash-1`;
    const orderPath = `${restaurantPath}/orders/order-payment`;
    await assertSucceeds(setDoc(doc(db, cashSessionPath), {
      restaurantId,
      branchId: branchA,
      status: 'open',
    }));
    await assertSucceeds(setDoc(doc(db, orderPath), {
      restaurantId,
      branchId: branchA,
      status: 'open',
      paymentStatus: 'pending',
      total: 100,
    }));

    await assertSucceeds(setDoc(doc(db, `${orderPath}/payments/payment-partial`), {
      restaurantId,
      branchId: branchA,
      cashSessionId: 'cash-1',
      status: 'active',
      method: 'cash',
      appliedAmount: 40,
      chargedAmount: 40,
    }));
    await assertSucceeds(updateDoc(doc(db, orderPath), {
      paymentStatus: 'partial',
      pendingTotal: 60,
    }));

    await assertSucceeds(setDoc(doc(db, `${orderPath}/payments/payment-final`), {
      restaurantId,
      branchId: branchA,
      cashSessionId: 'cash-1',
      status: 'active',
      method: 'card',
      appliedAmount: 60,
      chargedAmount: 62.4,
    }));
    await assertSucceeds(updateDoc(doc(db, orderPath), {
      status: 'paid',
      paymentStatus: 'paid',
      pendingTotal: 0,
    }));
    await assertSucceeds(updateDoc(doc(db, cashSessionPath), {
      status: 'closed',
      expectedCash: 40,
      expectedCardCharged: 62.4,
      netDifference: 0,
    }));
  });
});
