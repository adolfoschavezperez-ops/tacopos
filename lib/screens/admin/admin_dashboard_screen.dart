import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';
import 'product_catalog_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();

    return BrandedScaffold(
      title: 'Socio / Admin',
      actions: [
        IconButton(
          tooltip: 'Catalogo',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProductCatalogScreen()),
            );
          },
          icon: const Icon(Icons.restaurant_menu),
        ),
      ],
      body: StreamBuilder<List<PosOrder>>(
        stream: repository.watchAllOrders(),
        builder: (context, ordersSnapshot) {
          if (ordersSnapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Cargando dashboard...');
          }

          final orders = ordersSnapshot.data ?? [];

          return StreamBuilder<List<Product>>(
            stream: repository.watchProducts(),
            builder: (context, productsSnapshot) {
              final products = productsSnapshot.data ?? [];
              final todaySales = _todaySales(orders);
              final openTables = orders
                  .where((order) => order.status != 'paid')
                  .length;
              final kitchenOrders = orders
                  .where(
                    (order) =>
                        order.status != 'paid' &&
                        [
                          'sent',
                          'preparing',
                          'ready',
                        ].contains(order.kitchenStatus),
                  )
                  .length;
              final activeProducts = products
                  .where((product) => product.active)
                  .length;

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 900 ? 4 : 2;
                      return GridView.count(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: constraints.maxWidth >= 900
                            ? 1.6
                            : 1.25,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _MetricCard(
                            title: 'Ventas del dia',
                            icon: Icons.payments,
                            money: todaySales,
                            accent: BrandColors.yellow,
                          ),
                          _MetricCard(
                            title: 'Mesas abiertas',
                            icon: Icons.table_bar,
                            value: '$openTables',
                            accent: BrandColors.orange,
                          ),
                          _MetricCard(
                            title: 'Ordenes cocina',
                            icon: Icons.soup_kitchen,
                            value: '$kitchenOrders',
                            accent: BrandColors.success,
                          ),
                          _MetricCard(
                            title: 'Productos activos',
                            icon: Icons.fastfood,
                            value: '$activeProducts',
                            accent: BrandColors.info,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: BrandColors.orange.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.restaurant_menu,
                              color: BrandColors.yellow,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Catalogo de productos',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Ver, agregar, editar y activar productos del menu.',
                                  style: TextStyle(color: BrandColors.muted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ProductCatalogScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Abrir'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Ordenes recientes',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  if (orders.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'Aun no hay ordenes. Abre una mesa desde Mesero / Caja.',
                          style: TextStyle(color: BrandColors.muted),
                        ),
                      ),
                    )
                  else
                    ...orders
                        .take(8)
                        .map((order) => _RecentOrderTile(order: order)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  double _todaySales(List<PosOrder> orders) {
    final now = DateTime.now();
    return orders
        .where((order) {
          final createdAt = order.createdAt;
          if (createdAt == null || order.status != 'paid') {
            return false;
          }

          return createdAt.year == now.year &&
              createdAt.month == now.month &&
              createdAt.day == now.day;
        })
        .fold<double>(0, (sum, order) => sum + order.paidTotal);
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.icon,
    required this.accent,
    this.value,
    this.money,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final String? value;
  final double? money;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 30),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: BrandColors.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            if (money != null)
              MoneyText(
                value: money!,
                style: TextStyle(
                  color: accent,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                ),
              )
            else
              Text(
                value ?? '0',
                style: TextStyle(
                  color: accent,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RecentOrderTile extends StatelessWidget {
  const _RecentOrderTile({required this.order});

  final PosOrder order;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.receipt_long, color: BrandColors.orange),
        title: Text(
          order.tableName,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text('${order.status} | ${order.kitchenStatus}'),
        trailing: MoneyText(
          value: order.total,
          style: const TextStyle(
            color: BrandColors.yellow,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
