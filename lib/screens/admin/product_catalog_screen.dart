import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/kitchen_stock_item.dart';
import '../../models/order_platform.dart';
import '../../models/product.dart';
import '../../models/product_category.dart';
import '../../models/product_recipe_item.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/category_utils.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';

class ProductCatalogScreen extends StatefulWidget {
  const ProductCatalogScreen({super.key});

  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen> {
  final _searchController = TextEditingController();
  final _minPriceController = TextEditingController();
  final _maxPriceController = TextEditingController();
  final _factorController = TextEditingController();
  String _categoryFilter = _allFilter;
  String _statusFilter = _allFilter;
  String _kitchenFilter = _allFilter;
  String _stockFilter = _allFilter;
  String _platformFilter = _allFilter;
  _ProductSortMode _sortMode = _ProductSortMode.sortOrder;

  @override
  void dispose() {
    _searchController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _factorController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _minPriceController.clear();
      _maxPriceController.clear();
      _factorController.clear();
      _categoryFilter = _allFilter;
      _statusFilter = _allFilter;
      _kitchenFilter = _allFilter;
      _stockFilter = _allFilter;
      _platformFilter = _allFilter;
      _sortMode = _ProductSortMode.sortOrder;
    });
  }

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
        future: _prepareCatalog(repository),
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
          return StreamBuilder<List<ProductCategory>>(
            stream: repository.watchProductCategories(),
            builder: (context, categoriesSnapshot) {
              if (categoriesSnapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudieron cargar categorias',
                  message: '${categoriesSnapshot.error}',
                );
              }
              if (categoriesSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const LoadingPanel(message: 'Cargando categorias...');
              }
              final categories =
                  categoriesSnapshot.data ?? const <ProductCategory>[];
              return StreamBuilder<List<Product>>(
                stream: repository.watchProducts(),
                builder: (context, productsSnapshot) {
                  if (productsSnapshot.hasError) {
                    return EmptyState(
                      icon: Icons.error_outline,
                      title: 'No se pudo cargar el catalogo',
                      message: '${productsSnapshot.error}',
                    );
                  }

                  if (productsSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const LoadingPanel(message: 'Cargando catalogo...');
                  }

                  final products = productsSnapshot.data ?? [];
                  if (products.isEmpty) {
                    return const EmptyState(
                      icon: Icons.restaurant_menu,
                      title: 'Catalogo vacio',
                      message:
                          'Agrega productos para que aparezcan en Mesero / Caja.',
                    );
                  }

                  return StreamBuilder<List<OrderPlatform>>(
                    stream: repository.watchOrderPlatforms(activeOnly: false),
                    builder: (context, platformsSnapshot) {
                      final platforms =
                          platformsSnapshot.data ?? const <OrderPlatform>[];
                      return StreamBuilder<List<KitchenStockItem>>(
                        stream: repository.watchKitchenStockItems(),
                        builder: (context, stockSnapshot) {
                          final stockItems =
                              stockSnapshot.data ?? const <KitchenStockItem>[];
                          return _ProductCatalogView(
                            products: products,
                            categories: categories,
                            platforms: platforms,
                            stockItems: stockItems,
                            searchController: _searchController,
                            categoryFilter: _categoryFilter,
                            statusFilter: _statusFilter,
                            kitchenFilter: _kitchenFilter,
                            stockFilter: _stockFilter,
                            platformFilter: _platformFilter,
                            sortMode: _sortMode,
                            minPriceController: _minPriceController,
                            maxPriceController: _maxPriceController,
                            factorController: _factorController,
                            onSearchChanged: (_) => setState(() {}),
                            onCategoryChanged: (value) => setState(
                              () => _categoryFilter = value ?? _allFilter,
                            ),
                            onStatusChanged: (value) => setState(
                              () => _statusFilter = value ?? _allFilter,
                            ),
                            onKitchenChanged: (value) => setState(
                              () => _kitchenFilter = value ?? _allFilter,
                            ),
                            onStockChanged: (value) => setState(
                              () => _stockFilter = value ?? _allFilter,
                            ),
                            onPlatformChanged: (value) => setState(
                              () => _platformFilter = value ?? _allFilter,
                            ),
                            onSortChanged: (value) => setState(
                              () => _sortMode =
                                  value ?? _ProductSortMode.sortOrder,
                            ),
                            onClearFilters: _clearFilters,
                            onNormalizeCategories: () =>
                                _normalizeCategories(repository),
                            onEdit: (product) => _showProductDialog(
                              context,
                              repository,
                              product: product,
                              categories: categories,
                            ),
                            onToggle: repository.toggleProduct,
                          );
                        },
                      );
                    },
                  );
                },
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
    List<ProductCategory>? categories,
  }) async {
    try {
      final platforms = await repository
          .watchOrderPlatforms(activeOnly: false)
          .first;
      final activeCategories =
          categories ??
          await repository.getProductCategoriesOnce(activeOnly: true);
      final stockItems = await repository.watchKitchenStockItems().first;
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => _ProductDialog(
          repository: repository,
          product: product,
          categories: activeCategories,
          platforms: platforms,
          stockItems: stockItems,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        'No se pudo abrir el editor: $error',
        type: AppSnackBarType.error,
      );
    }
  }

  Future<void> _prepareCatalog(TacoPosRepository repository) async {
    await repository.seedDefaultProductCategoriesIfNeeded();
    await repository.ensureKitchenStockLinksForProducts();
  }

  Future<void> _normalizeCategories(TacoPosRepository repository) async {
    await repository.normalizeProductCategories();
    if (!mounted) return;
    showAppSnackBar(
      context,
      'Categorias normalizadas correctamente',
      type: AppSnackBarType.success,
    );
  }
}

const _allFilter = '__all__';

enum _ProductSortMode {
  sortOrder,
  name,
  category,
  priceAsc,
  priceDesc,
  activeFirst,
  kitchenFirst,
}

class _ProductCatalogView extends StatelessWidget {
  const _ProductCatalogView({
    required this.products,
    required this.categories,
    required this.platforms,
    required this.stockItems,
    required this.searchController,
    required this.categoryFilter,
    required this.statusFilter,
    required this.kitchenFilter,
    required this.stockFilter,
    required this.platformFilter,
    required this.sortMode,
    required this.minPriceController,
    required this.maxPriceController,
    required this.factorController,
    required this.onSearchChanged,
    required this.onCategoryChanged,
    required this.onStatusChanged,
    required this.onKitchenChanged,
    required this.onStockChanged,
    required this.onPlatformChanged,
    required this.onSortChanged,
    required this.onClearFilters,
    required this.onNormalizeCategories,
    required this.onEdit,
    required this.onToggle,
  });

  final List<Product> products;
  final List<ProductCategory> categories;
  final List<OrderPlatform> platforms;
  final List<KitchenStockItem> stockItems;
  final TextEditingController searchController;
  final String categoryFilter;
  final String statusFilter;
  final String kitchenFilter;
  final String stockFilter;
  final String platformFilter;
  final _ProductSortMode sortMode;
  final TextEditingController minPriceController;
  final TextEditingController maxPriceController;
  final TextEditingController factorController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onKitchenChanged;
  final ValueChanged<String?> onStockChanged;
  final ValueChanged<String?> onPlatformChanged;
  final ValueChanged<_ProductSortMode?> onSortChanged;
  final VoidCallback onClearFilters;
  final VoidCallback onNormalizeCategories;
  final ValueChanged<Product> onEdit;
  final ValueChanged<Product> onToggle;

  @override
  Widget build(BuildContext context) {
    final filteredProducts = _filterProducts(products);
    filteredProducts.sort(
      (a, b) => _compareProducts(a, b, sortMode, categories),
    );
    final counts = _ProductCounts.from(products);
    final compact = MediaQuery.sizeOf(context).width < 650;

    return ListView(
      padding: EdgeInsets.all(compact ? 12 : 22),
      children: [
        SectionHeader(
          title: 'Productos',
          subtitle:
              '${counts.total} productos · ${counts.active} activos · ${counts.withKitchen} con rendimiento · ${counts.categoryCount} categorias',
        ),
        const SizedBox(height: 12),
        _ProductCatalogFilters(
          products: products,
          categories: categories,
          platforms: platforms,
          stockItems: stockItems,
          searchController: searchController,
          categoryFilter: categoryFilter,
          statusFilter: statusFilter,
          kitchenFilter: kitchenFilter,
          stockFilter: stockFilter,
          platformFilter: platformFilter,
          sortMode: sortMode,
          minPriceController: minPriceController,
          maxPriceController: maxPriceController,
          factorController: factorController,
          onSearchChanged: onSearchChanged,
          onCategoryChanged: onCategoryChanged,
          onStatusChanged: onStatusChanged,
          onKitchenChanged: onKitchenChanged,
          onStockChanged: onStockChanged,
          onPlatformChanged: onPlatformChanged,
          onSortChanged: onSortChanged,
          onClearFilters: onClearFilters,
          onNormalizeCategories: onNormalizeCategories,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CountChip(label: '${counts.total} total'),
            _CountChip(label: '${counts.active} activos'),
            _CountChip(label: '${counts.inactive} inactivos'),
            _CountChip(label: '${counts.withKitchen} con rendimiento'),
            _CountChip(label: '${counts.withoutKitchen} sin rendimiento'),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '${filteredProducts.length} productos encontrados de ${products.length}',
          style: const TextStyle(
            color: BrandColors.textMuted,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        if (filteredProducts.isEmpty)
          const EmptyState(
            icon: Icons.search_off,
            title: 'Sin resultados',
            message: 'No se encontraron productos con estos filtros.',
          )
        else
          ...filteredProducts.map(
            (product) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ProductAdminTile(
                product: product,
                platforms: platforms,
                onEdit: () => onEdit(product),
                onToggle: () => onToggle(product),
              ),
            ),
          ),
      ],
    );
  }

  List<Product> _filterProducts(List<Product> source) {
    final query = _normalizeSearch(searchController.text);
    final minPrice = _readDoubleFilter(minPriceController.text);
    final maxPrice = _readDoubleFilter(maxPriceController.text);
    final factor = _readDoubleFilter(factorController.text);
    return source.where((product) {
      if (query.isNotEmpty &&
          !_normalizeSearch(product.name).contains(query) &&
          !_normalizeSearch(product.categoryName).contains(query)) {
        return false;
      }
      if (categoryFilter != _allFilter &&
          product.categoryId != categoryFilter) {
        return false;
      }
      if (statusFilter == 'active' && !product.active) {
        return false;
      }
      if (statusFilter == 'inactive' && product.active) {
        return false;
      }
      final hasKitchen =
          product.affectsKitchenStock && product.recipeItems.isNotEmpty;
      if (kitchenFilter == 'with' && !hasKitchen) {
        return false;
      }
      if (kitchenFilter == 'without' && hasKitchen) {
        return false;
      }
      if (stockFilter != _allFilter) {
        final primaryStockId = product.recipeItems.isNotEmpty
            ? product.recipeItems.first.kitchenStockItemId
            : product.kitchenStockItemId;
        if (primaryStockId != stockFilter) {
          return false;
        }
      }
      if (platformFilter != _allFilter) {
        if (!product.platformPrices.containsKey(platformFilter)) {
          return false;
        }
      }
      if (minPrice != null && product.price < minPrice) {
        return false;
      }
      if (maxPrice != null && product.price > maxPrice) {
        return false;
      }
      if (factor != null) {
        final productFactor = product.recipeItems.isNotEmpty
            ? product.recipeItems.first.consumptionFactor
            : product.stockConsumptionQty;
        if (productFactor == null || (productFactor - factor).abs() > 0.001) {
          return false;
        }
      }
      return true;
    }).toList();
  }
}

class _ProductCatalogFilters extends StatelessWidget {
  const _ProductCatalogFilters({
    required this.products,
    required this.categories,
    required this.platforms,
    required this.stockItems,
    required this.searchController,
    required this.categoryFilter,
    required this.statusFilter,
    required this.kitchenFilter,
    required this.stockFilter,
    required this.platformFilter,
    required this.sortMode,
    required this.minPriceController,
    required this.maxPriceController,
    required this.factorController,
    required this.onSearchChanged,
    required this.onCategoryChanged,
    required this.onStatusChanged,
    required this.onKitchenChanged,
    required this.onStockChanged,
    required this.onPlatformChanged,
    required this.onSortChanged,
    required this.onClearFilters,
    required this.onNormalizeCategories,
  });

  final List<Product> products;
  final List<ProductCategory> categories;
  final List<OrderPlatform> platforms;
  final List<KitchenStockItem> stockItems;
  final TextEditingController searchController;
  final String categoryFilter;
  final String statusFilter;
  final String kitchenFilter;
  final String stockFilter;
  final String platformFilter;
  final _ProductSortMode sortMode;
  final TextEditingController minPriceController;
  final TextEditingController maxPriceController;
  final TextEditingController factorController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onKitchenChanged;
  final ValueChanged<String?> onStockChanged;
  final ValueChanged<String?> onPlatformChanged;
  final ValueChanged<_ProductSortMode?> onSortChanged;
  final VoidCallback onClearFilters;
  final VoidCallback onNormalizeCategories;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 650;
    final usedStockIds = {
      for (final product in products)
        if (product.recipeItems.isNotEmpty)
          product.recipeItems.first.kitchenStockItemId
        else if ((product.kitchenStockItemId ?? '').isNotEmpty)
          product.kitchenStockItemId!,
    };
    final availableStock =
        stockItems.where((item) => usedStockIds.contains(item.id)).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final categoryValue =
        categoryFilter == _allFilter ||
            categories.any((category) => category.id == categoryFilter)
        ? categoryFilter
        : _allFilter;
    ProductCategory? quickCategory(String name) {
      return findCategoryByName(categories, name);
    }

    final stockValue =
        stockFilter == _allFilter ||
            availableStock.any((item) => item.id == stockFilter)
        ? stockFilter
        : _allFilter;
    final platformValue =
        platformFilter == _allFilter ||
            platforms.any((platform) => platform.id == platformFilter)
        ? platformFilter
        : _allFilter;

    return GlassPanel(
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              labelText: 'Buscar por nombre',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar busqueda',
                      onPressed: () {
                        searchController.clear();
                        onSearchChanged('');
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickFilterChip(
                label: 'Todos',
                selected: _allFiltersSelected,
                onSelected: (_) => onClearFilters(),
              ),
              for (final categoryName in ['Tacos', 'Gringas', 'Bebidas'])
                _QuickFilterChip(
                  label: categoryName,
                  selected: categoryFilter == quickCategory(categoryName)?.id,
                  color: categoryAccent(
                    categoryId: quickCategory(categoryName)?.id,
                    categoryName: categoryName,
                    colorHex: quickCategory(categoryName)?.colorHex,
                  ),
                  onSelected: (_) {
                    final category = quickCategory(categoryName);
                    if (category != null) onCategoryChanged(category.id);
                  },
                ),
              _QuickFilterChip(
                label: 'Activos',
                selected: statusFilter == 'active',
                onSelected: (_) => onStatusChanged('active'),
              ),
              _QuickFilterChip(
                label: 'Inactivos',
                selected: statusFilter == 'inactive',
                onSelected: (_) => onStatusChanged('inactive'),
              ),
              _QuickFilterChip(
                label: 'Con rendimiento',
                selected: kitchenFilter == 'with',
                onSelected: (_) => onKitchenChanged('with'),
              ),
              _QuickFilterChip(
                label: 'Sin rendimiento',
                selected: kitchenFilter == 'without',
                onSelected: (_) => onKitchenChanged('without'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _FilterDropdown<String>(
                label: 'Categoria',
                value: categoryValue,
                items: [
                  const DropdownMenuItem(
                    value: _allFilter,
                    child: Text('Todas'),
                  ),
                  for (final category in categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                onChanged: onCategoryChanged,
              ),
              _FilterDropdown<String>(
                label: 'Estado',
                value: statusFilter,
                items: const [
                  DropdownMenuItem(value: _allFilter, child: Text('Todos')),
                  DropdownMenuItem(value: 'active', child: Text('Activos')),
                  DropdownMenuItem(value: 'inactive', child: Text('Inactivos')),
                ],
                onChanged: onStatusChanged,
              ),
              _FilterDropdown<String>(
                label: 'Rendimiento',
                value: kitchenFilter,
                items: const [
                  DropdownMenuItem(value: _allFilter, child: Text('Todos')),
                  DropdownMenuItem(
                    value: 'with',
                    child: Text('Afecta rendimiento'),
                  ),
                  DropdownMenuItem(value: 'without', child: Text('No afecta')),
                ],
                onChanged: onKitchenChanged,
              ),
              _FilterDropdown<String>(
                label: 'Insumo principal',
                value: stockValue,
                items: [
                  const DropdownMenuItem(
                    value: _allFilter,
                    child: Text('Todos'),
                  ),
                  for (final item in availableStock)
                    DropdownMenuItem(value: item.id, child: Text(item.name)),
                ],
                onChanged: onStockChanged,
              ),
              _FilterDropdown<String>(
                label: 'Plataforma',
                value: platformValue,
                items: [
                  const DropdownMenuItem(
                    value: _allFilter,
                    child: Text('Todas'),
                  ),
                  for (final platform in platforms)
                    DropdownMenuItem(
                      value: platform.id,
                      child: Text('Con precio ${platform.name}'),
                    ),
                ],
                onChanged: onPlatformChanged,
              ),
              _FilterDropdown<_ProductSortMode>(
                label: 'Ordenar',
                value: sortMode,
                items: const [
                  DropdownMenuItem(
                    value: _ProductSortMode.sortOrder,
                    child: Text('sortOrder'),
                  ),
                  DropdownMenuItem(
                    value: _ProductSortMode.name,
                    child: Text('Nombre A-Z'),
                  ),
                  DropdownMenuItem(
                    value: _ProductSortMode.category,
                    child: Text('Categoria'),
                  ),
                  DropdownMenuItem(
                    value: _ProductSortMode.priceAsc,
                    child: Text('Precio menor a mayor'),
                  ),
                  DropdownMenuItem(
                    value: _ProductSortMode.priceDesc,
                    child: Text('Precio mayor a menor'),
                  ),
                  DropdownMenuItem(
                    value: _ProductSortMode.activeFirst,
                    child: Text('Activos primero'),
                  ),
                  DropdownMenuItem(
                    value: _ProductSortMode.kitchenFirst,
                    child: Text('Con rendimiento primero'),
                  ),
                ],
                onChanged: onSortChanged,
              ),
              _SmallFilterField(
                label: 'Precio min',
                controller: minPriceController,
                onChanged: onSearchChanged,
              ),
              _SmallFilterField(
                label: 'Precio max',
                controller: maxPriceController,
                onChanged: onSearchChanged,
              ),
              _SmallFilterField(
                label: 'Factor equiv.',
                controller: factorController,
                onChanged: onSearchChanged,
              ),
              OutlinedButton.icon(
                onPressed: onClearFilters,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Limpiar filtros'),
              ),
              OutlinedButton.icon(
                onPressed: onNormalizeCategories,
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: const Text('Normalizar categorias'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _allFiltersSelected =>
      searchController.text.isEmpty &&
      categoryFilter == _allFilter &&
      statusFilter == _allFilter &&
      kitchenFilter == _allFilter &&
      stockFilter == _allFilter &&
      platformFilter == _allFilter &&
      minPriceController.text.isEmpty &&
      maxPriceController.text.isEmpty &&
      factorController.text.isEmpty &&
      sortMode == _ProductSortMode.sortOrder;
}

class _SmallFilterField extends StatelessWidget {
  const _SmallFilterField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

class _QuickFilterChip extends StatelessWidget {
  const _QuickFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.color = BrandColors.accentYellow,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      onSelected: onSelected,
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.08),
      selectedColor: color.withValues(alpha: 0.22),
      side: BorderSide(color: color.withValues(alpha: selected ? 0.7 : 0.28)),
      labelStyle: TextStyle(
        color: selected ? color : BrandColors.textMuted,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: BrandColors.glassFill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: BrandColors.glassBorder),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: BrandColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProductCounts {
  const _ProductCounts({
    required this.total,
    required this.active,
    required this.inactive,
    required this.withKitchen,
    required this.withoutKitchen,
    required this.categoryCount,
  });

  final int total;
  final int active;
  final int inactive;
  final int withKitchen;
  final int withoutKitchen;
  final int categoryCount;

  factory _ProductCounts.from(List<Product> products) {
    final active = products.where((product) => product.active).length;
    final withKitchen = products
        .where(
          (product) =>
              product.affectsKitchenStock && product.recipeItems.isNotEmpty,
        )
        .length;
    return _ProductCounts(
      total: products.length,
      active: active,
      inactive: products.length - active,
      withKitchen: withKitchen,
      withoutKitchen: products.length - withKitchen,
      categoryCount: products
          .map((product) => product.categoryId)
          .toSet()
          .length,
    );
  }
}

int _compareProducts(
  Product a,
  Product b,
  _ProductSortMode sortMode,
  List<ProductCategory> categories,
) {
  switch (sortMode) {
    case _ProductSortMode.name:
      return _compareText(a.name, b.name);
    case _ProductSortMode.category:
      final categoryCompare = _compareProductCategories(a, b, categories);
      return categoryCompare != 0
          ? categoryCompare
          : _compareText(a.name, b.name);
    case _ProductSortMode.priceAsc:
      final priceCompare = a.price.compareTo(b.price);
      return priceCompare != 0 ? priceCompare : _compareText(a.name, b.name);
    case _ProductSortMode.priceDesc:
      final priceCompare = b.price.compareTo(a.price);
      return priceCompare != 0 ? priceCompare : _compareText(a.name, b.name);
    case _ProductSortMode.activeFirst:
      final activeCompare = (b.active ? 1 : 0).compareTo(a.active ? 1 : 0);
      return activeCompare != 0 ? activeCompare : _compareText(a.name, b.name);
    case _ProductSortMode.kitchenFirst:
      final aKitchen = a.affectsKitchenStock && a.recipeItems.isNotEmpty;
      final bKitchen = b.affectsKitchenStock && b.recipeItems.isNotEmpty;
      final kitchenCompare = (bKitchen ? 1 : 0).compareTo(aKitchen ? 1 : 0);
      return kitchenCompare != 0
          ? kitchenCompare
          : _compareText(a.name, b.name);
    case _ProductSortMode.sortOrder:
      final categoryCompare = _compareProductCategories(a, b, categories);
      if (categoryCompare != 0) return categoryCompare;
      final sortCompare = a.sortOrder.compareTo(b.sortOrder);
      return sortCompare != 0 ? sortCompare : _compareText(a.name, b.name);
  }
}

int _compareProductCategories(
  Product a,
  Product b,
  List<ProductCategory> categories,
) {
  final aCategory = findCategoryById(categories, a.categoryId);
  final bCategory = findCategoryById(categories, b.categoryId);
  final aSort = aCategory?.sortOrder ?? categoryRank(a.categoryName);
  final bSort = bCategory?.sortOrder ?? categoryRank(b.categoryName);
  final sortCompare = aSort.compareTo(bSort);
  if (sortCompare != 0) return sortCompare;
  return _compareText(
    aCategory?.name ?? a.categoryName,
    bCategory?.name ?? b.categoryName,
  );
}

int _compareText(String a, String b) {
  return _normalizeSearch(a).compareTo(_normalizeSearch(b));
}

String _normalizeSearch(String value) {
  return normalizeCategory(value);
}

double? _readDoubleFilter(String value) {
  final clean = value.trim();
  if (clean.isEmpty) return null;
  return double.tryParse(clean.replaceAll(',', '.'));
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({
    required this.repository,
    required this.categories,
    required this.platforms,
    required this.stockItems,
    this.product,
  });

  final TacoPosRepository repository;
  final Product? product;
  final List<ProductCategory> categories;
  final List<OrderPlatform> platforms;
  final List<KitchenStockItem> stockItems;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final Map<String, TextEditingController> _platformControllers;
  late List<ProductCategory> _categories;
  late String _categoryId;
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
    _categories = [...widget.categories];
    _nameController = TextEditingController(text: product?.name ?? '');
    final initialCategory = _resolveInitialCategory(product, _categories);
    _categoryId = initialCategory?.id ?? '';
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
          _selectedCategoryName,
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
              _selectedCategoryName,
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
      _selectedCategoryName,
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
            _selectedCategoryName,
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
    final selectedCategory = _selectedCategory;
    if (_nameController.text.trim().isEmpty ||
        selectedCategory == null ||
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
        categoryId: selectedCategory.id,
        categoryName: selectedCategory.name,
        category: selectedCategory.name,
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
    showAppSnackBar(context, text);
  }

  ProductCategory? get _selectedCategory {
    final selected = findCategoryById(_categories, _categoryId);
    if (selected != null) return selected;
    return _resolveInitialCategory(widget.product, _categories);
  }

  String get _selectedCategoryName => _selectedCategory?.name ?? 'Otros';

  Future<void> _seedInitialCategories() async {
    setState(() => _saving = true);
    try {
      await widget.repository.seedDefaultProductCategoriesIfNeeded();
      final categories = await widget.repository.getProductCategoriesOnce(
        activeOnly: true,
      );
      if (!mounted) return;
      setState(() {
        _categories = categories;
        final resolved = _resolveInitialCategory(widget.product, _categories);
        _categoryId = resolved?.id ?? _categoryId;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _message(error.toString());
    }
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
                          categories: _categories,
                          categoryId: _selectedCategory?.id ?? '',
                          priceController: _priceController,
                          active: _active,
                          sendToKitchen: _sendToKitchen,
                          saving: _saving,
                          onSeedCategories: _seedInitialCategories,
                          onCategoryChanged: (value) {
                            setState(() {
                              _categoryId = value ?? _categoryId;
                              _affectsKitchenStock =
                                  _affectsKitchenStock ||
                                  _defaultAffectsKitchenStock(
                                    _selectedCategoryName,
                                    _nameController.text,
                                  );
                            });
                          },
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

ProductCategory? _resolveInitialCategory(
  Product? product,
  List<ProductCategory> categories,
) {
  if (categories.isEmpty) return null;
  if (product != null) {
    final byId = findCategoryById(categories, product.categoryId);
    if (byId != null) return byId;

    final byCategoryName = findCategoryByName(categories, product.categoryName);
    if (byCategoryName != null) return byCategoryName;

    final byLegacyCategory = findCategoryByName(categories, product.category);
    if (byLegacyCategory != null) return byLegacyCategory;

    final otros = findCategoryByName(categories, 'Otros');
    if (otros != null) return otros;
  }

  final tacos = findCategoryByName(categories, 'Tacos');
  if (tacos != null) return tacos;

  final otros = findCategoryByName(categories, 'Otros');
  if (otros != null) return otros;

  return categories.first;
}

class _MainProductFields extends StatelessWidget {
  const _MainProductFields({
    required this.nameController,
    required this.categories,
    required this.categoryId,
    required this.priceController,
    required this.active,
    required this.sendToKitchen,
    required this.saving,
    required this.onSeedCategories,
    required this.onCategoryChanged,
    required this.onActiveChanged,
    required this.onSendToKitchenChanged,
  });

  final TextEditingController nameController;
  final List<ProductCategory> categories;
  final String categoryId;
  final TextEditingController priceController;
  final bool active;
  final bool sendToKitchen;
  final bool saving;
  final VoidCallback onSeedCategories;
  final ValueChanged<String?> onCategoryChanged;
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
          if (categories.isEmpty)
            OutlinedButton.icon(
              onPressed: saving ? null : onSeedCategories,
              icon: const Icon(Icons.category_outlined),
              label: const Text('Crear categorias iniciales'),
            )
          else
            DropdownButtonFormField<String>(
              initialValue:
                  categories.any((category) => category.id == categoryId)
                  ? categoryId
                  : categories.first.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: categories
                  .map(
                    (category) => DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
                  )
                  .toList(),
              onChanged: saving ? null : onCategoryChanged,
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
    required this.platforms,
    required this.onEdit,
    required this.onToggle,
  });

  final Product product;
  final List<OrderPlatform> platforms;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final accent = categoryAccent(
      categoryId: product.categoryId,
      categoryName: product.categoryName,
    );
    final platformPrices = platforms
        .where((platform) => product.platformPrices.containsKey(platform.id))
        .toList();
    return GlassCard(
      accent: product.active ? accent : BrandColors.textMuted,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: product.active
                  ? accent.withValues(alpha: 0.16)
                  : BrandColors.glassFill,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              product.active ? Icons.fastfood : Icons.visibility_off,
              color: product.active ? accent : BrandColors.textMuted,
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
                  'Categoria: ${product.categoryName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MiniInfoChip(
                      label: product.active ? 'Activo' : 'Inactivo',
                      color: product.active
                          ? BrandColors.success
                          : BrandColors.textMuted,
                    ),
                    _MiniInfoChip(
                      label: 'Precio tienda ${_moneyText(product.price)}',
                      color: BrandColors.accentYellow,
                    ),
                    for (final platform in platformPrices)
                      _MiniInfoChip(
                        label:
                            '${platform.name} ${_moneyText(product.platformPrices[platform.id] ?? 0)}',
                        color: BrandColors.info,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
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
              color: product.sendToKitchen ? accent : BrandColors.info,
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

class _MiniInfoChip extends StatelessWidget {
  const _MiniInfoChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
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

String _moneyText(double value) {
  return '\$${value.toStringAsFixed(2)}';
}
