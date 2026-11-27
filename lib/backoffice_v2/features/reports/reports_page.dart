import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';

import '../../../utils/binary_exporter.dart';
import '../../../utils/csv_exporter.dart';
import '../../auth/backoffice_session.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/filter_bar.dart';
import '../../widgets/kpi_tile.dart';
import '../../widgets/saas_card.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/status_pill.dart';
import 'reports_catalog.dart';
import 'reports_repository.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({
    super.key,
    required this.session,
    required this.repository,
    required this.onOpenSaleDetail,
  });

  final BackofficeSession session;
  final ReportsRepository repository;
  final ValueChanged<String> onOpenSaleDetail;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<BackofficeReportKind> _favorites = {
    BackofficeReportKind.products,
    BackofficeReportKind.dates,
    BackofficeReportKind.cashHistory,
    BackofficeReportKind.yieldProfit,
  };
  ReportCategory _selectedCategory = ReportCategory.all;
  bool _onlyFavorites = false;
  ReportDescriptor? _activeReport;

  DatePreset _preset = DatePreset.last7Days;
  late DateTime _startDate;
  late DateTime _endDate;
  Future<ReportTableResult>? _reportFuture;
  String? _lastBranchId;
  String _lastRestaurantId = '';

  double? _exportProgress;
  ExportCancellationToken? _exportToken;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _endDate = today;
    _startDate = today.subtract(const Duration(days: 6));
    _lastBranchId = widget.session.selectedBranchId;
    _lastRestaurantId = widget.session.restaurantId;
    widget.session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (_lastBranchId != widget.session.selectedBranchId ||
        _lastRestaurantId != widget.session.restaurantId) {
      _lastBranchId = widget.session.selectedBranchId;
      _lastRestaurantId = widget.session.restaurantId;
      if (_activeReport != null) _loadReport(_activeReport!);
    }
  }

  void _loadReport(ReportDescriptor descriptor, {bool forceRefresh = false}) {
    setState(() {
      _activeReport = descriptor;
      _reportFuture = widget.repository.runReport(
        kind: descriptor.kind,
        restaurantId: widget.session.restaurantId,
        startDate: _startDate,
        endDate: _endDate,
        branchId: widget.session.selectedBranchId,
        forceRefresh: forceRefresh,
      );
    });
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
    });
    if (_activeReport != null) _loadReport(_activeReport!);
  }

  Future<void> _pickCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (range == null) return;
    setState(() {
      _preset = DatePreset.custom;
      _startDate = range.start;
      _endDate = range.end;
    });
    if (_activeReport != null) _loadReport(_activeReport!);
  }

  Future<void> _exportCsv(ReportTableResult data) async {
    final token = ExportCancellationToken();
    setState(() {
      _exportToken = token;
      _exportProgress = 0.0;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final csv = await buildChunkedCsv(
        headers: data.headers,
        rows: data.rows,
        totalsRow: data.totalsRow,
        cancellationToken: token,
        onProgress: (p) {
          if (mounted) setState(() => _exportProgress = p);
        },
      );
      if (csv == null) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Exportación cancelada.')),
          );
        }
        return;
      }
      final msg = await exportCsvFile(
        fileName:
            '${data.kind.name}_${BackofficeSalesAdapter.formatBusinessDate(_startDate)}.csv',
        content: csv,
      );
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) {
        setState(() {
          _exportProgress = null;
          _exportToken = null;
        });
      }
    }
  }

  Future<void> _exportExcel(ReportTableResult data) async {
    final messenger = ScaffoldMessenger.of(context);
    final workbook = xls.Excel.createExcel();
    final sheetName = workbook.getDefaultSheet() ?? 'Reporte';
    final sheet = workbook[sheetName];
    sheet.appendRow(data.headers.map((h) => xls.TextCellValue(h)).toList());
    for (final row in data.rows) {
      sheet.appendRow(row.map((c) => xls.TextCellValue(c)).toList());
    }
    if (data.totalsRow != null) {
      sheet.appendRow(
        data.totalsRow!.map((c) => xls.TextCellValue(c)).toList(),
      );
    }
    final bytes = workbook.encode();
    if (bytes == null) return;
    final msg = await exportBinaryFile(
      fileName:
          '${data.kind.name}_${BackofficeSalesAdapter.formatBusinessDate(_startDate)}.xlsx',
      bytes: Uint8List.fromList(bytes),
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    if (mounted) messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: _activeReport == null
              ? _buildCatalog(context, tokens, isMobile)
              : _buildReportViewer(context, tokens, isMobile),
        ),
      ),
    );
  }

  Widget _buildCatalog(
    BuildContext context,
    BackofficeTokens tokens,
    bool isMobile,
  ) {
    final perms = widget.session.permissions;
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = backoffice25ReportsCatalog.where((r) {
      if (!r.isAllowed(perms)) return false;
      if (_onlyFavorites && !_favorites.contains(r.kind)) return false;
      if (_selectedCategory != ReportCategory.all &&
          r.category != _selectedCategory) {
        return false;
      }
      if (query.isNotEmpty) {
        final haystack =
            '${r.title} ${r.description} ${r.category.label}'.toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList(growable: false);

    final cols = isMobile ? 1 : (MediaQuery.sizeOf(context).width < 1100 ? 2 : 3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Centro de Reportes',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '25 reportes operativos, financieros y de auditoría compatibles con Backoffice 1.0.',
          style: TextStyle(fontSize: 13, color: tokens.textSecondary),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Buscar reporte por nombre, categoría o descripción...',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            FilterChip(
              avatar: Icon(
                _onlyFavorites ? Icons.star_rounded : Icons.star_border_rounded,
                size: 16,
              ),
              label: const Text('Favoritos'),
              selected: _onlyFavorites,
              onSelected: (v) => setState(() => _onlyFavorites = v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Wrap(
            spacing: 8,
            children: ReportCategory.values
                .map(
                  (c) => ChoiceChip(
                    label: Text(c.label),
                    selected: _selectedCategory == c,
                    onSelected: (_) => setState(() => _selectedCategory = c),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: 18),
        if (filtered.isEmpty)
          const SaasEmptyState(
            icon: Icons.analytics_outlined,
            title: 'Sin reportes coincidentes',
            message: 'Prueba limpiando la búsqueda o cambiando de categoría.',
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: isMobile ? 2.1 : 1.75,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              final r = filtered[i];
              final isFav = _favorites.contains(r.kind);
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _loadReport(r),
                child: SaasCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          StatusPill(
                            label: r.category.label,
                            tone: StatusTone.info,
                          ),
                          const Spacer(),
                          if (r.supportsExcel)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: StatusPill(
                                label: 'XLSX',
                                tone: StatusTone.success,
                              ),
                            ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              isFav
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              size: 18,
                              color: isFav ? tokens.brandAmber : tokens.textMuted,
                            ),
                            onPressed: () {
                              setState(() {
                                if (isFav) {
                                  _favorites.remove(r.kind);
                                } else {
                                  _favorites.add(r.kind);
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        r.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          r.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildReportViewer(
    BuildContext context,
    BackofficeTokens tokens,
    bool isMobile,
  ) {
    final descriptor = _activeReport!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() => _activeReport = null),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Catálogo'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                descriptor.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          descriptor.description,
          style: TextStyle(fontSize: 13, color: tokens.textSecondary),
        ),
        const SizedBox(height: 14),
        SaasFilterBar(
          activePreset: _preset,
          startDateLabel: BackofficeSalesAdapter.formatBusinessDate(_startDate),
          endDateLabel: BackofficeSalesAdapter.formatBusinessDate(_endDate),
          onPresetSelected: _applyPreset,
          onPickCustomRange: _pickCustomRange,
          trailingActions: [
            IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _loadReport(descriptor, forceRefresh: true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<ReportTableResult>(
          future: _reportFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const TableSkeleton(rows: 6);
            }
            if (snap.hasError) {
              return SaasErrorState(
                title: 'No pudimos generar el reporte',
                message: 'Verifica tu conexión o permisos e intenta nuevamente.',
                onRetry: () => _loadReport(descriptor, forceRefresh: true),
              );
            }
            final data = snap.data;
            if (data == null) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data.partialWarning != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.warningSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: tokens.warning),
                    ),
                    child: Text(
                      data.partialWarning!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (data.kpis.isNotEmpty) ...[
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: data.kpis
                        .map(
                          (k) => SizedBox(
                            width: isMobile ? 160 : 220,
                            child: KpiTile(label: k.label, value: k.value),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_exportProgress != null) ...[
                  LinearProgressIndicator(value: _exportProgress),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Exportando ${(_exportProgress! * 100).toStringAsFixed(0)}%...',
                        style: const TextStyle(fontSize: 12),
                      ),
                      TextButton(
                        onPressed: () => _exportToken?.cancel(),
                        child: const Text('Cancelar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                SaasCard(
                  title: data.title,
                  subtitle: data.subtitle,
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            _exportProgress == null ? () => _exportCsv(data) : null,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('CSV'),
                      ),
                      if (descriptor.supportsExcel)
                        FilledButton.icon(
                          onPressed: () => _exportExcel(data),
                          icon: const Icon(Icons.table_view_rounded, size: 16),
                          label: const Text('Excel'),
                        ),
                    ],
                  ),
                  padding: EdgeInsets.zero,
                  child: data.rows.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Sin registros en el periodo seleccionado.'),
                        )
                      : isMobile
                      ? _buildMobileCards(data, tokens)
                      : _buildDesktopTable(data, tokens),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildDesktopTable(ReportTableResult data, BackofficeTokens tokens) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(tokens.surfaceSubtle),
        columns: [
          for (final h in data.headers) DataColumn(label: Text(h)),
          if (data.rowOrderIds.isNotEmpty)
            const DataColumn(label: Text('Detalle')),
        ],
        rows: [
          for (var i = 0; i < data.rows.length; i++)
            DataRow(
              cells: [
                for (final cell in data.rows[i]) DataCell(Text(cell)),
                if (data.rowOrderIds.isNotEmpty)
                  DataCell(
                    (i < data.rowOrderIds.length && data.rowOrderIds[i] != null)
                        ? IconButton(
                            icon: const Icon(Icons.open_in_new_rounded, size: 16),
                            onPressed: () =>
                                widget.onOpenSaleDetail(data.rowOrderIds[i]!),
                          )
                        : const Text('—'),
                  ),
              ],
            ),
          if (data.totalsRow != null)
            DataRow(
              color: WidgetStatePropertyAll(tokens.surfaceElevated),
              cells: [
                for (final cell in data.totalsRow!)
                  DataCell(
                    Text(
                      cell,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                if (data.rowOrderIds.isNotEmpty) const DataCell(Text('')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMobileCards(ReportTableResult data, BackofficeTokens tokens) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: data.rows.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
      itemBuilder: (context, i) {
        final row = data.rows[i];
        final orderId = i < data.rowOrderIds.length ? data.rowOrderIds[i] : null;
        return Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.isNotEmpty ? row.first : '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (orderId != null)
                    TextButton(
                      onPressed: () => widget.onOpenSaleDetail(orderId),
                      child: const Text('Ver orden'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              for (var c = 1; c < row.length && c < data.headers.length; c++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          data.headers[c],
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        row[c],
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
