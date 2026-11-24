const fs = require("fs");
const path = require("path");
const {spawnSync} = require("child_process");
const {assertSafeFunctionsTestEnvironment} = require("../lib/testEnvironment");

assertSafeFunctionsTestEnvironment();

for (const file of fs.readdirSync(path.join(__dirname, "../src/test"))) {
  if (!file.endsWith(".test.ts")) continue;
  const source = fs.readFileSync(path.join(__dirname, "../src/test", file), "utf8");
  const adminImport = source.search(/(?:from\s*["']firebase-admin(?:\/[^"']+)?["']|require\(\s*["']firebase-admin(?:\/[^"']+)?["']\s*\))/);
  if (adminImport >= 0) {
    const guardImport = source.search(/import\s*["']\.\.\/testEnvironment["']/);
    if (guardImport < 0 || guardImport > adminImport) {
      throw new Error(`Refusing Functions tests: ${file} must import the emulator guard before Firebase Admin.`);
    }
  }
}

const project = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
const firestoreEmulator = process.env.FIRESTORE_EMULATOR_HOST;
console.log(`Functions tests target local emulators (${project}; Firestore ${firestoreEmulator}).`);

const mocha = path.join(__dirname, "../node_modules/mocha/bin/mocha.js");
const result = spawnSync(process.execPath, [mocha, "--timeout", "30000", "lib/test/**/*.test.js"], {
  cwd: path.join(__dirname, ".."),
  stdio: "inherit",
  env: {...process.env, NODE_ENV: "test", TACOPOS_FUNCTIONS_TEST: "true"},
});
if (result.error) throw result.error;
process.exit(result.status ?? 1);
