import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../models/order.dart';
import '../../models/order_platform.dart';
import '../../services/app_session.dart';
import '../../services/live_presence_service.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';
import '../../widgets/status_badge.dart';
import 'order_screen.dart';

enum _UnseatedMode { takeout, standing }

class TakeoutOrdersScreen extends StatelessWidget {
  const TakeoutOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _UnseatedOrdersScreen(mode: _UnseatedMode.takeout);
  }
}

class StandingOrdersScreen extends StatelessWidget {
  const StandingOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _UnseatedOrdersScreen(mode: _UnseatedMode.standing);
  }
}

class _UnseatedOrdersScreen extends StatefulWidget {
  const _UnseatedOrdersScreen({required this.mode});

  final _UnseatedMode mode;

  @override
  State<_UnseatedOrdersScreen> createState() => _UnseatedOrdersScreenState();
}

class _UnseatedOrdersScreenState extends State<_UnseatedOrdersScreen> {
  final _repository = TacoPosRepository();
  late final Stream<List<PosOrder>> _ordersStream;
  late final Stream<List<OrderPlatform>> _platformsStream;
  bool _busy = false;

  bool get _standing => widget.mode == _UnseatedMode.standing;
  String get _title => _standing ? 'Parados sin mesa' : 'Para llevar';

  @override
  void initState() {
    super.initState();
    _ordersStream = _standing
        ? _repository.watchOpenStandingOrders()
        : _repository.watchOpenTakeoutOrders();
    _platformsStream = _repository.watchOrderPlatforms();
    _repository.ensureDefaultOrderPlatforms();
    LivePresenceService.instance.update(
      appMode: 'waiter',
      currentScreen: _title,
      currentAction: 'Viendo órdenes $_title',
    );
  }

  Future<void> _newOrder(List<OrderPlatform> platforms) async {
    if (AppSession.instance.employee?.canTakeOrders != true || _busy) return;
    final inPerson = findInPersonPlatform(platforms);
    if (_standing && inPerson == null) {
      showAppSnackBar(
        context,
        'No se encontró la plataforma En persona en la configuración.',
        type: AppSnackBarType.error,
      );
      return;
    }
    final result = await showDialog<_NewUnseatedOrderResult>(
      context: context,
      builder: (_) =>
          _NewUnseatedOrderDialog(mode: widget.mode, platforms: platforms),
    );
    if (!mounted || result == null) return;

    setState(() => _busy = true);
    try {
      final order = _standing
          ? await _repository.createStandingOrder(
              customerName: result.customerName,
            )
          : await _repository.createTakeoutOrder(
              platform: result.platform!,
              customerName: result.customerName,
            );
      if (!mounted) return;
      await _openOrder(order);
    } catch (error) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudo crear la orden: $error',
          type: AppSnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOrder(PosOrder order) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderScreen(
          orderId: order.id,
          tableId: order.tableId,
          tableName: order.displayName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final employee = AppSession.instance.employee;
    final canTakeOrders = employee?.canTakeOrders == true;
    final canCharge = employee?.canCharge == true;
    if (!canTakeOrders && !canCharge) {
      return BrandedScaffold(
        title: _title,
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para levantar pedidos ni cobrar.',
        ),
      );
    }
    return BrandedScaffold(
      title: _title,
      body: StreamBuilder<List<OrderPlatform>>(
        stream: _platformsStream,
        builder: (context, platformSnapshot) {
          if (platformSnapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudo cargar la configuración',
              message: '${platformSnapshot.error}',
            );
          }
          if (!platformSnapshot.hasData) {
            return const LoadingPanel(message: 'Cargando configuración...');
          }
          final platforms = platformSnapshot.data ?? const <OrderPlatform>[];
          return StreamBuilder<List<PosOrder>>(
            stream: _ordersStream,
            builder: (context, orderSnapshot) {
              if (orderSnapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudieron cargar las órdenes',
                  message: '${orderSnapshot.error}',
                );
              }
              if (!orderSnapshot.hasData) {
                return const LoadingPanel(message: 'Cargando órdenes...');
              }
              final orders = orderSnapshot.data ?? const <PosOrder>[];
              return ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SectionHeader(
                          title: _title,
                          subtitle: _standing
                              ? 'Clientes en el establecimiento sin mesa física.'
                              : 'Pedidos independientes para recoger o plataforma.',
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed:
                            _busy ||
                                !canTakeOrders ||
                                (!_standing && platforms.isEmpty)
                            ? null
                            : () => _newOrder(platforms),
                        icon: const Icon(Icons.add),
                        label: Text(_busy ? 'Creando...' : 'Nueva orden'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (orders.isEmpty)
                    EmptyState(
                      icon: _standing
                          ? Icons.accessibility_new
                          : Icons.shopping_bag_outlined,
                      title: 'Sin órdenes abiertas',
                      message: 'Crea una orden nueva cuando llegue un cliente.',
                    )
                  else
                    ...orders.map(
                      (order) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _UnseatedOrderCard(
                          order: order,
                          standing: _standing,
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
    );
  }
}

class _UnseatedOrderCard extends StatelessWidget {
  const _UnseatedOrderCard({
    required this.order,
    required this.standing,
    required this.onTap,
  });

  final PosOrder order;
  final bool standing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final folio = order.id.length <= 6 ? order.id : order.id.substring(0, 6);
    final time = order.createdAt == null
        ? '--:--'
        : DateFormat('HH:mm').format(order.createdAt!);
    return GlassCard(
      onTap: onTap,
      accent: standing ? BrandColors.info : BrandColors.accentOrange,
      child: Row(
        children: [
          Icon(
            standing ? Icons.accessibility_new : Icons.shopping_bag_outlined,
            color: standing ? BrandColors.info : BrandColors.accentYellow,
            size: 30,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.customerDisplayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Folio $folio · $time · ${order.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: BrandColors.textMuted),
                ),
              ],
            ),
          ),
          StatusBadge(style: tableStatusStyle(order.status)),
          const SizedBox(width: 12),
          MoneyText(
            value: order.total,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _NewUnseatedOrderDialog extends StatefulWidget {
  const _NewUnseatedOrderDialog({required this.mode, required this.platforms});

  final _UnseatedMode mode;
  final List<OrderPlatform> platforms;

  @override
  State<_NewUnseatedOrderDialog> createState() =>
      _NewUnseatedOrderDialogState();
}

class _NewUnseatedOrderDialogState extends State<_NewUnseatedOrderDialog> {
  final _customerController = TextEditingController();
  OrderPlatform? _platform;
  String? _errorText;

  bool get _standing => widget.mode == _UnseatedMode.standing;

  @override
  void initState() {
    super.initState();
    _platform = _standing
        ? findInPersonPlatform(widget.platforms)
        : widget.platforms.isEmpty
        ? null
        : widget.platforms.first;
  }

  @override
  void dispose() {
    _customerController.dispose();
    super.dispose();
  }

  void _submit() {
    final customer = _customerController.text.trim();
    if (customer.isEmpty) {
      setState(() {
        _errorText = _standing
            ? 'Captura el nombre de la persona.'
            : 'Captura el nombre del cliente.';
      });
      return;
    }
    if (_platform == null) return;
    Navigator.pop(
      context,
      _NewUnseatedOrderResult(platform: _platform, customerName: customer),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _standing ? 'Nueva orden sin mesa' : 'Nuevo pedido para llevar',
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_standing) ...[
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
                onChanged: (value) => setState(() => _platform = value),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _customerController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Nombre del cliente',
                errorText: _errorText,
              ),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
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

class _NewUnseatedOrderResult {
  const _NewUnseatedOrderResult({
    required this.platform,
    required this.customerName,
  });

  final OrderPlatform? platform;
  final String customerName;
}
