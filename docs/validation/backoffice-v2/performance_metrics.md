# Métricas de Rendimiento y Lecturas Firestore — Fase 3

## 1. Estrategia de consultas y caché

| Operación | Backoffice 1.x | Backoffice 2.0 (Fase 3) | Impacto |
| --- | --- | --- | --- |
| **Apertura de Dashboard (frío)** | `3 + 4N` lecturas (con `N` órdenes) + streams vivos | `2` consultas acotadas por `businessDate` (periodo actual + comparativo) + lotes de 15 para `items`/`payments` solo de órdenes activas | Acotado a `maxOrdersPerQuery = 600` y sin listeners permanentes |
| **Reapertura / cambio de módulo (< 60s)** | Recarga futures / listeners | **0 lecturas** (`DashboardRepository` caché en memoria TTL 60s por `restaurantId\|branchId\|start\|end`) | Eliminación de lecturas duplicadas |
| **Listado de Ventas (navegación)** | Descarga histórica / `LocalPage` en memoria | Paginación por cursores en servidor (`limit(21)` + `startAfterDocument`) | **21 lecturas por página** sin importar la antigüedad del restaurante |
| **Búsqueda en Ventas** | Solo sobre página cargada o histórico completo | `searchOrdersInRange`: consulta acotada por `businessDate` + `limit(251)` | Búsqueda en periodo con límite estricto (`maxSearchLimit = 250`) |
| **Exportación CSV en Ventas** | Descarga en bloque único | `exportOrdersInRange`: paginación completa por cursores (`pageSize = 200`), progreso en vivo y cancelación cooperativa | Sin truncamiento silencioso ni picos de memoria |
| **Detalle de Venta** | Lectura individual | `1` doc de orden + `1` query `items` + `1` query `payments` bajo demanda | Carga mínima bajo demanda |
| **Caja y Arqueo (`CashRepository`)** | `_db.collectionGroup('payments').get()` global | Bloqueado en Rules; `loadCashDashboard` acotado por `restaurantId` + `branchId` + `businessDate` (`limit(100)` cortes, `limit(200)` retiros) | Aislamiento multi-tenant y lecturas acotadas |
| **Autorizaciones (`AuthorizationsRepository`)** | Listeners sin acotar | `loadAuthorizations` acotado por `businessDate` + `branchId` + `status` (`limit(150)` retiros, `limit(150)` descuentos) | Cero listeners permanentes |
| **Inventarios y Cocina (`InventoryRepository`)** | Listeners sobre colecciones completas | `loadInventory` acotado (`150` insumos, `60` sesiones, `100` agotados, `200` productos, `150` items de sesión seleccionada) | Carga bajo demanda por sesión |
| **Compras, Proveedores y CXP (`PurchasesRepository`)** | Streams vivos sobre colecciones completas | `loadDashboard` acotado por `businessDate` (`300` compras, `250` pagos, `200` CXP) + `fetchPurchasesPage` con cursores (`limit(21)`) + `exportAllPurchasesInRange` paginado | Sin descarga histórica completa para paginar; transacciones atómicas en pagos CXP |
| **Renovación de sesión (`SessionRenewalGuard`)** | `authStateChanges()` sin verificación de revocación | `idTokenChanges()` + `getIdToken(true)` protegido por `SessionRenewalGuard` (lock en vuelo + cooldown `60s`) | Sin bucles de renovación ni solicitudes redundantes |

## 2. Impacto del comparativo contra periodo anterior

El cálculo de crecimiento (`+9.9%`, `+14.3%`, `-3.8%`) ejecuta el periodo anterior en paralelo (`Future.wait`) únicamente en carga fría o al presionar **Actualizar** (`forceRefresh: true`). Durante los siguientes 60 segundos, la caché en memoria sirve ambas métricas con **0 lecturas**.
