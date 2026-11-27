# TacoPOS Backoffice 2.0 — Propuesta y Runbook de Habilitación Controlada de Preview

- **Rama:** `feat/backoffice-v2`
- **Alcance habilitado en Preview:** Dashboard, Ventas, Caja, Compras, Proveedores, CXP y Finanzas (solo lectura).
- **Módulos explícitamente bloqueados (navegación y URL directa):** Autorizaciones, Inventarios, Reportes, Auditoría, Empleados y Configuración.
- **Estado actual:** Implementación y validación E2E en Chrome sobre emuladores completadas; pendiente **autorización única del propietario** para aprovisionar infraestructura Cloud Run / Blaze / Hosting Preview e IAM de solo lectura.

---

## 1. Arquitectura de Aislamiento e Identidad (Sin Llaves JSON Permanentes)

La arquitectura separa tres planos para impedir cualquier escritura o fuga hacia producción:

1. **Identidad y Allowlist (`tacopos-backoffice-dev`):**
   - Autenticación del propietario mediante Firebase Auth en el proyecto aislado `tacopos-backoffice-dev`.
   - Allowlist en colección `previewUsers/{uid}` dentro de Firestore `tacopos-backoffice-dev` (`enabled`, `restaurantId`, `branchAccess`, `allBranchesAccess`, `role`, `expiresAt`).
   - En `firestore.backoffice-v2.rules`, `match /previewUsers/{uid}` tiene `allow read, write: if false;` desde clientes; únicamente el backend Preview API (Admin SDK) lee esta colección.
2. **Backend Intermedio Solo Lectura (`tools/preview_api/` en Cloud Run):**
   - Ejecuta con identidad administrada de Cloud Run (Service Account dedicado en `tacopos-backoffice-dev`, **sin archivos JSON de credenciales descargados ni secretos estáticos**).
   - Se le otorga exclusivamente el rol IAM **`roles/datastore.viewer`** sobre el proyecto productivo `tacopos-renovadev` (solo lectura en Firestore; cero permisos de escritura, cero `roles/editor`, cero `roles/owner`, cero acceso de modificación a Auth/Functions/Hosting productivos).
   - Variables de entorno requeridas en Cloud Run (`tools/preview_api/index.js`):
     - `PREVIEW_AUTH_PROJECT_ID=tacopos-backoffice-dev`
     - `PREVIEW_DATA_PROJECT_ID=tacopos-renovadev`
     - `PREVIEW_ALLOWED_ORIGINS=https://tacopos-backoffice-preview.web.app`
     - `PREVIEW_MAX_DOCS_PER_QUERY=500`
     - `PREVIEW_RATE_LIMIT_PER_MIN=120`
     - `PREVIEW_MAX_CONCURRENT=6`
     - `PREVIEW_MAX_DAYS_RANGE=93`
3. **Cliente Web Preview (`https://tacopos-backoffice-preview.web.app`):**
   - Sitio independiente en Firebase Hosting dentro de `tacopos-backoffice-dev`, compilado con `--dart-define=ENV=preview` y `--dart-define=PREVIEW_API_URL=https://<cloud-run-preview-api-url>` (sin `USE_EMULATORS`).
   - Todos los repositorios habilitados (`DashboardRepository`, `SalesRepository`, `CashRepository`, `PurchasesRepository`, `FinanceRepository`) consumen `PreviewApiClient` por HTTPS con Firebase ID Token; si Preview API no responde, fallan de forma explícita sin fallback a Firestore DEV ni producción.

---

## 2. Runbook Exacto de Aprovisionamiento GCP / Firebase

> **Nota:** Ninguno de estos pasos se ha ejecutado todavía; requieren autorización explícita del propietario.

### Paso A — Service Account e IAM de solo lectura (sin llaves permanentes)

```bash
# 1. Crear Service Account dedicado en tacopos-backoffice-dev
gcloud iam service-accounts create preview-api-runner \
  --project=tacopos-backoffice-dev \
  --display-name="TacoPOS Backoffice Preview API (Read-Only)"

# 2. Otorgar lectura sobre Firestore DEV (para leer previewUsers/{uid})
gcloud projects add-iam-policy-binding tacopos-backoffice-dev \
  --member="serviceAccount:preview-api-runner@tacopos-backoffice-dev.iam.gserviceaccount.com" \
  --role="roles/datastore.viewer"

# 3. Otorgar EXCLUSIVAMENTE roles/datastore.viewer sobre el proyecto productivo
gcloud projects add-iam-policy-binding tacopos-renovadev \
  --member="serviceAccount:preview-api-runner@tacopos-backoffice-dev.iam.gserviceaccount.com" \
  --role="roles/datastore.viewer"
```

### Paso B — Despliegue en Cloud Run (HTTPS, escala a cero y límites duros)

```bash
gcloud run deploy tacopos-preview-api \
  --project=tacopos-backoffice-dev \
  --region=us-central1 \
  --source=tools/preview_api \
  --service-account=preview-api-runner@tacopos-backoffice-dev.iam.gserviceaccount.com \
  --allow-unauthenticated \
  --min-instances=0 \
  --max-instances=2 \
  --concurrency=20 \
  --memory=256Mi \
  --cpu=1 \
  --timeout=30s \
  --set-env-vars="PREVIEW_AUTH_PROJECT_ID=tacopos-backoffice-dev,PREVIEW_DATA_PROJECT_ID=tacopos-renovadev,PREVIEW_ALLOWED_ORIGINS=https://tacopos-backoffice-preview.web.app,PREVIEW_MAX_DOCS_PER_QUERY=500,PREVIEW_RATE_LIMIT_PER_MIN=120,PREVIEW_MAX_CONCURRENT=6,PREVIEW_MAX_DAYS_RANGE=93"
```

*Nota sobre `--allow-unauthenticated`: Cloud Run permite el tráfico HTTPS del navegador, pero `tools/preview_api/server.js` rechaza toda petición sin `Authorization: Bearer <Firebase ID Token>` válido + registro activo en `previewUsers/{uid}` (HTTP 401/403) y aplica CORS estricto a `PREVIEW_ALLOWED_ORIGINS`.*

### Paso C — Hosting independiente y Onboarding / Revocación del Propietario

1. Crear sitio adicional en Firebase Hosting (`tacopos-backoffice-dev`):
   - `firebase hosting:sites:create tacopos-backoffice-preview --project tacopos-backoffice-dev`
   - URL definitiva de Preview: **`https://tacopos-backoffice-preview.web.app`**
2. Compilar y desplegar build Preview (sin `USE_EMULATORS`):
   - `flutter build web -t lib/main_backoffice.dart --dart-define=ENV=preview --dart-define=PREVIEW_API_URL=https://<cloud-run-url>`
   - `firebase deploy --only hosting:preview --project tacopos-backoffice-dev`
3. Alta del propietario:
   - Crear usuario en Firebase Auth de `tacopos-backoffice-dev`.
   - Registrar `previewUsers/{uid}` con `enabled: true`, `restaurantId` real de Los Padrinos, `allBranchesAccess: true` (o `branchAccess: [<aviacionId>]`), `role: "owner"`.
4. **Revocación instantánea (emergencia o término de validación):**
   - Cambiar `previewUsers/{uid}.enabled = false` (efecto inmediato en la siguiente petición al API) y ejecutar `auth.revokeRefreshTokens(uid)` en `tacopos-backoffice-dev`.

---

## 3. Costos, Plan Blaze y Controles de Consumo

- **Requisito de facturación:** Cloud Run requiere que `tacopos-backoffice-dev` esté en plan **Blaze (pago por uso)**. `tacopos-renovadev` no requiere cambios de facturación adicionales más allá de las lecturas Firestore que realice Preview.
- **Estimación mensual (uso exclusivo del propietario en validación):**
  - Cloud Run (`min-instances=0`, `max-instances=2`, 256MiB): dentro del nivel gratuito mensual de Cloud Run (2M peticiones, 360k GB-seg) -> **~\$0.00 a \$1.00 USD/mes**.
  - Lecturas Firestore en `tacopos-renovadev`: acotadas por página (20 docs por lista, máx. 500 por consulta), caché en cliente (60s) y rango máximo de 93 días -> **< \$1.00 USD/mes** en uso normal de consulta.
  - Firebase Hosting (`tacopos-backoffice-preview.web.app`): dentro del nivel gratuito -> **\$0.00 USD/mes**.
- **Alertas de presupuesto vs. Límites duros:**
  - *Alertas de presupuesto GCP* (ej. \$5 / \$10 / \$20 USD): **son informativas**, no cortan automáticamente el servicio.
  - *Límites duros efectivos implementados en código e infraestructura:*
    - Infraestructura Cloud Run: `max-instances=2`, `concurrency=20`, `timeout=30s`.
    - Aplicación (`tools/preview_api/server.js`): `PREVIEW_RATE_LIMIT_PER_MIN=120` por UID, `PREVIEW_MAX_CONCURRENT=6` por UID, `PREVIEW_MAX_DOCS_PER_QUERY=500`, `PREVIEW_MAX_DAYS_RANGE=93`, y logs estructurados con contador de lecturas (`dataReads`) por petición.

---

## 4. Plan de Primera Sesión Real — Los Padrinos (Sucursal Aviación)

Una vez autorizado y desplegado Preview, ejecutar la primera comparación lado a lado **Backoffice 1.0 vs Backoffice 2.0 Preview** sobre **Los Padrinos — Sucursal Aviación**:

### Cortes a validar
1. **Último día cerrado** (corte diario completo más reciente).
2. **Semana `2026-11-23` al `2026-11-27`**.
3. **Último mes calendario completo**.

### Matriz de comparación obligatoria (V1 vs V2 Preview)
| Concepto | Módulo en V2 Preview | Validación esperada vs Backoffice 1.0 |
| :--- | :--- | :--- |
| Ventas brutas, descuentos y ventas netas | Dashboard / Ventas | Coincidencia exacta de totales y conteo de órdenes |
| Efectivo | Dashboard / Caja / Ventas | Coincidencia en cobros y arqueo de sesiones de caja |
| Tarjetas (débito/crédito) | Dashboard / Ventas / Caja | Coincidencia exacta por método de pago |
| Plataformas (delivery/apps) | Dashboard / Ventas | Coincidencia exacta por canal/plataforma |
| Compras | Compras | Coincidencia de compras registradas y detalle de partidas |
| Gastos / Retiros | Caja / Finanzas | Coincidencia de egresos y retiros de caja |
| Pagos a proveedores | Compras / Proveedores | Coincidencia de abonos y folios liquidados |
| Cuentas por pagar (CXP) | Compras (CXP) | Coincidencia de saldo pendiente por proveedor |

Además, comprobar en vivo:
- Que las acciones de escritura (cancelar venta, registrar compra, pagar proveedor, crear gasto/aportación, editar configuración) muestran estado de solo lectura y están bloqueadas.
- Que las rutas `#/employees`, `#/reports`, `#/audit`, `#/inventory`, `#/authorizations`, `#/settings` muestran el bloqueo explícito `Módulo no habilitado en Preview`.

---

## 5. Dictamen y Solicitud Única de Autorización

- **Dictamen técnico para Preview controlado:** **GO (condicionado únicamente a autorización de aprovisionamiento)**. La integración real con `PreviewApiClient`, el bloqueo de módulos no integrados, la paginación por cursor, la ausencia de fallback y el tráfico exclusivo hacia Preview API quedaron verificados en Chrome real contra emuladores.
- **Solicitud única de autorización al propietario:**
  > Se solicita autorización expresa para:
  > 1. Habilitar plan **Blaze** (con alerta de presupuesto en \$10 USD) en el proyecto aislado `tacopos-backoffice-dev`.
  > 2. Crear la identidad administrada `preview-api-runner@tacopos-backoffice-dev.iam.gserviceaccount.com` con **exclusivamente `roles/datastore.viewer`** sobre `tacopos-renovadev`.
  > 3. Desplegar `tacopos-preview-api` en Cloud Run (`min-instances=0`, `max-instances=2`) y el sitio `https://tacopos-backoffice-preview.web.app` para iniciar la primera sesión de validación en **Los Padrinos — Sucursal Aviación**.
