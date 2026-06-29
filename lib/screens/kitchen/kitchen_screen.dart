import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/status_badge.dart';
import 'kitchen_order_detail_screen.dart';

class KitchenScreen extends StatelessWidget {
  const KitchenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();

    return BrandedScaffold(
      title: 'Cocina',
      body: StreamBuilder<List<KitchenOrderBundle>>(
        stream: repository.watchKitchenOrderBundles(),
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
                          '${bundles.length} activas · primero la mas vieja',
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: columns == 1 ? 1.75 : 1.22,
                        ),
                        itemCount: bundles.length,
                        itemBuilder: (context, index) {
                          return _KitchenOrderCard(
                            key: ValueKey('kitchen-${bundles[index].order.id}'),
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

    return GlassCard(
      accent: style.color,
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
                  order.tableName,
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
          Text(
            _formatTime(order.sentToKitchenAt ?? order.updatedAt),
            style: const TextStyle(
              color: BrandColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '${bundle.personCount} personas',
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
