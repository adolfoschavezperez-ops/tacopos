# Auditoría Fase 1 — TacoPOS Backoffice 2.0

Respaldo en repositorio de la auditoría realizada sobre la rama `audit/backoffice-antigravity` antes de iniciar Fase 2.

## Hallazgos clave

1. **Acoplamiento Android + Web:** `lib/main.dart` y `LoginGate` bifurcan Web/Android con `kIsWeb`, pero el Backoffice Web compartía `TacoPosRepository` (`16,437` líneas) y `BackofficeScreen` (`8,806` líneas).
2. **Riesgo crítico multi-tenant en `getCashDifferenceAudit`:** `lib/services/taco_pos_repository.dart:5174-5181` ejecuta `_db.collectionGroup('payments').get()` sin filtro de `restaurantId`, `branchId` ni fecha, además de leer colecciones completas de órdenes, sesiones de caja y retiros.
3. **Paginación en memoria (`LocalPage`):** `lib/core/backoffice/local_pagination.dart` pagina en memoria sobre resultados completos descargados.
4. **Contratos protegidos (Android 2.0.1 / Codex):** Se mantienen intactos `lib/models/*`, `CanonicalSalesSummary`, `operational_business_date.dart`, `firestore.rules`, `firestore.indexes.json` y `functions/src/index.ts`.
