require('./safeTestEnvironment');
const fs = require('fs');
const { strict: assert } = require('assert');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, getDoc, runTransaction, setDoc, updateDoc, serverTimestamp } = require('firebase/firestore');

const root = 'restaurants/tacopos';
let env;
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-tables-lifecycle', firestore: { rules: fs.readFileSync('firestore.rules', 'utf8') } });
});
after(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

const path = (kind, id) => `${root}/${kind}/${id}`;
const order = (fields = {}) => ({ restaurantId: 'tacopos', branchId: 'aviacion', status: 'open', paymentStatus: 'pending', tableId: 't1', tableIds: ['t1'], ...fields });
const table = (id, fields = {}) => ({ restaurantId: 'tacopos', branchId: 'aviacion', status: id ? 'occupied' : 'available', currentOrderId: id, ...fields });
async function seed(kind, id, data) { await env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(), path(kind, id)), data)); }
const db = (uid = 'waiter') => env.authenticatedContext(uid).firestore();
const ref = (d, kind, id) => doc(d, path(kind, id));
const release = () => ({ status: 'available', currentOrderId: null, currentOrderStatus: null, tableGroupId: null, tableGroupLabel: null, groupPrimaryTableId: null, occupiedAt: null, updatedAt: serverTimestamp() });

describe('Mesa: transiciones atomicas y vinculos obsoletos', () => {
  it('mueve una orden abierta sin dejar la mesa anterior ocupada', async () => {
    await seed('orders', 'o1', order()); await seed('tables', 't1', table('o1')); await seed('tables', 't2', table(null));
    const d = db();
    await assertSucceeds(runTransaction(d, async tx => {
      const o = ref(d, 'orders', 'o1'), a = ref(d, 'tables', 't1'), b = ref(d, 'tables', 't2');
      await tx.get(o); await tx.get(a); await tx.get(b);
      tx.update(o, { tableId: 't2', tableIds: ['t2'], updatedAt: serverTimestamp() });
      tx.set(a, release(), { merge: true });
      tx.set(b, { status: 'occupied', currentOrderId: 'o1', updatedAt: serverTimestamp() }, { merge: true });
    }));
    assert.equal((await getDoc(ref(d, 'tables', 't1'))).data().currentOrderId, null);
    assert.equal((await getDoc(ref(d, 'tables', 't2'))).data().currentOrderId, 'o1');
  });
  it('quita mesa secundaria de un grupo y conserva la principal', async () => {
    await seed('orders', 'o1', order({ isTableGroup: true, tableIds: ['t1', 't2'] }));
    await seed('tables', 't1', table('o1')); await seed('tables', 't2', table('o1'));
    const d = db();
    await assertSucceeds(runTransaction(d, async tx => {
      const o = ref(d, 'orders', 'o1'), t = ref(d, 'tables', 't2');
      await tx.get(o); await tx.get(t);
      tx.update(o, { isTableGroup: false, tableIds: ['t1'], updatedAt: serverTimestamp() });
      tx.set(t, release(), { merge: true });
    }));
    assert.equal((await getDoc(ref(d, 'tables', 't1'))).data().currentOrderId, 'o1');
  });
  it('limpia enlace fantasma a orden inexistente', async () => {
    await seed('tables', 't1', table('ghost'));
    const d = db(); await assertSucceeds(updateDoc(ref(d, 'tables', 't1'), release()));
  });
  it('limpia enlace obsoleto si orden abierta ocupa otra mesa', async () => {
    await seed('orders', 'o1', order({ tableId: 't9', tableIds: ['t9'] })); await seed('tables', 't1', table('o1'));
    const d = db(); await assertSucceeds(updateDoc(ref(d, 'tables', 't1'), release()));
  });
  it('rechaza usuario no autenticado', async () => {
    await seed('tables', 't1', table('ghost'));
    const d = env.unauthenticatedContext().firestore(); await assertFails(updateDoc(ref(d, 'tables', 't1'), release()));
  });
  it('rechaza liberar vinculo activo sin cambiar orden', async () => {
    await seed('orders', 'o1', order()); await seed('tables', 't1', table('o1'));
    const d = db(); await assertFails(updateDoc(ref(d, 'tables', 't1'), release()));
  });
  it('rechaza cambiar campos ajenos durante una limpieza fantasma', async () => {
    await seed('tables', 't1', table('ghost'));
    const d = db(); await assertFails(updateDoc(ref(d, 'tables', 't1'), { ...release(), name: 'Mesa adulterada' }));
  });
  it('rechaza limpiar un vinculo obsoleto sin dejar la mesa disponible', async () => {
    await seed('tables', 't1', table('ghost'));
    const d = db(); await assertFails(updateDoc(ref(d, 'tables', 't1'), { currentOrderId: null }));
  });
  it('rechaza liberar mesa si la orden sigue vinculada aunque otra transaccion toque su estado', async () => {
    await seed('orders', 'o1', order()); await seed('tables', 't1', table('o1'));
    const d = db(); await assertFails(runTransaction(d, async tx => {
      const o = ref(d, 'orders', 'o1'), t = ref(d, 'tables', 't1'); await tx.get(o); await tx.get(t);
      tx.update(o, { updatedAt: serverTimestamp() }); tx.set(t, release(), { merge: true });
    }));
  });
  it('rechaza cambio de mesa para orden terminal', async () => {
    await seed('orders', 'o1', order({ status: 'paid', paymentStatus: 'paid' })); await seed('tables', 't1', table('o1')); await seed('tables', 't2', table(null));
    const d = db(); await assertFails(runTransaction(d, async tx => {
      const o = ref(d, 'orders', 'o1'), a = ref(d, 'tables', 't1'), b = ref(d, 'tables', 't2');
      await tx.get(o); await tx.get(a); await tx.get(b);
      tx.update(o, { tableId: 't2', tableIds: ['t2'] }); tx.set(a, release(), { merge: true }); tx.set(b, table('o1'), { merge: true });
    }));
  });
  it('rechaza liberar la mesa activa desde otro cliente aunque el primero la haya leido', async () => {
    await seed('orders', 'o1', order()); await seed('tables', 't1', table('o1'));
    const d = db(); const t = ref(d, 'tables', 't1'); await getDoc(t);
    await assertFails(updateDoc(t, release())); assert.equal((await getDoc(t)).data().currentOrderId, 'o1');
  });
});
