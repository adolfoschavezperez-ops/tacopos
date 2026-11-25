# Validation evidence — Node.js 22

Date: 2026-11-25 (America/Mexico_City)

## Environment

- Node.js `22.21.0`; npm `11.6.2`.
- Firebase CLI `15.30.0`.
- Firebase Emulator project IDs used were `demo-*`; emulators used local Auth/Firestore endpoints only.
- These emulator test runs used demo IDs and local endpoints only. Production Rules/Functions deployment and the signed AAB build are recorded separately below; no production business records were written.

## Results

- `npm test --prefix functions`: **PASS, 112 tests** after adding coverage for Firebase CLI discovery. This runs the TypeScript build and `scripts/verify-test-emulator.js` before the tests. The emulator guard reported a `demo-*` project and local Auth/Firestore endpoints.
- Firebase CLI Functions Emulator discovery: **PASS**, using Node `22.21.0` and isolated local ports. It loaded exactly the six source definitions and exited without invoking any function. A first attempt on default ports was blocked by an already occupied port; no existing process was stopped.
- Full Firestore Rules Emulator suite: **PASS, 130 tests** using the repository Rules file.
- The full Rules suite includes `test/firestore-rules/tacopos_2rc_production_rules_compat.rules.test.js`. That test initializes the exact retrieved production Rules source plus the single `capture_submission_*` marker guard and verifies three compatibility groups: ordinary +31 activity events and marker immutability; capture, kitchen actions, extras, and branch scope; partial/final payments and normal cash close.
- `git diff --check`: **PASS** before committing the discovery guard.

## Production deployment follow-up

- Commit `4d2afbe` (remote branch `release/android-2.0.0-rc.1-prep`) fixes the CLI discovery guard. The guard remains active in tests and Functions Emulator; it exempts the Firebase CLI's `FUNCTIONS_CONTROL_API=true` discovery subprocess.
- Selective deployment created exactly `submitLocalOrderCapture` and `resolveLocalOrderCaptureSubmission` as active Gen 2 Node.js 22 functions in `us-central1`. `firebase functions:list` confirmed the four pre-existing Node.js 20 functions retained their prior hashes and service account.
- Both new callables retain `enforceAppCheck=true` and `consumeAppCheckToken=true`. An unauthenticated POST probe to each returned `401 UNAUTHENTICATED` without data writes. This does not prove App Check token issuance/consumption; a Play-installed Android test is still required.
- Firebase CLI deployment preflight enabled `cloudbilling.googleapis.com` and generated the managed Pub/Sub and Eventarc service identities. No cleanup policy was configured.
- Firebase CLI reported a non-zero final status after both function create operations succeeded because no Artifact Registry cleanup policy exists. No cleanup policy was added; that storage policy is outside this release's authorized deployment scope.

The release worktree has no root `node_modules`; its `functions/node_modules` supplies the Functions toolchain. The full Rules suite used already installed test dependencies from the source worktree because this repo's root `package.json` currently combines `firebase@^12` with `@firebase/rules-unit-testing@^4.0.1` (peer range Firebase `^11`), and a clean npm install fails with `ERESOLVE`. No dependency manifests were changed to work around this.

`npm audit --omit=dev` in `functions/` reported **9 moderate affected-package paths**, with no high or critical findings. The paths converge on one advisory, GHSA-w5hq-g745-h8pq/CVE-2026-41907: `uuid@9.0.1` is transitively included by Firebase Admin/Google Cloud libraries. The reported issue is specifically `uuid.v3/v5/v6` accepting an undersized caller-provided buffer or invalid offset without bounds rejection. Static search of the candidate's installed runtime dependency trees found only `uuid.v4()` callsites (in `teeny-request`) and no `v3/v5/v6` callsite or candidate direct UUID use, so the vulnerable API path is not exercised by the current candidate code. This reduces demonstrated reachability but does not remove the dependency finding; npm's automatic graph remediation requires a major Firebase Admin update to `14.5.1` (and/or Functions SDK update), so no major dependency change was included in this frozen release prep.

The separate root `ERESOLVE` affects only the Rules-test toolchain: root `package.json` combines `firebase@^12` with `@firebase/rules-unit-testing@^4.0.1` (peer range Firebase `^11`). It does not affect the production Functions dependency install, which has its own Node 22 lockfile, nor the Android APK/AAB runtime. The Rules suite was executed with already installed test dependencies from the source worktree; no root dependency manifests were changed.

## Scope

The emulator Rules suite and Functions tests ran against demo project IDs only. Emulator-generated transaction lock-timeout and permission-denied diagnostics occurred in expected concurrency/negative authorization cases; the test processes exited successfully with the counts above.
