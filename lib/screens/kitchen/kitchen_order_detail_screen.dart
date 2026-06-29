import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../services/taco_pos_repository.dart';
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
  int _personIndex = 0;
  bool _busy = false;

  Future<void> _setCooking() async {
    await _run(() {
      return _repository.updateKitchenStatus(
        orderId: widget.orderId,
        status: 'cooking',
      );
    });
  }

  Future<void> _markReady() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar comanda lista'),
        content: const Text('La comanda saldra de la lista activa de cocina.'),
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
      return _repository.updateKitchenStatus(
        orderId: widget.orderId,
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
            stream: _repository.watchOrder(widget.orderId),
            builder: (context, orderSnapshot) {
              final order = orderSnapshot.data;
              if (orderSnapshot.connectionState == ConnectionState.waiting ||
                  order == null) {
                return const LoadingPanel(message: 'Abriendo comanda...');
              }

              return StreamBuilder<List<OrderItem>>(
                stream: _repository.watchKitchenItems(widget.orderId),
                builder: (context, itemSnapshot) {
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
                                  'Persona $personNumber',
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Persona ${_personIndex + 1} de ${people.length}',
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
                              child: OutlinedButton.icon(
                                onPressed: _personIndex == 0
                                    ? null
                                    : () {
                                        setState(() {
                                          _personIndex -= 1;
                                        });
                                      },
                                icon: const Icon(Icons.chevron_left),
                                label: const Text('Persona anterior'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _personIndex >= people.length - 1
                                    ? null
                                    : () {
                                        setState(() {
                                          _personIndex += 1;
                                        });
                                      },
                                icon: const Icon(Icons.chevron_right),
                                label: const Text('Persona siguiente'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _busy ? null : _setCooking,
                                icon: const Icon(Icons.timer_outlined),
                                label: const Text('En preparacion'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed: _busy ? null : _markReady,
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('Listo'),
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
                order.tableName,
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
