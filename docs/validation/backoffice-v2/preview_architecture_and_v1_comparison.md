# Arquitectura Backoffice 2.0 Preview (Solo Consulta) y Matriz Comparativa V1 vs V2 — Fase 9.1.1

**Rama:** `feat/backoffice-v2`  
**Objetivo:** Permitir que el propietario consulte información real de Los Padrinos directamente desde la base original en modo **estrictamente de solo lectura**, para validar y comparar Backoffice 2.0 frente a Backoffice 1.0 (`7159969`) sin riesgo para Android (+32) ni producción.

---

## 1. Arquitectura Recomendada y Alternativas Evaluadas

### Alternativa A — Identidad Firebase Auth directa contra Firestore productivo (**DESCARTADA**)
- **Por qué se descarta:** Las Firestore Rules productivas heredadas permiten escrituras amplias mediante `signedIn()`. Agregar una regla que niegue escrituras a un usuario específico **no protege** si otra regla `allow write: if signedIn()` permite la operación. Además, leer `employees` directamente entregaría campos `pin` en texto plano al navegador (`P0-4`), y modificar las Rules productivas conlleva riesgo de bloquear Android (+32) o Backoffice 1.0.

### Alternativa B — API Intermedia Autenticada de Solo Lectura con separación Auth/Authz/Data e IAM `roles/datastore.viewer` (**RECOMENDADA E INTEGRADA EN FLUTTER**)
- **Flujo (Fase 9.1.2):**
  1. El cliente Flutter Web (`ENV=preview`) se autentica contra Firebase Auth en un proyecto aislado (`tacopos-backoffice-dev`, sin PINs heredados).
  2. `BackofficeV2AuthService` y los 7 módulos prioritarios (`DashboardRepository`, `SalesRepository`, `CashRepository`, `PurchasesRepository` [Compras/Proveedores/CXP], `FinanceRepository`) consumen **exclusivamente** `PreviewApiClient` (`POST /v1/preview/session`, `/v1/preview/query`, `/v1/preview/doc`) con token Bearer renovable y **cero fallback** a Firestore DEV o producción.
  3. El servidor **Preview Read-Only API** (`tools/preview_api/server.js`) separa explícitamente `auth` (Firebase Auth aislado), `authzDb` (`previewUsers/{uid}` aislado) y `dataDb` (Firestore de datos operativos con **únicamente `roles/datastore.viewer`**).
  4. Para subcolecciones (`orders/{id}/items`, `orders/{id}/payments`, `kitchenSessions/{id}/items`, `supplierPurchases/{id}/items`), el servidor valida primero el documento padre y su `branchId` (denegando alcance ambiguo).
  5. `projection.js` aplica proyecciones explícitas en `employees`, `devices`, `activityLog`, `settings` y `payments`, más sanitización recursiva de llaves sensibles (`pin`, `password`, `token`, `secret`, `credential`, `apiKey`).
  6. Paginación determinista por cursor (`nextCursor`, `hasMore`, `filterHash`), rate-limit por UID, límite de concurrencia, CORS restringido y tope de rango histórico (`maxDaysRange`).
- **Módulos prioritarios integrados en Preview (Fase 9.1.2):** `Dashboard`, `Ventas` (+ detalle), `Caja`, `Compras`, `Proveedores`, `Cuentas por pagar` y `Finanzas`. Los módulos secundarios (`Inventarios`, `Reportes`, `Auditoría`, `Empleados`, `Configuración`) permanecen sin fallback y se conectarán progresivamente sobre el mismo `PreviewApiClient` (sin mostrar datos sintéticos).
- **Ventajas:** Cero modificaciones a `firestore.rules` de producción, cero impacto en Android (+32) y Backoffice 1.0, protección criptográfica de `pin`, imposible escribir incluso ante un error de código porque la cuenta de servicio carece de permisos IAM de escritura.

### Alternativa C — Copias periódicas / Exportación a proyecto secundario (**DESCARTADA**)
- **Por qué se descarta:** El propietario requiere consultar información en tiempo real sin depender de sincronizaciones o copias periódicas.

---

## 2. Permisos IAM Exactos Requeridos (Principio de Mínimo Privilegio)

Para la Cuenta de Servicio dedicada (`tacopos-preview-reader@<proyecto>.iam.gserviceaccount.com`):
- **En el proyecto productivo (lectura de datos):**
  - `roles/datastore.viewer` (**exclusivamente lectura** de Cloud Firestore; prohíbe `datastore.entities.create/update/delete`).
- **En el proyecto aislado de autenticación/autorización (`tacopos-backoffice-dev`):**
  - Lectura de `previewUsers/{uid}` y verificación de tokens/revocación Firebase Auth (`roles/firebaseauth.viewer` + lectura Firestore de `previewUsers`).
- **Prohibido asignar en producción:** `roles/datastore.user`, `roles/editor`, `roles/owner`, `roles/firebase.admin` o cualquier permiso de escritura.
- **Credenciales en cliente:** Cero llaves de servicio en Flutter Web o navegador.
- **Nota sobre verificación IAM real:** Las pruebas actuales validan la lógica contra Emulator; la verificación efectiva de permisos IAM (`roles/datastore.viewer` rechazando escrituras en GCP) deberá completarse durante la habilitación controlada cuando el propietario autorice la cuenta de servicio.

---

## 3. Estimación de Consumo y Costos (Control de Costo)

| Módulo | Lecturas estimadas / consulta (periodo 1-7 días) | Lecturas por sesión típica | Límite de protección en Preview API |
| --- | --- | --- | --- |
| Dashboard | ~150 - 600 lecturas (caché TTL 60s) | ~600 | `MAX_DOCS_PER_QUERY = 500` por llamada |
| Ventas (paginado) | 20 órdenes + detalle bajo demanda | ~100 | Paginación por cursor `20/pág` |
| Caja | ~20 sesiones + ~50 retiros | ~150 | Filtro obligatorio por fecha + sucursal |
| Compras / Proveedores / CXP | ~80 compras + ~60 pagos | ~200 | Acotado por periodo |
| Inventarios / Cocina | ~40 sesiones + ~150 insumos | ~220 | Sin listeners en vivo |
| Finanzas / Reportes / Auditoría | ~300 - 1,200 lecturas (caché TTL 60s) | ~800 | Advertencia `isPartial` al tope |
| Empleados / Productos / Config | ~50 empleados (proyectados) + ~150 productos | ~200 | Carga única por pestaña |

- **Consumo estimado propietario (consulta diaria de validación):** ~2,000 a 5,000 lecturas/día (~60,000 - 150,000 lecturas/mes), dentro de la cuota gratuita diaria de Firestore (50,000 lecturas/día) o costo marginal mínimo (<$0.10 USD/mes excedente).
- **Infraestructura intermedia (Cloud Run cuando el propietario autorice):** Nivel gratuito de Cloud Run incluye 2 millones de solicitudes/mes y 180,000 vCPU-seg/mes. *Nota: desplegar un servicio externo o Cloud Function requiere autorización previa del propietario para habilitar facturación Blaze si no existe un entorno ya habilitado.*

---

## 4. Cambios Implementados en Fase 9.1.1 (Aislados en DEV/Emulator)

1. **`BackofficeEnv.preview` y `EnvironmentGuard`** (`lib/backoffice_v2/core/env/backoffice_env.dart`):
   - Nuevo ambiente explícito `preview` con `isReadOnly == true`, validación estricta de `PREVIEW_API_URL` (HTTPS o loopback en pruebas) y bloqueo permanente de `tacopos-renovadev`/`github.io` en `firebaseOptions`.
2. **`BackofficeReadOnlyGuard`** (`lib/backoffice_v2/core/read_only_guard.dart`):
   - Bloquea en la capa de acceso a datos cualquier operación de escritura cuando `isReadOnly == true`.
3. **Indicador visual permanente** (`lib/backoffice_v2/navigation/app_shell.dart` y `environment_banner.dart`):
   - Banner discreto permanente **`PREVIEW — Datos reales · Solo consulta`** en escritorio y móvil, conservando modos claro y oscuro.
4. **Preview Read-Only API** (`tools/preview_api/server.js`, `projection.js`, `test/preview_api.test.js`):
   - Endpoints exclusivamente de lectura (`GET /health`, `POST /v1/preview/query`, `POST /v1/preview/doc`), rechazo `405` a todo método HTTP de escritura, proyección anti-PIN en `employees`, allowlist de colecciones y validación de token revocable + sucursal.

---

## 5. Primera Validación Financiera — Matriz Comparativa V1 vs V2

**Criterios de corte obligatorios para cada prueba de comparación:**
- Mismo `restaurantId`, misma `branchId` (o todas), misma `businessDate` / rango de fechas, mismos criterios de órdenes canceladas (`isCanonicalCancelledOrder`), y corte en horario sin movimientos en curso.

| Rubro financiero | Fuente V1 (`7159969`) | Fuente V2 (`feat/backoffice-v2`) | Causa potencial de diferencia / Pendiente conocido | Resultado esperado al comparar |
| --- | --- | --- | --- | --- |
| **Ventas brutas** | `CanonicalSalesSummary.grossSales` | `CanonicalSalesSummary.grossSales` | Equivalente (mismo helper canónico). | **Idéntico** |
| **Ventas netas** | `CanonicalSalesSummary.netSales` | `CanonicalSalesSummary.netSales` | Equivalente. | **Idéntico** |
| **Efectivo** | `cashCollected` | `cashCollected` | Equivalente (sujeto a `P1-5` si supera límite en consultas grandes). | **Idéntico** (verificar aviso `isPartial`) |
| **Tarjetas** | `cardCollected` | `cardCollected` | Equivalente. | **Idéntico** |
| **Plataformas** | `platformCollected` | `platformCollected` | Equivalente. | **Idéntico** |
| **Propinas** | `tipsTotal` | `tipsTotal` | V2 separa propinas de venta neta en `FinancePeriodSummary`. | **Idéntico** |
| **Comisiones** | `cardFeesAbsorbed` | `cardFeesAbsorbed` | Equivalente cuando existen registros de comisión. | **Idéntico** |
| **Descuentos** | `discountTotal` | `discountTotal` | Equivalente. | **Idéntico** |
| **Consumos internos** | `employeeConsumption` / `employeeFreeMealTotal` | `employeeConsumption` / `employeeFreeMealTotal` | V2 los separa explícitamente de ingresos monetarios. | **Idéntico en monto** |
| **Compras** | `supplierPurchases` | `supplierPurchases` | Equivalente (excluye `cancelled`). | **Idéntico** |
| **Gastos** | `cashWithdrawalRequests` (aprobados) | `cashWithdrawalRequests` (aprobados, caja vs histórico) | Equivalente. | **Idéntico** |
| **Pagos a proveedores** | `supplierPayments` (activos) | `supplierPayments` (activos) | Equivalente. | **Idéntico** |
| **Cuentas por pagar** | `supplierPurchases.balance` pendiente | `supplierPurchases.balance` pendiente | Equivalente. | **Idéntico** |
| **Inventarios** | `kitchenSessions` / `kitchenStockItems` | `InventoryRepository` | Equivalente. | **Idéntico** |
| **Utilidad / Rentabilidad** | `YieldProfitReport` / `FinanceDashboardBundle` | `FinanceRepository` / `ReportsRepository` | **Pendientes `P1-3` y `P1-4`**: en `ReportsRepository._runYieldProfit` pueden filtrarse partidas de órdenes canceladas (`P1-3`), y el comparativo del periodo anterior en `FinanceRepository` omite COGS/pagos (`P1-4`). | **Requiere revisión explícita de `P1-3` y `P1-4` durante comparación** |

---

## 6. Procedimiento de Conexión a Producción y Revocación (Pendiente de Autorización)

### Conexión (cuando el propietario autorice):
1. Crear Service Account dedicada `tacopos-preview-reader` con **únicamente** `roles/datastore.viewer` sobre el proyecto de datos reales.
2. Desplegar `tools/preview_api/server.js` en entorno aislado con `PREVIEW_OWNER_EMAILS=<correo_del_propietario>` y la Service Account de solo lectura.
3. Compilar `flutter build web --release --target lib/main_backoffice.dart --dart-define=ENV=preview --dart-define=PREVIEW_API_URL=<url_segura>` y publicar en URL propuesta: **`https://tacopos-backoffice-preview.web.app`** (o sitio multi-site en `tacopos-backoffice-dev`).

### Revocación y desconexión inmediata:
- **Nivel 1 (instantáneo):** Remover el correo de `PREVIEW_OWNER_EMAILS` o desactivar `authUsers/{uid}.active = false` (el API valida `verifyIdToken(..., true)`).
- **Nivel 2 (infraestructura):** Revocar `roles/datastore.viewer` de la Service Account `tacopos-preview-reader` o detener el servicio Preview API.

---

## 7. Dictamen GO / NO-GO para Habilitar Preview con Datos Reales

- **Validación técnica en Emulator/DEV:** **APROBADA** (API de solo lectura probada con HTTP + Firestore Emulator; proyección anti-PIN verificada; bloqueos `EnvironmentGuard` y `BackofficeReadOnlyGuard` validados).
- **Dictamen para conexión a datos reales:** **CONDITIONAL GO (Listo para autorización del propietario)**. No se conecta todavía por restricción explícita de la Fase 9.1.1; en cuanto el propietario autorice la infraestructura de ejecución para el Preview API con `roles/datastore.viewer`, puede habilitarse sin modificar Android (+32), Backoffice 1.0 (`7159969`) ni las Firestore Rules productivas.
