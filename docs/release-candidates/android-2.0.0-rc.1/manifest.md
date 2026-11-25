# TacoPOS Android 2.0.0-rc.1 — candidato de preparación

Estado: **AAB FIRMADO Y VERIFICADO LOCALMENTE; NO SUBIDO A GOOGLE PLAY**

Fecha de validación: 2026-11-25 (America/Mexico_City)

## Identidad propuesta

| Campo | Valor / estado |
|---|---|
| Producto | TacoPOS Android |
| Versión candidata | `2.0.0-rc.1` |
| `versionCode` confirmado | `32` — libre según Google Play Console, confirmado por el propietario |
| Paquete | `com.renova.tacopos` |
| Proyecto Firebase de producción | `tacopos-renovadev` |
| SHA fuente base aprobada | `05323e9ac1fa9cd8f3f28b0c72426155f6fdd65d` |
| SHA exacto que produjo el AAB | `1c660da74c54cd87495b26c2698d3808a0bb638d` |
| Rama de preparación | `release/android-2.0.0-rc.1-prep` |
| Worktree de preparación | `C:/Users/geren/Documents/RenovaDev/tacopos-release-2.0.0-rc.1` |
| Rama local de preparación | `release/android-2.0.0-rc.1-prep` |
| Artefacto | `C:/Users/geren/Documents/RenovaDev/tacopos-release-2.0.0-rc.1/build/app/outputs/bundle/release/app-release.aab` |
| SHA-256 del AAB | `0B7571F7D18A1A05423CD42B1B48615E3CE459BF3441C4064F0426DEA55CE3D9` |
| Certificado de carga (SHA-256) | `85D45B556743896678234D8195E1F1172FC2CE17B199107E98247C9ED5BA05EE` |
| Etiqueta Git | `tacopos-android-v2.0.0-rc.1+32` (apunta al SHA que produjo el AAB) |
| Distribución | No subido a Play; pendiente prueba de token App Check en dispositivo desde Internal Testing |

`pubspec.yaml` está en `2.0.0-rc.1+32`. El propietario confirmó libre el `versionCode 32` en Google Play Console. El AAB se compiló desde el SHA exacto indicado y se validaron manifiesto, proyecto Firebase, paquete y certificado de carga. La firma local está configurada en `android/key.properties`, ignorado por Git.

## Integridad de Firebase y distribución

- `android/app/google-services.json` identifica `tacopos-renovadev` y el paquete `com.renova.tacopos`.
- `lib/main.dart` rechaza `TACOPOS_FIREBASE_EMULATORS=true` en release y solo activa Play Integrity para Android release. No se debe pasar define de Emulator al build.
- La Rules activa inicial se identificó como ruleset `c4cd13aa-b1a5-4e69-b98e-dfb6f42802d7`, actualizado `2026-08-28T01:30:48.691327Z`; su contenido coincidió exactamente con la base del archivo [production-marker-only.rules](production-marker-only.rules) al retirar el único guard de `capture_submission_*`.
- Con autorización expresa, se desplegó solo `firestore:rules` desde `firebase-rules-only.json`. Lectura posterior confirmó release `cloud.firestore`, ruleset `167eb735-240f-44cb-9665-7bc42b9dceda`, actualizado `2026-11-24T23:54:44.318606Z`; SHA-256 de contenido `6bb0f073ba64290eb944146198bb66f03dc56c01ec587b22647818bd7bb2f7d7`, idéntico al candidato. No se desplegó el `firestore.rules` completo del repositorio.
- El listado productivo posterior confirma submitLocalOrderCapture y resolveLocalOrderCaptureSubmission ACTIVE, Gen 2, Node.js 22 y us-central1. Las cuatro Functions existentes siguen en Node.js 20 con sus hashes previos; no fueron redesplegadas.
- App Check Play Integrity conserva `allowUnrecognizedVersion=true`, `MEETS_DEVICE_INTEGRITY` y TTL `3600s`. Se registraron SHA-256 del upload key y de las claves de firma actual/anterior de Play; el read-back conservó las tres.
- El propietario confirmó el vínculo Play Integrity en Play Console. Con autorización se habilitó `playintegrity.googleapis.com` y se concedió `roles/firebaseappcheck.tokenVerifier` a `346084471865-compute@developer.gserviceaccount.com`, conservando permisos existentes. No cambiaron los controles App Check. La emisión real del token debe probarse desde una instalación de Play.
- Las tablets `1.5.13+31` no contienen `capture_submission_*`, `submitLocalOrderCapture` ni `resolveLocalOrderCaptureSubmission` (revisión del worktree +31). El parche de Rules reserva únicamente ese prefijo y conserva la creación normal de otros eventos `activityLog`; la ruta antigua no cambia.

## Firma de carga preparada; token App Check real pendiente

El worktree `release/android-1.5.11-28` conserva la configuración local `android/key.properties` y el keystore externo en `C:/Users/geren/Documents/RenovaDev/keys/tacopos-upload-key.jks`. Se preparó una copia local ignorada en este worktree, sin subir credenciales. El certificado local de carga tiene SHA-256:

`85:D4:5B:55:67:43:89:66:78:23:4D:81:95:E1:F1:17:2F:C2:CE:17:B1:99:10:7E:98:24:7C:9E:D5:BA:05:EE`

El propietario confirmó desde Play Console que coinciden el certificado de carga del keystore y el de carga registrado. `keytool` verificó SHA-1 y SHA-256 localmente. La huella SHA-256 de Play App Signing es distinta; su estado de registro en Firebase y el certificado anterior están documentados en [signing-and-appcheck-verification.md](signing-and-appcheck-verification.md). No se debe confundir la clave de carga del AAB con la clave que firma los APK servidos por Play.

Gradle espera `android/key.properties` con las claves `storePassword`, `keyPassword`, `keyAlias` y `storeFile`, según `android/app/build.gradle.kts`. El archivo local ignorado está preparado en este worktree y apunta al keystore externo validado. No se incluyó ni en el commit ni en el paquete de respaldo; `git check-ignore` lo confirma.

## Validación del candidato y artefacto

- `flutter analyze`: PASS, sin issues.
- `flutter test`: PASS, 944 pruebas.
- Tests de versión dirigidos: PASS, 21 pruebas.
- `flutter build appbundle --release --no-pub`: PASS en el SHA `1c660da74c54cd87495b26c2698d3808a0bb638d`.
- `bundletool dump manifest`: paquete `com.renova.tacopos`, `versionName=2.0.0-rc.1`, `versionCode=32`.
- `bundletool dump resources`: Firebase project `tacopos-renovadev`, app ID `1:346084471865:android:fb196c5d19a1e300f949e8`.
- `jarsigner -verify`: PASS. `keytool -printcert -jarfile` confirmó que el firmante es la clave de carga verificada (SHA-256 `85:D4:5B:55:67:43:89:66:78:23:4D:81:95:E1:F1:17:2F:C2:CE:17:B1:99:10:7E:98:24:7C:9E:D5:BA:05:EE`).
- SHA-256 calculado del AAB: `0B7571F7D18A1A05423CD42B1B48615E3CE459BF3441C4064F0426DEA55CE3D9`.
- Functions contra Firestore/Auth Emulator aislados: PASS, 112 pruebas con Node 22.
- Firestore Rules Emulator aislado: PASS, 130 pruebas en la suite final bajo Node `22.21.0`; incluye 3 pruebas sobre la Rules productiva recuperada más el guard mínimo `capture_submission_*`.
- Functions Emulator cargó las seis definiciones locales en puertos aislados. Un POST sin autenticación a cada callable productiva devolvió `401 UNAUTHENTICATED` sin escribir datos; falta validar emisión de token Play Integrity real.
- `node tools/verify_release_worktree.js`: PASS en la rama fuente respaldada en GitHub.
- Evidencia reproducible de runtime y Rules: [validation-node22.md](validation-node22.md).
- Evidencia de firma y compatibilidad Firebase App Check: [signing-and-appcheck-verification.md](signing-and-appcheck-verification.md).
- La preparación de release fija Node 22 de forma concordante en `functions/package.json` (`engines.node`) y `firebase.json` (`functions.runtime`); `functions/package-lock.json` registra también el engine 22. Validación local con Node `22.21.0` y npm `11.6.2`.
- Las cuatro Functions actualmente desplegadas se inventariaron como `nodejs20`: `backofficePinLogin`, `cancelExpenseRequest`, `listBackofficeUsers` y `submitExpenseRequest`. No se redesplegarán con esta preparación. Node 20 llegó a retirada el `2026-10-30`; existe riesgo de que Google impida nuevas actualizaciones y posteriormente deshabilite workloads, por lo que se requiere una actualización separada antes de que afecte servicio.
- La suite de Functions bajo Node 22 pasó con 112 pruebas. La suite completa de Rules pasó con 130 pruebas; los tres escenarios del archivo `tacopos_2rc_production_rules_compat.rules.test.js` instancian la copia de Rules desplegada más el cambio mínimo y validan compatibilidad +31 para eventos corrientes, captura, Cocina, extras, sucursal, pagos parciales/finales y cierre normal de caja.
- La suite Rules completa se ejecutó contra un Emulator temporal con `singleProjectMode=false`; los `clearFirestore()` de las pruebas no tocaron la instancia ficticia conciliada del puerto 8080.

## Pendiente antes de ampliar distribución

1. Subir el AAB manualmente a Google Play Internal Testing; no está publicado por este proceso.
2. Instalar desde Play en tablet y validar emisión/verificación de App Check Play Integrity y el flujo operativo real.
3. Mantener sin cambios `allowUnrecognizedVersion`, TTL y nivel de integridad; no activar actualización obligatoria.
