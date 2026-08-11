import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/reports/weekly_finance_comparison.dart';
import '../../core/theme/brand_colors.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class WeeklyFinanceComparisonView extends StatefulWidget {
  const WeeklyFinanceComparisonView({
    super.key,
    required this.repository,
    this.padding = const EdgeInsets.all(18),
    this.physics,
    this.shrinkWrap = false,
  });

  final TacoPosRepository repository;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  @override
  State<WeeklyFinanceComparisonView> createState() =>
      _WeeklyFinanceComparisonViewState();
}

class _WeeklyFinanceComparisonViewState
    extends State<WeeklyFinanceComparisonView> {
  Future<WeeklyFinanceComparisonReport>? _future;
  WeeklyFinanceDailyMetric _dailyMetric = WeeklyFinanceDailyMetric.sales;
  WeeklyFinanceChartMetric _chartMetric = WeeklyFinanceChartMetric.income;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<WeeklyFinanceComparisonReport> _load({bool forceRefresh = false}) {
    final now = DateTime.now();
    final start = weeklyComparisonRangeStart(now);
    final endExclusive = weeklyComparisonRangeEndExclusive(now);
    final formatter = DateFormat('yyyy-MM-dd');
    return widget.repository
        .getFinanceDashboardBundle(
          startBusinessDate: formatter.format(start),
          endBusinessDate: formatter.format(
            endExclusive.subtract(const Duration(days: 1)),
          ),
          forceRefresh: forceRefresh,
        )
        .then(
          (bundle) =>
              buildWeeklyFinanceComparisonReport(bundle: bundle, now: now),
        );
  }

  void _refresh() {
    setState(() => _future = _load(forceRefresh: true));
  }

  @override
  Widget build(BuildContext context) {
    final future = _future ??= _load();
    return FutureBuilder<WeeklyFinanceComparisonReport>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingPanel(
            message: 'Calculando comparativo semanal...',
          );
        }
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudo cargar el comparativo',
            message: '${snapshot.error}',
          );
        }
        final report = snapshot.data;
        if (report == null) {
          return const EmptyState(
            icon: Icons.calendar_view_week_outlined,
            title: 'Sin datos',
            message: 'No hay informacion financiera para comparar.',
          );
        }
        return ListView(
          padding: widget.padding,
          physics: widget.physics,
          shrinkWrap: widget.shrinkWrap,
          children: [
            _Header(report: report, onRefresh: _refresh),
            const SizedBox(height: 14),
            _BestWeeks(report: report),
            const SizedBox(height: 14),
            _ComparisonTable(report: report),
            const SizedBox(height: 14),
            _VariationPanels(report: report),
            const SizedBox(height: 14),
            _ChartPanel(
              report: report,
              metric: _chartMetric,
              onChanged: (value) => setState(() => _chartMetric = value),
            ),
            const SizedBox(height: 14),
            _DailyBreakdown(
              report: report,
              metric: _dailyMetric,
              onChanged: (value) => setState(() => _dailyMetric = value),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.report, required this.onRefresh});

  final WeeklyFinanceComparisonReport report;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final first = report.weeks.first;
    final last = report.weeks.last;
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Comparativo semanal',
                  style: TextStyle(
                    color: BrandColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${first.periodLabel} al ${last.periodLabel}',
                  style: const TextStyle(
                    color: BrandColors.accentYellow,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Semanas fijas de lunes a domingo. La semana actual se muestra en curso y se compara tambien contra el mismo periodo transcurrido.',
                  style: const TextStyle(
                    color: BrandColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusPill(
                icon: Icons.timelapse_outlined,
                label: '${report.elapsedDayCount} dias transcurridos',
              ),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Actualizar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BestWeeks extends StatelessWidget {
  const _BestWeeks({required this.report});

  final WeeklyFinanceComparisonReport report;

  @override
  Widget build(BuildContext context) {
    final indicators = [
      (
        'Mayor venta',
        report.bestBy((metrics) => metrics.netSales),
        Icons.trending_up_outlined,
      ),
      (
        'Mayor ingreso real',
        report.bestBy((metrics) => metrics.realIncome),
        Icons.payments_outlined,
      ),
      (
        'Mayor utilidad',
        report.bestBy((metrics) => metrics.financialProfit),
        Icons.savings_outlined,
      ),
      (
        'Mayor ordenes',
        report.bestBy((metrics) => metrics.orders.toDouble()),
        Icons.receipt_long_outlined,
      ),
      (
        'Mayor ticket promedio',
        report.bestBy((metrics) => metrics.averageTicket),
        Icons.local_activity_outlined,
      ),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: indicators.map((indicator) {
        final week = indicator.$2;
        return SizedBox(
          width: 230,
          child: GlassPanel(
            padding: const EdgeInsets.all(12),
            borderRadius: 12,
            child: Row(
              children: [
                Icon(indicator.$3, color: BrandColors.accentYellow, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        indicator.$1,
                        style: const TextStyle(
                          color: BrandColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        week == null
                            ? 'Sin datos'
                            : '${week.label} · ${week.periodLabel}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: BrandColors.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.report});

  final WeeklyFinanceComparisonReport report;

  @override
  Widget build(BuildContext context) {
    final rows = [
      _MetricRow('Venta bruta', (metrics) => _money(metrics.grossSales)),
      _MetricRow('Descuentos', (metrics) => _money(metrics.discounts)),
      _MetricRow('Venta neta esperada', (metrics) => _money(metrics.netSales)),
      _MetricRow(
        'Ingreso real recibido',
        (metrics) => _money(metrics.realIncome),
      ),
      _MetricRow('Efectivo recibido', (metrics) => _money(metrics.cashIncome)),
      _MetricRow('Tarjeta recibida', (metrics) => _money(metrics.cardIncome)),
      _MetricRow('Otros ingresos', (metrics) => _money(metrics.otherIncome)),
      _MetricRow('Faltantes de corte', (metrics) => _money(metrics.shortages)),
      _MetricRow('Sobrantes de corte', (metrics) => _money(metrics.overages)),
      _MetricRow('Gastos', (metrics) => _money(metrics.expenses)),
      _MetricRow(
        'Utilidad financiera real',
        (metrics) => _money(metrics.financialProfit),
      ),
      _MetricRow('Ordenes', (metrics) => '${metrics.orders}'),
      _MetricRow('Ticket promedio', (metrics) => _money(metrics.averageTicket)),
    ];
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelTitle('Tabla comparativa principal'),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingTextStyle: const TextStyle(
                color: BrandColors.accentYellow,
                fontWeight: FontWeight.w900,
              ),
              dataTextStyle: const TextStyle(
                color: BrandColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
              columns: [
                const DataColumn(label: Text('Metrica')),
                for (final week in report.weeks)
                  DataColumn(
                    label: SizedBox(
                      width: 150,
                      child: Text(
                        '${week.label}${week.isInProgress ? ' · En curso' : ''}\n${week.periodLabel}',
                      ),
                    ),
                  ),
              ],
              rows: [
                for (final row in rows)
                  DataRow(
                    cells: [
                      DataCell(Text(row.label)),
                      for (final week in report.weeks)
                        DataCell(Text(row.format(week.metrics))),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VariationPanels extends StatelessWidget {
  const _VariationPanels({required this.report});

  final WeeklyFinanceComparisonReport report;

  @override
  Widget build(BuildContext context) {
    final current = report.weeks.last.metrics;
    final previous = report.weeks[report.weeks.length - 2].metrics;
    final sameCurrent = report.samePeriodWeeks.last.metrics;
    final samePrevious =
        report.samePeriodWeeks[report.samePeriodWeeks.length - 2].metrics;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final cards = [
          _VariationCard(
            title: 'Total semanal vs semana anterior',
            subtitle: 'Actual contra semana anterior completa',
            current: current,
            previous: previous,
          ),
          _VariationCard(
            title: 'Mismo periodo transcurrido',
            subtitle:
                'Mismos ${report.elapsedDayCount} dias de la semana anterior',
            current: sameCurrent,
            previous: samePrevious,
          ),
        ];
        if (!wide) {
          return Column(
            children: [cards[0], const SizedBox(height: 12), cards[1]],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
          ],
        );
      },
    );
  }
}

class _VariationCard extends StatelessWidget {
  const _VariationCard({
    required this.title,
    required this.subtitle,
    required this.current,
    required this.previous,
  });

  final String title;
  final String subtitle;
  final WeeklyFinanceMetrics current;
  final WeeklyFinanceMetrics previous;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Venta', current.netSales, previous.netSales),
      ('Ingreso real', current.realIncome, previous.realIncome),
      ('Gastos', current.expenses, previous.expenses),
      ('Utilidad', current.financialProfit, previous.financialProfit),
      ('Ordenes', current.orders.toDouble(), previous.orders.toDouble()),
      ('Ticket promedio', current.averageTicket, previous.averageTicket),
    ];
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelTitle(title),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: BrandColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (final row in rows)
            _VariationLine(
              label: row.$1,
              change: weeklyFinanceChange(current: row.$2, previous: row.$3),
              isCount: row.$1 == 'Ordenes',
            ),
        ],
      ),
    );
  }
}

class _VariationLine extends StatelessWidget {
  const _VariationLine({
    required this.label,
    required this.change,
    required this.isCount,
  });

  final String label;
  final WeeklyFinanceChange change;
  final bool isCount;

  @override
  Widget build(BuildContext context) {
    final color = change.isPositive
        ? BrandColors.success
        : change.isNegative
        ? BrandColors.danger
        : BrandColors.textMuted;
    final percent = change.percent;
    final text = percent == null
        ? 'Sin base'
        : '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(2)}%';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: BrandColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            isCount
                ? change.current.toInt().toString()
                : _money(change.current),
            style: const TextStyle(
              color: BrandColors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 88,
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPanel extends StatelessWidget {
  const _ChartPanel({
    required this.report,
    required this.metric,
    required this.onChanged,
  });

  final WeeklyFinanceComparisonReport report;
  final WeeklyFinanceChartMetric metric;
  final ValueChanged<WeeklyFinanceChartMetric> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = [
      for (final week in report.weeks) weeklyChartValue(week, metric),
    ];
    final maxValue = values.fold<double>(
      0,
      (max, value) => value.abs() > max ? value.abs() : max,
    );
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: _PanelTitle('Grafica comparativa')),
              _MetricMenu<WeeklyFinanceChartMetric>(
                value: metric,
                values: WeeklyFinanceChartMetric.values,
                label: _chartMetricLabel,
                onChanged: onChanged,
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final week in report.weeks)
            _BarLine(
              label: '${week.label}${week.isInProgress ? ' · En curso' : ''}',
              value: weeklyChartValue(week, metric),
              maxValue: maxValue,
              formatter: metric == WeeklyFinanceChartMetric.orders
                  ? (value) => value.toInt().toString()
                  : _money,
            ),
        ],
      ),
    );
  }
}

class _BarLine extends StatelessWidget {
  const _BarLine({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.formatter,
  });

  final String label;
  final double value;
  final double maxValue;
  final String Function(double value) formatter;

  @override
  Widget build(BuildContext context) {
    final factor = maxValue <= 0
        ? 0.0
        : (value.abs() / maxValue).clamp(0.0, 1.0);
    final color = value < 0 ? BrandColors.danger : BrandColors.success;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: const TextStyle(
                color: BrandColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 18,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: Colors.white.withValues(alpha: 0.07)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: factor,
                      child: Container(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              formatter(value),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: BrandColors.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyBreakdown extends StatelessWidget {
  const _DailyBreakdown({
    required this.report,
    required this.metric,
    required this.onChanged,
  });

  final WeeklyFinanceComparisonReport report;
  final WeeklyFinanceDailyMetric metric;
  final ValueChanged<WeeklyFinanceDailyMetric> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: _PanelTitle('Desglose por dia')),
              _MetricMenu<WeeklyFinanceDailyMetric>(
                value: metric,
                values: WeeklyFinanceDailyMetric.values,
                label: _dailyMetricLabel,
                onChanged: onChanged,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingTextStyle: const TextStyle(
                color: BrandColors.accentYellow,
                fontWeight: FontWeight.w900,
              ),
              columns: [
                const DataColumn(label: Text('Dia')),
                for (final week in report.weeks)
                  DataColumn(
                    label: SizedBox(
                      width: 145,
                      child: Text(
                        '${week.label}${week.isInProgress ? ' · En curso' : ''}\n${week.periodLabel}',
                      ),
                    ),
                  ),
              ],
              rows: [
                for (
                  var dayIndex = 0;
                  dayIndex < DateTime.daysPerWeek;
                  dayIndex++
                )
                  DataRow(
                    cells: [
                      DataCell(Text(_weekdayLabel(dayIndex))),
                      for (final week in report.weeks)
                        DataCell(
                          Text(
                            _dailyCellValue(week.dailyRows[dayIndex], metric),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricMenu<T> extends StatelessWidget {
  const _MetricMenu({
    required this.value,
    required this.values,
    required this.label,
    required this.onChanged,
  });

  final T value;
  final List<T> values;
  final String Function(T value) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      items: [
        for (final item in values)
          DropdownMenuItem<T>(value: item, child: Text(label(item))),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: BrandColors.accentYellow.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: BrandColors.accentYellow.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: BrandColors.accentYellow, size: 16),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: BrandColors.accentYellow,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: BrandColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _MetricRow {
  const _MetricRow(this.label, this.format);

  final String label;
  final String Function(WeeklyFinanceMetrics metrics) format;
}

String _dailyCellValue(
  WeeklyFinanceDaySummary day,
  WeeklyFinanceDailyMetric metric,
) {
  if (day.isFutureForCurrentWeek) {
    return 'Pendiente';
  }
  final value = weeklyDailyValue(day, metric);
  if (metric == WeeklyFinanceDailyMetric.orders) {
    return value.toInt().toString();
  }
  return _money(value);
}

String _dailyMetricLabel(WeeklyFinanceDailyMetric metric) {
  return switch (metric) {
    WeeklyFinanceDailyMetric.sales => 'Venta',
    WeeklyFinanceDailyMetric.income => 'Ingreso real',
    WeeklyFinanceDailyMetric.orders => 'Ordenes',
  };
}

String _chartMetricLabel(WeeklyFinanceChartMetric metric) {
  return switch (metric) {
    WeeklyFinanceChartMetric.sales => 'Venta',
    WeeklyFinanceChartMetric.income => 'Ingreso real',
    WeeklyFinanceChartMetric.profit => 'Utilidad',
    WeeklyFinanceChartMetric.orders => 'Ordenes',
  };
}

String _weekdayLabel(int weekdayIndex) {
  return const [
    'Lunes',
    'Martes',
    'Miercoles',
    'Jueves',
    'Viernes',
    'Sabado',
    'Domingo',
  ][weekdayIndex];
}

String _money(double value) {
  final sign = value < 0 ? '-' : '';
  final formatted = NumberFormat.currency(
    locale: 'es_MX',
    symbol: r'$',
    decimalDigits: 2,
  ).format(value.abs());
  return '$sign$formatted';
}
