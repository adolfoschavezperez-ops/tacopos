import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/product.dart';
import '../../models/product_category.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/category_utils.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class ProductCategoryCatalogScreen extends StatefulWidget {
  const ProductCategoryCatalogScreen({super.key});

  @override
  State<ProductCategoryCatalogScreen> createState() =>
      _ProductCategoryCatalogScreenState();
}

class _ProductCategoryCatalogScreenState
    extends State<ProductCategoryCatalogScreen> {
  final _repository = TacoPosRepository();

  @override
  Widget build(BuildContext context) {
    if (AppSession.instance.employee?.canManageProducts != true) {
      return const BrandedScaffold(
        title: 'Categorias de productos',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para administrar productos.',
        ),
      );
    }

    return BrandedScaffold(
      title: 'Categorias de productos',
      actions: [
        IconButton(
          tooltip: 'Normalizar categorias',
          onPressed: _normalize,
          icon: const Icon(Icons.auto_fix_high_outlined),
        ),
        IconButton(
          tooltip: 'Agregar categoria',
          onPressed: () => _showDialog(),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
      body: FutureBuilder<void>(
        future: _repository.seedDefaultProductCategoriesIfNeeded(),
        builder: (context, setupSnapshot) {
          if (setupSnapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Preparando categorias...');
          }
          if (setupSnapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudieron preparar categorias',
              message: '${setupSnapshot.error}',
            );
          }
          return StreamBuilder<List<ProductCategory>>(
            stream: _repository.watchProductCategories(),
            builder: (context, categoriesSnapshot) {
              if (categoriesSnapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudieron cargar categorias',
                  message: '${categoriesSnapshot.error}',
                );
              }
              if (!categoriesSnapshot.hasData) {
                return const LoadingPanel(message: 'Cargando categorias...');
              }
              final categories = categoriesSnapshot.data!;
              return StreamBuilder<List<Product>>(
                stream: _repository.watchProducts(activeOnly: false),
                builder: (context, productsSnapshot) {
                  final products = productsSnapshot.data ?? const <Product>[];
                  return ListView(
                    padding: const EdgeInsets.all(22),
                    children: [
                      SectionHeader(
                        title: 'Categorias de productos',
                        subtitle:
                            '${categories.length} categorias para catalogo y menu',
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _normalize,
                              icon: const Icon(Icons.auto_fix_high_outlined),
                              label: const Text('Normalizar categorias'),
                            ),
                            FilledButton.icon(
                              onPressed: () => _showDialog(),
                              icon: const Icon(Icons.add),
                              label: const Text('Agregar'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (categories.isEmpty)
                        const EmptyState(
                          icon: Icons.category_outlined,
                          title: 'Sin categorias',
                          message:
                              'Agrega categorias para clasificar productos.',
                        )
                      else
                        ...categories.map(
                          (category) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _CategoryTile(
                              category: category,
                              productCount: products
                                  .where(
                                    (product) =>
                                        product.categoryId == category.id,
                                  )
                                  .length,
                              onEdit: () => _showDialog(category: category),
                              onToggle: () =>
                                  _repository.toggleProductCategory(category),
                            ),
                          ),
                        ),
                    ],
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
          onTap: () => _showDialog(),
          icon: Icons.add,
          label: 'Agregar categoria',
          prominent: true,
        ),
      ),
    );
  }

  Future<void> _normalize() async {
    try {
      await _repository.normalizeProductCategories();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Categorias normalizadas correctamente')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showDialog({ProductCategory? category}) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _ProductCategoryDialog(repository: _repository, category: category),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.productCount,
    required this.onEdit,
    required this.onToggle,
  });

  final ProductCategory category;
  final int productCount;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final accent = categoryColorFromModel(category);
    return GlassCard(
      accent: category.active ? accent : BrandColors.textMuted,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: category.active ? 0.18 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Icon(Icons.category_outlined, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _Pill(label: 'Orden ${category.sortOrder}', color: accent),
                    _Pill(
                      label: category.active ? 'Activa' : 'Inactiva',
                      color: category.active
                          ? BrandColors.success
                          : BrandColors.textMuted,
                    ),
                    _Pill(
                      label: '$productCount productos',
                      color: BrandColors.info,
                    ),
                    if ((category.colorHex ?? '').isNotEmpty)
                      _Pill(label: category.colorHex!, color: accent),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: category.active ? 'Desactivar' : 'Activar',
            onPressed: onToggle,
            icon: Icon(category.active ? Icons.toggle_on : Icons.toggle_off),
          ),
        ],
      ),
    );
  }
}

class _ProductCategoryDialog extends StatefulWidget {
  const _ProductCategoryDialog({required this.repository, this.category});

  final TacoPosRepository repository;
  final ProductCategory? category;

  @override
  State<_ProductCategoryDialog> createState() => _ProductCategoryDialogState();
}

class _ProductCategoryDialogState extends State<_ProductCategoryDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _sortOrderController;
  late final TextEditingController _colorController;
  late bool _active;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _nameController = TextEditingController(text: category?.name ?? '');
    _sortOrderController = TextEditingController(
      text: (category?.sortOrder ?? 90).toString(),
    );
    _colorController = TextEditingController(text: category?.colorHex ?? '');
    _active = category?.active ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sortOrderController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final sortOrder = int.tryParse(_sortOrderController.text.trim()) ?? 90;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _message('Captura el nombre de la categoria.');
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.category == null) {
        await widget.repository.createProductCategory(
          name: name,
          active: _active,
          sortOrder: sortOrder,
          colorHex: _colorController.text,
        );
      } else {
        await widget.repository.updateProductCategory(
          categoryId: widget.category!.id,
          name: name,
          active: _active,
          sortOrder: sortOrder,
          colorHex: _colorController.text,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _message(error.toString());
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.category == null ? 'Agregar categoria' : 'Editar categoria',
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sortOrderController,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Orden'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _colorController,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Color/acento',
                hintText: '#F59A23',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activa'),
              value: _active,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _active = value),
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
          child: Text(_saving ? 'Guardando...' : 'Guardar'),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
