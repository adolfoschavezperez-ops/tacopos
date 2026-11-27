import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/order.dart';
import '../../../utils/csv_exporter.dart';
import '../../auth/backoffice_session.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../widgets/data_table_pro.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/filter_bar.dart';
import '../../widgets/kpi_spark_card.dart';
import '../../widgets/saas_card.dart';
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
  Future<SalesBoundedBatch>? _searchFuture;
  String? _lastBranchId;
  bool _exporting = false;
  bool _exportCancelRequested = false;
  int _exportProgressCount = 0;

  bool get _hasSearch => _searchController.text.trim().isNotEmpty;

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
      if (_hasSearch) {
        _searchFuture = widget.repository.searchOrdersInRange(
          restaurantId: widget.session.restaurantId,
          startBusinessDate: BackofficeSalesAdapter.formatBusinessDate(
            _startDate,
          ),
          endBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_endDate),
          branchId: widget.session.selectedBranchId,
          statusFilter: _statusFilter,
        );
      } else {
        _searchFuture = null;
        _future = widget.repository.fetchSalesPage(
          restaurantId: widget.session.restaurantId,
          startBusinessDate: BackofficeSalesAdapter.formatBusinessDate(
            _startDate,
          ),
          endBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_endDate),
          branchId: widget.session.selectedBranchId,
          statusFilter: _statusFilter,
          startAfter: _cursorStack[_pageIndex],
          pageSize: 20,
        );
      }
    });
  }

  List<PosOrder> _filterOrders(List<PosOrder> source) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source
        .where(
          (o) =>
              BackofficeSalesAdapter.resolveFolioLabel(
                o,
              ).toLowerCase().contains(query) ||
              o.tableName.toLowerCase().contains(query) ||
              (o.platformName ?? '').toLowerCase().contains(query) ||
              BackofficeSalesAdapter.orderChannelDisplay(
                o,
              ).toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  Future<void> _exportFullCsv(Map<String, String> branchNames) async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _exportCancelRequested = false;
      _exportProgressCount = 0;
    });
    try {
      final batch = await widget.repository.exportOrdersInRange(
        restaurantId: widget.session.restaurantId,
        startBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_startDate),
        endBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_endDate),
        branchId: widget.session.selectedBranchId,
        statusFilter: _statusFilter,
        onProgress: (loaded, _) {
          if (mounted) setState(() => _exportProgressCount = loaded);
        },
        isCancelled: () => _exportCancelRequested || !mounted,
      );
      if (batch.wasCancelled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Exportación cancelada (${batch.orders.length} registros leídos; no se generó archivo parcial).',
            ),
          ),
        );
        return;
      }
      final filtered = _filterOrders(batch.orders);
      final buf = StringBuffer()
        ..writeln('Folio,Sucursal,Canal,FechaOperativa,Estado,Descuento,Total');
      for (final o in filtered) {
        final folio = BackofficeSalesAdapter.resolveFolioLabel(o);
        final branch = (branchNames[o.branchId] ?? o.branchId).replaceAll('"', '""');
        final channel = BackofficeSalesAdapter.orderChannelDisplay(o).replaceAll('"', '""');
        final date = BackofficeSalesAdapter.resolveOrderBusinessDate(o);
        final status = BackofficeSalesAdapter.orderStatusLabel(o.status);
        buf.writeln(
          '"$folio","$branch","$channel",$date,$status,${o.explicitDiscount.toStringAsFixed(2)},${o.total.toStringAsFixed(2)}',
        );
      }
      final msg = await exportCsvFile(
        fileName:
            'ventas_${BackofficeSalesAdapter.formatBusinessDate(_startDate)}_${BackofficeSalesAdapter.formatBusinessDate(_endDate)}.csv',
        content: buf.toString(),
      );
      if (!mounted) return;
      final suffix = batch.truncated
          ? ' (exportación parcial: ${filtered.length} operaciones)'
          : ' (${filtered.length} operaciones completas)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$msg$suffix')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportCancelRequested = false;
        });
      }
    }
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
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    final branchNames = {
      for (final b in widget.session.branches) b.id: b.name,
    };

    return ListView(
      padding: EdgeInsets.all(isMobile ? 14 : 22),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Historial de ventas',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.session.restaurantName} • ${widget.session.selectedBranchLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.session.permissions.canExportData) ...[
                  OutlinedButton.icon(
                    onPressed: _exporting
                        ? null
                        : () => _exportFullCsv(branchNames),
                    icon: const Icon(Icons.download_rounded, size: 15),
                    label: Text(
                      _exporting
                          ? 'Exportando ($_exportProgressCount)...'
                          : 'Exportar CSV',
                    ),
                  ),
                  if (_exporting) ...[
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: () =>
                          setState(() => _exportCancelRequested = true),
                      child: const Text('Cancelar'),
                    ),
                  ],
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  onPressed: _resetAndLoad,
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: const Text('Actualizar'),
                ),
              ],
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
          searchHint: 'Buscar en todo el periodo (folio, mesa o canal)...',
          onSearchSubmitted: (_) => _resetAndLoad(),
          trailingActions: [
            SizedBox(
              width: 156,
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
        if (_hasSearch)
          FutureBuilder<SalesBoundedBatch>(
            future: _searchFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const TableSkeleton(rows: 8);
              }
              if (snapshot.hasError) {
                return SaasErrorState(
                  title: 'Error al buscar ventas',
                  message:
                      'No se pudieron cargar las operaciones. Intenta de nuevo.',
                  onRetry: _resetAndLoad,
                );
              }
              final batch = snapshot.data;
              final all = batch?.orders ?? const <PosOrder>[];
              final filtered = _filterOrders(all);
              final truncatedNote = batch?.truncated == true
                  ? ' — mostrando las primeras ${all.length} operaciones; existen resultados adicionales no mostrados'
                  : '';
              return _buildOrdersBody(
                context: context,
                tokens: tokens,
                isMobile: isMobile,
                branchNames: branchNames,
                orders: filtered,
                hasPrevious: false,
                hasNext: false,
                lastDocument: null,
                footerSummary:
                    '${filtered.length} coincidencia(s) en el periodo$truncatedNote',
                pageLabel: 'Búsqueda en periodo',
              );
            },
          )
        else
          FutureBuilder<SalesCursorPage>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const TableSkeleton(rows: 8);
              }
              if (snapshot.hasError) {
                return SaasErrorState(
                  title: 'Error al consultar ventas',
                  message:
                      'No se pudieron cargar las operaciones. Intenta de nuevo.',
                  onRetry: _resetAndLoad,
                );
              }
              final page = snapshot.data;
              if (page == null || page.orders.isEmpty) {
                return const SaasEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Sin ventas en este rango',
                  message:
                      'Ajusta las fechas, sucursal o estado para consultar operaciones.',
                );
              }
              return _buildOrdersBody(
                context: context,
                tokens: tokens,
                isMobile: isMobile,
                branchNames: branchNames,
                orders: page.orders,
                hasPrevious: _pageIndex > 0,
                hasNext: page.hasNext,
                lastDocument: page.lastDocument,
                footerSummary:
                    '${page.orders.length} operación(es) en esta página',
                pageLabel: 'Página ${_pageIndex + 1}',
              );
            },
          ),
      ],
    );
  }

  Widget _buildOrdersBody({
    required BuildContext context,
    required BackofficeTokens tokens,
    required bool isMobile,
    required Map<String, String> branchNames,
    required List<PosOrder> orders,
    required bool hasPrevious,
    required bool hasNext,
    required DocumentSnapshot<Map<String, dynamic>>? lastDocument,
    required String footerSummary,
    required String pageLabel,
  }) {
    if (orders.isEmpty) {
      return const SaasEmptyState(
        icon: Icons.search_off_rounded,
        title: 'Sin coincidencias',
        message: 'No hay ventas que coincidan con tu búsqueda en este periodo.',
      );
    }

    final filtered = orders;
    final paidOrders = filtered
        .where((o) => o.status == 'paid')
        .toList(growable: false);
    final totalSold = paidOrders.fold<double>(0, (acc, o) => acc + o.total);
    final avgTicket = paidOrders.isEmpty ? 0.0 : totalSold / paidOrders.length;
    final cancelledCount = filtered.where((o) => o.status == 'cancelled').length;
    final discountSum = filtered.fold<double>(
      0,
      (acc, o) => acc + o.explicitDiscount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 960
                ? 4
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: cols == 1 ? 2.65 : 2.35,
              children: [
                KpiSparkCard(
                  label: _hasSearch ? 'Total coincidente' : 'Total en página',
                  value: BackofficeSalesAdapter.formatMoney(totalSold),
                  subtitle: 'Operaciones pagadas visibles',
                  icon: Icons.payments_outlined,
                  accentColor: tokens.brandAccent,
                ),
                KpiSparkCard(
                  label: 'Operaciones',
                  value: '${filtered.length}',
                  subtitle: '${paidOrders.length} pagadas',
                  icon: Icons.receipt_long_outlined,
                  accentColor: tokens.info,
                ),
                KpiSparkCard(
                  label: 'Ticket promedio',
                  value: BackofficeSalesAdapter.formatMoney(avgTicket),
                  subtitle: 'Promedio por cuenta pagada',
                  icon: Icons.trending_up_rounded,
                  accentColor: tokens.success,
                ),
                KpiSparkCard(
                  label: 'Cancelaciones y desc.',
                  value: BackofficeSalesAdapter.formatMoney(discountSum),
                  subtitle: '$cancelledCount cancelada(s)',
                  icon: Icons.local_offer_outlined,
                  accentColor: tokens.warning,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        if (isMobile) ...[
          ...filtered.map(
            (o) => _MobileSaleCard(
              order: o,
              branchName: branchNames[o.branchId] ?? o.branchId,
              onTap: () => widget.onSelectSale(o.id),
            ),
          ),
          if (hasPrevious || hasNext) ...[
            const SizedBox(height: 8),
            _MobilePaginationBar(
              pageLabel: pageLabel,
              hasPrevious: hasPrevious,
              hasNext: hasNext,
              onPrevious: _goPrevious,
              onNext: () => _goNext(lastDocument),
            ),
          ],
        ] else
          DataTablePro<PosOrder>(
            items: filtered,
            onRowTap: (o) => widget.onSelectSale(o.id),
            hasPrevious: hasPrevious,
            hasNext: hasNext,
            onPrevious: _goPrevious,
            onNext: () => _goNext(lastDocument),
            pageLabel: pageLabel,
            footerSummary: footerSummary,
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
                cellBuilder: (o) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      o.orderType == 'takeout'
                          ? Icons.delivery_dining_outlined
                          : Icons.restaurant_outlined,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        BackofficeSalesAdapter.orderChannelDisplay(o),
                        style: Theme.of(context).textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              SaasColumn(
                label: 'Fecha',
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
          ),
      ],
    );
  }
}

class _MobileSaleCard extends StatelessWidget {
  const _MobileSaleCard({
    required this.order,
    required this.branchName,
    required this.onTap,
  });

  final PosOrder order;
  final String branchName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SaasCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  BackofficeSalesAdapter.resolveFolioLabel(order),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                switch (order.status) {
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
                const Spacer(),
                Text(
                  BackofficeSalesAdapter.formatMoney(order.total),
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$branchName • ${BackofficeSalesAdapter.orderChannelDisplay(order)} • ${BackofficeSalesAdapter.resolveOrderBusinessDate(order)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobilePaginationBar extends StatelessWidget {
  const _MobilePaginationBar({
    required this.pageLabel,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
  });

  final String pageLabel;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(BackofficeSpacing.radiusMd),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          OutlinedButton.icon(
            onPressed: hasPrevious ? onPrevious : null,
            icon: const Icon(Icons.chevron_left_rounded, size: 16),
            label: const Text('Anterior'),
          ),
          Text(
            pageLabel,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: tokens.textSecondary,
            ),
          ),
          OutlinedButton.icon(
            onPressed: hasNext ? onNext : null,
            icon: const Icon(Icons.chevron_right_rounded, size: 16),
            label: const Text('Siguiente'),
          ),
        ],
      ),
    );
  }
}
