import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../models/order.dart';
import '../../models/order_platform.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';
import '../../widgets/status_badge.dart';
import 'order_screen.dart';

class TakeoutOrdersScreen extends StatefulWidget {
  const TakeoutOrdersScreen({super.key});

  @override
  State<TakeoutOrdersScreen> createState() => _TakeoutOrdersScreenState();
}

class _TakeoutOrdersScreenState extends State<TakeoutOrdersScreen> {
  final _repository = TacoPosRepository();
  late final Stream<List<PosOrder>> _ordersStream;
  late final Stream<List<OrderPlatform>> _platformsStream;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ordersStream = _repository.watchOpenTakeoutOrders();
    _platformsStream = _repository.watchOrderPlatforms();
    _repository.ensureDefaultOrderPlatforms();
  }

  Future<void> _newOrder(List<OrderPlatform> platforms) async {
    if (AppSession.instance.employee?.canTakeOrders != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tienes permiso para levantar pedidos'),
        ),
      );
      return;
    }

    if (_busy) {
      return;
    }

    final result = await showDialog<_NewTakeoutResult>(
      context: context,
      builder: (_) => _NewTakeoutDialog(platforms: platforms),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      final order = await _repository.createTakeoutOrder(
        platform: result.platform,
        customerName: result.customerName,
      );
      if (!mounted) {
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              OrderScreen(orderId: order.id, tableName: order.displayName),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear pedido: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _openOrder(PosOrder order) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OrderScreen(orderId: order.id, tableName: order.displayName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canTakeOrders = AppSession.instance.employee?.canTakeOrders == true;
    final canCharge = AppSession.instance.employee?.canCharge == true;
    if (!canTakeOrders && !canCharge) {
      return const BrandedScaffold(
        title: 'Para llevar',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para levantar pedidos ni cobrar.',
        ),
      );
    }

    return BrandedScaffold(
      title: 'Para llevar',
      body: StreamBuilder<List<OrderPlatform>>(
        stream: _platformsStream,
        builder: (context, platformSnapshot) {
          if (platformSnapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudieron cargar plataformas',
              message: '${platformSnapshot.error}',
            );
          }

          if (platformSnapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Cargando plataformas...');
          }

          final platforms = platformSnapshot.data ?? [];

          return StreamBuilder<List<PosOrder>>(
            stream: _ordersStream,
            builder: (context, orderSnapshot) {
              if (orderSnapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudieron cargar pedidos',
                  message: '${orderSnapshot.error}',
                );
              }

              if (orderSnapshot.connectionState == ConnectionState.waiting) {
                return const LoadingPanel(message: 'Cargando pedidos...');
              }

              final orders = orderSnapshot.data ?? [];
              return ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: SectionHeader(
                          title: 'Pedidos para llevar',
                          subtitle:
                              'Crea pedidos independientes y abre los pendientes.',
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _busy || platforms.isEmpty || !canTakeOrders
                            ? null
                            : () => _newOrder(platforms),
                        icon: const Icon(Icons.add_shopping_cart),
                        label: Text(_busy ? 'Creando...' : 'Nuevo pedido'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (platforms.isEmpty)
                    const GlassPanel(
                      child: Text(
                        'No hay plataformas activas. Configuralas en Admin.',
                        style: TextStyle(color: BrandColors.textMuted),
                      ),
                    )
                  else if (orders.isEmpty)
                    const EmptyState(
                      icon: Icons.shopping_bag_outlined,
                      title: 'Sin pedidos abiertos',
                      message: 'Crea un pedido nuevo cuando llegue uno.',
                    )
                  else
                    ...orders.map(
                      (order) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TakeoutOrderCard(
                          order: order,
                          onTap: () => _openOrder(order),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: StreamBuilder<List<OrderPlatform>>(
        stream: _platformsStream,
        builder: (context, snapshot) {
          final platforms = snapshot.data ?? [];
          return SafeArea(
            minimum: const EdgeInsets.all(16),
            child: GlassButton(
              icon: Icons.add,
              label: _busy ? 'Creando...' : 'Nuevo pedido para llevar',
              prominent: true,
              onTap: _busy || platforms.isEmpty || !canTakeOrders
                  ? null
                  : () => _newOrder(platforms),
            ),
          );
        },
      ),
    );
  }
}

class _TakeoutOrderCard extends StatelessWidget {
  const _TakeoutOrderCard({required this.order, required this.onTap});

  final PosOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      accent: BrandColors.accentOrange,
      selected: order.status != 'open',
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: BrandColors.accentOrange.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.shopping_bag_outlined,
              color: BrandColors.accentYellow,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  order.customerName?.isEmpty ?? true
                      ? 'Pedido abierto'
                      : order.customerName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: BrandColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          StatusBadge(style: tableStatusStyle(order.status)),
          const SizedBox(width: 12),
          MoneyText(
            value: order.total,
            style: const TextStyle(
              color: BrandColors.accentYellow,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.arrow_forward_ios_rounded, size: 14),
        ],
      ),
    );
  }
}

class _NewTakeoutDialog extends StatefulWidget {
  const _NewTakeoutDialog({required this.platforms});

  final List<OrderPlatform> platforms;

  @override
  State<_NewTakeoutDialog> createState() => _NewTakeoutDialogState();
}

class _NewTakeoutDialogState extends State<_NewTakeoutDialog> {
  late OrderPlatform _platform;
  late final TextEditingController _customerController;

  @override
  void initState() {
    super.initState();
    _platform = widget.platforms.first;
    _customerController = TextEditingController();
  }

  @override
  void dispose() {
    _customerController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(
      context,
      _NewTakeoutResult(
        platform: _platform,
        customerName: _customerController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo pedido para llevar'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<OrderPlatform>(
              initialValue: _platform,
              decoration: const InputDecoration(labelText: 'Plataforma'),
              items: widget.platforms
                  .map(
                    (platform) => DropdownMenuItem(
                      value: platform,
                      child: Text(platform.name),
                    ),
                  )
                  .toList(),
              onChanged: (platform) {
                if (platform != null) {
                  setState(() {
                    _platform = platform;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customerController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Cliente opcional'),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Crear')),
      ],
    );
  }
}

class _NewTakeoutResult {
  const _NewTakeoutResult({required this.platform, this.customerName});

  final OrderPlatform platform;
  final String? customerName;
}
