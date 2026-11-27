import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/reports/canonical_sales_summary.dart';
import '../../../models/order.dart';
import '../../../utils/csv_exporter.dart';
import '../../auth/backoffice_session.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../widgets/charts/donut_chart.dart';
import '../../widgets/charts/revenue_area_chart.dart';
import '../../widgets/data_table_pro.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/filter_bar.dart';
import '../../widgets/kpi_spark_card.dart';
import '../../widgets/saas_card.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/status_pill.dart';
import 'dashboard_repository.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.session,
    required this.repository,
    required this.onOpenSaleDetail,
    required this.onOpenAllSales,
  });

  final BackofficeSession session;
  final DashboardRepository repository;
  final ValueChanged<String> onOpenSaleDetail;
  final VoidCallback onOpenAllSales;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DatePreset _preset = DatePreset.last7Days;
  late DateTime _startDate;
  late DateTime _endDate;
  Future<ExecutiveDashboardData>? _future;
  String? _lastBranchId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _endDate = DateTime(now.year, now.month, now.day);
    _startDate = _endDate.subtract(const Duration(days: 6));
    _lastBranchId = widget.session.selectedBranchId;
    widget.session.addListener(_onSessionChanged);
    _load();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (_lastBranchId != widget.session.selectedBranchId) {
      _lastBranchId = widget.session.selectedBranchId;
      _load();
    }
  }

  void _applyPreset(DatePreset preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _preset = preset;
      switch (preset) {
        case DatePreset.today:
          _startDate = today;
          _endDate = today;
          break;
        case DatePreset.last7Days:
          _startDate = today.subtract(const Duration(days: 6));
          _endDate = today;
          break;
        case DatePreset.last30Days:
          _startDate = today.subtract(const Duration(days: 29));
          _endDate = today;
          break;
        case DatePreset.last90Days:
          _startDate = today.subtract(const Duration(days: 89));
          _endDate = today;
          break;
        case DatePreset.monthToDate:
          _startDate = DateTime(today.year, today.month, 1);
          _endDate = today;
          break;
        case DatePreset.custom:
          break;
      }
    });
    _load();
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _preset = DatePreset.custom;
      _startDate = picked.start;
      _endDate = picked.end;
    });
    _load();
  }

  void _load({bool forceRefresh = false}) {
    setState(() {
      _future = widget.repository.loadDashboard(
        restaurantId: widget.session.restaurantId,
        startBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_startDate),
        endBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_endDate),
        branches: widget.session.branches,
        branchId: widget.session.selectedBranchId,
        forceRefresh: forceRefresh,
      );
    });
  }

  Future<void> _exportDashboardCsv(ExecutiveDashboardData data) async {
    final s = data.summary;
    final start = BackofficeSalesAdapter.formatBusinessDate(_startDate);
    final end = BackofficeSalesAdapter.formatBusinessDate(_endDate);
    final buf = StringBuffer()
      ..writeln('Seccion,Concepto,Cantidad,Monto')
      ..writeln('Resumen,Ventas brutas,${s.paidOrdersCount},${s.grossSales.toStringAsFixed(2)}')
      ..writeln('Resumen,Descuentos,,${s.discountTotal.toStringAsFixed(2)}')
      ..writeln('Resumen,Consumo interno beneficios,,${s.employeeFreeMealTotal.toStringAsFixed(2)}')
      ..writeln('Resumen,Ventas netas,${s.paidOrdersCount},${s.netSales.toStringAsFixed(2)}')
      ..writeln('Cobros monetarios,Efectivo,,${s.cashCollected.toStringAsFixed(2)}')
      ..writeln('Cobros monetarios,Tarjeta,,${s.cardCollected.toStringAsFixed(2)}')
      ..writeln('Cobros monetarios,Plataformas,,${s.platformCollected.toStringAsFixed(2)}')
      ..writeln('Cobros monetarios,Total ingreso monetario,,${s.monetaryCollected.toStringAsFixed(2)}')
      ..writeln('No monetario,Consumo interno cobrado,,${s.employeeConsumption.toStringAsFixed(2)}')
      ..writeln('Adicionales,Propinas,,${data.totalTips.toStringAsFixed(2)}')
      ..writeln('Adicionales,Comisiones tarjeta absorbidas,,${data.totalCardFeesAbsorbed.toStringAsFixed(2)}');

    for (final p in s.productRows) {
      buf.writeln('Producto,"${p.productName.replaceAll('"', '""')}",${p.qty},${p.netSales.toStringAsFixed(2)}');
    }
    for (final emp in data.employeeBreakdown) {
      buf.writeln('Empleado,"${emp.employeeName.replaceAll('"', '""')}",${emp.operationsCount},${emp.collectedAmount.toStringAsFixed(2)}');
    }

    final msg = await exportCsvFile(
      fileName: 'resumen_${start}_a_$end.csv',
      content: buf.toString(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _formatDelta(double? pct) {
    if (pct == null) return null;
    final sign = pct >= 0 ? '+' : '';
    return '$sign${pct.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    final startLabel = BackofficeSalesAdapter.formatBusinessDate(_startDate);
    final endLabel = BackofficeSalesAdapter.formatBusinessDate(_endDate);
    final firstName = (widget.session.employee?.name ?? 'Equipo')
        .split(' ')
        .first;

    return ListView(
      padding: EdgeInsets.all(isMobile ? 14 : 22),
      children: [
        // Executive personalized header
        Wrap(
          spacing: 12,
          runSpacing: 10,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hola, $firstName',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '${widget.session.restaurantName} • ${widget.session.selectedBranchLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.surfaceSubtle,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Text(
                    'Datos de demostración • MXN',
                    style: TextStyle(fontSize: 11.5, color: tokens.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _load(forceRefresh: true),
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: const Text('Actualizar'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        SaasFilterBar(
          activePreset: _preset,
          startDateLabel: startLabel,
          endDateLabel: endLabel,
          onPresetSelected: _applyPreset,
          onPickCustomRange: _pickCustomRange,
        ),
        const SizedBox(height: 18),
        FutureBuilder<ExecutiveDashboardData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const DashboardSkeleton();
            }
            if (snapshot.hasError) {
              return SaasErrorState(
                title: 'No se pudo cargar el resumen',
                message: 'Verifica tu conexión e intenta nuevamente.',
                onRetry: _load,
              );
            }
            final data = snapshot.data;
            if (data == null) {
              return const SaasEmptyState(
                icon: Icons.analytics_outlined,
                title: 'Sin datos en este periodo',
                message: 'Selecciona otro rango de fechas para consultar ventas.',
              );
            }

            final summary = data.summary;
            final netSpark = data.dailySeries.map((e) => e.netSales).toList();
            final orderSpark =
                data.dailySeries.map((e) => e.ordersCount.toDouble()).toList();
            final ticketSpark = data.dailySeries
                .map(
                  (e) => e.ordersCount == 0 ? 0.0 : e.netSales / e.ordersCount,
                )
                .toList();
            final branchNames = {
              for (final b in widget.session.branches) b.id: b.name,
            };

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data.truncatedToLimit) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.warningSoft,
                      borderRadius: BorderRadius.circular(
                        BackofficeSpacing.radiusMd,
                      ),
                      border: Border.all(
                        color: tokens.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'Mostrando el análisis de las ${DashboardRepository.maxOrdersPerQuery} operaciones más recientes del periodo.',
                      style: TextStyle(fontSize: 12, color: tokens.warning),
                    ),
                  ),
                ],
                // Asymmetric KPI row: Protagonist Hero Card + 3 KPI Spark Cards
                LayoutBuilder(
                  builder: (context, constraints) {
                    final hero = HeroRevenueCard(
                      title: 'Ventas netas del periodo',
                      amountText: BackofficeSalesAdapter.formatMoney(
                        summary.netSales,
                      ),
                      subtitle:
                          'vs periodo anterior • Brutas ${BackofficeSalesAdapter.formatMoney(summary.grossSales)}',
                      sparkValues: netSpark,
                      deltaLabel: _formatDelta(data.netSalesDeltaPct),
                      deltaPositive: data.netSalesDeltaPct == null
                          ? null
                          : data.netSalesDeltaPct! >= 0,
                      statusLabel: summary.hasReconciliationDifference
                          ? 'Revisar cobro'
                          : 'Cobro cuadrado',
                      statusPositive: !summary.hasReconciliationDifference,
                    );

                    final cardOrders = KpiSparkCard(
                      label: 'Órdenes pagadas',
                      value: '${summary.paidOrdersCount}',
                      subtitle:
                          'Comedor: ${summary.dineInOrdersCount} • Para llevar: ${summary.takeoutOrdersCount}',
                      icon: Icons.receipt_long_rounded,
                      accentColor: tokens.info,
                      deltaLabel: _formatDelta(data.ordersDeltaPct),
                      deltaPositive: data.ordersDeltaPct == null
                          ? null
                          : data.ordersDeltaPct! >= 0,
                      sparkValues: orderSpark,
                    );

                    final cardTicket = KpiSparkCard(
                      label: 'Ticket promedio',
                      value: BackofficeSalesAdapter.formatMoney(
                        summary.averageTicket,
                      ),
                      subtitle:
                          'Ingreso monetario: ${BackofficeSalesAdapter.formatMoney(summary.monetaryCollected)}',
                      icon: Icons.trending_up_rounded,
                      accentColor: tokens.success,
                      deltaLabel: _formatDelta(data.avgTicketDeltaPct),
                      deltaPositive: data.avgTicketDeltaPct == null
                          ? null
                          : data.avgTicketDeltaPct! >= 0,
                      sparkValues: ticketSpark,
                    );

                    final cardDiscounts = KpiSparkCard(
                      label: 'Descuentos y consumos',
                      value: BackofficeSalesAdapter.formatMoney(
                        summary.discountTotal + summary.employeeFreeMealTotal,
                      ),
                      subtitle:
                          'Interno: ${BackofficeSalesAdapter.formatMoney(summary.employeeFreeMealTotal)} • Canceladas: ${data.cancelledOrdersCount}',
                      icon: Icons.local_offer_outlined,
                      accentColor: tokens.brandAmber,
                    );

                    if (constraints.maxWidth >= 1140) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 5, child: hero),
                            const SizedBox(width: 14),
                            Expanded(flex: 3, child: cardOrders),
                            const SizedBox(width: 14),
                            Expanded(flex: 3, child: cardTicket),
                            const SizedBox(width: 14),
                            Expanded(flex: 3, child: cardDiscounts),
                          ],
                        ),
                      );
                    }
                    if (constraints.maxWidth >= 680) {
                      return Column(
                        children: [
                          hero,
                          const SizedBox(height: 12),
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: cardOrders),
                                const SizedBox(width: 12),
                                Expanded(child: cardTicket),
                                const SizedBox(width: 12),
                                Expanded(child: cardDiscounts),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        hero,
                        const SizedBox(height: 10),
                        cardOrders,
                        const SizedBox(height: 10),
                        cardTicket,
                        const SizedBox(height: 10),
                        cardDiscounts,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Middle row: Revenue Area Chart + Payment Donut Chart
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 960;
                    final areaCard = SaasCard(
                      title: 'Tendencia de ingresos netos',
                      subtitle: '$startLabel — $endLabel',
                      child: RevenueAreaChart(series: data.dailySeries),
                    );
                    final donutCard = SaasCard(
                      title: 'Ingresos monetarios por método',
                      subtitle: 'Dinero efectivamente cobrado (excluye consumo interno)',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PaymentDonutChart(
                            totalAmount: summary.monetaryCollected,
                            centerLabel: 'Ingreso monetario',
                            slices: [
                              DonutSlice(
                                label: 'Efectivo',
                                amount: summary.cashCollected,
                                color: tokens.success,
                              ),
                              DonutSlice(
                                label: 'Tarjeta',
                                amount: summary.cardCollected,
                                color: tokens.info,
                              ),
                              DonutSlice(
                                label: 'Plataformas',
                                amount: summary.platformCollected,
                                color: tokens.brandAccent,
                              ),
                            ],
                          ),
                          const Divider(height: 22),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Consumo interno (no monetario)',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              Text(
                                BackofficeSalesAdapter.formatMoney(
                                  summary.employeeConsumption +
                                      summary.employeeFreeMealTotal,
                                ),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: tokens.textPrimary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Propinas • Comisiones absorbidas',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              Text(
                                '${BackofficeSalesAdapter.formatMoney(data.totalTips)} • ${BackofficeSalesAdapter.formatMoney(data.totalCardFeesAbsorbed)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: tokens.textSecondary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );

                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: areaCard),
                          const SizedBox(width: 14),
                          Expanded(flex: 5, child: donutCard),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        areaCard,
                        const SizedBox(height: 14),
                        donutCard,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Third row: Branch Comparison + Channels & Top Products + Financial Alerts
                LayoutBuilder(
                  builder: (context, constraints) {
                    final branchCard = SaasCard(
                      title: 'Comparativo por sucursal',
                      subtitle: '${data.branchBreakdown.length} sucursal(es)',
                      child: data.branchBreakdown.isEmpty
                          ? Text(
                              'Sin ventas por sucursal en este periodo.',
                              style: Theme.of(context).textTheme.bodySmall,
                            )
                          : _BranchComparisonList(
                              branches: data.branchBreakdown,
                            ),
                    );

                    final channelAndTopCard = SaasCard(
                      title: 'Canales y productos estrella',
                      subtitle: 'Top 4 artículos más vendidos',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ChannelSummaryRow(channel: data.channelBreakdown),
                          const Divider(height: 22),
                          if (summary.productRows.isEmpty)
                            Text(
                              'Sin artículos vendidos.',
                              style: Theme.of(context).textTheme.bodySmall,
                            )
                          else
                            _TopProductsList(
                              products: summary.productRows.take(4).toList(),
                            ),
                        ],
                      ),
                    );

                    final alertsCard = SaasCard(
                      title: 'Ventas por empleado y alertas',
                      subtitle: 'Top operadores y seguimiento',
                      trailing: widget.session.permissions.canExportData
                          ? OutlinedButton.icon(
                              onPressed: () => _exportDashboardCsv(data),
                              icon: const Icon(Icons.download_rounded, size: 14),
                              label: const Text('CSV'),
                            )
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (data.employeeBreakdown.isNotEmpty) ...[
                            ...data.employeeBreakdown.take(3).map(
                              (emp) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        emp.employeeName,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${emp.operationsCount} ops • ${BackofficeSalesAdapter.formatMoney(emp.collectedAmount)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: tokens.textPrimary,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 18),
                          ],
                          _FinancialAlertsList(
                            summary: summary,
                            cancelledCount: data.cancelledOrdersCount,
                          ),
                        ],
                      ),
                    );

                    if (constraints.maxWidth >= 1120) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 4, child: branchCard),
                          const SizedBox(width: 14),
                          Expanded(flex: 5, child: channelAndTopCard),
                          const SizedBox(width: 14),
                          Expanded(flex: 4, child: alertsCard),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        branchCard,
                        const SizedBox(height: 14),
                        channelAndTopCard,
                        const SizedBox(height: 14),
                        alertsCard,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),

                // Recent Sales
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ventas recientes',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onOpenAllSales,
                      child: const Text('Ver todas →'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (data.recentOrders.isEmpty)
                  const SaasEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Sin ventas recientes',
                    message: 'No se encontraron operaciones en este rango.',
                  )
                else if (isMobile)
                  Column(
                    children: data.recentOrders
                        .map(
                          (o) => _MobileOrderCard(
                            order: o,
                            branchName: branchNames[o.branchId] ?? o.branchId,
                            onTap: () => widget.onOpenSaleDetail(o.id),
                          ),
                        )
                        .toList(),
                  )
                else
                  DataTablePro<PosOrder>(
                    items: data.recentOrders,
                    onRowTap: (order) => widget.onOpenSaleDetail(order.id),
                    footerSummary:
                        'Mostrando ${data.recentOrders.length} ventas recientes',
                    columns: [
                      SaasColumn(
                        label: 'Folio',
                        flex: 2,
                        cellBuilder: (o) => Text(
                          BackofficeSalesAdapter.resolveFolioLabel(o),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: tokens.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      SaasColumn(
                        label: 'Sucursal',
                        flex: 2,
                        cellBuilder: (o) => Text(
                          branchNames[o.branchId] ?? o.branchId,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      SaasColumn(
                        label: 'Canal',
                        flex: 2,
                        cellBuilder: (o) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              o.orderType == 'takeout'
                                  ? Icons.delivery_dining_outlined
                                  : Icons.restaurant_outlined,
                              size: 14,
                              color: tokens.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                BackofficeSalesAdapter.orderChannelDisplay(o),
                                style: Theme.of(context).textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SaasColumn(
                        label: 'Fecha',
                        flex: 2,
                        cellBuilder: (o) => Text(
                          BackofficeSalesAdapter.resolveOrderBusinessDate(o),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      SaasColumn(
                        label: 'Estado',
                        flex: 1,
                        cellBuilder: (o) => _orderStatusPill(o.status),
                      ),
                      SaasColumn(
                        label: 'Total',
                        flex: 1,
                        alignRight: true,
                        cellBuilder: (o) => Text(
                          BackofficeSalesAdapter.formatMoney(o.total),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: tokens.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

StatusPill _orderStatusPill(String status) {
  return switch (status) {
    'paid' => const StatusPill(label: 'Pagada', tone: StatusTone.success),
    'cancelled' => const StatusPill(label: 'Cancelada', tone: StatusTone.danger),
    _ => const StatusPill(label: 'Abierta', tone: StatusTone.warning),
  };
}

class _BranchComparisonList extends StatelessWidget {
  const _BranchComparisonList({required this.branches});

  final List<BranchSalesBreakdown> branches;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final maxSales = branches.fold<double>(
      1,
      (prev, b) => math.max(prev, b.netSales),
    );

    return Column(
      children: branches.map((b) {
        final ratio = (b.netSales / maxSales).clamp(0.05, 1.0);
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      b.branchName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    BackofficeSalesAdapter.formatMoney(b.netSales),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${b.ordersCount} órdenes • Ticket prom. ${BackofficeSalesAdapter.formatMoney(b.averageTicket)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 7,
                  backgroundColor: tokens.surfaceSubtle,
                  valueColor: AlwaysStoppedAnimation<Color>(tokens.brandAccent),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ChannelSummaryRow extends StatelessWidget {
  const _ChannelSummaryRow({required this.channel});

  final ChannelBreakdown channel;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tokens.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.restaurant_outlined,
                      size: 14,
                      color: tokens.brandAccent,
                    ),
                    const SizedBox(width: 6),
                    Text('Comedor', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  BackofficeSalesAdapter.formatMoney(channel.dineInSales),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  '${channel.dineInOrders} órdenes',
                  style: TextStyle(fontSize: 11, color: tokens.textMuted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tokens.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.delivery_dining_outlined,
                      size: 14,
                      color: tokens.info,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Para llevar',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  BackofficeSalesAdapter.formatMoney(channel.takeoutSales),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  '${channel.takeoutOrders} órdenes',
                  style: TextStyle(fontSize: 11, color: tokens.textMuted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TopProductsList extends StatelessWidget {
  const _TopProductsList({required this.products});

  final List<CanonicalProductSalesRow> products;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return Column(
      children: products.map((p) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.brandAccentSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${p.qty}×',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: tokens.brandAccent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  p.productName,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                BackofficeSalesAdapter.formatMoney(p.netSales),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _FinancialAlertsList extends StatelessWidget {
  const _FinancialAlertsList({
    required this.summary,
    required this.cancelledCount,
  });

  final CanonicalSalesSummary summary;
  final int cancelledCount;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final items = <({IconData icon, Color color, String title, String detail})>[
      if (summary.hasReconciliationDifference)
        (
          icon: Icons.warning_amber_rounded,
          color: tokens.warning,
          title: 'Diferencia en cobros',
          detail:
              'Variación de ${BackofficeSalesAdapter.formatMoney(summary.reconciliationDifference)} entre ventas netas y cobros.',
        )
      else
        (
          icon: Icons.check_circle_outline_rounded,
          color: tokens.success,
          title: 'Cobros conciliados',
          detail: 'Las ventas netas coinciden con los pagos registrados.',
        ),
      if (cancelledCount > 0)
        (
          icon: Icons.cancel_outlined,
          color: tokens.danger,
          title: '$cancelledCount orden(es) cancelada(s)',
          detail: 'Revisa el detalle en la sección de Ventas.',
        ),
      if (summary.employeeFreeMealTotal > 0)
        (
          icon: Icons.restaurant_menu_rounded,
          color: tokens.info,
          title: 'Consumo interno del personal',
          detail:
              'Total acumulado: ${BackofficeSalesAdapter.formatMoney(summary.employeeFreeMealTotal)}.',
        ),
      if (summary.discountTotal > 0)
        (
          icon: Icons.local_offer_outlined,
          color: tokens.brandAmber,
          title: 'Descuentos aplicados',
          detail:
              'Total otorgado: ${BackofficeSalesAdapter.formatMoney(summary.discountTotal)}.',
        ),
    ];

    return Column(
      children: items
          .map(
            (item) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: item.color.withValues(alpha: 0.22)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(item.icon, size: 17, color: item.color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: tokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.detail,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MobileOrderCard extends StatelessWidget {
  const _MobileOrderCard({
    required this.order,
    required this.branchName,
    required this.onTap,
  });

  final PosOrder order;
  final String branchName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SaasCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  BackofficeSalesAdapter.resolveFolioLabel(order),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                _orderStatusPill(order.status),
                const Spacer(),
                Text(
                  BackofficeSalesAdapter.formatMoney(order.total),
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$branchName • ${BackofficeSalesAdapter.orderChannelDisplay(order)} • ${BackofficeSalesAdapter.resolveOrderBusinessDate(order)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
