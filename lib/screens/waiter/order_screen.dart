import 'package:flutter/material.dart';

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
  late final Stream<List<OrderItem>> _itemsStream;
  late final Stream<List<Product>> _productsStream;
  int _selectedPerson = 1;
  int _personCount = 1;
  String _selectedCategory = 'Todos';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _itemsStream = _repository.watchOrderItems(widget.orderId);
    _productsStream = _repository.watchProducts(activeOnly: true);
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
          content: Text(
            sentCount == 0
                ? 'No hay productos de cocina para enviar.'
                : 'Comanda enviada a cocina.',
          ),
        ),
      );
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
      stream: _itemsStream,
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
              onSendToKitchen: _busy ? null : _sendToKitchen,
              onOpenPayment: _busy ? null : _openPayment,
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
                personNumber: _selectedPerson,
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
    required this.onSendToKitchen,
    required this.onOpenPayment,
  });

  final PosOrder order;
  final List<OrderItem> items;
  final int personCount;
  final int selectedPerson;
  final ValueChanged<int> onSelectPerson;
  final VoidCallback onAddPerson;
  final void Function(OrderItem item, int qty) onQtyChanged;
  final ValueChanged<OrderItem> onDelete;
  final VoidCallback? onSendToKitchen;
  final VoidCallback? onOpenPayment;

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
                    SectionHeader(
                      title: order.tableName,
                      subtitle: 'Orden por personas',
                      trailing: StatusBadge(
                        style: kitchenStatusStyle(order.kitchenStatus),
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
                    value: order.total,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: _OrderActionPanel(
            order: order,
            onSendToKitchen: onSendToKitchen,
            onOpenPayment: onOpenPayment,
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
                      key: ValueKey('person-$person'),
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
    super.key,
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
                    'Persona $person',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
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
    );
  }
}

class _OrderActionPanel extends StatelessWidget {
  const _OrderActionPanel({
    required this.order,
    required this.onSendToKitchen,
    required this.onOpenPayment,
  });

  final PosOrder order;
  final VoidCallback? onSendToKitchen;
  final VoidCallback? onOpenPayment;

  @override
  Widget build(BuildContext context) {
    final kitchenLabel = switch (order.kitchenStatus) {
      'sent' => 'Comanda enviada',
      'cooking' => 'En preparacion',
      'ready' => 'Lista para cobrar',
      'not_required' => 'Sin cocina',
      _ => 'Enviar comanda',
    };
    final kitchenHint = switch (order.kitchenStatus) {
      'sent' => 'Cocina ya recibio los tacos por persona',
      'cooking' => 'La comanda esta en preparacion',
      'ready' => 'Cocina marco la comanda como lista',
      'not_required' => 'Solo hay productos que no pasan por cocina',
      _ => 'Cocina vera tacos y gringas por persona',
    };
    final canSend = !['sent', 'cooking', 'ready'].contains(order.kitchenStatus);

    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.room_service_outlined,
            title: kitchenLabel,
            subtitle: kitchenHint,
            prominent: canSend,
            onTap: canSend ? onSendToKitchen : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionTile(
            icon: Icons.point_of_sale_outlined,
            title: 'Cobrar mesa',
            subtitle: 'Pago completo o por persona',
            prominent: order.kitchenStatus == 'ready',
            onTap: onOpenPayment,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.prominent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool prominent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      selected: prominent,
      accent: prominent ? BrandColors.accentYellow : BrandColors.accentOrange,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            icon,
            color: prominent
                ? BrandColors.accentYellow
                : BrandColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: BrandColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BrandColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
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
