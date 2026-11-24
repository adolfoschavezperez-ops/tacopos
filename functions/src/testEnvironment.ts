const localHostnames = new Set(["127.0.0.1", "localhost", "::1", "[::1]"]);

export function assertSafeFunctionsTestEnvironment(
  env: NodeJS.ProcessEnv = process.env,
): void {
  const projectIds = [env.GCLOUD_PROJECT, env.GOOGLE_CLOUD_PROJECT]
    .map((value) => value?.trim())
    .filter((value): value is string => Boolean(value));
  const firebaseConfig = env.FIREBASE_CONFIG?.trim();
  if (firebaseConfig) {
    if (!firebaseConfig.startsWith("{")) {
      throw new Error("Refusing Functions tests: FIREBASE_CONFIG must be a JSON object for the demo project.");
    }
    try {
      const projectId = (JSON.parse(firebaseConfig) as {projectId?: unknown}).projectId;
      if (typeof projectId !== "string" || !projectId.trim()) {
        throw new Error("Refusing Functions tests: FIREBASE_CONFIG must name the demo project.");
      }
      projectIds.push(projectId.trim());
    } catch {
      throw new Error("Refusing Functions tests: FIREBASE_CONFIG is invalid.");
    }
  }
  if (projectIds.length === 0 || projectIds.some((projectId) => !projectId.startsWith("demo-")) ||
      new Set(projectIds).size !== 1) {
    throw new Error("Refusing Functions tests: all configured projects must be the same demo-* project.");
  }

  assertLocalEndpoint("FIRESTORE_EMULATOR_HOST", env.FIRESTORE_EMULATOR_HOST);
  assertLocalEndpoint("FIREBASE_AUTH_EMULATOR_HOST", env.FIREBASE_AUTH_EMULATOR_HOST);
  for (const name of [
    "FIREBASE_DATABASE_EMULATOR_HOST",
    "FIREBASE_STORAGE_EMULATOR_HOST",
    "FIREBASE_REMOTE_CONFIG_EMULATOR_HOST",
    "FIREBASE_APP_CHECK_EMULATOR_HOST",
  ]) {
    const value = env[name];
    if (value?.trim()) assertLocalEndpoint(name, value);
  }
}

function assertLocalEndpoint(name: string, value: string | undefined): void {
  if (!value?.trim()) throw new Error(`Refusing Functions tests: ${name} is required.`);
  let parsed: URL;
  try {
    parsed = new URL(value.includes("://") ? value : `http://${value}`);
  } catch {
    throw new Error(`Refusing Functions tests: ${name} is not a valid host:port.`);
  }
  const hostname = parsed.hostname.toLowerCase();
  if (parsed.protocol !== "http:" || !localHostnames.has(hostname) || !parsed.port) {
    throw new Error(`Refusing Functions tests: ${name} must use a local HTTP emulator endpoint.`);
  }
}

function isTestInvocation(): boolean {
  if (process.env.NODE_ENV === "test" || process.env.TACOPOS_FUNCTIONS_TEST === "true") {
    return true;
  }
  return process.argv.some((argument) =>
    /(?:^|[/\\])(?:src|lib)[/\\]test(?:[/\\]|.*\.test\.(?:[cm]?js|ts)$)/i.test(argument),
  );
}

// Fail closed if an Admin-using Functions test is launched directly, outside
// the guarded npm runner. This module deliberately has no Firebase imports.
if (isTestInvocation()) assertSafeFunctionsTestEnvironment();
