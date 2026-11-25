# TacoPOS Android 2.0.0-rc.1 — candidato de preparación

Estado: **PREPARACIÓN REMOTA; AAB BLOQUEADO HASTA CONFIRMAR versionCode 32; NO PUBLICAR**

Fecha de validación: 2026-11-25 (America/Mexico_City)

## Identidad propuesta

| Campo | Valor / estado |
|---|---|
| Producto | TacoPOS Android |
| Versión candidata | `2.0.0-rc.1` |
| `versionCode` propuesto | `32` — **pendiente de confirmar en Google Play Console** |
| Paquete | `com.renova.tacopos` |
| Proyecto Firebase de producción | `tacopos-renovadev` |
| SHA fuente validado | `05323e9ac1fa9cd8f3f28b0c72426155f6fdd65d` |
| Rama fuente respaldada | `feature/durable-local-order-capture` |
| SHA remoto del guard de descubrimiento verificado | `4d2afbead2a5e3f552bc2eb9cde253abcdfac626` |
| Worktree de preparación | `C:/Users/geren/Documents/RenovaDev/tacopos-release-2.0.0-rc.1` |
| Rama local de preparación | `release/android-2.0.0-rc.1-prep` |
| Artefacto y SHA-256 | No generado |
| Etiqueta Git | No creada; esperar a verificar artefacto y SHA final |

`pubspec.yaml` permanece en `1.5.13+31`. El propietario aún debe confirmar que `versionCode 32` está libre en todas las pistas. Tras esa confirmación, un commit de versión respaldado en remoto permitirá preparar el AAB autorizado. La firma local está configurada en `android/key.properties`, ignorado por Git.

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

## Validación de este SHA

- `flutter analyze`: PASS, sin issues.
- `flutter test`: PASS, 944 pruebas.
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

## Condiciones que faltan para autorizar RC.1

1. Confirmar en Play Console que versionCode 32 no se ha usado en ninguna pista.
2. Tras confirmar el versionCode 32, actualizar la versión en un commit respaldado en remoto y ejecutar el guard de procedencia sobre ese SHA.
3. Las dos callables ya están desplegadas; validar sus tokens App Check desde una instalación Play antes de ampliar distribución.
4. Mantener sin cambios `allowUnrecognizedVersion`, TTL y nivel de integridad; validar una instalación interna reconocida por Play Integrity.
5. Generar el AAB autorizado y validar paquete, versión, código, certificado de carga y SHA-256.
6. Crear la etiqueta anotada `tacopos-android-v2.0.0-rc.1+32` solo después de verificar el artefacto.
