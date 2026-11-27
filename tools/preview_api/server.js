/**
 * Authenticated Read-Only Preview API for TacoPOS Backoffice 2.0 (Fase 9.1.2).
 *
 * - Strict separation between:
 *   1) `auth` (Firebase Auth in isolated auth project)
 *   2) `authzDb` (Firestore storing `previewUsers/{uid}` allowlist — never prod)
 *   3) `dataDb` (Firestore storing operational restaurant data — IAM `roles/datastore.viewer` only)
 * - Zero write endpoints and zero write SDK calls.
 * - Parent document authorization for all subcollections.
 * - Real deterministic cursor pagination (`nextCursor`, `hasMore`, `cursorHash`).
 * - Per-UID rate limiting, concurrency limiting, CORS allowlist, and consumption telemetry.
 */

const crypto = require('node:crypto');
const http = require('node:http');
const {
  MAX_DOCS_PER_QUERY,
  BRANCH_SCOPED_COLLECTIONS,
  projectDoc,
  serializeValue,
  isAllowedCollectionPath,
  isValidPathSegment,
} = require('./projection');

function sendJson(res, statusCode, payload, corsOrigin) {
  const headers = {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  };
  if (corsOrigin) {
    headers['Access-Control-Allow-Origin'] = corsOrigin;
    headers['Access-Control-Allow-Headers'] = 'Authorization, Content-Type';
    headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS';
    headers['Vary'] = 'Origin';
  }
  res.writeHead(statusCode, headers);
  res.end(JSON.stringify(payload));
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

function canUserAccessBranch(authzUser, branchId) {
  if (!authzUser || typeof branchId !== 'string' || !branchId.trim()) {
    return false;
  }
  if (authzUser.isSuperAdmin === true || authzUser.allBranchesAccess === true) {
    return true;
  }
  return Array.isArray(authzUser.branchAccess) && authzUser.branchAccess.includes(branchId);
}

function allowedBranchList(authzUser) {
  if (!authzUser) return [];
  if (authzUser.isSuperAdmin === true || authzUser.allBranchesAccess === true) {
    return null; // unrestricted within restaurant
  }
  return Array.isArray(authzUser.branchAccess)
    ? authzUser.branchAccess.map((b) => String(b).trim()).filter(Boolean)
    : [];
}

function computeFilterHash({ restaurantId, collectionName, subcollectionName, parentDocId, branchId, startBusinessDate, endBusinessDate, statusFilter }) {
  return crypto
    .createHash('sha256')
    .update(JSON.stringify({
      restaurantId,
      collectionName,
      subcollectionName: subcollectionName || '',
      parentDocId: parentDocId || '',
      branchId: branchId || '',
      startBusinessDate: startBusinessDate || '',
      endBusinessDate: endBusinessDate || '',
      statusFilter: statusFilter || '',
    }))
    .digest('hex')
    .slice(0, 16);
}

function validateDateRange(startStr, endStr, maxDaysRange) {
  if (!startStr && !endStr) return true;
  if (!startStr || !endStr) return false;
  const s = Date.parse(`${startStr}T00:00:00Z`);
  const e = Date.parse(`${endStr}T00:00:00Z`);
  if (!Number.isFinite(s) || !Number.isFinite(e) || e < s) return false;
  const days = Math.floor((e - s) / 86400000) + 1;
  return days <= maxDaysRange;
}

async function authorizePreviewRequest({ auth, authzDb, dataDb, req, restaurantId }) {
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

  let authzReads = 0;
  let dataReads = 0;

  // Read Preview authorization strictly from isolated `authzDb` (`previewUsers/{uid}`)
  const authzSnap = await authzDb.doc(`previewUsers/${decoded.uid}`).get();
  authzReads += 1;
  if (!authzSnap.exists) {
    return {
      ok: false,
      status: 403,
      code: 'PREVIEW_ACCESS_DENIED',
      message: 'Cuenta no autorizada en previewUsers.',
      authzReads,
      dataReads,
    };
  }

  const authzUser = authzSnap.data() || {};
  const isExplicitlyDisabled = authzUser.active === false || authzUser.enabled === false;
  const isExplicitlyEnabled = authzUser.active === true || authzUser.enabled === true;
  if (isExplicitlyDisabled || !isExplicitlyEnabled) {
    return { ok: false, status: 403, code: 'PREVIEW_USER_REVOKED', message: 'Acceso Preview revocado.', authzReads, dataReads };
  }
  if (authzUser.expiresAt) {
    const expDate = typeof authzUser.expiresAt.toDate === 'function'
      ? authzUser.expiresAt.toDate()
      : new Date(authzUser.expiresAt);
    if (!Number.isNaN(expDate.getTime()) && expDate.getTime() <= Date.now()) {
      return { ok: false, status: 403, code: 'PREVIEW_ACCESS_EXPIRED', message: 'Acceso Preview expirado.', authzReads, dataReads };
    }
  }

  // Validate UID allowlist binding and restaurant access
  if (authzUser.uid && authzUser.uid !== decoded.uid) {
    return { ok: false, status: 403, code: 'UID_MISMATCH', message: 'Inconsistencia de identidad.', authzReads, dataReads };
  }

  const allowedRestaurants = Array.isArray(authzUser.restaurantAccess)
    ? authzUser.restaurantAccess.map(String)
    : (authzUser.restaurantId ? [String(authzUser.restaurantId)] : []);

  if (!isValidPathSegment(restaurantId) || !allowedRestaurants.includes(restaurantId)) {
    return { ok: false, status: 403, code: 'RESTAURANT_ACCESS_DENIED', message: 'Sin acceso al restaurante.', authzReads, dataReads };
  }

  // If linked to an employeeId in dataDb, verify the employee exists and is active
  if (typeof authzUser.employeeId === 'string' && authzUser.employeeId.trim()) {
    const empId = authzUser.employeeId.trim();
    if (!isValidPathSegment(empId)) {
      return { ok: false, status: 403, code: 'INVALID_EMPLOYEE_LINK', message: 'Vínculo de empleado inválido.', authzReads, dataReads };
    }
    const empSnap = await dataDb.doc(`restaurants/${restaurantId}/employees/${empId}`).get();
    dataReads += 1;
    if (!empSnap.exists || empSnap.data()?.active !== true) {
      return {
        ok: false,
        status: 403,
        code: 'EMPLOYEE_INACTIVE_OR_MISSING',
        message: 'Empleado vinculado inactivo o inexistente.',
        authzReads,
        dataReads,
      };
    }
  }

  return { ok: true, uid: decoded.uid, authzUser, authzReads, dataReads };
}

function createPreviewServer({
  auth,
  authzDb,
  dataDb,
  allowedOrigins = [],
  maxDocsPerQuery = MAX_DOCS_PER_QUERY,
  maxRequestsPerMin = 120,
  maxConcurrentPerUid = 6,
  maxDaysRange = 93,
  requestTimeoutMs = 15000,
  disabled = false,
  logger = () => {},
}) {
  const originSet = new Set(allowedOrigins.map((o) => String(o).trim()).filter(Boolean));
  const rateBuckets = new Map(); // uid -> { windowStart, count }
  const inFlightCounts = new Map(); // uid -> number

  const server = http.createServer(async (req, res) => {
    const reqOrigin = req.headers.origin ? String(req.headers.origin).trim() : '';
    const corsAllowed = !reqOrigin || (originSet.size > 0 && originSet.has(reqOrigin));
    const corsHeader = reqOrigin && corsAllowed ? reqOrigin : null;

    if (!corsAllowed) {
      return sendJson(res, 403, { code: 'CORS_ORIGIN_DENIED' }, null);
    }
    if (disabled) {
      return sendJson(res, 503, { code: 'PREVIEW_SERVICE_DISABLED', message: 'Servicio Preview deshabilitado temporalmente.' }, corsHeader);
    }
    if (req.method === 'OPTIONS') {
      res.writeHead(204, {
        ...(corsHeader ? { 'Access-Control-Allow-Origin': corsHeader } : {}),
        'Access-Control-Allow-Headers': 'Authorization, Content-Type',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      });
      res.end();
      return;
    }

    const url = new URL(req.url || '/', 'http://127.0.0.1');
    if (req.method === 'GET' && url.pathname === '/health') {
      return sendJson(res, 200, { ok: true, mode: 'preview_read_only' }, corsHeader);
    }

    if (req.method !== 'POST') {
      return sendJson(res, 405, { code: 'READ_ONLY_MODE', message: 'Preview API solo acepta lectura.' }, corsHeader);
    }

    const allowedPaths = new Set(['/v1/preview/session', '/v1/preview/query', '/v1/preview/doc']);
    if (!allowedPaths.has(url.pathname)) {
      return sendJson(res, 404, { code: 'ENDPOINT_NOT_FOUND' }, corsHeader);
    }

    let body;
    try {
      body = await readJsonBody(req);
    } catch (e) {
      return sendJson(res, 400, { code: e.message || 'BAD_REQUEST' }, corsHeader);
    }

    const restaurantId = String(body.restaurantId || '').trim();
    const authResult = await authorizePreviewRequest({ auth, authzDb, dataDb, req, restaurantId });
    if (!authResult.ok) {
      logger({ event: 'authz_denied', code: authResult.code, path: url.pathname });
      return sendJson(res, authResult.status, { code: authResult.code, message: authResult.message }, corsHeader);
    }

    const { uid, authzUser } = authResult;
    let authzReads = authResult.authzReads;
    let dataReads = authResult.dataReads;

    // Rate limit per UID
    const now = Date.now();
    let bucket = rateBuckets.get(uid);
    if (!bucket || now - bucket.windowStart >= 60000) {
      bucket = { windowStart: now, count: 0 };
      rateBuckets.set(uid, bucket);
    }
    bucket.count += 1;
    if (bucket.count > maxRequestsPerMin) {
      return sendJson(res, 429, { code: 'RATE_LIMIT_EXCEEDED' }, corsHeader);
    }

    // Concurrency limit per UID
    const activeCount = inFlightCounts.get(uid) || 0;
    if (activeCount >= maxConcurrentPerUid) {
      return sendJson(res, 429, { code: 'CONCURRENCY_LIMIT_EXCEEDED' }, corsHeader);
    }
    inFlightCounts.set(uid, activeCount + 1);

    try {
      // --- Session bootstrap endpoint (authz + restaurant + allowed branches) ---
      if (url.pathname === '/v1/preview/session') {
        const restSnap = await dataDb.doc(`restaurants/${restaurantId}`).get();
        dataReads += 1;
        const branchSnap = await dataDb
          .collection(`restaurants/${restaurantId}/branches`)
          .orderBy('sortOrder')
          .limit(100)
          .get();
        dataReads += branchSnap.docs.length;

        const allowedBranches = branchSnap.docs
          .map((d) => ({ id: d.id, ...serializeValue(d.data() || {}) }))
          .filter((b) => b.active !== false && canUserAccessBranch(authzUser, b.id));

        if (!authzUser.isSuperAdmin && !authzUser.allBranchesAccess && allowedBranches.length === 0) {
          return sendJson(res, 403, { code: 'NO_AUTHORIZED_BRANCHES' }, corsHeader);
        }

        return sendJson(res, 200, {
          restaurant: {
            id: restaurantId,
            name: restSnap.data()?.name || restaurantId,
          },
          authzUser: {
            uid,
            employeeId: authzUser.employeeId || uid,
            displayName: authzUser.displayName || 'Propietario',
            isSuperAdmin: authzUser.isSuperAdmin === true,
            permissions: authzUser.permissions || {},
          },
          branches: allowedBranches,
          usage: { authzReads, dataReads, docsReturned: allowedBranches.length },
        }, corsHeader);
      }

      const collectionName = String(body.collection || '').trim();
      const subcollectionName = body.subcollection ? String(body.subcollection).trim() : null;
      const parentDocId = body.parentDocId ? String(body.parentDocId).trim() : null;
      const branchId = body.branchId ? String(body.branchId).trim() : null;

      if (!isAllowedCollectionPath(collectionName, subcollectionName)) {
        return sendJson(res, 403, { code: 'COLLECTION_FORBIDDEN' }, corsHeader);
      }
      if (subcollectionName && !isValidPathSegment(parentDocId)) {
        return sendJson(res, 400, { code: 'INVALID_PARENT_DOC_ID' }, corsHeader);
      }
      if (branchId && (!isValidPathSegment(branchId) || !canUserAccessBranch(authzUser, branchId))) {
        return sendJson(res, 403, { code: 'BRANCH_ACCESS_DENIED' }, corsHeader);
      }

      // Mandatory parent-doc authorization for subcollections
      if (subcollectionName) {
        const parentSnap = await dataDb
          .doc(`restaurants/${restaurantId}/${collectionName}/${parentDocId}`)
          .get();
        dataReads += 1;
        if (!parentSnap.exists) {
          return sendJson(res, 404, { code: 'PARENT_NOT_FOUND' }, corsHeader);
        }
        const parentBranch = parentSnap.data()?.branchId;
        if (BRANCH_SCOPED_COLLECTIONS.has(collectionName)) {
          if (typeof parentBranch !== 'string' || !parentBranch.trim()) {
            // Deny ambiguous parent scope when user has branch restrictions
            if (allowedBranchList(authzUser) !== null) {
              return sendJson(res, 403, { code: 'AMBIGUOUS_PARENT_SCOPE' }, corsHeader);
            }
          } else if (!canUserAccessBranch(authzUser, parentBranch)) {
            return sendJson(res, 403, { code: 'PARENT_BRANCH_ACCESS_DENIED' }, corsHeader);
          }
        }
      }

      // --- Single document endpoint ---
      if (url.pathname === '/v1/preview/doc') {
        const docId = String(body.docId || '').trim();
        if (!isValidPathSegment(docId)) {
          return sendJson(res, 400, { code: 'INVALID_DOC_ID' }, corsHeader);
        }
        const docPath = subcollectionName
          ? `restaurants/${restaurantId}/${collectionName}/${parentDocId}/${subcollectionName}/${docId}`
          : `restaurants/${restaurantId}/${collectionName}/${docId}`;
        const snap = await dataDb.doc(docPath).get();
        dataReads += 1;
        if (!snap.exists) {
          return sendJson(res, 200, { exists: false, doc: null }, corsHeader);
        }
        const data = snap.data() || {};
        if (!subcollectionName && BRANCH_SCOPED_COLLECTIONS.has(collectionName)) {
          if (typeof data.branchId !== 'string' || !data.branchId.trim()) {
            if (allowedBranchList(authzUser) !== null) {
              return sendJson(res, 403, { code: 'AMBIGUOUS_BRANCH_SCOPE' }, corsHeader);
            }
          } else if (!canUserAccessBranch(authzUser, data.branchId)) {
            return sendJson(res, 403, { code: 'BRANCH_ACCESS_DENIED' }, corsHeader);
          }
        }
        const projected = projectDoc(subcollectionName || collectionName, snap.id, data);
        return sendJson(res, 200, {
          doc: projected,
          usage: { authzReads, dataReads, docsReturned: 1 },
        }, corsHeader);
      }

      // --- Cursor-paginated query endpoint ---
      const startBusinessDate = body.startBusinessDate ? String(body.startBusinessDate).trim() : null;
      const endBusinessDate = body.endBusinessDate ? String(body.endBusinessDate).trim() : null;
      const statusFilter = body.statusFilter ? String(body.statusFilter).trim() : null;
      if (!validateDateRange(startBusinessDate, endBusinessDate, maxDaysRange)) {
        return sendJson(res, 400, { code: 'INVALID_OR_EXCESSIVE_DATE_RANGE' }, corsHeader);
      }

      const requestedLimit = Number(body.limit || 100);
      const effectiveLimit = Math.min(
        Math.max(1, Number.isFinite(requestedLimit) ? requestedLimit : 100),
        maxDocsPerQuery,
      );

      let ref = subcollectionName
        ? dataDb.collection(`restaurants/${restaurantId}/${collectionName}/${parentDocId}/${subcollectionName}`)
        : dataDb.collection(`restaurants/${restaurantId}/${collectionName}`);

      // Enforce branch filtering at the Firestore query source for root branch-scoped collections
      if (!subcollectionName && BRANCH_SCOPED_COLLECTIONS.has(collectionName)) {
        if (branchId) {
          ref = ref.where('branchId', '==', branchId);
        } else {
          const allowed = allowedBranchList(authzUser);
          if (allowed !== null) {
            if (allowed.length === 0) {
              return sendJson(res, 403, { code: 'NO_AUTHORIZED_BRANCHES' }, corsHeader);
            }
            if (allowed.length === 1) {
              ref = ref.where('branchId', '==', allowed[0]);
            } else if (allowed.length <= 10) {
              ref = ref.where('branchId', 'in', allowed);
            }
          }
        }
      }

      if (startBusinessDate) {
        ref = ref.where('businessDate', '>=', startBusinessDate);
      }
      if (endBusinessDate) {
        ref = ref.where('businessDate', '<=', endBusinessDate);
      }
      if (statusFilter) {
        ref = ref.where('status', '==', statusFilter);
      }

      // Deterministic ordering by document ID (or businessDate + __name__ when range-filtered)
      if (startBusinessDate || endBusinessDate) {
        ref = ref.orderBy('businessDate', 'desc').orderBy('__name__', 'desc');
      } else {
        ref = ref.orderBy('__name__', 'asc');
      }

      const filterHash = computeFilterHash({
        restaurantId,
        collectionName,
        subcollectionName,
        parentDocId,
        branchId,
        startBusinessDate,
        endBusinessDate,
        statusFilter,
      });

      if (body.cursor) {
        if (
          typeof body.cursor !== 'object' ||
          body.cursor.filterHash !== filterHash ||
          !isValidPathSegment(body.cursor.lastDocId)
        ) {
          return sendJson(res, 400, { code: 'INVALID_CURSOR' }, corsHeader);
        }
        const cursorValues = startBusinessDate || endBusinessDate
          ? [String(body.cursor.lastBusinessDate || ''), body.cursor.lastDocId]
          : [body.cursor.lastDocId];
        ref = ref.startAfter(...cursorValues);
      }

      const snap = await ref.limit(effectiveLimit + 1).get();
      dataReads += snap.docs.length;
      const hasMore = snap.docs.length > effectiveLimit;
      const pageDocs = hasMore ? snap.docs.slice(0, effectiveLimit) : snap.docs;

      const projectedDocs = [];
      for (const d of pageDocs) {
        const data = d.data() || {};
        if (!subcollectionName && BRANCH_SCOPED_COLLECTIONS.has(collectionName)) {
          if (typeof data.branchId !== 'string' || !data.branchId.trim()) {
            if (allowedBranchList(authzUser) !== null) continue;
          } else if (!canUserAccessBranch(authzUser, data.branchId)) {
            continue;
          }
        }
        projectedDocs.push(projectDoc(subcollectionName || collectionName, d.id, data));
      }

      const lastDoc = pageDocs.length > 0 ? pageDocs[pageDocs.length - 1] : null;
      const nextCursor = hasMore && lastDoc
        ? {
            filterHash,
            lastDocId: lastDoc.id,
            ...(startBusinessDate || endBusinessDate
              ? { lastBusinessDate: String(lastDoc.data()?.businessDate || '') }
              : {}),
          }
        : null;

      logger({
        event: 'preview_query',
        collection: subcollectionName ? `${collectionName}/${subcollectionName}` : collectionName,
        docsReturned: projectedDocs.length,
        dataReads,
        hasMore,
      });

      return sendJson(res, 200, {
        docs: projectedDocs,
        nextCursor,
        hasMore,
        isPartial: hasMore,
        usage: { authzReads, dataReads, docsReturned: projectedDocs.length },
      }, corsHeader);
    } finally {
      const current = inFlightCounts.get(uid) || 1;
      if (current <= 1) inFlightCounts.delete(uid);
      else inFlightCounts.set(uid, current - 1);
    }
  });

  server.requestTimeout = requestTimeoutMs;
  return server;
}

module.exports = { createPreviewServer, canUserAccessBranch, computeFilterHash };
