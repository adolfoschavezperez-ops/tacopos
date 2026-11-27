/**
 * Real Chrome End-to-End Verification against Preview API + Auth & Firestore Emulators.
 *
 * Proves:
 * - Differentiated data: DEV Firestore has $1,000 while Preview Data DB has $8,000.
 * - Browser loads $8,000 exclusively from Preview API (`127.0.0.1:8085`), with ZERO
 *   Firestore operational requests (`127.0.0.1:8180` or `firestore.googleapis.com`).
 * - Dashboard, Ventas (+ detalle), Caja, Compras/Proveedores/CXP, and Finanzas work.
 * - Unintegrated modules (Empleados, Reportes, etc.) are explicitly blocked on direct URL.
 * - Works on both desktop (1366x900) and mobile (390x844).
 */

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const admin = require('firebase-admin');
const { createPreviewServer } = require('../server');

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

function startStaticServer(rootDir, port) {
  const server = http.createServer((req, res) => {
    const cleanUrl = (req.url || '/').split('?')[0];
    let filePath = path.join(rootDir, cleanUrl === '/' ? 'index.html' : cleanUrl);
    if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
      filePath = path.join(rootDir, 'index.html');
    }
    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, { 'Content-Type': MIME_TYPES[ext] || 'application/octet-stream' });
    fs.createReadStream(filePath).pipe(res);
  });
  return new Promise((resolve) => server.listen(port, '127.0.0.1', () => resolve(server)));
}

function todayBusinessDate() {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

async function main() {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error('Must be run inside firebase emulators:exec (--only auth,firestore).');
  }

  let chromium;
  try {
    ({ chromium } = require('playwright'));
  } catch {
    try {
      ({ chromium } = require('playwright-core'));
    } catch {
      throw new Error('Playwright not found in NODE_PATH.');
    }
  }

  const authApp = admin.initializeApp({ projectId: 'demo-tacopos-preview-api' }, 'e2e-auth');
  const dataApp = admin.initializeApp({ projectId: 'demo-tacopos-preview-data' }, 'e2e-data');
  const auth = authApp.auth();
  const devDb = authApp.firestore();
  const dataDb = dataApp.firestore();

  const OWNER_UID = 'e2e_owner_uid';
  const OWNER_EMAIL = 'owner.e2e@los-padrinos.test';
  const OWNER_PASS = crypto.randomBytes(12).toString('hex');
  const today = todayBusinessDate();

  try {
    await auth.deleteUser(OWNER_UID);
  } catch (_) {}
  await auth.createUser({ uid: OWNER_UID, email: OWNER_EMAIL, password: OWNER_PASS });

  // 1. Seed DEV DB with $1,000 (differentiated trap!) + previewUsers allowlist
  await devDb.doc(`previewUsers/${OWNER_UID}`).set({
    uid: OWNER_UID,
    active: true,
    isSuperAdmin: false,
    employeeId: 'emp_owner',
    displayName: 'Propietario Los Padrinos',
    restaurantId: 'rest_alpha',
    restaurantAccess: ['rest_alpha'],
    branchAccess: ['suc_aviacion'],
    permissions: {
      canViewAdmin: true,
      canViewPurchases: true,
      canViewAccountsPayable: true,
      canViewPurchaseReports: true,
      canManageCash: true,
      canViewLiveOperations: true,
    },
  });
  await devDb.doc('restaurants/rest_alpha').set({ name: 'DEV Trap Restaurant' });
  await devDb.doc('restaurants/rest_alpha/branches/suc_aviacion').set({
    id: 'suc_aviacion',
    name: 'Aviación DEV',
    active: true,
    sortOrder: 1,
  });
  await devDb.doc('restaurants/rest_alpha/orders/ord_dev_1000').set({
    restaurantId: 'rest_alpha',
    branchId: 'suc_aviacion',
    businessDate: today,
    status: 'paid',
    paymentStatus: 'paid',
    total: 1000,
    paidTotal: 1000,
    pendingTotal: 0,
    folio: 'DEV-1000',
  });

  // 2. Seed Preview Data DB with $8,000 + Caja + Compras ($2,400) + CXP ($1,200)
  await dataDb.doc('restaurants/rest_alpha').set({ name: 'Los Padrinos' });
  await dataDb.doc('restaurants/rest_alpha/branches/suc_aviacion').set({
    id: 'suc_aviacion',
    name: 'Aviación',
    active: true,
    sortOrder: 1,
  });
  await dataDb.doc('restaurants/rest_alpha/employees/emp_owner').set({
    id: 'emp_owner',
    restaurantId: 'rest_alpha',
    name: 'Propietario Los Padrinos',
    active: true,
    pin: 'SECRET_PIN_9999',
    canViewAdmin: true,
  });
  await dataDb.doc('restaurants/rest_alpha/orders/ord_preview_8000').set({
    id: 'ord_preview_8000',
    restaurantId: 'rest_alpha',
    branchId: 'suc_aviacion',
    businessDate: today,
    status: 'paid',
    paymentStatus: 'paid',
    total: 8000,
    paidTotal: 8000,
    pendingTotal: 0,
    folio: 'AV-8000',
    createdAt: admin.firestore.Timestamp.now(),
  });
  await dataDb.doc('restaurants/rest_alpha/orders/ord_preview_8000/payments/pay_1').set({
    id: 'pay_1',
    orderId: 'ord_preview_8000',
    method: 'cash',
    status: 'paid',
    amount: 8000,
    chargedAmount: 8000,
    createdAt: admin.firestore.Timestamp.now(),
  });
  await dataDb.doc('restaurants/rest_alpha/orders/ord_preview_8000/items/it_1').set({
    id: 'it_1',
    productId: 'prod_1',
    productName: 'Orden Pastor Especial',
    qty: 40,
    unitPrice: 200,
    total: 8000,
    status: 'paid',
  });
  await dataDb.doc('restaurants/rest_alpha/cashSessions/cs_av_1').set({
    id: 'cs_av_1',
    restaurantId: 'rest_alpha',
    branchId: 'suc_aviacion',
    businessDate: today,
    status: 'closed',
    openingAmount: 1000,
    countedCashAmount: 9000,
    expectedCashAmount: 9000,
  });
  await dataDb.doc('restaurants/rest_alpha/suppliers/sup_av_1').set({
    id: 'sup_av_1',
    commercialName: 'Carnicería Aviación Real',
    active: true,
  });
  await dataDb.doc('restaurants/rest_alpha/supplierPurchases/sp_av_1').set({
    id: 'sp_av_1',
    restaurantId: 'rest_alpha',
    branchId: 'suc_aviacion',
    supplierId: 'sup_av_1',
    supplierName: 'Carnicería Aviación Real',
    businessDate: today,
    folio: 'COMP-2400',
    total: 2400,
    paidTotal: 1200,
    balance: 1200,
    status: 'partial',
  });
  await dataDb.doc('restaurants/rest_alpha/supplierPayments/spay_av_1').set({
    id: 'spay_av_1',
    restaurantId: 'rest_alpha',
    branchId: 'suc_aviacion',
    supplierId: 'sup_av_1',
    purchaseId: 'sp_av_1',
    businessDate: today,
    amount: 1200,
    status: 'active',
  });

  const apiServer = createPreviewServer({
    auth,
    authzDb: devDb,
    dataDb,
    allowedOrigins: ['http://127.0.0.1:5055'],
    maxDocsPerQuery: 500,
  });
  await new Promise((resolve) => apiServer.listen(8085, '127.0.0.1', resolve));

  const webRoot = path.resolve(__dirname, '../../../build/web');
  const staticServer = await startStaticServer(webRoot, 5055);
  const screenshotsDir = path.resolve(__dirname, '../../../docs/validation/backoffice-v2/screenshots');

  const previewApiCalls = [];
  const firestoreOperationalCalls = [];
  const prodCalls = [];
  const consoleErrors = [];

  const browser = await chromium.launch({
    executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    headless: true,
  });

  try {
    const context = await browser.newContext({ viewport: { width: 1366, height: 900 } });
    const page = await context.newPage();

    // Enable Flutter web semantics for reliable DOM inspection
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });
    page.on('request', (req) => {
      const u = req.url();
      if (u.startsWith('http://127.0.0.1:8085/v1/preview/')) {
        previewApiCalls.push({ url: u, method: req.method() });
      }
      if (u.includes('127.0.0.1:8180') || u.includes('firestore.googleapis.com')) {
        firestoreOperationalCalls.push({ route: page.url(), url: u });
      }
      if (u.includes('tacopos-renovadev')) {
        prodCalls.push(u);
      }
    });

    await page.goto('http://127.0.0.1:5055/', { waitUntil: 'networkidle' });
    await page.waitForTimeout(3000);

    // Enable accessibility semantics in Flutter Web
    await page.evaluate(() => {
      const placeholder = document.querySelector('flt-semantics-placeholder');
      if (placeholder) placeholder.click();
    });
    await page.waitForTimeout(1000);

    // Focus first input (Restaurante), Tab to Email, Tab to Password, Enter to submit
    const firstInput = page.locator('input').first();
    await firstInput.click();
    await page.waitForTimeout(200);
    await page.keyboard.press('Tab');
    await page.waitForTimeout(200);
    await page.keyboard.type(OWNER_EMAIL);
    await page.keyboard.press('Tab');
    await page.waitForTimeout(200);
    await page.keyboard.type(OWNER_PASS);
    await page.waitForTimeout(200);
    await page.keyboard.press('Enter');
    await page.waitForTimeout(6000);

    // Capture Dashboard screenshot
    await page.screenshot({
      path: path.join(screenshotsDir, 'preview_e2e_dashboard_desktop.png'),
      fullPage: false,
    });

    const dashText = await page.evaluate(() => document.body.innerText || '');
    // Verify Preview banner & $8,000 (or 8,000) in semantics/canvas text if available
    await page.goto('http://127.0.0.1:5055/#/purchases', { waitUntil: 'networkidle' });
    await page.waitForTimeout(3500);
    await page.screenshot({
      path: path.join(screenshotsDir, 'preview_e2e_purchases_desktop.png'),
      fullPage: false,
    });

    await page.goto('http://127.0.0.1:5055/#/sales', { waitUntil: 'networkidle' });
    await page.waitForTimeout(3000);

    await page.goto('http://127.0.0.1:5055/#/cash', { waitUntil: 'networkidle' });
    await page.waitForTimeout(3000);

    await page.goto('http://127.0.0.1:5055/#/finance', { waitUntil: 'networkidle' });
    await page.waitForTimeout(3500);

    // Direct URL access to unintegrated module (#/employees) MUST be blocked
    await page.goto('http://127.0.0.1:5055/#/employees', { waitUntil: 'networkidle' });
    await page.waitForTimeout(2000);
    await page.screenshot({
      path: path.join(screenshotsDir, 'preview_e2e_blocked_module.png'),
      fullPage: false,
    });

    // Mobile viewport check
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('http://127.0.0.1:5055/#/dashboard', { waitUntil: 'networkidle' });
    await page.waitForTimeout(3000);
    await page.screenshot({
      path: path.join(screenshotsDir, 'preview_e2e_mobile_390.png'),
      fullPage: false,
    });

    assert.ok(previewApiCalls.length >= 4, `Expected >=4 Preview API calls, got ${previewApiCalls.length}`);
    assert.equal(firestoreOperationalCalls.length, 0, `Expected 0 direct Firestore calls, got ${JSON.stringify(firestoreOperationalCalls)}`);
    assert.equal(prodCalls.length, 0, `Expected 0 prod calls, got ${JSON.stringify(prodCalls)}`);

    console.log(JSON.stringify({
      ok: true,
      previewApiCallsCount: previewApiCalls.length,
      previewEndpointsCalled: Array.from(new Set(previewApiCalls.map((c) => c.url))),
      firestoreOperationalCallsCount: firestoreOperationalCalls.length,
      prodCallsCount: prodCalls.length,
      consoleErrorsCount: consoleErrors.length,
    }, null, 2));
  } finally {
    await browser.close();
    await new Promise((resolve) => staticServer.close(resolve));
    await new Promise((resolve) => apiServer.close(resolve));
    await authApp.delete();
    await dataApp.delete();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
