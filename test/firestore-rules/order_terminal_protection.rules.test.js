require('./safeTestEnvironment');
const { strict: assert } = require('node:assert');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, deleteDoc, writeBatch, Timestamp } = require('firebase/firestore');
const fs = require('node:fs');

const restaurantId = 'tacopos-terminal-protection';
const branchId = 'aviacion';
const root = `restaurants/${restaurantId}`;
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-tacopos-order-terminal-protection',
    firestore: { rules: fs.readFileSync('firestore.rules', 'utf8') },
  });
});
after(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

const db = (uid = 'waiter') => env.authenticatedContext(uid).firestore();
const path = (relative) => `${root}/${relative}`;
const seed = (relative, data) => env.withSecurityRulesDisabled((context) =>
  setDoc(doc(context.firestore(), path(relative)), data));

async function seedOrder({ id = 'order', status = 'open', paymentStatus = 'pending', extra = {} } = {}) {
  await seed(`orders/${id}`, {
    restaurantId,
    branchId,
    orderType: 'dine_in',
    status,
    kitchenStatus: 'sent',
    paymentStatus,
    total: 100,
    grossSubtotal: 100,
    netTotal: 100,
    paidTotal: 0,
    pendingTotal: 100,
    captureRevision: 0,
    ...extra,
  });
}

async function seedItem(orderId = 'order', itemId = 'item') {
  await seed(`orders/${orderId}/items/${itemId}`, {
    restaurantId,
    branchId,
    productId: 'pastor',
    status: 'active',
    kitchenStatus: 'sent',
    paymentStatus: 'pending',
    qty: 1,
    unitPrice: 100,
    total: 100,
  });
}

describe('terminal order write protection', () => {
  it('allows ordinary capture only when the parent revision advances atomically', async () => {
    await seedOrder();
    const d = db();
    const batch = writeBatch(d);
    batch.set(doc(d, path('orders/order/items/new-item')), {
      restaurantId, branchId, productId: 'asada', status: 'active',
      paymentStatus: 'pending', kitchenStatus: 'pending', qty: 1, total: 20,
    });
    batch.update(doc(d, path('orders/order')), { captureRevision: 1 });
    await assertSucceeds(batch.commit());
  });

  it('rejects stale capture, quantity edits and deletion after payment', async () => {
    await seedOrder({ status: 'paid', paymentStatus: 'paid', extra: {
      paidAt: Timestamp.fromMillis(1), pendingTotal: 0, paidTotal: 100,
    }});
    await seedItem();
    const d = db();
    await assertFails(setDoc(doc(d, path('orders/order/items/late')), {
      restaurantId, branchId, productId: 'asada', status: 'active',
      paymentStatus: 'pending', qty: 1, total: 20,
    }));
    await assertFails(updateDoc(doc(d, path('orders/order/items/item')), {
      qty: 2, total: 200,
    }));
    await assertFails(deleteDoc(doc(d, path('orders/order/items/item'))));
    await assertFails(updateDoc(doc(d, path('orders/order')), {
      status: 'open', paymentStatus: 'pending', paidAt: null,
    }));
  });

  it('protects historical terminal documents without the newer fields', async () => {
    await seedOrder({ id: 'old-paid', status: 'ready', paymentStatus: 'partial', extra: {
      closedAt: Timestamp.fromMillis(1),
    }});
    await seedOrder({ id: 'old-cancelled', status: 'cancelada', paymentStatus: 'pending' });
    await seedItem('old-paid');
    await seedItem('old-cancelled');
    const d = db();
    await assertFails(setDoc(doc(d, path('orders/old-paid/items/late')), {
      restaurantId, branchId, productId: 'suadero', status: 'active',
      paymentStatus: 'pending', qty: 1, total: 25,
    }));
    await assertFails(updateDoc(doc(d, path('orders/old-cancelled/items/item')), {
      qty: 2, total: 200,
    }));
  });

  it('rejects an atomic batch that both closes an order and appends an item', async () => {
    await seedOrder();
    const d = db();
    const batch = writeBatch(d);
    batch.set(doc(d, path('orders/order/items/racing-item')), {
      restaurantId, branchId, productId: 'lengua', status: 'active',
      paymentStatus: 'pending', qty: 1, total: 25,
    });
    batch.update(doc(d, path('orders/order')), {
      status: 'paid', paymentStatus: 'paid', paidAt: Timestamp.fromMillis(5),
      paidTotal: 100, pendingTotal: 0, captureRevision: 1,
    });
    await assertFails(batch.commit());
  });

  it('allows the existing atomic final-payment shape without changing its financial fields', async () => {
    await seedOrder();
    await seedItem();
    await seed('cashSessions/cash', { restaurantId, branchId, status: 'open' });
    const d = db();
    const now = Timestamp.fromMillis(10);
    const batch = writeBatch(d);
    batch.set(doc(d, path('orders/order/payments/pay-1')), {
      restaurantId, branchId, orderId: 'order', status: 'active',
      method: 'cash', baseAmount: 100, cashSessionId: 'cash',
    });
    batch.update(doc(d, path('orders/order/items/item')), {
      paymentStatus: 'paid', paymentId: 'pay-1', paidAt: now,
    });
    batch.update(doc(d, path('orders/order')), {
      status: 'paid', paymentStatus: 'paid', paidAt: now,
      paidTotal: 100, pendingTotal: 0, captureRevision: 1,
    });
    await assertSucceeds(batch.commit());
  });

  it('rejects payments created after a terminal order and permits a partial payment on an active order', async () => {
    await seedOrder({ id: 'paid', status: 'paid', paymentStatus: 'paid', extra: {
      paidAt: Timestamp.fromMillis(1), pendingTotal: 0,
    }});
    await seedOrder({ id: 'active' });
    await seed('cashSessions/cash', { restaurantId, branchId, status: 'open' });
    const d = db();
    await assertFails(setDoc(doc(d, path('orders/paid/payments/late')), {
      restaurantId, branchId, orderId: 'paid', status: 'active', method: 'cash',
      baseAmount: 20, cashSessionId: 'cash',
    }));
    const batch = writeBatch(d);
    batch.set(doc(d, path('orders/active/payments/partial')), {
      restaurantId, branchId, orderId: 'active', status: 'active', method: 'cash',
      baseAmount: 20, cashSessionId: 'cash',
    });
    batch.update(doc(d, path('orders/active')), {
      paymentStatus: 'partial', paidTotal: 20, pendingTotal: 80, captureRevision: 1,
    });
    await assertSucceeds(batch.commit());
  });
});
