require('./safeTestEnvironment');
const assert = require('assert');
const { assertSafeRulesTestEnvironment } = require('./safeTestEnvironment');

describe('Firestore Rules test environment guard', () => {
  const safe = {
    GCLOUD_PROJECT: 'demo-rules-test',
    GOOGLE_CLOUD_PROJECT: 'demo-rules-test',
    FIREBASE_CONFIG: JSON.stringify({ projectId: 'demo-rules-test' }),
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080',
  };

  it('accepts one demo project and local Firestore emulator', () => {
    assert.doesNotThrow(() => assertSafeRulesTestEnvironment(safe));
  });

  it('rejects a non-demo project even if Firestore points locally', () => {
    assert.throws(
      () => assertSafeRulesTestEnvironment({ ...safe, GCLOUD_PROJECT: 'tacopos-renovadev' }),
      /same demo-\* project/,
    );
  });

  it('rejects mismatched configured project IDs', () => {
    assert.throws(
      () => assertSafeRulesTestEnvironment({ ...safe, GOOGLE_CLOUD_PROJECT: 'demo-other' }),
      /same demo-\* project/,
    );
  });

  it('requires the Firestore emulator host', () => {
    const { FIRESTORE_EMULATOR_HOST, ...withoutHost } = safe;
    assert.throws(
      () => assertSafeRulesTestEnvironment(withoutHost),
      /FIRESTORE_EMULATOR_HOST is required/,
    );
  });

  it('rejects a remote Firestore endpoint', () => {
    assert.throws(
      () => assertSafeRulesTestEnvironment({ ...safe, FIRESTORE_EMULATOR_HOST: 'firestore.googleapis.com:443' }),
      /local HTTP emulator/,
    );
  });
});
