# Validation evidence — Node.js 22

Date: 2026-11-24 (America/Mexico_City)

## Environment

- Node.js `22.21.0`; npm `11.6.2`.
- Firebase CLI `15.30.0`.
- Firebase Emulator project IDs used were `demo-*`; emulators used local Auth/Firestore endpoints only.
- No production deployment, writes, Android build, or AAB generation was performed.

## Results

- `npm test --prefix functions`: **PASS, 110 tests**. This runs the TypeScript build and `scripts/verify-test-emulator.js` before the tests. The emulator guard reported project `demo-tacopos-node22-validation` and Firestore `127.0.0.1:8181`.
- Full Firestore Rules Emulator suite: **PASS, 130 tests** using the repository Rules file.
- The full Rules suite includes `test/firestore-rules/tacopos_2rc_production_rules_compat.rules.test.js`. That test initializes the exact retrieved production Rules source plus the single `capture_submission_*` marker guard and verifies three compatibility groups: ordinary +31 activity events and marker immutability; capture, kitchen actions, extras, and branch scope; partial/final payments and normal cash close.
- `git diff --check`: **PASS** before staging.

The release worktree has no root `node_modules`; its `functions/node_modules` supplies the Functions toolchain. The full Rules suite used already installed test dependencies from the source worktree because this repo's root `package.json` currently combines `firebase@^12` with `@firebase/rules-unit-testing@^4.0.1` (peer range Firebase `^11`), and a clean npm install fails with `ERESOLVE`. No dependency manifests were changed to work around this.

`npm audit --omit=dev` in `functions/` reported **8 moderate production dependency advisories**, transitive through `firebase-admin` / Google Cloud libraries. npm says the available automatic remediation requires a major `firebase-admin` update to `14.5.1`; that dependency upgrade is outside this runtime-only preparation and remains for separate review.

## Scope

The emulator Rules suite and Functions tests ran against demo project IDs only. Emulator-generated transaction lock-timeout and permission-denied diagnostics occurred in expected concurrency/negative authorization cases; the test processes exited successfully with the counts above.
