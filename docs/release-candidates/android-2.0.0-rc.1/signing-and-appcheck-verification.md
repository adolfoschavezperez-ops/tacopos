# Signing and App Check verification

Date: 2026-11-24 (America/Mexico_City)

## Firebase Android app

- Firebase project: `tacopos-renovadev`.
- Android package: `com.renova.tacopos`.
- Firebase App ID: `1:346084471865:android:fb196c5d19a1e300f949e8` (ACTIVE).
- Before registration, `firebase apps:android:sha:list` returned only the upload certificate SHA-256 `85:D4:5B:55:67:43:89:66:78:23:4D:81:95:E1:F1:17:2F:C2:CE:17:B1:99:10:7E:98:24:7C:9E:D5:BA:05:EE`.
- This Firebase SHA-256 exactly matches the local upload keystore and the upload certificate supplied from Play Console.
- After explicit authorization, the current Play app-signing SHA-256 (`D2:8F:BF:06:AF:8F:57:2C:3C:7E:79:17:C5:FE:2B:9A:1F:EF:88:D1:5F:77:95:CB:51:00:F1:7D:35:75:C6:21`) and previous Play app-signing SHA-256 (`9F:61:A3:30:9F:F5:43:12:2C:54:66:3F:2F:D7:AD:45:EF:CC:35:94:AB:28:5D:11:EC:9D:9F:89:FA:6D:C0:13`) were added. Read-back confirmed exactly three SHA-256 entries: upload, current Play signing, and previous Play signing. No existing certificate was removed.

The Play Integrity config remains unchanged: `tokenTtl=3600s`, `allowUnrecognizedVersion=true`, and `minDeviceRecognitionLevel=MEETS_DEVICE_INTEGRITY`. Firebase's App Check documentation says registered SHA-256 signing fingerprints are used to validate Play Integrity tokens. A read-only Google Service Usage query returned `playintegrity.googleapis.com` state `DISABLED`; the Firebase-side config exists, but its Play Console project link to `tacopos-renovadev` could not be independently confirmed with available access. Resolve/verify the Play Console link and API state before testing a Play-installed build. No App Check controls were changed.

SHA-1 is not required by App Check Play Integrity, which validates SHA-256 fingerprints. Source review found Firebase custom-token authentication and no Google Sign-In, phone authentication, or Firebase Dynamic Links integration; SHA-1 registration is not needed for those services in this candidate. If those services are added later, register the corresponding SHA-1.

Firebase certificate metadata was modified only to add the two authorized SHA-256 hashes. App Check controls and SHA-1 registrations were not modified.

## Local upload signing setup

- The external keystore `C:/Users/geren/Documents/RenovaDev/keys/tacopos-upload-key.jks` exists.
- `keytool -list` using the existing local `android/key.properties` confirmed alias `tacopos-upload` and both owner-provided upload-certificate fingerprints: SHA-1 `59:F2:2A:AC:CD:2D:8D:09:7D:41:15:33:10:DF:2C:F5:5F:E8:C8:CA`; SHA-256 `85:D4:5B:55:67:43:89:66:78:23:4D:81:95:E1:F1:17:2F:C2:CE:17:B1:99:10:7E:98:24:7C:9E:D5:BA:05:EE`.
- The existing ignored `android/key.properties` was copied locally into this release worktree and points to the same external keystore. `android/.gitignore` ignores it; Git status remains clean and the secret file is not committed or pushed.
- The AAB must be signed by this upload key for Play upload; Google Play then signs delivered APKs with its app-signing key. These are distinct roles and certificates.
- No new key was created, no key reset was requested, and no artifact was built.

## Required owner follow-up

Verify in Play Console that Play Integrity is linked to `tacopos-renovadev`. Confirm why Service Usage reports `playintegrity.googleapis.com` as `DISABLED` and validate App Check token issuance from a Play-installed internal-test build before wider distribution.
