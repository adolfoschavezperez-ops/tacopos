import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/kitchen_stock_item.dart';
import '../../models/order_platform.dart';
import '../../models/product.dart';
import '../../models/product_recipe_item.dart';
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
        title: 'Productos',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para administrar productos.',
        ),
      );
    }

    return BrandedScaffold(
      title: 'Productos',
      actions: [
        IconButton(
          tooltip: 'Agregar producto',
          onPressed: () => _showProductDialog(context, repository),
          icon: const Icon(Icons.add_circle),
        ),
      ],
      body: FutureBuilder<void>(
        future: repository.ensureKitchenStockLinksForProducts(),
        builder: (context, setupSnapshot) {
          if (setupSnapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Preparando catalogo...');
          }
          if (setupSnapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudo preparar control de cocina',
              message: '${setupSnapshot.error}',
            );
          }
          return StreamBuilder<List<Product>>(
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
                  message:
                      'Agrega productos para que aparezcan en Mesero / Caja.',
                );
              }

              return ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  SectionHeader(
                    title: 'Productos',
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
    Product? product,
  }) async {
    await repository.ensureDefaultOrderPlatforms();
    await repository.ensureKitchenStockLinksForProducts();
    final platforms = await repository.watchOrderPlatforms().first;
    final stockItems = await repository.watchKitchenStockItems().first;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => _ProductDialog(
        repository: repository,
        product: product,
        platforms: platforms,
        stockItems: stockItems,
      ),
    );
  }
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({
    required this.repository,
    required this.platforms,
    required this.stockItems,
    this.product,
  });

  final TacoPosRepository repository;
  final Product? product;
  final List<OrderPlatform> platforms;
  final List<KitchenStockItem> stockItems;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _priceController;
  late final Map<String, TextEditingController> _platformControllers;
  late bool _active;
  late bool _sendToKitchen;
  late bool _affectsKitchenStock;
  late List<KitchenStockItem> _stockItems;
  late List<_RecipeDraftItem> _recipeItems;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _nameController = TextEditingController(text: product?.name ?? '');
    _categoryController = TextEditingController(
      text: product?.category ?? 'Tacos',
    );
    _priceController = TextEditingController(
      text: product == null ? '' : product.price.toStringAsFixed(2),
    );
    _platformControllers = {
      for (final platform in widget.platforms.where(
        (platform) => platform.id != 'en_persona',
      ))
        platform.id: TextEditingController(
          text: product?.platformPrices[platform.id]?.toStringAsFixed(2) ?? '',
        ),
    };
    _active = product?.active ?? true;
    _sendToKitchen = product?.sendToKitchen ?? true;
    _affectsKitchenStock =
        product?.affectsKitchenStock ??
        _defaultAffectsKitchenStock(
          _categoryController.text,
          _nameController.text,
        );
    _stockItems = [...widget.stockItems];
    _recipeItems = [
      for (final item
          in (product?.recipeItems ?? const <ProductRecipeItem>[]).take(1))
        _RecipeDraftItem.fromRecipeItem(item),
    ];
    if (_recipeItems.isEmpty && _affectsKitchenStock) {
      final guessed = _guessStockItemId(product?.name ?? '');
      String? stockItemId = guessed;
      if (stockItemId == null) {
        for (final item in _stockItems) {
          if (item.active) {
            stockItemId = item.id;
            break;
          }
        }
      }
      if (stockItemId != null) {
        _recipeItems.add(
          _RecipeDraftItem(
            stockItemId: stockItemId,
            factor: _defaultEquivalenceFactor(
              _categoryController.text,
              product?.name ?? '',
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    for (final controller in _platformControllers.values) {
      controller.dispose();
    }
    for (final item in _recipeItems) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _createKitchenStockItem() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _message('Captura el nombre del producto primero.');
      return;
    }

    final normalizedName = _normalize(name);
    for (final item in _stockItems) {
      if (_normalize(item.name) == normalizedName) {
        setState(() => _setPrimaryRecipeItem(item.id));
        _message('Insumo existente seleccionado.');
        return;
      }
    }

    final defaults = _kitchenDefaultsFor(
      _categoryController.text,
      _nameController.text,
    );
    final created = await showDialog<KitchenStockItem>(
      context: context,
      builder: (_) => _QuickKitchenStockDialog(
        repository: widget.repository,
        defaultName: name,
        defaultCategory: defaults.category,
        defaultUnit: defaults.unit,
        sortOrder: _stockItems.length + 1,
      ),
    );
    if (!mounted || created == null) return;
    setState(() {
      _stockItems = [..._stockItems, created]
        ..sort((a, b) => a.name.compareTo(b.name));
      _setPrimaryRecipeItem(created.id);
    });
  }

  void _setPrimaryRecipeItem([String? stockItemId]) {
    var id = stockItemId ?? _guessStockItemId(_nameController.text);
    if (id == null) {
      for (final item in _stockItems) {
        if (item.active) {
          id = item.id;
          break;
        }
      }
    }
    if (id == null) {
      _message('No hay insumos disponibles para seleccionar.');
      return;
    }
    if (_recipeItems.isEmpty) {
      _recipeItems.add(
        _RecipeDraftItem(
          stockItemId: id,
          factor: _defaultEquivalenceFactor(
            _categoryController.text,
            _nameController.text,
          ),
        ),
      );
    } else {
      _recipeItems.first.stockItemId = id;
    }
  }

  Future<void> _save() async {
    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    if (_nameController.text.trim().isEmpty ||
        _categoryController.text.trim().isEmpty ||
        price == null) {
      _message('Completa nombre, categoria y precio.');
      return;
    }

    final recipeItems = _readRecipeItems();
    if (_affectsKitchenStock && recipeItems.isEmpty) {
      _message('Selecciona el insumo principal para rendimiento.');
      return;
    }

    final platformPrices = <String, double>{};
    for (final entry in _platformControllers.entries) {
      final raw = entry.value.text.trim();
      if (raw.isEmpty) continue;
      final value = double.tryParse(raw.replaceAll(',', '.'));
      if (value == null || value <= 0) {
        _message('Revisa precios por plataforma.');
        return;
      }
      platformPrices[entry.key] = value;
    }

    setState(() => _saving = true);
    try {
      await widget.repository.saveProduct(
        productId: widget.product?.id,
        name: _nameController.text,
        category: _categoryController.text,
        price: price,
        platformPrices: platformPrices,
        active: _active,
        sendToKitchen: _sendToKitchen,
        affectsKitchenStock: _affectsKitchenStock,
        recipeItems: recipeItems,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      _message(error.toString().replaceFirst('Bad state: ', ''));
      setState(() => _saving = false);
    }
  }

  List<ProductRecipeItem> _readRecipeItems() {
    if (!_affectsKitchenStock) {
      return const [];
    }
    final recipe = <ProductRecipeItem>[];
    final draft = _recipeItems.isEmpty ? null : _recipeItems.first;
    final stockItem = _stockItemById(_stockItems, draft?.stockItemId);
    final factor = double.tryParse(
      draft?.factorController.text.trim().replaceAll(',', '.') ?? '',
    );
    if (stockItem == null) {
      _message('Selecciona el insumo principal.');
      return const [];
    }
    if (factor == null || factor <= 0) {
      _message('El factor de equivalencia debe ser mayor a cero.');
      return const [];
    }
    recipe.add(
      ProductRecipeItem(
        kitchenStockItemId: stockItem.id,
        kitchenStockItemName: stockItem.name,
        kitchenStockUnit: stockItem.unit,
        consumptionFactor: factor,
      ),
    );
    return recipe;
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.product == null
                            ? 'Agregar producto'
                            : 'Editar producto',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 720;
                        final left = _MainProductFields(
                          nameController: _nameController,
                          categoryController: _categoryController,
                          priceController: _priceController,
                          active: _active,
                          sendToKitchen: _sendToKitchen,
                          saving: _saving,
                          onActiveChanged: (value) {
                            setState(() => _active = value);
                          },
                          onSendToKitchenChanged: (value) {
                            setState(() => _sendToKitchen = value);
                          },
                        );
                        final right = _ProductKitchenFields(
                          platformControllers: _platformControllers,
                          platforms: widget.platforms,
                          saving: _saving,
                          affectsKitchenStock: _affectsKitchenStock,
                          stockItems: _stockItems,
                          recipeItems: _recipeItems,
                          onAffectsChanged: (value) {
                            setState(() {
                              _affectsKitchenStock = value;
                              if (value && _recipeItems.isEmpty) {
                                _setPrimaryRecipeItem(
                                  _guessStockItemId(_nameController.text),
                                );
                              }
                            });
                          },
                          onRecipeStockChanged: (value) {
                            setState(() {
                              _setPrimaryRecipeItem(value);
                            });
                          },
                          onCreateStockItem: _createKitchenStockItem,
                        );
                        if (!wide) {
                          return Column(
                            children: [left, const SizedBox(height: 16), right],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: left),
                            const SizedBox(width: 18),
                            Expanded(child: right),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Guardando...' : 'Guardar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MainProductFields extends StatelessWidget {
  const _MainProductFields({
    required this.nameController,
    required this.categoryController,
    required this.priceController,
    required this.active,
    required this.sendToKitchen,
    required this.saving,
    required this.onActiveChanged,
    required this.onSendToKitchenChanged,
  });

  final TextEditingController nameController;
  final TextEditingController categoryController;
  final TextEditingController priceController;
  final bool active;
  final bool sendToKitchen;
  final bool saving;
  final ValueChanged<bool> onActiveChanged;
  final ValueChanged<bool> onSendToKitchenChanged;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Producto',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: nameController,
            enabled: !saving,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: categoryController,
            enabled: !saving,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Categoria'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: priceController,
            enabled: !saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Precio tienda'),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Activo'),
            value: active,
            onChanged: saving ? null : onActiveChanged,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enviar a cocina'),
            value: sendToKitchen,
            onChanged: saving ? null : onSendToKitchenChanged,
          ),
        ],
      ),
    );
  }
}

class _ProductKitchenFields extends StatelessWidget {
  const _ProductKitchenFields({
    required this.platformControllers,
    required this.platforms,
    required this.saving,
    required this.affectsKitchenStock,
    required this.stockItems,
    required this.recipeItems,
    required this.onAffectsChanged,
    required this.onRecipeStockChanged,
    required this.onCreateStockItem,
  });

  final Map<String, TextEditingController> platformControllers;
  final List<OrderPlatform> platforms;
  final bool saving;
  final bool affectsKitchenStock;
  final List<KitchenStockItem> stockItems;
  final List<_RecipeDraftItem> recipeItems;
  final ValueChanged<bool> onAffectsChanged;
  final ValueChanged<String?> onRecipeStockChanged;
  final VoidCallback onCreateStockItem;

  @override
  Widget build(BuildContext context) {
    final recipeItem = recipeItems.isEmpty ? null : recipeItems.first;
    return Column(
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rendimiento de cocina',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Afecta rendimiento de cocina'),
                value: affectsKitchenStock,
                onChanged: saving ? null : onAffectsChanged,
              ),
              if (affectsKitchenStock) ...[
                const SizedBox(height: 8),
                const Text(
                  'Taco normal = 1. Gringa chica = 2.5. Gringa grande = 3.5.',
                  style: TextStyle(
                    color: BrandColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (!stockItems.any((item) => item.active))
                  const Text(
                    'No hay insumos de cocina activos. Crea uno en Admin > Insumos de cocina.',
                    style: TextStyle(
                      color: BrandColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (recipeItems.isEmpty)
                  const Text(
                    'Selecciona el insumo principal para medir rendimiento.',
                    style: TextStyle(color: BrandColors.textMuted),
                  )
                else
                  Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: recipeItem?.stockItemId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Insumo principal',
                        ),
                        items: stockItems
                            .where(
                              (stockItem) =>
                                  stockItem.active ||
                                  stockItem.id == recipeItem?.stockItemId,
                            )
                            .map(
                              (stockItem) => DropdownMenuItem(
                                value: stockItem.id,
                                child: Text(
                                  stockItem.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: saving ? null : onRecipeStockChanged,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: recipeItem?.factorController,
                        enabled: !saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Factor de equivalencia',
                          suffixText: 'equiv.',
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: saving ? null : onCreateStockItem,
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('Crear insumo nuevo'),
                  ),
                ),
              ] else
                const Text(
                  'No afecta rendimiento',
                  style: TextStyle(
                    color: BrandColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Precios por plataforma',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              for (final platform in platforms.where(
                (platform) => platform.id != 'en_persona',
              )) ...[
                TextField(
                  controller: platformControllers[platform.id],
                  enabled: !saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Precio ${platform.name}',
                    helperText: 'Vacio usa precio tienda',
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RecipeDraftItem {
  _RecipeDraftItem({this.stockItemId, double factor = 1})
    : factorController = TextEditingController(text: _factorText(factor));

  factory _RecipeDraftItem.fromRecipeItem(ProductRecipeItem item) {
    return _RecipeDraftItem(
      stockItemId: item.kitchenStockItemId,
      factor: item.consumptionFactor,
    );
  }

  String? stockItemId;
  final TextEditingController factorController;

  void dispose() {
    factorController.dispose();
  }
}

class _QuickKitchenStockDialog extends StatefulWidget {
  const _QuickKitchenStockDialog({
    required this.repository,
    required this.defaultName,
    required this.defaultCategory,
    required this.defaultUnit,
    required this.sortOrder,
  });

  final TacoPosRepository repository;
  final String defaultName;
  final String defaultCategory;
  final String defaultUnit;
  final int sortOrder;

  @override
  State<_QuickKitchenStockDialog> createState() =>
      _QuickKitchenStockDialogState();
}

class _QuickKitchenStockDialogState extends State<_QuickKitchenStockDialog> {
  late final TextEditingController _nameController;
  late String _category;
  late String _unit;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.defaultName);
    _category = widget.defaultCategory;
    _unit = widget.defaultUnit;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.repository.saveKitchenStockItem(
        name: name,
        category: _category,
        unit: _unit,
        active: true,
        sortOrder: widget.sortOrder,
        optimalConsumptionPerSaleQty: _unit == 'piece' ? 1 : 50,
        optimalConsumptionUnit: _unit == 'piece'
            ? 'piece_per_item'
            : 'g_per_item',
      );
      final items = await widget.repository
          .watchKitchenStockItems(activeOnly: true)
          .first;
      final created = items.firstWhere(
        (item) => _normalize(item.name) == _normalize(name),
        orElse: () => items.last,
      );
      if (!mounted) return;
      Navigator.pop(context, created);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Crear insumo nuevo'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: const [
                DropdownMenuItem(value: 'meat', child: Text('Carne')),
                DropdownMenuItem(value: 'tortilla', child: Text('Tortilla')),
                DropdownMenuItem(value: 'drink', child: Text('Bebida')),
                DropdownMenuItem(value: 'water', child: Text('Agua')),
                DropdownMenuItem(value: 'other', child: Text('Otro')),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _category = value ?? 'other'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _unit,
              decoration: const InputDecoration(labelText: 'Unidad'),
              items: const [
                DropdownMenuItem(value: 'kg', child: Text('kg')),
                DropdownMenuItem(value: 'piece', child: Text('pieza')),
                DropdownMenuItem(value: 'liter', child: Text('litro')),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _unit = value ?? 'kg'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando...' : 'Crear'),
        ),
      ],
    );
  }
}

class _KitchenDefaults {
  const _KitchenDefaults({required this.category, required this.unit});

  final String category;
  final String unit;
}

_KitchenDefaults _kitchenDefaultsFor(String category, String name) {
  final safeCategory = _normalize(category);
  final safeName = _normalize(name);
  if (safeCategory.contains('bebida') || safeName.contains('refresco')) {
    return const _KitchenDefaults(category: 'drink', unit: 'piece');
  }
  if (safeCategory.contains('tortilla')) {
    return const _KitchenDefaults(category: 'tortilla', unit: 'kg');
  }
  if (safeCategory.contains('taco')) {
    return const _KitchenDefaults(category: 'meat', unit: 'kg');
  }
  return const _KitchenDefaults(category: 'other', unit: 'kg');
}

bool _defaultAffectsKitchenStock(String category, String name) {
  final safeCategory = _normalize(category);
  final safeName = _normalize(name);
  if (safeCategory.contains('taco') ||
      safeName.contains('taco') ||
      safeName.contains('gringa')) {
    return true;
  }
  if (safeCategory.contains('bebida') || safeName.contains('refresco')) {
    return true;
  }
  return false;
}

double _defaultEquivalenceFactor(String category, String name) {
  final safeCategory = _normalize(category);
  final safeName = _normalize(name);
  if (safeName.contains('gringa')) {
    final isGrande = safeName.contains('grande') || safeName.contains('gde');
    return isGrande ? 3.5 : 2.5;
  }
  if (safeCategory.contains('bebida') ||
      safeName.contains('refresco') ||
      safeName.contains('coca')) {
    return 1;
  }
  return 1;
}

KitchenStockItem? _stockItemById(List<KitchenStockItem> items, String? id) {
  if (id == null) return null;
  for (final item in items) {
    if (item.id == id) return item;
  }
  return null;
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .trim()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');
}

String? _guessStockItemId(String productName) {
  final normalized = _normalize(productName);
  if (normalized.contains('bistec')) return 'bistec';
  if (normalized.contains('adobada')) return 'adobada';
  if (normalized.contains('carnaza')) return 'carnaza';
  if (normalized.contains('arrachera')) return 'arrachera';
  if (normalized.contains('chorizo')) return 'chorizo';
  if (normalized.contains('higado')) return 'higado';
  if (normalized.contains('labio')) return 'labio';
  if (normalized.contains('tripa')) return 'tripa';
  if (normalized.contains('lengua')) return 'lengua';
  if (normalized.contains('coca') || normalized.contains('refresco')) {
    return 'refresco_coca_cola';
  }
  return null;
}

String _factorText(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
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
                  product.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: BrandColors.textMuted),
                ),
                const SizedBox(height: 8),
                _ProductRecipeSummary(product: product),
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

class _ProductRecipeSummary extends StatelessWidget {
  const _ProductRecipeSummary({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    if (!product.affectsKitchenStock) {
      return const Text(
        'No afecta rendimiento',
        style: TextStyle(
          color: BrandColors.textMuted,
          fontWeight: FontWeight.w800,
        ),
      );
    }

    if (product.recipeItems.isEmpty) {
      return const Text(
        'Rendimiento: sin insumo principal',
        style: TextStyle(
          color: BrandColors.danger,
          fontWeight: FontWeight.w800,
        ),
      );
    }

    final item = product.recipeItems.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: BrandColors.accentYellow.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: BrandColors.accentYellow.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        'Rendimiento: ${item.kitchenStockItemName} · ${_factorText(item.consumptionFactor)} equiv.',
        style: const TextStyle(
          color: BrandColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
