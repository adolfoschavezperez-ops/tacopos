# Signing and App Check verification

Date: 2026-11-24 (America/Mexico_City)

## Firebase Android app (read-only)

- Firebase project: `tacopos-renovadev`.
- Android package: `com.renova.tacopos`.
- Firebase App ID: `1:346084471865:android:fb196c5d19a1e300f949e8` (ACTIVE).
- `firebase apps:android:sha:list` returned exactly one registered certificate: SHA-256 `85:D4:5B:55:67:43:89:66:78:23:4D:81:95:E1:F1:17:2F:C2:CE:17:B1:99:10:7E:98:24:7C:9E:D5:BA:05:EE`. No SHA-1 entry or Play app-signing certificate was returned.
- This Firebase SHA-256 exactly matches the local upload keystore and the upload certificate supplied from Play Console.
- The current Play app-signing SHA-256 supplied by the owner (`D2:8F:BF:06:AF:8F:57:2C:3C:7E:79:17:C5:FE:2B:9A:1F:EF:88:D1:5F:77:95:CB:51:00:F1:7D:35:75:C6:21`) is **not currently registered** in Firebase. The prior Play app-signing certificate is also not in the returned list; its fingerprints were not supplied in this verification.

The read-only Play Integrity config currently has `tokenTtl=3600s`, `allowUnrecognizedVersion=true`, and `minDeviceRecognitionLevel=MEETS_DEVICE_INTEGRITY`. Firebase's App Check documentation says registered SHA-256 signing fingerprints are used to validate Play Integrity tokens. Therefore the Play-signed installation is not fully verified against the current Firebase registration. Before distributing through Play, register the current Play app-signing SHA-256 and, if the previous app-signing key can still sign/serve installed builds, its SHA-256 as well. Preserve the existing upload-key entry. Do not change App Check enforcement/recognition controls as part of that registration.

No Firebase configuration was modified. No certificate was removed.

## Local upload signing setup

- The external keystore `C:/Users/geren/Documents/RenovaDev/keys/tacopos-upload-key.jks` exists.
- `keytool -list` using the existing local `android/key.properties` confirmed alias `tacopos-upload` and both owner-provided upload-certificate fingerprints: SHA-1 `59:F2:2A:AC:CD:2D:8D:09:7D:41:15:33:10:DF:2C:F5:5F:E8:C8:CA`; SHA-256 `85:D4:5B:55:67:43:89:66:78:23:4D:81:95:E1:F1:17:2F:C2:CE:17:B1:99:10:7E:98:24:7C:9E:D5:BA:05:EE`.
- The existing ignored `android/key.properties` was copied locally into this release worktree and points to the same external keystore. `android/.gitignore` ignores it; Git status remains clean and the secret file is not committed or pushed.
- The AAB must be signed by this upload key for Play upload; Google Play then signs delivered APKs with its app-signing key. These are distinct roles and certificates.
- No new key was created, no key reset was requested, and no artifact was built.

## Required owner follow-up

Obtain the previous Play app-signing SHA-256 from Play Console. Then authorize adding the current and previous app-signing SHA-256 fingerprints to this existing Firebase Android app without deleting the upload fingerprint or changing App Check settings. Re-run the read-only SHA listing and validate a Play-installed internal-test build's App Check token before wider distribution.
