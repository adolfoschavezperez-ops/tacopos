import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/kitchen_session.dart';
import '../../models/kitchen_stock_item.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';

class KitchenAdminScreen extends StatefulWidget {
  const KitchenAdminScreen({super.key});

  @override
  State<KitchenAdminScreen> createState() => _KitchenAdminScreenState();
}

class _KitchenAdminScreenState extends State<KitchenAdminScreen> {
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = _startDate;
  }

  String get _startBusinessDate => DateFormat('yyyy-MM-dd').format(_startDate);
  String get _endBusinessDate => DateFormat('yyyy-MM-dd').format(_endDate);

  String get _rangeLabel => _startBusinessDate == _endBusinessDate
      ? (_isToday(_startDate) ? 'Hoy' : _startBusinessDate)
      : '$_startBusinessDate a $_endBusinessDate';

  Future<void> _pickStart() async {
    final picked = await _pickDate(_startDate);
    if (picked == null || !mounted) return;
    setState(() {
      _startDate = picked;
      if (_endDate.isBefore(_startDate)) _endDate = _startDate;
    });
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDate(_endDate);
    if (picked == null || !mounted) return;
    setState(() {
      _endDate = picked;
      if (_startDate.isAfter(_endDate)) _startDate = _endDate;
    });
  }

  Future<DateTime?> _pickDate(DateTime initialDate) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 2),
    );
  }

  void _today() {
    final now = DateTime.now();
    setState(() {
      _startDate = DateTime(now.year, now.month, now.day);
      _endDate = _startDate;
    });
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final employee = AppSession.instance.employee;
    final canView =
        employee?.canViewKitchenReports == true ||
        employee?.canManageKitchenStock == true;
    if (!canView) {
      return const BrandedScaffold(
        title: 'Control de cocina',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para reportes de cocina.',
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: BrandedScaffold(
        title: 'Control de cocina',
        body: Column(
          children: [
            _DateRangePanel(
              label: _rangeLabel,
              startBusinessDate: _startBusinessDate,
              endBusinessDate: _endBusinessDate,
              onPickStart: _pickStart,
              onPickEnd: _pickEnd,
              onToday: _today,
            ),
            const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.analytics_outlined), text: 'Reporte'),
                Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Insumos'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _KitchenReportTab(
                    startBusinessDate: _startBusinessDate,
                    endBusinessDate: _endBusinessDate,
                  ),
                  const _KitchenStockCatalogTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateRangePanel extends StatelessWidget {
  const _DateRangePanel({
    required this.label,
    required this.startBusinessDate,
    required this.endBusinessDate,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onToday,
  });

  final String label;
  final String startBusinessDate;
  final String endBusinessDate;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
      child: GlassPanel(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Viendo: $label',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            OutlinedButton.icon(
              onPressed: onPickStart,
              icon: const Icon(Icons.event_outlined),
              label: Text('Inicial: $startBusinessDate'),
            ),
            OutlinedButton.icon(
              onPressed: onPickEnd,
              icon: const Icon(Icons.event_available_outlined),
              label: Text('Final: $endBusinessDate'),
            ),
            TextButton.icon(
              onPressed: onToday,
              icon: const Icon(Icons.today_outlined),
              label: const Text('Hoy'),
            ),
          ],
        ),
      ),
    );
  }
}

class _KitchenReportTab extends StatelessWidget {
  const _KitchenReportTab({
    required this.startBusinessDate,
    required this.endBusinessDate,
  });

  final String startBusinessDate;
  final String endBusinessDate;

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();
    return StreamBuilder<List<KitchenSession>>(
      stream: repository.watchKitchenSessions(
        startBusinessDate: startBusinessDate,
        endBusinessDate: endBusinessDate,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudieron cargar cierres',
            message: '${snapshot.error}',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPanel(message: 'Cargando reporte...');
        }
        final sessions = snapshot.data ?? [];
        if (sessions.isEmpty) {
          return const EmptyState(
            icon: Icons.analytics_outlined,
            title: 'Sin control de cocina',
            message: 'No hay aperturas de cocina en este rango.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const SectionHeader(
              title: 'Reporte de cocina',
              subtitle: 'Consumo operativo y rendimiento por insumo.',
            ),
            const SizedBox(height: 18),
            ...sessions.map(
              (session) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _KitchenSessionReportCard(
                  session: session,
                  repository: repository,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KitchenSessionReportCard extends StatelessWidget {
  const _KitchenSessionReportCard({
    required this.session,
    required this.repository,
  });

  final KitchenSession session;
  final TacoPosRepository repository;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: StreamBuilder<List<KitchenSessionItem>>(
        stream: repository.watchKitchenSessionItems(session.id),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Fecha ${session.businessDate}',
                subtitle:
                    '${session.status} | abre ${session.openedByEmployeeName ?? 'Empleado'} | cierra ${session.closedByEmployeeName ?? 'Sin cierre'}',
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Insumo')),
                    DataColumn(label: Text('Unidad')),
                    DataColumn(label: Text('Anterior')),
                    DataColumn(label: Text('Entradas')),
                    DataColumn(label: Text('Disponible')),
                    DataColumn(label: Text('Sobrante')),
                    DataColumn(label: Text('Merma')),
                    DataColumn(label: Text('Consumo util')),
                    DataColumn(label: Text('Vendido')),
                    DataColumn(label: Text('Rendimiento')),
                  ],
                  rows: items
                      .map(
                        (item) => DataRow(
                          cells: [
                            DataCell(Text(item.name)),
                            DataCell(Text(item.unit)),
                            DataCell(Text(_qty(item.previousRemainingQty))),
                            DataCell(Text(_qty(item.todayInputQty))),
                            DataCell(Text(_qty(item.availableQty))),
                            DataCell(Text(_qty(item.finalRemainingQty))),
                            DataCell(Text(_qty(item.wasteQty))),
                            DataCell(Text(_qty(item.usefulConsumedQty))),
                            DataCell(Text(_qty(item.soldQty))),
                            DataCell(Text(_qty(item.yieldQtyPerUnit))),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _qty(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }
}

class _KitchenStockCatalogTab extends StatefulWidget {
  const _KitchenStockCatalogTab();

  @override
  State<_KitchenStockCatalogTab> createState() =>
      _KitchenStockCatalogTabState();
}

class _KitchenStockCatalogTabState extends State<_KitchenStockCatalogTab> {
  final _repository = TacoPosRepository();

  @override
  void initState() {
    super.initState();
    _repository.ensureDefaultKitchenStockItems();
  }

  Future<void> _showDialog({KitchenStockItem? item}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _KitchenStockDialog(repository: _repository, item: item),
    );
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          item == null ? 'Insumo agregado.' : 'Insumo actualizado.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canManage =
        AppSession.instance.employee?.canManageKitchenStock == true;
    return StreamBuilder<List<KitchenStockItem>>(
      stream: _repository.watchKitchenStockItems(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudieron cargar insumos',
            message: '${snapshot.error}',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPanel(message: 'Cargando insumos...');
        }
        final items = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            SectionHeader(
              title: 'Insumos controlados',
              subtitle: '${items.length} insumos configurados',
              trailing: canManage
                  ? IconButton(
                      tooltip: 'Agregar insumo',
                      onPressed: () => _showDialog(),
                      icon: const Icon(Icons.add),
                    )
                  : null,
            ),
            const SizedBox(height: 18),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  accent: item.active
                      ? BrandColors.info
                      : BrandColors.textMuted,
                  child: ListTile(
                    leading: Icon(
                      item.active ? Icons.inventory_2_outlined : Icons.block,
                      color: item.active
                          ? BrandColors.info
                          : BrandColors.textMuted,
                    ),
                    title: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      '${item.category} | ${item.unit} | orden ${item.sortOrder}',
                    ),
                    trailing: canManage
                        ? Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Editar',
                                onPressed: () => _showDialog(item: item),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: item.active ? 'Desactivar' : 'Activar',
                                onPressed: () =>
                                    _repository.toggleKitchenStockItem(item),
                                icon: Icon(
                                  item.active
                                      ? Icons.toggle_on
                                      : Icons.toggle_off,
                                ),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KitchenStockDialog extends StatefulWidget {
  const _KitchenStockDialog({required this.repository, this.item});

  final TacoPosRepository repository;
  final KitchenStockItem? item;

  @override
  State<_KitchenStockDialog> createState() => _KitchenStockDialogState();
}

class _KitchenStockDialogState extends State<_KitchenStockDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _sortController;
  late String _category;
  late String _unit;
  late bool _active;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameController = TextEditingController(text: item?.name ?? '');
    _sortController = TextEditingController(text: '${item?.sortOrder ?? 1}');
    _category = item?.category ?? 'meat';
    _unit = item?.unit ?? 'kg';
    _active = item?.active ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sortController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final sortOrder = int.tryParse(_sortController.text.trim());
    if (_nameController.text.trim().isEmpty || sortOrder == null) {
      setState(() => _error = 'Captura nombre y orden validos.');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await widget.repository.saveKitchenStockItem(
        itemId: widget.item?.id,
        name: _nameController.text,
        category: _category,
        unit: _unit,
        active: _active,
        sortOrder: sortOrder,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Agregar insumo' : 'Editar insumo'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
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
              const SizedBox(height: 12),
              TextField(
                controller: _sortController,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Orden'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activo'),
                value: _active,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _active = value),
              ),
              if (_error.isNotEmpty)
                Text(
                  _error,
                  style: const TextStyle(
                    color: BrandColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando...' : 'Listo'),
        ),
      ],
    );
  }
}
