// Table releases carry the device's branch fields (`_currentBranchFields`),
// including restaurantName. These tests replay the real payloads of final
// checkout, change table and order cancellation against tables whose
// restaurantName is missing or differs, and prove it cannot be set freely.
require('./safeTestEnvironment');
const fs = require('fs');
const { strict: assert } = require('assert');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const {
  deleteField, doc, getDoc, increment, runTransaction, serverTimestamp, setDoc, updateDoc, writeBatch,
} = require('firebase/firestore');

const RESTAURANT_ID = 'tacopos';
const BRANCH_ID = 'aviacion';
const RESTAURANT_NAME = "Los Padrino's Tacos";
const root = `restaurants/${RESTAURANT_ID}`;

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-tables-restaurant-name',
    firestore: { rules: fs.readFileSync('firestore.rules', 'utf8') },
  });
});
after(async () => env?.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await seed('cashSessions/cs1', { restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, status: 'open' });
  await seed(`branches/${BRANCH_ID}`, {
    restaurantId: RESTAURANT_ID, restaurantName: RESTAURANT_NAME, name: 'Aviacion', active: true,
  });
});

const path = (relative) => `${root}/${relative}`;
async function seed(relative, data) {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), path(relative)), data));
}
async function read(relative) {
  let data;
  await env.withSecurityRulesDisabled(async (ctx) => {
    data = (await getDoc(doc(ctx.firestore(), path(relative)))).data();
  });
  return data;
}
const db = (uid = 'device') => env.authenticatedContext(uid).firestore();
const ref = (d, relative) => doc(d, path(relative));

// Mirrors TacoPosRepository._currentBranchFields.
const branchFields = (restaurantName = RESTAURANT_NAME) => ({
  restaurantId: RESTAURANT_ID, restaurantName, branchId: BRANCH_ID, branchName: 'Aviacion',
});
// Mirrors _releaseLinkedTablesInTransaction / _setLinkedTablesStateInBatch(release: true).
const releasePayload = (restaurantName = RESTAURANT_NAME) => ({
  status: 'available', currentOrderId: null, currentOrderStatus: null, tableGroupId: null,
  tableGroupLabel: null, groupPrimaryTableId: null, occupiedAt: null,
  ...branchFields(restaurantName), updatedAt: serverTimestamp(),
});
const openOrder = (fields = {}) => ({
  restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, restaurantName: RESTAURANT_NAME,
  status: 'ready', paymentStatus: 'pending', kitchenStatus: 'ready', orderType: 'dine_in',
  tableId: 't1', tableIds: ['t1'], total: 300, grossSubtotal: 300, netTotal: 300,
  paidTotal: 0, pendingTotal: 300, captureRevision: 3, cashSessionId: 'cs1', ...fields,
});
const tableVariants = {
  'con restaurantName igual': { restaurantName: RESTAURANT_NAME },
  'sin restaurantName': {},
  'con restaurantName distinto': { restaurantName: 'Nombre anterior' },
};
async function seedOccupiedTable(id, variant, orderId = 'o1') {
  await seed(`tables/${id}`, {
    restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, branchName: 'Aviacion', name: id,
    status: 'occupied', currentOrderId: orderId, currentOrderStatus: 'ready', ...variant,
  });
}
async function seedOrderWithItem(fields = {}) {
  await seed('orders/o1', openOrder(fields));
  await seed('orders/o1/items/i1', {
    restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, status: 'active', paymentStatus: 'pending',
    kitchenStatus: 'ready', qty: 1, unitPrice: 300, total: 300,
  });
}

// Real final checkout payload (_finalizeSaleWithDailyFolio without daily folio).
function finalCheckout(d, { restaurantName = RESTAURANT_NAME, tableRelease } = {}) {
  return runTransaction(d, async (tx) => {
    const order = ref(d, 'orders/o1');
    const item = ref(d, 'orders/o1/items/i1');
    const table = ref(d, 'tables/t1');
    const payment = ref(d, 'orders/o1/payments/attempt-1');
    await tx.get(order); await tx.get(item); await tx.get(table); await tx.get(payment);
    tx.set(payment, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, orderId: 'o1', status: 'active',
      type: 'full_table', method: 'cash', baseAmount: 300, chargedAmount: 300,
      cashSessionId: 'cs1', paymentAttemptId: 'attempt-1', createdAt: serverTimestamp(),
    });
    tx.update(item, { paymentStatus: 'paid', paidAt: serverTimestamp(), paymentId: 'attempt-1', updatedAt: serverTimestamp() });
    tx.update(order, {
      status: 'paid', paymentStatus: 'paid', paidTotal: 300, pendingTotal: 0, monetaryPaid: 300,
      totalLiquidated: 300, paidAt: serverTimestamp(), captureRevision: increment(1),
      ...branchFields(restaurantName), updatedAt: serverTimestamp(),
    });
    tx.set(table, tableRelease ?? releasePayload(restaurantName), { merge: true });
  });
}

// Real changeOrderTable payload.
function changeTable(d, restaurantName = RESTAURANT_NAME) {
  return runTransaction(d, async (tx) => {
    const order = ref(d, 'orders/o1');
    const destination = ref(d, 'tables/t2');
    const source = ref(d, 'tables/t1');
    await tx.get(order); await tx.get(destination); await tx.get(source);
    tx.update(order, {
      tableId: 't2', tableName: 't2', orderType: 'dine_in', isTableGroup: false,
      primaryTableId: 't2', primaryTableName: 't2', tableIds: ['t2'], tableNames: ['t2'],
      tableGroupLabel: deleteField(), previousOrderType: 'dine_in', previousTableId: 't1',
      previousTableName: 't1', changedTableAt: serverTimestamp(), updatedAt: serverTimestamp(),
    });
    tx.set(source, releasePayload(restaurantName), { merge: true });
    tx.set(destination, {
      status: 'occupied', currentOrderId: 'o1', currentOrderStatus: 'ready', tableGroupId: null,
      tableGroupLabel: null, groupPrimaryTableId: null, occupiedAt: serverTimestamp(),
      ...branchFields(restaurantName), updatedAt: serverTimestamp(),
    }, { merge: true });
    tx.set(doc(d, path(`activityLog/change-${Date.now()}`)), {
      type: 'change_table', orderId: 'o1', restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      createdAt: serverTimestamp(),
    });
  });
}

// Real cancelOrder payload (batch + _setLinkedTablesStateInBatch release).
function cancelOrderBatch(d, restaurantName = RESTAURANT_NAME) {
  const batch = writeBatch(d);
  batch.update(ref(d, 'orders/o1'), {
    status: 'cancelled', kitchenStatus: 'cancelled', paymentStatus: 'cancelled', total: 0,
    paidTotal: 0, pendingTotal: 0, cancelledAt: serverTimestamp(), cancelReason: 'Cliente se fue',
    updatedAt: serverTimestamp(),
  });
  batch.update(ref(d, 'orders/o1/items/i1'), {
    kitchenStatus: 'cancelled', paymentStatus: 'cancelled', cancelledAt: serverTimestamp(),
    cancelReason: 'Cliente se fue', updatedAt: serverTimestamp(),
  });
  batch.set(ref(d, 'tables/t1'), releasePayload(restaurantName), { merge: true });
  batch.set(doc(d, path(`activityLog/cancel-${Date.now()}`)), {
    type: 'order_cancelled', orderId: 'o1', restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
    createdAt: serverTimestamp(),
  });
  return batch.commit();
}

// Real cancelEmptyOrder payload.
function cancelEmptyOrderBatch(d, restaurantName = RESTAURANT_NAME) {
  const batch = writeBatch(d);
  batch.update(ref(d, 'orders/o1'), {
    status: 'cancelled', kitchenStatus: 'cancelled', paymentStatus: 'cancelled',
    cancelledAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  batch.set(ref(d, 'tables/t1'), releasePayload(restaurantName), { merge: true });
  return batch.commit();
}

describe('Mesas: restaurantName en payloads reales de liberacion', () => {
  for (const [label, variant] of Object.entries(tableVariants)) {
    it(`cobro final libera mesa ${label}`, async () => {
      await seedOrderWithItem(); await seedOccupiedTable('t1', variant);
      await assertSucceeds(finalCheckout(db('cashier')));
      const table = await read('tables/t1');
      assert.equal(table.currentOrderId, null);
      assert.equal(table.restaurantName, RESTAURANT_NAME);
      assert.equal((await read('orders/o1')).status, 'paid');
    });

    it(`cambio de mesa libera origen ${label}`, async () => {
      await seedOrderWithItem(); await seedOccupiedTable('t1', variant);
      await seed('tables/t2', { ...branchFields(), name: 't2', status: 'available', currentOrderId: null });
      await assertSucceeds(changeTable(db('waiter')));
      assert.equal((await read('tables/t1')).currentOrderId, null);
      assert.equal((await read('tables/t2')).currentOrderId, 'o1');
    });

    it(`cancelOrder libera mesa ${label}`, async () => {
      await seedOrderWithItem({ status: 'open', paymentStatus: 'pending', kitchenStatus: 'pending' });
      await seedOccupiedTable('t1', variant);
      await assertSucceeds(cancelOrderBatch(db('manager')));
      assert.equal((await read('tables/t1')).status, 'available');
    });

    it(`cancelEmptyOrder libera mesa ${label}`, async () => {
      await seed('orders/o1', openOrder({ status: 'open', total: 0, pendingTotal: 0, kitchenStatus: 'pending' }));
      await seedOccupiedTable('t1', variant);
      await assertSucceeds(cancelEmptyOrderBatch(db('waiter')));
      assert.equal((await read('tables/t1')).status, 'available');
    });
  }

  it('acepta el nombre por defecto de la app si la sucursal no define restaurantName', async () => {
    await seed(`branches/${BRANCH_ID}`, { restaurantId: RESTAURANT_ID, name: 'Aviacion', active: true });
    await seedOrderWithItem(); await seedOccupiedTable('t1', { restaurantName: 'Nombre anterior' });
    await assertSucceeds(finalCheckout(db('cashier')));
  });

  it('acepta el nombre vigente de la sucursal tras un renombre', async () => {
    await seed(`branches/${BRANCH_ID}`, {
      restaurantId: RESTAURANT_ID, restaurantName: 'Los Padrinos Aviacion', name: 'Aviacion', active: true,
    });
    await seedOrderWithItem(); await seedOccupiedTable('t1', { restaurantName: RESTAURANT_NAME });
    await assertSucceeds(finalCheckout(db('cashier'), { restaurantName: 'Los Padrinos Aviacion' }));
  });
});

describe('Mesas: restaurantName no puede alterarse arbitrariamente', () => {
  it('rechaza cobro final que escribe un restaurantName arbitrario en la mesa', async () => {
    await seedOrderWithItem(); await seedOccupiedTable('t1', {});
    await assertFails(finalCheckout(db('cashier'), { restaurantName: 'Restaurante pirata' }));
    assert.equal((await read('orders/o1')).status, 'ready');
    assert.equal((await read('tables/t1')).currentOrderId, 'o1');
  });

  it('rechaza un restaurantName que no coincide con la sucursal ni con el valor por defecto', async () => {
    await seed(`branches/${BRANCH_ID}`, {
      restaurantId: RESTAURANT_ID, restaurantName: 'Los Padrinos Aviacion', name: 'Aviacion', active: true,
    });
    await seed('tables/t1', { ...branchFields(), status: 'occupied', currentOrderId: 'ghost' });
    const d = db('waiter');
    await assertFails(updateDoc(ref(d, 'tables/t1'), releasePayload('Otro restaurante')));
  });

  it('rechaza borrar restaurantName durante una liberacion', async () => {
    await seed('tables/t1', { ...branchFields(), status: 'occupied', currentOrderId: 'ghost' });
    const d = db('waiter');
    await assertFails(updateDoc(ref(d, 'tables/t1'), { ...releasePayload(), restaurantName: deleteField() }));
  });

  it('rechaza restaurantName vacio o no textual durante una liberacion', async () => {
    await seed('tables/t1', { ...branchFields(), status: 'occupied', currentOrderId: 'ghost' });
    const d = db('waiter');
    await assertFails(updateDoc(ref(d, 'tables/t1'), { ...releasePayload(), restaurantName: '' }));
    await assertFails(updateDoc(ref(d, 'tables/t1'), { ...releasePayload(), restaurantName: 42 }));
  });

  it('rechaza cambiar restaurantId durante una liberacion', async () => {
    await seed('tables/t1', { ...branchFields(), status: 'occupied', currentOrderId: 'ghost' });
    const d = db('waiter');
    await assertFails(updateDoc(ref(d, 'tables/t1'), { ...releasePayload(), restaurantId: 'otro' }));
  });

  it('el nombre canonico no permite liberar la mesa de una orden activa vinculada', async () => {
    await seedOrderWithItem(); await seedOccupiedTable('t1', {});
    const d = db('waiter');
    await assertFails(updateDoc(ref(d, 'tables/t1'), releasePayload()));
  });
});

describe('Mesas: protecciones de ordenes terminales permanecen', () => {
  async function seedPaidOrder() {
    await seedOrderWithItem({
      status: 'paid', paymentStatus: 'paid', paidTotal: 300, pendingTotal: 0, paidAt: new Date(),
    });
    await seedOccupiedTable('t1', {});
  }

  it('rechaza reabrir una orden pagada aunque libere la mesa con payload canonico', async () => {
    await seedPaidOrder();
    const d = db('old-apk');
    await assertFails(runTransaction(d, async (tx) => {
      const order = ref(d, 'orders/o1'); const table = ref(d, 'tables/t1');
      await tx.get(order); await tx.get(table);
      tx.update(order, { status: 'ready', paymentStatus: 'partial', pendingTotal: 50 });
      tx.set(table, releasePayload(), { merge: true });
    }));
    assert.equal((await read('orders/o1')).status, 'paid');
  });

  it('rechaza alterar totales de una orden pagada', async () => {
    await seedPaidOrder();
    await assertFails(updateDoc(ref(db('old-apk'), 'orders/o1'), { total: 250, paidTotal: 250 }));
  });

  it('rechaza agregar o editar articulos de una orden pagada', async () => {
    await seedPaidOrder();
    const d = db('old-apk');
    await assertFails(setDoc(ref(d, 'orders/o1/items/late'), {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, status: 'active', qty: 1, total: 25,
    }));
    await assertFails(updateDoc(ref(d, 'orders/o1/items/i1'), { qty: 2, total: 600 }));
  });

  it('permite liberar la mesa de una orden ya pagada con payload canonico', async () => {
    await seedPaidOrder();
    await assertSucceeds(updateDoc(ref(db('cashier'), 'tables/t1'), releasePayload()));
  });
});
