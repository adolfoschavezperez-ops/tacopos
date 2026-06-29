import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/product.dart';
import '../../services/taco_pos_repository.dart';
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
  });

  final String orderId;
  final String tableName;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  final _repository = TacoPosRepository();
  late Stream<PosOrder?> _orderStream;
  late Stream<List<OrderItem>> _itemsStream;
  late final Stream<List<Product>> _productsStream;
  int _selectedPerson = 1;
  int _personCount = 1;
  String _selectedCategory = 'Todos';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bindOrderStreams();
    _productsStream = _repository.watchProducts(activeOnly: true);
  }

  @override
  void didUpdateWidget(covariant OrderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) {
      _bindOrderStreams();
    }
  }

  void _bindOrderStreams() {
    _orderStream = _repository.watchOrder(widget.orderId);
    _itemsStream = _repository.watchOrderItems(widget.orderId);
  }

  Future<void> _sendToKitchen() async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      final sentCount = await _repository.sendOrderToKitchen(widget.orderId);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 900),
          content: Text(
            sentCount == 0
                ? 'No hay productos de cocina para enviar.'
                : 'Comanda enviada a cocina.',
          ),
        ),
      );

      if (sentCount > 0) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar la comanda: $error')),
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
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PaymentScreen(orderId: widget.orderId)),
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

  void _addPerson() {
    setState(() {
      _personCount += 1;
      _selectedPerson = _personCount;
    });
  }

  Future<void> _renamePerson(int personNumber, String currentName) async {
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
        orderId: widget.orderId,
        personNumber: personNumber,
        name: newName,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo renombrar la persona: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PosOrder?>(
      stream: _orderStream,
      builder: (context, orderSnapshot) {
        final order = orderSnapshot.data;

        return BrandedScaffold(
          title: order?.tableName ?? widget.tableName,
          actions: [
            StreamBuilder<List<OrderItem>>(
              stream: _itemsStream,
              initialData: const [],
              builder: (context, itemSnapshot) {
                return _TopOrderActions(
                  order: order,
                  items: itemSnapshot.data ?? const [],
                  busy: _busy,
                  itemsLoaded: itemSnapshot.hasData,
                  onSendToKitchen: _sendToKitchen,
                  onOpenPayment: _openPayment,
                  onBlockedPayment: _showKitchenPendingDialog,
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

  Widget _buildBody(AsyncSnapshot<PosOrder?> orderSnapshot) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        final selectedPerson = _selectedPerson < 1 ? 1 : _selectedPerson;
        final summary = _OrderSummaryLoader(
          orderSnapshot: orderSnapshot,
          itemsStream: _itemsStream,
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
          },
          onAddPerson: _addPerson,
          onRenamePerson: _renamePerson,
          onQtyChanged: (item, qty) => _repository.updateItemQty(
            orderId: widget.orderId,
            item: item,
            qty: qty,
          ),
          onDelete: (item) =>
              _repository.deleteItem(orderId: widget.orderId, itemId: item.id),
        );
        final menu = _ProductMenu(
          productsStream: _productsStream,
          selectedCategory: _selectedCategory,
          onCategoryChanged: (category) {
            setState(() {
              _selectedCategory = category;
            });
          },
          onAddProduct: (product) => _repository.addProductToOrder(
            orderId: widget.orderId,
            product: product,
            personNumber: selectedPerson,
          ),
        );

        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RepaintBoundary(
                  child: SizedBox(
                    width: constraints.maxWidth * 0.46,
                    child: GlassPanel(
                      padding: EdgeInsets.zero,
                      blur: 8,
                      child: summary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
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

        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            GlassPanel(
              padding: EdgeInsets.zero,
              blur: 8,
              child: SizedBox(height: 560, child: summary),
            ),
            const SizedBox(height: 16),
            GlassPanel(
              padding: EdgeInsets.zero,
              blur: 8,
              child: SizedBox(height: 640, child: menu),
            ),
          ],
        );
      },
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
    required this.orderSnapshot,
    required this.itemsStream,
    required this.personCount,
    required this.selectedPerson,
    required this.onPersonCountChanged,
    required this.onSelectPerson,
    required this.onAddPerson,
    required this.onRenamePerson,
    required this.onQtyChanged,
    required this.onDelete,
  });

  final AsyncSnapshot<PosOrder?> orderSnapshot;
  final Stream<List<OrderItem>> itemsStream;
  final int personCount;
  final int selectedPerson;
  final ValueChanged<int> onPersonCountChanged;
  final ValueChanged<int> onSelectPerson;
  final VoidCallback onAddPerson;
  final void Function(int personNumber, String currentName) onRenamePerson;
  final void Function(OrderItem item, int qty) onQtyChanged;
  final ValueChanged<OrderItem> onDelete;

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

    return StreamBuilder<List<OrderItem>>(
      stream: itemsStream,
      initialData: const [],
      builder: (context, itemsSnapshot) {
        if (itemsSnapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudieron cargar los articulos',
            message: '${itemsSnapshot.error}',
          );
        }

        final items = itemsSnapshot.data ?? [];
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
        final nextSelectedPerson = selectedPerson
            .clamp(1, nextPersonCount)
            .toInt();

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
          onDelete: onDelete,
        );
      },
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
    required this.onDelete,
  });

  final PosOrder order;
  final List<OrderItem> items;
  final int personCount;
  final int selectedPerson;
  final ValueChanged<int> onSelectPerson;
  final VoidCallback onAddPerson;
  final void Function(int personNumber, String currentName) onRenamePerson;
  final void Function(OrderItem item, int qty) onQtyChanged;
  final ValueChanged<OrderItem> onDelete;

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
    final grouped = <int, List<OrderItem>>{};
    for (final item in widget.items) {
      grouped.putIfAbsent(item.personNumber, () => []).add(item);
    }
    final batchLabels = _buildBatchLabels(widget.items, widget.order.createdAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      title: widget.order.tableName,
                      subtitle: 'Orden por personas',
                      trailing: StatusBadge(
                        style: kitchenStatusStyle(widget.order.kitchenStatus),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'TOTAL',
                    style: TextStyle(
                      color: BrandColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  MoneyText(
                    value: widget.order.total,
                    style: const TextStyle(
                      color: BrandColors.accentYellow,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: 58,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            scrollDirection: Axis.horizontal,
            itemCount: widget.personCount + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == widget.personCount) {
                return OutlinedButton.icon(
                  onPressed: widget.onAddPerson,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Persona'),
                );
              }

              final person = index + 1;
              final personName = _personDisplayName(
                order: widget.order,
                person: person,
                items: grouped[person] ?? const [],
              );
              return ChoiceChip(
                selected: widget.selectedPerson == person,
                onSelected: (_) => widget.onSelectPerson(person),
                label: Text(personName),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: widget.items.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long,
                  title: 'Sin articulos agregados',
                  message: 'Elige una persona y agrega productos del menu.',
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                  itemCount: widget.personCount,
                  itemBuilder: (context, index) {
                    final person = index + 1;
                    final personItems = grouped[person] ?? [];
                    final subtotal = personItems.fold<double>(
                      0,
                      (sum, item) => sum + item.total,
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
                      onDelete: widget.onDelete,
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
    required this.onDelete,
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
  final ValueChanged<OrderItem> onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        onTap: onSelect,
        selected: selected,
        accent: BrandColors.accentYellow,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    personName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Renombrar persona',
                  onPressed: onRename,
                  icon: const Icon(Icons.edit_outlined),
                ),
                const SizedBox(width: 4),
                MoneyText(
                  value: subtotal,
                  style: const TextStyle(
                    color: BrandColors.accentYellow,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                      onDelete: () => onDelete(item),
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
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: BrandColors.glassBorder.withValues(alpha: 0.85),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '${label.title} · ${_formatBatchTime(label.time)}',
              style: TextStyle(
                color: label.initial
                    ? BrandColors.textMuted
                    : BrandColors.accentYellow,
                fontSize: 12,
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
    final itemTime = _batchTime(item) ?? orderCreatedAt;
    final current = batchTimes[key];
    if (current == null || (itemTime != null && itemTime.isBefore(current))) {
      batchTimes[key] = itemTime;
    } else {
      batchTimes.putIfAbsent(key, () => itemTime);
    }
  }

  final ordered = batchTimes.entries.toList()
    ..sort((a, b) {
      final aTime = a.value ?? DateTime.now();
      final bTime = b.value ?? DateTime.now();
      return aTime.compareTo(bTime);
    });

  final labels = <String, _OrderBatchLabel>{};
  for (var index = 0; index < ordered.length; index += 1) {
    final entry = ordered[index];
    final initial = index == 0;
    labels[entry.key] = _OrderBatchLabel(
      key: entry.key,
      title: initial ? 'Orden inicial' : 'Orden extra',
      time: entry.value,
      initial: initial,
    );
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
            final aTime =
                _batchTime(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime =
                _batchTime(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
            final timeCompare = aTime.compareTo(bTime);
            return timeCompare != 0
                ? timeCompare
                : a.productName.compareTo(b.productName);
          });
        return _PersonBatch(label: label, items: sortedItems);
      }).toList()..sort((a, b) {
        final aTime = a.label.time ?? DateTime.now();
        final bTime = b.label.time ?? DateTime.now();
        return aTime.compareTo(bTime);
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
  return item.sentToKitchenAt ?? item.createdAt ?? item.updatedAt;
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
  });

  final PosOrder? order;
  final List<OrderItem> items;
  final bool busy;
  final bool itemsLoaded;
  final VoidCallback onSendToKitchen;
  final VoidCallback onOpenPayment;
  final VoidCallback onBlockedPayment;

  @override
  Widget build(BuildContext context) {
    final currentOrder = order;
    final pendingKitchenCount = items
        .where((item) => item.sendToKitchen && item.kitchenStatus == 'pending')
        .length;
    final hadKitchenSend = items.any(
      (item) =>
          item.sendToKitchen &&
          ['sent', 'cooking', 'ready'].contains(item.kitchenStatus),
    );
    final canSend = !busy && pendingKitchenCount > 0;
    final sendLabel = pendingKitchenCount == 0
        ? 'Cocina al dia'
        : hadKitchenSend
        ? 'Enviar extras'
        : 'Enviar cocina';
    final hasKitchenPending = items.any(
      (item) =>
          item.sendToKitchen &&
          ['pending', 'sent', 'cooking'].contains(item.kitchenStatus),
    );
    final canAttemptCharge =
        currentOrder != null && currentOrder.total > 0 && !busy && itemsLoaded;
    final chargeLabel = hasKitchenPending
        ? 'Hay productos pendientes en cocina'
        : 'Cobrar';

    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            onPressed: canSend ? onSendToKitchen : null,
            icon: Icon(
              pendingKitchenCount == 0
                  ? Icons.check_circle_outline
                  : Icons.room_service_outlined,
            ),
            label: Text(sendLabel, overflow: TextOverflow.ellipsis),
          ),
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

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({
    required this.item,
    required this.onQtyChanged,
    required this.onDelete,
  });

  final OrderItem item;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.category} | ${item.kitchenStatus}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BrandColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Menos',
            onPressed: () => onQtyChanged(item.qty - 1),
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '${item.qty}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Mas',
            onPressed: () => onQtyChanged(item.qty + 1),
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 86,
            child: MoneyText(
              value: item.total,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, color: BrandColors.danger),
          ),
        ],
      ),
    );
  }
}

class _ProductMenu extends StatelessWidget {
  const _ProductMenu({
    required this.productsStream,
    required this.selectedCategory,
    required this.onCategoryChanged,
    required this.onAddProduct,
  });

  final Stream<List<Product>> productsStream;
  final String selectedCategory;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<Product> onAddProduct;

  @override
  Widget build(BuildContext context) {
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
            message: 'Agrega o activa productos desde el catalogo de Admin.',
          );
        }

        final categories = [
          'Todos',
          ...{for (final product in products) product.category},
        ];
        final visibleProducts = selectedCategory == 'Todos'
            ? products
            : products
                  .where((product) => product.category == selectedCategory)
                  .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Menu',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '${visibleProducts.length} productos',
                    style: const TextStyle(color: BrandColors.textMuted),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 54,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return ChoiceChip(
                    selected: selectedCategory == category,
                    onSelected: (_) => onCategoryChanged(category),
                    label: Text(category),
                  );
                },
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 700 ? 3 : 2;

                  return GridView.builder(
                    padding: const EdgeInsets.all(18),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.45,
                    ),
                    itemCount: visibleProducts.length,
                    itemBuilder: (context, index) {
                      final product = visibleProducts[index];
                      return _ProductTile(
                        key: ValueKey('product-${product.id}'),
                        product: product,
                        onTap: () => onAddProduct(product),
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
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({super.key, required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      accent: BrandColors.accentOrange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  product.category.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BrandColors.accentOrange,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(
                Icons.add_circle_outline,
                color: BrandColors.accentYellow,
              ),
            ],
          ),
          const Spacer(),
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          MoneyText(
            value: product.price,
            style: const TextStyle(
              color: BrandColors.accentYellow,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
