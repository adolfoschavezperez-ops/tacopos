// cancelPayment (+28): the exact transactional write set must be accepted by
// the deployed-candidate rules, and the discover -> fenced transaction
// protocol must keep order aggregates consistent under concurrent writers.
// This file models TacoPosRepository.cancelPayment in JS so it can run
// against real rules; the Dart implementation itself is exercised in
// test/cancel_payment_transaction_test.dart.
const fs = require('fs');
const { strict: assert } = require('assert');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const {
  collection, deleteField, doc, getDoc, getDocs, increment, query, runTransaction, serverTimestamp,
  setDoc, updateDoc, where, writeBatch,
} = require('firebase/firestore');

const R = 'tacopos';
const B = 'aviacion';
const root = `restaurants/${R}`;
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-cancel-payment-protocol',
    firestore: { rules: fs.readFileSync('firestore.rules', 'utf8') },
  });
});
after(async () => env?.cleanup());

const path = (rel) => `${root}/${rel}`;
const db = (uid = 'cashier') => env.authenticatedContext(uid).firestore();
async function seed(rel, data) { await env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), path(rel)), data)); }
async function read(rel) { let v; await env.withSecurityRulesDisabled(async (c) => { v = (await getDoc(doc(c.firestore(), path(rel)))).data(); }); return v; }
async function list(rel) { let v; await env.withSecurityRulesDisabled(async (c) => { v = (await getDocs(collection(c.firestore(), path(rel)))).docs.map((d) => ({ id: d.id, ...d.data() })); }); return v; }

async function seedOrder({ items = { i1: 300 }, payments = { p1: 100 }, revision = 5 } = {}) {
  await env.clearFirestore();
  await seed('cashSessions/cs1', { restaurantId: R, branchId: B, status: 'open' });
  const total = Object.values(items).reduce((a, b) => a + b, 0);
  const paid = Object.values(payments).reduce((a, b) => a + b, 0);
  await seed('orders/o1', {
    restaurantId: R, branchId: B, status: 'ready', kitchenStatus: 'ready', total,
    paidTotal: paid, pendingTotal: total - paid, paymentStatus: paid > 0 ? 'partial' : 'pending',
    updatedAt: new Date('2026-11-21T10:00:00Z'), ...(revision == null ? {} : { captureRevision: revision }),
  });
  for (const [id, v] of Object.entries(items)) {
    await seed(`orders/o1/items/${id}`, { restaurantId: R, branchId: B, status: 'active', paymentStatus: 'pending', kitchenStatus: 'ready', qty: 1, unitPrice: v, total: v });
  }
  for (const [id, v] of Object.entries(payments)) {
    await seed(`orders/o1/payments/${id}`, { restaurantId: R, branchId: B, orderId: 'o1', status: 'active', type: 'partial', method: 'cash', baseAmount: v, cashSessionId: 'cs1' });
  }
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

// JS model of TacoPosRepository.cancelPayment (same reads, fence and writes).
async function cancelPayment(d, paymentId, hooks = {}) {
  for (let attempt = 1; attempt <= 3; attempt++) {
    const orderRef = doc(d, path('orders/o1'));
    const discovered = (await getDoc(orderRef)).data();
    const payRefs = (await getDocs(collection(d, path('orders/o1/payments')))).docs.map((s) => s.ref);
    const itemRefs = (await getDocs(collection(d, path('orders/o1/items')))).docs.map((s) => s.ref);
    const usageRefs = (await getDocs(query(collection(d, path('discountUsage')), where('paymentId', '==', paymentId)))).docs.map((s) => s.ref);
    if (hooks.afterDiscovery) await hooks.afterDiscovery(attempt);
    const activityRef = doc(d, path(`activityLog/payment_cancelled_o1_${paymentId}`));
    try {
      return await runTransaction(d, async (tx) => {
        const orderSnap = await tx.get(orderRef);
        const pays = []; for (const r of payRefs) { const s = await tx.get(r); if (s.exists()) pays.push({ id: s.id, ref: r, ...s.data() }); }
        const items = []; for (const r of itemRefs) { const s = await tx.get(r); if (s.exists()) items.push({ id: s.id, ref: r, ...s.data() }); }
        const usages = []; for (const r of usageRefs) { const s = await tx.get(r); if (s.exists()) usages.push({ ref: r, ...s.data() }); }
        const target = pays.find((x) => x.id === paymentId);
        if (!target) throw new Error('El pago ya no existe.');
        if (target.status === 'cancelled') return 'alreadyCancelled';
        const order = orderSnap.data();
        if ((order.captureRevision ?? 0) !== (discovered.captureRevision ?? 0) || !equalData(order, discovered)) throw new Error('CONFLICT');
        if (['paid', 'cancelled', 'closed'].includes(order.status) || order.paymentStatus === 'paid') throw new Error('orden cerrada');
        const authRef = target.discountAuthorizationRequestId ? doc(d, path(`discountAuthorizationRequests/${target.discountAuthorizationRequestId}`)) : null;
        const auth = authRef ? (await tx.get(authRef)).data() : null;
        const cash = (await tx.get(doc(d, path(`cashSessions/${target.cashSessionId}`)))).data();
        if (!cash || cash.status !== 'open') throw new Error('caja no abierta');
        const activity = await tx.get(activityRef);
        const total = items.filter((i) => i.status === 'active').reduce((a, i) => a + i.total, 0);
        const paid = pays.filter((x) => x.status === 'active' && x.id !== paymentId).reduce((a, x) => a + x.baseAmount, 0);
        const now = serverTimestamp();
        tx.update(target.ref, { status: 'cancelled', cancelledAt: now, cancelReason: 'Prueba', updatedAt: now });
        for (const u of usages) if (u.status === 'active') tx.update(u.ref, { status: 'cancelled', cancelledAt: now, cancelReason: 'Prueba' });
        if (auth && auth.status === 'used' && auth.usedPaymentId === paymentId) tx.update(authRef, { status: 'approved', usedAt: deleteField(), usedPaymentId: '', updatedAt: now });
        for (const i of items) if (i.paymentId === paymentId) tx.update(i.ref, { paymentStatus: 'pending', paymentId: deleteField(), paidAt: deleteField(), updatedAt: now });
        tx.update(orderRef, {
          total, grossSubtotal: total, netTotal: total, paidTotal: paid, pendingTotal: Math.max(total - paid, 0),
          paymentStatus: paid > 0 ? 'partial' : 'pending', paidAt: deleteField(), captureRevision: increment(1), updatedAt: now,
        });
        if (!activity.exists()) {
          tx.set(activityRef, { type: 'payment_cancelled', restaurantId: R, branchId: B, orderId: 'o1', paymentId, createdAt: now });
        }
        return 'cancelled';
      });
    } catch (e) {
      if (e.message !== 'CONFLICT') throw e;
    }
  }
  throw new Error('reintentos agotados');
}

async function assertConsistent(expectedTotal, expectedPaid) {
  const o = await read('orders/o1');
  const paid = (await list('orders/o1/payments')).filter((x) => x.status === 'active').reduce((a, x) => a + x.baseAmount, 0);
  assert.equal(paid, expectedPaid, 'pagos activos');
  assert.equal(o.total, expectedTotal, 'total');
  assert.equal(o.paidTotal, expectedPaid, 'paidTotal');
  assert.equal(o.pendingTotal, expectedTotal - expectedPaid, 'pendingTotal');
}

function partialPayment28(d, id, amount) {
  return runTransaction(d, async (tx) => {
    const o = doc(d, path('orders/o1')); const order = (await tx.get(o)).data();
    tx.set(doc(d, path(`orders/o1/payments/${id}`)), { restaurantId: R, branchId: B, orderId: 'o1', status: 'active', type: 'partial', method: 'cash', baseAmount: amount, cashSessionId: 'cs1' });
    tx.update(o, { paidTotal: order.paidTotal + amount, pendingTotal: order.pendingTotal - amount, captureRevision: increment(1), updatedAt: serverTimestamp() });
  });
}

describe('cancelPayment: reglas aceptan el conjunto de escrituras transaccional', () => {
  it('cancela pago con descuento historico, autorizacion propia, articulo pagado y actividad determinista', async () => {
    await seedOrder();
    await seed('orders/o1/payments/p1', { restaurantId: R, branchId: B, orderId: 'o1', status: 'active', baseAmount: 100, cashSessionId: 'cs1', discountAuthorizationRequestId: 'a1' });
    await seed('orders/o1/items/i1', { restaurantId: R, branchId: B, status: 'active', paymentStatus: 'paid', paymentId: 'p1', qty: 1, total: 300 });
    await seed('discountUsage/rNd0m', { restaurantId: R, branchId: B, orderId: 'o1', paymentId: 'p1', status: 'active' });
    await seed('discountAuthorizationRequests/a1', { restaurantId: R, branchId: B, status: 'used', usedPaymentId: 'p1' });
    assert.equal(await cancelPayment(db(), 'p1'), 'cancelled');
    await assertConsistent(300, 0);
    assert.equal((await read('discountUsage/rNd0m')).status, 'cancelled');
    assert.equal((await read('discountAuthorizationRequests/a1')).status, 'approved');
    assert.equal((await read('orders/o1/items/i1')).paymentStatus, 'pending');
    assert.equal((await list('activityLog')).length, 1);
    assert.equal((await read('orders/o1')).captureRevision, 6);
  });

  it('las reglas rechazan cancelar un pago cuya caja esta en cierre aunque el cliente omita la validacion', async () => {
    await seedOrder();
    await seed('cashSessions/cs1', { restaurantId: R, branchId: B, status: 'closing' });
    await assertFails(updateDoc(doc(db(), path('orders/o1/payments/p1')), { status: 'cancelled' }));
  });

  it('las reglas rechazan sobrescribir el registro de actividad determinista', async () => {
    await seedOrder();
    await assertSucceeds(setDoc(doc(db(), path('activityLog/payment_cancelled_o1_p1')), { type: 'payment_cancelled', restaurantId: R, branchId: B }));
    await assertFails(setDoc(doc(db(), path('activityLog/payment_cancelled_o1_p1')), { type: 'payment_cancelled', restaurantId: R, branchId: B, extra: 1 }));
  });
});

describe('cancelPayment: concurrencia bajo reglas reales', () => {
  it('C1 abono concurrente entre descubrimiento y transaccion', async () => {
    await seedOrder();
    await cancelPayment(db('A'), 'p1', { afterDiscovery: (n) => (n === 1 ? partialPayment28(db('B'), 'p2', 100) : null) });
    await assertConsistent(300, 100);
  });

  it('C2 dos cancelaciones de pagos distintos', async () => {
    await seedOrder({ payments: { p1: 100, p2: 100 } });
    await cancelPayment(db('A'), 'p1', { afterDiscovery: (n) => (n === 1 ? cancelPayment(db('B'), 'p2') : null) });
    await assertConsistent(300, 0);
  });

  it('mismo pago dos veces: una cancelacion y un registro', async () => {
    await seedOrder({ payments: { p1: 100, p2: 50 } });
    let other;
    const mine = await cancelPayment(db('A'), 'p1', { afterDiscovery: async (n) => { if (n === 1) other = await cancelPayment(db('B'), 'p1'); } });
    assert.equal(other, 'cancelled');
    assert.equal(mine, 'alreadyCancelled');
    await assertConsistent(300, 50);
    assert.equal((await list('activityLog')).length, 1);
  });

  it('C4 articulo agregado con revision durante la cancelacion', async () => {
    await seedOrder();
    const waiter = db('W');
    await cancelPayment(db('A'), 'p1', {
      afterDiscovery: (n) => (n === 1 ? runTransaction(waiter, async (tx) => {
        const o = doc(waiter, path('orders/o1')); await tx.get(o);
        tx.set(doc(waiter, path('orders/o1/items/i2')), { restaurantId: R, branchId: B, status: 'active', paymentStatus: 'pending', qty: 1, total: 50 });
        tx.update(o, { captureRevision: increment(1) });
      }) : null),
    });
    await assertConsistent(350, 0);
  });

  it('escritor sin revision que toca la orden se detecta por comparacion completa', async () => {
    await seedOrder();
    await cancelPayment(db('A'), 'p1', {
      afterDiscovery: async (n) => {
        if (n !== 1) return;
        const legacy = db('L');
        const b = writeBatch(legacy);
        b.set(doc(legacy, path('orders/o1/payments/p27')), { restaurantId: R, branchId: B, orderId: 'o1', status: 'active', baseAmount: 100, cashSessionId: 'cs1' });
        b.update(doc(legacy, path('orders/o1')), { paidTotal: 200, pendingTotal: 100, updatedAt: serverTimestamp() });
        await b.commit();
      },
    });
    await assertConsistent(300, 100);
  });

  it('riesgo residual: articulo legacy sin tocar la orden no se descubre en esa ventana', async () => {
    await seedOrder();
    await cancelPayment(db('A'), 'p1', {
      afterDiscovery: (n) => (n === 1 ? setDoc(doc(db('L'), path('orders/o1/items/i27')), { restaurantId: R, branchId: B, status: 'active', paymentStatus: 'pending', qty: 1, total: 80 }) : null),
    });
    assert.equal((await read('orders/o1')).total, 300);
  });
});
