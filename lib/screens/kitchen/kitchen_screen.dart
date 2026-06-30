import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _repository = TacoPosRepository();
    _bundlesStream = _repository.watchKitchenOrderBundles();
    _kitchenIsOpenFuture = _repository
        .getOpenKitchenSessionForCurrentBusinessDate()
        .then((session) => session != null);
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
              if (bundles.isEmpty) {
                return const EmptyState(
                  icon: Icons.room_service_outlined,
                  title: 'Sin comandas activas',
                  message: 'Solo apareceran tacos y gringas enviados a cocina.',
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1180
                      ? 3
                      : constraints.maxWidth >= 760
                      ? 2
                      : 1;

                  return Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionHeader(
                          title: 'Comandas',
                          subtitle:
                              '${bundles.length} activas | primero la mas vieja',
                        ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  childAspectRatio: columns == 1 ? 1.75 : 1.22,
                                ),
                            itemCount: bundles.length,
                            itemBuilder: (context, index) {
                              return _KitchenOrderCard(
                                key: ValueKey(
                                  'kitchen-${bundles[index].order.id}',
                                ),
                                bundle: bundles[index],
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
              'Debes abrir cocina antes de entrar a operacion.',
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
  const _KitchenOrderCard({super.key, required this.bundle});

  final KitchenOrderBundle bundle;

  @override
  Widget build(BuildContext context) {
    final order = bundle.order;
    final style = kitchenStatusStyle(order.kitchenStatus);
    final waitingSince =
        bundle.firstSentToKitchenAt ?? order.sentToKitchenAt ?? order.updatedAt;

    return GlassCard(
      accent: _elapsedColorForStart(waitingSince),
      selected: order.kitchenStatus == 'cooking',
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => KitchenOrderDetailScreen(orderId: order.id),
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
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              StatusBadge(style: style),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatTime(waitingSince),
                  style: const TextStyle(
                    color: BrandColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              KitchenElapsedBadge(startTime: waitingSince),
            ],
          ),
          const Spacer(),
          Text(
            bundle.personLabel.isEmpty
                ? '${bundle.personCount} personas'
                : bundle.personLabel,
            style: const TextStyle(
              color: BrandColors.accentYellow,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            bundle.shortSummary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BrandColors.textSecondary,
              fontSize: 15,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Text(
                'Abrir comanda',
                style: TextStyle(
                  color: BrandColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.open_in_full, size: 16, color: BrandColors.textMuted),
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

class KitchenElapsedBadge extends StatefulWidget {
  const KitchenElapsedBadge({super.key, required this.startTime});

  final DateTime? startTime;

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        _formatElapsed(elapsed),
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
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
