'use strict';

function assertSafeRulesTestEnvironment(env = process.env) {
  const projectIds = [env.GCLOUD_PROJECT, env.GOOGLE_CLOUD_PROJECT]
    .map((value) => value?.trim())
    .filter(Boolean);
  const firebaseConfig = env.FIREBASE_CONFIG?.trim();
  if (firebaseConfig) {
    if (!firebaseConfig.startsWith('{')) {
      throw new Error('Refusing Rules tests: FIREBASE_CONFIG must be a JSON object.');
    }
    let projectId;
    try {
      projectId = JSON.parse(firebaseConfig).projectId;
    } catch {
      throw new Error('Refusing Rules tests: FIREBASE_CONFIG is invalid.');
    }
    if (typeof projectId !== 'string' || !projectId.trim()) {
      throw new Error('Refusing Rules tests: FIREBASE_CONFIG must name the demo project.');
    }
    projectIds.push(projectId.trim());
  }
  if (projectIds.length === 0 || projectIds.some((id) => !id.startsWith('demo-')) ||
      new Set(projectIds).size !== 1) {
    throw new Error('Refusing Rules tests: all configured projects must be the same demo-* project.');
  }

  const rawHost = env.FIRESTORE_EMULATOR_HOST?.trim();
  if (!rawHost) throw new Error('Refusing Rules tests: FIRESTORE_EMULATOR_HOST is required.');
  let parsed;
  try {
    parsed = new URL(rawHost.includes('://') ? rawHost : `http://${rawHost}`);
  } catch {
    throw new Error('Refusing Rules tests: FIRESTORE_EMULATOR_HOST is invalid.');
  }
  if (parsed.protocol !== 'http:' ||
      !['127.0.0.1', 'localhost', '::1', '[::1]'].includes(parsed.hostname.toLowerCase()) ||
      !parsed.port) {
    throw new Error('Refusing Rules tests: Firestore must use a local HTTP emulator endpoint.');
  }
}

assertSafeRulesTestEnvironment();

module.exports = { assertSafeRulesTestEnvironment };
