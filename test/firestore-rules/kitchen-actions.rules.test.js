const fs = require('fs');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, writeBatch } = require('firebase/firestore');

const PROJECT_ID = 'demo-kitchen-actions-rules';
const RESTAURANT_ID = 'tacopos';
const BRANCH_ID = 'aviacion';
const ORDER_PATH = `restaurants/${RESTAURANT_ID}/orders/kitchen-action-order`;
const ITEM_PATH = `${ORDER_PATH}/items/item-1`;

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: fs.readFileSync('firestore.rules', 'utf8') },
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, ORDER_PATH), {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      status: 'sent',
      paymentStatus: 'pending',
      kitchenStatus: 'sent',
    });
    await setDoc(doc(db, ITEM_PATH), {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      sendToKitchen: true,
      kitchenStatus: 'sent',
      paymentStatus: 'pending',
    });
  });
});

function db() {
  return testEnv.authenticatedContext('kitchen-user').firestore();
}

async function applyKitchenTransition(status) {
  const firestore = db();
  const batch = writeBatch(firestore);
  batch.update(doc(firestore, ITEM_PATH), { kitchenStatus: status });
  batch.update(doc(firestore, ORDER_PATH), {
    status,
    kitchenStatus: status,
  });
  await assertSucceeds(batch.commit());
  const [order, item] = await Promise.all([
    getDoc(doc(firestore, ORDER_PATH)),
    getDoc(doc(firestore, ITEM_PATH)),
  ]);
  return { order: order.data(), item: item.data() };
}

describe('Firestore rules: kitchen item actions', () => {
  it('persists cooking and ready transitions for an active order', async () => {
    const cooking = await applyKitchenTransition('cooking');
    if (cooking.order.kitchenStatus !== 'cooking' ||
        cooking.item.kitchenStatus !== 'cooking') {
      throw new Error('The cooking transition was not persisted.');
    }

    const ready = await applyKitchenTransition('ready');
    if (ready.order.kitchenStatus !== 'ready' ||
        ready.item.kitchenStatus !== 'ready') {
      throw new Error('The ready transition was not persisted.');
    }
  });

  for (const terminalStatus of ['paid', 'cancelled']) {
    it(`rejects kitchen item changes after an order is ${terminalStatus}`, async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), ORDER_PATH), {
          restaurantId: RESTAURANT_ID,
          branchId: BRANCH_ID,
          status: terminalStatus,
          paymentStatus: terminalStatus === 'paid' ? 'paid' : 'pending',
          kitchenStatus: terminalStatus === 'cancelled' ? 'cancelled' : 'ready',
        });
      });

      const firestore = db();
      await assertFails(
        writeBatch(firestore)
          .update(doc(firestore, ITEM_PATH), { kitchenStatus: 'ready' })
          .commit(),
      );
    });
  }
});
