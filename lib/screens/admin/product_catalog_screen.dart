import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/product.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';

class ProductCatalogScreen extends StatelessWidget {
  const ProductCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();

    return BrandedScaffold(
      title: 'Catalogo',
      actions: [
        IconButton(
          tooltip: 'Agregar producto',
          onPressed: () => _showProductDialog(context, repository),
          icon: const Icon(Icons.add_circle),
        ),
      ],
      body: StreamBuilder<List<Product>>(
        stream: repository.watchProducts(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Cargando catalogo...');
          }

          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudo cargar el catalogo',
              message: '${snapshot.error}',
            );
          }

          final products = snapshot.data ?? [];
          if (products.isEmpty) {
            return const EmptyState(
              icon: Icons.restaurant_menu,
              title: 'Catalogo vacio',
              message: 'Agrega productos o crea datos demo desde el inicio.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final product = products[index];
              return _ProductAdminTile(
                product: product,
                onEdit: () =>
                    _showProductDialog(context, repository, product: product),
                onToggle: () => repository.toggleProduct(product),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: () => _showProductDialog(context, repository),
          icon: const Icon(Icons.add),
          label: const Text('Agregar producto'),
        ),
      ),
    );
  }

  Future<void> _showProductDialog(
    BuildContext context,
    TacoPosRepository repository, {
    Product? product,
  }) async {
    final nameController = TextEditingController(text: product?.name ?? '');
    final categoryController = TextEditingController(
      text: product?.category ?? 'Tacos',
    );
    final priceController = TextEditingController(
      text: product == null ? '' : product.price.toStringAsFixed(2),
    );
    var active = product?.active ?? true;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                product == null ? 'Agregar producto' : 'Editar producto',
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: categoryController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Categoria'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Precio'),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Activo'),
                      value: active,
                      onChanged: (value) {
                        setDialogState(() {
                          active = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final price = double.tryParse(
                      priceController.text.replaceAll(',', '.'),
                    );

                    if (nameController.text.trim().isEmpty ||
                        categoryController.text.trim().isEmpty ||
                        price == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Completa nombre, categoria y precio.'),
                        ),
                      );
                      return;
                    }

                    await repository.saveProduct(
                      productId: product?.id,
                      name: nameController.text,
                      category: categoryController.text,
                      price: price,
                      active: active,
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    categoryController.dispose();
    priceController.dispose();
  }
}

class _ProductAdminTile extends StatelessWidget {
  const _ProductAdminTile({
    required this.product,
    required this.onEdit,
    required this.onToggle,
  });

  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: product.active
                    ? BrandColors.orange.withValues(alpha: 0.18)
                    : BrandColors.surfaceHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                product.active ? Icons.fastfood : Icons.visibility_off,
                color: product.active ? BrandColors.yellow : BrandColors.muted,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: BrandColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: MoneyText(
                value: product.price,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: BrandColors.yellow,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              tooltip: 'Editar',
              onPressed: onEdit,
              icon: const Icon(Icons.edit),
            ),
            IconButton(
              tooltip: product.active ? 'Desactivar' : 'Activar',
              onPressed: onToggle,
              icon: Icon(product.active ? Icons.toggle_on : Icons.toggle_off),
              color: product.active ? BrandColors.success : BrandColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}
