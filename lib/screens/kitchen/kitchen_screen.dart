import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/status_badge.dart';

class KitchenScreen extends StatelessWidget {
  const KitchenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();

    return BrandedScaffold(
      title: 'Cocina',
      body: StreamBuilder<List<PosOrder>>(
        stream: repository.watchKitchenOrders(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Cargando comandas...');
          }

          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudieron cargar comandas',
              message: '${snapshot.error}',
            );
          }

          final orders = snapshot.data ?? [];
          if (orders.isEmpty) {
            return const EmptyState(
              icon: Icons.soup_kitchen,
              title: 'Sin comandas en cocina',
              message: 'Cuando Mesero envie una orden, aparecera aqui.',
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1180
                  ? 3
                  : constraints.maxWidth >= 760
                  ? 2
                  : 1;

              return GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: columns == 1 ? 1.18 : 0.92,
                ),
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  return _KitchenOrderCard(
                    order: orders[index],
                    repository: repository,
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

class _KitchenOrderCard extends StatelessWidget {
  const _KitchenOrderCard({required this.order, required this.repository});

  final PosOrder order;
  final TacoPosRepository repository;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kitchenStatusStyle(order.kitchenStatus).background,
              border: Border(
                top: BorderSide(
                  color: kitchenStatusStyle(order.kitchenStatus).color,
                  width: 5,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.tableName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(order.createdAt),
                        style: const TextStyle(
                          color: BrandColors.muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                StatusBadge(style: kitchenStatusStyle(order.kitchenStatus)),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<OrderItem>>(
              stream: repository.watchOrderItems(order.id),
              builder: (context, snapshot) {
                final items = snapshot.data ?? [];

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingPanel(message: 'Cargando items...');
                }

                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt,
                    title: 'Sin items',
                    message: 'Esta orden aun no tiene productos.',
                  );
                }

                final grouped = <int, List<OrderItem>>{};
                for (final item in items) {
                  grouped.putIfAbsent(item.personNumber, () => []).add(item);
                }

                final people = grouped.keys.toList()..sort();

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: people.length,
                  separatorBuilder: (_, _) => const Divider(height: 22),
                  itemBuilder: (context, index) {
                    final person = people[index];
                    final personItems = grouped[person] ?? [];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Persona $person',
                          style: const TextStyle(
                            color: BrandColors.yellow,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...personItems.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: BrandColors.orange.withValues(
                                      alpha: 0.18,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${item.qty}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: BrandColors.yellow,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item.productName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => repository.updateKitchenStatus(
                      orderId: order.id,
                      status: 'preparing',
                    ),
                    icon: const Icon(Icons.timer),
                    label: const Text('En preparacion'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => repository.updateKitchenStatus(
                      orderId: order.id,
                      status: 'ready',
                    ),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Listo'),
                  ),
                ),
              ],
            ),
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
