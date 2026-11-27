import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/reports/cancellation_shortage_audit.dart';
import '../../../core/reports/canonical_sales_summary.dart';
import '../../../core/reports/discounts_by_day_report.dart';
import '../../../core/reports/product_sales_cost_report.dart';
import '../../../core/reports/rapid_card_sales_audit.dart';
import '../../../core/reports/visit_classification_report.dart';
import '../../../models/cash_session.dart';
import '../../../models/cash_withdrawal_request.dart';
import '../../../models/kitchen_session.dart';
import '../../../models/kitchen_stock_item.dart';
import '../../../models/order.dart';
import '../../../models/order_item.dart';
import '../../../models/payment.dart';
import '../../../models/product.dart';
import '../../../models/purchase_models.dart';
import '../../../models/yield_profit_models.dart';
import '../../../services/taco_pos_repository.dart' show ProductStockOutRow;
import '../../core/adapters/sales_adapter.dart';
import '../finance/finance_analytics.dart';
import 'reports_catalog.dart';

class ReportKpi {
  const ReportKpi({required this.label, required this.value});

  final String label;
  final String value;
}

class ReportTableResult {
  const ReportTableResult({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.kpis,
    required this.headers,
    required this.rows,
    this.totalsRow,
    this.rowOrderIds = const [],
    this.partialWarning,
    required this.readCount,
  });

  final BackofficeReportKind kind;
  final String title;
  final String subtitle;
  final List<ReportKpi> kpis;
  final List<String> headers;
  final List<List<String>> rows;
  final List<String>? totalsRow;
  final List<String?> rowOrderIds;
  final String? partialWarning;
  final int readCount;
}

class ReportsRepository {
  ReportsRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final Map<String, _CachedOrderBundle> _orderCache = {};

  void invalidateCache() => _orderCache.clear();

  Future<ReportTableResult> runReport({
    required BackofficeReportKind kind,
    required String restaurantId,
    required DateTime startDate,
    required DateTime endDate,
    String? branchId,
    bool forceRefresh = false,
  }) async {
    final startStr = BackofficeSalesAdapter.formatBusinessDate(startDate);
    final endStr = BackofficeSalesAdapter.formatBusinessDate(endDate);
    final restRef = _db.collection('restaurants').doc(restaurantId);

    switch (kind) {
      case BackofficeReportKind.cashHistory:
        return _runCashHistory(
          restRef: restRef,
          startStr: startStr,
          endStr: endStr,
          branchId: branchId,
        );
      case BackofficeReportKind.cashSchedule:
        return _runCashSchedule(
          restRef: restRef,
          startStr: startStr,
          endStr: endStr,
          branchId: branchId,
        );
      case BackofficeReportKind.withdrawals:
        return _runWithdrawals(
          restRef: restRef,
          startStr: startStr,
          endStr: endStr,
          branchId: branchId,
        );
      case BackofficeReportKind.kitchenWaste:
      case BackofficeReportKind.kitchenInventory:
      case BackofficeReportKind.kitchenYield:
        return _runKitchenReports(
          kind: kind,
          restRef: restRef,
          startStr: startStr,
          endStr: endStr,
          branchId: branchId,
        );
      case BackofficeReportKind.productStockOuts:
        return _runProductStockOuts(
          restRef: restRef,
          startStr: startStr,
          endStr: endStr,
          branchId: branchId,
        );
      case BackofficeReportKind.predictiveConsumptionAudit:
        return _runPredictiveConsumption(
          restRef: restRef,
          startStr: startStr,
          endStr: endStr,
          branchId: branchId,
        );
      case BackofficeReportKind.yieldProfit:
        return _runYieldProfit(
          restRef: restRef,
          startStr: startStr,
          endStr: endStr,
          branchId: branchId,
          forceRefresh: forceRefresh,
        );
      default:
        return _runOrderBasedReport(
          kind: kind,
          restRef: restRef,
          restaurantId: restaurantId,
          startStr: startStr,
          endStr: endStr,
          branchId: branchId,
          forceRefresh: forceRefresh,
        );
    }
  }

  Future<_CachedOrderBundle> _loadOrderBundle({
    required DocumentReference<Map<String, dynamic>> restRef,
    required String restaurantId,
    required String startStr,
    required String endStr,
    String? branchId,
    required bool includeItems,
    bool forceRefresh = false,
  }) async {
    final key = '$restaurantId|$startStr|$endStr|${branchId ?? 'all'}';
    final cached = _orderCache[key];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.cachedAt) <
            const Duration(seconds: 60) &&
        (!includeItems || cached.hasItems)) {
      return cached;
    }

    const orderLimit = 3000;
    const pageSize = 500;
    final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? lastDoc;
    var hitLimit = false;
    final baseQuery = restRef
        .collection('orders')
        .where('businessDate', isGreaterThanOrEqualTo: startStr)
        .where('businessDate', isLessThanOrEqualTo: endStr)
        .orderBy('businessDate', descending: true);

    while (allDocs.length < orderLimit) {
      var q = baseQuery.limit(pageSize);
      if (lastDoc != null) q = q.startAfterDocument(lastDoc);
      final snap = await q.get();
      if (snap.docs.isEmpty) break;
      allDocs.addAll(snap.docs);
      lastDoc = snap.docs.last;
      if (snap.docs.length < pageSize) break;
      if (allDocs.length >= orderLimit) {
        hitLimit = true;
        break;
      }
    }

    final orders = allDocs
        .map(PosOrder.fromDoc)
        .where(
          (o) => branchId == null || branchId.isEmpty || o.branchId == branchId,
        )
        .toList(growable: false);

    final itemsByOrder = <String, List<OrderItem>>{};
    final paymentsByOrder = <String, List<Payment>>{};
    var readCount = allDocs.length;

    for (var i = 0; i < orders.length; i += 50) {
      final chunk = orders.sublist(i, (i + 50).clamp(0, orders.length));
      final paymentFutures = chunk.map(
        (o) => restRef.collection('orders').doc(o.id).collection('payments').get(),
      );
      final itemFutures = includeItems
          ? chunk.map(
              (o) =>
                  restRef.collection('orders').doc(o.id).collection('items').get(),
            )
          : const <Future<QuerySnapshot<Map<String, dynamic>>>>[];

      final paySnaps = await Future.wait(paymentFutures);
      final itemSnaps = includeItems
          ? await Future.wait(itemFutures)
          : const <QuerySnapshot<Map<String, dynamic>>>[];

      for (var j = 0; j < chunk.length; j++) {
        final pList = paySnaps[j].docs.map(Payment.fromDoc).toList(growable: false);
        paymentsByOrder[chunk[j].id] = pList;
        readCount += pList.length;
        if (includeItems) {
          final iList =
              itemSnaps[j].docs.map(OrderItem.fromDoc).toList(growable: false);
          itemsByOrder[chunk[j].id] = iList;
          readCount += iList.length;
        }
      }
    }

    final bundle = _CachedOrderBundle(
      orders: orders,
      itemsByOrder: itemsByOrder,
      paymentsByOrder: paymentsByOrder,
      hasItems: includeItems,
      hitLimit: hitLimit,
      readCount: readCount,
      cachedAt: DateTime.now(),
    );
    _orderCache[key] = bundle;
    return bundle;
  }

  Future<ReportTableResult> _runOrderBasedReport({
    required BackofficeReportKind kind,
    required DocumentReference<Map<String, dynamic>> restRef,
    required String restaurantId,
    required String startStr,
    required String endStr,
    String? branchId,
    bool forceRefresh = false,
  }) async {
    final needsItems =
        kind != BackofficeReportKind.hourly &&
        kind != BackofficeReportKind.hourlyYesterdayLastSales &&
        kind != BackofficeReportKind.hourlyPreviousWeek &&
        kind != BackofficeReportKind.visitClassification &&
        kind != BackofficeReportKind.cancelledPayments;

    final bundle = await _loadOrderBundle(
      restRef: restRef,
      restaurantId: restaurantId,
      startStr: startStr,
      endStr: endStr,
      branchId: branchId,
      includeItems: needsItems,
      forceRefresh: forceRefresh,
    );

    final partialWarn = bundle.hitLimit
        ? 'El periodo supera 3,000 órdenes; se muestran resultados parciales. Acota las fechas para obtener el universo completo.'
        : null;

    final orders = bundle.orders;
    final itemsByOrder = bundle.itemsByOrder;
    final paymentsByOrder = bundle.paymentsByOrder;
    final canonical = BackofficeSalesAdapter.buildCanonicalSummary(
      orders: orders,
      itemsByOrder: itemsByOrder,
      paymentsByOrder: paymentsByOrder,
    );

    final activePayments = paymentsByOrder.values
        .expand((l) => l)
        .where((p) => isCanonicalActivePayment(p) && canonicalPaymentAppliedAmount(p) > 0)
        .toList(growable: false);

    switch (kind) {
      case BackofficeReportKind.products:
        final prodSnap = await restRef.collection('products').limit(300).get();
        final products = prodSnap.docs.map(Product.fromDoc).toList(growable: false);
        final rows = buildProductSalesCostRows(
          salesRows: canonical.productRows,
          products: products,
        );
        final cells = rows
            .map((r) => r.toReportCells(totalNetSales: canonical.netSales))
            .toList(growable: false);
        final totals = rows.isNotEmpty
            ? buildProductSalesCostTotalsCells(rows)
            : null;
        return ReportTableResult(
          kind: kind,
          title: 'Ventas por artículo',
          subtitle: '$startStr al $endStr · ${rows.length} productos',
          kpis: [
            ReportKpi(
              label: 'Venta neta',
              value: BackofficeSalesAdapter.formatMoney(canonical.netSales),
            ),
            ReportKpi(
              label: 'Descuentos',
              value: BackofficeSalesAdapter.formatMoney(canonical.discountTotal),
            ),
            ReportKpi(
              label: 'Artículos',
              value: '${rows.length}',
            ),
          ],
          headers: productSalesCostReportHeaders,
          rows: cells,
          totalsRow: totals,
          partialWarning: partialWarn,
          readCount: bundle.readCount + prodSnap.docs.length,
        );

      case BackofficeReportKind.hourly:
      case BackofficeReportKind.hourlyYesterdayLastSales:
      case BackofficeReportKind.hourlyPreviousWeek:
        final byHour = <int, double>{};
        final ordersByHour = <int, Set<String>>{};
        for (final p in activePayments) {
          final h = p.createdAt?.hour ?? 0;
          byHour[h] = (byHour[h] ?? 0.0) + canonicalPaymentAppliedAmount(p);
          ordersByHour.putIfAbsent(h, () => {}).add(p.orderId);
        }
        final hours = byHour.keys.toList()..sort();
        final rows = hours.map((h) {
          final total = byHour[h] ?? 0.0;
          final cnt = ordersByHour[h]?.length ?? 0;
          final avg = cnt > 0 ? total / cnt : 0.0;
          return [
            '${h.toString().padLeft(2, '0')}:00',
            '$cnt',
            '—',
            BackofficeSalesAdapter.formatMoney(total),
            BackofficeSalesAdapter.formatMoney(avg),
            '—',
          ];
        }).toList(growable: false);
        final totalCollected = activePayments.fold<double>(
          0.0,
          (a, p) => a + canonicalPaymentAppliedAmount(p),
        );
        return ReportTableResult(
          kind: kind,
          title: backoffice25ReportsCatalog
              .firstWhere((r) => r.kind == kind)
              .title,
          subtitle: '$startStr al $endStr',
          kpis: [
            ReportKpi(
              label: 'Cobrado en rango',
              value: BackofficeSalesAdapter.formatMoney(totalCollected),
            ),
            ReportKpi(label: 'Horas activas', value: '${hours.length}'),
          ],
          headers: const [
            'Hora',
            'Órdenes',
            'Productos',
            'Venta total',
            'Ticket promedio',
            'Método predominante',
          ],
          rows: rows,
          partialWarning: partialWarn,
          readCount: bundle.readCount,
        );

      case BackofficeReportKind.dates:
        final byDate = <String, _DateBucket>{};
        for (final r in canonical.orderRows) {
          final b = byDate.putIfAbsent(r.businessDate, _DateBucket.new);
          b.gross += r.grossSales;
          b.discounts += r.discountTotal;
          b.net += r.netSales;
          b.collected += r.totalCollected;
          b.orders += 1;
        }
        for (final p in activePayments) {
          final d = (p.businessDate ?? '').trim();
          final b = byDate.putIfAbsent(d, _DateBucket.new);
          final amt = canonicalPaymentAppliedAmount(p);
          switch (p.method.trim().toLowerCase()) {
            case 'cash':
              b.cash += amt;
            case 'card':
              b.card += amt;
            case 'platform_paid':
              b.platform += amt;
            case 'employee_consumption':
              b.employee += amt;
          }
        }
        final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
        final rows = dates.map((d) {
          final b = byDate[d]!;
          final avg = b.orders > 0 ? b.net / b.orders : 0.0;
          final diff = b.collected - b.net;
          return [
            d,
            BackofficeSalesAdapter.formatMoney(b.gross),
            BackofficeSalesAdapter.formatMoney(b.discounts),
            BackofficeSalesAdapter.formatMoney(b.net),
            BackofficeSalesAdapter.formatMoney(b.collected),
            BackofficeSalesAdapter.formatMoney(diff),
            '${b.orders}',
            BackofficeSalesAdapter.formatMoney(avg),
            BackofficeSalesAdapter.formatMoney(b.cash),
            BackofficeSalesAdapter.formatMoney(b.card),
            BackofficeSalesAdapter.formatMoney(b.platform),
            BackofficeSalesAdapter.formatMoney(b.employee),
          ];
        }).toList(growable: false);
        return ReportTableResult(
          kind: kind,
          title: 'Ventas por fecha',
          subtitle: '$startStr al $endStr · ${dates.length} días',
          kpis: [
            ReportKpi(
              label: 'Venta neta',
              value: BackofficeSalesAdapter.formatMoney(canonical.netSales),
            ),
            ReportKpi(
              label: 'Cobrado real',
              value: BackofficeSalesAdapter.formatMoney(canonical.totalCollected),
            ),
            ReportKpi(
              label: 'Órdenes pagadas',
              value: '${canonical.paidOrdersCount}',
            ),
          ],
          headers: const [
            'Día',
            'Venta bruta',
            'Descuentos',
            'Venta neta',
            'Cobrado real',
            'Dif. reconciliación',
            'Órdenes',
            'Ticket prom.',
            'Efectivo',
            'Tarjeta',
            'Plataforma',
            'Consumo empl.',
          ],
          rows: rows,
          partialWarning: partialWarn,
          readCount: bundle.readCount,
        );

      case BackofficeReportKind.platform:
        final byPlat = <String, _SimpleAgg>{};
        for (final r in canonical.orderRows) {
          final key = (r.order.platformName ?? '').trim().isNotEmpty
              ? r.order.platformName!.trim()
              : 'En persona';
          final agg = byPlat.putIfAbsent(key, _SimpleAgg.new);
          agg.net += r.netSales;
          agg.count += 1;
        }
        final rows = byPlat.entries.map((e) {
          final avg = e.value.count > 0 ? e.value.net / e.value.count : 0.0;
          return [
            e.key,
            BackofficeSalesAdapter.formatMoney(e.value.net),
            BackofficeSalesAdapter.formatMoney(avg),
            '${e.value.count} órd.',
          ];
        }).toList(growable: false);
        return ReportTableResult(
          kind: kind,
          title: 'Ventas por plataforma',
          subtitle: '$startStr al $endStr',
          kpis: [
            ReportKpi(
              label: 'Venta neta',
              value: BackofficeSalesAdapter.formatMoney(canonical.netSales),
            ),
            ReportKpi(label: 'Canales', value: '${byPlat.length}'),
          ],
          headers: const [
            'Plataforma',
            'Venta neta',
            'Ticket promedio',
            'Órdenes',
          ],
          rows: rows,
          partialWarning: partialWarn,
          readCount: bundle.readCount,
        );

      case BackofficeReportKind.paymentMethod:
        final byMethod = <String, _PayMethodAgg>{};
        for (final p in activePayments) {
          final label = BackofficeSalesAdapter.paymentMethodLabel(p.method);
          final agg = byMethod.putIfAbsent(label, _PayMethodAgg.new);
          final applied = canonicalPaymentAppliedAmount(p);
          final fee = p.method.trim().toLowerCase() == 'card'
              ? p.cardFeeAbsorbedAmount
              : 0.0;
          agg.charged += applied;
          agg.surcharge += p.surchargeAmount;
          agg.fee += fee;
        }
        final rows = byMethod.entries.map((e) {
          final net = e.value.charged - e.value.fee;
          return [
            e.key,
            BackofficeSalesAdapter.formatMoney(e.value.charged),
            BackofficeSalesAdapter.formatMoney(e.value.surcharge),
            BackofficeSalesAdapter.formatMoney(e.value.fee),
            BackofficeSalesAdapter.formatMoney(net),
            BackofficeSalesAdapter.formatMoney(0),
          ];
        }).toList();
        rows.add([
          'Descuentos aplicados',
          BackofficeSalesAdapter.formatMoney(0),
          BackofficeSalesAdapter.formatMoney(0),
          BackofficeSalesAdapter.formatMoney(0),
          BackofficeSalesAdapter.formatMoney(0),
          BackofficeSalesAdapter.formatMoney(canonical.discountTotal),
        ]);
        return ReportTableResult(
          kind: kind,
          title: 'Ventas por método de pago',
          subtitle: '$startStr al $endStr',
          kpis: [
            ReportKpi(
              label: 'Cobrado monetario',
              value: BackofficeSalesAdapter.formatMoney(canonical.monetaryCollected),
            ),
            ReportKpi(
              label: 'Descuentos',
              value: BackofficeSalesAdapter.formatMoney(canonical.discountTotal),
            ),
          ],
          headers: const [
            'Método',
            'Cobrado real',
            'Recargo cliente',
            'Comisión absorbida',
            'Neto estimado',
            'Descuentos aplicados',
          ],
          rows: rows,
          partialWarning: partialWarn,
          readCount: bundle.readCount,
        );

      case BackofficeReportKind.employee:
        final byEmp = <String, _SimpleAgg>{};
        final empOrders = <String, Set<String>>{};
        for (final p in activePayments) {
          final name = (p.employeeName ?? '').trim().isNotEmpty
              ? p.employeeName!.trim()
              : 'Sin usuario';
          final agg = byEmp.putIfAbsent(name, _SimpleAgg.new);
          agg.net += canonicalPaymentAppliedAmount(p);
          empOrders.putIfAbsent(name, () => {}).add(p.orderId);
        }
        final rows = byEmp.entries.map((e) {
          final cnt = empOrders[e.key]?.length ?? 0;
          final avg = cnt > 0 ? e.value.net / cnt : 0.0;
          return [
            e.key,
            '$cnt',
            BackofficeSalesAdapter.formatMoney(e.value.net),
            BackofficeSalesAdapter.formatMoney(avg),
            '—',
          ];
        }).toList(growable: false);
        return ReportTableResult(
          kind: kind,
          title: 'Ventas por empleado',
          subtitle: '$startStr al $endStr',
          kpis: [
            ReportKpi(label: 'Operadores', value: '${byEmp.length}'),
            ReportKpi(
              label: 'Cobrado',
              value: BackofficeSalesAdapter.formatMoney(canonical.totalCollected),
            ),
          ],
          headers: const [
            'Empleado',
            'Órdenes',
            'Venta neta',
            'Ticket promedio',
            'Tiempo promedio',
          ],
          rows: rows,
          partialWarning: partialWarn,
          readCount: bundle.readCount,
        );

      case BackofficeReportKind.visitClassification:
        final report = buildVisitClassificationWeeklyReport(
          orders: orders,
          startBusinessDate: startStr,
          endBusinessDate: endStr,
        );
        final rows = report.rows
            .map(
              (r) => [
                '${BackofficeSalesAdapter.formatBusinessDate(r.weekStart)} – ${BackofficeSalesAdapter.formatBusinessDate(r.weekEnd)}',
                r.isPartial ? 'Parcial' : 'Completa',
                '${r.firstTime}',
                '${r.returning}',
                '${r.classified}',
                '${r.unknown}',
                '${r.firstTimePercent.toStringAsFixed(1)}%',
                '${r.returningPercent.toStringAsFixed(1)}%',
              ],
            )
            .toList(growable: false);
        return ReportTableResult(
          kind: kind,
          title: 'Visitas nuevas y recurrentes',
          subtitle: '$startStr al $endStr · ${report.rows.length} semanas',
          kpis: [
            ReportKpi(label: 'Nuevas', value: '${report.firstTimeTotal}'),
            ReportKpi(label: 'Recurrentes', value: '${report.returningTotal}'),
            ReportKpi(label: 'Sin clasificar', value: '${report.unknownTotal}'),
          ],
          headers: const [
            'Semana',
            'Tipo',
            'Nuevas',
            'Recurrentes',
            'Clasificadas',
            'Sin clasificar',
            '% Nuevas',
            '% Recurrentes',
          ],
          rows: rows,
          partialWarning: partialWarn,
          readCount: bundle.readCount,
        );

      case BackofficeReportKind.discountsByDay:
        final discReport = buildDiscountsByDayReport(
          orderRows: canonical.orderRows,
          paymentsByOrder: paymentsByOrder,
        );
        final discRows = discReport.rows;
        final rows = discRows
            .map(
              (r) => [
                r.businessDate,
                BackofficeSalesAdapter.resolveFolioLabel(r.order),
                r.discountName,
                r.beneficiary,
                r.appliedBy,
                r.authorizedBy,
                BackofficeSalesAdapter.formatMoney(r.discountAmount),
                BackofficeSalesAdapter.formatMoney(r.netTotal),
              ],
            )
            .toList(growable: false);
        final totalDisc = discRows.fold<double>(
          0.0,
          (a, r) => a + r.discountAmount,
        );
        return ReportTableResult(
          kind: kind,
          title: 'Descuentos por día',
          subtitle: '$startStr al $endStr · ${discRows.length} eventos',
          kpis: [
            ReportKpi(
              label: 'Total descuentos',
              value: BackofficeSalesAdapter.formatMoney(totalDisc),
            ),
            ReportKpi(label: 'Registros', value: '${discRows.length}'),
          ],
          headers: const [
            'Fecha',
            'Folio',
            'Concepto',
            'Beneficiario',
            'Aplicó',
            'Autorizó',
            'Descuento',
            'Neto',
          ],
          rows: rows,
          rowOrderIds: discRows.map((r) => r.order.id).toList(growable: false),
          partialWarning: partialWarn,
          readCount: bundle.readCount,
        );

      case BackofficeReportKind.cancellations:
        final rows = <List<String>>[];
        final orderIds = <String?>[];
        for (final o in orders) {
          if (isCanonicalCancelledOrder(o)) {
            rows.add([
              o.businessDate ?? '',
              BackofficeSalesAdapter.resolveFolioLabel(o),
              BackofficeSalesAdapter.orderChannelDisplay(o),
              BackofficeSalesAdapter.formatMoney(o.total),
              o.cancelReason ?? 'Sin motivo',
              o.cancelledByEmployeeName ?? '—',
              o.kitchenStatus,
              'Orden cancelada',
              BackofficeSalesAdapter.formatDateTime(o.cancelledAt),
            ]);
            orderIds.add(o.id);
          }
        }
        return ReportTableResult(
          kind: kind,
          title: 'Cancelaciones de tickets',
          subtitle: '$startStr al $endStr · ${rows.length} cancelaciones',
          kpis: [
            ReportKpi(label: 'Órdenes canceladas', value: '${rows.length}'),
          ],
          headers: const [
            'Fecha',
            'ID / Folio',
            'Mesa / Canal',
            'Importe',
            'Motivo',
            'Responsable',
            'Cocina',
            'Estado',
            'Hora',
          ],
          rows: rows,
          rowOrderIds: orderIds,
          partialWarning: partialWarn,
          readCount: bundle.readCount,
        );

      case BackofficeReportKind.cancelledPayments:
        final cancelled = paymentsByOrder.values
            .expand((l) => l)
            .where((p) => p.isCancelled)
            .toList(growable: false);
        final rows = cancelled
            .map(
              (p) => [
                p.businessDate ?? '',
                p.id,
                p.tableName,
                BackofficeSalesAdapter.paymentMethodLabel(p.method),
                BackofficeSalesAdapter.formatMoney(p.baseAmount),
                BackofficeSalesAdapter.formatMoney(p.chargedAmount),
                p.cancelReason ?? '—',
                p.cancelledByEmployeeName ?? '—',
                BackofficeSalesAdapter.formatDateTime(p.cancelledAt),
              ],
            )
            .toList(growable: false);
        return ReportTableResult(
          kind: kind,
          title: 'Pagos cancelados',
          subtitle: '$startStr al $endStr · ${cancelled.length} pagos',
          kpis: [
            ReportKpi(label: 'Pagos anulados', value: '${cancelled.length}'),
          ],
          headers: const [
            'Fecha',
            'ID Pago',
            'Mesa / Canal',
            'Método',
            'Base',
            'Cobrado',
            'Motivo',
            'Cancelado por',
            'Hora',
          ],
          rows: rows,
          rowOrderIds: cancelled.map((p) => p.orderId).toList(growable: false),
          partialWarning: partialWarn,
          readCount: bundle.readCount,
        );

      case BackofficeReportKind.saleFolios:
        final active = orders
            .where((o) => !isCanonicalCancelledOrder(o))
            .toList(growable: false);
        final voided = orders
            .where((o) => isCanonicalCancelledOrder(o))
            .toList(growable: false);
        final rows = orders
            .map(
              (o) => [
                o.businessDate ?? '',
                BackofficeSalesAdapter.resolveFolioLabel(o),
                BackofficeSalesAdapter.orderStatusLabel(o.status),
                BackofficeSalesAdapter.formatMoney(o.total),
                BackofficeSalesAdapter.formatMoney(o.paidTotal),
              ],
            )
            .toList(growable: false);
        return ReportTableResult(
          kind: kind,
          title: 'Folios de venta',
          subtitle: '$startStr al $endStr · ${orders.length} folios',
          kpis: [
            ReportKpi(label: 'Emitidos', value: '${orders.length}'),
            ReportKpi(label: 'Activos', value: '${active.length}'),
            ReportKpi(label: 'Anulados', value: '${voided.length}'),
          ],
          headers: const ['Fecha', 'Folio', 'Estado', 'Total', 'Pagado'],
          rows: rows,
          rowOrderIds: orders.map((o) => o.id).toList(growable: false),
          partialWarning: partialWarn,
          readCount: bundle.readCount,
        );

      case BackofficeReportKind.salesDiscrepancyAudit:
        final rows = <List<String>>[];
        final orderIds = <String?>[];
        for (final r in canonical.orderRows) {
          final diff = (r.totalCollected - r.netSales).abs();
          if (diff > salesReconciliationTolerance) {
            rows.add([
              r.businessDate,
              BackofficeSalesAdapter.resolveFolioLabel(r.order),
              BackofficeSalesAdapter.formatMoney(r.netSales),
              BackofficeSalesAdapter.formatMoney(r.totalCollected),
              BackofficeSalesAdapter.formatMoney(r.totalCollected - r.netSales),
            ]);
            orderIds.add(r.order.id);
          }
        }
        return ReportTableResult(
          kind: kind,
          title: 'Auditoría de discrepancias de ventas',
          subtitle: '$startStr al $endStr · Solo lectura',
          kpis: [
            ReportKpi(label: 'Órdenes con diferencia', value: '${rows.length}'),
          ],
          headers: const [
            'Fecha',
            'Folio',
            'Venta neta',
            'Cobrado',
            'Diferencia',
          ],
          rows: rows,
          rowOrderIds: orderIds,
          partialWarning: partialWarn,
          readCount: bundle.readCount,
        );

      case BackofficeReportKind.rapidCardSalesAudit:
        final rapidRows = buildRapidCardSalesAudit(
          orders: orders,
          itemsByOrder: itemsByOrder,
          paymentsByOrder: paymentsByOrder,
        );
        final rows = rapidRows
            .map(
              (r) => [
                r.order.businessDate ?? '',
                BackofficeSalesAdapter.resolveFolioLabel(r.order),
                r.payment.employeeName ?? '—',
                BackofficeSalesAdapter.formatMoney(r.chargedAmount),
                '${r.readyKitchenItems} listos',
              ],
            )
            .toList(growable: false);
        return ReportTableResult(
          kind: kind,
          title: 'Auditoría de cobros rápidos con tarjeta',
          subtitle: '$startStr al $endStr · ${rapidRows.length} registros',
          kpis: [
            ReportKpi(label: 'Cobros tarjeta auditados', value: '${rapidRows.length}'),
          ],
          headers: const [
            'Fecha',
            'Folio',
            'Cajero',
            'Cobrado',
            'Cocina lista antes cobro',
          ],
          rows: rows,
          rowOrderIds: rapidRows.map((r) => r.order.id).toList(growable: false),
          partialWarning: partialWarn,
          readCount: bundle.readCount,
        );

      case BackofficeReportKind.cancellationShortageAudit:
        final auditRows = buildCancellationCashAuditRows(
          orders: orders,
          itemsByOrder: itemsByOrder,
          paymentsByOrder: paymentsByOrder,
        );
        final rows = auditRows
            .map(
              (r) => [
                r.businessDate,
                BackofficeSalesAdapter.resolveFolioLabel(r.order),
                r.order.cancelReason ?? 'Sin motivo',
                r.initiatedByNames.isNotEmpty
                    ? r.initiatedByNames.join(', ')
                    : '—',
                r.passedThroughKitchen ? 'Sí' : 'No',
                BackofficeSalesAdapter.formatMoney(r.cancelledAmount),
              ],
            )
            .toList(growable: false);
        return ReportTableResult(
          kind: kind,
          title: 'Cancelaciones vs faltantes de caja',
          subtitle: '$startStr al $endStr · ${auditRows.length} hallazgos',
          kpis: [
            ReportKpi(label: 'Eventos', value: '${auditRows.length}'),
          ],
          headers: const [
            'Fecha',
            'Folio',
            'Motivo',
            'Actor',
            'Pasó cocina',
            'Importe',
          ],
          rows: rows,
          rowOrderIds: auditRows.map((r) => r.order.id).toList(growable: false),
          partialWarning: partialWarn,
          readCount: bundle.readCount,
        );

      default:
        return ReportTableResult(
          kind: kind,
          title: 'Reporte',
          subtitle: '$startStr al $endStr',
          kpis: const [],
          headers: const [],
          rows: const [],
          readCount: bundle.readCount,
        );
    }
  }

  Future<ReportTableResult> _runCashHistory({
    required DocumentReference<Map<String, dynamic>> restRef,
    required String startStr,
    required String endStr,
    String? branchId,
  }) async {
    final snap = await restRef
        .collection('cashSessions')
        .where('businessDate', isGreaterThanOrEqualTo: startStr)
        .where('businessDate', isLessThanOrEqualTo: endStr)
        .orderBy('businessDate', descending: true)
        .limit(120)
        .get();
    final sessions = snap.docs
        .map(CashSession.fromDoc)
        .where((s) => branchId == null || branchId.isEmpty || s.branchId == branchId)
        .toList(growable: false);
    final rows = sessions
        .map(
          (s) => [
            s.businessDate,
            s.openedByEmployeeName,
            s.closedByEmployeeName ?? 'Abierta',
            BackofficeSalesAdapter.formatMoney(s.expectedCashAmount),
            BackofficeSalesAdapter.formatMoney(s.countedCashAmount),
            BackofficeSalesAdapter.formatMoney(s.expectedCardChargedAmount),
            BackofficeSalesAdapter.formatMoney(s.expectedCardFeeAbsorbedAmount),
            BackofficeSalesAdapter.formatMoney(s.estimatedCardNetAmount),
            BackofficeSalesAdapter.formatMoney(s.terminalReportedAmount),
            BackofficeSalesAdapter.formatMoney(s.shortageAmount),
            BackofficeSalesAdapter.formatMoney(s.overAmount),
            BackofficeSalesAdapter.formatMoney(s.approvedWithdrawalsTotal),
          ],
        )
        .toList(growable: false);
    return ReportTableResult(
      kind: BackofficeReportKind.cashHistory,
      title: 'Corte de caja histórico',
      subtitle: '$startStr al $endStr · ${sessions.length} cortes',
      kpis: [
        ReportKpi(label: 'Cortes', value: '${sessions.length}'),
        ReportKpi(
          label: 'Faltantes',
          value: BackofficeSalesAdapter.formatMoney(
            sessions.fold(0.0, (a, s) => a + s.shortageAmount),
          ),
        ),
      ],
      headers: const [
        'Fecha',
        'Abre',
        'Cierra',
        'Efectivo esp.',
        'Efectivo cont.',
        'Tarjeta esp.',
        'Comisión',
        'Neto tarjeta',
        'Terminal',
        'Faltante',
        'Sobrante',
        'Retiros',
      ],
      rows: rows,
      readCount: snap.docs.length,
    );
  }

  Future<ReportTableResult> _runCashSchedule({
    required DocumentReference<Map<String, dynamic>> restRef,
    required String startStr,
    required String endStr,
    String? branchId,
  }) async {
    final snap = await restRef
        .collection('cashSessions')
        .where('businessDate', isGreaterThanOrEqualTo: startStr)
        .where('businessDate', isLessThanOrEqualTo: endStr)
        .orderBy('businessDate', descending: true)
        .limit(120)
        .get();
    final sessions = snap.docs
        .map(CashSession.fromDoc)
        .where((s) => branchId == null || branchId.isEmpty || s.branchId == branchId)
        .toList(growable: false);
    final rows = sessions.map((s) {
      final duration = (s.openedAt != null && s.closedAt != null)
          ? '${s.closedAt!.difference(s.openedAt!).inHours}h ${s.closedAt!.difference(s.openedAt!).inMinutes % 60}m'
          : 'En curso';
      return [
        s.businessDate,
        s.branchName,
        BackofficeSalesAdapter.formatDateTime(s.openedAt),
        BackofficeSalesAdapter.formatDateTime(s.closedAt),
        duration,
        s.openedByEmployeeName,
      ];
    }).toList(growable: false);
    return ReportTableResult(
      kind: BackofficeReportKind.cashSchedule,
      title: 'Horarios de apertura y cierre',
      subtitle: '$startStr al $endStr · ${sessions.length} turnos',
      kpis: [ReportKpi(label: 'Turnos', value: '${sessions.length}')],
      headers: const [
        'Fecha',
        'Sucursal',
        'Apertura',
        'Cierre',
        'Duración',
        'Responsable',
      ],
      rows: rows,
      readCount: snap.docs.length,
    );
  }

  Future<ReportTableResult> _runWithdrawals({
    required DocumentReference<Map<String, dynamic>> restRef,
    required String startStr,
    required String endStr,
    String? branchId,
  }) async {
    final snap = await restRef
        .collection('cashWithdrawalRequests')
        .where('businessDate', isGreaterThanOrEqualTo: startStr)
        .where('businessDate', isLessThanOrEqualTo: endStr)
        .orderBy('businessDate', descending: true)
        .limit(200)
        .get();
    final list = snap.docs
        .map(CashWithdrawalRequest.fromDoc)
        .where((w) => branchId == null || branchId.isEmpty || w.branchId == branchId)
        .toList(growable: false);
    final rows = list
        .map(
          (w) => [
            w.businessDate,
            BackofficeSalesAdapter.formatMoney(w.amount),
            w.reason,
            w.requestedByEmployeeName,
            w.authorizedByEmployeeName ?? 'Pendiente',
            w.status,
          ],
        )
        .toList(growable: false);
    return ReportTableResult(
      kind: BackofficeReportKind.withdrawals,
      title: 'Gastos / retiros',
      subtitle: '$startStr al $endStr · ${list.length} solicitudes',
      kpis: [
        ReportKpi(
          label: 'Total aprobado',
          value: BackofficeSalesAdapter.formatMoney(
            list
                .where((w) => isApprovedExpenseStatus(w.status))
                .fold(0.0, (a, w) => a + w.amount),
          ),
        ),
      ],
      headers: const [
        'Fecha',
        'Monto',
        'Motivo',
        'Solicitó',
        'Autorizó',
        'Estado',
      ],
      rows: rows,
      readCount: snap.docs.length,
    );
  }

  Future<ReportTableResult> _runKitchenReports({
    required BackofficeReportKind kind,
    required DocumentReference<Map<String, dynamic>> restRef,
    required String startStr,
    required String endStr,
    String? branchId,
  }) async {
    final snaps = await Future.wait([
      restRef
          .collection('kitchenSessions')
          .where('businessDate', isGreaterThanOrEqualTo: startStr)
          .where('businessDate', isLessThanOrEqualTo: endStr)
          .orderBy('businessDate', descending: true)
          .limit(60)
          .get(),
      restRef.collection('kitchenStockItems').limit(150).get(),
    ]);

    final sessions = snaps[0].docs
        .map(KitchenSession.fromDoc)
        .where((s) => branchId == null || branchId.isEmpty || s.branchId == branchId)
        .toList(growable: false);
    final stockById = {
      for (final s in snaps[1].docs.map(KitchenStockItem.fromDoc)) s.id: s,
    };

    final itemSnaps = await Future.wait(
      sessions.map(
        (s) => restRef
            .collection('kitchenSessions')
            .doc(s.id)
            .collection('items')
            .limit(100)
            .get(),
      ),
    );

    final rows = <List<String>>[];
    var readCount = snaps[0].docs.length + snaps[1].docs.length;
    for (var i = 0; i < sessions.length; i++) {
      final session = sessions[i];
      final items = itemSnaps[i].docs
          .map(KitchenSessionItem.fromDoc)
          .toList(growable: false);
      readCount += items.length;
      for (final item in items) {
        if (kind == BackofficeReportKind.kitchenWaste) {
          if (item.wasteQty <= 0) continue;
          rows.add([
            item.name,
            item.unit,
            item.wasteQty.toStringAsFixed(2),
            session.businessDate,
            session.closedByEmployeeName ?? '—',
            item.notes,
          ]);
        } else if (kind == BackofficeReportKind.kitchenInventory) {
          rows.add([
            item.name,
            item.previousRemainingQty.toStringAsFixed(2),
            (item.todayInputQty + item.additionalEntriesQty).toStringAsFixed(2),
            item.availableQty.toStringAsFixed(2),
            item.finalRemainingQty.toStringAsFixed(2),
            item.wasteQty.toStringAsFixed(2),
            item.usedQty.toStringAsFixed(2),
            item.soldQty.toStringAsFixed(1),
            item.yieldQtyPerUnit.toStringAsFixed(2),
          ]);
        } else {
          final opt =
              stockById[item.kitchenStockItemId]?.optimalConsumptionPerSaleQty ??
              0;
          final diff = item.yieldQtyPerUnit - opt;
          rows.add([
            item.name,
            opt.toStringAsFixed(2),
            item.yieldQtyPerUnit.toStringAsFixed(2),
            item.yieldQtyPerUnit.toStringAsFixed(2),
            diff.toStringAsFixed(2),
          ]);
        }
      }
    }

    final headers = switch (kind) {
      BackofficeReportKind.kitchenWaste => const [
        'Insumo',
        'Unidad',
        'Merma',
        'Fecha',
        'Usuario cierre',
        'Notas',
      ],
      BackofficeReportKind.kitchenInventory => const [
        'Insumo',
        'Sobrante ant.',
        'Entradas',
        'Disponible',
        'Sobrante final',
        'Merma',
        'Consumo real',
        'Equivalentes',
        'Rendimiento',
      ],
      _ => const ['Insumo', 'Óptimo', 'Actual', 'Promedio', 'Diferencia'],
    };

    return ReportTableResult(
      kind: kind,
      title: backoffice25ReportsCatalog.firstWhere((r) => r.kind == kind).title,
      subtitle: '$startStr al $endStr · ${sessions.length} sesiones',
      kpis: [ReportKpi(label: 'Registros', value: '${rows.length}')],
      headers: headers,
      rows: rows,
      readCount: readCount,
    );
  }

  Future<ReportTableResult> _runProductStockOuts({
    required DocumentReference<Map<String, dynamic>> restRef,
    required String startStr,
    required String endStr,
    String? branchId,
  }) async {
    final snap = await restRef
        .collection('productStockOuts')
        .where('businessDate', isGreaterThanOrEqualTo: startStr)
        .where('businessDate', isLessThanOrEqualTo: endStr)
        .orderBy('businessDate', descending: true)
        .limit(150)
        .get();
    final list = snap.docs
        .map(ProductStockOutRow.fromDoc)
        .where((r) => branchId == null || branchId.isEmpty || r.branchId == branchId)
        .toList(growable: false);
    final rows = list
        .map(
          (r) => [
            r.businessDate,
            r.branchName,
            r.productName,
            r.soldOutByEmployeeName,
            r.isActive ? 'Agotado' : 'Restablecido',
            r.reason,
          ],
        )
        .toList(growable: false);
    return ReportTableResult(
      kind: BackofficeReportKind.productStockOuts,
      title: 'Productos agotados',
      subtitle: '$startStr al $endStr · ${list.length} eventos',
      kpis: [
        ReportKpi(
          label: 'Activos',
          value: '${list.where((r) => r.isActive).length}',
        ),
        ReportKpi(
          label: 'Liberados',
          value: '${list.where((r) => !r.isActive).length}',
        ),
      ],
      headers: const [
        'Fecha',
        'Sucursal',
        'Producto',
        'Reportó',
        'Estado',
        'Motivo',
      ],
      rows: rows,
      readCount: snap.docs.length,
    );
  }

  Future<ReportTableResult> _runPredictiveConsumption({
    required DocumentReference<Map<String, dynamic>> restRef,
    required String startStr,
    required String endStr,
    String? branchId,
  }) async {
    final purSnap = await restRef
        .collection('supplierPurchases')
        .where('businessDate', isGreaterThanOrEqualTo: startStr)
        .where('businessDate', isLessThanOrEqualTo: endStr)
        .limit(120)
        .get();
    final purchases = purSnap.docs
        .map(SupplierPurchase.fromDoc)
        .where(
          (p) =>
              p.status.toLowerCase() != 'cancelled' &&
              (branchId == null || branchId.isEmpty || p.branchId == branchId),
        )
        .toList(growable: false);
    final itemSnaps = await Future.wait(
      purchases.map(
        (p) => restRef
            .collection('supplierPurchases')
            .doc(p.id)
            .collection('items')
            .get(),
      ),
    );
    final byItem = <String, double>{};
    final unitByItem = <String, String>{};
    var reads = purSnap.docs.length;
    for (final s in itemSnaps) {
      reads += s.docs.length;
      for (final d in s.docs) {
        final item = SupplierPurchaseItem.fromDoc(d);
        byItem[item.purchaseItemName] =
            (byItem[item.purchaseItemName] ?? 0.0) + item.quantity;
        unitByItem[item.purchaseItemName] = item.unit;
      }
    }
    final rows = byItem.entries
        .map(
          (e) => [
            e.key,
            e.value.toStringAsFixed(2),
            unitByItem[e.key] ?? '',
            'Abastecido en periodo',
          ],
        )
        .toList(growable: false);
    return ReportTableResult(
      kind: BackofficeReportKind.predictiveConsumptionAudit,
      title: 'Inteligencia de consumo',
      subtitle: '$startStr al $endStr · ${rows.length} insumos',
      kpis: [ReportKpi(label: 'Insumos comprados', value: '${rows.length}')],
      headers: const ['Insumo', 'Comprado en periodo', 'Unidad', 'Estado'],
      rows: rows,
      readCount: reads,
    );
  }

  Future<ReportTableResult> _runYieldProfit({
    required DocumentReference<Map<String, dynamic>> restRef,
    required String startStr,
    required String endStr,
    String? branchId,
    bool forceRefresh = false,
  }) async {
    final bundle = await _loadOrderBundle(
      restRef: restRef,
      restaurantId: restRef.id,
      startStr: startStr,
      endStr: endStr,
      branchId: branchId,
      includeItems: true,
      forceRefresh: forceRefresh,
    );
    final extra = await Future.wait([
      restRef.collection('productRecipes').limit(200).get(),
      restRef.collection('ingredientYieldProfiles').limit(100).get(),
      restRef
          .collection('supplierPurchases')
          .where('businessDate', isGreaterThanOrEqualTo: startStr)
          .where('businessDate', isLessThanOrEqualTo: endStr)
          .limit(120)
          .get(),
    ]);
    final recipes =
        extra[0].docs.map(TheoreticalProductRecipe.fromDoc).toList(growable: false);
    final yields =
        extra[1].docs.map(IngredientYieldProfile.fromDoc).toList(growable: false);
    final purchases = extra[2].docs
        .map(SupplierPurchase.fromDoc)
        .where(
          (p) =>
              p.status.toLowerCase() != 'cancelled' &&
              (branchId == null || branchId.isEmpty || p.branchId == branchId),
        )
        .toList(growable: false);
    final purItemSnaps = await Future.wait(
      purchases.map(
        (p) => restRef
            .collection('supplierPurchases')
            .doc(p.id)
            .collection('items')
            .get(),
      ),
    );
    final purchaseItems = purItemSnaps
        .expand((s) => s.docs.map(SupplierPurchaseItem.fromDoc))
        .toList(growable: false);

    final salesMap = <String, _SimpleAgg>{};
    final nameById = <String, String>{};
    final catById = <String, String>{};
    for (final list in bundle.itemsByOrder.values) {
      for (final item in list) {
        if (item.status == 'cancelled' || item.qty <= 0) continue;
        final id = item.productId.isNotEmpty ? item.productId : item.productName;
        nameById[id] = item.productName;
        catById[id] = item.category;
        final agg = salesMap.putIfAbsent(id, _SimpleAgg.new);
        agg.net += item.total;
        agg.count += item.qty;
      }
    }
    final aggregates = salesMap.entries
        .map(
          (e) => ProductSaleAggregate(
            productId: e.key,
            productName: nameById[e.key] ?? e.key,
            categoryName: catById[e.key] ?? 'General',
            unitsSold: e.value.count.toDouble(),
            netRevenue: e.value.net,
          ),
        )
        .toList(growable: false);

    final profRows = buildProductProfitabilityReport(
      sales: aggregates,
      recipes: recipes,
      yieldProfiles: yields,
      ingredientCosts: resolveIngredientCosts(
        periodPurchaseItems: purchaseItems,
        historicalPurchaseItems: const [],
      ),
    );
    final rows = profRows
        .map(
          (r) => [
            r.productName,
            r.unitsSold.toStringAsFixed(0),
            BackofficeSalesAdapter.formatMoney(r.netRevenue),
            r.theoreticalUnitCost == null
                ? 'Costo N/D'
                : BackofficeSalesAdapter.formatMoney(r.theoreticalUnitCost!),
            r.estimatedGrossProfit == null
                ? 'N/D'
                : BackofficeSalesAdapter.formatMoney(r.estimatedGrossProfit!),
            r.marginPercent == null
                ? 'N/D'
                : '${r.marginPercent!.toStringAsFixed(1)}%',
            r.costNote,
          ],
        )
        .toList(growable: false);
    return ReportTableResult(
      kind: BackofficeReportKind.yieldProfit,
      title: 'Rendimiento y utilidad',
      subtitle: '$startStr al $endStr · ${rows.length} productos',
      kpis: [
        ReportKpi(
          label: 'Con costo completo',
          value: '${profRows.where((r) => r.hasCost).length}',
        ),
        ReportKpi(
          label: 'Sin receta/costo',
          value: '${profRows.where((r) => !r.hasCost).length}',
        ),
      ],
      headers: const [
        'Producto',
        'Unidades',
        'Ingreso neto',
        'Costo unit.',
        'Utilidad est.',
        'Margen %',
        'Metodología',
      ],
      rows: rows,
      readCount:
          bundle.readCount +
          extra[0].docs.length +
          extra[1].docs.length +
          extra[2].docs.length +
          purchaseItems.length,
    );
  }
}

class _CachedOrderBundle {
  const _CachedOrderBundle({
    required this.orders,
    required this.itemsByOrder,
    required this.paymentsByOrder,
    required this.hasItems,
    required this.hitLimit,
    required this.readCount,
    required this.cachedAt,
  });

  final List<PosOrder> orders;
  final Map<String, List<OrderItem>> itemsByOrder;
  final Map<String, List<Payment>> paymentsByOrder;
  final bool hasItems;
  final bool hitLimit;
  final int readCount;
  final DateTime cachedAt;
}

class _DateBucket {
  double gross = 0;
  double discounts = 0;
  double net = 0;
  double collected = 0;
  int orders = 0;
  double cash = 0;
  double card = 0;
  double platform = 0;
  double employee = 0;
}

class _SimpleAgg {
  double net = 0;
  int count = 0;
}

class _PayMethodAgg {
  double charged = 0;
  double surcharge = 0;
  double fee = 0;
}
