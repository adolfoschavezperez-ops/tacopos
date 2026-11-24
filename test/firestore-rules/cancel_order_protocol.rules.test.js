// cancelOrder / cancelEmptyOrder (+28): the transactional write set must be
// accepted by the current rules, and a confirmed scope must commit exactly as
// confirmed (never widened by a retry) while keeping orders, payments, items
// and tables consistent. This file
// models TacoPosRepository._runFencedOrderMutation in JS to run against real
// rules; the Dart implementation is exercised in
// test/cancel_order_transaction_test.dart.
require('./safeTestEnvironment');
const fs = require('fs');
const { strict: assert } = require('assert');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const {
  collection, doc, getDoc, getDocs, increment, query, runTransaction, serverTimestamp, setDoc, where,
} = require('firebase/firestore');

const R = 'tacopos';
const B = 'aviacion';
const RN = "Los Padrino's Tacos";
const branchFields = { restaurantId: R, restaurantName: RN, branchId: B, branchName: 'Aviacion' };
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-cancel-order-protocol',
    firestore: { rules: fs.readFileSync('firestore.rules', 'utf8') },
  });
});
after(async () => env?.cleanup());

const path = (rel) => `restaurants/${R}/${rel}`;
const db = (uid = 'manager') => env.authenticatedContext(uid).firestore();
async function seed(rel, data) { await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), path(rel)), data)); }
async function read(rel) { let v; await env.withSecurityRulesDisabled(async (c) => { v = (await getDoc(doc(c.firestore(), path(rel)))).data(); }); return v; }
async function list(rel) { let v; await env.withSecurityRulesDisabled(async (c) => { v = (await getDocs(collection(c.firestore(), path(rel)))).docs.map((d) => ({ id: d.id, ...d.data() })); }); return v; }

async function seedOrder({ items = { i1: 120 }, extra = {} } = {}) {
  await env.clearFirestore();
  await seed('cashSessions/cs1', { restaurantId: R, branchId: B, status: 'open' });
  await seed(`branches/${B}`, { restaurantId: R, restaurantName: RN, name: 'Aviacion' });
  const total = Object.values(items).reduce((a, b) => a + b, 0);
  await seed('orders/o1', {
    ...branchFields, status: 'open', kitchenStatus: 'pending', paymentStatus: 'pending', orderType: 'dine_in',
    tableId: 't1', tableIds: ['t1'], total, paidTotal: 0, pendingTotal: total, captureRevision: 3,
    updatedAt: new Date('2026-11-21T10:00:00Z'), ...extra,
  });
  for (const [id, v] of Object.entries(items)) {
    await seed(`orders/o1/items/${id}`, { ...branchFields, status: 'active', paymentStatus: 'pending', kitchenStatus: 'sent', kitchenBatchId: 'k1', qty: 1, total: v });
  }
  if (Object.keys(items).length) await seed('orders/o1/kitchenBatches/k1', { ...branchFields, status: 'sent', itemCount: Object.keys(items).length });
  await seed('tables/t1', { ...branchFields, name: 'Mesa 1', status: 'occupied', currentOrderId: 'o1' });
}

function equalData(a, b) {
  if (a === b) return true;
  if (a && b && typeof a.isEqual === 'function') return a.isEqual(b);
  if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((x, i) => equalData(x, b[i]));
  if (a && b && typeof a === 'object' && typeof b === 'object') {
    const ka = Object.keys(a); const kb = Object.keys(b);
    return ka.length === kb.length && ka.every((k) => k in b && equalData(a[k], b[k]));
  }
  return false;
}

const release = () => ({
  status: 'available', currentOrderId: null, currentOrderStatus: null, tableGroupId: null, tableGroupLabel: null,
  groupPrimaryTableId: null, occupiedAt: null, ...branchFields, updatedAt: serverTimestamp(),
});

// JS model of prepareOrderCancellation / prepareEmptyOrderClose (server read
// shown to the operator) and _runFencedOrderMutation, which commits only the
// confirmed scope and never widens it on retry.
async function prepare(d) {
  const orderSnap = await getDoc(doc(d, path('orders/o1')));
  const items = (await getDocs(collection(d, path('orders/o1/items')))).docs;
  const pays = (await getDocs(collection(d, path('orders/o1/payments')))).docs;
  return {
    order: orderSnap.data(),
    items: Object.fromEntries(items.map((s) => [s.id, s.data()])),
    payments: Object.fromEntries(pays.map((s) => [s.id, s.data()])),
  };
}

function scopeChange(scope, order, items, pays) {
  if ((order.captureRevision ?? 0) !== (scope.order.captureRevision ?? 0) || !equalData(order, scope.order)) return 'order';
  const sameSet = (a, b) => Object.keys(a).length === Object.keys(b).length && Object.keys(a).every((k) => k in b && equalData(a[k], b[k]));
  if (!sameSet(scope.items, items)) return 'items';
  if (!sameSet(scope.payments, pays)) return 'payments';
  return null;
}

async function fencedCancel(d, scope, { empty = false, hooks = {} } = {}) {
  for (let attempt = 1; attempt <= 3; attempt++) {
    const orderRef = doc(d, path('orders/o1'));
    const itemRefs = (await getDocs(collection(d, path('orders/o1/items')))).docs.map((s) => s.ref);
    const payRefs = (await getDocs(collection(d, path('orders/o1/payments')))).docs.map((s) => s.ref);
    const pointing = (await getDocs(query(collection(d, path('tables')), where('currentOrderId', '==', 'o1')))).docs.map((s) => s.id);
    const ids = (refs) => refs.map((r) => r.id).sort().join(',');
    if (ids(itemRefs) !== Object.keys(scope.items).sort().join(',') || ids(payRefs) !== Object.keys(scope.payments).sort().join(',')) {
      throw new Error('SCOPE_CHANGED');
    }
    if (hooks.afterDiscovery) await hooks.afterDiscovery(attempt);
    try {
      return await runTransaction(d, async (tx) => {
        const order = (await tx.get(orderRef)).data();
        const items = {}; const itemList = [];
        for (const r of itemRefs) { const s = await tx.get(r); if (s.exists()) { items[s.id] = s.data(); itemList.push({ id: s.id, ref: r, ...s.data() }); } }
        const pays = {}; for (const r of payRefs) { const s = await tx.get(r); if (s.exists()) pays[s.id] = s.data(); }
        if (order.status === 'cancelled') return 'alreadyCancelled';
        if (scopeChange(scope, order, items, pays)) throw new Error('SCOPE_CHANGED');
        const candidates = [...new Set([...(order.tableIds || []), ...pointing])];
        const owners = {};
        for (const t of candidates) { const s = await tx.get(doc(d, path(`tables/${t}`))); if (s.exists()) owners[t] = s.data().currentOrderId; }
        const toRelease = candidates.filter((t) => owners[t] === 'o1');
        const skipped = candidates.filter((t) => !(t in owners) || (owners[t] && owners[t] !== 'o1'));
        const toCancel = empty ? [] : itemList.filter((i) => i.kitchenStatus !== 'cancelled');
        const batchIds = [...new Set(toCancel.map((i) => i.kitchenBatchId).filter(Boolean))];
        const batches = []; for (const b of batchIds) { const s = await tx.get(doc(d, path(`orders/o1/kitchenBatches/${b}`))); if (s.exists()) batches.push({ ref: s.ref, ...s.data() }); }
        const activityRef = doc(d, path('activityLog/order_cancelled_o1'));
        const activity = empty ? null : await tx.get(activityRef);
        const pendingBatches = batches.filter((b) => b.status !== 'cancelled');
        const docWrites = 1 + toCancel.length + pendingBatches.length + toRelease.length + (empty || activity.exists() ? 0 : 1);
        if (docWrites * 2 > 500) throw new Error('TOO_LARGE');
        const now = serverTimestamp();
        tx.update(orderRef, {
          status: 'cancelled', kitchenStatus: 'cancelled', paymentStatus: 'cancelled',
          ...(empty ? {} : { total: 0, paidTotal: 0, pendingTotal: 0, cancelReason: 'Prueba' }),
          cancelledAt: now, captureRevision: increment(1), updatedAt: now,
        });
        for (const i of toCancel) {
          tx.update(i.ref, { kitchenStatus: 'cancelled', paymentStatus: 'cancelled', cancelledAt: now, cancelReason: 'Prueba', updatedAt: now });
        }
        for (const b of pendingBatches) tx.set(b.ref, { status: 'cancelled', itemCount: 0, activeItemCount: 0, cancelledAt: now, updatedAt: now }, { merge: true });
        for (const t of toRelease) tx.set(doc(d, path(`tables/${t}`)), release(), { merge: true });
        if (!empty && !activity.exists()) tx.set(activityRef, { ...branchFields, type: 'order_cancelled', orderId: 'o1', cancelledItemCount: toCancel.length, cancelledItems: toCancel.map((i) => ({ itemId: i.id, qty: i.qty, total: i.total, previousKitchenStatus: i.kitchenStatus })), releasedTableIds: toRelease, skippedTableIds: skipped, createdAt: now });
        return 'cancelled';
      });
    } catch (e) {
      if (e.code !== 'aborted') throw e;
    }
  }
  throw new Error('reintentos agotados');
}

async function confirmAndCancel(d, options) {
  return fencedCancel(d, await prepare(d), options);
}

async function assertCancelledClean() {
  const o = await read('orders/o1');
  assert.equal(o.status, 'cancelled');
  assert.equal((await list('orders/o1/payments')).filter((x) => x.status === 'active').length, 0, 'pagos activos');
  for (const i of await list('orders/o1/items')) assert.equal(i.kitchenStatus, 'cancelled', `articulo ${i.id}`);
  for (const t of await list('tables')) assert.notEqual(t.currentOrderId, 'o1', `mesa ${t.id}`);
}

async function addItemWithRevision(d, id, total) {
  await runTransaction(d, async (tx) => {
    const o = doc(d, path('orders/o1')); await tx.get(o);
    tx.set(doc(d, path(`orders/o1/items/${id}`)), { ...branchFields, status: 'active', paymentStatus: 'pending', kitchenStatus: 'pending', qty: 1, total });
    tx.update(o, { captureRevision: increment(1) });
  });
}

describe('cancelOrder: reglas aceptan el conjunto de escrituras transaccional', () => {
  it('cancela orden, articulos, lote, mesa propia y actividad determinista', async () => {
    await seedOrder({ items: { i1: 120, i2: 30 } });
    assert.equal(await confirmAndCancel(db()), 'cancelled');
    await assertCancelledClean();
    assert.equal((await read('orders/o1/kitchenBatches/k1')).status, 'cancelled');
    assert.equal((await list('activityLog')).length, 1);
    assert.equal((await read('activityLog/order_cancelled_o1')).cancelledItems.length, 2);
  });

  it('libera tambien una mesa fantasma que apunta a la orden', async () => {
    await seedOrder();
    await seed('tables/t9', { ...branchFields, name: 'Mesa 9', status: 'occupied', currentOrderId: 'o1' });
    await confirmAndCancel(db());
    await assertCancelledClean();
  });

  it('no toca una mesa vinculada que ya pertenece a otra orden', async () => {
    await seedOrder();
    await seed('orders/o2', { ...branchFields, status: 'open', paymentStatus: 'pending', orderType: 'dine_in', tableId: 't1', tableIds: ['t1'] });
    await seed('tables/t1', { ...branchFields, name: 'Mesa 1', status: 'occupied', currentOrderId: 'o2' });
    assert.equal(await confirmAndCancel(db()), 'cancelled');
    assert.equal((await read('tables/t1')).currentOrderId, 'o2');
    assert.deepEqual((await read('activityLog/order_cancelled_o1')).skippedTableIds, ['t1']);
  });

  it('repeticion con la misma identidad: no escribe ni duplica actividad', async () => {
    await seedOrder();
    const scope = await prepare(db('A'));
    await fencedCancel(db('A'), scope);
    assert.equal(await fencedCancel(db('B'), scope), 'alreadyCancelled');
    assert.equal((await list('activityLog')).filter((l) => l.type === 'order_cancelled').length, 1);
  });

  it('las reglas rechazan sobrescribir la actividad determinista', async () => {
    await seedOrder();
    await confirmAndCancel(db());
    await assertFails(setDoc(doc(db(), path('activityLog/order_cancelled_o1')), { ...branchFields, type: 'order_cancelled', extra: 1 }));
  });

  it('cancelEmptyOrder: cierra la orden vacia y libera la mesa', async () => {
    await seedOrder({ items: {} });
    assert.equal(await confirmAndCancel(db(), { empty: true }), 'cancelled');
    await assertCancelledClean();
  });
});

describe('cancelOrder: alcance confirmado bajo reglas reales', () => {
  it('Codex: cuarto articulo despues de confirmar tres: aborta sin cancelar nada', async () => {
    await seedOrder({ items: { i1: 50, i2: 40, i3: 30 } });
    const scope = await prepare(db('A'));
    await addItemWithRevision(db('B'), 'i4', 45);
    await assert.rejects(fencedCancel(db('A'), scope), /SCOPE_CHANGED/);
    assert.equal((await read('orders/o1')).status, 'open');
    for (const id of ['i1', 'i2', 'i3']) assert.equal((await read(`orders/o1/items/${id}`)).kitchenStatus, 'sent');
    assert.equal((await read('orders/o1/items/i4')).status, 'active');
  });

  it('articulo despues del descubrimiento: no se reintenta ni amplia', async () => {
    await seedOrder({ items: { i1: 50 } });
    const scope = await prepare(db('A'));
    const waiter = db('B');
    await assert.rejects(fencedCancel(db('A'), scope, {
      hooks: { afterDiscovery: (n) => (n === 1 ? addItemWithRevision(waiter, 'i4', 45) : null) },
    }), /SCOPE_CHANGED/);
    assert.equal((await read('orders/o1')).status, 'open');
    assert.equal((await read('orders/o1/items/i4')).status, 'active');
  });

  it('E1 abono despues de confirmar: se rechaza la cancelacion', async () => {
    await seedOrder();
    const scope = await prepare(db());
    const cashier = db('caja');
    await runTransaction(cashier, async (tx) => {
      const o = doc(cashier, path('orders/o1')); const order = (await tx.get(o)).data();
      tx.set(doc(cashier, path('orders/o1/payments/p2')), { ...branchFields, orderId: 'o1', status: 'active', baseAmount: 50, cashSessionId: 'cs1' });
      tx.update(o, { paidTotal: order.paidTotal + 50, paymentStatus: 'partial', captureRevision: increment(1) });
    });
    await assert.rejects(fencedCancel(db(), scope), /SCOPE_CHANGED/);
    assert.equal((await read('orders/o1')).status, 'open');
  });

  it('E5 orden vacia recibe un articulo: no se cierra', async () => {
    await seedOrder({ items: {} });
    const scope = await prepare(db());
    await addItemWithRevision(db('mesero'), 'i-late', 80);
    await assert.rejects(fencedCancel(db(), scope, { empty: true }), /SCOPE_CHANGED/);
    assert.equal((await read('orders/o1')).status, 'open');
    assert.equal((await read('orders/o1/items/i-late')).status, 'active');
  });

  it('E7 cambio de mesa: aborta y la reconfirmacion libera la mesa vigente', async () => {
    await seedOrder();
    await seed('tables/t2', { ...branchFields, name: 'Mesa 2', status: 'available', currentOrderId: null });
    const scope = await prepare(db());
    const waiter = db('mesero');
    await runTransaction(waiter, async (tx) => {
      const o = doc(waiter, path('orders/o1')); const from = doc(waiter, path('tables/t1')); const to = doc(waiter, path('tables/t2'));
      await tx.get(o); await tx.get(to); await tx.get(from);
      tx.update(o, { tableId: 't2', tableIds: ['t2'], updatedAt: serverTimestamp() });
      tx.set(from, release(), { merge: true });
      tx.set(to, { status: 'occupied', currentOrderId: 'o1', ...branchFields, updatedAt: serverTimestamp() }, { merge: true });
    });
    await assert.rejects(fencedCancel(db(), scope), /SCOPE_CHANGED/);
    await confirmAndCancel(db());
    await assertCancelledClean();
  });
});

describe('cancelOrder: volumen bajo reglas reales', () => {
  it('200 articulos, 1 lote y 1 mesa: 204 documentos en una transaccion', async () => {
    const items = Object.fromEntries(Array.from({ length: 200 }, (_, i) => [`i${i}`, 10]));
    await seedOrder({ items });
    const started = Date.now();
    assert.equal(await confirmAndCancel(db()), 'cancelled');
    const elapsed = Date.now() - started;
    await assertCancelledClean();
    const event = await read('activityLog/order_cancelled_o1');
    assert.equal(event.cancelledItems.length, 200);
    assert.equal((await list('activityLog')).length, 1);
    console.log(`      volumen: 200 articulos cancelados en ${elapsed} ms (emulador)`);
  });

  it('300 articulos exceden el presupuesto: rechazo antes de cualquier escritura', async () => {
    const items = Object.fromEntries(Array.from({ length: 300 }, (_, i) => [`i${i}`, 10]));
    await seedOrder({ items });
    await assert.rejects(confirmAndCancel(db()), /TOO_LARGE/);
    assert.equal((await read('orders/o1')).status, 'open');
    for (const i of await list('orders/o1/items')) assert.equal(i.kitchenStatus, 'sent');
    assert.equal((await read('tables/t1')).currentOrderId, 'o1');
    assert.equal((await list('activityLog')).length, 0);
  });
});
