/**
 * Synthetic seed script for Backoffice 2.0 LOCAL Firebase Emulator Suite.
 *
 * Strictly connects ONLY to local emulators (127.0.0.1:8180 / 9199).
 * Refuses to run if FIRESTORE_EMULATOR_HOST is not pointing to localhost/127.0.0.1.
 */

const fs = require('node:fs');
const path = require('node:path');

const FIRESTORE_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180';
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9199';
const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-tacopos-backoffice-v2';

if (
  !FIRESTORE_HOST.startsWith('127.0.0.1:') &&
  !FIRESTORE_HOST.startsWith('localhost:')
) {
  throw new Error(
    `Refusing to seed non-local Firestore host: ${FIRESTORE_HOST}`,
  );
}
if (!PROJECT_ID.startsWith('demo-')) {
  throw new Error(`Refusing to seed non-demo projectId: ${PROJECT_ID}`);
}

process.env.FIRESTORE_EMULATOR_HOST = FIRESTORE_HOST;
process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_HOST;

const admin = require(
  path.resolve(__dirname, '../functions/node_modules/firebase-admin'),
);

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();
const auth = admin.auth();

function formatDate(d) {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

async function ensureAuthUser(uid, email, password, displayName) {
  try {
    await auth.getUser(uid);
  } catch {
    await auth.createUser({ uid, email, password, displayName });
  }
}

async function seedRestaurant({
  restaurantId,
  name,
  branches,
  adminUid,
  adminEmail,
  adminName,
  pin,
  daysCount,
}) {
  const restRef = db.collection('restaurants').doc(restaurantId);
  await restRef.set({
    name,
    active: true,
    synthetic: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await ensureAuthUser(adminUid, adminEmail, 'DevPass2026!', adminName);

  await restRef.collection('employees').doc(adminUid).set({
    id: adminUid,
    name: adminName,
    active: true,
    pin,
    canViewAdmin: true,
    canManageEmployees: true,
    canManageProducts: true,
    canAuthorizeCashWithdrawals: true,
  });

  await restRef.collection('authUsers').doc(adminUid).set({
    employeeId: adminUid,
    displayName: adminName,
    active: true,
    isSuperAdmin: true,
    branchAccess: branches.map((b) => b.id),
    permissions: {
      canViewAdmin: true,
      canManageEmployees: true,
      canManageProducts: true,
      canAuthorizeCashWithdrawals: true,
    },
  });

  for (let i = 0; i < branches.length; i++) {
    const b = branches[i];
    await restRef.collection('branches').doc(b.id).set({
      id: b.id,
      restaurantId,
      restaurantName: name,
      name: b.name,
      normalizedName: b.id,
      active: true,
      sortOrder: i + 1,
      timezone: 'America/Mexico_City',
    });
  }

  const now = new Date();
  const products = [
    { id: 'p_pastor', name: 'Orden Tacos al Pastor', category: 'Tacos', price: 125 },
    { id: 'p_asada', name: 'Gringa de Asada', category: 'Especialidades', price: 145 },
    { id: 'p_agua', name: 'Agua de Horchata 1L', category: 'Bebidas', price: 55 },
    { id: 'p_volcan', name: 'Volcán de Arrachera', category: 'Especialidades', price: 78 },
  ];

  let orderCounter = 1;
  for (let dayOffset = 0; dayOffset < daysCount; dayOffset++) {
    const dateObj = new Date(now.getFullYear(), now.getMonth(), now.getDate() - dayOffset);
    const businessDate = formatDate(dateObj);

    for (const branch of branches) {
      const ordersInDay = 3 + ((dayOffset + branch.seedWeight) % 3);
      for (let k = 0; k < ordersInDay; k++) {
        const ordId = `ord_${restaurantId}_${branch.id}_${businessDate}_${k + 1}`;
        const createdAt = new Date(
          dateObj.getFullYear(),
          dateObj.getMonth(),
          dateObj.getDate(),
          13 + k * 2,
          15 + k * 7,
        );
        const prodA = products[(dayOffset + k) % products.length];
        const prodB = products[(dayOffset + k + 1) % products.length];
        const qtyA = 2 + (k % 2);
        const qtyB = 1 + (dayOffset % 2);
        const total = prodA.price * qtyA + prodB.price * qtyB;
        const isCancelled = dayOffset === 2 && k === 2;
        const status = isCancelled ? 'cancelled' : 'paid';
        const method = k % 3 === 0 ? 'card' : k % 3 === 1 ? 'cash' : 'platform';
        const folio = `V-${String(orderCounter++).padStart(4, '0')}`;

        const ordRef = restRef.collection('orders').doc(ordId);
        await ordRef.set({
          id: ordId,
          restaurantId,
          restaurantName: name,
          branchId: branch.id,
          branchName: branch.name,
          tableId: method === 'platform' ? 'takeout' : `mesa_${(k % 5) + 1}`,
          tableName: method === 'platform' ? '' : `Mesa ${(k % 5) + 1}`,
          orderType: method === 'platform' ? 'takeout' : 'dine_in',
          platformName: method === 'platform' ? 'Uber Eats' : null,
          status,
          kitchenStatus: 'ready',
          paymentStatus: isCancelled ? 'cancelled' : 'paid',
          total,
          paidTotal: isCancelled ? 0 : total,
          pendingTotal: 0,
          personNames: { '1': `Cliente ${folio}` },
          businessDate,
          saleFolioFull: folio,
          saleFolioDisplay: folio,
          createdAt: admin.firestore.Timestamp.fromDate(createdAt),
          updatedAt: admin.firestore.Timestamp.fromDate(createdAt),
          paidAt: isCancelled ? null : admin.firestore.Timestamp.fromDate(createdAt),
        });

        await ordRef.collection('items').doc('item_1').set({
          productId: prodA.id,
          productName: prodA.name,
          category: prodA.category,
          qty: qtyA,
          unitPrice: prodA.price,
          total: prodA.price * qtyA,
          personNumber: 1,
          personName: `Cliente ${folio}`,
          notes: '',
          sendToKitchen: true,
          kitchenStatus: 'ready',
          paymentStatus: isCancelled ? 'cancelled' : 'paid',
          status: isCancelled ? 'cancelled' : 'active',
        });

        await ordRef.collection('items').doc('item_2').set({
          productId: prodB.id,
          productName: prodB.name,
          category: prodB.category,
          qty: qtyB,
          unitPrice: prodB.price,
          total: prodB.price * qtyB,
          personNumber: 1,
          personName: `Cliente ${folio}`,
          notes: 'Sin cebolla',
          sendToKitchen: true,
          kitchenStatus: 'ready',
          paymentStatus: isCancelled ? 'cancelled' : 'paid',
          status: isCancelled ? 'cancelled' : 'active',
        });

        if (!isCancelled) {
          await ordRef.collection('payments').doc('pay_1').set({
            orderId: ordId,
            tableId: method === 'platform' ? 'takeout' : `mesa_${(k % 5) + 1}`,
            tableName: method === 'platform' ? '' : `Mesa ${(k % 5) + 1}`,
            type: method,
            method,
            baseAmount: total,
            surchargeRate: 0,
            surchargeAmount: 0,
            chargedAmount: total,
            appliedAmount: total,
            businessDate,
            cashSessionId: `cs_${branch.id}_${businessDate}`,
            createdBy: adminUid,
            createdByEmployeeName: adminName,
            status: 'active',
            restaurantId,
            branchId: branch.id,
            createdAt: admin.firestore.Timestamp.fromDate(createdAt),
          });
        }
      }
    }
  }
}

async function main() {
  await seedRestaurant({
    restaurantId: 'rest_alpha',
    name: 'Taquería Los Padrinos (Demo Alpha)',
    branches: [
      { id: 'suc_centro', name: 'Sucursal Centro', seedWeight: 1 },
      { id: 'suc_norte', name: 'Sucursal Norte', seedWeight: 2 },
    ],
    adminUid: 'alpha_admin_1',
    adminEmail: 'admin.alpha@tacopos-dev.local',
    adminName: 'Adolfo Chávez (Admin)',
    pin: '1234',
    daysCount: 7,
  });

  await seedRestaurant({
    restaurantId: 'rest_beta',
    name: 'Tacos El Norte (Demo Beta)',
    branches: [
      { id: 'suc_sur', name: 'Sucursal Sur', seedWeight: 1 },
    ],
    adminUid: 'beta_admin_1',
    adminEmail: 'admin.beta@tacopos-dev.local',
    adminName: 'Sofía Martínez (Admin)',
    pin: '5678',
    daysCount: 4,
  });

  console.log('Seeded synthetic Backoffice 2.0 emulator data successfully.');
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
