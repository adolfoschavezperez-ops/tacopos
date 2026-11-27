import 'package:flutter/material.dart';

import '../../../models/activity_event.dart';
import '../../../utils/csv_exporter.dart';
import '../../auth/backoffice_session.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/filter_bar.dart';
import '../../widgets/saas_card.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/status_pill.dart';
import '../reports/reports_catalog.dart';
import 'audit_repository.dart';

enum _AuditTab {
  log('Bitácora de actividad'),
  alerts('Alertas administrativas');

  const _AuditTab(this.label);
  final String label;
}

class AuditPage extends StatefulWidget {
  const AuditPage({
    super.key,
    required this.session,
    required this.repository,
    required this.onOpenSaleDetail,
  });

  final BackofficeSession session;
  final AuditRepository repository;
  final ValueChanged<String> onOpenSaleDetail;

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  _AuditTab _tab = _AuditTab.log;
  DatePreset _preset = DatePreset.last7Days;
  late DateTime _startDate;
  late DateTime _endDate;
  final TextEditingController _searchCtrl = TextEditingController();
  String _typeFilter = 'all';
  Future<AuditDashboardData>? _future;
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
    _load();
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
      _load();
    }
  }

  void _load() {
    setState(() {
      _future = widget.repository.loadAuditData(
        restaurantId: widget.session.restaurantId,
        startDate: _startDate,
        endDate: _endDate,
        branchId: widget.session.selectedBranchId,
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
    _load();
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
    _load();
  }

  bool _matchesType(ActivityEvent e) {
    final t = e.type.toLowerCase();
    return switch (_typeFilter) {
      'cancellations' => t.contains('cancel'),
      'payments' => t.contains('payment') || t.contains('pago'),
      'cash' => t.contains('cash') || t.contains('withdrawal'),
      'purchases' => t.contains('purchase') || t.contains('supplier'),
      'inventory' => t.contains('kitchen') || t.contains('stock'),
      'partners' => t.contains('partner'),
      _ => true,
    };
  }

  Future<void> _exportCsv(List<ActivityEvent> events) async {
    final token = ExportCancellationToken();
    setState(() {
      _exportToken = token;
      _exportProgress = 0.0;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final csv = await buildChunkedCsv(
        headers: const [
          'Fecha',
          'Operación',
          'Responsable',
          'Origen',
          'Sucursal',
          'Orden / Doc',
          'Motivo / Nota',
        ],
        rows: events
            .map(
              (e) => [
                BackofficeSalesAdapter.formatDateTime(e.createdAt),
                e.type,
                e.employeeName,
                e.actionSource,
                e.branchName,
                e.orderId ?? e.targetId ?? '—',
                e.reason ?? e.note ?? '—',
              ],
            )
            .toList(growable: false),
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
            'auditoria_${BackofficeSalesAdapter.formatBusinessDate(_startDate)}.csv',
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

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Auditoría y Alertas Administrativas',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Bitácora verificable de eventos y centro de hallazgos de solo lectura.',
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
                searchController: _searchCtrl,
                searchHint: 'Buscar por empleado, operación, motivo o documento...',
                onSearchSubmitted: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _AuditTab.values
                    .map(
                      (t) => ChoiceChip(
                        label: Text(t.label),
                        selected: _tab == t,
                        onSelected: (_) => setState(() => _tab = t),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),
              FutureBuilder<AuditDashboardData>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const TableSkeleton(rows: 6);
                  }
                  if (snap.hasError) {
                    return SaasErrorState(
                      title: 'No pudimos cargar la auditoría',
                      message:
                          'Verifica tu conexión o permisos e intenta nuevamente.',
                      onRetry: _load,
                    );
                  }
                  final data = snap.data;
                  if (data == null) return const SizedBox.shrink();

                  if (_tab == _AuditTab.alerts) {
                    return _buildAlertsView(data.alerts, tokens);
                  }
                  return _buildLogView(data.events, tokens);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogView(List<ActivityEvent> rawEvents, BackofficeTokens tokens) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final events = rawEvents
        .where((e) {
          if (!_matchesType(e)) return false;
          if (q.isNotEmpty) {
            final text =
                '${e.type} ${e.employeeName} ${e.actionSource} ${e.reason ?? ''} ${e.note ?? ''} ${e.orderId ?? ''} ${e.targetId ?? ''}'
                    .toLowerCase();
            if (!text.contains(q)) return false;
          }
          return true;
        })
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Wrap(
            spacing: 8,
            children: [
              for (final entry in const [
                ('all', 'Todos'),
                ('cancellations', 'Cancelaciones'),
                ('payments', 'Pagos'),
                ('cash', 'Caja y retiros'),
                ('purchases', 'Compras / Prov.'),
                ('inventory', 'Inventarios'),
                ('partners', 'Socios'),
              ])
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: _typeFilter == entry.$1,
                  onSelected: (_) => setState(() => _typeFilter = entry.$1),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_exportProgress != null) ...[
          LinearProgressIndicator(value: _exportProgress),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Exportando ${(_exportProgress! * 100).toStringAsFixed(0)}%...'),
              TextButton(
                onPressed: () => _exportToken?.cancel(),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ],
        SaasCard(
          title: 'Bitácora de actividad (${events.length})',
          subtitle: 'Eventos registrados en activityLog (solo lectura).',
          trailing: OutlinedButton.icon(
            onPressed: _exportProgress == null ? () => _exportCsv(events) : null,
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('CSV'),
          ),
          padding: EdgeInsets.zero,
          child: events.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No hay eventos de auditoría con los filtros actuales.'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: events.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: tokens.border),
                  itemBuilder: (context, i) {
                    final e = events[i];
                    final detail = [
                      BackofficeSalesAdapter.formatDateTime(e.createdAt),
                      if (e.branchName.isNotEmpty) e.branchName,
                      'Resp: ${e.employeeName}',
                      'Origen: ${e.actionSource}',
                    ].join(' · ');
                    final reasonText = e.reason ?? e.note ?? '';
                    return ListTile(
                      title: Text(
                        e.type,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail,
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.textSecondary,
                            ),
                          ),
                          if (reasonText.isNotEmpty)
                            Text(
                              reasonText,
                              style: TextStyle(
                                fontSize: 12,
                                color: tokens.textMuted,
                              ),
                            ),
                        ],
                      ),
                      trailing: (e.orderId != null && e.orderId!.isNotEmpty)
                          ? OutlinedButton(
                              onPressed: () =>
                                  widget.onOpenSaleDetail(e.orderId!),
                              child: const Text('Ver orden'),
                            )
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAlertsView(
    List<AdminAlertFinding> alerts,
    BackofficeTokens tokens,
  ) {
    if (alerts.isEmpty) {
      return const SaasEmptyState(
        icon: Icons.verified_user_outlined,
        title: 'Sin hallazgos relevantes en el periodo',
        message: 'No se detectaron diferencias ni pendientes administrativos.',
      );
    }
    return SaasCard(
      title: 'Centro de alertas administrativas (${alerts.length})',
      subtitle:
          'Hallazgos informativos basados en datos verificables (sin acciones automáticas).',
      padding: EdgeInsets.zero,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: alerts.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
        itemBuilder: (context, i) {
          final a = alerts[i];
          final tone = switch (a.severity) {
            AuditAlertSeverity.high => StatusTone.danger,
            AuditAlertSeverity.warning => StatusTone.warning,
            AuditAlertSeverity.info => StatusTone.info,
          };
          return ListTile(
            title: Row(
              children: [
                StatusPill(label: a.category, tone: tone),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    a.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                a.detail,
                style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
              ),
            ),
            trailing: (a.orderId != null && a.orderId!.isNotEmpty)
                ? OutlinedButton(
                    onPressed: () => widget.onOpenSaleDetail(a.orderId!),
                    child: const Text('Ver orden'),
                  )
                : null,
          );
        },
      ),
    );
  }
}
