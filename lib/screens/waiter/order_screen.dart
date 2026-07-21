import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/product.dart';
import '../../models/product_category.dart';
import '../../services/app_session.dart';
import '../../services/live_presence_service.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/category_utils.dart';
import '../../utils/formatters.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';
import '../../widgets/status_badge.dart';
import 'payment_screen.dart';

class OrderScreen extends StatefulWidget {
  const OrderScreen({
    super.key,
    required this.orderId,
    required this.tableName,
    this.tableId,
  });

  final String orderId;
  final String tableName;
  final String? tableId;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  final _repository = TacoPosRepository();
  late Stream<PosOrder?> _orderStream;
  late final Stream<List<Product>> _productsStream;
  late final Stream<List<ProductCategory>> _productCategoriesStream;
  late String _boundOrderId;
  StreamSubscription<List<OrderItem>>? _itemsSubscription;
  List<OrderItem> _loadedItems = const [];
  bool _itemsLoading = true;
  Object? _itemsError;
  int _selectedPerson = 1;
  int _personCount = 1;
  String _selectedCategory = 'tacos';
  bool _busy = false;
  String? _lastOrderDebugSignature;
  String? _lastItemsDebugSignature;

  @override
  void initState() {
    super.initState();
    _bindOrderStreams(widget.orderId);
    _productsStream = _repository.watchProducts(activeOnly: true);
    _productCategoriesStream = _repository.watchProductCategories(
      activeOnly: true,
    );
    LivePresenceService.instance.update(
      appMode: 'waiter',
      currentScreen: 'Orden',
      currentTableId: widget.tableId,
      currentTableName: widget.tableName,
      currentOrderId: widget.orderId,
      currentPersonNumber: _selectedPerson,
      currentAction: 'Levantando orden',
    );
  }

  @override
  void didUpdateWidget(covariant OrderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) {
      _bindOrderStreams(widget.orderId);
      LivePresenceService.instance.update(
        appMode: 'waiter',
        currentScreen: 'Orden',
        currentTableId: widget.tableId,
        currentTableName: widget.tableName,
        currentOrderId: widget.orderId,
        currentPersonNumber: _selectedPerson,
        currentAction: 'Levantando orden',
      );
    }
  }

  @override
  void dispose() {
    _itemsSubscription?.cancel();
    super.dispose();
  }

  void _bindOrderStreams(String orderId) {
    _boundOrderId = orderId.trim();
    debugPrint(
      '[TacoPOS][OrderScreen.bind] tableId=${widget.tableId ?? '-'} '
      'tableName=${widget.tableName} receivedOrderId=${widget.orderId} '
      'boundOrderId=$_boundOrderId itemsPath=restaurants/${AppConstants.restaurantId}/orders/$_boundOrderId/items',
    );
    _orderStream = _repository.watchOrder(_boundOrderId);
    _bindOrderItems(_boundOrderId, clearItems: true);
  }

  Future<void> _bindOrderItems(
    String orderId, {
    bool clearItems = false,
  }) async {
    await _itemsSubscription?.cancel();
    final cleanOrderId = orderId.trim();
    final path =
        'restaurants/${AppConstants.restaurantId}/orders/$cleanOrderId/items';
    debugPrint('[TacoPOS][OrderItems.load] orderId=$cleanOrderId');
    debugPrint('[TacoPOS][OrderItems.path] $path');

    if (mounted) {
      setState(() {
        if (clearItems) {
          _loadedItems = const [];
        }
        _itemsLoading = cleanOrderId.isNotEmpty && _loadedItems.isEmpty;
        _itemsError = cleanOrderId.isEmpty
            ? StateError('OrderId vacio al cargar articulos.')
            : null;
      });
    }

    if (cleanOrderId.isEmpty) {
      debugPrint(
        '[TacoPOS][OrderItems.error] orderId=$cleanOrderId path=$path error=OrderId vacio',
      );
      return;
    }

    try {
      final initialItems = await _repository.getOrderItemsOnce(cleanOrderId);
      debugPrint('[TacoPOS][OrderItems.initialCount] ${initialItems.length}');
      if (!mounted || cleanOrderId != _boundOrderId) {
        return;
      }
      setState(() {
        _loadedItems = initialItems;
        _itemsLoading = false;
        _itemsError = null;
      });
      _itemsSubscription = _repository
          .watchOrderItems(cleanOrderId)
          .listen(
            (items) {
              debugPrint('[TacoPOS][OrderItems.streamCount] ${items.length}');
              if (!mounted || cleanOrderId != _boundOrderId) {
                return;
              }
              setState(() {
                _loadedItems = items;
                _itemsLoading = false;
                _itemsError = null;
              });
            },
            onError: (Object error, StackTrace stackTrace) {
              debugPrint(
                '[TacoPOS][OrderItems.error] orderId=$cleanOrderId path=$path error=$error',
              );
              if (!mounted || cleanOrderId != _boundOrderId) {
                return;
              }
              setState(() {
                _itemsLoading = false;
                _itemsError = error;
              });
            },
          );
    } catch (error) {
      debugPrint(
        '[TacoPOS][OrderItems.error] orderId=$cleanOrderId path=$path error=$error',
      );
      if (!mounted || cleanOrderId != _boundOrderId) {
        return;
      }
      setState(() {
        _itemsLoading = false;
        _itemsError = error;
      });
    }
  }

  Future<void> _sendToKitchen() async {
    if (AppSession.instance.employee?.canTakeOrders != true) {
      _showMessage('No tienes permiso para levantar pedidos');
      return;
    }
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      LivePresenceService.instance.update(currentAction: 'Enviando cocina');
      final sentCount = await _repository.sendOrderToKitchen(_boundOrderId);
      if (!mounted) {
        return;
      }

      showAppSnackBar(
        context,
        sentCount == 0
            ? 'No hay productos de cocina para enviar.'
            : 'Comanda enviada a cocina.',
        type: sentCount == 0 ? AppSnackBarType.info : AppSnackBarType.success,
      );

      if (sentCount > 0) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      showAppSnackBar(
        context,
        'No se pudo enviar la comanda: $error',
        type: AppSnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _openPayment() async {
    if (AppSession.instance.employee?.canCharge != true) {
      _showMessage('No tienes permiso para cobrar');
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.recalculateOrderBeforeCheckout(_boundOrderId);
    } catch (error) {
      if (!mounted) return;
      _showMessage('No se pudo validar el total: $error');
      setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PaymentScreen(orderId: _boundOrderId)),
    );
    if (!mounted) {
      return;
    }
    LivePresenceService.instance.updateCurrentScreen(
      appMode: 'waiter',
      currentScreen: 'Orden',
      currentAction: 'Levantando orden',
      currentTableId: widget.tableId,
      currentTableName: widget.tableName,
      currentOrderId: _boundOrderId,
      currentPersonNumber: _selectedPerson,
      force: true,
    );
  }

  Future<void> _showKitchenPendingDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hay productos pendientes en cocina'),
        content: const Text(
          'No puedes cobrar hasta que cocina marque todo como listo.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _closeEmptyOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar mesa vacia'),
        content: const Text(
          'La mesa quedara disponible. Solo se puede cerrar si no tiene articulos, pagos ni envio a cocina.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar mesa'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _repository.cancelEmptyOrder(_boundOrderId);
      if (!mounted) {
        return;
      }
      await LivePresenceService.instance.clearCurrentOrder(
        currentAction: 'Viendo mesas',
      );
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('$error');
    }
  }

  Future<void> _cancelOrder() async {
    if (AppSession.instance.employee?.canCancelOrders != true &&
        AppSession.instance.employee?.canViewAdmin != true) {
      _showMessage('No tienes permiso para cancelar tickets.');
      return;
    }

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(title: 'Cancelar ticket'),
    );
    if (!mounted || reason == null) {
      return;
    }

    try {
      await _repository.cancelOrder(orderId: _boundOrderId, reason: reason);
      if (!mounted) {
        return;
      }
      await LivePresenceService.instance.clearCurrentOrder(
        currentAction: 'Viendo mesas',
      );
      if (!mounted) {
        return;
      }
      _showMessage('Orden cancelada y mesa liberada.');
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('$error'.replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _cancelOrRequestItem(OrderItem item) async {
    final employee = AppSession.instance.employee;
    final canCancelItem =
        employee?.canCancelItems == true ||
        employee?.canCancelOrders == true ||
        employee?.canViewAdmin == true;
    if (!canCancelItem) {
      _showMessage('No tienes permiso para cancelar articulos.');
      return;
    }
    if (item.kitchenStatus == 'ready') {
      _showMessage(
        'Este producto ya fue servido por cocina y no puede cancelarse.',
      );
      return;
    }
    final title = item.kitchenStatus == 'pending'
        ? 'Cancelar articulo'
        : 'Solicitar cancelacion';
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(title: title),
    );
    if (!mounted || reason == null) {
      return;
    }
    try {
      if (item.kitchenStatus == 'pending' ||
          item.kitchenStatus == 'not_required') {
        await _repository.cancelOrderItem(
          orderId: _boundOrderId,
          itemId: item.id,
          reason: reason,
        );
        _showMessage('Articulo cancelado.');
      } else {
        await _repository.requestOrderItemCancellation(
          orderId: _boundOrderId,
          itemId: item.id,
          reason: reason,
        );
        _showMessage('Cancelacion solicitada a cocina.');
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _addPerson() {
    if (AppSession.instance.employee?.canTakeOrders != true) {
      _showMessage('No tienes permiso para levantar pedidos');
      return;
    }
    setState(() {
      _personCount += 1;
      _selectedPerson = _personCount;
    });
  }

  Future<void> _renamePerson(int personNumber, String currentName) async {
    if (AppSession.instance.employee?.canTakeOrders != true) {
      _showMessage('No tienes permiso para levantar pedidos');
      return;
    }
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenamePersonDialog(
        currentName: currentName,
        personNumber: personNumber,
      ),
    );

    if (!mounted || newName == null) {
      return;
    }

    try {
      await _repository.renamePerson(
        orderId: _boundOrderId,
        personNumber: personNumber,
        name: newName,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        'No se pudo renombrar la persona: $error',
        type: AppSnackBarType.error,
      );
    }
  }

  void _showMessage(String message) {
    showAppSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PosOrder?>(
      stream: _orderStream,
      builder: (context, orderSnapshot) {
        final order = orderSnapshot.data;
        if (order != null) {
          _logOrderDebug(order);
        }
        final canTakeOrders =
            AppSession.instance.employee?.canTakeOrders == true;
        final canCharge = AppSession.instance.employee?.canCharge == true;

        return BrandedScaffold(
          title: order?.displayName ?? widget.tableName,
          actions: [
            Builder(
              builder: (context) {
                if (order != null) {
                  _logItemsDebug(order, _loadedItems);
                }
                return _TopOrderActions(
                  order: order,
                  items: _loadedItems,
                  busy: _busy,
                  itemsLoaded: !_itemsLoading,
                  onSendToKitchen: _sendToKitchen,
                  onOpenPayment: _openPayment,
                  onBlockedPayment: _showKitchenPendingDialog,
                  onCloseEmptyOrder: _closeEmptyOrder,
                  onCancelOrder: _cancelOrder,
                  canTakeOrders: canTakeOrders,
                  canCharge: canCharge,
                  canCancelOrders:
                      AppSession.instance.employee?.canCancelOrders == true ||
                      AppSession.instance.employee?.canViewAdmin == true,
                );
              },
            ),
            const SizedBox(width: 10),
          ],
          body: _buildBody(orderSnapshot),
        );
      },
    );
  }

  void _logOrderDebug(PosOrder order) {
    final signature =
        '${order.id}:${order.total}:${order.status}:${order.paymentStatus}:${order.updatedAt?.millisecondsSinceEpoch}';
    if (_lastOrderDebugSignature == signature) {
      return;
    }
    _lastOrderDebugSignature = signature;
    debugPrint(
      '[TacoPOS][OrderScreen.order] tableId=${widget.tableId ?? order.tableId} '
      'tableName=${widget.tableName} receivedOrderId=${widget.orderId} '
      'boundOrderId=$_boundOrderId loadedOrderId=${order.id} '
      'total=${order.total} status=${order.status} paymentStatus=${order.paymentStatus} '
      'itemsPath=restaurants/${AppConstants.restaurantId}/orders/$_boundOrderId/items',
    );
  }

  void _logItemsDebug(PosOrder order, List<OrderItem> items) {
    final preview = items
        .take(5)
        .map((item) => '${item.id}:${item.productName}')
        .join(', ');
    final signature =
        '${order.id}:${items.length}:${items.map((item) => item.id).take(5).join('|')}';
    if (_lastItemsDebugSignature == signature) {
      return;
    }
    _lastItemsDebugSignature = signature;
    debugPrint(
      '[TacoPOS][OrderScreen.items] tableId=${widget.tableId ?? order.tableId} '
      'tableName=${widget.tableName} orderId=$_boundOrderId total=${order.total} '
      'path=restaurants/${AppConstants.restaurantId}/orders/$_boundOrderId/items '
      'itemCount=${items.length} firstItems=[$preview]',
    );
    if (order.total > 0 && items.isEmpty) {
      debugPrint(
        '[TacoPOS][OrderItems.warning] orderId=$_boundOrderId '
        'path=restaurants/${AppConstants.restaurantId}/orders/$_boundOrderId/items '
        'total=${order.total} itemCount=0',
      );
    }
  }

  Widget _buildBody(AsyncSnapshot<PosOrder?> orderSnapshot) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 650 || constraints.maxHeight < 750;
        final twoPane = constraints.maxWidth >= 720;
        final selectedPerson = _selectedPerson < 1 ? 1 : _selectedPerson;
        final order = orderSnapshot.data;
        final canTakeOrders =
            AppSession.instance.employee?.canTakeOrders == true;
        final summary = _OrderSummaryLoader(
          key: ValueKey('summary-$_boundOrderId'),
          orderId: _boundOrderId,
          onDiagnostic: (message) => debugPrint(message),
          orderSnapshot: orderSnapshot,
          items: _loadedItems,
          itemsLoading: _itemsLoading,
          itemsError: _itemsError,
          onRetryItems: () => _bindOrderItems(_boundOrderId),
          personCount: _personCount,
          selectedPerson: selectedPerson,
          onPersonCountChanged: (personCount) {
            setState(() {
              _personCount = personCount;
              if (_selectedPerson > _personCount) {
                _selectedPerson = _personCount;
              }
            });
          },
          onSelectPerson: (person) {
            setState(() {
              _selectedPerson = person;
            });
            LivePresenceService.instance.update(
              currentPersonNumber: person,
              currentAction: 'Agregando productos',
            );
          },
          onAddPerson: _addPerson,
          onRenamePerson: _renamePerson,
          onQtyChanged: (item, qty) => _repository
              .updateItemQty(orderId: _boundOrderId, item: item, qty: qty)
              .catchError((error) => _showMessage(_editErrorText(error))),
          onCancelItem: _cancelOrRequestItem,
          canEditOrder: canTakeOrders,
        );
        final menu = _ProductMenu(
          productsStream: _productsStream,
          categoriesStream: _productCategoriesStream,
          stockOutsStream: _repository.watchActiveProductStockOuts(),
          selectedCategory: _selectedCategory,
          platformId: order?.orderType == 'takeout' ? order?.platformId : null,
          onCategoryChanged: (category) {
            setState(() {
              _selectedCategory = category;
            });
          },
          onAddProduct: (product) => _repository.addProductToOrder(
            orderId: _boundOrderId,
            product: product,
            personNumber: selectedPerson,
          ),
          onMarkProductStockOut: _repository.markProductStockOut,
          onClearProductStockOut: (product) =>
              _repository.clearProductStockOut(product),
          canAddProducts: canTakeOrders,
          onBlockedAddProduct: () =>
              _showMessage('No tienes permiso para levantar pedidos'),
        );

        if (twoPane) {
          final orderWidthFactor = constraints.maxWidth >= 960 ? 0.46 : 0.43;
          return Padding(
            padding: EdgeInsets.all(compact ? 8 : 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RepaintBoundary(
                  child: SizedBox(
                    width: constraints.maxWidth * orderWidthFactor,
                    child: GlassPanel(
                      padding: EdgeInsets.zero,
                      blur: 8,
                      child: summary,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 8 : 16),
                Expanded(
                  child: RepaintBoundary(
                    child: GlassPanel(
                      padding: EdgeInsets.zero,
                      blur: 8,
                      child: menu,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        if (compact) {
          final orderPanelHeight = (constraints.maxHeight * 0.40).clamp(
            230.0,
            320.0,
          );
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                SizedBox(
                  height: orderPanelHeight,
                  child: GlassPanel(
                    padding: EdgeInsets.zero,
                    borderRadius: 14,
                    blur: 8,
                    child: summary,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: GlassPanel(
                    padding: EdgeInsets.zero,
                    borderRadius: 14,
                    blur: 8,
                    child: menu,
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              SizedBox(
                height: (constraints.maxHeight * 0.38).clamp(300.0, 420.0),
                child: GlassPanel(
                  padding: EdgeInsets.zero,
                  blur: 8,
                  child: summary,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: GlassPanel(
                  padding: EdgeInsets.zero,
                  blur: 8,
                  child: menu,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _editErrorText(Object error) {
    return error.toString().replaceFirst('Bad state: ', '');
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});

  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Captura el motivo.');
      return;
    }
    Navigator.pop(context, reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Motivo obligatorio'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_error, style: const TextStyle(color: BrandColors.danger)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Confirmar')),
      ],
    );
  }
}

class _RenamePersonDialog extends StatefulWidget {
  const _RenamePersonDialog({
    required this.currentName,
    required this.personNumber,
  });

  final String currentName;
  final int personNumber;

  @override
  State<_RenamePersonDialog> createState() => _RenamePersonDialogState();
}

class _RenamePersonDialogState extends State<_RenamePersonDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    final safeName = name.isEmpty ? 'Persona ${widget.personNumber}' : name;
    Navigator.pop(context, safeName);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Renombrar ${widget.currentName}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Nombre de persona'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

class _OrderSummaryLoader extends StatelessWidget {
  const _OrderSummaryLoader({
    super.key,
    required this.orderId,
    required this.onDiagnostic,
    required this.orderSnapshot,
    required this.items,
    required this.itemsLoading,
    required this.itemsError,
    required this.onRetryItems,
    required this.personCount,
    required this.selectedPerson,
    required this.onPersonCountChanged,
    required this.onSelectPerson,
    required this.onAddPerson,
    required this.onRenamePerson,
    required this.onQtyChanged,
    required this.onCancelItem,
    required this.canEditOrder,
  });

  final String orderId;
  final ValueChanged<String> onDiagnostic;
  final AsyncSnapshot<PosOrder?> orderSnapshot;
  final List<OrderItem> items;
  final bool itemsLoading;
  final Object? itemsError;
  final VoidCallback onRetryItems;
  final int personCount;
  final int selectedPerson;
  final ValueChanged<int> onPersonCountChanged;
  final ValueChanged<int> onSelectPerson;
  final VoidCallback onAddPerson;
  final void Function(int personNumber, String currentName) onRenamePerson;
  final void Function(OrderItem item, int qty) onQtyChanged;
  final ValueChanged<OrderItem> onCancelItem;
  final bool canEditOrder;

  @override
  Widget build(BuildContext context) {
    if (orderSnapshot.hasError) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'No se pudo cargar la orden',
        message: '${orderSnapshot.error}',
      );
    }

    if (orderSnapshot.connectionState == ConnectionState.waiting) {
      return const LoadingPanel(message: 'Abriendo orden...');
    }

    final order = orderSnapshot.data;
    if (order == null) {
      return const EmptyState(
        icon: Icons.receipt_long,
        title: 'Orden no encontrada',
        message: 'Regresa a mesas y abre una orden nueva.',
      );
    }

    if (itemsError != null && items.isEmpty) {
      return _ItemsLoadIssue(
        title: 'No se pudieron cargar los articulos de la orden.',
        message: '$itemsError',
        onRetry: onRetryItems,
      );
    }

    if (itemsLoading && items.isEmpty) {
      return const LoadingPanel(message: 'Cargando articulos...');
    }

    if (items.isEmpty && order.total > 0) {
      onDiagnostic(
        '[TacoPOS][OrderItems.warning] orderId=$orderId '
        'path=restaurants/${AppConstants.restaurantId}/orders/$orderId/items '
        'total=${order.total} itemCount=0',
      );
      return _ItemsLoadIssue(
        title: 'La orden tiene total, pero no se encontraron articulos.',
        message: 'Reintentar.',
        onRetry: onRetryItems,
        icon: Icons.warning_amber_rounded,
      );
    }

    final maxPersonFromItems = items.fold<int>(
      1,
      (max, item) => item.personNumber > max ? item.personNumber : max,
    );
    final maxPersonFromNames = order.personNames.keys.fold<int>(
      1,
      (max, person) => person > max ? person : max,
    );
    final nextPersonCount = [
      personCount,
      maxPersonFromItems,
      maxPersonFromNames,
    ].reduce((max, value) => value > max ? value : max);
    final nextSelectedPerson = selectedPerson.clamp(1, nextPersonCount).toInt();

    if (nextPersonCount != personCount ||
        nextSelectedPerson != selectedPerson) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) {
          return;
        }
        onPersonCountChanged(nextPersonCount);
      });
    }

    return _OrderSummary(
      order: order,
      items: items,
      personCount: nextPersonCount,
      selectedPerson: nextSelectedPerson,
      onSelectPerson: onSelectPerson,
      onAddPerson: onAddPerson,
      onRenamePerson: onRenamePerson,
      onQtyChanged: onQtyChanged,
      onCancelItem: onCancelItem,
      canEditOrder: canEditOrder,
    );
  }
}

class _ItemsLoadIssue extends StatelessWidget {
  const _ItemsLoadIssue({
    required this.title,
    required this.message,
    required this.onRetry,
    this.icon = Icons.error_outline,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: GlassPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: BrandColors.danger, size: 42),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: BrandColors.textMuted),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderSummary extends StatefulWidget {
  const _OrderSummary({
    required this.order,
    required this.items,
    required this.personCount,
    required this.selectedPerson,
    required this.onSelectPerson,
    required this.onAddPerson,
    required this.onRenamePerson,
    required this.onQtyChanged,
    required this.onCancelItem,
    required this.canEditOrder,
  });

  final PosOrder order;
  final List<OrderItem> items;
  final int personCount;
  final int selectedPerson;
  final ValueChanged<int> onSelectPerson;
  final VoidCallback onAddPerson;
  final void Function(int personNumber, String currentName) onRenamePerson;
  final void Function(OrderItem item, int qty) onQtyChanged;
  final ValueChanged<OrderItem> onCancelItem;
  final bool canEditOrder;

  @override
  State<_OrderSummary> createState() => _OrderSummaryState();
}

class _OrderSummaryState extends State<_OrderSummary> {
  final _scrollController = ScrollController();
  final _personKeys = <int, GlobalKey>{};
  String? _lastFocusSignature;

  @override
  void initState() {
    super.initState();
    _scheduleSelectedPersonFocus();
  }

  @override
  void didUpdateWidget(covariant _OrderSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleSelectedPersonFocus();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleSelectedPersonFocus() {
    final selectedItems = widget.items
        .where((item) => item.personNumber == widget.selectedPerson)
        .length;
    final signature = '${widget.selectedPerson}:$selectedItems';
    if (signature == _lastFocusSignature) {
      return;
    }
    _lastFocusSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final targetContext = _personKeys[widget.selectedPerson]?.currentContext;
      if (targetContext == null) {
        return;
      }
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  GlobalKey _personKey(int person) {
    return _personKeys.putIfAbsent(person, GlobalKey.new);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 650 || size.height < 750;
    final edgePadding = compact ? 10.0 : 18.0;
    final grouped = <int, List<OrderItem>>{};
    for (final item in widget.items) {
      grouped.putIfAbsent(item.personNumber, () => []).add(item);
    }
    final batchLabels = _buildBatchLabels(widget.items, widget.order.createdAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.all(compact ? 8 : edgePadding),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (compact) ...[
                      Text(
                        widget.order.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      StatusBadge(
                        style: kitchenStatusStyle(widget.order.kitchenStatus),
                      ),
                    ] else
                      SectionHeader(
                        title: widget.order.displayName,
                        subtitle: 'Orden por personas',
                        trailing: StatusBadge(
                          style: kitchenStatusStyle(widget.order.kitchenStatus),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 8 : 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'TOTAL',
                    style: TextStyle(
                      color: BrandColors.textMuted,
                      fontSize: compact ? 10 : 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  MoneyText(
                    value: widget.order.total,
                    style: TextStyle(
                      color: BrandColors.accentYellow,
                      fontSize: compact ? 22 : 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: compact ? 36 : 58,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : edgePadding,
            ),
            scrollDirection: Axis.horizontal,
            itemCount: widget.personCount + 1,
            separatorBuilder: (_, _) => SizedBox(width: compact ? 6 : 10),
            itemBuilder: (context, index) {
              if (index == widget.personCount) {
                return OutlinedButton.icon(
                  onPressed: widget.onAddPerson,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Persona'),
                  style: compact
                      ? OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        )
                      : null,
                );
              }

              final person = index + 1;
              final personName = _personDisplayName(
                order: widget.order,
                person: person,
                items: grouped[person] ?? const [],
              );
              return ChoiceChip(
                visualDensity: compact ? VisualDensity.compact : null,
                selected: widget.selectedPerson == person,
                onSelected: (_) => widget.onSelectPerson(person),
                label: Text(personName),
              );
            },
          ),
        ),
        SizedBox(height: compact ? 2 : 6),
        Expanded(
          child: widget.items.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long,
                  title: 'Sin articulos agregados',
                  message: 'Elige una persona y agrega productos del menu.',
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                    compact ? 8 : edgePadding,
                    compact ? 3 : 8,
                    compact ? 8 : edgePadding,
                    compact ? 8 : edgePadding,
                  ),
                  itemCount: widget.personCount,
                  itemBuilder: (context, index) {
                    final person = index + 1;
                    final personItems = grouped[person] ?? [];
                    final subtotal = personItems.fold<double>(
                      0,
                      (sum, item) => item.isCancelled ? sum : sum + item.total,
                    );
                    final personName = _personDisplayName(
                      order: widget.order,
                      person: person,
                      items: personItems,
                    );

                    return _PersonItemsCard(
                      key: _personKey(person),
                      person: person,
                      personName: personName,
                      selected: widget.selectedPerson == person,
                      items: personItems,
                      batchLabels: batchLabels,
                      subtotal: subtotal,
                      onSelect: () => widget.onSelectPerson(person),
                      onRename: () => widget.onRenamePerson(person, personName),
                      onQtyChanged: widget.onQtyChanged,
                      onCancelItem: widget.onCancelItem,
                      canEditOrder: widget.canEditOrder,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PersonItemsCard extends StatelessWidget {
  const _PersonItemsCard({
    super.key,
    required this.person,
    required this.personName,
    required this.selected,
    required this.items,
    required this.batchLabels,
    required this.subtotal,
    required this.onSelect,
    required this.onRename,
    required this.onQtyChanged,
    required this.onCancelItem,
    required this.canEditOrder,
  });

  final int person;
  final String personName;
  final bool selected;
  final List<OrderItem> items;
  final Map<String, _OrderBatchLabel> batchLabels;
  final double subtotal;
  final VoidCallback onSelect;
  final VoidCallback onRename;
  final void Function(OrderItem item, int qty) onQtyChanged;
  final ValueChanged<OrderItem> onCancelItem;
  final bool canEditOrder;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 650 || size.height < 750;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 6 : 14),
      child: GlassCard(
        onTap: onSelect,
        selected: selected,
        accent: BrandColors.accentYellow,
        padding: EdgeInsets.all(compact ? 7 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    personName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 14 : 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Renombrar persona',
                  visualDensity: compact ? VisualDensity.compact : null,
                  onPressed: canEditOrder ? onRename : null,
                  icon: const Icon(Icons.edit_outlined),
                ),
                SizedBox(width: compact ? 2 : 4),
                MoneyText(
                  value: subtotal,
                  style: TextStyle(
                    color: BrandColors.accentYellow,
                    fontSize: compact ? 14 : 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 4 : 8),
            if (items.isEmpty)
              const Text(
                'Sin productos',
                style: TextStyle(color: BrandColors.textMuted),
              )
            else
              ..._buildPersonBatches(items, batchLabels).expand(
                (batch) => [
                  _OrderBatchDivider(label: batch.label),
                  ...batch.items.map(
                    (item) => _OrderItemRow(
                      item: item,
                      onQtyChanged: (qty) => onQtyChanged(item, qty),
                      onCancel: () => onCancelItem(item),
                      canEditOrder: canEditOrder,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderBatchDivider extends StatelessWidget {
  const _OrderBatchDivider({required this.label});

  final _OrderBatchLabel label;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 650 || size.height < 750;
    return Padding(
      padding: EdgeInsets.only(top: compact ? 6 : 12, bottom: compact ? 3 : 6),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: BrandColors.glassBorder.withValues(alpha: 0.85),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
            child: Text(
              label.key == 'pending'
                  ? label.title
                  : '${label.title} · ${_formatBatchTime(label.time)}',
              style: TextStyle(
                color: label.initial
                    ? BrandColors.textMuted
                    : BrandColors.accentYellow,
                fontSize: compact ? 10.5 : 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: BrandColors.glassBorder.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonBatch {
  const _PersonBatch({required this.label, required this.items});

  final _OrderBatchLabel label;
  final List<OrderItem> items;
}

class _OrderBatchLabel {
  const _OrderBatchLabel({
    required this.key,
    required this.title,
    required this.time,
    required this.initial,
  });

  final String key;
  final String title;
  final DateTime? time;
  final bool initial;
}

Map<String, _OrderBatchLabel> _buildBatchLabels(
  List<OrderItem> items,
  DateTime? orderCreatedAt,
) {
  final batchTimes = <String, DateTime?>{};
  for (final item in items) {
    final key = _batchKey(item);
    final itemTime = _batchTime(item) ?? item.createdAt ?? orderCreatedAt;
    final current = batchTimes[key];
    if (current == null || (itemTime != null && itemTime.isBefore(current))) {
      batchTimes[key] = itemTime;
    } else {
      batchTimes.putIfAbsent(key, () => itemTime);
    }
  }

  final ordered = batchTimes.entries.toList()
    ..sort((a, b) => _compareBatchEntries(a.key, a.value, b.key, b.value));

  final labels = <String, _OrderBatchLabel>{};
  var sentBatchIndex = 0;
  for (var index = 0; index < ordered.length; index += 1) {
    final entry = ordered[index];
    final pending = entry.key == 'pending';
    final initial = !pending && sentBatchIndex == 0;
    labels[entry.key] = _OrderBatchLabel(
      key: entry.key,
      title: pending
          ? 'Pendiente de enviar'
          : initial
          ? 'Orden inicial'
          : 'Orden extra',
      time: entry.value,
      initial: initial,
    );
    if (!pending) {
      sentBatchIndex += 1;
    }
  }
  return labels;
}

List<_PersonBatch> _buildPersonBatches(
  List<OrderItem> items,
  Map<String, _OrderBatchLabel> labels,
) {
  final grouped = <String, List<OrderItem>>{};
  for (final item in items) {
    grouped.putIfAbsent(_batchKey(item), () => []).add(item);
  }

  final batches =
      grouped.entries.map((entry) {
        final label =
            labels[entry.key] ??
            _OrderBatchLabel(
              key: entry.key,
              title: 'Orden extra',
              time: null,
              initial: false,
            );
        final sortedItems = entry.value.toList()
          ..sort((a, b) {
            final personCompare = a.personNumber.compareTo(b.personNumber);
            if (personCompare != 0) return personCompare;
            final aTime = _itemSortTime(a);
            final bTime = _itemSortTime(b);
            final timeCompare = aTime.compareTo(bTime);
            return timeCompare != 0 ? timeCompare : a.id.compareTo(b.id);
          });
        return _PersonBatch(label: label, items: sortedItems);
      }).toList()..sort((a, b) {
        return _compareBatchEntries(
          a.label.key,
          a.label.time,
          b.label.key,
          b.label.time,
        );
      });

  return batches;
}

String _batchKey(OrderItem item) {
  final batchId = item.kitchenBatchId;
  if (batchId != null && batchId.isNotEmpty) {
    return batchId;
  }
  final sentAt = item.sentToKitchenAt;
  if (sentAt != null) {
    return 'legacy-${sentAt.millisecondsSinceEpoch}';
  }
  return 'pending';
}

DateTime? _batchTime(OrderItem item) {
  return item.kitchenBatchCreatedAt ?? item.sentToKitchenAt ?? item.createdAt;
}

DateTime _itemSortTime(OrderItem item) {
  return item.createdAt ??
      item.sentToKitchenAt ??
      item.kitchenBatchCreatedAt ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

int _compareBatchEntries(
  String aKey,
  DateTime? aTime,
  String bKey,
  DateTime? bTime,
) {
  if (aKey == 'pending' && bKey != 'pending') return 1;
  if (bKey == 'pending' && aKey != 'pending') return -1;
  final aSortTime = aTime ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bSortTime = bTime ?? DateTime.fromMillisecondsSinceEpoch(0);
  final timeCompare = aSortTime.compareTo(bSortTime);
  return timeCompare != 0 ? timeCompare : aKey.compareTo(bKey);
}

String _formatBatchTime(DateTime? time) {
  if (time == null) {
    return DateFormat('h:mm a').format(DateTime.now());
  }
  return DateFormat('h:mm a').format(time);
}

String _personDisplayName({
  required PosOrder order,
  required int person,
  required List<OrderItem> items,
}) {
  final orderName = order.personName(person);
  if (orderName != 'Persona $person') {
    return orderName;
  }
  for (final item in items) {
    final itemName = item.personName.trim();
    if (itemName.isNotEmpty && itemName != 'Persona $person') {
      return itemName;
    }
  }
  return orderName;
}

class _TopOrderActions extends StatelessWidget {
  const _TopOrderActions({
    required this.order,
    required this.items,
    required this.busy,
    required this.itemsLoaded,
    required this.onSendToKitchen,
    required this.onOpenPayment,
    required this.onBlockedPayment,
    required this.onCloseEmptyOrder,
    required this.onCancelOrder,
    required this.canTakeOrders,
    required this.canCharge,
    required this.canCancelOrders,
  });

  final PosOrder? order;
  final List<OrderItem> items;
  final bool busy;
  final bool itemsLoaded;
  final VoidCallback onSendToKitchen;
  final VoidCallback onOpenPayment;
  final VoidCallback onBlockedPayment;
  final VoidCallback onCloseEmptyOrder;
  final VoidCallback onCancelOrder;
  final bool canTakeOrders;
  final bool canCharge;
  final bool canCancelOrders;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 650 || size.height < 750;
    final currentOrder = order;
    final pendingKitchenCount = items
        .where(
          (item) =>
              isActiveKitchenItem(item) &&
              normalizeStatus(item.kitchenStatus) == 'pending',
        )
        .length;
    final hadKitchenSend = items.any(
      (item) =>
          !item.isCancelled &&
          item.sendToKitchen &&
          [
            'sent',
            'cooking',
            'ready',
          ].contains(normalizeStatus(item.kitchenStatus)),
    );
    final canSend = canTakeOrders && !busy && pendingKitchenCount > 0;
    final sendLabel = pendingKitchenCount == 0
        ? 'Cocina al dia'
        : hadKitchenSend
        ? 'Enviar extras'
        : 'Enviar cocina';
    final hasKitchenPending = items.any(isActiveKitchenItem);
    final canCloseEmpty =
        currentOrder != null &&
        currentOrder.status == 'open' &&
        currentOrder.sentToKitchenAt == null &&
        !['sent', 'cooking', 'ready'].contains(currentOrder.kitchenStatus) &&
        items.isEmpty;
    final canAttemptCharge =
        canCharge &&
        currentOrder != null &&
        currentOrder.total > 0 &&
        !busy &&
        itemsLoaded;
    final chargeLabel = hasKitchenPending
        ? 'Hay productos pendientes en cocina'
        : !canCharge
        ? 'No tienes permiso para cobrar'
        : 'Cobrar';
    final canCancelOrder =
        canCancelOrders &&
        currentOrder != null &&
        currentOrder.paymentStatus != 'paid' &&
        currentOrder.status != 'paid' &&
        items.isNotEmpty &&
        !items.any(
          (item) =>
              isActiveOrderItem(item) &&
              normalizeStatus(item.kitchenStatus) == 'ready',
        );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CompactHeaderAction(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back),
              label: 'Volver',
            ),
            Tooltip(
              message: sendLabel,
              child: _CompactHeaderAction(
                onPressed: canSend ? onSendToKitchen : null,
                label: 'Enviar',
                icon: Icon(
                  pendingKitchenCount == 0
                      ? Icons.check_circle_outline
                      : Icons.room_service_outlined,
                ),
              ),
            ),
            if (canCloseEmpty)
              Tooltip(
                message: 'Cerrar mesa vacia',
                child: _CompactHeaderAction(
                  onPressed: busy ? null : onCloseEmptyOrder,
                  icon: const Icon(Icons.close),
                  label: 'Cerrar',
                ),
              ),
            if (canCancelOrder)
              Tooltip(
                message: 'Cancelar ticket',
                child: _CompactHeaderAction(
                  onPressed: busy ? null : onCancelOrder,
                  icon: const Icon(Icons.cancel_outlined),
                  label: 'Cancelar',
                ),
              ),
            Tooltip(
              message: chargeLabel,
              child: _CompactHeaderAction(
                onPressed: !canAttemptCharge
                    ? null
                    : hasKitchenPending
                    ? onBlockedPayment
                    : onOpenPayment,
                icon: const Icon(Icons.point_of_sale_outlined),
                label: 'Cobrar',
                prominent: true,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Volver'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: canSend ? onSendToKitchen : null,
            icon: Icon(
              pendingKitchenCount == 0
                  ? Icons.check_circle_outline
                  : Icons.room_service_outlined,
            ),
            label: Text(sendLabel, overflow: TextOverflow.ellipsis),
          ),
          if (canCloseEmpty) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: busy ? null : onCloseEmptyOrder,
              icon: const Icon(Icons.close),
              label: const Text('Cerrar mesa vacia'),
            ),
          ],
          if (canCancelOrder) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: busy ? null : onCancelOrder,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancelar ticket'),
            ),
          ],
          const SizedBox(width: 8),
          Tooltip(
            message: chargeLabel,
            child: FilledButton.icon(
              onPressed: !canAttemptCharge
                  ? null
                  : hasKitchenPending
                  ? onBlockedPayment
                  : onOpenPayment,
              icon: const Icon(Icons.point_of_sale_outlined),
              label: Text(chargeLabel, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactHeaderAction extends StatelessWidget {
  const _CompactHeaderAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.prominent = false,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final buttonStyle = prominent
        ? FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          )
        : OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTheme.merge(data: const IconThemeData(size: 16), child: icon),
        const SizedBox(width: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: prominent
          ? FilledButton(onPressed: onPressed, style: buttonStyle, child: child)
          : OutlinedButton(
              onPressed: onPressed,
              style: buttonStyle,
              child: child,
            ),
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({
    required this.item,
    required this.onQtyChanged,
    required this.onCancel,
    required this.canEditOrder,
  });

  final OrderItem item;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onCancel;
  final bool canEditOrder;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 650 || size.height < 750;
    final cancelled = item.isCancelled;
    final cancelReason = getItemCancelReason(item);
    final locked = item.kitchenStatus == 'ready';
    final canRequestCancel = [
      'sent',
      'cooking',
      'cancel_requested',
    ].contains(item.kitchenStatus);
    final cancelButtonLabel = item.kitchenStatus == 'pending'
        ? 'Cancelar'
        : canRequestCancel
        ? 'Solicitar cancelacion'
        : 'Cancelar';
    final editable =
        canEditOrder &&
        !cancelled &&
        !locked &&
        !['sent', 'cooking'].contains(item.kitchenStatus) &&
        item.paymentStatus != 'paid';
    final cancellable =
        canEditOrder &&
        !cancelled &&
        item.paymentStatus != 'paid' &&
        !item.hasCancellationRequested &&
        (editable || canRequestCancel);
    void blockedEdit() {
      showAppSnackBar(
        context,
        'Este producto ya fue servido por cocina y no puede cancelarse.',
        type: AppSnackBarType.warning,
      );
    }

    final textDecoration = cancelled ? TextDecoration.lineThrough : null;
    final contentColor = cancelled
        ? BrandColors.textMuted.withValues(alpha: 0.72)
        : BrandColors.textPrimary;

    return Opacity(
      opacity: cancelled ? 0.58 : 1,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 3 : 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatOrderItemDisplayName(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: contentColor,
                      decoration: textDecoration,
                      decorationThickness: 2,
                      fontSize: compact ? 12.5 : null,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (!cancelled &&
                      !locked &&
                      !item.hasCancellationRequested) ...[
                    SizedBox(height: compact ? 3 : 5),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: StatusBadge(
                        style: kitchenStatusStyle(item.kitchenStatus),
                      ),
                    ),
                  ],
                  if (cancelled)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          const StatusBadge(
                            style: StatusStyle(
                              label: 'Cancelado',
                              color: BrandColors.danger,
                              background: Color(0x1FFF5A5A),
                            ),
                          ),
                          if (cancelReason.isNotEmpty)
                            Text(
                              'Motivo: $cancelReason',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: BrandColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (locked && !cancelled)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: StatusBadge(
                        style: StatusStyle(
                          label: 'Servido',
                          color: BrandColors.success,
                          background: Color(0x1F55D98B),
                        ),
                      ),
                    ),
                  if (item.hasCancellationRequested)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: StatusBadge(
                        style: StatusStyle(
                          label: 'Cancelacion solicitada',
                          color: BrandColors.accentYellow,
                          background: Color(0x1FFFD54A),
                        ),
                      ),
                    ),
                  if (item.wasCancellationRejected)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: StatusBadge(
                        style: StatusStyle(
                          label: 'Cancelacion rechazada por cocina',
                          color: BrandColors.danger,
                          background: Color(0x1FFF5A5A),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Menos',
              iconSize: compact ? 18 : 24,
              visualDensity: compact ? VisualDensity.compact : null,
              onPressed: cancelled
                  ? null
                  : editable
                  ? () => onQtyChanged(item.qty - 1)
                  : locked
                  ? blockedEdit
                  : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: compact ? 20 : 34,
              child: Text(
                '${item.qty}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: contentColor,
                  decoration: textDecoration,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Mas',
              iconSize: compact ? 18 : 24,
              visualDensity: compact ? VisualDensity.compact : null,
              onPressed: cancelled
                  ? null
                  : editable
                  ? () => onQtyChanged(item.qty + 1)
                  : locked
                  ? blockedEdit
                  : null,
              icon: const Icon(Icons.add),
            ),
            SizedBox(width: compact ? 4 : 8),
            SizedBox(
              width: compact ? 58 : 86,
              child: MoneyText(
                value: item.total,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: cancelled ? BrandColors.textMuted : null,
                  decoration: textDecoration,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              tooltip: cancelButtonLabel,
              iconSize: compact ? 18 : 24,
              visualDensity: compact ? VisualDensity.compact : null,
              onPressed: cancellable
                  ? onCancel
                  : locked
                  ? blockedEdit
                  : null,
              icon: Icon(
                canRequestCancel
                    ? Icons.assignment_late_outlined
                    : Icons.cancel_outlined,
                color: BrandColors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductMenu extends StatelessWidget {
  const _ProductMenu({
    required this.productsStream,
    required this.categoriesStream,
    required this.stockOutsStream,
    required this.selectedCategory,
    required this.platformId,
    required this.onCategoryChanged,
    required this.onAddProduct,
    required this.onMarkProductStockOut,
    required this.onClearProductStockOut,
    required this.canAddProducts,
    required this.onBlockedAddProduct,
  });

  final Stream<List<Product>> productsStream;
  final Stream<List<ProductCategory>> categoriesStream;
  final Stream<Map<String, ProductStockOutRow>> stockOutsStream;
  final String selectedCategory;
  final String? platformId;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<Product> onAddProduct;
  final Future<void> Function(Product product) onMarkProductStockOut;
  final Future<void> Function(Product product) onClearProductStockOut;
  final bool canAddProducts;
  final VoidCallback onBlockedAddProduct;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 650 || size.height < 750;
    return StreamBuilder<List<ProductCategory>>(
      stream: categoriesStream,
      builder: (context, categoriesSnapshot) {
        final catalogCategories =
            categoriesSnapshot.data ?? const <ProductCategory>[];
        return StreamBuilder<List<Product>>(
          stream: productsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return EmptyState(
                icon: Icons.error_outline,
                title: 'No se pudieron cargar los productos',
                message: '${snapshot.error}',
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingPanel(message: 'Cargando productos...');
            }

            final products = snapshot.data ?? [];
            if (products.isEmpty) {
              return const EmptyState(
                icon: Icons.restaurant_menu,
                title: 'No hay productos activos',
                message:
                    'Agrega o activa productos desde el catalogo de Admin.',
              );
            }

            final categories = _menuCategories(products, catalogCategories);
            if (categories.isEmpty) {
              return const EmptyState(
                icon: Icons.category_outlined,
                title: 'Sin categorias',
                message: 'Asigna categoria a los productos activos.',
              );
            }
            final effectiveCategory =
                categories.any((category) => category.id == selectedCategory)
                ? selectedCategory
                : categories.first.id;
            if (effectiveCategory != selectedCategory) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onCategoryChanged(effectiveCategory);
              });
            }
            final visibleProducts =
                products
                    .where((product) => product.categoryId == effectiveCategory)
                    .toList()
                  ..sort(_compareProductsForMenu);
            final currentCategory = categories.firstWhere(
              (category) => category.id == effectiveCategory,
              orElse: () => categories.first,
            );

            return StreamBuilder<Map<String, ProductStockOutRow>>(
              stream: stockOutsStream,
              builder: (context, stockOutSnapshot) {
                final stockOuts =
                    stockOutSnapshot.data ??
                    const <String, ProductStockOutRow>{};
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 8 : 18,
                        compact ? 7 : 18,
                        compact ? 8 : 18,
                        compact ? 2 : 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              currentCategory.name,
                              style: TextStyle(
                                fontSize: compact ? 16 : 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            '${visibleProducts.length} productos',
                            style: TextStyle(
                              color: BrandColors.textMuted,
                              fontSize: compact ? 11 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: compact ? 34 : 54,
                      child: ListView.separated(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 8 : 18,
                        ),
                        scrollDirection: Axis.horizontal,
                        itemCount: categories.length,
                        separatorBuilder: (_, _) =>
                            SizedBox(width: compact ? 6 : 10),
                        itemBuilder: (context, index) {
                          final category = categories[index];
                          final accent = categoryColorFromModel(category);
                          final selected = effectiveCategory == category.id;
                          return ChoiceChip(
                            visualDensity: compact
                                ? VisualDensity.compact
                                : null,
                            selected: selected,
                            onSelected: (_) => onCategoryChanged(category.id),
                            backgroundColor: accent.withValues(alpha: 0.08),
                            selectedColor: accent.withValues(alpha: 0.22),
                            side: BorderSide(
                              color: accent.withValues(
                                alpha: selected ? 0.72 : 0.32,
                              ),
                            ),
                            labelStyle: TextStyle(
                              color: selected ? accent : BrandColors.textMuted,
                              fontWeight: selected
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                            ),
                            label: Text(category.name),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 1100
                              ? 5
                              : constraints.maxWidth >= 760
                              ? 4
                              : constraints.maxWidth >= 430
                              ? 3
                              : constraints.maxWidth >= 300
                              ? 2
                              : 1;

                          return GridView.builder(
                            padding: EdgeInsets.all(compact ? 8 : 18),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: compact ? 7 : 12,
                                  mainAxisSpacing: compact ? 7 : 12,
                                  childAspectRatio: compact ? 2.15 : 1.9,
                                ),
                            itemCount: visibleProducts.length,
                            itemBuilder: (context, index) {
                              final product = visibleProducts[index];
                              final category = findCategoryById(
                                categories,
                                product.categoryId,
                              );
                              final stockOut = stockOuts[product.id];
                              final stockedOut = stockOut != null;
                              return _ProductTile(
                                key: ValueKey('product-${product.id}'),
                                product: product,
                                category: category,
                                platformId: platformId,
                                compact: compact,
                                stockedOut: stockedOut,
                                stockOutTimeLabel:
                                    stockOut?.soldOutTimeLabel ?? '',
                                onTap: canAddProducts
                                    ? () {
                                        if (stockedOut) {
                                          showAppSnackBar(
                                            context,
                                            'Producto agotado hasta cierre de cocina.',
                                          );
                                          return;
                                        }
                                        onAddProduct(product);
                                      }
                                    : onBlockedAddProduct,
                                onLongPressCompleted: canAddProducts
                                    ? () => _toggleStockOut(
                                        context,
                                        product,
                                        stockedOut,
                                      )
                                    : null,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _toggleStockOut(
    BuildContext context,
    Product product,
    bool stockedOut,
  ) async {
    try {
      if (stockedOut) {
        await onClearProductStockOut(product);
        if (!context.mounted) return;
        showAppSnackBar(
          context,
          'Producto disponible nuevamente.',
          type: AppSnackBarType.success,
        );
      } else {
        await onMarkProductStockOut(product);
        if (!context.mounted) return;
        showAppSnackBar(
          context,
          'Producto marcado como agotado hasta cierre de cocina.',
          type: AppSnackBarType.warning,
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
        type: AppSnackBarType.error,
      );
    }
  }
}

List<ProductCategory> _menuCategories(
  List<Product> products,
  List<ProductCategory> catalogCategories,
) {
  final productCategoryIds = products
      .map((product) => product.categoryId)
      .where((id) => id.trim().isNotEmpty)
      .toSet();
  final categories = <ProductCategory>[
    for (final category in catalogCategories)
      if (productCategoryIds.contains(category.id)) category,
  ];
  final knownIds = categories.map((category) => category.id).toSet();
  for (final product in products) {
    if (knownIds.contains(product.categoryId)) continue;
    knownIds.add(product.categoryId);
    categories.add(
      ProductCategory(
        id: product.categoryId,
        name: product.categoryName,
        normalizedName: normalizeCategory(product.categoryName),
        active: true,
        sortOrder: categoryRank(product.categoryName),
      ),
    );
  }
  categories.sort((a, b) {
    final sortCompare = a.sortOrder.compareTo(b.sortOrder);
    if (sortCompare != 0) return sortCompare;
    return normalizeCategory(a.name).compareTo(normalizeCategory(b.name));
  });
  return categories;
}

class _ProductTile extends StatefulWidget {
  const _ProductTile({
    super.key,
    required this.product,
    required this.category,
    required this.platformId,
    required this.compact,
    required this.stockedOut,
    required this.stockOutTimeLabel,
    required this.onTap,
    this.onLongPressCompleted,
  });

  final Product product;
  final ProductCategory? category;
  final String? platformId;
  final bool compact;
  final bool stockedOut;
  final String stockOutTimeLabel;
  final VoidCallback onTap;
  final Future<void> Function()? onLongPressCompleted;

  @override
  State<_ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends State<_ProductTile>
    with SingleTickerProviderStateMixin {
  Timer? _stockOutTimer;
  late final AnimationController _holdController;
  bool _completingLongPress = false;
  bool _suppressNextTap = false;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  void dispose() {
    _stockOutTimer?.cancel();
    _holdController.dispose();
    super.dispose();
  }

  void _startStockOutHold() {
    if (widget.onLongPressCompleted == null || _completingLongPress) return;
    _stockOutTimer?.cancel();
    _holdController
      ..reset()
      ..forward();
    _stockOutTimer = Timer(const Duration(seconds: 4), () async {
      if (!mounted || _completingLongPress) return;
      setState(() {
        _completingLongPress = true;
        _suppressNextTap = true;
      });
      await widget.onLongPressCompleted?.call();
      if (!mounted) return;
      setState(() => _completingLongPress = false);
      _holdController.reset();
    });
  }

  void _cancelStockOutHold() {
    _stockOutTimer?.cancel();
    if (!_completingLongPress) {
      _holdController.reset();
    }
  }

  void _handleTap() {
    if (_suppressNextTap) {
      _suppressNextTap = false;
      return;
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final compact = widget.compact;
    final accent = widget.category == null
        ? categoryAccent(
            categoryId: product.categoryId,
            categoryName: product.categoryName,
          )
        : categoryColorFromModel(widget.category!);
    final fadedAccent = widget.stockedOut ? BrandColors.textMuted : accent;
    return GestureDetector(
      onTapDown: (_) => _startStockOutHold(),
      onTapUp: (_) => _cancelStockOutHold(),
      onTapCancel: _cancelStockOutHold,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: widget.stockedOut ? 0.58 : 1,
        child: Stack(
          children: [
            GlassCard(
              onTap: _handleTap,
              padding: EdgeInsets.all(compact ? 7 : 12),
              accent: fadedAccent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedBuilder(
                    animation: _holdController,
                    builder: (context, child) {
                      return LinearProgressIndicator(
                        minHeight: compact ? 2 : 3,
                        value: _holdController.value,
                        backgroundColor: fadedAccent.withValues(alpha: 0.20),
                        valueColor: AlwaysStoppedAnimation<Color>(fadedAccent),
                      );
                    },
                  ),
                  SizedBox(height: compact ? 5 : 7),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.categoryName.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: fadedAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(
                        widget.stockedOut
                            ? Icons.block_outlined
                            : Icons.add_circle_outline,
                        color: fadedAccent,
                        size: compact ? 16 : 22,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.stockedOut
                          ? BrandColors.textMuted
                          : BrandColors.textPrimary,
                      fontSize: compact ? 12.5 : 16,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    ),
                  ),
                  SizedBox(height: compact ? 2 : 6),
                  MoneyText(
                    value: product.priceForPlatform(widget.platformId),
                    style: TextStyle(
                      color: widget.stockedOut
                          ? BrandColors.textMuted
                          : BrandColors.accentYellow,
                      fontSize: compact ? 12.5 : 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.stockedOut)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.black.withValues(alpha: 0.20),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: BrandColors.danger.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'AGOTADO',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                          if (widget.stockOutTimeLabel.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              'desde ${widget.stockOutTimeLabel}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

int _compareProductsForMenu(Product a, Product b) {
  final sortCompare = a.sortOrder.compareTo(b.sortOrder);
  if (sortCompare != 0) {
    return sortCompare;
  }
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
