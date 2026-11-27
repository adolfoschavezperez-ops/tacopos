# Métricas de Rendimiento y Lecturas Firestore — Fase 3

## 1. Estrategia de consultas y caché

| Operación | Backoffice 1.x | Backoffice 2.0 (Fase 3) | Impacto |
| --- | --- | --- | --- |
| **Apertura de Dashboard (frío)** | `3 + 4N` lecturas (con `N` órdenes) + streams vivos | `2` consultas acotadas por `businessDate` (periodo actual + comparativo) + lotes de 15 para `items`/`payments` solo de órdenes activas | Acotado a `maxOrdersPerQuery = 600` y sin listeners permanentes |
| **Reapertura / cambio de módulo (< 60s)** | Recarga futures / listeners | **0 lecturas** (`DashboardRepository` caché en memoria TTL 60s por `restaurantId\|branchId\|start\|end`) | Eliminación de lecturas duplicadas |
| **Listado de Ventas (navegación)** | Descarga histórica / `LocalPage` en memoria | Paginación por cursores en servidor (`limit(21)` + `startAfterDocument`) | **21 lecturas por página** sin importar la antigüedad del restaurante |
| **Búsqueda en Ventas** | Solo sobre página cargada o histórico completo | Consulta acotada al rango de fechas (`fetchOrdersInRange`, máximo `600` docs) | Búsqueda sobre todo el periodo sin descargar toda la colección |
| **Detalle de Venta** | Lectura individual | `1` doc de orden + `1` query `items` + `1` query `payments` bajo demanda | Carga mínima bajo demanda |
| **Auditoría de caja (`CashRepository`)** | `_db.collectionGroup('payments').get()` global | Bloqueado en `firestore.backoffice-v2.rules`; consultas acotadas por `restaurantId` + `branchId` + `businessDate` | Aislamiento multi-tenant garantizado |

## 2. Impacto del comparativo contra periodo anterior

El cálculo de crecimiento (`+9.9%`, `+14.3%`, `-3.8%`) ejecuta el periodo anterior en paralelo (`Future.wait`) únicamente en carga fría o al presionar **Actualizar** (`forceRefresh: true`). Durante los siguientes 60 segundos, la caché en memoria sirve ambas métricas con **0 lecturas**.
