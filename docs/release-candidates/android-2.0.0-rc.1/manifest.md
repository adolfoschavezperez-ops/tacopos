# TacoPOS Android 2.0.0-rc.1 — candidato de preparación

Estado: **PREPARACIÓN LOCAL; NO AUTORIZADO PARA COMPILAR, DISTRIBUIR O PUBLICAR**

Fecha de validación: 2026-11-24 (America/Mexico_City)

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
| SHA de rama remota comprobado | `05323e9ac1fa9cd8f3f28b0c72426155f6fdd65d` |
| Worktree de preparación | `C:/Users/geren/Documents/RenovaDev/tacopos-release-2.0.0-rc.1` |
| Rama local de preparación | `release/android-2.0.0-rc.1-prep` |
| Artefacto y SHA-256 | No generado |
| Etiqueta Git | No creada; esperar a verificar artefacto y SHA final |

`pubspec.yaml` permanece en `1.5.13+31`. El worktree de preparación no cambia la versión. Antes de compilar, un commit autorizado deberá actualizarla a `2.0.0-rc.1+32` (solo si Play confirma libre el código 32) y respaldar ese mismo SHA en la rama remota de release. El guard de procedencia pasó en la rama fuente aprobada; este worktree local aún no es compilable: contiene este paquete de preparación sin commit remoto y deliberadamente no tiene `android/key.properties`.

## Integridad de Firebase y distribución

- `android/app/google-services.json` identifica `tacopos-renovadev` y el paquete `com.renova.tacopos`.
- `lib/main.dart` rechaza `TACOPOS_FIREBASE_EMULATORS=true` en release y solo activa Play Integrity para Android release. No se debe pasar define de Emulator al build.
- La cuenta Firebase autenticada pudo leer el recurso de Rules y las configuraciones App Check. La Rules Firestore activa se identificó como `projects/tacopos-renovadev/releases/cloud.firestore`, ruleset `projects/tacopos-renovadev/rulesets/c4cd13aa-b1a5-4e69-b98e-dfb6f42802d7`, actualizado `2026-08-28T01:30:48.691327Z`.
- Se preparó [una copia de esa Rules activa con únicamente el rechazo de IDs `capture_submission_*`](production-marker-only.rules). No es el `firestore.rules` completo del repositorio y no se desplegó.
- El listado productivo actual contiene `backofficePinLogin`, `cancelExpenseRequest`, `listBackofficeUsers` y `submitExpenseRequest`; `submitLocalOrderCapture` y `resolveLocalOrderCaptureSubmission` todavía no aparecen desplegadas.
- App Check Play Integrity está configurado para la app Android `1:346084471865:android:fb196c5d19a1e300f949e8`, exige `MEETS_DEVICE_INTEGRITY`; la respuesta de configuración indica `allowUnrecognizedVersion: true`. El código de Functions exige App Check y consume token limitado para ambas callables fuera del Emulator.
- Las tablets `1.5.13+31` no contienen `capture_submission_*`, `submitLocalOrderCapture` ni `resolveLocalOrderCaptureSubmission` (revisión del worktree +31). El parche de Rules reserva únicamente ese prefijo y conserva la creación normal de otros eventos `activityLog`; la ruta antigua no cambia.

## Firma, pendiente de confirmación

El worktree `release/android-1.5.11-28` conserva la configuración local `android/key.properties` y el keystore externo en `C:/Users/geren/Documents/RenovaDev/keys/tacopos-upload-key.jks`; no se copiaron secretos al worktree nuevo. El certificado local de carga encontrado tiene SHA-256:

`85:D4:5B:55:67:43:89:66:78:23:4D:81:95:E1:F1:17:2F:C2:CE:17:B1:99:10:7E:98:24:7C:9E:D5:BA:05:EE`

Esto identifica el certificado del keystore de carga local, pero **no demuestra** que coincida con el certificado de carga registrado en Play Console ni identifica el certificado de firma de Play App Signing. Ambos deben verificarse en Play Console antes de autorizar una subida. El worktree de preparación requiere recibir `key.properties` por el canal secreto aprobado; nunca se debe incluir en Git.

Gradle espera el archivo local ignorado `android/key.properties` con las claves `storePassword`, `keyPassword`, `keyAlias` y `storeFile`, según `android/app/build.gradle.kts`. El archivo y el keystore no existen en este worktree. El propietario puede colocarlos desde el almacén secreto aprobado; verificar después `git check-ignore android/key.properties` y no copiar/mostrar los valores. No hay credenciales ni keystore en el paquete de respaldo.

## Validación de este SHA

- `flutter analyze`: PASS, sin issues.
- `flutter test`: PASS, 944 pruebas.
- Functions contra Firestore/Auth Emulator aislados: PASS, 110 pruebas.
- Firestore Rules Emulator aislado: PASS, 130 pruebas en la suite final bajo Node `22.21.0`; incluye 3 pruebas sobre la Rules productiva recuperada más el guard mínimo `capture_submission_*`.
- Functions Emulator cargó las seis definiciones locales, incluidas ambas callables de captura. La comprobación HTTP GET devolvió 400 por método inválido y no ejecutó escrituras.
- `node tools/verify_release_worktree.js`: PASS en la rama fuente respaldada en GitHub.
- Evidencia reproducible de runtime y Rules: [validation-node22.md](validation-node22.md).
- La preparación de release fija Node 22 de forma concordante en `functions/package.json` (`engines.node`) y `firebase.json` (`functions.runtime`); `functions/package-lock.json` registra también el engine 22. Validación local con Node `22.21.0` y npm `11.6.2`.
- Las cuatro Functions actualmente desplegadas se inventariaron como `nodejs20`: `backofficePinLogin`, `cancelExpenseRequest`, `listBackofficeUsers` y `submitExpenseRequest`. No se redesplegarán con esta preparación. Node 20 llegó a retirada el `2026-10-30`; existe riesgo de que Google impida nuevas actualizaciones y posteriormente deshabilite workloads, por lo que se requiere una actualización separada antes de que afecte servicio.
- La suite de Functions bajo Node 22 pasó con 110 pruebas. La suite completa de Rules pasó con 130 pruebas; los tres escenarios del archivo `tacopos_2rc_production_rules_compat.rules.test.js` instancian la copia de Rules desplegada más el cambio mínimo y validan compatibilidad +31 para eventos corrientes, captura, Cocina, extras, sucursal, pagos parciales/finales y cierre normal de caja.
- La suite Rules completa se ejecutó contra un Emulator temporal con `singleProjectMode=false`; los `clearFirestore()` de las pruebas no tocaron la instancia ficticia conciliada del puerto 8080.

## Condiciones que faltan para autorizar RC.1

1. Confirmar que Play no ha usado `versionCode 32` y comparar certificados de carga y Play App Signing en la app `com.renova.tacopos`.
2. Revisar/aceptar la Rules mínima contra la release activa identificada; programar su despliegue por separado. No desplegar `firestore.rules` del worktree, que contiene otras protecciones acumuladas no presentes en producción.
3. Desplegar únicamente las dos callables indicadas, después de Rules, y verificar sus opciones App Check en producción sin reemplazar otras Functions.
4. Cerrar el riesgo de `allowUnrecognizedVersion: true` mediante confirmación del propietario de que corresponde a la política de pruebas Play; comprobar una instalación interna reconocida por Play Integrity.
5. Configurar firma en el worktree dedicado mediante canal secreto, actualizar versión solo tras autorización, commit/push del SHA final y guard limpio con remote SHA coincidente.
6. Generar AAB únicamente tras autorización separada; comprobar paquete, versión, `versionCode`, firma y SHA-256; después crear la etiqueta anotada `tacopos-android-v2.0.0-rc.1+32` apuntando al SHA exacto del artefacto.
