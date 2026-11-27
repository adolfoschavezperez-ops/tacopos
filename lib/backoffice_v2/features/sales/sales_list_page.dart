import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/order.dart';
import '../../auth/backoffice_session.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../widgets/data_table_pro.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/filter_bar.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/status_pill.dart';
import 'sales_repository.dart';

class SalesListPage extends StatefulWidget {
  const SalesListPage({
    super.key,
    required this.session,
    required this.repository,
    required this.onSelectSale,
  });

  final BackofficeSession session;
  final SalesRepository repository;
  final ValueChanged<String> onSelectSale;

  @override
  State<SalesListPage> createState() => _SalesListPageState();
}

class _SalesListPageState extends State<SalesListPage> {
  DatePreset _preset = DatePreset.last7Days;
  late DateTime _startDate;
  late DateTime _endDate;
  String? _statusFilter;
  final TextEditingController _searchController = TextEditingController();

  final List<DocumentSnapshot<Map<String, dynamic>>?> _cursorStack = [null];
  int _pageIndex = 0;
  Future<SalesCursorPage>? _future;
  String? _lastBranchId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _endDate = DateTime(now.year, now.month, now.day);
    _startDate = _endDate.subtract(const Duration(days: 6));
    _lastBranchId = widget.session.selectedBranchId;
    widget.session.addListener(_onSessionChanged);
    _resetAndLoad();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (_lastBranchId != widget.session.selectedBranchId) {
      _lastBranchId = widget.session.selectedBranchId;
      _resetAndLoad();
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
          break;
        case DatePreset.last7Days:
          _startDate = today.subtract(const Duration(days: 6));
          _endDate = today;
          break;
        case DatePreset.last30Days:
          _startDate = today.subtract(const Duration(days: 29));
          _endDate = today;
          break;
        case DatePreset.last90Days:
          _startDate = today.subtract(const Duration(days: 89));
          _endDate = today;
          break;
        case DatePreset.monthToDate:
          _startDate = DateTime(today.year, today.month, 1);
          _endDate = today;
          break;
        case DatePreset.custom:
          break;
      }
    });
    _resetAndLoad();
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _preset = DatePreset.custom;
      _startDate = picked.start;
      _endDate = picked.end;
    });
    _resetAndLoad();
  }

  void _resetAndLoad() {
    _cursorStack
      ..clear()
      ..add(null);
    _pageIndex = 0;
    _loadCurrentPage();
  }

  void _loadCurrentPage() {
    setState(() {
      _future = widget.repository.fetchSalesPage(
        restaurantId: widget.session.restaurantId,
        startBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_startDate),
        endBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_endDate),
        branchId: widget.session.selectedBranchId,
        statusFilter: _statusFilter,
        startAfter: _cursorStack[_pageIndex],
        pageSize: 20,
      );
    });
  }

  void _goNext(DocumentSnapshot<Map<String, dynamic>>? lastDoc) {
    if (lastDoc == null) return;
    if (_cursorStack.length <= _pageIndex + 1) {
      _cursorStack.add(lastDoc);
    } else {
      _cursorStack[_pageIndex + 1] = lastDoc;
    }
    _pageIndex++;
    _loadCurrentPage();
  }

  void _goPrevious() {
    if (_pageIndex == 0) return;
    _pageIndex--;
    _loadCurrentPage();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final branchNames = {
      for (final b in widget.session.branches) b.id: b.name,
    };

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ventas',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Consulta paginada por cursores en Firestore • ${widget.session.selectedBranchLabel}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _resetAndLoad,
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('Actualizar'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SaasFilterBar(
          activePreset: _preset,
          startDateLabel: BackofficeSalesAdapter.formatBusinessDate(_startDate),
          endDateLabel: BackofficeSalesAdapter.formatBusinessDate(_endDate),
          onPresetSelected: _applyPreset,
          onPickCustomRange: _pickCustomRange,
          searchController: _searchController,
          searchHint: 'Filtrar página por folio, mesa o plataforma...',
          onSearchSubmitted: (_) => setState(() {}),
          trailingActions: [
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String?>(
                initialValue: _statusFilter,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Estado'),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                  DropdownMenuItem<String?>(
                    value: 'paid',
                    child: Text('Pagadas'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'open',
                    child: Text('Abiertas'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'cancelled',
                    child: Text('Canceladas'),
                  ),
                ],
                onChanged: (value) {
                  _statusFilter = value;
                  _resetAndLoad();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<SalesCursorPage>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const TableSkeleton(rows: 8);
            }
            if (snapshot.hasError) {
              return SaasErrorState(
                title: 'Error al consultar ventas',
                message: snapshot.error.toString(),
                onRetry: _resetAndLoad,
              );
            }
            final page = snapshot.data;
            if (page == null || page.orders.isEmpty) {
              return const SaasEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Sin ventas en este rango',
                message:
                    'Ajusta el filtro de fechas, sucursal o estado para consultar órdenes.',
              );
            }

            final query = _searchController.text.trim().toLowerCase();
            final filtered = query.isEmpty
                ? page.orders
                : page.orders.where((o) {
                    return BackofficeSalesAdapter.resolveFolioLabel(o)
                            .toLowerCase()
                            .contains(query) ||
                        o.tableName.toLowerCase().contains(query) ||
                        (o.platformName ?? '').toLowerCase().contains(query) ||
                        o.id.toLowerCase().contains(query);
                  }).toList();

            return DataTablePro<PosOrder>(
              items: filtered,
              onRowTap: (o) => widget.onSelectSale(o.id),
              hasPrevious: _pageIndex > 0,
              hasNext: page.hasNext,
              onPrevious: _goPrevious,
              onNext: () => _goNext(page.lastDocument),
              pageLabel: 'Página ${_pageIndex + 1}',
              footerSummary:
                  '${filtered.length} orden(es) en esta página (límite servidor: 20)',
              columns: [
                SaasColumn(
                  label: 'Folio',
                  flex: 2,
                  cellBuilder: (o) => Text(
                    BackofficeSalesAdapter.resolveFolioLabel(o),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                SaasColumn(
                  label: 'Sucursal',
                  flex: 2,
                  cellBuilder: (o) => Text(
                    branchNames[o.branchId] ?? o.branchId,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                SaasColumn(
                  label: 'Canal / Mesa',
                  flex: 2,
                  cellBuilder: (o) => Text(
                    o.tableName.isNotEmpty
                        ? o.tableName
                        : ((o.platformName ?? '').isNotEmpty
                              ? o.platformName!
                              : o.orderType),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                SaasColumn(
                  label: 'Fecha operativa',
                  flex: 2,
                  cellBuilder: (o) => Text(
                    BackofficeSalesAdapter.resolveOrderBusinessDate(o),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                SaasColumn(
                  label: 'Estado',
                  flex: 1,
                  cellBuilder: (o) => switch (o.status) {
                    'paid' => const StatusPill(
                      label: 'Pagada',
                      tone: StatusTone.success,
                    ),
                    'cancelled' => const StatusPill(
                      label: 'Cancelada',
                      tone: StatusTone.danger,
                    ),
                    _ => const StatusPill(
                      label: 'Abierta',
                      tone: StatusTone.warning,
                    ),
                  },
                ),
                SaasColumn(
                  label: 'Total',
                  flex: 1,
                  alignRight: true,
                  cellBuilder: (o) => Text(
                    BackofficeSalesAdapter.formatMoney(o.total),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
