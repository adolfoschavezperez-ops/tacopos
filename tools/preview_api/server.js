/**
 * Authenticated Read-Only Preview API for TacoPOS Backoffice 2.0.
 *
 * Security model:
 * - Zero write endpoints and zero write Firestore SDK calls.
 * - Intended to run under a dedicated GCP Service Account with ONLY
 *   `roles/datastore.viewer` on the target Firestore project.
 * - Verifies Firebase ID Token with revocation check (`verifyIdToken(..., true)`).
 * - Enforces owner allowlist, restaurant/branch authorization, and server-side
 *   field projection (strips plaintext `pin` and credentials from `employees`).
 */

const http = require('node:http');
const {
  MAX_DOCS_PER_QUERY,
  BRANCH_SCOPED_COLLECTIONS,
  projectDoc,
  isAllowedCollectionPath,
} = require('./projection');

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  res.end(body);
}

async function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > 64 * 1024) {
        reject(new Error('PAYLOAD_TOO_LARGE'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      try {
        const raw = Buffer.concat(chunks).toString('utf8').trim();
        resolve(raw ? JSON.parse(raw) : {});
      } catch {
        reject(new Error('INVALID_JSON'));
      }
    });
    req.on('error', reject);
  });
}

function canUserAccessBranch(authUser, branchId) {
  if (!authUser || typeof branchId !== 'string' || !branchId.trim()) {
    return false;
  }
  if (authUser.isSuperAdmin === true || authUser.allBranchesAccess === true) {
    return true;
  }
  return Array.isArray(authUser.branchAccess) && authUser.branchAccess.includes(branchId);
}

async function authorizePreviewRequest({
  auth,
  db,
  req,
  restaurantId,
  ownerAllowlist,
}) {
  const authHeader = req.headers.authorization || '';
  if (!authHeader.startsWith('Bearer ')) {
    return { ok: false, status: 401, code: 'UNAUTHENTICATED', message: 'Token requerido.' };
  }
  const idToken = authHeader.slice('Bearer '.length).trim();
  if (!idToken) {
    return { ok: false, status: 401, code: 'UNAUTHENTICATED', message: 'Token vacío.' };
  }

  let decoded;
  try {
    decoded = await auth.verifyIdToken(idToken, true);
  } catch {
    return { ok: false, status: 401, code: 'INVALID_OR_REVOKED_TOKEN', message: 'Sesión inválida o revocada.' };
  }

  const email = (decoded.email || '').toLowerCase().trim();
  if (!email || !ownerAllowlist.has(email)) {
    return {
      ok: false,
      status: 403,
      code: 'PREVIEW_OWNER_REQUIRED',
      message: 'Acceso a Preview restringido a cuentas autorizadas del propietario.',
    };
  }

  if (!restaurantId || typeof restaurantId !== 'string' || !restaurantId.trim()) {
    return { ok: false, status: 400, code: 'MISSING_RESTAURANT_ID', message: 'restaurantId requerido.' };
  }

  const authUserSnap = await db
    .doc(`restaurants/${restaurantId.trim()}/authUsers/${decoded.uid}`)
    .get();
  if (!authUserSnap.exists) {
    return { ok: false, status: 403, code: 'RESTAURANT_ACCESS_DENIED', message: 'Sin acceso al restaurante.' };
  }
  const authUser = authUserSnap.data() || {};
  if (authUser.active !== true) {
    return { ok: false, status: 403, code: 'USER_REVOKED', message: 'Usuario desactivado.' };
  }

  if (typeof authUser.employeeId === 'string' && authUser.employeeId.trim()) {
    const empSnap = await db
      .doc(`restaurants/${restaurantId.trim()}/employees/${authUser.employeeId.trim()}`)
      .get();
    if (empSnap.exists && empSnap.data()?.active === false) {
      return { ok: false, status: 403, code: 'EMPLOYEE_REVOKED', message: 'Empleado desactivado.' };
    }
  }

  return { ok: true, uid: decoded.uid, email, authUser };
}

function createPreviewServer({
  auth,
  db,
  ownerAllowlist = new Set(),
  maxDocsPerQuery = MAX_DOCS_PER_QUERY,
}) {
  const normalizedAllowlist = new Set(
    Array.from(ownerAllowlist).map((e) => String(e).toLowerCase().trim()),
  );

  return http.createServer(async (req, res) => {
    const url = new URL(req.url || '/', 'http://127.0.0.1');

    if (req.method === 'GET' && url.pathname === '/health') {
      return sendJson(res, 200, { ok: true, mode: 'preview_read_only' });
    }

    if (req.method !== 'POST') {
      return sendJson(res, 405, {
        code: 'READ_ONLY_MODE',
        message: 'Preview API solo acepta consultas de lectura.',
      });
    }

    if (url.pathname !== '/v1/preview/query' && url.pathname !== '/v1/preview/doc') {
      return sendJson(res, 404, {
        code: 'ENDPOINT_NOT_FOUND',
        message: 'Endpoint no habilitado en Preview Read-Only API.',
      });
    }

    let body;
    try {
      body = await readJsonBody(req);
    } catch (e) {
      return sendJson(res, 400, { code: e.message || 'BAD_REQUEST' });
    }

    const restaurantId = String(body.restaurantId || '').trim();
    const collectionName = String(body.collection || '').trim();
    const subcollectionName = body.subcollection ? String(body.subcollection).trim() : null;
    const parentDocId = body.parentDocId ? String(body.parentDocId).trim() : null;
    const branchId = body.branchId ? String(body.branchId).trim() : null;

    const authResult = await authorizePreviewRequest({
      auth,
      db,
      req,
      restaurantId,
      ownerAllowlist: normalizedAllowlist,
    });
    if (!authResult.ok) {
      return sendJson(res, authResult.status, {
        code: authResult.code,
        message: authResult.message,
      });
    }

    if (!isAllowedCollectionPath(collectionName, subcollectionName)) {
      return sendJson(res, 403, {
        code: 'COLLECTION_FORBIDDEN',
        message: `Colección "${collectionName}" bloqueada en Preview.`,
      });
    }

    const { authUser } = authResult;
    if (branchId && !canUserAccessBranch(authUser, branchId)) {
      return sendJson(res, 403, {
        code: 'BRANCH_ACCESS_DENIED',
        message: 'No tienes acceso a la sucursal solicitada.',
      });
    }

    if (url.pathname === '/v1/preview/doc') {
      const docId = String(body.docId || '').trim();
      if (!docId) {
        return sendJson(res, 400, { code: 'MISSING_DOC_ID' });
      }
      const docPath = subcollectionName && parentDocId
        ? `restaurants/${restaurantId}/${collectionName}/${parentDocId}/${subcollectionName}/${docId}`
        : `restaurants/${restaurantId}/${collectionName}/${docId}`;
      const snap = await db.doc(docPath).get();
      if (!snap.exists) {
        return sendJson(res, 404, { code: 'NOT_FOUND' });
      }
      const data = snap.data() || {};
      if (BRANCH_SCOPED_COLLECTIONS.has(collectionName) && data.branchId) {
        if (!canUserAccessBranch(authUser, data.branchId)) {
          return sendJson(res, 403, { code: 'BRANCH_ACCESS_DENIED' });
        }
      }
      return sendJson(res, 200, {
        doc: projectDoc(subcollectionName || collectionName, snap.id, data),
        readCount: 1,
      });
    }

    // /v1/preview/query
    const requestedLimit = Number(body.limit || 100);
    const effectiveLimit = Math.min(
      Math.max(1, Number.isFinite(requestedLimit) ? requestedLimit : 100),
      maxDocsPerQuery,
    );

    let ref = subcollectionName && parentDocId
      ? db.collection(`restaurants/${restaurantId}/${collectionName}/${parentDocId}/${subcollectionName}`)
      : db.collection(`restaurants/${restaurantId}/${collectionName}`);

    if (branchId && BRANCH_SCOPED_COLLECTIONS.has(collectionName) && !subcollectionName) {
      ref = ref.where('branchId', '==', branchId);
    }
    if (body.startBusinessDate) {
      ref = ref.where('businessDate', '>=', String(body.startBusinessDate));
    }
    if (body.endBusinessDate) {
      ref = ref.where('businessDate', '<=', String(body.endBusinessDate));
    }

    const snap = await ref.limit(effectiveLimit + 1).get();
    const hitLimit = snap.docs.length > effectiveLimit;
    const rawDocs = hitLimit ? snap.docs.slice(0, effectiveLimit) : snap.docs;

    const filteredDocs = [];
    for (const d of rawDocs) {
      const data = d.data() || {};
      if (BRANCH_SCOPED_COLLECTIONS.has(collectionName) && data.branchId) {
        if (!canUserAccessBranch(authUser, data.branchId)) continue;
      }
      filteredDocs.push(projectDoc(subcollectionName || collectionName, d.id, data));
    }

    return sendJson(res, 200, {
      docs: filteredDocs,
      isPartial: hitLimit,
      readCount: snap.docs.length,
    });
  });
}

module.exports = { createPreviewServer, canUserAccessBranch };
