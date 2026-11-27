# Matriz de Equivalencia Funcional — Backoffice Anterior vs. Backoffice 2.0

Inventario realizado exclusivamente mediante inspección de código fuente (`lib/screens/admin/`, `lib/core/`, `lib/services/`), sin acceso a producción.

---

## 1. Módulos principales

| Módulo Backoffice 1.x | Ubicación origen | Equivalente Backoffice 2.0 | Estado |
| --- | --- | --- | --- |
| **Dashboard** | `_DashboardSection` (`backoffice_screen.dart`) | `DashboardPage` + `DashboardRepository` | **Implementado (Fase 3)** |
| **Ventas** | `_SalesSection` (`backoffice_screen.dart`) | `SalesListPage` + `SaleDetailPage` + `SalesRepository` | **Implementado (Fase 3)** |
| **Caja** | `CashAdminScreen` | `CashRepository` + módulo Caja | **Planificado (Fase 4)** |
| **Autorizaciones** | `AuthorizationAdminScreen` | Submódulo Autorizaciones en Caja/Descuentos | **Planificado (Fase 4)** |
| **Control de cocina / Inventarios** | `KitchenAdminScreen`, `RecipeYieldConfigScreen` | Módulo Inventarios | **Planificado (Fase 4)** |
| **Compras / CXP / Proveedores** | `PurchaseAdminScreen` (8 pestañas) | Módulo Compras | **Planificado (Fase 5)** |
| **Finanzas / Socios** | `FinanceAdminScreen`, `FinanceMainDashboardScreen`, `WeeklyFinanceComparisonView` | Módulo Finanzas | **Planificado (Fase 5)** |
| **Reportes (25 variantes)** | `_ReportsSection` (`_ReportKind`) | Módulo Reportes | **Planificado (Fase 5)** |
| **Visor operativo** | `LiveOperationsScreen` | Integrado en Dashboard / Auditoría | **Planificado (Fase 5)** |
| **Configuración y Catálogos** | `BranchCatalogScreen`, `EmployeeCatalogScreen`, `ProductCatalogScreen`, `ProductCategoryCatalogScreen`, `TableCatalogScreen`, `OrderPlatformCatalogScreen`, `DiscountAdminScreen`, `ExpensePolicyAdminScreen`, `DeviceVersionsScreen`, `OperationResetScreen` | Módulos Empleados, Auditoría y Configuración | **Planificado (Fase 6)** |

---

## 2. Submódulos, indicadores y reglas consolidados en Dashboard y Ventas (Fase 3)

| Capacidad | Backoffice 1.x | Backoffice 2.0 (Fase 3) |
| --- | --- | --- |
| **Ventas netas / brutas / conciliación** | `CanonicalSalesSummary` | `CanonicalSalesSummary` vía `BackofficeSalesAdapter` (idéntico) |
| **Separación monetario vs consumo interno** | Mezclado en resumen textual | Gráfica de dona exclusivamente monetaria (`monetaryCollected`) + tarjeta separada de consumo interno no monetario |
| **Comparativo vs periodo anterior** | No incluido en Dashboard | Cálculo real de periodo equivalente anterior (`netSalesDeltaPct`, `ordersDeltaPct`, `avgTicketDeltaPct`) |
| **Comparativo multi-sucursal** | Selector único de sucursal | Selector `"Todas las sucursales"` + comparativo visual por sucursal |
| **Ventas por canal / producto / empleado** | Reportes separados (`platform`, `products`, `employee`) | Integrados en Dashboard (`ChannelBreakdown`, `productRows`, `employeeBreakdown`) |
| **Propinas y comisiones absorbidas** | En detalle de pago/corte | Sumarizados en Dashboard y mostrados en Detalle de Venta |
| **Búsqueda de ventas** | En memoria tras descarga | Paginación por cursores (`20`/pág) sin búsqueda + búsqueda acotada sobre todo el periodo (`fetchOrdersInRange`) |
| **Exportación CSV** | `exportCsvFile` | Exportación CSV completa en Dashboard y Ventas (independiente de la página visible) |
| **Cancelación de ventas/pagos** | `backoffice_sales_cancellation.dart` | Permisos evaluados en `BackofficePermissions`; acción de escritura diferida tras validación con Codex |

---

## 3. Inventario de los 25 Reportes pendientes para Fase 5 (`_ReportKind`)

1. Ventas: `products`, `hourly`, `hourlyYesterdayLastSales`, `hourlyPreviousWeek`, `dates`, `platform`, `paymentMethod`, `employee`, `discountsByDay`, `visitClassification`, `saleFolios`.
2. Auditorías: `salesDiscrepancyAudit`, `rapidCardSalesAudit`, `cancellationShortageAudit`, `predictiveConsumptionAudit`.
3. Caja: `cashHistory`, `withdrawals`, `cashSchedule`.
4. Cocina y costos: `kitchenWaste`, `kitchenInventory`, `kitchenYield`, `productStockOuts`, `yieldProfit`.
5. Cancelaciones: `cancellations`, `cancelledPayments`.
