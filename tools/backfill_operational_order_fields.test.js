const assert = require('node:assert/strict');
const { classify } = require('./backfill_operational_order_fields');

const branch = (data = {}) => classify(data, 'aviacion');

assert.deepEqual(branch({}), {
  operationalActive: true,
  effectiveBranchId: 'aviacion',
});
assert.deepEqual(branch({ status: 'sent', createdAt: '2020-01-01' }), {
  operationalActive: true,
  effectiveBranchId: 'aviacion',
});
assert.equal(branch({ kitchenStatus: 'cancelada' }).operationalActive, false);
assert.equal(branch({ paymentStatus: 'CERRADA' }).operationalActive, false);
assert.equal(branch({ paidAt: {}, pendingTotal: 0.02 }).operationalActive, false);
assert.equal(branch({ paidAt: {}, pendingTotal: 0.03 }).operationalActive, true);
assert.equal(branch({ cancelledAt: {} }).operationalActive, false);
assert.equal(branch({ status: 'sent', branchId: ' norte ' }).effectiveBranchId, 'norte');

console.log('Backfill classifier: 8 assertions passed');
