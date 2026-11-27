import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/order.dart';
import '../../auth/backoffice_session.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../widgets/data_table_pro.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/filter_bar.dart';
import '../../widgets/kpi_tile.dart';
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

  void _load() {
    setState(() {
      _future = widget.repository.loadDashboard(
        restaurantId: widget.session.restaurantId,
        startBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_startDate),
        endBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_endDate),
        branches: widget.session.branches,
        branchId: widget.session.selectedBranchId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final startLabel = BackofficeSalesAdapter.formatBusinessDate(_startDate);
    final endLabel = BackofficeSalesAdapter.formatBusinessDate(_endDate);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Resumen ejecutivo',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.session.restaurantName} • ${widget.session.selectedBranchLabel}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('Actualizar'),
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
        const SizedBox(height: 16),
        FutureBuilder<ExecutiveDashboardData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const DashboardSkeleton();
            }
            if (snapshot.hasError) {
              return SaasErrorState(
                title: 'No se pudo cargar el Dashboard',
                message: snapshot.error.toString(),
                onRetry: _load,
              );
            }
            final data = snapshot.data;
            if (data == null) {
              return const SaasEmptyState(
                icon: Icons.analytics_outlined,
                title: 'Sin datos',
                message: 'No hay registros en el rango seleccionado.',
              );
            }

            final summary = data.summary;
            final branchNames = {
              for (final b in widget.session.branches) b.id: b.name,
            };

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data.truncatedToLimit) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
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
                      'Consulta acotada a las primeras ${DashboardRepository.maxOrdersPerQuery} órdenes del rango para proteger el rendimiento.',
                      style: TextStyle(fontSize: 12, color: tokens.warning),
                    ),
                  ),
                ],
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth >= 980
                        ? 4
                        : constraints.maxWidth >= 580
                        ? 2
                        : 1;
                    return GridView.count(
                      crossAxisCount: cols,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: cols == 1 ? 2.8 : 2.15,
                      children: [
                        KpiTile(
                          label: 'Ventas Netas',
                          value: BackofficeSalesAdapter.formatMoney(
                            summary.netSales,
                          ),
                          subtitle:
                              'Brutas: ${BackofficeSalesAdapter.formatMoney(summary.grossSales)}',
                          icon: Icons.payments_outlined,
                          delta: summary.hasReconciliationDifference
                              ? 'Dif. ${BackofficeSalesAdapter.formatMoney(summary.reconciliationDifference)}'
                              : 'Conciliado',
                          deltaPositive: !summary.hasReconciliationDifference,
                        ),
                        KpiTile(
                          label: 'Órdenes Pagadas',
                          value: '${summary.paidOrdersCount}',
                          subtitle:
                              'Mesa: ${summary.dineInOrdersCount} • Llevar: ${summary.takeoutOrdersCount}',
                          icon: Icons.receipt_long_outlined,
                        ),
                        KpiTile(
                          label: 'Ticket Promedio',
                          value: BackofficeSalesAdapter.formatMoney(
                            summary.averageTicket,
                          ),
                          subtitle:
                              'Cobro monetario: ${BackofficeSalesAdapter.formatMoney(summary.monetaryCollected)}',
                          icon: Icons.trending_up_outlined,
                        ),
                        KpiTile(
                          label: 'Descuentos y Beneficios',
                          value: BackofficeSalesAdapter.formatMoney(
                            summary.discountTotal +
                                summary.employeeFreeMealTotal,
                          ),
                          subtitle:
                              'Comida empleado: ${BackofficeSalesAdapter.formatMoney(summary.employeeFreeMealTotal)}',
                          icon: Icons.local_offer_outlined,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 960;
                    final chartCard = SaasCard(
                      title: 'Tendencia de ingresos netos',
                      subtitle: '$startLabel — $endLabel',
                      child: data.dailySeries.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 36),
                              child: Center(
                                child: Text('Sin ventas pagadas en el rango'),
                              ),
                            )
                          : SizedBox(
                              height: 220,
                              child: _RevenueBarChart(series: data.dailySeries),
                            ),
                    );

                    final sideColumn = Column(
                      children: [
                        SaasCard(
                          title: 'Métodos de cobro',
                          subtitle: 'Distribución canónica',
                          child: Column(
                            children: [
                              _MetricLine(
                                label: 'Efectivo',
                                amount: summary.cashCollected,
                                total: summary.totalCollected,
                                color: tokens.success,
                              ),
                              const SizedBox(height: 10),
                              _MetricLine(
                                label: 'Tarjeta',
                                amount: summary.cardCollected,
                                total: summary.totalCollected,
                                color: tokens.info,
                              ),
                              const SizedBox(height: 10),
                              _MetricLine(
                                label: 'Plataformas',
                                amount: summary.platformCollected,
                                total: summary.totalCollected,
                                color: tokens.brandAccent,
                              ),
                              const SizedBox(height: 10),
                              _MetricLine(
                                label: 'Consumo empleado',
                                amount: summary.employeeConsumption,
                                total: summary.totalCollected,
                                color: tokens.textMuted,
                              ),
                            ],
                          ),
                        ),
                        if (data.branchBreakdown.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SaasCard(
                            title: 'Comparativo por sucursal',
                            subtitle:
                                '${data.branchBreakdown.length} sucursal(es)',
                            child: Column(
                              children: data.branchBreakdown
                                  .map(
                                    (b) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  b.branchName,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.titleMedium,
                                                ),
                                                Text(
                                                  '${b.ordersCount} órdenes • Ticket ${BackofficeSalesAdapter.formatMoney(b.averageTicket)}',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            BackofficeSalesAdapter.formatMoney(
                                              b.netSales,
                                            ),
                                            style: TextStyle(
                                              fontSize: 13.5,
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
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ],
                    );

                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: chartCard),
                          const SizedBox(width: 14),
                          Expanded(flex: 4, child: sideColumn),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        chartCard,
                        const SizedBox(height: 14),
                        sideColumn,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
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
                      child: const Text('Ver todas las ventas →'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (data.recentOrders.isEmpty)
                  const SaasEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Sin ventas registradas',
                    message:
                        'No se encontraron órdenes en el periodo seleccionado.',
                  )
                else
                  DataTablePro<PosOrder>(
                    items: data.recentOrders,
                    onRowTap: (order) => widget.onOpenSaleDetail(order.id),
                    footerSummary:
                        'Mostrando ${data.recentOrders.length} órdenes recientes',
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

class _MetricLine extends StatelessWidget {
  const _MetricLine({
    required this.label,
    required this.amount,
    required this.total,
    required this.color,
  });

  final String label;
  final double amount;
  final double total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final ratio = total <= 0 ? 0.0 : (amount / total).clamp(0.0, 1.0);
    final pct = (ratio * 100).toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text(
              '${BackofficeSalesAdapter.formatMoney(amount)} ($pct%)',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: tokens.surfaceSubtle,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _RevenueBarChart extends StatelessWidget {
  const _RevenueBarChart({required this.series});

  final List<DailyRevenuePoint> series;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final maxVal = series.fold<double>(
      1,
      (prev, e) => math.max(prev, e.netSales),
    );

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: series.map((point) {
              final factor = (point.netSales / maxVal).clamp(0.04, 1.0);
              final shortDate = point.businessDate.length >= 10
                  ? point.businessDate.substring(5)
                  : point.businessDate;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Tooltip(
                    message:
                        '${point.businessDate}\n${BackofficeSalesAdapter.formatMoney(point.netSales)} • ${point.ordersCount} órdenes',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          BackofficeSalesAdapter.formatMoney(point.netSales),
                          style: TextStyle(
                            fontSize: 10,
                            color: tokens.textMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: factor,
                              widthFactor: 0.65,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: tokens.brandAccent,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(5),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          shortDate,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
