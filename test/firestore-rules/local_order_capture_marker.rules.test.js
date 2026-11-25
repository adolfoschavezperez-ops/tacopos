const fs = require('fs');
const { strict: assert } = require('assert');
require('./safeTestEnvironment');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { deleteDoc, doc, getDoc, setDoc, updateDoc } = require('firebase/firestore');

const rulesPath = process.env.TACOPOS_RULES_FILE || 'firestore.rules';

const R = 'tacopos';
const B = 'aviacion';
const root = `restaurants/${R}`;
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-local-order-capture-marker',
    firestore: { rules: fs.readFileSync(rulesPath, 'utf8') },
  });
});
after(async () => env?.cleanup());

const db = (uid = 'waiter') => env.authenticatedContext(uid).firestore();
const path = (id) => `${root}/activityLog/${id}`;

describe('local order capture idempotency marker', () => {
  beforeEach(async () => env.clearFirestore());

  it('rejects a signed-in client trying to forge a callable acknowledgement', async () => {
    const forged = doc(db(), path('capture_submission_known-id'));
    await assertFails(setDoc(forged, {
      restaurantId: R,
      branchId: B,
      orderId: 'order-1',
      payloadHash: 'attacker-controlled',
      createdBy: 'waiter',
      result: { orderId: 'order-1', acceptedLines: 1 },
    }));

    // The reserved ID remains inaccessible to clients after a server write.
    await env.withSecurityRulesDisabled((context) => setDoc(
      doc(context.firestore(), path('capture_submission_server-id')),
      { restaurantId: R, branchId: B, createdBy: 'waiter', result: { ok: true } },
    ));
    await assertFails(updateDoc(doc(db(), path('capture_submission_server-id')), { result: { ok: false } }));
    await assertFails(deleteDoc(doc(db(), path('capture_submission_server-id'))));
    const stored = await getDoc(doc(db(), path('capture_submission_server-id')));
    assert.equal(stored.exists(), true);
    assert.deepEqual(stored.data().result, { ok: true });
  });

  it('preserves creation of ordinary activityLog events', async () => {
    await assertSucceeds(setDoc(doc(db(), path('payment_cancelled_o1_p1')), {
      restaurantId: R,
      branchId: B,
      type: 'payment_cancelled',
    }));
  });
});
