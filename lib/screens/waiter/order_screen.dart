import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/product.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';
import '../../widgets/status_badge.dart';

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
  int _selectedPerson = 1;
  int _personCount = 1;
  String _selectedCategory = 'Todos';
  bool _busy = false;

  Future<void> _sendToKitchen() async {
    await _runAction(
      action: () => _repository.sendOrderToKitchen(widget.orderId),
      success: 'Orden enviada a cocina.',
    );
  }

  Future<void> _markPaid(PosOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cobrar mesa'),
        content: Text(
          'Se marcara ${order.tableName} como pagada por un total de '
          r'$'
          '${order.total.toStringAsFixed(2)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Marcar pagada'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await _runAction(
      action: () => _repository.markOrderPaid(widget.orderId),
      success: 'Orden pagada y mesa liberada.',
      popAfter: true,
    );
  }

  Future<void> _runAction({
    required Future<void> Function() action,
    required String success,
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

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      if (popAfter) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo completar la accion: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _addPerson() {
    setState(() {
      _personCount += 1;
      _selectedPerson = _personCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PosOrder?>(
      stream: _repository.watchOrder(widget.orderId),
      builder: (context, orderSnapshot) {
        final order = orderSnapshot.data;

        return BrandedScaffold(
          title: order?.tableName ?? widget.tableName,
          actions: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Enviar a cocina',
              onPressed: _busy ? null : _sendToKitchen,
              icon: const Icon(Icons.outdoor_grill),
            ),
            IconButton(
              tooltip: 'Cobrar',
              onPressed: order == null || _busy ? null : () => _markPaid(order),
              icon: const Icon(Icons.payments),
            ),
          ],
          body: _buildBody(orderSnapshot),
        );
      },
    );
  }

  Widget _buildBody(AsyncSnapshot<PosOrder?> orderSnapshot) {
    if (orderSnapshot.connectionState == ConnectionState.waiting) {
      return const LoadingPanel(message: 'Abriendo orden...');
    }

    if (orderSnapshot.hasError) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'No se pudo cargar la orden',
        message: '${orderSnapshot.error}',
      );
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
      stream: _repository.watchOrderItems(widget.orderId),
      builder: (context, itemsSnapshot) {
        if (itemsSnapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPanel(message: 'Cargando productos...');
        }

        final items = itemsSnapshot.data ?? [];
        final maxPerson = items.fold<int>(
          _personCount,
          (max, item) => item.personNumber > max ? item.personNumber : max,
        );
        _personCount = maxPerson < 1 ? 1 : maxPerson;
        if (_selectedPerson > _personCount) {
          _selectedPerson = _personCount;
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            final summary = _OrderSummary(
              order: order,
              items: items,
              personCount: _personCount,
              selectedPerson: _selectedPerson,
              onSelectPerson: (person) {
                setState(() {
                  _selectedPerson = person;
                });
              },
              onAddPerson: _addPerson,
              onQtyChanged: (item, qty) => _repository.updateItemQty(
                orderId: widget.orderId,
                item: item,
                qty: qty,
              ),
              onDelete: (item) => _repository.deleteItem(
                orderId: widget.orderId,
                itemId: item.id,
              ),
            );
            final menu = _ProductMenu(
              selectedCategory: _selectedCategory,
              onCategoryChanged: (category) {
                setState(() {
                  _selectedCategory = category;
                });
              },
              onAddProduct: (product) => _repository.addProductToOrder(
                orderId: widget.orderId,
                product: product,
                personNumber: _selectedPerson,
              ),
            );

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: constraints.maxWidth * 0.48, child: summary),
                  const VerticalDivider(width: 1),
                  Expanded(child: menu),
                ],
              );
            }

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                SizedBox(height: 560, child: summary),
                const Divider(height: 1),
                SizedBox(height: 640, child: menu),
              ],
            );
          },
        );
      },
    );
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({
    required this.order,
    required this.items,
    required this.personCount,
    required this.selectedPerson,
    required this.onSelectPerson,
    required this.onAddPerson,
    required this.onQtyChanged,
    required this.onDelete,
  });

  final PosOrder order;
  final List<OrderItem> items;
  final int personCount;
  final int selectedPerson;
  final ValueChanged<int> onSelectPerson;
  final VoidCallback onAddPerson;
  final void Function(OrderItem item, int qty) onQtyChanged;
  final ValueChanged<OrderItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final grouped = <int, List<OrderItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.personNumber, () => []).add(item);
    }

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
                    Text(
                      order.tableName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StatusBadge(style: kitchenStatusStyle(order.kitchenStatus)),
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
                      color: BrandColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  MoneyText(
                    value: order.total,
                    style: const TextStyle(
                      color: BrandColors.yellow,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
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
            itemCount: personCount + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == personCount) {
                return OutlinedButton.icon(
                  onPressed: onAddPerson,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Persona'),
                );
              }

              final person = index + 1;
              return ChoiceChip(
                selected: selectedPerson == person,
                onSelected: (_) => onSelectPerson(person),
                label: Text('Persona $person'),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long,
                  title: 'Orden vacia',
                  message: 'Elige una persona y agrega productos del menu.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                  itemCount: personCount,
                  itemBuilder: (context, index) {
                    final person = index + 1;
                    final personItems = grouped[person] ?? [];
                    final subtotal = personItems.fold<double>(
                      0,
                      (sum, item) => sum + item.total,
                    );

                    return _PersonItemsCard(
                      person: person,
                      selected: selectedPerson == person,
                      items: personItems,
                      subtotal: subtotal,
                      onSelect: () => onSelectPerson(person),
                      onQtyChanged: onQtyChanged,
                      onDelete: onDelete,
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
    required this.person,
    required this.selected,
    required this.items,
    required this.subtotal,
    required this.onSelect,
    required this.onQtyChanged,
    required this.onDelete,
  });

  final int person;
  final bool selected;
  final List<OrderItem> items;
  final double subtotal;
  final VoidCallback onSelect;
  final void Function(OrderItem item, int qty) onQtyChanged;
  final ValueChanged<OrderItem> onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: selected ? const Color(0xFF24210F) : BrandColors.surface,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Persona $person',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  MoneyText(
                    value: subtotal,
                    style: const TextStyle(
                      color: BrandColors.yellow,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Text(
                  'Sin productos',
                  style: TextStyle(color: BrandColors.muted),
                )
              else
                ...items.map(
                  (item) => _OrderItemRow(
                    item: item,
                    onQtyChanged: (qty) => onQtyChanged(item, qty),
                    onDelete: () => onDelete(item),
                  ),
                ),
            ],
          ),
        ),
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
                    color: BrandColors.muted,
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
    required this.selectedCategory,
    required this.onCategoryChanged,
    required this.onAddProduct,
  });

  final String selectedCategory;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<Product> onAddProduct;

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();

    return StreamBuilder<List<Product>>(
      stream: repository.watchProducts(activeOnly: true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPanel(message: 'Cargando menu...');
        }

        final products = snapshot.data ?? [];
        if (products.isEmpty) {
          return const EmptyState(
            icon: Icons.restaurant_menu,
            title: 'Menu vacio',
            message: 'Crea datos demo o agrega productos en Admin.',
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
                    style: const TextStyle(
                      color: BrandColors.muted,
                      fontWeight: FontWeight.w800,
                    ),
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
  const _ProductTile({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                        color: BrandColors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Icon(Icons.add_circle, color: BrandColors.yellow),
                ],
              ),
              const Spacer(),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 8),
              MoneyText(
                value: product.price,
                style: const TextStyle(
                  color: BrandColors.yellow,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
