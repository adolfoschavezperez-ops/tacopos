# Preparación Firebase — TacoPOS 2.0.0-rc.1

Este documento prepara comandos; no autoriza ejecución. No se desplegó nada.

## Rules mínima

La release Firestore activa leída en solo lectura es `projects/tacopos-renovadev/releases/cloud.firestore`, ruleset `c4cd13aa-b1a5-4e69-b98e-dfb6f42802d7`, con `updateTime` `2026-08-28T01:30:48.691327Z`. El archivo [production-marker-only.rules](production-marker-only.rules) se obtuvo de esa versión y agrega únicamente esta condición al `create` de `activityLog`:

```rules
allow create: if !eventId.matches('^capture_submission_.*$') &&
  validCreate(restaurantId);
```

Todas las demás líneas corresponden a la fuente desplegada recuperada; no sustituirla por el `firestore.rules` completo del repositorio. Se preparó una configuración separada que apunta solo a esta fuente:

```powershell
firebase deploy --config docs/release-candidates/android-2.0.0-rc.1/firebase-rules-only.json --only firestore:rules --project tacopos-renovadev
```

Ejecutar solo tras revisión del propietario, aceptación del diff de una condición y ventana autorizada. El cambio mantiene los eventos `activityLog` ordinarios y no altera el cliente `1.5.13+31`, que no usa el prefijo reservado.

## Functions selectivas

El listado de producción consultado actualmente no contiene las callables de captura. Una vez revisadas y con Rules lista, desplegar exclusivamente:

```powershell
firebase deploy --only functions:submitLocalOrderCapture,functions:resolveLocalOrderCaptureSubmission --project tacopos-renovadev
```

La configuración versionada fija `nodejs22` para el codebase Functions y `engines.node=22` en `functions/package.json`; el lockfile generado con npm en Node `22.21.0` coincide. Firebase documenta que `functions.runtime` en `firebase.json` prevalece sobre `package.json`, por eso se conservan ambos valores iguales.

No usar `--only functions` a secas y no redesplegar `backofficePinLogin`, Caja u otras Functions. Confirmar en el listado que solo se crearon/actualizaron esos dos endpoints y que ambos exigen Auth/App Check, consumen token de uso limitado y operan en `us-central1`.

Inventario de Functions existentes consultado en producción (solo lectura): `backofficePinLogin`, `cancelExpenseRequest`, `listBackofficeUsers`, `submitExpenseRequest`; todas declaran `nodejs20`. No se incluirán en el despliegue selectivo de RC.1. Node 20 fue retirado el `2026-10-30`; planificar y probar su migración en un cambio separado. No actualizar esas cuatro junto con las callables nuevas.

## App Check y Play Integrity

La consulta de solo lectura a Firebase devolvió para Android `MEETS_DEVICE_INTEGRITY`, `allowUnrecognizedVersion: true`. El código local activa `AndroidPlayIntegrityProvider` en release y configura ambas callables con `enforceAppCheck` fuera del Emulator y `consumeAppCheckToken: true`.

Antes del internal test, el propietario debe confirmar en Firebase App Check que el app ID y paquete corresponden a producción y si `allowUnrecognizedVersion: true` es intencional para la política de distribución. Validar token real desde una instalación de pista interna; el Emulator no acredita Play Integrity. Confirmar en Play Console que la firma de la pista usa Play App Signing y cotejar los certificados antes de atribuir una falla a Rules.

## Compatibilidad y orden

1. Mantener compatibilidad con `1.5.13+31`: la regla solo reserva IDs nuevos y las funciones nuevas no son invocadas por esa versión.
2. Aplicar la Rules mínima previamente revisada y verificar creación permitida de eventos normales y rechazada de `capture_submission_*`.
3. Desplegar las dos Functions con App Check y verificar sus nombres/settings; no activar todavía actualización obligatoria.
4. Instalar la RC desde Internal Testing, validar el flujo físico y reconciliar envíos pendientes.
5. Si cualquier paso falla, detener la pista; no retirar Rules/Functions mientras haya clientes con una respuesta de envío incierta. Resolver o drenar esos IDs antes de rollback server-side.

Las reglas productivas leídas carecen de varias protecciones terminales/financieras presentes en la versión más nueva del repositorio. No se incluyeron en este parche mínimo ni se deben desplegar como parte de esta candidata sin revisión y autorización separadas.
