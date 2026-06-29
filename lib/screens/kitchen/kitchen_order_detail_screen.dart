import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/status_badge.dart';

class KitchenOrderDetailScreen extends StatefulWidget {
  const KitchenOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<KitchenOrderDetailScreen> createState() =>
      _KitchenOrderDetailScreenState();
}

class _KitchenOrderDetailScreenState extends State<KitchenOrderDetailScreen> {
  final _repository = TacoPosRepository();
  late final Stream<PosOrder?> _orderStream;
  late final Stream<List<OrderItem>> _itemsStream;
  int _personIndex = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _orderStream = _repository.watchOrder(widget.orderId);
    _itemsStream = _repository.watchKitchenItems(widget.orderId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repository.markActiveKitchenItemsCooking(widget.orderId);
    });
  }

  Future<void> _markReady(List<OrderItem> activeItems) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar comanda lista'),
        content: const Text(
          'Se marcaran listos todos los productos activos de esta comanda.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Listo'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await _run(() {
      return _repository.updateKitchenItemsStatus(
        orderId: widget.orderId,
        itemIds: activeItems.map((item) => item.id),
        status: 'ready',
      );
    }, popAfter: true);
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool popAfter = false,
  }) async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await action();
      if (mounted && popAfter) {
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PremiumBackground(
        child: SafeArea(
          child: StreamBuilder<PosOrder?>(
            stream: _orderStream,
            builder: (context, orderSnapshot) {
              if (orderSnapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudo abrir la comanda',
                  message: '${orderSnapshot.error}',
                );
              }

              final order = orderSnapshot.data;
              if (orderSnapshot.connectionState == ConnectionState.waiting ||
                  order == null) {
                return const LoadingPanel(message: 'Abriendo comanda...');
              }

              return StreamBuilder<List<OrderItem>>(
                stream: _itemsStream,
                initialData: const [],
                builder: (context, itemSnapshot) {
                  if (itemSnapshot.hasError) {
                    return EmptyState(
                      icon: Icons.error_outline,
                      title: 'No se pudieron cargar articulos de cocina',
                      message: '${itemSnapshot.error}',
                    );
                  }

                  final items = itemSnapshot.data ?? [];
                  final grouped = <int, List<OrderItem>>{};
                  for (final item in items) {
                    grouped.putIfAbsent(item.personNumber, () => []).add(item);
                  }
                  final people = grouped.keys.toList()..sort();
                  if (_personIndex >= people.length) {
                    _personIndex = people.isEmpty ? 0 : people.length - 1;
                  }

                  if (people.isEmpty) {
                    return const Center(
                      child: Text('Esta comanda no tiene items de cocina.'),
                    );
                  }

                  final personNumber = people[_personIndex];
                  final personItems = grouped[personNumber] ?? [];
                  final personName = _personDisplayName(
                    personNumber,
                    personItems,
                  );
                  final isLastPerson = _personIndex >= people.length - 1;
                  final elapsedSince = _elapsedStart(items);

                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          order: order,
                          onClose: () => Navigator.pop(context),
                        ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: GlassPanel(
                            blur: 8,
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  personName,
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${_personIndex + 1} de ${people.length}',
                                  style: const TextStyle(
                                    color: BrandColors.textMuted,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Expanded(
                                  child: ListView.separated(
                                    itemCount: personItems.length,
                                    separatorBuilder: (_, _) =>
                                        const Divider(height: 24),
                                    itemBuilder: (context, index) {
                                      final item = personItems[index];
                                      return Row(
                                        children: [
                                          Container(
                                            width: 58,
                                            height: 58,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: BrandColors.accentGlow,
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                            child: Text(
                                              '${item.qty}',
                                              style: const TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.w800,
                                                color: BrandColors.accentYellow,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 18),
                                          Expanded(
                                            child: Text(
                                              item.productName,
                                              style: const TextStyle(
                                                fontSize: 28,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _PreparationTimer(startTime: elapsedSince),
                            ),
                            if (people.length > 1 && _personIndex > 0) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () {
                                          setState(() {
                                            _personIndex -= 1;
                                          });
                                        },
                                  icon: const Icon(Icons.chevron_left),
                                  label: const Text('Anterior'),
                                ),
                              ),
                            ],
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: isLastPerson
                                  ? FilledButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () => _markReady(items),
                                      icon: const Icon(
                                        Icons.check_circle_outline,
                                      ),
                                      label: const Text('Listo'),
                                    )
                                  : FilledButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () {
                                              setState(() {
                                                _personIndex += 1;
                                              });
                                            },
                                      icon: const Icon(Icons.chevron_right),
                                      label: const Text('Siguiente plato'),
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  DateTime? _elapsedStart(List<OrderItem> items) {
    return items
        .map((item) => item.cookingAt ?? item.sentToKitchenAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (min, date) => min == null || date.isBefore(min) ? date : min,
        );
  }
}

String _personDisplayName(int personNumber, List<OrderItem> items) {
  for (final item in items) {
    final name = item.personName.trim();
    if (name.isNotEmpty && name != 'Persona $personNumber') {
      return name;
    }
  }
  return 'Persona $personNumber';
}

class _PreparationTimer extends StatelessWidget {
  const _PreparationTimer({required this.startTime});

  final DateTime? startTime;

  @override
  Widget build(BuildContext context) {
    return KitchenElapsedBadge(
      startTime: startTime,
      prefix: 'En preparacion',
      height: 48,
    );
  }
}

class KitchenElapsedBadge extends StatefulWidget {
  const KitchenElapsedBadge({
    super.key,
    required this.startTime,
    required this.prefix,
    required this.height,
  });

  final DateTime? startTime;
  final String prefix;
  final double height;

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
      height: widget.height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${widget.prefix} ${_formatElapsed(elapsed)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.order, required this.onClose});

  final PosOrder order;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                _formatTime(order.sentToKitchenAt ?? order.updatedAt),
                style: const TextStyle(color: BrandColors.textMuted),
              ),
            ],
          ),
        ),
        StatusBadge(style: kitchenStatusStyle(order.kitchenStatus)),
      ],
    );
  }

  String _formatTime(DateTime? date) {
    if (date == null) {
      return 'Hora pendiente';
    }

    return DateFormat('HH:mm').format(date);
  }
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
