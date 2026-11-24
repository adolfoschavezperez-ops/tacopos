# TacoPOS release and Git policy

This policy applies independently to Android and Backoffice releases. It does not
authorize a merge, deployment, publication, migration, or version change by
itself.

## 1. Preserve and inventory worktrees

Before switching branches, deleting a worktree, cleaning files, rebasing, or
preparing a release, record for every worktree:

- absolute path, branch (or detached state), full `HEAD`, and `git status
  --short --untracked-files=all`;
- the configured upstream and remote SHA for the branch;
- committed-only and working-tree-only changes, including untracked files.

Use `git worktree list --porcelain`, then inspect each path with `git -C <path>`.
Never use `git clean`, blanket `git add`, reset, checkout, or stash to make a
worktree appear clean. Stop if an unexpected change appears. Preserve every
untracked file unless its owner explicitly authorizes its removal.

Before changing or removing a worktree containing legitimate work, preserve it
on a clearly named remote branch or an explicitly approved archive. Do not
publish secrets: inspect staged paths and patches for credentials first. A
backup is not permission to rewrite the original branch. Keep a written mapping
from the original branch/SHA to its backup branch/archive.

## 2. Release identity and traceability

Android and Backoffice version independently. Android uses `versionName` and a
monotonically increasing Play `versionCode`; Backoffice uses its own release
version and deployment record. Never infer one product's version from the
other's.

Create permanent tags only for releases whose source SHA and distributed
artifact are demonstrably linked by release records, CI provenance, or a
retained signed artifact with matching metadata. Do not create tags for
historical versions when the correspondence cannot be proven. Record any
unresolved history as unknown; do not guess from a nearby commit or version
string.

Use separate namespaces: `tacopos-android-v<version>+<versionCode>` for Android
(for example, `tacopos-android-v2.0.0-rc.1+32`) and
`tacopos-backoffice-v<version>` for Backoffice. Create each as an annotated tag
only after the release artifact passes verification. Never move or reuse a
published release tag.

For each candidate/release, retain a manifest containing:

| Field | Required value |
|---|---|
| Product/platform | Android, Backoffice, or other explicit target |
| Release label | For example `2.0.0-rc.1` |
| Version | Android `versionName` and `versionCode`, or Backoffice version |
| Source | Full commit SHA and branch/tag |
| Remote verification | Remote branch/tag SHA and verification time |
| Artifact | Exact path/name, package ID, signing-certificate fingerprint when applicable |
| Integrity | SHA-256 of the final artifact |
| Distribution | Track/environment and release URL, if any |
| Validation | Commands, results, device/emulator, and outstanding blockers |

Never store signing keys, passwords, access tokens, or other secrets in the
manifest or repository.

## 3. Release worktree and build gate

Build only from a dedicated release worktree after an explicit release decision.
Before building:

1. Confirm product, candidate version, and Play availability of the Android
   `versionCode` (or the corresponding Backoffice release identifier).
2. Confirm the worktree path, branch/tag, full `HEAD`, and a clean status,
   including untracked files.
3. Confirm the remote source SHA equals the local source SHA. A clean worktree
   on a stale or unverified commit is not releasable.
4. Confirm all intended source changes are committed and the candidate is based
   on the approved SHA. Do not silently include generated or local-only files.
5. Record build toolchain and signing identity without recording secrets.
6. After artifact generation, verify package/application ID, version metadata,
   signing certificate, and artifact SHA-256; then record the manifest.

For Android AABs, calculate SHA-256 from the final AAB bytes (for example,
`Get-FileHash -Algorithm SHA256 <path>`). A filename or build log alone does not
prove artifact identity. Do not reuse a `versionCode` already accepted by Play.

## 4. Candidate and rollback checklist

### TacoPOS Android 2.0.0-rc.1

- Target `versionName`: `2.0.0-rc.1`.
- Proposed `versionCode`: `32`, **pending Play Console confirmation**.
- Do not edit `pubspec.yaml`, build a production AAB, tag, or publish until the
  candidate is separately authorized and all validation gates are clear.
- Keep the 2.1.0 historical-orders query optimization out of this candidate.

### Candidate authorization checklist

- [ ] Approved source SHA is present remotely and matches the clean release worktree.
- [ ] Automated tests, real Android UI flow, two-device concurrency, and
  physical-device/network tests are recorded separately; no unrun scenario is
  marked passed.
- [ ] Production Rules and callable/App Check contract are verified read-only,
  or the release is blocked with the exact missing access/verification.
- [ ] Play `versionCode` is available.
- [ ] AAB package, version, signing certificate, and SHA-256 are verified.
- [ ] Internal testing results and operational recovery instructions are ready.
- [ ] Rollback owner, stop criteria, support contact, and forward-fix path are
  recorded.

### Rollback

For an Android rollout, pause or halt the affected Play track/rollout and stop
further promotion. Do not plan a downgrade: Android/Play version codes are
monotonic. Prepare a forward-fix with a higher available code. Preserve the
failed artifact, source SHA, logs, and local capture data needed for recovery.
Do not disable or remove server callables while clients may hold pending local
submissions. Keep server changes backward-compatible until the client rollback
window is closed. Backoffice rollback is independent and follows its own
deployment/version history.

## 5. Read-only production Rules review

The current validation operator has no usable Google access token, so deployed
Rules remain unverified. Ask the project owner to grant the reviewing principal
the predefined `roles/firebaserules.viewer` role on Firebase project
`tacopos-renovadev` only. This is the narrowest predefined Rules role; its
permissions are read-only for releases/rulesets and include Ruleset testing.
Do not grant Owner, Editor, Firebase Rules Admin, or deploy permissions.
The project owner can grant this role to the reviewer with:

```sh
gcloud projects add-iam-policy-binding tacopos-renovadev \
  --member="user:REVIEWER_EMAIL" \
  --role="roles/firebaserules.viewer"
```

Remove it after the read-only review with the same command using
`remove-iam-policy-binding`.

The owner or an authorized reviewer can inspect the active release using the
Firebase Rules REST API `GET` methods:

1. `GET https://firebaserules.googleapis.com/v1/projects/tacopos-renovadev/releases`
   to find the Firestore release and its `rulesetName`.
2. `GET https://firebaserules.googleapis.com/v1/{rulesetName}` to retrieve the
   source for that exact deployed ruleset.
3. Record the release name, ruleset name, update time, and source fingerprint,
   then compare it with the candidate rule block in `firestore.rules`.

Candidate requirement for local capture: client `create` of
`activityLog/capture_submission_*` markers must be denied; only Admin SDK
callables create those idempotency records. Existing activity log reads and
other writes must retain their current authorization. The repository currently
has that narrow prefix exclusion in `firestore.rules`, but this does **not**
prove the deployed ruleset contains it. No production Rules change is prepared
as a deployable replacement until the active source is retrieved and compared.

## 6. App Check contract

The source contract to verify for production is:

- Android release activates Play Integrity; debug uses the debug provider.
- Capture callable definitions enforce App Check outside Functions Emulator and
  consume a limited-use token.
- Android capture/resolve calls request limited-use App Check tokens.
- Functions Emulator intentionally disables capture App Check enforcement, so
  emulator success cannot prove Play Integrity registration, attestation, token
  consumption, or production callable deployment.

Before release, verify the Android app's Play Integrity provider is registered
for the production Firebase project/package and that the Play signing
certificate fingerprints match the Play App Signing configuration. Confirm the
deployed callable settings and complete one authorized internal-track smoke
test after a separate approval. Do not use production credentials in emulator
tests.

## 7. Inventory snapshot for the 2.0.0 validation work

Captured on 2026-11-24 before emulator-specific validation edits. This snapshot
is evidence of state at that time, not a replacement for a fresh inventory
before a later release. The feature worktree was clean at
`1808cf74675b58f7200a5fa41f32760cb34515c8`;

the remote `feature/durable-local-order-capture` SHA matched. `main` remained at
`7159969f01f196754638175e73a4f572585a5e76` and was not modified.

| Worktree | Branch | HEAD | Pre-existing status |
|---|---|---|---|
| `C:/Users/geren/Documents/RenovaDev/tacopos` | `fix/order-capture-kitchen-payment-consistency` | `90918ed1d89297a74dbcf63024ab4b238a267c78` | Untracked audit HTML, JSON, JS, PowerShell, PNG, and purchase snapshot files; preserved |
| `C:/Users/geren/Documents/RenovaDev/tacopos-active-orders` | `perf/active-orders-field` | `90918ed1d89297a74dbcf63024ab4b238a267c78` | Modified `firestore.indexes.json`, `lib/services/taco_pos_repository.dart`; untracked operational-order field tests/backfill files; preserved |
| `C:/Users/geren/Documents/RenovaDev/tacopos-hotfix-checkout-revision` | `hotfix/checkout-revision-conflict` | `f60f576494348ed94967a0770ac63c68e35d6200` | Clean |
| `C:/Users/geren/Documents/RenovaDev/tacopos-hotfix-first-person-quantity` | `hotfix/first-person-quantity-loss` | `f60f576494348ed94967a0770ac63c68e35d6200` | Modified repository, `pubspec.yaml`, version/product tests; untracked concurrency test; preserved |
| `C:/Users/geren/Documents/RenovaDev/tacopos-hotfix-kitchen-actions` | `hotfix/kitchen-actions-recovery` | `6b638e154921eb223134dee5fa5f35b0fee57f08` | Clean |
| `C:/Users/geren/Documents/RenovaDev/tacopos-hotfix-payment-return` | `hotfix/payment-return-to-tables` | `f60f576494348ed94967a0770ac63c68e35d6200` | Modified payment/order screens, version and tests; preserved |
| `C:/Users/geren/Documents/RenovaDev/tacopos-hotfix-payment-return-plus31` | `hotfix/payment-return-after-full-payment-31` | `fcac5117940aab241cdce125c79eecec94eff6df` | Modified payment/order screens, version and tests; preserved |
| `C:/Users/geren/Documents/RenovaDev/tacopos-local-capture-v1` | `feature/durable-local-order-capture` | `1808cf74675b58f7200a5fa41f32760cb34515c8` | Clean before this policy file |
| `C:/Users/geren/Documents/RenovaDev/tacopos-release-1.5.11-28` | `release/android-1.5.11-28` | `90918ed1d89297a74dbcf63024ab4b238a267c78` | Clean |

No historical release tags were added by this work. The only existing repository
tag observed was `v1.4.0`; this snapshot does not establish binary provenance for
other historical releases.
