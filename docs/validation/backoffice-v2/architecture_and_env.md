# Arquitectura, Ambientes y Seguridad — TacoPOS Backoffice 2.0

## 1. Arquitectura modular (`lib/main_backoffice.dart` + `lib/backoffice_v2/`)

- **Entrypoint exclusivo:** `lib/main_backoffice.dart` (no arrastra pantallas operativas Android).
- **Módulos:**
  - `core/env/`: `BackofficeEnv` (`local`, `dev`, `prod`), `BackofficeConfig`, `EnvironmentGuard`, `BackofficeDevFirebaseOptions`.
  - `core/design/`: `BackofficeTokens` (Light & Dark) y `BackofficeTheme` (estilo SaaS Stripe/Linear/Vercel).
  - `core/adapters/`: `BackofficeSalesAdapter` que reutiliza `CanonicalSalesSummary` y `resolveOperationalBusinessDate` sin duplicar fórmulas financieras.
  - `auth/`: `BackofficeSession` (multi-tenant + selector multi-sucursal "Todas las sucursales") y `BackofficeV2AuthService` (PIN via Functions + Email/Password DEV contra `restaurants/{r}/authUsers/{uid}`).
  - `navigation/`: Router declarativo con URLs (`/login`, `/dashboard`, `/sales`, `/sales/:id`, etc.) y `BackofficeAppShell` colapsable y responsivo.
  - `features/`: `dashboard`, `sales` (paginación real por cursores `limit` + `startAfterDocument`), `cash` (diseño acotado sin `collectionGroup` global) y `placeholders` honestos para Fase 3-5.

## 2. Separación de ambientes y protecciones

| Ambiente | `ENV` | Project ID | Estado en Fase 2 |
| --- | --- | --- | --- |
| **LOCAL** | `local` | `demo-tacopos-backoffice-v2` | Activo en Firebase Emulator Suite (`9199`, `8180`, `5101`, `5050`, `4100`) |
| **DEV** | `dev` | `tacopos-backoffice-dev` | Activo en `https://tacopos-backoffice-dev.web.app` (plan Spark, sin Blaze) |
| **PROD** | `prod` | `tacopos-renovadev` | **Bloqueado** (`PROD_BLOCKED`, sin fallback automático) |

`EnvironmentGuard.resolveAndValidate` bloquea el arranque con `IsolationBlockedApp` si:
- Falta `ENV` (`MISSING_ENV`) o es desconocido (`UNKNOWN_ENV`).
- `ENV=prod` (`PROD_BLOCKED`) o el `projectId` es productivo (`FORBIDDEN_PROD_PROJECT`).
- Se detectan endpoints productivos (`FORBIDDEN_ENDPOINT`).
- `LOCAL` intenta usar un host de emulador distinto a `localhost` / `127.0.0.1` (`UNAUTHORIZED_EMULATOR_HOST`) o un `projectId` sin prefijo `demo-` (`INVALID_LOCAL_PROJECT`).

## 3. Resolución del hallazgo `getCashDifferenceAudit`

- En la nueva arquitectura (`CashRepository` y `firestore.backoffice-v2.rules`):
  1. Se prohíbe `collectionGroup('payments').get()` sin filtro en reglas (`allow read, write: if false` fuera de rutas explícitas).
  2. `CashRepository.fetchScopedPaymentsForSession` consulta únicamente órdenes de `restaurants/{restaurantId}` filtradas por `branchId` y `businessDate`, leyendo subcolecciones `payments` en lotes acotados.
  3. Las reglas `firestore.backoffice-v2.rules` exigen autenticación no anónima, membresía activa en `restaurants/{r}/authUsers/{uid}`, permiso `canViewAdmin` y pertenencia a `branchAccess`.
