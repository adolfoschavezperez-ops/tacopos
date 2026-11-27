/**
 * Synthetic 90-day demo seeder for `tacopos-backoffice-dev` ONLY.
 *
 * Uses `gcloud auth print-access-token` with Firestore & IdentityToolkit REST APIs.
 * Safety guards:
 * - Refuses to run unless TARGET_PROJECT === 'tacopos-backoffice-dev'.
 * - Never writes passwords to disk, Git, or logs (only prints generated eval
 *   credentials once to stdout).
 */

const crypto = require('node:crypto');
const { execSync } = require('node:child_process');

const TARGET_PROJECT = 'tacopos-backoffice-dev';
const FORBIDDEN_PROJECTS = new Set(['tacopos-renovadev', 'tacopos-control']);

if (process.env.GCLOUD_PROJECT && process.env.GCLOUD_PROJECT !== TARGET_PROJECT) {
  throw new Error(`Refusing to run against project ${process.env.GCLOUD_PROJECT}`);
}
if (FORBIDDEN_PROJECTS.has(TARGET_PROJECT)) {
  throw new Error(`Forbidden project ${TARGET_PROJECT}`);
}

const ACCESS_TOKEN = execSync('gcloud auth print-access-token', {
  encoding: 'utf8',
}).trim();

const HEADERS = {
  Authorization: `Bearer ${ACCESS_TOKEN}`,
  'x-goog-user-project': TARGET_PROJECT,
  'Content-Type': 'application/json',
};

function toFsValue(val) {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === 'boolean') return { booleanValue: val };
  if (typeof val === 'number') {
    return Number.isInteger(val)
      ? { integerValue: String(val) }
      : { doubleValue: val };
  }
  if (typeof val === 'string') return { stringValue: val };
  if (val instanceof Date) return { timestampValue: val.toISOString() };
  if (Array.isArray(val)) {
    return { arrayValue: { values: val.map(toFsValue) } };
  }
  if (typeof val === 'object') {
    const fields = {};
    for (const [k, v] of Object.entries(val)) {
      if (v !== undefined) fields[k] = toFsValue(v);
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(val) };
}

function makeWrite(docPath, data) {
  const fields = {};
  for (const [k, v] of Object.entries(data)) {
    if (v !== undefined) fields[k] = toFsValue(v);
  }
  return {
    update: {
      name: `projects/${TARGET_PROJECT}/databases/(default)/documents/${docPath}`,
      fields,
    },
  };
}

async function commitWrites(writes) {
  const url = `https://firestore.googleapis.com/v1/projects/${TARGET_PROJECT}/databases/(default)/documents:commit`;
  const chunkSize = 400;
  for (let i = 0; i < writes.length; i += chunkSize) {
    const chunk = writes.slice(i, i + chunkSize);
    const res = await fetch(url, {
      method: 'POST',
      headers: HEADERS,
      body: JSON.stringify({ writes: chunk }),
    });
    if (!res.ok) {
      const txt = await res.text();
      throw new Error(`Firestore commit failed (${res.status}): ${txt}`);
    }
  }
}

async function ensureEvalUser(email, displayName) {
  const password = `${crypto.randomBytes(9).toString('base64url')}!7Aa`;
  const lookupRes = await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${TARGET_PROJECT}/accounts:lookup`,
    {
      method: 'POST',
      headers: HEADERS,
      body: JSON.stringify({ email: [email] }),
    },
  );
  const lookupJson = await lookupRes.json();
  const existing = lookupJson.users && lookupJson.users[0];

  if (existing && existing.localId) {
    const updRes = await fetch(
      `https://identitytoolkit.googleapis.com/v1/projects/${TARGET_PROJECT}/accounts:update`,
      {
        method: 'POST',
        headers: HEADERS,
        body: JSON.stringify({
          localId: existing.localId,
          password,
          displayName,
          emailVerified: true,
        }),
      },
    );
    if (!updRes.ok) {
      throw new Error(`Failed updating eval user: ${await updRes.text()}`);
    }
    return { uid: existing.localId, email, password };
  }

  const createRes = await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${TARGET_PROJECT}/accounts`,
    {
      method: 'POST',
      headers: HEADERS,
      body: JSON.stringify({
        email,
        password,
        displayName,
        emailVerified: true,
      }),
    },
  );
  const createJson = await createRes.json();
  if (!createRes.ok || !createJson.localId) {
    throw new Error(`Failed creating eval user: ${JSON.stringify(createJson)}`);
  }
  return { uid: createJson.localId, email, password };
}

function formatDate(d) {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

async function main() {
  const evalEmail = 'evaluador@tacopos-backoffice-dev.local';
  const evalUser = await ensureEvalUser(
    evalEmail,
    'Evaluador RenovaDev (Admin)',
  );

  const restaurantId = 'rest_alpha';
  const restaurantName = 'Taquería Los Padrinos • Demo DEV';
  const writes = [];

  writes.push(
    makeWrite(`restaurants/${restaurantId}`, {
      name: restaurantName,
      active: true,
      synthetic: true,
      currency: 'MXN',
      timezone: 'America/Mexico_City',
      updatedAt: new Date(),
    }),
  );

  const branches = [
    { id: 'suc_centro', name: 'Sucursal Centro', weight: 1 },
    { id: 'suc_norte', name: 'Sucursal Norte', weight: 2 },
  ];

  for (let i = 0; i < branches.length; i++) {
    const br = branches[i];
    writes.push(
      makeWrite(`restaurants/${restaurantId}/branches/${br.id}`, {
        id: br.id,
        restaurantId,
        restaurantName,
        name: br.name,
        normalizedName: br.id,
        active: true,
        sortOrder: i + 1,
        timezone: 'America/Mexico_City',
      }),
    );
  }

  writes.push(
    makeWrite(`restaurants/${restaurantId}/authUsers/${evalUser.uid}`, {
      employeeId: evalUser.uid,
      displayName: 'Evaluador RenovaDev (Admin)',
      active: true,
      isSuperAdmin: true,
      branchAccess: branches.map((x) => x.id),
      permissions: {
        canViewAdmin: true,
        canManageEmployees: true,
        canManageProducts: true,
        canAuthorizeCashWithdrawals: true,
      },
    }),
  );

  const categories = [
    { id: 'cat_tacos', name: 'Tacos', sortOrder: 1 },
    { id: 'cat_esp', name: 'Especialidades', sortOrder: 2 },
    { id: 'cat_beb', name: 'Bebidas', sortOrder: 3 },
    { id: 'cat_pos', name: 'Postres', sortOrder: 4 },
  ];
  for (const cat of categories) {
    writes.push(
      makeWrite(`restaurants/${restaurantId}/productCategories/${cat.id}`, {
        ...cat,
        active: true,
        restaurantId,
      }),
    );
  }

  const products = [
    { id: 'p_pastor', name: 'Orden Tacos al Pastor (5 pzas)', category: 'Tacos', price: 135 },
    { id: 'p_suadero', name: 'Orden Tacos de Suadero (5 pzas)', category: 'Tacos', price: 140 },
    { id: 'p_gringa', name: 'Gringa de Pastor', category: 'Especialidades', price: 115 },
    { id: 'p_volcan', name: 'Volcán de Arrachera', category: 'Especialidades', price: 85 },
    { id: 'p_horchata', name: 'Agua de Horchata 1L', category: 'Bebidas', price: 60 },
    { id: 'p_jamaica', name: 'Agua de Jamaica 1L', category: 'Bebidas', price: 55 },
    { id: 'p_flan', name: 'Flan Napolitano', category: 'Postres', price: 65 },
  ];
  for (const prod of products) {
    writes.push(
      makeWrite(`restaurants/${restaurantId}/products/${prod.id}`, {
        ...prod,
        active: true,
        restaurantId,
      }),
    );
  }

  const employees = [
    { id: 'emp_carlos', name: 'Carlos Mendoza (Mesero)', role: 'waiter' },
    { id: 'emp_laura', name: 'Laura Gómez (Cajera)', role: 'cashier' },
    { id: 'emp_miguel', name: 'Miguel Ángel (Cocina)', role: 'kitchen' },
    { id: evalUser.uid, name: 'Evaluador RenovaDev (Admin)', role: 'admin' },
  ];
  for (const emp of employees) {
    writes.push(
      makeWrite(`restaurants/${restaurantId}/employees/${emp.id}`, {
        id: emp.id,
        name: emp.name,
        active: true,
        canViewAdmin: emp.role === 'admin',
      }),
    );
  }

  const now = new Date();
  let folioSeq = 1;
  for (let dayOffset = 0; dayOffset < 90; dayOffset++) {
    const dateObj = new Date(
      now.getFullYear(),
      now.getMonth(),
      now.getDate() - dayOffset,
    );
    const businessDate = formatDate(dateObj);

    for (const br of branches) {
      const cashSessionId = `cs_${br.id}_${businessDate}`;
      const isOpen = dayOffset === 0;
      const openedAt = new Date(
        dateObj.getFullYear(),
        dateObj.getMonth(),
        dateObj.getDate(),
        10,
        0,
      );
      const closedAt = isOpen
        ? null
        : new Date(
            dateObj.getFullYear(),
            dateObj.getMonth(),
            dateObj.getDate(),
            23,
            30,
          );
      const openingCashAmount = 1500;
      const expectedCashAmount = 2500 + ((dayOffset * 173) % 1400);
      const diffDelta = isOpen
        ? 0
        : dayOffset === 1 && br.id === 'suc_centro'
        ? -45
        : dayOffset === 2 && br.id === 'suc_norte'
        ? 30
        : 0;
      const countedCashAmount = isOpen ? 0 : expectedCashAmount + diffDelta;
      const expectedCard = 1800 + ((dayOffset * 131) % 900);
      const terminalCard = isOpen ? 0 : expectedCard;
      const expectedPlatform = 950 + ((dayOffset * 97) % 600);
      const approvedWithdrawals = dayOffset < 7 ? 350 : 0;
      const pendingWithdrawals = isOpen ? 200 : 0;

      writes.push(
        makeWrite(`restaurants/${restaurantId}/cashSessions/${cashSessionId}`, {
          id: cashSessionId,
          restaurantId,
          restaurantName,
          branchId: br.id,
          branchName: br.name,
          businessDate,
          status: isOpen ? 'open' : 'closed',
          openingCashAmount,
          openedByEmployeeId: employees[0].id,
          openedByEmployeeName: employees[0].name,
          openedAt,
          closedByEmployeeId: isOpen ? null : employees[1].id,
          closedByEmployeeName: isOpen ? null : employees[1].name,
          closedAt,
          expectedCashAmount,
          countedCashAmount,
          expectedCardChargedAmount: expectedCard,
          expectedCardBaseAmount: expectedCard,
          expectedCardSurchargeAmount: 0,
          expectedCardFeeAbsorbedAmount: Number((expectedCard * 0.036).toFixed(2)),
          terminalReportedAmount: terminalCard,
          expectedPlatformAmount: expectedPlatform,
          expectedEmployeeConsumptionAmount: dayOffset % 5 === 0 ? 180 : 0,
          totalExpectedRealMoney: expectedCashAmount + expectedCard + expectedPlatform,
          totalCountedRealMoney: isOpen
            ? 0
            : countedCashAmount + terminalCard + expectedPlatform,
          cashDifference: diffDelta,
          cardDifference: 0,
          netDifference: diffDelta,
          shortageAmount: diffDelta < 0 ? Math.abs(diffDelta) : 0,
          overAmount: diffDelta > 0 ? diffDelta : 0,
          approvedWithdrawalsTotal: approvedWithdrawals,
          pendingWithdrawalsTotal: pendingWithdrawals,
          withdrawalRequestCount: approvedWithdrawals > 0 || pendingWithdrawals > 0 ? 1 : 0,
        }),
      );

      const countToday =
        dayOffset < 7 ? 3 : (dayOffset + br.weight) % 2 === 0 ? 3 : 2;
      for (let k = 0; k < countToday; k++) {
        const ordId = `ord_${br.id}_${businessDate}_${k + 1}`;
        const hour = 13 + ((k * 3 + dayOffset) % 10);
        const minute = (k * 17 + dayOffset * 5) % 60;
        const createdAt = new Date(
          dateObj.getFullYear(),
          dateObj.getMonth(),
          dateObj.getDate(),
          hour,
          minute,
        );

        const prodA = products[(dayOffset + k) % products.length];
        const prodB = products[(dayOffset + k + 2) % products.length];
        const qtyA = 1 + ((dayOffset + k) % 3);
        const qtyB = 1 + (k % 2);
        const gross = prodA.price * qtyA + prodB.price * qtyB;

        const isCancelled = dayOffset % 19 === 4 && k === countToday - 1;
        const isEmployeeMeal = !isCancelled && dayOffset % 11 === 3 && k === 0;
        const hasDiscount =
          !isCancelled && !isEmployeeMeal && dayOffset % 7 === 2 && k === 1;
        const discountAmt = hasDiscount ? Math.round(gross * 0.1) : 0;
        const netTotal = isCancelled ? 0 : gross - discountAmt;

        const method = isEmployeeMeal
          ? 'employee_consumption'
          : k % 4 === 0
          ? 'card'
          : k % 4 === 1
          ? 'cash'
          : k % 4 === 2
          ? 'platform_paid'
          : 'cash';

        const folio = `V-${String(folioSeq++).padStart(4, '0')}`;
        const ordPath = `restaurants/${restaurantId}/orders/${ordId}`;

        writes.push(
          makeWrite(ordPath, {
            id: ordId,
            restaurantId,
            restaurantName,
            branchId: br.id,
            branchName: br.name,
            tableId:
              method === 'platform_paid' ? 'takeout' : `mesa_${(k % 6) + 1}`,
            tableName:
              method === 'platform_paid' ? '' : `Mesa ${(k % 6) + 1}`,
            orderType: method === 'platform_paid' ? 'takeout' : 'dine_in',
            platformName: method === 'platform_paid' ? 'Uber Eats' : null,
            status: isCancelled ? 'cancelled' : 'paid',
            kitchenStatus: 'ready',
            paymentStatus: isCancelled ? 'cancelled' : 'paid',
            total: netTotal,
            grossSubtotal: gross,
            netTotal,
            explicitDiscount: discountAmt,
            discountApplied: hasDiscount,
            discountName: hasDiscount
              ? 'Promoción Cliente Frecuente 10%'
              : null,
            paidTotal: isCancelled ? 0 : netTotal,
            pendingTotal: 0,
            personNames: {
              '1': isEmployeeMeal ? 'Consumo Interno' : `Cliente ${folio}`,
            },
            businessDate,
            cashSessionId,
            saleFolioFull: folio,
            saleFolioDisplay: folio,
            createdAt,
            updatedAt: createdAt,
            paidAt: isCancelled ? null : createdAt,
          }),
        );

        writes.push(
          makeWrite(`${ordPath}/items/item_1`, {
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
          }),
        );

        writes.push(
          makeWrite(`${ordPath}/items/item_2`, {
            productId: prodB.id,
            productName: prodB.name,
            category: prodB.category,
            qty: qtyB,
            unitPrice: prodB.price,
            total: prodB.price * qtyB,
            personNumber: 1,
            personName: `Cliente ${folio}`,
            notes: k === 0 ? 'Con cilantro y cebolla' : '',
            sendToKitchen: true,
            kitchenStatus: 'ready',
            paymentStatus: isCancelled ? 'cancelled' : 'paid',
            status: isCancelled ? 'cancelled' : 'active',
          }),
        );

        if (!isCancelled) {
          writes.push(
            makeWrite(`${ordPath}/payments/pay_1`, {
              orderId: ordId,
              tableId:
                method === 'platform_paid' ? 'takeout' : `mesa_${(k % 6) + 1}`,
              tableName:
                method === 'platform_paid' ? '' : `Mesa ${(k % 6) + 1}`,
              type: method,
              method,
              baseAmount: netTotal,
              surchargeRate: 0,
              surchargeAmount: 0,
              chargedAmount: netTotal,
              appliedAmount: netTotal,
              businessDate,
              cashSessionId,
              createdBy: employees[k % employees.length].id,
              createdByEmployeeName: employees[k % employees.length].name,
              status: 'active',
              restaurantId,
              branchId: br.id,
              createdAt,
            }),
          );
        }
      }
    }
  }

  // Phase 4: Cash Withdrawals, Discount Authorizations, Kitchen & Inventory
  const stockCatalog = [
    {
      id: 'ksi_pastor',
      name: 'Carne al Pastor',
      category: 'Carnes',
      unit: 'kg',
      optimal: 0.12,
      supplier: 'Carnicería El Buen Corte',
    },
    {
      id: 'ksi_suadero',
      name: 'Suadero Cocido',
      category: 'Carnes',
      unit: 'kg',
      optimal: 0.12,
      supplier: 'Carnicería El Buen Corte',
    },
    {
      id: 'ksi_bistec',
      name: 'Bistec de Res',
      category: 'Carnes',
      unit: 'kg',
      optimal: 0.15,
      supplier: 'Distribuidora Norte',
    },
    {
      id: 'ksi_tortilla',
      name: 'Tortilla de Maíz',
      category: 'Abarrotes',
      unit: 'kg',
      optimal: 0.08,
      supplier: 'Tortillería La Esperanza',
    },
    {
      id: 'ksi_limon',
      name: 'Limón Verde',
      category: 'Verduras',
      unit: 'kg',
      optimal: 0.03,
      supplier: 'Central de Abastos',
    },
  ];

  for (let i = 0; i < stockCatalog.length; i++) {
    const item = stockCatalog[i];
    writes.push(
      makeWrite(`restaurants/${restaurantId}/kitchenStockItems/${item.id}`, {
        id: item.id,
        name: item.name,
        category: item.category,
        unit: item.unit,
        active: true,
        sortOrder: i + 1,
        optimalConsumptionPerSaleQty: item.optimal,
        optimalConsumptionUnit: item.unit,
        affectsKitchenPerformance: true,
        defaultSupplierName: item.supplier,
      }),
    );
  }

  for (let i = 0; i < products.length; i++) {
    const prod = products[i];
    const stockRef = stockCatalog[i % stockCatalog.length];
    writes.push(
      makeWrite(`restaurants/${restaurantId}/products/${prod.id}`, {
        id: prod.id,
        name: prod.name,
        categoryId: prod.category.toLowerCase(),
        categoryName: prod.category,
        category: prod.category,
        price: prod.price,
        active: true,
        sendToKitchen: true,
        sortOrder: i + 1,
        affectsKitchenStock: true,
        kitchenStockItemId: stockRef.id,
        kitchenStockItemName: stockRef.name,
        kitchenStockUnit: stockRef.unit,
        stockConsumptionQty: stockRef.optimal,
        recipeItems: [
          {
            kitchenStockItemId: stockRef.id,
            kitchenStockItemName: stockRef.name,
            kitchenStockUnit: stockRef.unit,
            consumptionFactor: stockRef.optimal,
          },
        ],
      }),
    );
  }

  for (let dayOffset = 0; dayOffset < 7; dayOffset++) {
    const dateObj = new Date(
      now.getFullYear(),
      now.getMonth(),
      now.getDate() - dayOffset,
    );
    const businessDate = formatDate(dateObj);
    const reqAt = new Date(
      dateObj.getFullYear(),
      dateObj.getMonth(),
      dateObj.getDate(),
      15,
      30,
    );

    for (const br of branches) {
      const cashSessionId = `cs_${br.id}_${businessDate}`;
      const cwStatus =
        dayOffset === 0 ? 'pending' : dayOffset === 3 ? 'rejected' : 'approved';
      writes.push(
        makeWrite(
          `restaurants/${restaurantId}/cashWithdrawalRequests/cw_${br.id}_${businessDate}`,
          {
            id: `cw_${br.id}_${businessDate}`,
            restaurantId,
            branchId: br.id,
            branchName: br.name,
            cashSessionId,
            businessDate,
            amount: dayOffset === 0 ? 200 : 350,
            reason:
              dayOffset === 0
                ? 'Compra urgente de hielo y cilantro'
                : 'Pago a proveedor de tortillas',
            status: cwStatus,
            requestedByEmployeeId: employees[1].id,
            requestedByEmployeeName: employees[1].name,
            requestedAt: reqAt,
            createdAt: reqAt,
            approvedByEmployeeId: cwStatus === 'approved' ? employees[0].id : null,
            approvedByEmployeeName:
              cwStatus === 'approved' ? employees[0].name : null,
            approvedAt: cwStatus === 'approved' ? reqAt : null,
            rejectedByEmployeeId: cwStatus === 'rejected' ? employees[0].id : null,
            rejectedByEmployeeName:
              cwStatus === 'rejected' ? employees[0].name : null,
            rejectedAt: cwStatus === 'rejected' ? reqAt : null,
            rejectReason:
              cwStatus === 'rejected' ? 'Falta comprobante fiscal' : null,
          },
        ),
      );

      if (dayOffset < 5) {
        const daStatus =
          dayOffset === 0
            ? 'pending'
            : dayOffset === 2
            ? 'rejected'
            : 'approved';
        writes.push(
          makeWrite(
            `restaurants/${restaurantId}/discountAuthorizationRequests/da_${br.id}_${businessDate}`,
            {
              id: `da_${br.id}_${businessDate}`,
              restaurantId,
              branchId: br.id,
              branchName: br.name,
              orderId: `ord_${br.id}_${businessDate}_1`,
              businessDate,
              tableName: 'Mesa 4',
              orderType: 'dine_in',
              requestedDiscountType: 'percent',
              requestedDiscountName: 'Cortesía Cliente Frecuente',
              requestedDiscountPercent: 15,
              amountBeforeDiscount: 420,
              estimatedDiscountAmount: 63,
              estimatedTotalAfterDiscount: 357,
              requestReason: 'Aniversario de cliente habitual',
              status: daStatus,
              requestedAt: reqAt,
              requestedByEmployeeId: employees[2].id,
              requestedByEmployeeName: employees[2].name,
              approvedAt: daStatus === 'approved' ? reqAt : null,
              approvedByEmployeeId:
                daStatus === 'approved' ? employees[0].id : null,
              approvedByEmployeeName:
                daStatus === 'approved' ? employees[0].name : null,
              rejectedAt: daStatus === 'rejected' ? reqAt : null,
              rejectedByEmployeeId:
                daStatus === 'rejected' ? employees[0].id : null,
              rejectedByEmployeeName:
                daStatus === 'rejected' ? employees[0].name : null,
              rejectReason:
                daStatus === 'rejected' ? 'Descuento fuera de horario' : null,
            },
          ),
        );
      }

      const ksId = `ks_${br.id}_${businessDate}`;
      const ksOpen = dayOffset === 0;
      writes.push(
        makeWrite(`restaurants/${restaurantId}/kitchenSessions/${ksId}`, {
          id: ksId,
          restaurantId,
          branchId: br.id,
          branchName: br.name,
          businessDate,
          status: ksOpen ? 'open' : 'closed',
          cashSessionId,
          openedAt: reqAt,
          openedByEmployeeId: employees[2].id,
          openedByEmployeeName: employees[2].name,
          closedAt: ksOpen ? null : reqAt,
          closedByEmployeeId: ksOpen ? null : employees[0].id,
          closedByEmployeeName: ksOpen ? null : employees[0].name,
        }),
      );

      for (const item of stockCatalog) {
        const prev = 4.5;
        const input = 12.0;
        const finalRem = ksOpen ? 0 : 3.2;
        const waste = ksOpen ? 0 : 0.4;
        const used = ksOpen ? 0 : Number((prev + input - finalRem).toFixed(2));
        const useful = ksOpen ? 0 : Number((used - waste).toFixed(2));
        const sold = ksOpen ? 6.4 : Number((useful - 0.15).toFixed(2));
        writes.push(
          makeWrite(
            `restaurants/${restaurantId}/kitchenSessions/${ksId}/items/${item.id}`,
            {
              kitchenStockItemId: item.id,
              name: item.name,
              category: item.category,
              unit: item.unit,
              previousRemainingQty: prev,
              todayInputQty: input,
              additionalEntriesQty: 0,
              availableQty: prev + input,
              finalRemainingQty: finalRem,
              wasteQty: waste,
              usedQty: used,
              usefulConsumedQty: useful,
              soldQty: sold,
              yieldQtyPerUnit: 1,
            },
          ),
        );
      }
    }
  }

  writes.push(
    makeWrite(
      `restaurants/${restaurantId}/productStockOuts/so_suc_centro_${formatDate(now)}`,
      {
        id: `so_suc_centro_${formatDate(now)}`,
        businessDate: formatDate(now),
        branchId: 'suc_centro',
        branchName: 'Centro',
        productId: products[2].id,
        productName: products[2].name,
        categoryId: 'bebidas',
        categoryName: 'Bebidas',
        status: 'active',
        reason: 'Lote de horchata agotado en barra',
        soldOutAt: now,
        soldOutByEmployeeId: employees[1].id,
        soldOutByEmployeeName: employees[1].name,
      },
    ),
  );

  // Phase 5: Suppliers, Purchase Items, Supplier Purchases & Payments
  const suppliers = [
    {
      id: 'sup_buen_corte',
      commercialName: 'Carnicería El Buen Corte',
      phone: '55 4120 8890',
      creditDays: 7,
      paymentWeekday: 'friday',
      paymentWeekdayName: 'Viernes',
      preferredPaymentMethod: 'transfer',
    },
    {
      id: 'sup_esperanza',
      commercialName: 'Tortillería La Esperanza',
      phone: '55 3811 2245',
      creditDays: 0,
      paymentWeekday: 'none',
      paymentWeekdayName: 'Sin dia fijo',
      preferredPaymentMethod: 'cash',
    },
    {
      id: 'sup_dist_norte',
      commercialName: 'Distribuidora Norte',
      phone: '55 5902 1140',
      creditDays: 15,
      paymentWeekday: 'monday',
      paymentWeekdayName: 'Lunes',
      preferredPaymentMethod: 'transfer',
    },
    {
      id: 'sup_bebidas_valle',
      commercialName: 'Bebidas y Abarrotes del Valle',
      phone: '55 6120 7731',
      creditDays: 10,
      paymentWeekday: 'wednesday',
      paymentWeekdayName: 'Miércoles',
      preferredPaymentMethod: 'both',
    },
  ];

  for (const sup of suppliers) {
    writes.push(
      makeWrite(`restaurants/${restaurantId}/suppliers/${sup.id}`, {
        ...sup,
        active: true,
        legalName: `${sup.commercialName} S.A. de C.V.`,
        contactName: 'Ventas Mayoreo',
      }),
    );
  }

  const purchaseItems = [
    {
      id: 'pi_pastor',
      name: 'Carne al Pastor',
      category: 'Carnes',
      unit: 'kg',
      defaultSupplierId: 'sup_buen_corte',
      defaultSupplierName: 'Carnicería El Buen Corte',
      basePrice: 118,
    },
    {
      id: 'pi_suadero',
      name: 'Suadero Cocido',
      category: 'Carnes',
      unit: 'kg',
      defaultSupplierId: 'sup_buen_corte',
      defaultSupplierName: 'Carnicería El Buen Corte',
      basePrice: 124,
    },
    {
      id: 'pi_tripa',
      name: 'Tripa Limpia',
      category: 'Carnes',
      unit: 'kg',
      defaultSupplierId: 'sup_dist_norte',
      defaultSupplierName: 'Distribuidora Norte',
      basePrice: 142,
    },
    {
      id: 'pi_tortilla',
      name: 'Tortilla de Maíz',
      category: 'Abarrotes',
      unit: 'kg',
      defaultSupplierId: 'sup_esperanza',
      defaultSupplierName: 'Tortillería La Esperanza',
      basePrice: 22,
    },
    {
      id: 'pi_jamaica',
      name: 'Concentrado de Jamaica',
      category: 'Bebidas',
      unit: 'lt',
      defaultSupplierId: 'sup_bebidas_valle',
      defaultSupplierName: 'Bebidas y Abarrotes del Valle',
      basePrice: 48,
    },
  ];

  for (const pi of purchaseItems) {
    writes.push(
      makeWrite(`restaurants/${restaurantId}/purchaseItems/${pi.id}`, {
        id: pi.id,
        name: pi.name,
        category: pi.category,
        unit: pi.unit,
        active: true,
        defaultSupplierId: pi.defaultSupplierId,
        defaultSupplierName: pi.defaultSupplierName,
      }),
    );
  }

  let purchaseFolioSeq = 1;
  for (let dayOffset = 0; dayOffset < 28; dayOffset += 2) {
    const pDate = new Date(
      now.getFullYear(),
      now.getMonth(),
      now.getDate() - dayOffset,
      11,
      15,
    );
    const businessDate = formatDate(pDate);
    for (let bi = 0; bi < branches.length; bi++) {
      const br = branches[bi];
      const pi = purchaseItems[(dayOffset + bi) % purchaseItems.length];
      const sup = suppliers.find((s) => s.id === pi.defaultSupplierId) || suppliers[0];
      const qty = pi.unit === 'kg' ? 12 + ((dayOffset + bi) % 15) : 20;
      // Simulate recent +13.5% price increase on Carne al Pastor in last 2 days
      const unitCost =
        pi.id === 'pi_pastor' && dayOffset <= 2
          ? 134
          : pi.basePrice + ((dayOffset % 3) * 2);
      const total = Number((qty * unitCost).toFixed(2));

      const isPaid = dayOffset >= 8;
      const isPartial = dayOffset >= 4 && dayOffset < 8;
      const paidTotal = isPaid ? total : isPartial ? Number((total * 0.5).toFixed(2)) : 0;
      const balance = Number((total - paidTotal).toFixed(2));
      const status = isPaid ? 'paid' : isPartial ? 'partial' : 'pending';
      const dueDate = new Date(
        pDate.getTime() + (sup.creditDays > 0 ? sup.creditDays : 3) * 86400000,
      );

      const spId = `sp_${br.id}_${businessDate}_${bi}`;
      const folio = `C-${String(purchaseFolioSeq++).padStart(4, '0')}`;

      writes.push(
        makeWrite(`restaurants/${restaurantId}/supplierPurchases/${spId}`, {
          id: spId,
          restaurantId,
          restaurantName,
          branchId: br.id,
          branchName: br.name,
          supplierId: sup.id,
          supplierName: sup.commercialName,
          purchaseDate: pDate,
          businessDate,
          dueDate,
          folio,
          documentType: sup.creditDays > 0 ? 'invoice' : 'note',
          status,
          subtotal: total,
          total,
          paidTotal,
          balance,
          notes: isPartial ? 'Abono inicial del 50%' : '',
          createdByEmployeeId: employees[0].id,
          createdByEmployeeName: employees[0].name,
          createdAt: pDate,
        }),
      );

      writes.push(
        makeWrite(`restaurants/${restaurantId}/supplierPurchases/${spId}/items/line_1`, {
          id: 'line_1',
          purchaseItemId: pi.id,
          purchaseItemName: pi.name,
          quantity: qty,
          unit: pi.unit,
          unitCost,
          unitCostCalculated: unitCost,
          total,
          lineTotal: total,
          lineTotalCents: Math.round(total * 100),
          calculationMode: 'line_total',
          status: 'active',
        }),
      );

      if (paidTotal > 0) {
        writes.push(
          makeWrite(`restaurants/${restaurantId}/supplierPayments/spay_${spId}`, {
            id: `spay_${spId}`,
            restaurantId,
            restaurantName,
            branchId: br.id,
            branchName: br.name,
            supplierId: sup.id,
            supplierName: sup.commercialName,
            purchaseId: spId,
            purchaseFolio: folio,
            paymentDate: pDate,
            businessDate,
            amount: paidTotal,
            method: sup.preferredPaymentMethod === 'cash' ? 'cash' : 'transfer',
            fundingSource: sup.preferredPaymentMethod === 'cash' ? 'cash' : 'transfer',
            fundingSourceName:
              sup.preferredPaymentMethod === 'cash' ? 'Efectivo' : 'Transferencia',
            reference: `REF-${folio}`,
            notes: isPartial ? 'Pago parcial' : 'Liquidación total',
            status: 'active',
            createdByEmployeeId: employees[0].id,
            createdByEmployeeName: employees[0].name,
            createdAt: pDate,
          }),
        );
      }
    }
  }

  writes.push(
    makeWrite('restaurants/rest_beta', {
      name: 'Tacos El Norte • Tenant Aislado',
      active: true,
      synthetic: true,
    }),
  );
  writes.push(
    makeWrite('restaurants/rest_beta/orders/ord_beta_isolated', {
      id: 'ord_beta_isolated',
      restaurantId: 'rest_beta',
      branchId: 'suc_sur',
      businessDate: formatDate(now),
      status: 'paid',
      total: 999,
    }),
  );

  await commitWrites(writes);
  console.log('SEED_DEV_OK');
  console.log(
    JSON.stringify({
      projectId: TARGET_PROJECT,
      restaurantId,
      ordersSeeded: folioSeq - 1,
      writesCommitted: writes.length,
      evalEmail: evalUser.email,
      evalPassword: evalUser.password,
      evalUid: evalUser.uid,
    }),
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
