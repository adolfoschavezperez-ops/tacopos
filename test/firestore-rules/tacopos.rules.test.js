const fs = require('fs');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc } = require('firebase/firestore');

const PROJECT_ID = 'tacopos-renovadev-rules-test';
const RESTAURANT_ID = 'tacopos';
const BRANCH_ID = 'aviacion';

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
  await testEnv.cleanup();
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
