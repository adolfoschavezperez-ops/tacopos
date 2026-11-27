const fs = require('fs');
const assert = require('assert');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  increment,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} = require('firebase/firestore');

const PROJECT_ID = 'demo-tacopos-pr';
const RESTAURANT_ID = 'tacopos';
const BRANCH_ID = 'aviacion';
const BUSINESS_DATE = '2026-07-31';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync('firestore.rules', 'utf8'),
    },
  });
});

after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

function authedDb(uid = 'anon-user') {
  return testEnv.authenticatedContext(uid).firestore();
}

function anonDb() {
  return testEnv.unauthenticatedContext().firestore();
}

function adminDb(uid = 'admin-uid') {
  return testEnv.authenticatedContext(uid).firestore();
}

function counterPath() {
  return `restaurants/${RESTAURANT_ID}/branches/${BRANCH_ID}/dailySaleCounters/${BUSINESS_DATE}`;
}

function counterDoc(db) {
  return doc(db, counterPath());
}

function kitchenSequencePath() {
  return `restaurants/${RESTAURANT_ID}/branches/${BRANCH_ID}/kitchenDailySequences/${BUSINESS_DATE}`;
}

function kitchenSequenceDoc(db) {
  return doc(db, kitchenSequencePath());
}

function kitchenSequenceData(overrides = {}) {
  return {
    restaurantId: RESTAURANT_ID,
    branchId: BRANCH_ID,
    businessDate: BUSINESS_DATE,
    lastSequence: 1,
    updatedAt: new Date('2026-07-31T11:00:00.000Z'),
    ...overrides,
  };
}

function twoPartyBarrier() {
  let arrivals = 0;
  let release;
  const released = new Promise((resolve) => { release = resolve; });
  return async () => {
    arrivals += 1;
    if (arrivals === 2) release();
    await released;
  };
}

function counterData(overrides = {}) {
  return {
    businessDate: BUSINESS_DATE,
    restaurantId: RESTAURANT_ID,
    branchId: BRANCH_ID,
    lastSequence: 1,
    updatedAt: new Date('2026-07-31T11:00:00.000Z'),
    updatedByDeviceId: 'device-1',
    version: 1,
    ...overrides,
  };
}

function auditPath() {
  return `restaurants/${RESTAURANT_ID}/branches/${BRANCH_ID}/saleAuditEvents/event-1`;
}

function auditDoc(db) {
  return doc(db, auditPath());
}

function auditEventData(overrides = {}) {
  return {
    eventType: 'sale_completed',
    orderId: 'order-folio',
    saleFolioSequence: 1,
    saleFolioFull: 'AVI-2026-07-31-0001',
    businessDate: BUSINESS_DATE,
    restaurantId: RESTAURANT_ID,
    branchId: BRANCH_ID,
    amount: 120,
    paymentMethodsSnapshot: [{ method: 'cash', amount: 120 }],
    previousStatus: 'pending',
    newStatus: 'paid',
    reason: 'Venta completada',
    authorizedBy: 'cashier-1',
    performedBy: 'Caja',
    deviceId: 'device-1',
    createdAt: new Date('2026-07-31T11:00:00.000Z'),
    eventVersion: 1,
    ...overrides,
  };
}

async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

async function seedAdmin(uid = 'admin-uid', restaurantId = RESTAURANT_ID) {
  await seed(`restaurants/${restaurantId}/authUsers/${uid}`, {
    active: true,
    isSuperAdmin: true,
    permissions: {
      canViewAdmin: true,
      canAuthorizeCashWithdrawals: true,
    },
  });
}

async function seedInactiveAdmin(uid = 'inactive-admin', restaurantId = RESTAURANT_ID) {
  await seed(`restaurants/${restaurantId}/authUsers/${uid}`, {
    active: false,
    isSuperAdmin: true,
    permissions: {
      canViewAdmin: true,
      canAuthorizeCashWithdrawals: true,
    },
  });
}

function appUpdatesPath(restaurantId = RESTAURANT_ID) {
  return `restaurants/${restaurantId}/settings/appUpdates`;
}

function expenseSettingsPath(restaurantId = RESTAURANT_ID) {
  return `restaurants/${restaurantId}/settings/expensePolicies`;
}

function devicePath(deviceId = 'device-uid', restaurantId = RESTAURANT_ID) {
  return `restaurants/${restaurantId}/devices/${deviceId}`;
}

function policyPath(policyId = 'hielo', restaurantId = RESTAURANT_ID) {
  return `restaurants/${restaurantId}/expensePolicies/${policyId}`;
}

function usagePath(usageId = 'usage-1', restaurantId = RESTAURANT_ID) {
  return `restaurants/${restaurantId}/expensePolicyUsage/${usageId}`;
}

function policyData(overrides = {}) {
  return {
    restaurantId: RESTAURANT_ID,
    branchId: BRANCH_ID,
    name: 'Hielo',
    code: 'hielo',
    active: true,
    autoApproveEnabled: false,
    maxAmountPerTransaction: 45,
    maxAmountPerPeriod: 45,
    maxUsesPerPeriod: 1,
    frequencyType: 'daily',
    policyVersion: 1,
    ...overrides,
  };
}

function deviceData(deviceId = 'device-uid', overrides = {}) {
  return {
    deviceId,
    deviceName: 'Caja',
    branchId: BRANCH_ID,
    branchName: 'Aviacion',
    role: 'Caja',
    platform: 'android',
    appVersionName: '1.5.0',
    appVersionCode: 16,
    availableVersionCode: 16,
    lastSeenAt: new Date('2026-08-18T10:00:00.000Z'),
    lastUpdateCheckAt: new Date('2026-08-18T10:00:00.000Z'),
    employeeId: 'cashier',
    employeeName: 'Caja',
    updateStatus: 'upToDate',
    updatedAt: new Date('2026-08-18T10:00:00.000Z'),
    ...overrides,
  };
}

describe('TacoPOS Firestore production guard rails', () => {
  it('restringe conteos de cierre a admin, sesión cerrada y un documento inmutable', async () => {
    await seedAdmin();
    const recentDate = new Date().toISOString().slice(0, 10);
    await seed(`restaurants/${RESTAURANT_ID}/kitchenSessions/kitchen-close`, {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      businessDate: recentDate,
      status: 'closed',
      closedAt: new Date(Date.now() - 60000),
    });
    const skuKey = 'water:name:agua 600 ml';
    const checkpointId = `${BRANCH_ID}|${recentDate}|${skuKey}`;
    const path = `restaurants/${RESTAURANT_ID}/resaleCheckpoints/${checkpointId}`;
    const data = {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      businessDate: recentDate,
      skuKey,
      skuName: 'agua 600 ml',
      boundary: 'closing',
      verification: 'recentObserved',
      physicalCount: 12,
      kitchenSessionId: 'kitchen-close',
      recordedAt: serverTimestamp(),
      recordedByUid: 'admin-uid',
    };
    await seed(`restaurants/${RESTAURANT_ID}/authUsers/withdrawal-uid`, {
      active: true,
      isSuperAdmin: false,
      permissions: {
        canViewAdmin: false,
        canAuthorizeCashWithdrawals: true,
      },
    });
    await assertFails(setDoc(doc(authedDb('withdrawal-uid'), path), {
      ...data, recordedByUid: 'withdrawal-uid',
    }));
    await assertFails(setDoc(doc(authedDb('cashier-1'), path), {
      ...data, recordedByUid: 'cashier-1',
    }));
    await assertFails(setDoc(doc(adminDb(), path), {
      ...data, physicalCount: -1,
    }));
    await assertFails(setDoc(doc(adminDb(), path), {
      ...data, kitchenSessionId: 'unknown',
    }));
    await seed(`restaurants/${RESTAURANT_ID}/kitchenSessions/stale-close`, {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      businessDate: recentDate,
      status: 'closed',
      closedAt: new Date(Date.now() - 3 * 86400000),
    });
    await assertFails(setDoc(doc(adminDb(), path), {
      ...data, kitchenSessionId: 'stale-close',
    }));
    await assertSucceeds(setDoc(doc(adminDb(), path), data));
    await assertFails(updateDoc(doc(adminDb(), path), { physicalCount: 13 }));
    await assertFails(deleteDoc(doc(adminDb(), path)));
    await assertFails(getDoc(doc(authedDb('cashier-1'), path)));
    await assertSucceeds(getDoc(doc(adminDb(), path)));
    const correction = {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      businessDate: recentDate,
      skuKey,
      revision: 1,
      supersedesRevision: 0,
      physicalCount: 10,
      reason: 'Captura inicial con dos botellas duplicadas',
      recordedAt: serverTimestamp(),
      recordedByUid: 'admin-uid',
    };
    const correctionPath = `${path}/corrections/1`;
    await assertFails(setDoc(doc(adminDb(), `${path}/corrections/2`), {
      ...correction, revision: 2, supersedesRevision: 1,
    }));
    await assertFails(setDoc(doc(adminDb(), correctionPath), {
      ...correction, reason: 'corto',
    }));
    await assertFails(setDoc(doc(authedDb('cashier-1'), correctionPath), {
      ...correction, recordedByUid: 'cashier-1',
    }));
    await assertSucceeds(setDoc(doc(adminDb(), correctionPath), correction));
    await assertFails(updateDoc(doc(adminDb(), correctionPath), { physicalCount: 7 }));
    await assertFails(deleteDoc(doc(adminDb(), correctionPath)));
    await assertSucceeds(setDoc(doc(adminDb(), `${path}/corrections/2`), {
      ...correction, revision: 2, supersedesRevision: 1,
      physicalCount: 9, reason: 'Verificación posterior del registro',
    }));
    assert.strictEqual((await getDoc(doc(adminDb(), path))).data().physicalCount, 12);
    assert.strictEqual((await getDoc(doc(adminDb(), correctionPath))).data().physicalCount, 10);
    assert.strictEqual((await getDoc(doc(adminDb(), `${path}/corrections/2`))).data().physicalCount, 9);
  });
  it('rechaza usuario no autenticado', async () => {
    await assertFails(
      getDoc(doc(anonDb(), `restaurants/${RESTAURANT_ID}`)),
    );
  });

  it('permite usuario autenticado en rutas conocidas', async () => {
    await seed(`restaurants/${RESTAURANT_ID}`, { name: 'TacoPOS' });
    await assertSucceeds(
      getDoc(doc(authedDb(), `restaurants/${RESTAURANT_ID}`)),
    );
  });

  it('rechaza rutas desconocidas', async () => {
    await assertFails(
      setDoc(doc(authedDb(), 'unknown/doc'), { ok: true }),
    );
  });

  it('rechaza create con restaurantId alterado', async () => {
    await assertFails(
      setDoc(
        doc(authedDb(), `restaurants/${RESTAURANT_ID}/orders/order-1`),
        {
          restaurantId: 'otro-restaurante',
          branchId: BRANCH_ID,
          status: 'open',
        },
      ),
    );
  });

  it('rechaza update que cambia branchId existente', async () => {
    await seed(`restaurants/${RESTAURANT_ID}/orders/order-1`, {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      status: 'open',
    });
    await assertFails(
      updateDoc(doc(authedDb(), `restaurants/${RESTAURANT_ID}/orders/order-1`), {
        branchId: 'otra-sucursal',
      }),
    );
  });

  it('permite orden y pago validos con auth anonima', async () => {
    const db = authedDb('anon-pos');
    await assertSucceeds(
      setDoc(doc(db, `restaurants/${RESTAURANT_ID}/orders/order-1`), {
        restaurantId: RESTAURANT_ID,
        branchId: BRANCH_ID,
        status: 'open',
        paymentStatus: 'pending',
      }),
    );
    await assertSucceeds(
      setDoc(
        doc(db, `restaurants/${RESTAURANT_ID}/orders/order-1/payments/payment-1`),
        {
          restaurantId: RESTAURANT_ID,
          branchId: BRANCH_ID,
          orderId: 'order-1',
          method: 'cash',
          status: 'active',
        },
      ),
    );
  });

  it('cliente antiguo no puede mutar articulos ni reabrir una orden terminal', async () => {
    const orderPath = `restaurants/${RESTAURANT_ID}/orders/terminal-order`;
    const itemPath = `${orderPath}/items/item-1`;
    await seed(orderPath, {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      status: 'paid',
      paymentStatus: 'paid',
      kitchenStatus: 'ready',
      total: 100,
      grossSubtotal: 100,
      netTotal: 100,
      paidTotal: 100,
      pendingTotal: 0,
      paidAt: new Date(),
    });
    await seed(itemPath, {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      status: 'active',
      paymentStatus: 'paid',
      qty: 1,
      total: 100,
    });
    const db = authedDb('old-apk-client');
    await assertFails(setDoc(doc(db, `${orderPath}/items/late-item`), {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, status: 'active', qty: 1, total: 25,
    }));
    await assertFails(updateDoc(doc(db, itemPath), { qty: 2, total: 200 }));
    await assertFails(deleteDoc(doc(db, itemPath)));
    await assertFails(updateDoc(doc(db, orderPath), {
      status: 'ready', paymentStatus: 'partial', total: 125, pendingTotal: 25,
    }));
  });

  it('permite cerrar orden y marcar articulos pagados en una misma transaccion', async () => {
    const orderPath = `restaurants/${RESTAURANT_ID}/orders/atomic-close`;
    const db = authedDb('checkout');
    const orderRefPath = doc(db, orderPath);
    const itemRef = doc(db, `${orderPath}/items/item-1`);
    const tableRef = doc(db, `restaurants/${RESTAURANT_ID}/tables/table-1`);
    await seed(orderPath, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'ready', paymentStatus: 'pending', total: 100,
      grossSubtotal: 100, netTotal: 100, paidTotal: 0, pendingTotal: 100,
    });
    await seed(`${orderPath}/items/item-1`, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'active', paymentStatus: 'pending', qty: 1, total: 100,
    });
    await seed(`restaurants/${RESTAURANT_ID}/tables/table-1`, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'occupied', currentOrderId: 'atomic-close',
    });
    await assertSucceeds(runTransaction(db, async (tx) => {
      await tx.get(orderRefPath);
      await tx.get(itemRef);
      await tx.get(tableRef);
      tx.update(itemRef, { paymentStatus: 'paid', paidAt: serverTimestamp() });
      tx.update(orderRefPath, {
        status: 'paid', paymentStatus: 'paid', paidTotal: 100,
        pendingTotal: 0, paidAt: serverTimestamp(),
      });
      tx.update(tableRef, { status: 'available', currentOrderId: null });
    }));
  });

  it('no permite que una operacion de una orden antigua ocupe o libere la mesa de otra orden', async () => {
    const oldOrderPath = `restaurants/${RESTAURANT_ID}/orders/old-order`;
    const currentOrderPath = `restaurants/${RESTAURANT_ID}/orders/current-order`;
    const tablePath = `restaurants/${RESTAURANT_ID}/tables/table-2`;
    await seed(oldOrderPath, { restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, status: 'open', paymentStatus: 'pending' });
    await seed(currentOrderPath, { restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, status: 'open', paymentStatus: 'pending' });
    await seed(tablePath, { restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, status: 'occupied', currentOrderId: 'current-order' });
    const db = authedDb('stale-table-client');
    await assertFails(updateDoc(doc(db, tablePath), {
      status: 'available', currentOrderId: null,
    }));
    await assertFails(updateDoc(doc(db, tablePath), {
      status: 'occupied', currentOrderId: 'old-order',
    }));
  });

  it('permite pagos parciales en una orden que sigue editable y conserva agregados', async () => {
    const orderPath = `restaurants/${RESTAURANT_ID}/orders/partial-order`;
    await seed(orderPath, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'ready', paymentStatus: 'pending', total: 450,
      grossSubtotal: 450, netTotal: 450, paidTotal: 0, pendingTotal: 450,
    });
    const db = authedDb('cashier-partial');
    await assertSucceeds(setDoc(doc(db, `${orderPath}/payments/p1`), {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, orderId: 'partial-order',
      method: 'cash', status: 'active', type: 'partial', baseAmount: 100,
    }));
    await assertSucceeds(updateDoc(doc(db, orderPath), {
      paymentStatus: 'partial', paidTotal: 100, pendingTotal: 350,
    }));
  });

  it('preserva cancelacion administrativa auditada de pago y reapertura de articulos', async () => {
    await seedAdmin('admin-cancel');
    const orderPath = `restaurants/${RESTAURANT_ID}/orders/admin-cancel-order`;
    const itemPath = `${orderPath}/items/item-1`;
    const paymentPath = `${orderPath}/payments/payment-1`;
    await seed(orderPath, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'paid', paymentStatus: 'paid', total: 100,
      grossSubtotal: 100, netTotal: 100, paidTotal: 100, pendingTotal: 0,
      paidAt: new Date(),
    });
    await seed(itemPath, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'active', paymentStatus: 'paid', paymentId: 'payment-1', qty: 1, total: 100,
    });
    await seed(paymentPath, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'active', baseAmount: 100,
    });
    const db = adminDb('admin-cancel');
    const orderRef = doc(db, orderPath);
    const itemRef = doc(db, itemPath);
    const paymentRef = doc(db, paymentPath);
    await assertSucceeds(runTransaction(db, async (tx) => {
      await tx.get(orderRef);
      await tx.get(itemRef);
      await tx.get(paymentRef);
      tx.update(paymentRef, { status: 'cancelled' });
      tx.update(itemRef, { paymentStatus: 'pending' });
      tx.update(orderRef, {
        status: 'ready', paymentStatus: 'pending',
        paidTotal: 0, pendingTotal: 100, paidAt: null,
      });
      tx.set(doc(db, `restaurants/${RESTAURANT_ID}/activityLog/admin-cancel-audit`), {
        restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
        type: 'customer_payment_cancelled', orderId: 'admin-cancel-order',
      });
    }));
  });

  it('dos clientes concurrentes aplican abonos sin perder pagos ni sobrescribir agregados', async () => {
    const orderPath = `restaurants/${RESTAURANT_ID}/orders/concurrent-partials`;
    await seed(orderPath, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'ready', paymentStatus: 'pending', total: 450,
      grossSubtotal: 450, netTotal: 450, paidTotal: 0, pendingTotal: 450,
      captureRevision: 0,
    });
    const dbA = authedDb('cashier-a');
    const dbB = authedDb('cashier-b');
    const barrier = twoPartyBarrier();
    const runPartial = (db, paymentId, amount) => {
      let firstAttempt = true;
      const orderRef = doc(db, orderPath);
      const paymentRef = doc(db, `${orderPath}/payments/${paymentId}`);
      return runTransaction(db, async (tx) => {
        const order = await tx.get(orderRef);
        const payment = await tx.get(paymentRef);
        if (payment.exists()) return;
        if (firstAttempt) { firstAttempt = false; await barrier(); }
        const currentPaid = order.data().paidTotal;
        tx.set(paymentRef, {
          restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
          status: 'active', type: 'partial', baseAmount: amount,
        });
        tx.update(orderRef, {
          paidTotal: currentPaid + amount,
          pendingTotal: order.data().total - currentPaid - amount,
          paymentStatus: 'partial',
          captureRevision: increment(1),
        });
      });
    };
    await Promise.all([
      runPartial(dbA, 'payment-100', 100),
      runPartial(dbB, 'payment-150', 150),
    ]);
    const db = authedDb('verify-partials');
    const [order, payments] = await Promise.all([
      getDoc(doc(db, orderPath)),
      getDocs(collection(db, `${orderPath}/payments`)),
    ]);
    assert.strictEqual(payments.size, 2);
    assert.strictEqual(order.data().paidTotal, 250);
    assert.strictEqual(order.data().pendingTotal, 200);
  });

  it('captura concurrente con cobro completo se serializa por la revision compartida', async () => {
    const orderPath = `restaurants/${RESTAURANT_ID}/orders/capture-vs-checkout`;
    const itemPath = `${orderPath}/items/item-1`;
    await seed(orderPath, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'ready', paymentStatus: 'pending', total: 100,
      grossSubtotal: 100, netTotal: 100, paidTotal: 0, pendingTotal: 100,
      captureRevision: 0,
    });
    await seed(itemPath, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'active', paymentStatus: 'pending', qty: 1, total: 100,
    });
    const dbA = authedDb('capture-client');
    const dbB = authedDb('checkout-client');
    const orderA = doc(dbA, orderPath);
    const itemA = doc(dbA, itemPath);
    const orderB = doc(dbB, orderPath);
    const itemB = doc(dbB, itemPath);
    const barrier = twoPartyBarrier();
    let captureFirst = true;
    let checkoutFirst = true;
    const capture = runTransaction(dbA, async (tx) => {
      const order = await tx.get(orderA);
      if (captureFirst) { captureFirst = false; await barrier(); }
      if (['paid', 'cancelled'].includes(order.data().paymentStatus)) {
        throw new Error('terminal order');
      }
      const newItemRef = doc(dbA, `${orderPath}/items/late-item`);
      tx.set(newItemRef, {
        restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
        status: 'active', paymentStatus: 'pending', qty: 1, total: 25,
      });
      tx.update(orderA, { captureRevision: increment(1) });
    });
    const checkout = runTransaction(dbB, async (tx) => {
      const order = await tx.get(orderB);
      const item = await tx.get(itemB);
      if (checkoutFirst) { checkoutFirst = false; await barrier(); }
      if (order.data().captureRevision !== 0 || order.data().pendingTotal !== 100) {
        throw new Error('stale checkout snapshot');
      }
      tx.update(itemB, { paymentStatus: 'paid' });
      tx.update(orderB, {
        status: 'paid', paymentStatus: 'paid', paidTotal: 100,
        pendingTotal: 0, captureRevision: increment(1),
      });
    });
    const outcomes = await Promise.allSettled([capture, checkout]);
    assert.strictEqual(outcomes.filter((entry) => entry.status === 'fulfilled').length, 1);
    const verifyDb = authedDb('verify-race');
    const order = await getDoc(doc(verifyDb, orderPath));
    const lateItem = await getDoc(doc(verifyDb, `${orderPath}/items/late-item`));
    if (order.data().status === 'paid') {
      assert.strictEqual(lateItem.exists(), false);
    } else {
      assert.strictEqual(order.data().status, 'ready');
      assert.strictEqual(lateItem.exists(), true);
    }
  });

  it('envio contra cancelacion concurrentes dejan una sola transicion valida', async () => {
    const orderPath = `restaurants/${RESTAURANT_ID}/orders/send-vs-cancel`;
    const itemPath = `${orderPath}/items/item-1`;
    await seed(orderPath, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'open', paymentStatus: 'pending', total: 100,
      paidTotal: 0, pendingTotal: 100, captureRevision: 0,
    });
    await seed(itemPath, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'active', paymentStatus: 'pending', kitchenStatus: 'pending',
      sendToKitchen: true, qty: 1, total: 100,
    });
    const dbSend = authedDb('kitchen-send-client');
    const dbCancel = authedDb('cancel-client');
    const sendOrder = doc(dbSend, orderPath);
    const sendItem = doc(dbSend, itemPath);
    const cancelOrder = doc(dbCancel, orderPath);
    const cancelItem = doc(dbCancel, itemPath);
    const barrier = twoPartyBarrier();
    let sendFirst = true;
    let cancelFirst = true;
    const send = runTransaction(dbSend, async (tx) => {
      const order = await tx.get(sendOrder);
      const item = await tx.get(sendItem);
      if (sendFirst) { sendFirst = false; await barrier(); }
      if (item.data().status !== 'active' || order.data().status === 'cancelled') {
        throw new Error('not sendable');
      }
      tx.update(sendItem, { kitchenStatus: 'sent', kitchenBatchId: 'batch-1' });
      tx.update(sendOrder, { status: 'sent', captureRevision: increment(1) });
    });
    const cancel = runTransaction(dbCancel, async (tx) => {
      const order = await tx.get(cancelOrder);
      const item = await tx.get(cancelItem);
      if (cancelFirst) { cancelFirst = false; await barrier(); }
      if (item.data().kitchenStatus === 'sent' || order.data().status === 'sent') {
        throw new Error('already sent');
      }
      tx.update(cancelItem, { status: 'cancelled', kitchenStatus: 'cancelled', paymentStatus: 'cancelled' });
      tx.update(cancelOrder, { status: 'cancelled', paymentStatus: 'cancelled', captureRevision: increment(1) });
    });
    await Promise.allSettled([send, cancel]);
    const verifyDb = authedDb('verify-send-cancel');
    const [order, item] = await Promise.all([
      getDoc(doc(verifyDb, orderPath)), getDoc(doc(verifyDb, itemPath)),
    ]);
    assert.ok(['sent', 'cancelled'].includes(order.data().status));
    assert.strictEqual(item.data().kitchenStatus, order.data().status === 'sent' ? 'sent' : 'cancelled');
  });

  it('recálculo concurrente con cobro no reabre ni aplica agregados obsoletos', async () => {
    const orderPath = `restaurants/${RESTAURANT_ID}/orders/recalc-vs-checkout`;
    const itemPath = `${orderPath}/items/item-1`;
    await seed(orderPath, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'ready', paymentStatus: 'pending', total: 100,
      grossSubtotal: 100, netTotal: 100, paidTotal: 0, pendingTotal: 100,
      captureRevision: 0,
    });
    await seed(itemPath, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'active', paymentStatus: 'pending', qty: 1, unitPrice: 100, total: 100,
    });
    const dbRecalc = authedDb('recalc-client');
    const dbClose = authedDb('checkout-race-client');
    const orderRecalc = doc(dbRecalc, orderPath);
    const itemRecalc = doc(dbRecalc, itemPath);
    const orderClose = doc(dbClose, orderPath);
    const itemClose = doc(dbClose, itemPath);
    const barrier = twoPartyBarrier();
    let recalcFirst = true;
    let closeFirst = true;
    const recalc = runTransaction(dbRecalc, async (tx) => {
      const order = await tx.get(orderRecalc);
      const item = await tx.get(itemRecalc);
      if (recalcFirst) { recalcFirst = false; await barrier(); }
      if (order.data().status === 'paid') return;
      if (order.data().captureRevision !== 0) throw new Error('stale recalc');
      const gross = item.data().qty * item.data().unitPrice;
      tx.update(orderRecalc, {
        total: gross, grossSubtotal: gross, netTotal: gross,
        pendingTotal: gross - order.data().paidTotal,
        captureRevision: increment(1),
      });
    });
    const close = runTransaction(dbClose, async (tx) => {
      const order = await tx.get(orderClose);
      const item = await tx.get(itemClose);
      if (closeFirst) { closeFirst = false; await barrier(); }
      if (order.data().status === 'paid') return;
      if (order.data().captureRevision !== 0 || order.data().pendingTotal !== 100) {
        throw new Error('stale checkout');
      }
      tx.update(itemClose, { paymentStatus: 'paid' });
      tx.update(orderClose, {
        status: 'paid', paymentStatus: 'paid', paidTotal: 100,
        pendingTotal: 0, captureRevision: increment(1),
      });
    });
    await Promise.allSettled([recalc, close]);
    const verifyDb = authedDb('verify-recalc-close');
    const order = await getDoc(doc(verifyDb, orderPath));
    assert.ok(['ready', 'paid'].includes(order.data().status));
    if (order.data().status === 'paid') {
      assert.strictEqual(order.data().pendingTotal, 0);
      assert.strictEqual(order.data().paidTotal, 100);
    }
  });

  it('cancelar último producto deja borrador abierto para agregar y enviar nuevos productos', async () => {
    const orderPath = `restaurants/${RESTAURANT_ID}/orders/empty-draft-flow`;
    await seed(orderPath, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'open', paymentStatus: 'pending', total: 25,
      paidTotal: 0, pendingTotal: 25, captureRevision: 1,
    });
    await seed(`${orderPath}/items/first`, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'active', paymentStatus: 'pending', kitchenStatus: 'pending', qty: 1, total: 25,
    });
    const db = authedDb('waiter-flow');
    await assertSucceeds(updateDoc(doc(db, `${orderPath}/items/first`), {
      status: 'cancelled', paymentStatus: 'cancelled', kitchenStatus: 'cancelled',
      cancelStatus: 'accepted',
    }));
    await assertSucceeds(updateDoc(doc(db, orderPath), {
      status: 'open', paymentStatus: 'pending', total: 0,
      grossSubtotal: 0, netTotal: 0, paidTotal: 0, pendingTotal: 0,
    }));
    await assertSucceeds(setDoc(doc(db, `${orderPath}/items/replacement`), {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID,
      status: 'active', paymentStatus: 'pending', kitchenStatus: 'pending',
      sendToKitchen: true, qty: 2, total: 50,
    }));
    await assertSucceeds(runTransaction(db, async (tx) => {
      const orderRef = doc(db, orderPath);
      const itemRef = doc(db, `${orderPath}/items/replacement`);
      await tx.get(orderRef);
      await tx.get(itemRef);
      tx.update(itemRef, { kitchenStatus: 'sent', kitchenBatchId: 'batch-replacement' });
      tx.update(orderRef, { status: 'sent', total: 50, pendingTotal: 50 });
    }));
    const finalItem = await getDoc(doc(db, `${orderPath}/items/replacement`));
    const cancelledItem = await getDoc(doc(db, `${orderPath}/items/first`));
    assert.strictEqual(finalItem.data().kitchenStatus, 'sent');
    assert.strictEqual(cancelledItem.data().status, 'cancelled');
  });

  it('permite leer pagos mediante collectionGroup para calcular cierre', async () => {
    const db = authedDb('anon-manager');
    await seed(
      `restaurants/${RESTAURANT_ID}/orders/order-1/payments/payment-1`,
      {
        restaurantId: RESTAURANT_ID,
        branchId: BRANCH_ID,
        orderId: 'order-1',
        cashSessionId: 'cash-1',
        method: 'cash',
        status: 'active',
        baseAmount: 4136,
      },
    );

    await assertSucceeds(getDocs(collectionGroup(db, 'payments')));
  });

  it('permite caja y cocina validas', async () => {
    const db = authedDb('anon-manager');
    await assertSucceeds(
      setDoc(doc(db, `restaurants/${RESTAURANT_ID}/cashSessions/cash-1`), {
        restaurantId: RESTAURANT_ID,
        branchId: BRANCH_ID,
        businessDate: '2026-07-25',
        status: 'open',
      }),
    );
    await assertSucceeds(
      setDoc(doc(db, `restaurants/${RESTAURANT_ID}/kitchenSessions/kitchen-1`), {
        restaurantId: RESTAURANT_ID,
        branchId: BRANCH_ID,
        businessDate: '2026-07-25',
        status: 'open',
      }),
    );
  });

  it('permite crear el contador diario con secuencia 1', async () => {
    await assertSucceeds(
      setDoc(counterDoc(authedDb('cashier-1')), counterData({ lastSequence: 1 })),
    );
  });

  it('permite crear e incrementar el contador diario de cocina', async () => {
    await seed(devicePath('device-uid'), deviceData('device-uid'));
    const db = authedDb('device-uid');
    await assertSucceeds(
      setDoc(kitchenSequenceDoc(db), kitchenSequenceData()),
    );
    await assertSucceeds(
      updateDoc(kitchenSequenceDoc(db), {
        lastSequence: 2,
        updatedAt: new Date('2026-07-31T11:01:00.000Z'),
      }),
    );
  });

  it('rechaza saltar o borrar el contador diario de cocina', async () => {
    await seed(devicePath('device-uid'), deviceData('device-uid'));
    await seed(kitchenSequencePath(), kitchenSequenceData());
    const db = authedDb('device-uid');
    await assertFails(
      updateDoc(kitchenSequenceDoc(db), { lastSequence: 4 }),
    );
    await assertFails(deleteDoc(kitchenSequenceDoc(db)));
  });

  it('permite incrementar el contador diario de 1 a 2', async () => {
    await seed(counterPath(), counterData({ lastSequence: 1 }));

    await assertSucceeds(
      updateDoc(counterDoc(authedDb('cashier-1')), {
        lastSequence: 2,
        updatedAt: new Date('2026-07-31T11:01:00.000Z'),
        updatedByDeviceId: 'device-2',
      }),
    );
  });

  it('rechaza saltar el contador de 1 a 3', async () => {
    await seed(counterPath(), counterData({ lastSequence: 1 }));

    await assertFails(
      updateDoc(counterDoc(authedDb('cashier-1')), {
        lastSequence: 3,
        updatedAt: new Date('2026-07-31T11:01:00.000Z'),
        updatedByDeviceId: 'device-2',
      }),
    );
  });

  it('rechaza disminuir el contador diario', async () => {
    await seed(counterPath(), counterData({ lastSequence: 2 }));

    await assertFails(
      updateDoc(counterDoc(authedDb('cashier-1')), {
        lastSequence: 1,
        updatedAt: new Date('2026-07-31T11:01:00.000Z'),
        updatedByDeviceId: 'device-2',
      }),
    );
  });

  it('rechaza eliminar el contador diario', async () => {
    await seed(counterPath(), counterData({ lastSequence: 1 }));

    await assertFails(deleteDoc(counterDoc(authedDb('cashier-1'))));
  });

  it('rechaza crear contador con restaurantId alterado', async () => {
    await assertFails(
      setDoc(
        counterDoc(authedDb('cashier-1')),
        counterData({ restaurantId: 'otro' }),
      ),
    );
  });

  it('rechaza crear contador con branchId alterado', async () => {
    await assertFails(
      setDoc(
        counterDoc(authedDb('cashier-1')),
        counterData({ branchId: 'otra-sucursal' }),
      ),
    );
  });

  it('rechaza crear contador con businessDate alterado', async () => {
    await assertFails(
      setDoc(
        counterDoc(authedDb('cashier-1')),
        counterData({ businessDate: '2026-08-01' }),
      ),
    );
  });

  it('permite crear evento de auditoria de venta', async () => {
    await assertSucceeds(
      setDoc(auditDoc(authedDb('cashier-1')), auditEventData()),
    );
  });

  it('rechaza el payload anterior con serverTimestamp anidado en auditoria', async () => {
    assert.throws(
      () =>
        setDoc(
          auditDoc(authedDb('cashier-1')),
          auditEventData({
            paymentMethodsSnapshot: [
              {
                method: 'cash',
                amount: 120,
                createdAt: serverTimestamp(),
              },
            ],
          }),
        ),
      /FieldValue|serverTimestamp|Unsupported|invalid/i,
    );
  });

  it('rechaza modificar evento de auditoria de venta', async () => {
    await seed(auditPath(), auditEventData());

    await assertFails(
      updateDoc(auditDoc(authedDb('admin-1')), { reason: 'Cambio posterior' }),
    );
  });

  it('rechaza eliminar evento de auditoria de venta', async () => {
    await seed(auditPath(), auditEventData());

    await assertFails(deleteDoc(auditDoc(authedDb('admin-1'))));
  });

  it('permite leer eventos de auditoria a usuario autenticado', async () => {
    await seed(auditPath(), auditEventData());

    await assertSucceeds(getDoc(auditDoc(authedDb('admin-1'))));
  });

  it('rechaza leer o escribir contador y auditoria sin autenticacion', async () => {
    await seed(counterPath(), counterData({ lastSequence: 1 }));
    await seed(auditPath(), auditEventData());

    await assertFails(getDoc(counterDoc(anonDb())));
    await assertFails(getDoc(auditDoc(anonDb())));
    await assertFails(setDoc(counterDoc(anonDb()), counterData()));
    await assertFails(setDoc(auditDoc(anonDb()), auditEventData()));
  });

  it('rechaza otra sucursal cuando el payload no coincide con la ruta', async () => {
    const db = authedDb('cashier-1');

    await assertFails(
      setDoc(
        doc(
          db,
          `restaurants/${RESTAURANT_ID}/branches/otra-sucursal/dailySaleCounters/${BUSINESS_DATE}`,
        ),
        counterData({ branchId: BRANCH_ID }),
      ),
    );
  });

  it('permite la transaccion completa de cobro con folio diario', async () => {
    const db = authedDb('cashier-1');
    await seed(`restaurants/${RESTAURANT_ID}/orders/order-folio`, {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      status: 'ready',
      paymentStatus: 'pending',
      total: 120,
    });
    await seed(`restaurants/${RESTAURANT_ID}/orders/order-folio/items/item-1`, {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      paymentStatus: 'pending',
    });

    await assertSucceeds(
      runTransaction(db, async (transaction) => {
        const orderRef = doc(db, `restaurants/${RESTAURANT_ID}/orders/order-folio`);
        const itemRef = doc(db, `restaurants/${RESTAURANT_ID}/orders/order-folio/items/item-1`);
        const paymentRef = doc(db, `restaurants/${RESTAURANT_ID}/orders/order-folio/payments/payment-1`);
        const counterRef = counterDoc(db);
        const auditRef = auditDoc(db);
        await transaction.get(orderRef);
        await transaction.get(counterRef);
        transaction.set(counterRef, counterData({ lastSequence: 1 }));
        transaction.set(paymentRef, {
          restaurantId: RESTAURANT_ID,
          branchId: BRANCH_ID,
          orderId: 'order-folio',
          method: 'cash',
          status: 'active',
          saleFolioSequence: 1,
          saleFolioDisplay: '0001',
          saleFolioFull: 'AVI-2026-07-31-0001',
        });
        transaction.update(itemRef, {
          paymentStatus: 'paid',
          paymentId: 'payment-1',
          paidAt: new Date('2026-07-31T11:00:00.000Z'),
          updatedAt: new Date('2026-07-31T11:00:00.000Z'),
        });
        transaction.update(orderRef, {
          status: 'paid',
          paymentStatus: 'paid',
          paidTotal: 120,
          pendingTotal: 0,
          saleFolioSequence: 1,
          saleFolioDisplay: '0001',
          saleFolioFull: 'AVI-2026-07-31-0001',
          saleFolioBusinessDate: BUSINESS_DATE,
          saleFolioBranchId: BRANCH_ID,
          saleFolioRestaurantId: RESTAURANT_ID,
          saleFolioAssignedAt: new Date('2026-07-31T11:00:00.000Z'),
          saleFolioVersion: 1,
          updatedAt: new Date('2026-07-31T11:00:00.000Z'),
        });
        transaction.set(auditRef, auditEventData());
      }),
    );
  });

  it('permite orden y pago con campos de folio diario', async () => {
    const db = authedDb('cashier-1');
    await seed(`restaurants/${RESTAURANT_ID}/orders/order-fields`, {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      status: 'ready',
      paymentStatus: 'pending',
      total: 120,
    });

    await assertSucceeds(
      setDoc(
        doc(db, `restaurants/${RESTAURANT_ID}/orders/order-fields/payments/payment-1`),
        {
          restaurantId: RESTAURANT_ID,
          branchId: BRANCH_ID,
          orderId: 'order-fields',
          method: 'cash',
          status: 'active',
          saleFolioSequence: 1,
          saleFolioDisplay: '0001',
          saleFolioFull: 'AVI-2026-07-31-0001',
        },
      ),
    );
    await assertSucceeds(
      updateDoc(doc(db, `restaurants/${RESTAURANT_ID}/orders/order-fields`), {
        status: 'paid',
        paymentStatus: 'paid',
        paidTotal: 120,
        pendingTotal: 0,
        saleFolioSequence: 1,
        saleFolioDisplay: '0001',
        saleFolioFull: 'AVI-2026-07-31-0001',
        saleFolioBusinessDate: BUSINESS_DATE,
        saleFolioBranchId: BRANCH_ID,
        saleFolioRestaurantId: RESTAURANT_ID,
        saleFolioAssignedAt: new Date('2026-07-31T11:00:00.000Z'),
        saleFolioVersion: 1,
        updatedAt: new Date('2026-07-31T11:00:00.000Z'),
      }),
    );
  });

  it('permite cerrar cashSession con campos de cierre y registrar activityLog', async () => {
    const db = authedDb('anon-manager');
    await seed(`restaurants/${RESTAURANT_ID}/cashSessions/cash-close`, {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      businessDate: '2026-07-28',
      status: 'open',
      openingCashAmount: 0,
      countedCashAmount: 0,
      terminalReportedAmount: 0,
    });

    await assertSucceeds(
      updateDoc(doc(db, `restaurants/${RESTAURANT_ID}/cashSessions/cash-close`), {
        status: 'closed',
        countedCashAmount: 4136,
        terminalReportedAmount: 557,
        expectedCashAmount: 4100,
        expectedCardChargedAmount: 557,
        expectedCardBaseAmount: 557,
        expectedCardSurchargeAmount: 0,
        expectedCardFeeAbsorbedAmount: 0,
        expectedPlatformAmount: 0,
        expectedEmployeeConsumptionAmount: 0,
        approvedWithdrawalsTotal: 0,
        pendingWithdrawalsTotal: 0,
        withdrawalRequestCount: 0,
        totalExpectedRealMoney: 4657,
        totalCountedRealMoney: 4693,
        cashDifference: 36,
        cardDifference: 0,
        netDifference: 36,
        shortageAmount: 0,
        overAmount: 36,
        notes: '',
        closedAt: new Date('2026-07-29T06:12:00.000Z'),
        closedByEmployeeId: 'cashier-1',
        closedByEmployeeName: 'Caja',
        updatedAt: new Date('2026-07-29T06:12:00.000Z'),
      }),
    );

    await assertSucceeds(
      setDoc(doc(db, `restaurants/${RESTAURANT_ID}/activityLog/log-close`), {
        type: 'cash_close_shortage',
        restaurantId: RESTAURANT_ID,
        branchId: BRANCH_ID,
        cashSessionId: 'cash-close',
        businessDate: '2026-07-28',
        shortageAmount: 12,
        netDifference: -12,
        createdByEmployeeId: 'cashier-1',
        createdByEmployeeName: 'Caja',
        createdAt: new Date('2026-07-29T06:12:00.000Z'),
        createdBy: 'anon-manager',
      }),
    );
  });

  it('documenta que permisos por empleado requieren uid vinculado', async () => {
    await seed(`restaurants/${RESTAURANT_ID}/employees/waiter`, {
      active: true,
      canCharge: false,
      branchAccess: [{ branchId: BRANCH_ID, active: true }],
    });
    await assertSucceeds(
      setDoc(doc(authedDb('uid-sin-vinculo'), `restaurants/${RESTAURANT_ID}/orders/order-2`), {
        restaurantId: RESTAURANT_ID,
        branchId: BRANCH_ID,
        status: 'open',
      }),
    );
  });

  it('admin autorizado puede leer y actualizar appUpdates', async () => {
    await seedAdmin();
    await seed(appUpdatesPath(), {
      active: true,
      minimumVersionCode: 15,
      recommendedVersionCode: 16,
    });

    const db = adminDb();
    await assertSucceeds(getDoc(doc(db, appUpdatesPath())));
    await assertSucceeds(
      updateDoc(doc(db, appUpdatesPath()), {
        recommendedVersionCode: 17,
      }),
    );
  });

  it('usuario operativo puede leer appUpdates para comprobar version', async () => {
    await seed(appUpdatesPath(), {
      active: true,
      minimumVersionCode: 15,
      recommendedVersionCode: 16,
    });

    await assertSucceeds(getDoc(doc(authedDb('tablet-uid'), appUpdatesPath())));
  });

  it('usuario no autorizado no puede modificar appUpdates', async () => {
    await seed(appUpdatesPath(), {
      active: true,
      minimumVersionCode: 15,
      recommendedVersionCode: 16,
    });

    await assertFails(
      updateDoc(doc(authedDb('tablet-uid'), appUpdatesPath()), {
        recommendedVersionCode: 99,
      }),
    );
  });

  it('backoffice puede listar dispositivos y tablet puede actualizar solo su heartbeat', async () => {
    await seedAdmin();
    await seed(devicePath('device-uid'), deviceData('device-uid'));

    await assertSucceeds(getDocs(collection(adminDb(), `restaurants/${RESTAURANT_ID}/devices`)));
    await assertSucceeds(
      updateDoc(doc(authedDb('device-uid'), devicePath('device-uid')), {
        appVersionCode: 16,
        updateStatus: 'upToDate',
        lastSeenAt: new Date('2026-08-18T11:00:00.000Z'),
        updatedAt: new Date('2026-08-18T11:00:00.000Z'),
      }),
    );
  });

  it('usuario no autorizado no puede modificar dispositivos sensibles', async () => {
    await seed(devicePath('device-uid'), {
      ...deviceData('device-uid'),
      rolloutGroup: 'pilot',
    });

    await assertFails(
      updateDoc(doc(authedDb('device-uid'), devicePath('device-uid')), {
        rolloutGroup: 'all',
      }),
    );
    await assertFails(
      updateDoc(doc(authedDb('other-device'), devicePath('device-uid')), {
        updateStatus: 'upToDate',
      }),
    );
  });

  it('admin puede listar crear editar y activar politicas de gasto', async () => {
    await seedAdmin();
    const db = adminDb();

    await assertSucceeds(getDocs(collection(db, `restaurants/${RESTAURANT_ID}/expensePolicies`)));
    await assertSucceeds(setDoc(doc(db, policyPath('hielo')), policyData()));
    await assertSucceeds(
      updateDoc(doc(db, policyPath('hielo')), {
        maxAmountPerTransaction: 55,
        active: false,
      }),
    );
  });

  it('admin inactivo no puede crear politicas de gasto', async () => {
    await seedInactiveAdmin();

    await assertFails(
      setDoc(doc(authedDb('inactive-admin'), policyPath('hielo')), policyData()),
    );
  });

  it('admin de otro restaurante no puede administrar politicas cruzadas', async () => {
    await seedAdmin('cross-admin', 'otro-restaurante');

    await assertFails(
      setDoc(doc(authedDb('cross-admin'), policyPath('hielo')), policyData()),
    );
  });

  it('admin puede leer settings de politicas y consultar usage', async () => {
    await seedAdmin();
    await seed(expenseSettingsPath(), { expensePoliciesEnabled: false });
    await seed(usagePath(), {
      policyId: 'hielo',
      branchId: BRANCH_ID,
      periodKey: '2026-08-18',
      amountUsed: 40,
      usesUsed: 1,
      expenseIds: ['expense-1'],
    });

    const db = adminDb();
    await assertSucceeds(getDoc(doc(db, expenseSettingsPath())));
    await assertSucceeds(getDocs(collection(db, `restaurants/${RESTAURANT_ID}/expensePolicyUsage`)));
  });

  it('device restaurant A lee policy A y no lee restaurant B', async () => {
    await seed(devicePath('device-uid'), deviceData('device-uid'));
    await seed(policyPath('hielo'), policyData());
    await seed(policyPath('hielo', 'otro-restaurante'), policyData({
      restaurantId: 'otro-restaurante',
      branchId: BRANCH_ID,
    }));

    const db = authedDb('device-uid');
    await assertSucceeds(getDoc(doc(db, policyPath('hielo'))));
    await assertFails(getDoc(doc(db, policyPath('hielo', 'otro-restaurante'))));
  });

  it('device lista politicas activas solo de su branch para catalogo de gastos', async () => {
    await seed(devicePath('device-uid'), deviceData('device-uid'));
    await seed(policyPath('hielo'), policyData({ active: true, branchId: BRANCH_ID }));
    await seed(policyPath('otra-branch'), policyData({
      active: true,
      branchId: 'otra',
      code: 'otra-branch',
      name: 'Otra branch',
    }));

    const db = authedDb('device-uid');
    await assertSucceeds(
      getDocs(
        query(
          collection(db, `restaurants/${RESTAURANT_ID}/expensePolicies`),
          where('branchId', '==', BRANCH_ID),
        ),
      ),
    );
    await assertFails(
      getDocs(
        query(
          collection(db, `restaurants/${RESTAURANT_ID}/expensePolicies`),
          where('active', '==', true),
        ),
      ),
    );
  });

  it('device crea expense de su branch y no en otro branch', async () => {
    await seed(devicePath('device-uid'), deviceData('device-uid'));
    await seed(`restaurants/${RESTAURANT_ID}/cashSessions/cash-open`, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, status: 'open',
    });
    const db = authedDb('device-uid');
    const base = {
      id: 'request-1',
      clientRequestId: 'request-1',
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      cashSessionId: 'cash-open',
      businessDate: BUSINESS_DATE,
      amount: 40,
      reason: 'Hielo',
      status: 'approved',
      requestedByDeviceId: 'device-uid',
      requestedByEmployeeId: 'employee',
      requestedByEmployeeName: 'Empleado',
      policyId: 'hielo',
      autoApproved: true,
      wouldAutoApprove: false,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    };

    await assertSucceeds(
      setDoc(doc(db, `restaurants/${RESTAURANT_ID}/cashWithdrawalRequests/request-1`), base),
    );
    await assertFails(
      setDoc(doc(db, `restaurants/${RESTAURANT_ID}/cashWithdrawalRequests/request-2`), {
        ...base,
        id: 'request-2',
        clientRequestId: 'request-2',
        branchId: 'otra',
      }),
    );
  });

  it('device actualiza usage de su policy branch y cross restaurant usage falla', async () => {
    await seed(devicePath('device-uid'), deviceData('device-uid'));
    await seed(policyPath('hielo'), policyData({ branchId: BRANCH_ID }));
    const db = authedDb('device-uid');

    await assertSucceeds(
      setDoc(doc(db, usagePath('hielo-usage')), {
        policyId: 'hielo',
        branchId: BRANCH_ID,
        periodKey: 'hielo_aviacion:2026-07-31',
        amountUsed: 40,
        usesUsed: 1,
        expenseIds: ['request-1'],
        updatedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      updateDoc(doc(db, usagePath('hielo-usage')), {
        amountUsed: 80,
        usesUsed: 2,
        expenseIds: ['request-1', 'request-2'],
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(db, usagePath('hielo-usage', 'otro-restaurante')), {
        policyId: 'hielo',
        branchId: BRANCH_ID,
        periodKey: 'hielo_aviacion:2026-07-31',
        amountUsed: 40,
        usesUsed: 1,
        expenseIds: ['request-1'],
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('device puede confirmar transaccion local-first completa de gasto aprobado', async () => {
    await seed(devicePath('device-uid'), deviceData('device-uid'));
    await seed(policyPath('hielo'), policyData({ branchId: BRANCH_ID }));
    await seed(`restaurants/${RESTAURANT_ID}/cashSessions/cash-open`, {
      restaurantId: RESTAURANT_ID, branchId: BRANCH_ID, status: 'open',
    });
    const db = authedDb('device-uid');
    const requestId = 'request-local-first';

    await assertSucceeds(
      runTransaction(db, async (tx) => {
        await tx.get(doc(db, usagePath('hielo-aviacion-2026-07-31')));
        tx.set(doc(db, `restaurants/${RESTAURANT_ID}/cashWithdrawalRequests/${requestId}`), {
          id: requestId,
          clientRequestId: requestId,
          restaurantId: RESTAURANT_ID,
          branchId: BRANCH_ID,
          cashSessionId: 'cash-open',
          businessDate: BUSINESS_DATE,
          amount: 40,
          reason: 'Hielo',
          source: 'cash',
          sourceName: 'cash',
          supplierId: '',
          hasReceipt: false,
          requestedByDeviceId: 'device-uid',
          requestedByEmployeeId: 'employee',
          requestedByEmployeeName: 'Empleado',
          requestedAt: serverTimestamp(),
          status: 'approved',
          authorizedByEmployeeId: 'auto_policy',
          authorizedByEmployeeName: 'Politica de gasto',
          authorizedAt: serverTimestamp(),
          approvalSource: 'device_policy',
          approvedAt: serverTimestamp(),
          approvedByEmployeeId: 'auto_policy',
          approvedByEmployeeName: 'Politica de gasto',
          policyId: 'hielo',
          policyVersion: 1,
          policyName: 'Hielo',
          policySnapshot: { id: 'hielo', name: 'Hielo' },
          autoApproved: true,
          autoApprovedAt: serverTimestamp(),
          wouldAutoApprove: false,
          policyEvaluationMode: 'live',
          policyDecisionReasonCode: 'auto_approved',
          policyDecisionMessage: 'Dentro de politica',
          policyEvaluationReason: 'Dentro de politica',
          createdAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        });
        tx.set(doc(db, usagePath('hielo-aviacion-2026-07-31')), {
          policyId: 'hielo',
          branchId: BRANCH_ID,
          periodKey: 'hielo_aviacion:2026-07-31',
          amountUsed: 40,
          usesUsed: 1,
          expenseIds: [requestId],
          updatedAt: serverTimestamp(),
        });
        tx.set(doc(collection(db, `restaurants/${RESTAURANT_ID}/activityLog`)), {
          type: 'EXPENSE_AUTO_APPROVED_DEVICE',
          restaurantId: RESTAURANT_ID,
          branchId: BRANCH_ID,
          expenseId: requestId,
          policyId: 'hielo',
          policyName: 'Hielo',
          policyVersion: 1,
          policyDecisionReasonCode: 'auto_approved',
          policyDecisionMessage: 'Dentro de politica',
          policyEvaluationMode: 'live',
          amount: 40,
          employeeId: 'employee',
          employeeName: 'Empleado',
          deviceId: 'device-uid',
          approvalSource: 'device_policy',
          createdAt: serverTimestamp(),
        });
        tx.set(doc(db, `restaurants/${RESTAURANT_ID}/expenseRequestIdempotency/${requestId}`), {
          clientRequestId: requestId,
          requestId,
          result: {
            requestId,
            status: 'approved',
            autoApproved: true,
            amountUsed: 40,
            usesUsed: 1,
          },
          createdAt: serverTimestamp(),
          uid: 'device-uid',
        });
      }),
    );
  });

  it('usuario operativo no puede crear editar politicas ni modificar limites', async () => {
    await seed(policyPath('hielo'), policyData());
    const db = authedDb('waiter-uid');

    await assertFails(setDoc(doc(db, policyPath('garrafon')), policyData({ code: 'garrafon' })));
    await assertFails(
      updateDoc(doc(db, policyPath('hielo')), {
        maxAmountPerTransaction: 500,
      }),
    );
  });

  it('usuario operativo no puede modificar usage arbitrariamente', async () => {
    await seed(usagePath(), {
      policyId: 'hielo',
      branchId: BRANCH_ID,
      periodKey: '2026-08-18',
      amountUsed: 40,
      usesUsed: 1,
      expenseIds: ['expense-1'],
    });

    await assertFails(
      updateDoc(doc(authedDb('waiter-uid'), usagePath()), {
        amountUsed: 0,
        usesUsed: 0,
      }),
    );
  });

  it('expensePolicyUsage sigue protegido incluso para admin', async () => {
    await seedAdmin();
    await seed(usagePath(), {
      policyId: 'hielo',
      branchId: BRANCH_ID,
      periodKey: '2026-08-18',
      amountUsed: 40,
      usesUsed: 1,
      expenseIds: ['expense-1'],
    });

    await assertFails(
      updateDoc(doc(adminDb(), usagePath()), {
        amountUsed: 0,
        usesUsed: 0,
      }),
    );
  });

  it('usuario no autorizado no puede autoaprobar gasto por escritura directa', async () => {
    await seed(`restaurants/${RESTAURANT_ID}/cashWithdrawalRequests/expense-1`, {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      cashSessionId: 'cash-1',
      businessDate: BUSINESS_DATE,
      amount: 40,
      reason: 'Hielo',
      status: 'pending',
    });

    await assertFails(
      updateDoc(doc(authedDb('waiter-uid'), `restaurants/${RESTAURANT_ID}/cashWithdrawalRequests/expense-1`), {
        status: 'approved',
        autoApproved: true,
        policySnapshot: { policyId: 'hielo', policyVersion: 1 },
      }),
    );
  });

  it('mantiene orders payments cuts y expenses existentes protegidos', async () => {
    await seed(devicePath('cashier-1'), deviceData('cashier-1'));
    const db = authedDb('cashier-1');
    await assertSucceeds(
      setDoc(doc(db, `restaurants/${RESTAURANT_ID}/orders/order-rules`), {
        restaurantId: RESTAURANT_ID,
        branchId: BRANCH_ID,
        status: 'open',
      }),
    );
    await assertSucceeds(
      setDoc(doc(db, `restaurants/${RESTAURANT_ID}/orders/order-rules/payments/payment-1`), {
        restaurantId: RESTAURANT_ID,
        branchId: BRANCH_ID,
        status: 'active',
      }),
    );
    await assertSucceeds(
      setDoc(doc(db, `restaurants/${RESTAURANT_ID}/cashSessions/cash-rules`), {
        restaurantId: RESTAURANT_ID,
        branchId: BRANCH_ID,
        status: 'open',
      }),
    );
    await assertSucceeds(
      setDoc(doc(db, `restaurants/${RESTAURANT_ID}/cashWithdrawalRequests/expense-rules`), {
        id: 'expense-rules',
        clientRequestId: 'expense-rules',
        restaurantId: RESTAURANT_ID,
        branchId: BRANCH_ID,
        cashSessionId: 'cash-rules',
        businessDate: BUSINESS_DATE,
        amount: 40,
        reason: 'Hielo',
        status: 'pending',
        requestedByDeviceId: 'cashier-1',
        policyId: '',
        autoApproved: false,
        wouldAutoApprove: false,
      }),
    );
  });

  it('rechaza pagos y autorizaciones cuando la caja esta closing', async () => {
    const sessionId = 'cash-closing';
    await seed(`restaurants/${RESTAURANT_ID}/cashSessions/${sessionId}`, {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      status: 'closing',
    });
    await seedAdmin();
    await seed(`restaurants/${RESTAURANT_ID}/cashWithdrawalRequests/closing-expense`, {
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      cashSessionId: sessionId,
      businessDate: BUSINESS_DATE,
      amount: 40,
      reason: 'Hielo',
      status: 'pending',
      policyId: '',
      autoApproved: false,
      wouldAutoApprove: false,
    });

    await assertFails(
      setDoc(
        doc(authedDb('cashier'), `restaurants/${RESTAURANT_ID}/orders/closing-order/payments/late-payment`),
        {
          restaurantId: RESTAURANT_ID,
          branchId: BRANCH_ID,
          cashSessionId: sessionId,
          status: 'active',
        },
      ),
    );
    await assertFails(
      updateDoc(
        doc(adminDb(), `restaurants/${RESTAURANT_ID}/cashWithdrawalRequests/closing-expense`),
        { status: 'approved' },
      ),
    );
  });

  it('no permite acceso cross-restaurant para admin de otro restaurante', async () => {
    await seedAdmin('admin-uid', RESTAURANT_ID);
    await seed(policyPath('hielo', 'otro-restaurante'), policyData({
      restaurantId: 'otro-restaurante',
      branchId: BRANCH_ID,
    }));

    await assertFails(
      updateDoc(doc(adminDb('admin-uid'), policyPath('hielo', 'otro-restaurante')), {
        maxAmountPerTransaction: 100,
      }),
    );
  });
});
