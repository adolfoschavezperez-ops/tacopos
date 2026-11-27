import 'package:flutter/material.dart';

import '../../../models/kitchen_stock_item.dart';
import '../../../models/product.dart';
import '../../../models/yield_profit_models.dart';
import '../../../services/taco_pos_repository.dart' show ProductStockOutRow;
import '../../auth/backoffice_session.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/filter_bar.dart';
import '../../widgets/saas_card.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/status_pill.dart';
import 'inventory_repository.dart';

enum _InventoryTab { kitchen, stock, recipes, yields, stockOuts }

class InventoryPage extends StatefulWidget {
  const InventoryPage({
    super.key,
    required this.session,
    required this.repository,
  });

  final BackofficeSession session;
  final InventoryRepository repository;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  DatePreset _preset = DatePreset.last7Days;
  late DateTime _startDate;
  late DateTime _endDate;
  _InventoryTab _tab = _InventoryTab.kitchen;
  Future<InventoryDashboardData>? _future;
  String? _lastBranchId;
  String? _selectedSessionId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _endDate = DateTime(now.year, now.month, now.day);
    _startDate = _endDate.subtract(const Duration(days: 6));
    _lastBranchId = widget.session.selectedBranchId;
    widget.session.addListener(_onSessionChanged);
    _load();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (_lastBranchId != widget.session.selectedBranchId) {
      _lastBranchId = widget.session.selectedBranchId;
      _selectedSessionId = null;
      _load();
    }
  }

  void _applyPreset(DatePreset preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _preset = preset;
      switch (preset) {
        case DatePreset.today:
          _startDate = today;
          _endDate = today;
        case DatePreset.last7Days:
          _startDate = today.subtract(const Duration(days: 6));
          _endDate = today;
        case DatePreset.last30Days:
          _startDate = today.subtract(const Duration(days: 29));
          _endDate = today;
        case DatePreset.last90Days:
          _startDate = today.subtract(const Duration(days: 89));
          _endDate = today;
        case DatePreset.monthToDate:
          _startDate = DateTime(today.year, today.month, 1);
          _endDate = today;
        case DatePreset.custom:
          break;
      }
      _selectedSessionId = null;
      _load();
    });
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked == null) return;
    setState(() {
      _preset = DatePreset.custom;
      _startDate = picked.start;
      _endDate = picked.end;
      _selectedSessionId = null;
      _load();
    });
  }

  void _load() {
    setState(() {
      _future = widget.repository.loadInventory(
        restaurantId: widget.session.restaurantId,
        startBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_startDate),
        endBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_endDate),
        branchId: widget.session.selectedBranchId,
        selectedSessionId: _selectedSessionId,
      );
    });
  }

  Future<void> _openStockItemDialog(KitchenStockItem? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final catCtrl = TextEditingController(text: existing?.category ?? 'Carnes');
    final unitCtrl = TextEditingController(text: existing?.unit ?? 'kg');
    final optCtrl = TextEditingController(
      text: (existing?.optimalConsumptionPerSaleQty ?? 0).toString(),
    );
    final supCtrl = TextEditingController(
      text: existing?.defaultSupplierName ?? '',
    );
    var active = existing?.active ?? true;
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? 'Nuevo insumo de cocina' : 'Editar insumo',
          ),
          content: SizedBox(
            width: 390,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: catCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Categoría',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: unitCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Unidad',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: optCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Consumo óptimo por venta',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: supCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Proveedor habitual',
                    ),
                  ),
                  SwitchListTile(
                    value: active,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Insumo activo'),
                    onChanged: (v) => setDialogState(() => active = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      setDialogState(() => saving = true);
                      await widget.repository.saveKitchenStockItem(
                        restaurantId: widget.session.restaurantId,
                        itemId: existing?.id,
                        name: nameCtrl.text,
                        category: catCtrl.text,
                        unit: unitCtrl.text,
                        active: active,
                        optimalConsumptionPerSaleQty:
                            double.tryParse(optCtrl.text.trim()) ?? 0,
                        defaultSupplierName: supCtrl.text,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    },
              child: Text(saving ? 'Guardando...' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _openAdditionalEntryDialog(
    InventoryDashboardData data,
  ) async {
    final session = data.selectedSession;
    if (session == null || !session.isOpen || data.sessionItems.isEmpty) return;
    var selectedItem = data.sessionItems.first;
    final qtyCtrl = TextEditingController(text: '2');
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Entrada adicional de cocina'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedItem.id,
                  decoration: const InputDecoration(labelText: 'Insumo'),
                  items: data.sessionItems
                      .map(
                        (i) => DropdownMenuItem(
                          value: i.id,
                          child: Text('${i.name} (${i.unit})'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (id) {
                    if (id == null) return;
                    setDialogState(() {
                      selectedItem = data.sessionItems.firstWhere(
                        (i) => i.id == id,
                      );
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Cantidad adicional (${selectedItem.unit})',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final qty = double.tryParse(qtyCtrl.text.trim()) ?? 0;
                      if (qty <= 0) return;
                      setDialogState(() => saving = true);
                      await widget.repository.registerAdditionalEntry(
                        restaurantId: widget.session.restaurantId,
                        sessionId: session.id,
                        itemId: selectedItem.id,
                        addedQty: qty,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    },
              child: Text(saving ? 'Aplicando...' : 'Registrar'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _openYieldProfileDialog(
    IngredientYieldProfile? existing,
    List<KitchenStockItem> stockItems,
  ) async {
    var selectedStockId = existing?.stockItemId ??
        (stockItems.isNotEmpty ? stockItems.first.id : '');
    final pctCtrl = TextEditingController(
      text: (existing?.cookingYieldPercent ?? 70.0).toStringAsFixed(1),
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    var needsValidation = existing?.needsInternalValidation ?? false;
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? 'Nuevo perfil de rendimiento'
                : 'Editar rendimiento (${existing.stockItemName})',
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (existing == null && stockItems.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: selectedStockId,
                    decoration: const InputDecoration(
                      labelText: 'Insumo de cocina',
                    ),
                    items: stockItems
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.name),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedStockId = v);
                    },
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: pctCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Rendimiento de cocción (%)',
                    helperText: 'Ej. 65% significa 650 g cocidos por cada 1,000 g crudos',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notas'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: needsValidation,
                  onChanged: (v) =>
                      setDialogState(() => needsValidation = v ?? false),
                  title: const Text('Requiere validación interna'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: saving || selectedStockId.isEmpty
                  ? null
                  : () async {
                      final pct =
                          double.tryParse(pctCtrl.text.trim()) ?? 0.0;
                      if (pct <= 0 || pct > 100) return;
                      setDialogState(() => saving = true);
                      final stockName = existing?.stockItemName ??
                          stockItems
                              .firstWhere(
                                (s) => s.id == selectedStockId,
                                orElse: () => stockItems.first,
                              )
                              .name;
                      final emp = widget.session.employee;
                      await widget.repository.saveIngredientYieldProfile(
                        restaurantId: widget.session.restaurantId,
                        stockItemId: selectedStockId,
                        stockItemName: stockName,
                        cookingYieldPercent: pct,
                        needsInternalValidation: needsValidation,
                        notes: notesCtrl.text,
                        employeeId: emp?.id ?? '',
                        employeeName: emp?.name ?? 'Admin',
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    },
              child: Text(saving ? 'Guardando...' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _openTheoreticalRecipeDialog(
    TheoreticalProductRecipe? existing,
    List<Product> allProducts,
    List<KitchenStockItem> stockItems,
  ) async {
    if (allProducts.isEmpty || stockItems.isEmpty) return;
    var selectedProductId = existing?.productId ?? allProducts.first.id;
    final ingredients = existing != null
        ? List<TheoreticalRecipeIngredient>.from(existing.ingredients)
        : <TheoreticalRecipeIngredient>[];
    var recipeStatus = existing?.recipeStatus ?? 'complete';
    final missingNotesCtrl = TextEditingController(
      text: existing?.missingIngredientNotes ?? '',
    );
    var saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? 'Nueva receta teórica'
                : 'Editar receta · ${existing.productName}',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (existing == null)
                    DropdownButtonFormField<String>(
                      initialValue: selectedProductId,
                      decoration: const InputDecoration(labelText: 'Producto'),
                      items: allProducts
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => selectedProductId = v);
                        }
                      },
                    ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Ingredientes teóricos',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          final first = stockItems.first;
                          setDialogState(() {
                            ingredients.add(
                              TheoreticalRecipeIngredient(
                                stockItemId: first.id,
                                stockItemName: first.name,
                                quantity: 30,
                                quantityType: 'grams',
                                inputStage: 'cooked',
                                unit: 'g',
                                baseQuantity: 30,
                              ),
                            );
                          });
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Agregar insumo'),
                      ),
                    ],
                  ),
                  for (var i = 0; i < ingredients.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              initialValue: ingredients[i].stockItemId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Insumo',
                                isDense: true,
                              ),
                              items: stockItems
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s.id,
                                      child: Text(
                                        s.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (v) {
                                if (v == null) return;
                                final s = stockItems.firstWhere(
                                  (e) => e.id == v,
                                );
                                final cur = ingredients[i];
                                setDialogState(() {
                                  ingredients[i] = TheoreticalRecipeIngredient(
                                    stockItemId: s.id,
                                    stockItemName: s.name,
                                    quantity: cur.quantity,
                                    quantityType: cur.quantityType,
                                    inputStage: cur.inputStage,
                                    unit: cur.unit,
                                    baseQuantity: cur.baseQuantity,
                                  );
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              initialValue:
                                  ingredients[i].quantity.toString(),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Cant.',
                                isDense: true,
                              ),
                              onChanged: (v) {
                                final qty = double.tryParse(v.trim()) ?? 0;
                                final cur = ingredients[i];
                                ingredients[i] = TheoreticalRecipeIngredient(
                                  stockItemId: cur.stockItemId,
                                  stockItemName: cur.stockItemName,
                                  quantity: qty,
                                  quantityType: cur.quantityType,
                                  inputStage: cur.inputStage,
                                  unit: cur.unit,
                                  baseQuantity: qty,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: ingredients[i].inputStage,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Etapa',
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'raw',
                                  child: Text('Crudo'),
                                ),
                                DropdownMenuItem(
                                  value: 'cooked',
                                  child: Text('Cocido'),
                                ),
                                DropdownMenuItem(
                                  value: 'ready_to_serve',
                                  child: Text('Listo'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                final cur = ingredients[i];
                                setDialogState(() {
                                  ingredients[i] = TheoreticalRecipeIngredient(
                                    stockItemId: cur.stockItemId,
                                    stockItemName: cur.stockItemName,
                                    quantity: cur.quantity,
                                    quantityType: cur.quantityType,
                                    inputStage: v,
                                    unit: cur.unit,
                                    baseQuantity: cur.baseQuantity,
                                  );
                                });
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => setDialogState(
                              () => ingredients.removeAt(i),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: recipeStatus,
                    decoration: const InputDecoration(
                      labelText: 'Estado de receta',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'complete',
                        child: Text('Completa'),
                      ),
                      DropdownMenuItem(
                        value: 'incomplete',
                        child: Text('Incompleta'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => recipeStatus = v);
                    },
                  ),
                  if (recipeStatus == 'incomplete') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: missingNotesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Notas de insumos faltantes',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      final prod = allProducts.firstWhere(
                        (p) => p.id == selectedProductId,
                        orElse: () => allProducts.first,
                      );
                      final emp = widget.session.employee;
                      await widget.repository.saveTheoreticalProductRecipe(
                        restaurantId: widget.session.restaurantId,
                        productId: prod.id,
                        productName: prod.name,
                        ingredients: ingredients,
                        recipeStatus: recipeStatus,
                        missingIngredientNotes: missingNotesCtrl.text,
                        employeeId: emp?.id ?? '',
                        employeeName: emp?.name ?? 'Admin',
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    },
              child: Text(saving ? 'Guardando...' : 'Guardar receta'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _clearStockOut(ProductStockOutRow row) async {
    await widget.repository.clearProductStockOut(
      restaurantId: widget.session.restaurantId,
      stockOutId: row.id,
      reason: 'Restablecido desde Backoffice 2.0',
      employeeId: widget.session.employee?.id ?? '',
      employeeName: widget.session.employee?.name ?? '',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${row.productName} liberado.')),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final branchNames = {
      for (final b in widget.session.branches) b.id: b.name,
    };

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Inventarios y Cocina',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Insumos de cocina, sesiones de apertura y cierre, mermas, recetas y productos agotados.',
                style: TextStyle(fontSize: 13, color: tokens.textSecondary),
              ),
              const SizedBox(height: 16),
              SaasFilterBar(
                activePreset: _preset,
                startDateLabel: BackofficeSalesAdapter.formatBusinessDate(
                  _startDate,
                ),
                endDateLabel: BackofficeSalesAdapter.formatBusinessDate(_endDate),
                onPresetSelected: _applyPreset,
                onPickCustomRange: _pickCustomRange,
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<_InventoryTab>(
                  segments: const [
                    ButtonSegment(
                      value: _InventoryTab.kitchen,
                      label: Text('Sesiones de cocina'),
                    ),
                    ButtonSegment(
                      value: _InventoryTab.stock,
                      label: Text('Insumos'),
                    ),
                    ButtonSegment(
                      value: _InventoryTab.recipes,
                      label: Text('Recetas'),
                    ),
                    ButtonSegment(
                      value: _InventoryTab.yields,
                      label: Text('Rendimientos'),
                    ),
                    ButtonSegment(
                      value: _InventoryTab.stockOuts,
                      label: Text('Agotados'),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (v) => setState(() => _tab = v.first),
                ),
              ),
              const SizedBox(height: 18),
              FutureBuilder<InventoryDashboardData>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const TableSkeleton(rows: 6);
                  }
                  if (snapshot.hasError) {
                    return SaasErrorState(
                      title: 'Error al cargar inventario de cocina',
                      message:
                          'No se pudieron consultar los registros de cocina. Intenta de nuevo.',
                      onRetry: _load,
                    );
                  }
                  final data = snapshot.data;
                  if (data == null) {
                    return const SaasEmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'Sin datos disponibles',
                      message: 'No hay registros en el periodo seleccionado.',
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _InventorySummaryRow(data: data, isMobile: isMobile),
                      const SizedBox(height: 16),
                      switch (_tab) {
                        _InventoryTab.kitchen => _KitchenSessionsView(
                          data: data,
                          branchNames: branchNames,
                          isMobile: isMobile,
                          canManage:
                              widget.session.permissions.canViewInventory,
                          onAddEntry: () => _openAdditionalEntryDialog(data),
                          onSelectSession: (id) {
                            _selectedSessionId = id;
                            _load();
                          },
                        ),
                        _InventoryTab.stock => _StockItemsView(
                          items: data.stockItems,
                          isMobile: isMobile,
                          canManage:
                              widget.session.permissions.canViewInventory,
                          onCreateOrEdit: _openStockItemDialog,
                        ),
                        _InventoryTab.recipes => _RecipesView(
                          products: data.productsWithRecipes,
                          theoreticalRecipes: data.theoreticalRecipes,
                          isMobile: isMobile,
                          canManage:
                              widget.session.permissions.canViewInventory,
                          onCreateOrEditRecipe: (r) =>
                              _openTheoreticalRecipeDialog(
                            r,
                            data.allProducts,
                            data.stockItems,
                          ),
                        ),
                        _InventoryTab.yields => _YieldProfilesView(
                          profiles: data.yieldProfiles,
                          canManage:
                              widget.session.permissions.canViewInventory,
                          onCreateOrEdit: (p) =>
                              _openYieldProfileDialog(p, data.stockItems),
                        ),
                        _InventoryTab.stockOuts => _StockOutsView(
                          rows: data.stockOuts,
                          branchNames: branchNames,
                          isMobile: isMobile,
                          canManage:
                              widget.session.permissions.canViewInventory,
                          onClearStockOut: _clearStockOut,
                        ),
                      },
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventorySummaryRow extends StatelessWidget {
  const _InventorySummaryRow({required this.data, required this.isMobile});

  final InventoryDashboardData data;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final activeItems = data.stockItems.where((i) => i.active).length;
    final totalWaste = data.sessionItems.fold<double>(
      0,
      (acc, i) => acc + i.wasteQty,
    );

    final cards = [
      (
        'Insumos activos',
        '$activeItems',
        '${data.stockItems.length} registrados',
        tokens.brandAccent,
      ),
      (
        'Sesiones de cocina',
        '${data.sessions.length}',
        'En periodo seleccionado',
        tokens.info,
      ),
      (
        'Merma del turno',
        totalWaste.toStringAsFixed(2),
        data.selectedSession != null
            ? 'Sesión ${data.selectedSession!.businessDate}'
            : 'Sin sesión activa',
        tokens.warning,
      ),
      (
        'Agotados activos',
        '${data.activeStockOutsCount}',
        '${data.stockOuts.length} eventos totales',
        data.activeStockOutsCount > 0 ? tokens.danger : tokens.success,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        final width = (constraints.maxWidth - (12 * (cols - 1))) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map(
                (c) => SizedBox(
                  width: width,
                  child: SaasCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.$1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: tokens.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          c.$2,
                          style: TextStyle(
                            fontSize: isMobile ? 19 : 22,
                            fontWeight: FontWeight.w700,
                            color: c.$4,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.$3,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _KitchenSessionsView extends StatelessWidget {
  const _KitchenSessionsView({
    required this.data,
    required this.branchNames,
    required this.isMobile,
    required this.canManage,
    required this.onAddEntry,
    required this.onSelectSession,
  });

  final InventoryDashboardData data;
  final Map<String, String> branchNames;
  final bool isMobile;
  final bool canManage;
  final VoidCallback onAddEntry;
  final ValueChanged<String> onSelectSession;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    if (data.sessions.isEmpty) {
      return const SaasEmptyState(
        icon: Icons.kitchen_outlined,
        title: 'Sin sesiones de cocina',
        message: 'No hay aperturas ni cierres de cocina en este periodo.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaasCard(
          title: 'Sesiones de cocina',
          subtitle: 'Selecciona una sesión para ver el desglose por insumo.',
          padding: EdgeInsets.zero,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: data.sessions.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
            itemBuilder: (context, index) {
              final s = data.sessions[index];
              final selected = s.id == data.selectedSession?.id;
              return ListTile(
                selected: selected,
                onTap: () => onSelectSession(s.id),
                title: Text(
                  '${s.businessDate} · ${branchNames[s.branchId] ?? s.branchName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                subtitle: Text(
                  'Abrió: ${s.openedByEmployeeName}${s.closedByEmployeeName != null && s.closedByEmployeeName!.isNotEmpty ? ' · Cerró: ${s.closedByEmployeeName}' : ''}',
                  style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                ),
                trailing: StatusPill(
                  label: s.isOpen ? 'Abierta' : 'Cerrada',
                  tone: s.isOpen ? StatusTone.success : StatusTone.neutral,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        if (data.selectedSession != null)
          SaasCard(
            title:
                'Control de insumos — ${data.selectedSession!.businessDate}',
            subtitle:
                'Sobrante previo, entradas, sobrante final, merma, usado, vendido y diferencia.',
            trailing: canManage &&
                    data.selectedSession!.isOpen &&
                    data.sessionItems.isNotEmpty
                ? OutlinedButton.icon(
                    onPressed: onAddEntry,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Entrada adicional'),
                  )
                : null,
            padding: data.sessionItems.isEmpty
                ? const EdgeInsets.all(20)
                : EdgeInsets.zero,
            child: data.sessionItems.isEmpty
                ? Text(
                    'Esta sesión no tiene movimientos de insumos registrados.',
                    style: TextStyle(fontSize: 13, color: tokens.textSecondary),
                  )
                : isMobile
                ? ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: data.sessionItems.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: tokens.border),
                    itemBuilder: (context, index) {
                      final item = data.sessionItems[index];
                      final entries =
                          item.todayInputQty + item.additionalEntriesQty;
                      final diff = item.usefulConsumedQty - item.soldQty;
                      return Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.name} (${item.unit})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                                StatusPill(
                                  label:
                                      'Dif: ${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(2)}',
                                  tone: diff.abs() > 0.5
                                      ? StatusTone.warning
                                      : StatusTone.success,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 14,
                              runSpacing: 6,
                              children: [
                                Text(
                                  'Previo: ${item.previousRemainingQty.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Entradas: ${entries.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Final: ${item.finalRemainingQty.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Merma: ${item.wasteQty.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Usado: ${item.usedQty.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  'Vendido: ${item.soldQty.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Insumo')),
                        DataColumn(label: Text('Unidad')),
                        DataColumn(label: Text('Previo'), numeric: true),
                        DataColumn(label: Text('Entradas'), numeric: true),
                        DataColumn(label: Text('Final'), numeric: true),
                        DataColumn(label: Text('Merma'), numeric: true),
                        DataColumn(label: Text('Usado'), numeric: true),
                        DataColumn(label: Text('Vendido'), numeric: true),
                        DataColumn(label: Text('Diferencia'), numeric: true),
                      ],
                      rows: data.sessionItems.map((item) {
                        final entries =
                            item.todayInputQty + item.additionalEntriesQty;
                        final diff = item.usefulConsumedQty - item.soldQty;
                        return DataRow(
                          cells: [
                            DataCell(Text(item.name)),
                            DataCell(Text(item.unit)),
                            DataCell(
                              Text(
                                item.previousRemainingQty.toStringAsFixed(2),
                              ),
                            ),
                            DataCell(Text(entries.toStringAsFixed(2))),
                            DataCell(
                              Text(item.finalRemainingQty.toStringAsFixed(2)),
                            ),
                            DataCell(Text(item.wasteQty.toStringAsFixed(2))),
                            DataCell(Text(item.usedQty.toStringAsFixed(2))),
                            DataCell(Text(item.soldQty.toStringAsFixed(2))),
                            DataCell(
                              Text(
                                '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: diff.abs() > 0.5
                                      ? tokens.warning
                                      : tokens.success,
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
      ],
    );
  }
}

class _StockItemsView extends StatelessWidget {
  const _StockItemsView({
    required this.items,
    required this.isMobile,
    required this.canManage,
    required this.onCreateOrEdit,
  });

  final List<KitchenStockItem> items;
  final bool isMobile;
  final bool canManage;
  final ValueChanged<KitchenStockItem?> onCreateOrEdit;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    if (items.isEmpty) {
      return Column(
        children: [
          const SaasEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Sin insumos registrados',
            message: 'Aún no hay catálogo de insumos de cocina configurado.',
          ),
          if (canManage) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => onCreateOrEdit(null),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Nuevo insumo'),
            ),
          ],
        ],
      );
    }
    return SaasCard(
      title: 'Catálogo de insumos de cocina',
      subtitle: '${items.length} insumo(s) configurado(s)',
      trailing: canManage
          ? FilledButton.icon(
              onPressed: () => onCreateOrEdit(null),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Nuevo insumo'),
            )
          : null,
      padding: EdgeInsets.zero,
      child: isMobile
          ? ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  onTap: canManage ? () => onCreateOrEdit(item) : null,
                  title: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${item.category} · Unidad: ${item.unit}${item.defaultSupplierName != null && item.defaultSupplierName!.isNotEmpty ? ' · Proveedor: ${item.defaultSupplierName}' : ''}',
                    style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                  ),
                  trailing: StatusPill(
                    label: item.active ? 'Activo' : 'Inactivo',
                    tone: item.active ? StatusTone.success : StatusTone.neutral,
                  ),
                );
              },
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Insumo')),
                  DataColumn(label: Text('Categoría')),
                  DataColumn(label: Text('Unidad')),
                  DataColumn(label: Text('Consumo óptimo')),
                  DataColumn(label: Text('Proveedor habitual')),
                  DataColumn(label: Text('Estado')),
                ],
                rows: items.map((item) {
                  return DataRow(
                    onSelectChanged: canManage ? (_) => onCreateOrEdit(item) : null,
                    cells: [
                      DataCell(Text(item.name)),
                      DataCell(Text(item.category)),
                      DataCell(Text(item.unit)),
                      DataCell(
                        Text(
                          item.optimalConsumptionPerSaleQty > 0
                              ? '${item.optimalConsumptionPerSaleQty.toStringAsFixed(2)} ${item.optimalConsumptionUnit}'
                              : '—',
                        ),
                      ),
                      DataCell(
                        Text(
                          (item.defaultSupplierName ?? '').isEmpty
                              ? '—'
                              : item.defaultSupplierName!,
                        ),
                      ),
                      DataCell(
                        StatusPill(
                          label: item.active ? 'Activo' : 'Inactivo',
                          tone: item.active
                              ? StatusTone.success
                              : StatusTone.neutral,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }
}

class _RecipesView extends StatelessWidget {
  const _RecipesView({
    required this.products,
    required this.theoreticalRecipes,
    required this.isMobile,
    required this.canManage,
    required this.onCreateOrEditRecipe,
  });

  final List<Product> products;
  final List<TheoreticalProductRecipe> theoreticalRecipes;
  final bool isMobile;
  final bool canManage;
  final ValueChanged<TheoreticalProductRecipe?> onCreateOrEditRecipe;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaasCard(
          title: 'Recetas teóricas de rentabilidad',
          subtitle:
              '${theoreticalRecipes.length} receta(s) configuradas para cálculo de costo',
          trailing: canManage
              ? FilledButton.icon(
                  onPressed: () => onCreateOrEditRecipe(null),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Nueva receta'),
                )
              : null,
          padding: theoreticalRecipes.isEmpty
              ? const EdgeInsets.all(20)
              : EdgeInsets.zero,
          child: theoreticalRecipes.isEmpty
              ? const Text(
                  'Aún no hay recetas teóricas registradas. Crea una para calcular rentabilidad.',
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: theoreticalRecipes.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: tokens.border),
                  itemBuilder: (context, i) {
                    final r = theoreticalRecipes[i];
                    final summary = r.ingredients
                        .map(
                          (ing) =>
                              '${ing.stockItemName}: ${ing.quantity} ${ing.unit} (${ing.inputStage})',
                        )
                        .join(' · ');
                    return ListTile(
                      onTap: canManage ? () => onCreateOrEditRecipe(r) : null,
                      title: Text(
                        r.productName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        summary.isEmpty ? 'Sin ingredientes' : summary,
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textSecondary,
                        ),
                      ),
                      trailing: StatusPill(
                        label: r.recipeStatus == 'complete'
                            ? 'Completa'
                            : 'Incompleta',
                        tone: r.recipeStatus == 'complete'
                            ? StatusTone.success
                            : StatusTone.warning,
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 16),
        if (products.isEmpty)
          const SaasEmptyState(
            icon: Icons.restaurant_menu_outlined,
            title: 'Sin recetas de descuento en cocina',
            message: 'Ningún producto tiene consumo directo de insumos configurado.',
          )
        else
          SaasCard(
            title: 'Consumo operativo en cocina',
            subtitle: '${products.length} producto(s) vinculados a cocina',
            padding: EdgeInsets.zero,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: products.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: tokens.border),
              itemBuilder: (context, index) {
                final p = products[index];
                final recipeSummary = p.recipeItems.isNotEmpty
                    ? p.recipeItems
                          .map(
                            (r) =>
                                '${r.kitchenStockItemName}: ${r.consumptionFactor.toStringAsFixed(3)} ${r.kitchenStockUnit}',
                          )
                          .join(' · ')
                    : '${p.kitchenStockItemName ?? 'Insumo'}: ${(p.stockConsumptionQty ?? 0).toStringAsFixed(3)} ${p.kitchenStockUnit ?? ''}';
                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 14 : 18,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${p.categoryName} · $recipeSummary',
                              style: TextStyle(
                                fontSize: 12,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusPill(
                        label: p.active ? 'Activo' : 'Inactivo',
                        tone: p.active
                            ? StatusTone.success
                            : StatusTone.neutral,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _StockOutsView extends StatelessWidget {
  const _StockOutsView({
    required this.rows,
    required this.branchNames,
    required this.isMobile,
    required this.canManage,
    required this.onClearStockOut,
  });

  final List<ProductStockOutRow> rows;
  final Map<String, String> branchNames;
  final bool isMobile;
  final bool canManage;
  final ValueChanged<ProductStockOutRow> onClearStockOut;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    if (rows.isEmpty) {
      return const SaasEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Sin productos agotados',
        message: 'No hay alertas ni historial de agotados en este periodo.',
      );
    }
    return SaasCard(
      title: 'Alertas de productos agotados',
      subtitle: '${rows.length} registro(s) en el periodo',
      padding: EdgeInsets.zero,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
        itemBuilder: (context, index) {
          final r = rows[index];
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 18,
              vertical: 12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${branchNames[r.branchId] ?? r.branchName} · ${r.businessDate} · Reportó: ${r.soldOutByEmployeeName}',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textSecondary,
                        ),
                      ),
                      if (r.reason.isNotEmpty)
                        Text(
                          'Motivo: ${r.reason}',
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                StatusPill(
                  label: r.isActive ? 'Agotado' : 'Restablecido',
                  tone: r.isActive ? StatusTone.danger : StatusTone.success,
                ),
                if (canManage && r.isActive) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => onClearStockOut(r),
                    child: const Text('Liberar'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _YieldProfilesView extends StatelessWidget {
  const _YieldProfilesView({
    required this.profiles,
    required this.canManage,
    required this.onCreateOrEdit,
  });

  final List<IngredientYieldProfile> profiles;
  final bool canManage;
  final ValueChanged<IngredientYieldProfile?> onCreateOrEdit;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return SaasCard(
      title: 'Perfiles de rendimiento de cocina',
      subtitle: 'Conversión de insumo crudo a cocido (${profiles.length} perfil(es)).',
      trailing: canManage
          ? FilledButton.icon(
              onPressed: () => onCreateOrEdit(null),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Nuevo perfil'),
            )
          : null,
      padding: profiles.isEmpty ? const EdgeInsets.all(20) : EdgeInsets.zero,
      child: profiles.isEmpty
          ? const Text('No hay perfiles de rendimiento configurados.')
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: profiles.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: tokens.border),
              itemBuilder: (context, i) {
                final p = profiles[i];
                final tacosPerKg = (1000 * p.cookingYieldRate) / 30;
                return ListTile(
                  onTap: canManage ? () => onCreateOrEdit(p) : null,
                  title: Text(
                    p.stockItemName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Rendimiento: ${p.cookingYieldPercent.toStringAsFixed(1)}% · Merma cocción: ${p.estimatedReductionPercent.toStringAsFixed(1)}% · ~${tacosPerKg.toStringAsFixed(1)} tacos (30 g)/kg',
                    style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                  ),
                  trailing: canManage
                      ? const Icon(Icons.edit_outlined, size: 18)
                      : null,
                );
              },
            ),
    );
  }
}
