import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/reports/hourly_sales_comparison.dart';
import '../../core/sound/kitchen_sound_service.dart';
import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../services/app_session.dart';
import '../../services/live_presence_service.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/status_badge.dart';
import '../kitchen_control/kitchen_control_screen.dart';
import 'kitchen_order_detail_screen.dart';

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  late final TacoPosRepository _repository;
  late final Stream<List<KitchenOrderBundle>> _bundlesStream;
  late final Future<bool> _kitchenIsOpenFuture;
  final Set<String> _knownKitchenOrderIds = <String>{};
  bool _hasInitializedKitchenOrders = false;
  bool _openingHourlySales = false;

  @override
  void initState() {
    super.initState();
    _repository = TacoPosRepository();
    _bundlesStream = _repository.watchKitchenOrderBundles();
    _kitchenIsOpenFuture = _repository
        .hasCompletedOpenKitchenForCurrentBusinessDate();
    LivePresenceService.instance.update(
      appMode: 'kitchen',
      currentScreen: 'Cocina',
      currentAction: 'Viendo comandas',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (AppSession.instance.employee?.canViewKitchen != true) {
      return const BrandedScaffold(
        title: 'Cocina',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para ver cocina.',
        ),
      );
    }

    return BrandedScaffold(
      title: 'Cocina',
      body: FutureBuilder<bool>(
        future: _kitchenIsOpenFuture,
        builder: (context, kitchenSnapshot) {
          if (kitchenSnapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Verificando apertura...');
          }
          if (kitchenSnapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudo validar cocina',
              message: '${kitchenSnapshot.error}',
            );
          }
          if (kitchenSnapshot.data != true) {
            return _KitchenNotOpenState(
              canOpenKitchen:
                  AppSession.instance.employee?.canOpenKitchen == true,
            );
          }

          return StreamBuilder<List<KitchenOrderBundle>>(
            stream: _bundlesStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudieron cargar comandas',
                  message: '${snapshot.error}',
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingPanel(message: 'Cargando comandas...');
              }

              final bundles = snapshot.data ?? [];
              _handleNewKitchenBundles(bundles);
              if (bundles.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _KitchenListHeader(
                        activeCount: 0,
                        onTestBeep: () => _testKitchenBeep(context),
                        onTestExpressBeep: () =>
                            _testKitchenExpressBeep(context),
                        canViewHourlySales:
                            _canViewKitchenHourlySalesComparison,
                        openingHourlySales: _openingHourlySales,
                        onOpenHourlySales: () =>
                            _openHourlySalesComparison(context),
                      ),
                      const SizedBox(height: 18),
                      const Expanded(
                        child: EmptyState(
                          icon: Icons.room_service_outlined,
                          title: 'Sin comandas activas',
                          message:
                              'Solo apareceran tacos y gringas enviados a cocina.',
                        ),
                      ),
                    ],
                  ),
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 700;
                  final medium = constraints.maxWidth < 950;
                  final padding = compact
                      ? 12.0
                      : medium
                      ? 16.0
                      : 22.0;
                  final gap = compact ? 10.0 : 14.0;

                  return Padding(
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _KitchenListHeader(
                          activeCount: bundles.length,
                          onTestBeep: () => _testKitchenBeep(context),
                          onTestExpressBeep: () =>
                              _testKitchenExpressBeep(context),
                          canViewHourlySales:
                              _canViewKitchenHourlySalesComparison,
                          openingHourlySales: _openingHourlySales,
                          onOpenHourlySales: () =>
                              _openHourlySalesComparison(context),
                        ),
                        SizedBox(height: compact ? 10 : 18),
                        Expanded(
                          child: GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: compact
                                      ? 330
                                      : medium
                                      ? 420
                                      : 460,
                                  mainAxisExtent: compact
                                      ? 196
                                      : medium
                                      ? 242
                                      : 278,
                                  crossAxisSpacing: gap,
                                  mainAxisSpacing: gap,
                                ),
                            itemCount: bundles.length,
                            itemBuilder: (context, index) {
                              return _KitchenOrderCard(
                                key: ValueKey(
                                  'kitchen-${bundles[index].stableKitchenKey}',
                                ),
                                bundle: bundles[index],
                                compact: compact,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  bool get _canViewKitchenHourlySalesComparison =>
      AppSession.instance.employee?.canViewKitchenHourlySalesComparison == true;

  Future<void> _openHourlySalesComparison(BuildContext context) async {
    if (!_canViewKitchenHourlySalesComparison) {
      showAppSnackBar(
        context,
        'No tienes permiso para consultar este reporte.',
        type: AppSnackBarType.error,
        position: AppSnackBarPosition.top,
      );
      return;
    }
    if (_openingHourlySales) return;
    setState(() => _openingHourlySales = true);
    try {
      await showDialog<void>(
        context: context,
        useSafeArea: true,
        barrierDismissible: true,
        builder: (_) => _KitchenHourlySalesDialog(repository: _repository),
      );
    } finally {
      if (mounted) {
        setState(() => _openingHourlySales = false);
      }
    }
  }

  void _handleNewKitchenBundles(List<KitchenOrderBundle> bundles) {
    final currentByKey = {
      for (final bundle in bundles) bundle.stableKitchenKey: bundle,
    };

    if (!_hasInitializedKitchenOrders) {
      _knownKitchenOrderIds.addAll(currentByKey.keys);
      _hasInitializedKitchenOrders = true;
      debugPrint(
        'Kitchen beep: comandas conocidas inicializadas ${currentByKey.length}',
      );
      return;
    }

    final newKeys = currentByKey.keys
        .where((key) => !_knownKitchenOrderIds.contains(key))
        .toList();
    _knownKitchenOrderIds.addAll(currentByKey.keys);
    if (newKeys.isNotEmpty) {
      final hasExpress = newKeys.any(
        (key) => currentByKey[key]?.isKitchenExpress == true,
      );
      for (final key in newKeys) {
        final bundle = currentByKey[key];
        debugPrint(
          'Kitchen beep: nueva comanda detectada $key '
          'express=${bundle?.isKitchenExpress == true}',
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (hasExpress) {
          KitchenSoundService.instance.playExpressOrderBeep();
        } else {
          KitchenSoundService.instance.playNewOrderBeep();
        }
      });
    }
  }

  Future<void> _testKitchenBeep(BuildContext context) async {
    await KitchenSoundService.instance.playNewOrderBeep();
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      'Timbre probado',
      type: AppSnackBarType.success,
      position: AppSnackBarPosition.top,
    );
  }

  Future<void> _testKitchenExpressBeep(BuildContext context) async {
    await KitchenSoundService.instance.playExpressOrderBeep();
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      'Timbre express probado',
      type: AppSnackBarType.success,
      position: AppSnackBarPosition.top,
    );
  }
}

class _KitchenListHeader extends StatelessWidget {
  const _KitchenListHeader({
    required this.activeCount,
    required this.onTestBeep,
    required this.onTestExpressBeep,
    required this.canViewHourlySales,
    required this.openingHourlySales,
    required this.onOpenHourlySales,
  });

  final int activeCount;
  final VoidCallback onTestBeep;
  final VoidCallback onTestExpressBeep;
  final bool canViewHourlySales;
  final bool openingHourlySales;
  final VoidCallback onOpenHourlySales;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SectionHeader(
            title: 'Comandas',
            subtitle: '$activeCount activas | primero la mas vieja',
          ),
        ),
        const SizedBox(width: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            if (canViewHourlySales)
              OutlinedButton.icon(
                onPressed: openingHourlySales ? null : onOpenHourlySales,
                icon: const Icon(Icons.query_stats, size: 18),
                label: Text(
                  openingHourlySales ? 'Abriendo...' : 'Ventas por hora',
                ),
              ),
            OutlinedButton.icon(
              onPressed: onTestBeep,
              icon: const Icon(Icons.notifications_active_outlined, size: 18),
              label: const Text('Probar timbre'),
            ),
            OutlinedButton.icon(
              onPressed: onTestExpressBeep,
              icon: const Icon(Icons.priority_high_rounded, size: 18),
              label: const Text('Probar express'),
            ),
          ],
        ),
      ],
    );
  }
}

class _KitchenHourlySalesDialog extends StatefulWidget {
  const _KitchenHourlySalesDialog({required this.repository});

  final TacoPosRepository repository;

  @override
  State<_KitchenHourlySalesDialog> createState() =>
      _KitchenHourlySalesDialogState();
}

class _KitchenHourlySalesDialogState extends State<_KitchenHourlySalesDialog> {
  late final Future<HourlyComparisonReport> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.getKitchenHourlySalesComparison();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(18),
      child: FractionallySizedBox(
        widthFactor: 0.92,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 760),
          child: GlassPanel(
            borderRadius: 18,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: SectionHeader(
                        title: 'Ventas por hora',
                        subtitle: 'Hoy vs mismo dia de la semana anterior',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: FutureBuilder<HourlyComparisonReport>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const SizedBox(
                          height: 320,
                          child: LoadingPanel(
                            message: 'Cargando ventas por hora...',
                          ),
                        );
                      }
                      if (snapshot.hasError || !snapshot.hasData) {
                        debugPrint(
                          'Kitchen hourly sales report failed: ${snapshot.error}',
                        );
                        return const SizedBox(
                          height: 260,
                          child: EmptyState(
                            icon: Icons.error_outline,
                            title: 'No se pudo cargar',
                            message:
                                'No se pudo cargar el comparativo de ventas.',
                          ),
                        );
                      }
                      return _KitchenHourlySalesContent(report: snapshot.data!);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KitchenHourlySalesContent extends StatelessWidget {
  const _KitchenHourlySalesContent({required this.report});

  final HourlyComparisonReport report;

  @override
  Widget build(BuildContext context) {
    final diff = report.totalA - report.totalB;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _KitchenHourlyMetric(
                label: 'Dia seleccionado ${_dateText(report.aDate)}',
                value: _money(report.totalA),
                accent: BrandColors.accentYellow,
              ),
              _KitchenHourlyMetric(
                label: 'Semana anterior ${_dateText(report.bDate)}',
                value: _money(report.totalB),
                accent: BrandColors.info,
              ),
              _KitchenHourlyMetric(
                label: 'Diferencia total',
                value:
                    '${_money(diff)} ${hourlyPercentLabel(report.totalA, report.totalB)}',
                accent: _diffColor(diff),
              ),
              _KitchenHourlyMetric(
                label: 'Mejor hora dia seleccionado',
                value: report.bestA == null
                    ? 'Sin ventas'
                    : '${hourRange(report.bestA!.hour)} ${_money(report.bestA!.a.sales)}',
                accent: BrandColors.accentYellow,
              ),
              _KitchenHourlyMetric(
                label: 'Mejor hora semana anterior',
                value: report.bestB == null
                    ? 'Sin ventas'
                    : '${hourRange(report.bestB!.hour)} ${_money(report.bestB!.b.sales)}',
                accent: BrandColors.info,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _KitchenHourlyChart(report: report),
        ],
      ),
    );
  }
}

class _KitchenHourlyMetric extends StatelessWidget {
  const _KitchenHourlyMetric({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: BrandColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KitchenHourlyChart extends StatelessWidget {
  const _KitchenHourlyChart({required this.report});

  final HourlyComparisonReport report;

  @override
  Widget build(BuildContext context) {
    final visibleRows = report.rows
        .where((row) => row.a.sales > 0 || row.b.sales > 0)
        .toList();
    final maxSales = visibleRows.fold<double>(
      0,
      (max, row) => [
        max,
        row.a.sales,
        row.b.sales,
      ].reduce((value, element) => value > element ? value : element),
    );
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: const [
              _KitchenHourlyLegend(
                color: BrandColors.accentYellow,
                label: 'Dia A',
              ),
              _KitchenHourlyLegend(color: BrandColors.info, label: 'Dia B'),
            ],
          ),
          const SizedBox(height: 14),
          if (visibleRows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Sin ventas por hora para graficar.',
                style: TextStyle(
                  color: BrandColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            ...visibleRows.map(
              (row) => _KitchenHourlyBarRow(row: row, maxSales: maxSales),
            ),
        ],
      ),
    );
  }
}

class _KitchenHourlyLegend extends StatelessWidget {
  const _KitchenHourlyLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: BrandColors.textMuted)),
      ],
    );
  }
}

class _KitchenHourlyBarRow extends StatelessWidget {
  const _KitchenHourlyBarRow({required this.row, required this.maxSales});

  final HourlyComparisonRow row;
  final double maxSales;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(
              hourRange(row.hour),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _KitchenHourlyBar(
                  value: maxSales <= 0 ? 0 : row.a.sales / maxSales,
                  color: BrandColors.accentYellow,
                ),
                const SizedBox(height: 4),
                _KitchenHourlyBar(
                  value: maxSales <= 0 ? 0 : row.b.sales / maxSales,
                  color: BrandColors.info,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(
              _money(row.diff),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _diffColor(row.diff),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KitchenHourlyBar extends StatelessWidget {
  const _KitchenHourlyBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: (constraints.maxWidth * value).clamp(
              2,
              constraints.maxWidth,
            ),
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        );
      },
    );
  }
}

class _KitchenNotOpenState extends StatelessWidget {
  const _KitchenNotOpenState({required this.canOpenKitchen});

  final bool canOpenKitchen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassPanel(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.soup_kitchen_outlined,
              size: 46,
              color: BrandColors.accentOrange,
            ),
            const SizedBox(height: 12),
            const Text(
              'Debes completar la apertura de cocina antes de entrar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              canOpenKitchen
                  ? 'Abre cocina desde Control de cocina para ver comandas.'
                  : 'No tienes permiso para abrir cocina. Solicita a un administrador.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: BrandColors.textMuted),
            ),
            if (canOpenKitchen) ...[
              const SizedBox(height: 18),
              GlassButton(
                icon: Icons.soup_kitchen_outlined,
                label: 'Abrir cocina',
                prominent: true,
                onTap: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const KitchenControlScreen(),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KitchenOrderCard extends StatelessWidget {
  const _KitchenOrderCard({
    super.key,
    required this.bundle,
    required this.compact,
  });

  final KitchenOrderBundle bundle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final order = bundle.order;
    final style = kitchenStatusStyle(order.kitchenStatus);
    final waitingSince =
        bundle.firstSentToKitchenAt ?? order.sentToKitchenAt ?? order.updatedAt;
    final hasCancellationRequest = bundle.items.any(
      (item) => item.hasCancellationRequested,
    );

    return GlassCard(
      accent: _elapsedColorForStart(waitingSince),
      selected: order.kitchenStatus == 'cooking',
      padding: EdgeInsets.all(compact ? 10 : 16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => KitchenOrderDetailScreen(
              orderId: order.id,
              kitchenBatchId: bundle.kitchenBatchId,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 18 : 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              StatusBadge(style: style),
            ],
          ),
          SizedBox(height: compact ? 4 : 8),
          if (bundle.isKitchenExpress) ...[
            _ExpressChip(compact: compact),
            SizedBox(height: compact ? 5 : 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatTime(waitingSince),
                  style: TextStyle(
                    color: BrandColors.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: compact ? 12 : 14,
                  ),
                ),
              ),
              KitchenElapsedBadge(startTime: waitingSince, compact: compact),
            ],
          ),
          const Spacer(),
          if (hasCancellationRequest) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: BrandColors.danger.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: BrandColors.danger.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                'Cancelacion solicitada',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: BrandColors.danger,
                  fontSize: compact ? 13 : 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            SizedBox(height: compact ? 6 : 8),
          ],
          _IngredientSummary(bundle: bundle, compact: compact),
          SizedBox(height: compact ? 6 : 10),
          Text(
            bundle.personLabel.isEmpty
                ? '${bundle.personCount} personas'
                : bundle.personLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: BrandColors.accentYellow,
              fontSize: compact ? 14 : 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: compact ? 8 : 14),
          Row(
            children: [
              Text(
                'Abrir comanda',
                style: TextStyle(
                  color: BrandColors.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 12 : 14,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.open_in_full,
                size: compact ? 14 : 16,
                color: BrandColors.textMuted,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime? date) {
    if (date == null) {
      return 'Hora pendiente';
    }

    return DateFormat('HH:mm').format(date);
  }
}

class _ExpressChip extends StatelessWidget {
  const _ExpressChip({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: BrandColors.danger.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: BrandColors.danger.withValues(alpha: 0.50)),
        ),
        child: Text(
          'Surtido express',
          style: TextStyle(
            color: BrandColors.danger,
            fontSize: compact ? 11 : 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _IngredientSummary extends StatelessWidget {
  const _IngredientSummary({required this.bundle, required this.compact});

  final KitchenOrderBundle bundle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final summary = bundle.ingredientSummary.take(compact ? 3 : 5).toList();
    if (summary.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: summary.map((entry) {
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 5 : 7,
          ),
          decoration: BoxDecoration(
            color: BrandColors.accentYellow.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: BrandColors.accentYellow.withValues(alpha: 0.34),
            ),
          ),
          child: Text(
            '${entry.key} x ${_qty(entry.value)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: BrandColors.accentYellow,
              fontSize: compact ? 14 : 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      }).toList(),
    );
  }
}

String _qty(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}

class KitchenElapsedBadge extends StatefulWidget {
  const KitchenElapsedBadge({
    super.key,
    required this.startTime,
    this.compact = false,
  });

  final DateTime? startTime;
  final bool compact;

  @override
  State<KitchenElapsedBadge> createState() => _KitchenElapsedBadgeState();
}

class _KitchenElapsedBadgeState extends State<KitchenElapsedBadge> {
  late final Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.startTime == null
        ? Duration.zero
        : _now.difference(widget.startTime!);
    final color = _elapsedColor(elapsed);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 7 : 10,
        vertical: widget.compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        _formatElapsed(elapsed),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: widget.compact ? 12 : 14,
        ),
      ),
    );
  }
}

String _money(double value) {
  return NumberFormat.currency(symbol: r'$', decimalDigits: 2).format(value);
}

String _dateText(DateTime date) {
  return DateFormat('dd/MM/yyyy').format(date);
}

Color _diffColor(double value) {
  if (value > 0.01) return BrandColors.success;
  if (value < -0.01) return BrandColors.danger;
  return BrandColors.textMuted;
}

Color _elapsedColorForStart(DateTime? startTime) {
  if (startTime == null) {
    return BrandColors.success;
  }
  return _elapsedColor(DateTime.now().difference(startTime));
}

Color _elapsedColor(Duration elapsed) {
  if (elapsed <= const Duration(minutes: 4)) {
    return BrandColors.success;
  }
  if (elapsed <= const Duration(minutes: 6)) {
    return BrandColors.accentYellow;
  }
  return BrandColors.danger;
}

String _formatElapsed(Duration elapsed) {
  final safeElapsed = elapsed.isNegative ? Duration.zero : elapsed;
  final minutes = safeElapsed.inMinutes;
  final seconds = safeElapsed.inSeconds
      .remainder(60)
      .toString()
      .padLeft(2, '0');
  return '$minutes:$seconds';
}
