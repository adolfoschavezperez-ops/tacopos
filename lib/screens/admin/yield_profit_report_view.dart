import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/reports/yield_profit_report.dart';
import '../../core/reports/yield_profit_report_excel.dart';
import '../../core/theme/brand_colors.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/binary_exporter.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import 'recipe_yield_config_screen.dart';

class YieldProfitReportView extends StatefulWidget {
  const YieldProfitReportView({
    super.key,
    required this.repository,
    required this.startBusinessDate,
    required this.endBusinessDate,
  });

  final TacoPosRepository repository;
  final String startBusinessDate;
  final String endBusinessDate;

  @override
  State<YieldProfitReportView> createState() => _YieldProfitReportViewState();
}

class _YieldProfitReportViewState extends State<YieldProfitReportView> {
  late Future<YieldProfitReportBundle> _future;
  String _category = '';
  String _product = '';
  String _ingredient = '';
  bool _onlyWithoutRecipe = false;
  bool _onlyWithoutCost = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant YieldProfitReportView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startBusinessDate != widget.startBusinessDate ||
        oldWidget.endBusinessDate != widget.endBusinessDate) {
      _load();
    }
  }

  void _load({bool force = false}) {
    _future = widget.repository.getYieldProfitReportBundle(
      startBusinessDate: widget.startBusinessDate,
      endBusinessDate: widget.endBusinessDate,
      forceRefresh: force,
    );
  }

  Future<void> _refresh() async {
    setState(() => _load(force: true));
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<YieldProfitReportBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudo cargar el reporte',
            message: '${snapshot.error}',
          );
        }
        if (!snapshot.hasData) {
          return const LoadingPanel(
            message: 'Calculando rendimiento y utilidad...',
          );
        }
        final bundle = snapshot.data!;
        final products = _filteredProducts(bundle);
        final productIds = products.map((row) => row.productId).toSet();
        final ingredients = _filteredIngredients(bundle, productIds);
        final completeProducts = products.where((row) => row.hasCompleteCost);
        final hasCompleteCostCoverage = hasCompleteYieldCostCoverage(products);
        final includedNet = completeProducts.fold<double>(
          0,
          (sum, row) => sum + row.netSales,
        );
        final cost = completeProducts.fold<double>(
          0,
          (sum, row) => sum + (row.totalCost ?? 0),
        );
        final profit = includedNet - cost;
        final rawGrams = ingredients.fold<double>(
          0,
          (sum, row) =>
              sum +
              row.usages
                  .where((usage) => productIds.contains(usage.productId))
                  .fold<double>(
                    0,
                    (subtotal, usage) => subtotal + usage.rawEquivalent,
                  ),
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
          children: [
            _toolbar(bundle),
            const SizedBox(height: 12),
            _notice(
              Icons.science_outlined,
              'Los rendimientos y porciones iniciales son estimaciones de '
              'referencia. Los resultados no sustituyen una prueba interna '
              'de peso y coccion.',
            ),
            const SizedBox(height: 12),
            _filters(bundle),
            const SizedBox(height: 14),
            _metrics(
              products: products,
              ingredients: ingredients,
              cost: cost,
              profit: profit,
              includedNet: includedNet,
              rawGrams: rawGrams,
              hasCompleteCostCoverage: hasCompleteCostCoverage,
            ),
            if (products.isNotEmpty &&
                products.every((row) => !row.hasRecipe)) ...[
              const SizedBox(height: 12),
              _notice(
                Icons.warning_amber_outlined,
                'No es posible calcular costos hasta configurar las recetas '
                'de los productos.',
              ),
            ],
            const SizedBox(height: 18),
            const _SectionTitle('RENDIMIENTO Y UTILIDAD POR PRODUCTO'),
            const SizedBox(height: 8),
            _productTable(products),
            const SizedBox(height: 18),
            const _SectionTitle('CONSUMO TEORICO POR INGREDIENTE'),
            const SizedBox(height: 8),
            _ingredientTable(ingredients),
            const SizedBox(height: 12),
            _notice(
              Icons.info_outline,
              'Esta diferencia no representa inventario, merma ni faltante '
              'real. Parte de las compras puede continuar almacenada. Sin '
              'inventario fisico no es posible determinar consumo o merma real.',
            ),
          ],
        );
      },
    );
  }

  Widget _toolbar(YieldProfitReportBundle bundle) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Calculado con la receta vigente actualmente.',
            style: const TextStyle(color: BrandColors.textMuted),
          ),
        ),
        IconButton(
          tooltip: 'Actualizar',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _exporting ? null : () => _export(bundle),
          icon: _exporting
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
          label: Text(_exporting ? 'Generando...' : 'Exportar a Excel'),
        ),
      ],
    );
  }

  Widget _filters(YieldProfitReportBundle bundle) {
    final categories =
        bundle.report.products
            .map((row) => row.categoryName)
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final products =
        bundle.report.products.map((row) => row.productName).toList()..sort();
    final ingredients =
        bundle.report.ingredients.map((row) => row.stockItemName).toList()
          ..sort();
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      borderRadius: 8,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _dropdown(
            'Categoria',
            _category,
            categories,
            (value) => setState(() => _category = value),
          ),
          _dropdown(
            'Producto',
            _product,
            products,
            (value) => setState(() => _product = value),
          ),
          _dropdown(
            'Ingrediente',
            _ingredient,
            ingredients,
            (value) => setState(() => _ingredient = value),
          ),
          FilterChip(
            label: const Text('Solo sin receta'),
            selected: _onlyWithoutRecipe,
            onSelected: (value) => setState(() => _onlyWithoutRecipe = value),
          ),
          FilterChip(
            label: const Text('Solo sin costo'),
            selected: _onlyWithoutCost,
            onSelected: (value) => setState(() => _onlyWithoutCost = value),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    return SizedBox(
      width: 210,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isDense: true,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: '', child: Text('Todos')),
          ...options.map(
            (option) => DropdownMenuItem(
              value: option,
              child: Text(option, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (selected) => onChanged(selected ?? ''),
      ),
    );
  }

  List<YieldProductRow> _filteredProducts(YieldProfitReportBundle bundle) {
    final ingredientProductIds = _ingredient.isEmpty
        ? null
        : bundle.report.ingredients
              .where((row) => row.stockItemName == _ingredient)
              .expand((row) => row.usages)
              .map((usage) => usage.productId)
              .toSet();
    return bundle.report.products.where((row) {
      if (_category.isNotEmpty && row.categoryName != _category) return false;
      if (_product.isNotEmpty && row.productName != _product) return false;
      if (ingredientProductIds != null &&
          !ingredientProductIds.contains(row.productId)) {
        return false;
      }
      if (_onlyWithoutRecipe && row.hasRecipe) return false;
      if (_onlyWithoutCost && row.hasCompleteCost) return false;
      return true;
    }).toList();
  }

  List<YieldIngredientRow> _filteredIngredients(
    YieldProfitReportBundle bundle,
    Set<String> productIds,
  ) {
    return bundle.report.ingredients.where((row) {
      if (_ingredient.isNotEmpty && row.stockItemName != _ingredient) {
        return false;
      }
      if (!row.usages.any((usage) => productIds.contains(usage.productId))) {
        return false;
      }
      if (_onlyWithoutCost && row.cost != null) return false;
      return true;
    }).toList();
  }

  Widget _metrics({
    required List<YieldProductRow> products,
    required List<YieldIngredientRow> ingredients,
    required double cost,
    required double profit,
    required double includedNet,
    required double rawGrams,
    required bool hasCompleteCostCoverage,
  }) {
    final cards = [
      (
        'Venta neta',
        _money(products.fold(0, (sum, row) => sum + row.netSales)),
      ),
      (
        'Costo teorico de ingredientes',
        hasCompleteCostCoverage ? _money(cost) : 'No disponible',
      ),
      (
        'Utilidad bruta teorica',
        hasCompleteCostCoverage ? _money(profit) : 'No disponible',
      ),
      (
        'Margen bruto teorico',
        !hasCompleteCostCoverage || includedNet == 0
            ? 'No disponible'
            : _percent(profit / includedNet * 100),
      ),
      ('Kg crudos estimados consumidos', (rawGrams / 1000).toStringAsFixed(2)),
      (
        'Productos sin receta',
        '${products.where((row) => !row.hasRecipe).length}',
      ),
      (
        'Ingredientes sin costo',
        '${ingredients.where((row) => row.cost == null).length}',
      ),
      (
        'Recetas pendientes de validacion',
        '${products.where((row) => row.recipe?.needsInternalValidation == true).length}',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 1200
            ? (constraints.maxWidth - 36) / 4
            : constraints.maxWidth >= 700
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map(
                (card) => SizedBox(
                  width: width,
                  height: 112,
                  child: GlassPanel(
                    padding: const EdgeInsets.all(16),
                    borderRadius: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          card.$1,
                          style: const TextStyle(
                            color: BrandColors.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          card.$2,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _productTable(List<YieldProductRow> rows) {
    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Sin productos para mostrar',
        message: 'Ajusta los filtros del reporte.',
      );
    }
    return _dataTable(
      columns: const [
        'Producto',
        'Categoria',
        'Unidades',
        'Venta bruta',
        'Descuento',
        'Venta neta',
        'Costo unitario',
        'Costo total',
        'Utilidad bruta',
        'Margen',
        'Estado',
        'Detalle',
      ],
      rows: rows.map((row) {
        final status = !row.hasRecipe
            ? 'Sin receta'
            : !row.hasCompleteCost
            ? 'Costo incompleto'
            : row.recipe!.needsInternalValidation
            ? 'Pendiente'
            : 'Validada';
        return [
          Text(row.productName),
          Text(row.categoryName),
          Text('${row.unitsSold}'),
          Text(_money(row.grossSales)),
          Text(_money(row.discountAllocated)),
          Text(_money(row.netSales)),
          Text(row.unitCost == null ? 'No disponible' : _money(row.unitCost!)),
          Text(
            row.totalCost == null ? 'No disponible' : _money(row.totalCost!),
          ),
          Text(
            row.grossProfit == null
                ? 'No disponible'
                : _money(row.grossProfit!),
          ),
          Text(
            row.grossMarginPercent == null
                ? '-'
                : _percent(row.grossMarginPercent!),
          ),
          Text(status),
          row.hasRecipe
              ? IconButton(
                  tooltip: 'Ver detalle',
                  onPressed: () => _showProductDetail(row),
                  icon: const Icon(Icons.visibility_outlined),
                )
              : TextButton(
                  onPressed: _openConfiguration,
                  child: const Text('Configurar receta'),
                ),
        ];
      }).toList(),
    );
  }

  Widget _ingredientTable(List<YieldIngredientRow> rows) {
    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Sin ingredientes para mostrar',
        message: 'No hay consumo teorico para los filtros seleccionados.',
      );
    }
    return _dataTable(
      columns: const [
        'Ingrediente',
        'Unidad compra',
        'Rendimiento',
        'Reduccion estimada',
        'Cocido teorico',
        'Crudo estimado',
        'Costo promedio',
        'Costo consumido',
        'Compras periodo',
        'Diferencia estimada',
        'Estado',
        'Detalle',
      ],
      rows: rows.map((row) {
        return [
          Text(row.stockItemName),
          Text(row.purchaseUnit),
          Text(
            row.profile == null
                ? 'No configurado'
                : _percent(row.profile!.cookingYieldPercent),
          ),
          Text(
            row.profile == null
                ? '-'
                : _percent(row.profile!.estimatedReductionPercent),
          ),
          Text(_baseQuantity(row.cookedQuantity, row.purchaseUnit)),
          Text(_baseQuantity(row.rawEstimatedQuantity, row.purchaseUnit)),
          Text(
            row.cost == null
                ? 'Sin costo registrado'
                : _cost(row.cost!.costPerBaseUnit, row.purchaseUnit),
          ),
          Text(
            row.theoreticalConsumedCost == null
                ? 'No disponible'
                : _money(row.theoreticalConsumedCost!),
          ),
          Text(_baseQuantity(row.purchasedInPeriod, row.purchaseUnit)),
          Text(_baseQuantity(row.estimatedDifference, row.purchaseUnit)),
          Text(row.cost?.source ?? 'Sin costo registrado'),
          IconButton(
            tooltip: 'Ver detalle',
            onPressed: () => _showIngredientDetail(row),
            icon: const Icon(Icons.visibility_outlined),
          ),
        ];
      }).toList(),
    );
  }

  Widget _dataTable({
    required List<String> columns,
    required List<List<Widget>> rows,
  }) {
    return GlassPanel(
      padding: EdgeInsets.zero,
      borderRadius: 8,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 48,
          dataRowMinHeight: 48,
          dataRowMaxHeight: 64,
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

  void _showProductDetail(YieldProductRow row) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(row.productName),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detail('Unidades vendidas', '${row.unitsSold}'),
                _detail(
                  'Precio promedio de venta',
                  row.unitsSold == 0
                      ? '-'
                      : _money(row.netSales / row.unitsSold),
                ),
                _detail('Venta bruta', _money(row.grossSales)),
                _detail('Descuento asignado', _money(row.discountAllocated)),
                _detail('Venta neta', _money(row.netSales)),
                const Divider(),
                for (final ingredient in row.recipe!.ingredients)
                  _detail(
                    ingredient.stockItemName,
                    '${ingredient.baseQuantity.toStringAsFixed(2)} ${ingredient.unit} '
                    '(${ingredient.inputStage})',
                  ),
                const Divider(),
                _detail(
                  'Costo teorico de ingredientes',
                  row.unitCost == null
                      ? 'Incompleto: ${row.missingCostIngredients.join(', ')}'
                      : _money(row.unitCost!),
                ),
                _detail(
                  'Utilidad bruta teorica',
                  row.grossProfit == null
                      ? 'No disponible'
                      : _money(row.grossProfit!),
                ),
                _detail(
                  'Margen bruto',
                  row.grossMarginPercent == null
                      ? 'No disponible'
                      : _percent(row.grossMarginPercent!),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Calculo realizado con receta y rendimientos provisionales.',
                  style: TextStyle(color: BrandColors.textMuted),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showIngredientDetail(YieldIngredientRow row) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(row.stockItemName),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detail(
                  'Rendimiento provisional',
                  row.profile == null
                      ? 'No configurado'
                      : _percent(row.profile!.cookingYieldPercent),
                ),
                _detail(
                  'Reduccion estimada',
                  row.profile == null
                      ? '-'
                      : _percent(row.profile!.estimatedReductionPercent),
                ),
                _detail(
                  'Costo promedio',
                  row.cost == null
                      ? 'Sin costo registrado'
                      : _cost(row.cost!.costPerBaseUnit, row.purchaseUnit),
                ),
                _detail(
                  'Consumo cocido teorico',
                  _baseQuantity(row.cookedQuantity, row.purchaseUnit),
                ),
                _detail(
                  'Equivalente crudo estimado',
                  _baseQuantity(row.rawEstimatedQuantity, row.purchaseUnit),
                ),
                _detail(
                  'Costo consumido estimado',
                  row.theoreticalConsumedCost == null
                      ? 'No disponible'
                      : _money(row.theoreticalConsumedCost!),
                ),
                const Divider(),
                const Text(
                  'Productos que lo consumieron',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                for (final usage in row.usages)
                  _detail(
                    usage.productName,
                    '${usage.unitsSold} x ${usage.portion.toStringAsFixed(2)} = '
                    '${usage.theoreticalInput.toStringAsFixed(2)} ${usage.inputStage == 'cooked' ? 'g cocidos' : 'unidades base'}',
                  ),
                const Divider(),
                Text(
                  'Compras utilizadas para el costo: ${row.cost?.purchaseLines.length ?? 0}',
                  style: const TextStyle(color: BrandColors.textMuted),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Text(
              label,
              style: const TextStyle(color: BrandColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openConfiguration() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecipeYieldConfigScreen()),
    );
    if (mounted) setState(() => _load(force: true));
  }

  Future<void> _export(YieldProfitReportBundle bundle) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final session = AppSession.instance;
      final bytes = buildYieldProfitWorkbook(
        bundle: bundle,
        restaurantName: session.currentRestaurantName,
        branchName: session.currentBranchName,
      );
      final branch = session.currentBranchName
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final message = await exportBinaryFile(
        fileName:
            'Rendimiento_Utilidad_${branch}_${widget.startBusinessDate}_${widget.endBusinessDate}.xlsx',
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (mounted) showAppSnackBar(context, message);
    } catch (error) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudo exportar: $error',
          type: AppSnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _notice(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BrandColors.accentYellow.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: BrandColors.accentYellow.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: BrandColors.accentYellow),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: BrandColors.accentYellow,
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

String _money(double value) => NumberFormat.currency(
  locale: 'es_MX',
  symbol: r'$',
  decimalDigits: 2,
).format(value);

String _percent(double value) => '${value.toStringAsFixed(2)}%';

String _baseQuantity(double value, String purchaseUnit) {
  final isWeight = const {
    'kg',
    'g',
    'gr',
    'gramos',
  }.contains(normalizeYieldName(purchaseUnit));
  if (isWeight) return '${(value / 1000).toStringAsFixed(2)} kg';
  return '${value.toStringAsFixed(2)} $purchaseUnit';
}

String _cost(double costPerBase, String purchaseUnit) {
  final isWeight = const {
    'kg',
    'g',
    'gr',
    'gramos',
  }.contains(normalizeYieldName(purchaseUnit));
  return isWeight
      ? '${_money(costPerBase * 1000)}/kg'
      : '${_money(costPerBase)}/$purchaseUnit';
}
