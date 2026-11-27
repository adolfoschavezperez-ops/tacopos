import 'package:flutter/material.dart';

import '../../../models/kitchen_stock_item.dart';
import '../../../models/product.dart';
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

enum _InventoryTab { kitchen, stock, recipes, stockOuts }

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
                          onSelectSession: (id) {
                            _selectedSessionId = id;
                            _load();
                          },
                        ),
                        _InventoryTab.stock => _StockItemsView(
                          items: data.stockItems,
                          isMobile: isMobile,
                        ),
                        _InventoryTab.recipes => _RecipesView(
                          products: data.productsWithRecipes,
                          isMobile: isMobile,
                        ),
                        _InventoryTab.stockOuts => _StockOutsView(
                          rows: data.stockOuts,
                          branchNames: branchNames,
                          isMobile: isMobile,
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
    required this.onSelectSession,
  });

  final InventoryDashboardData data;
  final Map<String, String> branchNames;
  final bool isMobile;
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
  const _StockItemsView({required this.items, required this.isMobile});

  final List<KitchenStockItem> items;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    if (items.isEmpty) {
      return const SaasEmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Sin insumos registrados',
        message: 'Aún no hay catálogo de insumos de cocina configurado.',
      );
    }
    return SaasCard(
      title: 'Catálogo de insumos de cocina',
      subtitle: '${items.length} insumo(s) configurado(s)',
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
  const _RecipesView({required this.products, required this.isMobile});

  final List<Product> products;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    if (products.isEmpty) {
      return const SaasEmptyState(
        icon: Icons.restaurant_menu_outlined,
        title: 'Sin recetas vinculadas',
        message: 'Ningún producto tiene consumo de insumos configurado.',
      );
    }
    return SaasCard(
      title: 'Recetas y consumo por producto',
      subtitle: '${products.length} producto(s) vinculados a cocina',
      padding: EdgeInsets.zero,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: products.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
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
                  tone: p.active ? StatusTone.success : StatusTone.neutral,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StockOutsView extends StatelessWidget {
  const _StockOutsView({
    required this.rows,
    required this.branchNames,
    required this.isMobile,
  });

  final List<ProductStockOutRow> rows;
  final Map<String, String> branchNames;
  final bool isMobile;

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
              ],
            ),
          );
        },
      ),
    );
  }
}
