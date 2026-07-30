# TacoPOS Google Play updates

## Android audit

- `applicationId`: `com.renova.tacopos`
- Gradle file: `android/app/build.gradle.kts`
- Version source: `pubspec.yaml`
- Current prepared version: `1.0.1+2`
- Current release signing fallback: Android debug key when `android/key.properties` does not exist
- Observed APK certificate for `build/app/outputs/flutter-apk/app-release.apk`:
  - DN: `C=US, O=Android, CN=Android Debug`
  - SHA-1: `56:63:67:74:4D:99:B9:3A:69:F9:D7:93:17:FF:45:F5:11:58:27:17`
  - SHA-256: `e1:59:99:74:f4:8e:ae:ff:e9:2b:05:7f:38:f8:9e:5c:ca:0b:d2:ec:c3:6a:fa:fd:a6:67:2c:97:b6:e8:d2:b3`

## Migration risk

The APKs currently installed from local files were built with the Android debug
certificate. A Google Play install can update them without uninstalling only if
the Play-delivered package is considered the same signed app by Android.

Do not switch to a new release key for tablets that already have the debug-signed
APK installed unless you accept uninstall/reinstall or a managed migration plan.
For production, create a permanent release key before the first public/internal
Play upload and keep it backed up.

## Permanent release key setup

Do not commit `.jks`, `.keystore`, or real `key.properties` files. They are
ignored by Git.

1. Create and store the keystore outside the repo:

   ```powershell
   keytool -genkeypair -v -keystore C:\secure\tacopos\tacopos-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias tacopos
   ```

2. Copy `android/key.properties.example` to `android/key.properties`.
3. Replace placeholders with the real passwords and `storeFile`.
4. Back up the keystore and passwords in a secure password vault.
5. Run `flutter build appbundle --release`.

When `android/key.properties` exists, Gradle signs release builds with that key.
When it does not exist, Gradle keeps the current debug signing fallback.

## Remote update configuration

Create this Firestore document:

`restaurants/main_restaurant/settings/appUpdates`

Fields:

- `minimumSupportedVersionCode`: number. Lowest version allowed to operate.
- `recommendedVersionCode`: number. Version that should be suggested.
- `updateMessage`: string shown to the operator.
- `forceUpdate`: boolean. If true, versions below `recommendedVersionCode` are forced.

Suggested initial values for version `2`:

- `minimumSupportedVersionCode`: `1`
- `recommendedVersionCode`: `2`
- `updateMessage`: `Hay una nueva version de TacoPOS disponible.`
- `forceUpdate`: `false`

For a critical update, set `minimumSupportedVersionCode` to the required build
number and `forceUpdate` to `true`.

## Google Play Console manual steps

1. Create the app with package `com.renova.tacopos`.
2. Enable Play App Signing.
3. Upload the generated AAB to Internal testing.
4. Add tester Google accounts or a tester group.
5. Complete required store listing, content rating, data safety, and app access forms.
6. Publish only to Internal testing first.
7. Install from the Play testing link on tablets.

TacoPOS opens the Google Play listing for installation. It does not download APKs
directly and does not use Firebase App Distribution as a production updater.

Current app behavior:

- Recommended update: shows a dialog, lets the operator continue temporarily,
  and can open Google Play.
- Required update: blocks operation below `minimumSupportedVersionCode` or below
  `recommendedVersionCode` when `forceUpdate=true`, then opens Google Play.
- If Firestore config cannot be fetched or there is no update configured, the app
  continues operating.
