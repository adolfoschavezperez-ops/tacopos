import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/reports/yield_profit_report.dart';
import '../../core/theme/brand_colors.dart';
import '../../models/kitchen_stock_item.dart';
import '../../models/product.dart';
import '../../models/yield_profit_models.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class RecipeYieldConfigScreen extends StatefulWidget {
  const RecipeYieldConfigScreen({super.key});

  @override
  State<RecipeYieldConfigScreen> createState() =>
      _RecipeYieldConfigScreenState();
}

class _RecipeYieldConfigScreenState extends State<RecipeYieldConfigScreen> {
  final _repository = TacoPosRepository();
  late Future<void> _future;
  List<Product> _products = const [];
  List<KitchenStockItem> _stockItems = const [];
  List<IngredientYieldProfile> _profiles = const [];
  List<TheoreticalProductRecipe> _recipes = const [];
  InitialYieldSeedPlan? _seedPlan;

  @override
  void initState() {
    super.initState();
    _future = _initialize();
  }

  Future<void> _initialize() async {
    if (!kIsWeb) {
      throw StateError('Esta configuracion esta disponible solo en web.');
    }
    _seedPlan = await _repository.ensureInitialYieldProfiles();
    final data = await _repository.getYieldConfiguration();
    _products = data.$1;
    _stockItems = data.$2;
    _profiles = data.$3;
    _recipes = data.$4;
  }

  Future<void> _reload() async {
    setState(() => _future = _initialize());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PremiumBackground(
        child: SafeArea(
          child: Column(
            children: [
              _topBar(),
              Expanded(
                child: FutureBuilder<void>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return EmptyState(
                        icon: Icons.error_outline,
                        title: 'No se pudo cargar la configuracion',
                        message: '${snapshot.error}',
                      );
                    }
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const LoadingPanel(
                        message: 'Preparando recetas y rendimientos...',
                      );
                    }
                    return _content();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Regresar',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recetas y rendimientos',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                Text(
                  'Configuracion teorica para costo y utilidad bruta.',
                  style: TextStyle(color: BrandColors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _showRecipeAssistant,
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: const Text('Configurar recetas iniciales'),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
      children: [
        _notice(),
        const SizedBox(height: 14),
        if (_seedPlan != null) _seedStatus(_seedPlan!),
        const SizedBox(height: 18),
        _sectionHeader(
          'Rendimientos de coccion',
          '${_profiles.length} perfiles vinculados',
          null,
        ),
        const SizedBox(height: 8),
        _yieldTable(),
        const SizedBox(height: 22),
        _sectionHeader(
          'Recetas vigentes',
          '${_recipes.length} de ${_products.where((item) => item.active).length} productos activos',
          () => _editRecipe(),
        ),
        const SizedBox(height: 8),
        _recipeTable(),
      ],
    );
  }

  Widget _notice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BrandColors.accentYellow.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: BrandColors.accentYellow.withValues(alpha: 0.28),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.science_outlined, color: BrandColors.accentYellow),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Los rendimientos y porciones iniciales son estimaciones de '
              'referencia. Valida internamente peso y coccion antes de '
              'desmarcar el estado provisional.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _seedStatus(InitialYieldSeedPlan plan) {
    final linked = plan.linkedNames.isEmpty
        ? 'Ninguno'
        : plan.linkedNames.join(', ');
    final pending = plan.pendingNames.isEmpty
        ? 'Ninguno'
        : plan.pendingNames.join(', ');
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      borderRadius: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Carga inicial idempotente',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text('Ingredientes encontrados: $linked'),
          const SizedBox(height: 4),
          Text(
            'Pendientes de vincular: $pending',
            style: TextStyle(
              color: plan.pendingNames.isEmpty
                  ? BrandColors.textMuted
                  : BrandColors.accentYellow,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, String subtitle, VoidCallback? onAdd) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(color: BrandColors.textMuted),
              ),
            ],
          ),
        ),
        if (onAdd != null)
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Nueva receta'),
          ),
      ],
    );
  }

  Widget _yieldTable() {
    if (_profiles.isEmpty) {
      return const EmptyState(
        icon: Icons.percent_outlined,
        title: 'Sin perfiles vinculados',
        message:
            'Los ingredientes que no coincidan por nombre quedan pendientes '
            'y no se crean automaticamente.',
      );
    }
    return _table(
      columns: const [
        'Ingrediente',
        'Rendimiento',
        'Reduccion estimada',
        'Tacos/kg (30 g)',
        'Gringas/kg (60 g)',
        'Estado',
        'Editar',
      ],
      rows: _profiles.map((profile) {
        return [
          Text(profile.stockItemName),
          Text('${profile.cookingYieldPercent.toStringAsFixed(2)}%'),
          Text('${profile.estimatedReductionPercent.toStringAsFixed(2)}%'),
          Text(
            theoreticalUnitsPerRawKg(
              cookingYieldRate: profile.cookingYieldRate,
              cookedPortionGrams: 30,
            ).toStringAsFixed(2),
          ),
          Text(
            theoreticalUnitsPerRawKg(
              cookingYieldRate: profile.cookingYieldRate,
              cookedPortionGrams: 60,
            ).toStringAsFixed(2),
          ),
          Text(
            profile.needsInternalValidation
                ? 'Pendiente de validacion'
                : 'Validado',
          ),
          IconButton(
            tooltip: 'Editar rendimiento',
            onPressed: () => _editProfile(profile),
            icon: const Icon(Icons.edit_outlined),
          ),
        ];
      }).toList(),
    );
  }

  Widget _recipeTable() {
    final recipesByProduct = {
      for (final recipe in _recipes) recipe.productId: recipe,
    };
    final products = [..._products.where((item) => item.active)]
      ..sort((a, b) => a.name.compareTo(b.name));
    return _table(
      columns: const [
        'Producto',
        'Categoria',
        'Ingredientes',
        'Version',
        'Estado',
        'Editar',
      ],
      rows: products.map((product) {
        final recipe = recipesByProduct[product.id];
        return [
          Text(product.name),
          Text(product.categoryName),
          Text(
            recipe == null
                ? 'Sin receta'
                : recipe.ingredients
                      .map(
                        (item) =>
                            '${item.stockItemName} ${item.quantity.toStringAsFixed(2)} ${item.unit}',
                      )
                      .join(', '),
          ),
          Text(recipe == null ? '-' : '${recipe.version}'),
          Text(
            recipe == null
                ? 'Sin receta'
                : recipe.needsInternalValidation
                ? 'Pendiente de validacion'
                : 'Validada',
          ),
          IconButton(
            tooltip: recipe == null ? 'Configurar receta' : 'Editar receta',
            onPressed: () => _editRecipe(product: product, recipe: recipe),
            icon: Icon(recipe == null ? Icons.add : Icons.edit_outlined),
          ),
        ];
      }).toList(),
    );
  }

  Widget _table({
    required List<String> columns,
    required List<List<Widget>> rows,
  }) {
    return GlassPanel(
      padding: EdgeInsets.zero,
      borderRadius: 8,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          dataRowMinHeight: 48,
          dataRowMaxHeight: 72,
          columns: columns
              .map((label) => DataColumn(label: Text(label)))
              .toList(),
          rows: rows
              .map(
                (cells) => DataRow(
                  cells: cells.map((cell) => DataCell(cell)).toList(),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Future<void> _editProfile(IngredientYieldProfile profile) async {
    final percentController = TextEditingController(
      text: profile.cookingYieldPercent.toStringAsFixed(2),
    );
    final notesController = TextEditingController(text: profile.notes);
    var estimated = profile.isEstimated;
    var pending = profile.needsInternalValidation;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Rendimiento de ${profile.stockItemName}'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: percentController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Rendimiento de coccion %',
                    suffixText: '%',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notas'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: estimated,
                  title: const Text('Valor estimado'),
                  onChanged: (value) =>
                      setDialogState(() => estimated = value ?? true),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: pending,
                  title: const Text('Pendiente de validacion interna'),
                  onChanged: (value) =>
                      setDialogState(() => pending = value ?? true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final percent = double.tryParse(
                  percentController.text.replaceAll(',', '.'),
                );
                if (percent == null || percent <= 0 || percent > 100) {
                  showAppSnackBar(
                    context,
                    'Captura un rendimiento entre 0.01 y 100.',
                    type: AppSnackBarType.error,
                  );
                  return;
                }
                await _repository.saveIngredientYieldProfile(
                  profile.copyWith(
                    cookingYieldPercent: percent,
                    isEstimated: estimated,
                    needsInternalValidation: pending,
                    notes: notesController.text,
                  ),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    percentController.dispose();
    notesController.dispose();
    if (saved == true) {
      await _reload();
      if (mounted) showAppSnackBar(context, 'Rendimiento actualizado.');
    }
  }

  Future<void> _editRecipe({
    Product? product,
    TheoreticalProductRecipe? recipe,
  }) async {
    final result = await showDialog<TheoreticalProductRecipe>(
      context: context,
      builder: (context) => _RecipeEditorDialog(
        products: _products,
        stockItems: _stockItems,
        initialProduct: product,
        initialRecipe: recipe,
      ),
    );
    if (result == null) return;
    await _repository.saveTheoreticalProductRecipe(result);
    await _reload();
    if (mounted) showAppSnackBar(context, 'Receta guardada.');
  }

  Future<void> _showRecipeAssistant() async {
    final suggestions = suggestInitialRecipes(
      products: _products,
      stockItems: _stockItems,
      existingRecipes: _recipes,
    );
    if (suggestions.isEmpty) {
      showAppSnackBar(
        context,
        'No hay nuevas asociaciones seguras por nombre.',
      );
      return;
    }
    final selected = <String>{
      for (final item in suggestions) item.recipe.productId,
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Vista previa de recetas iniciales'),
          content: SizedBox(
            width: 760,
            height: 480,
            child: ListView(
              children: suggestions.map((suggestion) {
                return CheckboxListTile(
                  value: selected.contains(suggestion.recipe.productId),
                  title: Text(suggestion.recipe.productName),
                  subtitle: Text(
                    '${suggestion.recipe.ingredients.map((item) => '${item.stockItemName} ${item.quantity.toStringAsFixed(0)} ${item.unit} (${item.inputStage})').join(', ')}\n'
                    '${suggestion.reason}. No sobrescribe recetas existentes.',
                  ),
                  onChanged: (value) => setDialogState(() {
                    if (value == true) {
                      selected.add(suggestion.recipe.productId);
                    } else {
                      selected.remove(suggestion.recipe.productId);
                    }
                  }),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.check),
              label: Text('Crear ${selected.length}'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final count = await _repository.createSuggestedYieldRecipes(
      suggestions
          .where((item) => selected.contains(item.recipe.productId))
          .map((item) => item.recipe),
    );
    await _reload();
    if (mounted) showAppSnackBar(context, 'Se crearon $count recetas.');
  }
}

class _RecipeEditorDialog extends StatefulWidget {
  const _RecipeEditorDialog({
    required this.products,
    required this.stockItems,
    this.initialProduct,
    this.initialRecipe,
  });

  final List<Product> products;
  final List<KitchenStockItem> stockItems;
  final Product? initialProduct;
  final TheoreticalProductRecipe? initialRecipe;

  @override
  State<_RecipeEditorDialog> createState() => _RecipeEditorDialogState();
}

class _RecipeEditorDialogState extends State<_RecipeEditorDialog> {
  Product? _product;
  late List<TheoreticalRecipeIngredient> _ingredients;
  late TextEditingController _notesController;
  late bool _estimated;
  late bool _pending;

  @override
  void initState() {
    super.initState();
    _product = widget.initialProduct;
    _ingredients = [...?widget.initialRecipe?.ingredients];
    _notesController = TextEditingController(
      text: widget.initialRecipe?.notes ?? '',
    );
    _estimated = widget.initialRecipe?.isEstimated ?? true;
    _pending = widget.initialRecipe?.needsInternalValidation ?? true;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initialRecipe == null ? 'Configurar receta' : 'Editar receta',
      ),
      content: SizedBox(
        width: 840,
        height: 570,
        child: Column(
          children: [
            DropdownButtonFormField<Product>(
              initialValue: _product,
              decoration: const InputDecoration(labelText: 'Producto'),
              items: widget.products
                  .where((item) => item.active)
                  .map(
                    (product) => DropdownMenuItem(
                      value: product,
                      child: Text(product.name),
                    ),
                  )
                  .toList(),
              onChanged: widget.initialProduct == null
                  ? (value) => setState(() => _product = value)
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Ingredientes',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton.icon(
                  onPressed: _addIngredient,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            Expanded(
              child: _ingredients.isEmpty
                  ? const Center(child: Text('Agrega al menos un ingrediente.'))
                  : ListView.builder(
                      itemCount: _ingredients.length,
                      itemBuilder: (context, index) {
                        final item = _ingredients[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.stockItemName),
                          subtitle: Text(
                            '${item.quantity.toStringAsFixed(2)} ${item.unit} · ${item.inputStage}',
                          ),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Editar',
                                onPressed: () => _editIngredient(index),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Quitar',
                                onPressed: () => setState(
                                  () => _ingredients.removeAt(index),
                                ),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notas'),
            ),
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _estimated,
                    title: const Text('Receta estimada'),
                    onChanged: (value) =>
                        setState(() => _estimated = value ?? true),
                  ),
                ),
                Expanded(
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _pending,
                    title: const Text('Pendiente de validacion'),
                    onChanged: (value) =>
                        setState(() => _pending = value ?? true),
                  ),
                ),
              ],
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
          onPressed: _product == null || _ingredients.isEmpty ? null : _save,
          child: const Text('Guardar receta'),
        ),
      ],
    );
  }

  Future<void> _addIngredient() async {
    final item = await showDialog<TheoreticalRecipeIngredient>(
      context: context,
      builder: (context) =>
          _IngredientEditorDialog(stockItems: widget.stockItems),
    );
    if (item != null) setState(() => _ingredients.add(item));
  }

  Future<void> _editIngredient(int index) async {
    final item = await showDialog<TheoreticalRecipeIngredient>(
      context: context,
      builder: (context) => _IngredientEditorDialog(
        stockItems: widget.stockItems,
        initial: _ingredients[index],
      ),
    );
    if (item != null) setState(() => _ingredients[index] = item);
  }

  void _save() {
    final current = widget.initialRecipe;
    Navigator.pop(
      context,
      TheoreticalProductRecipe(
        productId: _product!.id,
        productName: _product!.name,
        ingredients: _ingredients,
        active: current?.active ?? true,
        isEstimated: _estimated,
        needsInternalValidation: _pending,
        notes: _notesController.text,
        version: current?.version ?? 1,
        effectiveFrom: current?.effectiveFrom,
        effectiveTo: current?.effectiveTo,
        createdAt: current?.createdAt,
        createdByEmployeeId: current?.createdByEmployeeId ?? '',
        createdByEmployeeName: current?.createdByEmployeeName ?? '',
      ),
    );
  }
}

class _IngredientEditorDialog extends StatefulWidget {
  const _IngredientEditorDialog({required this.stockItems, this.initial});

  final List<KitchenStockItem> stockItems;
  final TheoreticalRecipeIngredient? initial;

  @override
  State<_IngredientEditorDialog> createState() =>
      _IngredientEditorDialogState();
}

class _IngredientEditorDialogState extends State<_IngredientEditorDialog> {
  KitchenStockItem? _stockItem;
  late TextEditingController _quantityController;
  late String _unit;
  late String _stage;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      for (final item in widget.stockItems) {
        if (item.id == initial.stockItemId) _stockItem = item;
      }
    }
    _quantityController = TextEditingController(
      text: initial?.quantity.toString() ?? '',
    );
    _unit = initial?.unit ?? 'g';
    _stage = initial?.inputStage ?? 'ready_to_serve';
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ingrediente de receta'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<KitchenStockItem>(
              initialValue: _stockItem,
              decoration: const InputDecoration(labelText: 'Ingrediente'),
              items: widget.stockItems
                  .where((item) => item.active)
                  .map(
                    (item) =>
                        DropdownMenuItem(value: item, child: Text(item.name)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _stockItem = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantityController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Cantidad'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: const InputDecoration(labelText: 'Unidad'),
                    items: const [
                      DropdownMenuItem(value: 'g', child: Text('Gramos')),
                      DropdownMenuItem(value: 'piece', child: Text('Pieza')),
                      DropdownMenuItem(value: 'ml', child: Text('Mililitros')),
                    ],
                    onChanged: (value) => setState(() => _unit = value ?? 'g'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _stage,
                    decoration: const InputDecoration(labelText: 'Etapa'),
                    items: const [
                      DropdownMenuItem(value: 'raw', child: Text('Crudo')),
                      DropdownMenuItem(value: 'cooked', child: Text('Cocido')),
                      DropdownMenuItem(
                        value: 'ready_to_serve',
                        child: Text('Listo para servir'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _stage = value ?? 'ready_to_serve'),
                  ),
                ),
              ],
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
          onPressed: () {
            final quantity = double.tryParse(
              _quantityController.text.replaceAll(',', '.'),
            );
            if (_stockItem == null || quantity == null || quantity <= 0) return;
            Navigator.pop(
              context,
              TheoreticalRecipeIngredient(
                stockItemId: _stockItem!.id,
                stockItemName: _stockItem!.name,
                quantity: quantity,
                quantityType: 'portion',
                inputStage: _stage,
                unit: _unit,
                baseQuantity: quantityToBase(quantity, _unit),
                isEstimated: true,
                needsInternalValidation: true,
              ),
            );
          },
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}
