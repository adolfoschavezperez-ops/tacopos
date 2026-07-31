const fs = require('fs');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  runTransaction,
  setDoc,
  updateDoc,
} = require('firebase/firestore');

const PROJECT_ID = 'tacopos-renovadev';
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

function counterPath() {
  return `restaurants/${RESTAURANT_ID}/branches/${BRANCH_ID}/dailySaleCounters/${BUSINESS_DATE}`;
}

function counterDoc(db) {
  return doc(db, counterPath());
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

describe('TacoPOS Firestore production guard rails', () => {
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
});
