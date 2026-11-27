import '../../../models/employee.dart';
import '../../auth/backoffice_permissions.dart';

enum ReportCategory {
  all('Todos'),
  sales('Ventas'),
  cash('Caja'),
  payments('Pagos'),
  purchases('Compras'),
  suppliers('Proveedores'),
  inventory('Inventarios'),
  kitchen('Cocina'),
  profitability('Rentabilidad'),
  finance('Finanzas'),
  employees('Empleados'),
  audit('Auditoría');

  const ReportCategory(this.label);
  final String label;
}

enum BackofficeReportKind {
  products,
  hourly,
  hourlyYesterdayLastSales,
  hourlyPreviousWeek,
  dates,
  kitchenWaste,
  kitchenInventory,
  platform,
  paymentMethod,
  employee,
  cashHistory,
  withdrawals,
  kitchenYield,
  cancellations,
  cancelledPayments,
  productStockOuts,
  saleFolios,
  salesDiscrepancyAudit,
  rapidCardSalesAudit,
  cancellationShortageAudit,
  predictiveConsumptionAudit,
  discountsByDay,
  visitClassification,
  cashSchedule,
  yieldProfit,
}

enum ReportPermissionGroup {
  general,
  cashSchedule,
  adminAudit,
  kitchen,
  yieldProfit,
}

class ReportDescriptor {
  const ReportDescriptor({
    required this.kind,
    required this.title,
    required this.description,
    required this.category,
    required this.legacyLocation,
    required this.permissionGroup,
    this.supportsExcel = false,
  });

  final BackofficeReportKind kind;
  final String title;
  final String description;
  final ReportCategory category;
  final String legacyLocation;
  final ReportPermissionGroup permissionGroup;
  final bool supportsExcel;

  bool isAllowed(BackofficePermissions perms) {
    if (!perms.isAuthenticated) return false;
    if (perms.isSuperAdmin) return true;
    final Employee e = perms.employee!;
    final hasAdmin = e.canViewAdmin;
    return switch (permissionGroup) {
      ReportPermissionGroup.general => hasAdmin || e.canViewKitchenReports,
      ReportPermissionGroup.cashSchedule => hasAdmin || e.canManageCash,
      ReportPermissionGroup.adminAudit => hasAdmin,
      ReportPermissionGroup.kitchen => hasAdmin || e.canViewKitchenReports,
      ReportPermissionGroup.yieldProfit => hasAdmin,
    };
  }
}

const List<ReportDescriptor> backoffice25ReportsCatalog = [
  ReportDescriptor(
    kind: BackofficeReportKind.products,
    title: 'Ventas por artículo',
    description:
        'Desglose por producto: unidades vendidas, venta bruta, descuento asignado, venta neta, costo y utilidad.',
    category: ReportCategory.sales,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.products)',
    permissionGroup: ReportPermissionGroup.general,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.dates,
    title: 'Ventas por fecha',
    description:
        'Resumen diario con venta bruta, descuentos, venta neta, cobro real, diferencia de reconciliación y métodos de pago.',
    category: ReportCategory.sales,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.dates)',
    permissionGroup: ReportPermissionGroup.general,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.hourly,
    title: 'Ventas por hora',
    description: 'Distribución horaria de ingresos cobrados en el periodo.',
    category: ReportCategory.sales,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.hourly)',
    permissionGroup: ReportPermissionGroup.general,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.hourlyYesterdayLastSales,
    title: 'Día seleccionado vs último día con ventas',
    description:
        'Comparativo horario contra el día operativo previo con ventas registradas.',
    category: ReportCategory.sales,
    legacyLocation:
        'backoffice_screen.dart (_ReportKind.hourlyYesterdayLastSales)',
    permissionGroup: ReportPermissionGroup.general,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.hourlyPreviousWeek,
    title: 'Comparación contra semana anterior',
    description:
        'Comparativo horario frente al mismo día de la semana pasada.',
    category: ReportCategory.sales,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.hourlyPreviousWeek)',
    permissionGroup: ReportPermissionGroup.general,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.platform,
    title: 'Ventas por plataforma',
    description:
        'Venta neta y ticket promedio agrupados por canal (en persona vs plataformas).',
    category: ReportCategory.sales,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.platform)',
    permissionGroup: ReportPermissionGroup.general,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.visitClassification,
    title: 'Visitas nuevas y recurrentes',
    description:
        'Clasificación semanal de clientes nuevos, recurrentes y sin clasificar.',
    category: ReportCategory.sales,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.visitClassification)',
    permissionGroup: ReportPermissionGroup.general,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.paymentMethod,
    title: 'Ventas por método de pago',
    description:
        'Cobrado real, recargos, comisiones bancarias absorbidas, neto estimado y descuentos.',
    category: ReportCategory.payments,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.paymentMethod)',
    permissionGroup: ReportPermissionGroup.general,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.cancelledPayments,
    title: 'Pagos cancelados',
    description:
        'Auditoría de pagos anulados con método, base, cobrado, motivo y responsable.',
    category: ReportCategory.payments,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.cancelledPayments)',
    permissionGroup: ReportPermissionGroup.general,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.cashHistory,
    title: 'Corte de caja histórico',
    description:
        'Cortes cerrados y abiertos con esperado, contado, terminal, faltante, sobrante y retiros.',
    category: ReportCategory.cash,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.cashHistory)',
    permissionGroup: ReportPermissionGroup.general,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.cashSchedule,
    title: 'Horarios de apertura y cierre',
    description:
        'Seguimiento semanal de puntualidad y duración de turnos de caja.',
    category: ReportCategory.cash,
    legacyLocation: 'cash_schedule_report_view.dart (_ReportKind.cashSchedule)',
    permissionGroup: ReportPermissionGroup.cashSchedule,
    supportsExcel: true,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.withdrawals,
    title: 'Gastos / retiros',
    description:
        'Solicitudes de retiro y gastos operativos con solicitante, autorizador y estado.',
    category: ReportCategory.finance,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.withdrawals)',
    permissionGroup: ReportPermissionGroup.general,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.employee,
    title: 'Ventas por empleado',
    description:
        'Órdenes cobradas, venta neta y ticket promedio por cajero/operador.',
    category: ReportCategory.employees,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.employee)',
    permissionGroup: ReportPermissionGroup.general,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.discountsByDay,
    title: 'Descuentos por día',
    description:
        'Descuentos y comidas gratuitas de empleados con beneficiario, categoría y autorizador.',
    category: ReportCategory.audit,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.discountsByDay)',
    permissionGroup: ReportPermissionGroup.general,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.cancellations,
    title: 'Cancelaciones de tickets',
    description:
        'Órdenes y partidas canceladas o rechazadas, motivo, paso por cocina y hora.',
    category: ReportCategory.audit,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.cancellations)',
    permissionGroup: ReportPermissionGroup.general,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.saleFolios,
    title: 'Folios de venta',
    description:
        'Secuencia diaria de folios emitidos, pagados, anulados y saltos de folio.',
    category: ReportCategory.audit,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.saleFolios)',
    permissionGroup: ReportPermissionGroup.adminAudit,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.salesDiscrepancyAudit,
    title: 'Auditoría de discrepancias de ventas',
    description:
        'Órdenes donde partidas, total, cobrado o pendiente presentan diferencias (solo lectura).',
    category: ReportCategory.audit,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.salesDiscrepancyAudit)',
    permissionGroup: ReportPermissionGroup.general,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.rapidCardSalesAudit,
    title: 'Auditoría de cobros rápidos con tarjeta',
    description:
        'Pagos con tarjeta completados en ventanas cortas con cocina lista antes del cobro.',
    category: ReportCategory.audit,
    legacyLocation:
        'rapid_card_sales_audit_view.dart (_ReportKind.rapidCardSalesAudit)',
    permissionGroup: ReportPermissionGroup.adminAudit,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.cancellationShortageAudit,
    title: 'Cancelaciones vs faltantes de caja',
    description:
        'Cruce de cancelaciones (especialmente órdenes enviadas a cocina sin pago) vs faltantes diarios.',
    category: ReportCategory.audit,
    legacyLocation:
        'cancellation_shortage_audit_view.dart (_ReportKind.cancellationShortageAudit)',
    permissionGroup: ReportPermissionGroup.adminAudit,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.predictiveConsumptionAudit,
    title: 'Inteligencia de consumo',
    description:
        'Auditoría integral de compras, ventas, cancelaciones y cierres de cocina por insumo.',
    category: ReportCategory.inventory,
    legacyLocation:
        'predictive_consumption_audit_view.dart (_ReportKind.predictiveConsumptionAudit)',
    permissionGroup: ReportPermissionGroup.adminAudit,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.kitchenWaste,
    title: 'Mermas por insumo',
    description:
        'Cantidades mermadas por insumo de cocina, fecha, usuario de cierre y notas.',
    category: ReportCategory.kitchen,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.kitchenWaste)',
    permissionGroup: ReportPermissionGroup.kitchen,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.kitchenInventory,
    title: 'Entradas y salidas de insumos',
    description:
        'Balance completo de cocina: sobrante anterior, entradas, disponible, sobrante final, merma y consumo.',
    category: ReportCategory.kitchen,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.kitchenInventory)',
    permissionGroup: ReportPermissionGroup.kitchen,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.kitchenYield,
    title: 'Rendimiento de cocina',
    description:
        'Comparativo de rendimiento óptimo vs actual y promedio por insumo.',
    category: ReportCategory.kitchen,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.kitchenYield)',
    permissionGroup: ReportPermissionGroup.kitchen,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.productStockOuts,
    title: 'Productos agotados',
    description:
        'Historial de productos marcados como agotados y restablecidos por sucursal.',
    category: ReportCategory.inventory,
    legacyLocation: 'backoffice_screen.dart (_ReportKind.productStockOuts)',
    permissionGroup: ReportPermissionGroup.kitchen,
  ),
  ReportDescriptor(
    kind: BackofficeReportKind.yieldProfit,
    title: 'Rendimiento y utilidad',
    description:
        'Costo teórico de ingredientes, cobertura de recetas, utilidad bruta estimada y exportación Excel.',
    category: ReportCategory.profitability,
    legacyLocation: 'yield_profit_report_view.dart (_ReportKind.yieldProfit)',
    permissionGroup: ReportPermissionGroup.yieldProfit,
    supportsExcel: true,
  ),
];

class ExportCancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Builds a properly escaped RFC-4180 CSV string in async chunks so exports of
/// 1,000 to 10,000+ rows report progress and support cooperative cancellation.
Future<String?> buildChunkedCsv({
  required List<String> headers,
  required List<List<String>> rows,
  List<String>? totalsRow,
  ExportCancellationToken? cancellationToken,
  void Function(double progress)? onProgress,
  int chunkSize = 1000,
}) async {
  String escapeCell(String raw) {
    if (raw.contains(',') ||
        raw.contains('"') ||
        raw.contains('\n') ||
        raw.contains('\r')) {
      return '"${raw.replaceAll('"', '""')}"';
    }
    return raw;
  }

  final buf = StringBuffer()
    ..writeln(headers.map(escapeCell).join(','));

  final total = rows.length;
  for (var i = 0; i < total; i += chunkSize) {
    if (cancellationToken?.isCancelled ?? false) return null;
    final end = (i + chunkSize).clamp(0, total);
    for (var j = i; j < end; j++) {
      buf.writeln(rows[j].map(escapeCell).join(','));
    }
    onProgress?.call(total == 0 ? 1.0 : end / total);
    await Future<void>.delayed(Duration.zero);
  }

  if (totalsRow != null && totalsRow.isNotEmpty) {
    buf.writeln(totalsRow.map(escapeCell).join(','));
  }
  onProgress?.call(1.0);
  return buf.toString();
}
