// Safe, resumable Firestore Admin SDK backfill. Defaults to dry-run.
// Usage: node tools/backfill_operational_order_fields.js --project PROJECT_ID
// Add --apply only after review; --start-after DOCUMENT_ID resumes a page walk.
const args = new Set(process.argv.slice(2));
const value = (name) => {
  const i = process.argv.indexOf(name);
  return i < 0 ? null : process.argv[i + 1] || null;
};
const projectId = value('--project');
const restaurantId = value('--restaurant') || 'main_restaurant';
const defaultBranchId = value('--default-branch') || 'aviacion';
const pageSize = Number(value('--page-size') || 250);
if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > 500) {
  throw new Error('--page-size must be between 1 and 500');
}
const dryRun = !args.has('--apply');
const normalize = (v) => String(v ?? 'null').toLowerCase().trim()
  .replace(/[\u00e1\u00e9\u00ed\u00f3\u00fa\u00f1]/g, (c) => ({'\u00e1':'a','\u00e9':'e','\u00ed':'i','\u00f3':'o','\u00fa':'u','\u00f1':'n'}[c]))
  .replace(/\u00c3\u00a1|\u00c3\u00a9|\u00c3\u00ad|\u00c3\u00b3|\u00c3\u00ba|\u00c3\u00b1/g, (c) => ({'\u00c3\u00a1':'a','\u00c3\u00a9':'e','\u00c3\u00ad':'i','\u00c3\u00b3':'o','\u00c3\u00ba':'u','\u00c3\u00b1':'n'}[c]));
const cancelled = new Set(['cancelled','canceled','cancelado','cancelada','voided','anulado','anulada']);
const paid = new Set(['paid','pagado','pagada','closed','cerrado','cerrada']);
function classify(d, branchFallback = defaultBranchId) {
  const pending = typeof d.pendingTotal === 'number' ? d.pendingTotal : 0;
  const inactive = cancelled.has(normalize(d.status)) || cancelled.has(normalize(d.kitchenStatus)) ||
    cancelled.has(normalize(d.paymentStatus)) || d.cancelledAt != null || d.canceledAt != null ||
    paid.has(normalize(d.status)) || paid.has(normalize(d.paymentStatus)) || d.closedAt != null ||
    (d.paidAt != null && Math.abs(pending) <= 0.02);
  const branch = typeof d.branchId === 'string' && d.branchId.trim() ? d.branchId.trim() : branchFallback;
  return {operationalActive: !inactive, effectiveBranchId: branch};
}
async function main() {
  if (!projectId) throw new Error('Provide --project PROJECT_ID');
  const admin = require('../functions/node_modules/firebase-admin');
  if (!admin.apps.length) admin.initializeApp({ projectId });
  const db = admin.firestore();
  const counts = new Map();
  let cursor = value('--start-after');
  let scanned = 0, changed = 0, conflicts = 0;
  while (true) {
    let q = db.collection('restaurants').doc(restaurantId).collection('orders')
      .orderBy(admin.firestore.FieldPath.documentId()).limit(pageSize);
    if (cursor) q = q.startAfter(cursor);
    const page = await q.get();
    if (page.empty) break;
    for (const doc of page.docs) {
      scanned++;
      const d = doc.data();
      const fields = classify(d);
      const branchCount = counts.get(fields.effectiveBranchId) || {total:0,active:0,inactive:0,changed:0};
      branchCount.total++;
      branchCount[fields.operationalActive ? 'active' : 'inactive']++;
      const needs = d.operationalActive !== fields.operationalActive || d.effectiveBranchId !== fields.effectiveBranchId;
      if (needs) {
        branchCount.changed++;
        changed++;
        if (!dryRun) {
          try {
            await db.runTransaction(async (tx) => {
              const fresh = await tx.get(doc.ref);
              if (!fresh.exists || !fresh.updateTime.isEqual(doc.updateTime)) throw new Error('document-changed');
              tx.update(doc.ref, classify(fresh.data()));
            });
          } catch (e) {
            if (e.message === 'document-changed') conflicts++;
            else throw e;
          }
        }
      }
      counts.set(fields.effectiveBranchId, branchCount);
    }
    cursor = page.docs[page.docs.length - 1].id;
    process.stdout.write(JSON.stringify({checkpoint:cursor,scanned,changed,conflicts,dryRun}) + '\n');
  }
  console.log(JSON.stringify({projectId,restaurantId,dryRun,scanned,changed,conflicts,byBranch:Object.fromEntries(counts)},null,2));
}
module.exports = { classify };
if (require.main === module) {
  main().catch((e) => { console.error(e); process.exitCode = 1; });
}
