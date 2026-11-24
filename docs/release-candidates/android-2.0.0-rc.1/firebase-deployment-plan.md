# Preparación Firebase — TacoPOS 2.0.0-rc.1

Documento de control de despliegue. La Rules mínima ya se desplegó con autorización; las dos Functions siguen pendientes por bloqueos de App Check/IAM.

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

El listado actual no contiene las callables de captura. Su despliegue selectivo queda detenido hasta resolver App Check/IAM. Después, desplegar exclusivamente:

```powershell
firebase deploy --only functions:submitLocalOrderCapture,functions:resolveLocalOrderCaptureSubmission --project tacopos-renovadev
```

La configuración versionada fija `nodejs22` para el codebase Functions y `engines.node=22` en `functions/package.json`; el lockfile generado con npm en Node `22.21.0` coincide. Firebase documenta que `functions.runtime` en `firebase.json` prevalece sobre `package.json`, por eso se conservan ambos valores iguales.

No usar `--only functions` a secas y no redesplegar `backofficePinLogin`, Caja u otras Functions. Confirmar en el listado que solo se crearon/actualizaron esos dos endpoints y que ambos exigen Auth/App Check, consumen token de uso limitado y operan en `us-central1`.

Inventario actual (solo lectura): `backofficePinLogin`, `cancelExpenseRequest`, `listBackofficeUsers`, `submitExpenseRequest`; las cuatro son Gen 2, `nodejs20`, región `us-central1` y ejecutan con `346084471865-compute@developer.gserviceaccount.com`. No se incluirán en RC.1. Node 20 fue retirado el `2026-10-30`; planificar su migración por separado, sin actualizar esas cuatro junto con las callables nuevas.

Las callables nuevas tienen `enforceAppCheck=true` y `consumeAppCheckToken=true`. El IAM del proyecto no muestra `roles/firebaseappcheck.tokenVerifier` para la cuenta de ejecución Gen 2 por defecto. Esa cuenta también la usan las cuatro Functions existentes; no se ha concedido el rol y su alcance requiere una decisión explícita. Además, `playintegrity.googleapis.com` está `DISABLED`; aunque existe una configuración Firebase Play Integrity, no se pudo confirmar el vínculo desde Play Console a `tacopos-renovadev`. No desplegar las callables hasta resolver ambos puntos.

## App Check y Play Integrity

La configuración Firebase conserva `MEETS_DEVICE_INTEGRITY`, `allowUnrecognizedVersion: true` y TTL `3600s`. Se registraron las SHA-256 actual/anterior de Play, conservando la de carga; no se modificaron los controles App Check. El servicio `playintegrity.googleapis.com` aparece `DISABLED`, y el vínculo de Play Console requiere confirmación del propietario.

Antes del internal test, el propietario debe confirmar en Firebase App Check que el app ID y paquete corresponden a producción y si `allowUnrecognizedVersion: true` es intencional para la política de distribución. Validar token real desde una instalación de pista interna; el Emulator no acredita Play Integrity. Confirmar en Play Console que la firma de la pista usa Play App Signing y cotejar los certificados antes de atribuir una falla a Rules.

## Compatibilidad y orden

1. Mantener compatibilidad con `1.5.13+31`: la regla solo reserva IDs nuevos y las funciones nuevas no son invocadas por esa versión.
2. Rules mínima ya desplegada y verificada por lectura posterior.
3. Resolver vínculo/servicio Play Integrity y el permiso Token Verifier; después desplegar solo las dos Functions y verificar sus settings. No activar actualización obligatoria.
4. Instalar la RC desde Internal Testing, validar el flujo físico y reconciliar envíos pendientes.
5. Si cualquier paso falla, detener la pista; no retirar Rules/Functions mientras haya clientes con una respuesta de envío incierta. Resolver o drenar esos IDs antes de rollback server-side.

Las reglas productivas leídas carecen de varias protecciones terminales/financieras presentes en la versión más nueva del repositorio. No se incluyeron en este parche mínimo ni se deben desplegar como parte de esta candidata sin revisión y autorización separadas.
