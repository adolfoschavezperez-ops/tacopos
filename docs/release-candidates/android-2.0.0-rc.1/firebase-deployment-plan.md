# Preparación Firebase — TacoPOS 2.0.0-rc.1

Documento de control de despliegue. La Rules mínima y las dos Functions nuevas ya se desplegaron con autorización. La prueba de token Play Integrity desde una instalación real y la confirmación de versionCode 32 siguen pendientes.

## Rules mínima — DESPLEGADA

La release Firestore activa leída en solo lectura es `projects/tacopos-renovadev/releases/cloud.firestore`, ruleset `c4cd13aa-b1a5-4e69-b98e-dfb6f42802d7`, con `updateTime` `2026-08-28T01:30:48.691327Z`. El archivo [production-marker-only.rules](production-marker-only.rules) se obtuvo de esa versión y agrega únicamente esta condición al `create` de `activityLog`:

```rules
allow create: if !eventId.matches('^capture_submission_.*$') &&
  validCreate(restaurantId);
```

Todas las demás líneas corresponden a la fuente desplegada recuperada; no sustituirla por el `firestore.rules` completo del repositorio. Se preparó una configuración separada que apunta solo a esta fuente:

```powershell
firebase deploy --config docs/release-candidates/android-2.0.0-rc.1/firebase-rules-only.json --only firestore:rules --project tacopos-renovadev
```

Antes del despliegue se volvió a leer producción: Ruleset `c4cd13aa-b1a5-4e69-b98e-dfb6f42802d7`, `updateTime` `2026-08-28T01:30:48.691327Z`; al retirar la única condición nueva, la fuente coincidió byte a byte con el Ruleset activo. Con autorización, el archivo aislado se desplegó con el comando anterior. Lectura posterior: Ruleset `167eb735-240f-44cb-9665-7bc42b9dceda`, `updateTime` `2026-11-24T23:54:44.318606Z`, SHA-256 `6bb0f073ba64290eb944146198bb66f03dc56c01ec587b22647818bd7bb2f7d7`, idéntico al candidato. La regla conserva eventos `activityLog` ordinarios y no altera +31.

## Functions selectivas

Despliegue selectivo completado el 2026-11-25, commit de preparación `4d2afbe`:

```powershell
firebase deploy --only functions:submitLocalOrderCapture,functions:resolveLocalOrderCaptureSubmission --project tacopos-renovadev
```

El listado de producción confirma `submitLocalOrderCapture` y `resolveLocalOrderCaptureSubmission` ACTIVE, Gen 2, Node.js 22, `us-central1`, con la cuenta de ejecución `346084471865-compute@developer.gserviceaccount.com`. Los otros cuatro endpoints siguen Node.js 20 y conservan sus hashes de despliegue previos: no se redesplegaron. La compatibilidad con +31 se conserva porque esas instalaciones no llaman las nuevas callables y las Rules solo reservan los marcadores de captura.

No usar `--only functions` a secas y no redesplegar `backofficePinLogin`, Caja u otras Functions. El listado posterior mostró solo las dos nuevas Functions en Node 22; las cuatro existentes permanecen en Node 20, región `us-central1`, mismo service account y mismos hashes anteriores. En el código desplegado, ambas callables conservan `enforceAppCheck=true` y `consumeAppCheckToken=true`.

Inventario actual (solo lectura): `backofficePinLogin`, `cancelExpenseRequest`, `listBackofficeUsers`, `submitExpenseRequest`; las cuatro son Gen 2, `nodejs20`, región `us-central1` y ejecutan con `346084471865-compute@developer.gserviceaccount.com`. No se incluirán en RC.1. Node 20 fue retirado el `2026-10-30`; planificar su migración por separado, sin actualizar esas cuatro junto con las callables nuevas.

El propietario confirmó el vínculo de Play Integrity desde Play Console con `tacopos-renovadev`. Con autorización expresa se habilitó `playintegrity.googleapis.com` y se concedió únicamente `roles/firebaseappcheck.tokenVerifier` a `346084471865-compute@developer.gserviceaccount.com`; los permisos previos se conservaron. La cuenta es compartida por las cuatro Functions antiguas, pero estas no se redesplegaron. No se modificó la política de App Check.

## App Check y Play Integrity

La configuración Firebase conserva `MEETS_DEVICE_INTEGRITY`, `allowUnrecognizedVersion: true` y TTL `3600s`. Se registraron las SHA-256 actual/anterior de Play, conservando la de carga; no se modificaron los controles App Check. El servicio está habilitado y el propietario confirmó el vínculo Play Console.

Una solicitud POST sin autenticación a cada callable respondió `401 UNAUTHENTICATED` y no creó datos. Esto verifica que los endpoints están activos y rechazan una llamada anónima, pero no sustituye una prueba con ID token y token App Check real. El propietario confirmó que `versionCode 32` está libre y el AAB ya se generó; validar el token real desde una instalación de pista interna antes de ampliar la distribución.

## Compatibilidad y orden

1. Mantener compatibilidad con `1.5.13+31`: la regla solo reserva IDs nuevos y las funciones nuevas no son invocadas por esa versión.
2. Rules mínima ya desplegada y verificada por lectura posterior.
3. Con vínculo Play Integrity, API y permiso Token Verifier activos, las dos Functions quedaron desplegadas. No activar actualización obligatoria.
4. Tras confirmar versionCode 32 y generar el AAB, instalar la RC desde Internal Testing, validar token App Check y flujo físico, y reconciliar envíos pendientes.
5. Si cualquier paso falla, detener la pista; no retirar Rules/Functions mientras haya clientes con una respuesta de envío incierta. Resolver o drenar esos IDs antes de rollback server-side.

Las reglas productivas leídas carecen de varias protecciones terminales/financieras presentes en la versión más nueva del repositorio. No se incluyeron en este parche mínimo ni se deben desplegar como parte de esta candidata sin revisión y autorización separadas.
