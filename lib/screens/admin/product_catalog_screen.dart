import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/product.dart';
import '../../models/order_platform.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';

class ProductCatalogScreen extends StatelessWidget {
  const ProductCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();
    if (AppSession.instance.employee?.canManageProducts != true) {
      return const BrandedScaffold(
        title: 'Catalogo',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para administrar productos.',
        ),
      );
    }

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
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudo cargar el catalogo',
              message: '${snapshot.error}',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Cargando catalogo...');
          }

          final products = snapshot.data ?? [];
          if (products.isEmpty) {
            return const EmptyState(
              icon: Icons.restaurant_menu,
              title: 'Catalogo vacio',
              message: 'Agrega productos para que aparezcan en Mesero / Caja.',
            );
          }

          return StreamBuilder<List<OrderPlatform>>(
            stream: repository.watchOrderPlatforms(),
            builder: (context, platformSnapshot) {
              if (platformSnapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudieron cargar plataformas',
                  message: '${platformSnapshot.error}',
                );
              }

              final platforms = platformSnapshot.data ?? [];
              return ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  SectionHeader(
                    title: 'Catalogo',
                    subtitle: '${products.length} productos configurados',
                  ),
                  const SizedBox(height: 18),
                  ...products.map(
                    (product) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ProductAdminTile(
                        product: product,
                        onEdit: () => _showProductDialog(
                          context,
                          repository,
                          platforms: platforms,
                          product: product,
                        ),
                        onToggle: () => repository.toggleProduct(product),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: GlassButton(
          onTap: () => _showProductDialog(context, repository),
          icon: Icons.add,
          label: 'Agregar producto',
          prominent: true,
        ),
      ),
    );
  }

  Future<void> _showProductDialog(
    BuildContext context,
    TacoPosRepository repository, {
    List<OrderPlatform> platforms = const [],
    Product? product,
  }) async {
    await repository.ensureDefaultOrderPlatforms();
    final availablePlatforms = platforms.isEmpty
        ? await repository.watchOrderPlatforms().first
        : platforms;
    if (!context.mounted) {
      return;
    }
    final nameController = TextEditingController(text: product?.name ?? '');
    final categoryController = TextEditingController(
      text: product?.category ?? 'Tacos',
    );
    final priceController = TextEditingController(
      text: product == null ? '' : product.price.toStringAsFixed(2),
    );
    var active = product?.active ?? true;
    var sendToKitchen = product?.sendToKitchen ?? true;
    final platformControllers = <String, TextEditingController>{
      for (final platform in availablePlatforms.where(
        (platform) => platform.id != 'en_persona',
      ))
        platform.id: TextEditingController(
          text: product?.platformPrices[platform.id]?.toStringAsFixed(2) ?? '',
        ),
    };

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
                      decoration: const InputDecoration(
                        labelText: 'Precio en tienda',
                      ),
                    ),
                    for (final platform in availablePlatforms.where(
                      (platform) => platform.id != 'en_persona',
                    )) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: platformControllers[platform.id],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Precio ${platform.name}',
                          helperText: 'Vacio usa precio en tienda',
                        ),
                      ),
                    ],
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enviar a cocina'),
                      subtitle: const Text(
                        'Desactivalo para bebidas u otros extras.',
                      ),
                      value: sendToKitchen,
                      onChanged: (value) {
                        setDialogState(() {
                          sendToKitchen = value;
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

                    final platformPrices = <String, double>{};
                    for (final entry in platformControllers.entries) {
                      final raw = entry.value.text.trim();
                      if (raw.isEmpty) {
                        continue;
                      }
                      final value = double.tryParse(raw.replaceAll(',', '.'));
                      if (value == null || value <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Revisa precios por plataforma.'),
                          ),
                        );
                        return;
                      }
                      platformPrices[entry.key] = value;
                    }

                    await repository.saveProduct(
                      productId: product?.id,
                      name: nameController.text,
                      category: categoryController.text,
                      price: price,
                      platformPrices: platformPrices,
                      active: active,
                      sendToKitchen: sendToKitchen,
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
    for (final controller in platformControllers.values) {
      controller.dispose();
    }
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
    return GlassCard(
      accent: product.active ? BrandColors.accentOrange : BrandColors.textMuted,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: product.active
                  ? BrandColors.accentOrange.withValues(alpha: 0.16)
                  : BrandColors.glassFill,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              product.active ? Icons.fastfood : Icons.visibility_off,
              color: product.active
                  ? BrandColors.accentYellow
                  : BrandColors.textMuted,
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
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.platformPrices.isEmpty
                      ? product.category
                      : '${product.category} · ${product.platformPrices.length} precios plataforma',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: BrandColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: product.sendToKitchen
                ? 'Se envia a cocina'
                : 'No se envia a cocina',
            child: Icon(
              product.sendToKitchen
                  ? Icons.room_service_outlined
                  : Icons.local_drink_outlined,
              color: product.sendToKitchen
                  ? BrandColors.accentOrange
                  : BrandColors.info,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: MoneyText(
              value: product.price,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: BrandColors.accentYellow,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Editar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: product.active ? 'Desactivar' : 'Activar',
            onPressed: onToggle,
            icon: Icon(product.active ? Icons.toggle_on : Icons.toggle_off),
            color: product.active ? BrandColors.success : BrandColors.textMuted,
          ),
        ],
      ),
    );
  }
}
