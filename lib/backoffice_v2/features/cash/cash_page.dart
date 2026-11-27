import 'package:flutter/material.dart';

import '../../../models/cash_session.dart';
import '../../../models/cash_withdrawal_request.dart';
import '../../../utils/csv_exporter.dart';
import '../../auth/backoffice_session.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/filter_bar.dart';
import '../../widgets/saas_card.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/status_pill.dart';
import 'cash_repository.dart';

class CashPage extends StatefulWidget {
  const CashPage({
    super.key,
    required this.session,
    required this.repository,
  });

  final BackofficeSession session;
  final CashRepository repository;

  @override
  State<CashPage> createState() => _CashPageState();
}

class _CashPageState extends State<CashPage> {
  DatePreset _preset = DatePreset.last7Days;
  late DateTime _startDate;
  late DateTime _endDate;
  final TextEditingController _employeeController = TextEditingController();
  Future<CashDashboardData>? _future;
  String? _lastBranchId;
  String? _selectedSessionId;
  bool _exporting = false;

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
    _employeeController.dispose();
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
      _future = widget.repository.loadCashDashboard(
        restaurantId: widget.session.restaurantId,
        startBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_startDate),
        endBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_endDate),
        branchId: widget.session.selectedBranchId,
        employeeQuery: _employeeController.text,
        selectedSessionId: _selectedSessionId,
      );
    });
  }

  Future<void> _exportCsv(
    List<CashSession> sessions,
    Map<String, String> branchNames,
  ) async {
    if (_exporting || sessions.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final buf = StringBuffer()
        ..writeln(
          'FechaOperativa,Sucursal,Estado,AbiertaPor,CerradaPor,FondoInicial,EfectivoEsperado,EfectivoContado,TarjetaEsperada,TerminalReportada,Plataformas,RetirosAprobados,Faltante,Sobrante,DiferenciaNeta',
        );
      for (final s in sessions) {
        final branch = (branchNames[s.branchId] ?? s.branchName)
            .replaceAll('"', '""');
        final openedBy = s.openedByEmployeeName.replaceAll('"', '""');
        final closedBy = (s.closedByEmployeeName ?? '').replaceAll('"', '""');
        buf.writeln(
          '${s.businessDate},"$branch",${_statusLabel(s)},"$openedBy","$closedBy",'
          '${s.openingCashAmount.toStringAsFixed(2)},'
          '${s.expectedCashAmount.toStringAsFixed(2)},'
          '${s.countedCashAmount.toStringAsFixed(2)},'
          '${s.expectedCardChargedAmount.toStringAsFixed(2)},'
          '${s.terminalReportedAmount.toStringAsFixed(2)},'
          '${s.expectedPlatformAmount.toStringAsFixed(2)},'
          '${s.approvedWithdrawalsTotal.toStringAsFixed(2)},'
          '${s.shortageAmount.toStringAsFixed(2)},'
          '${s.overAmount.toStringAsFixed(2)},'
          '${s.netDifference.toStringAsFixed(2)}',
        );
      }
      final msg = await exportCsvFile(
        fileName:
            'caja_${BackofficeSalesAdapter.formatBusinessDate(_startDate)}_${BackofficeSalesAdapter.formatBusinessDate(_endDate)}.csv',
        content: buf.toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$msg (${sessions.length} cortes)')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
              _buildHeader(context, tokens),
              const SizedBox(height: 16),
              SaasFilterBar(
                activePreset: _preset,
                startDateLabel: BackofficeSalesAdapter.formatBusinessDate(
                  _startDate,
                ),
                endDateLabel: BackofficeSalesAdapter.formatBusinessDate(_endDate),
                onPresetSelected: _applyPreset,
                onPickCustomRange: _pickCustomRange,
                searchController: _employeeController,
                searchHint: 'Filtrar por cajero o responsable...',
                onSearchSubmitted: (_) => _load(),
                trailingActions: [
                  if (_employeeController.text.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        _employeeController.clear();
                        _load();
                      },
                      child: const Text('Limpiar'),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              FutureBuilder<CashDashboardData>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Column(
                      children: [
                        TableSkeleton(rows: 4),
                        SizedBox(height: 16),
                        TableSkeleton(rows: 6),
                      ],
                    );
                  }
                  if (snapshot.hasError) {
                    return SaasErrorState(
                      title: 'No pudimos cargar los cortes de caja',
                      message:
                          'Verifica tu conexión o permisos de sucursal e intenta nuevamente.',
                      onRetry: _load,
                    );
                  }
                  final data = snapshot.data;
                  if (data == null || data.sessions.isEmpty) {
                    return const SaasEmptyState(
                      icon: Icons.point_of_sale_outlined,
                      title: 'Sin cortes de caja en el periodo',
                      message:
                          'Prueba ampliando el rango de fechas o cambiando la sucursal seleccionada.',
                    );
                  }

                  final detail = data.selectedDetail;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (detail != null) ...[
                        _CashHeroBanner(
                          session: detail.session,
                          summary: detail.summary,
                          branchName:
                              branchNames[detail.session.branchId] ??
                              detail.session.branchName,
                          isOpenHighlight:
                              data.openSession?.id == detail.session.id,
                        ),
                        const SizedBox(height: 16),
                        _CashKpiGrid(
                          summary: detail.summary,
                          isMobile: isMobile,
                        ),
                        const SizedBox(height: 16),
                        _NonMonetaryCard(summary: detail.summary),
                        const SizedBox(height: 16),
                      ],
                      _CashSessionsSection(
                        sessions: data.sessions,
                        selectedId: detail?.session.id,
                        branchNames: branchNames,
                        isMobile: isMobile,
                        canExport: widget.session.permissions.canExportData,
                        exporting: _exporting,
                        onExport: () => _exportCsv(data.sessions, branchNames),
                        onSelect: (session) {
                          setState(() {
                            _selectedSessionId = session.id;
                            _load();
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      _WithdrawalsSection(
                        withdrawals: detail?.withdrawals ?? data.withdrawals,
                        branchNames: branchNames,
                        isMobile: isMobile,
                      ),
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

  Widget _buildHeader(BuildContext context, BackofficeTokens tokens) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Caja y Cortes',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Control de turnos, arqueo de efectivo, terminal bancaria, retiros y diferencias por sucursal.',
                style: TextStyle(fontSize: 13, color: tokens.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _statusLabel(CashSession session) {
  if (session.isOpen) return 'Abierta';
  if (session.isClosing) return 'En cierre';
  return 'Cerrada';
}

StatusTone _statusTone(CashSession session) {
  if (session.isOpen) return StatusTone.success;
  if (session.isClosing) return StatusTone.warning;
  return StatusTone.neutral;
}

class _CashHeroBanner extends StatelessWidget {
  const _CashHeroBanner({
    required this.session,
    required this.summary,
    required this.branchName,
    required this.isOpenHighlight,
  });

  final CashSession session;
  final CashReconciliationSummary summary;
  final String branchName;
  final bool isOpenHighlight;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final hasShortage = summary.shortageAmount > 0.009;
    final hasOver = summary.overAmount > 0.009;
    final diffLabel = hasShortage
        ? 'Faltante ${BackofficeSalesAdapter.formatMoney(summary.shortageAmount)}'
        : hasOver
        ? 'Sobrante ${BackofficeSalesAdapter.formatMoney(summary.overAmount)}'
        : 'Cuadre exacto';
    final diffTone = hasShortage
        ? StatusTone.danger
        : hasOver
        ? StatusTone.warning
        : StatusTone.success;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.surface,
            tokens.brandAccentSoft.withValues(alpha: 0.45),
          ],
        ),
        borderRadius: BorderRadius.circular(BackofficeSpacing.radiusLg),
        border: Border.all(
          color: isOpenHighlight
              ? tokens.brandAccent.withValues(alpha: 0.45)
              : tokens.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(
                label: isOpenHighlight
                    ? 'Caja actualmente abierta'
                    : _statusLabel(session),
                tone: _statusTone(session),
                icon: session.isOpen
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
              ),
              StatusPill(
                label: diffLabel,
                tone: diffTone,
                icon: hasShortage
                    ? Icons.warning_amber_rounded
                    : Icons.verified_outlined,
              ),
              Text(
                '$branchName · ${session.businessDate}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 28,
            runSpacing: 14,
            children: [
              _HeroMetric(
                label: 'Efectivo esperado en caja',
                value: BackofficeSalesAdapter.formatMoney(
                  summary.expectedCashInDrawer,
                ),
                tokens: tokens,
                emphasized: true,
              ),
              _HeroMetric(
                label: 'Efectivo contado',
                value: session.isClosed || summary.countedCashAmount > 0
                    ? BackofficeSalesAdapter.formatMoney(
                        summary.countedCashAmount,
                      )
                    : 'Pendiente de cierre',
                tokens: tokens,
              ),
              _HeroMetric(
                label: 'Dinero real esperado',
                value: BackofficeSalesAdapter.formatMoney(
                  summary.totalExpectedRealMoney,
                ),
                tokens: tokens,
              ),
              _HeroMetric(
                label: 'Responsable apertura',
                value: session.openedByEmployeeName.isEmpty
                    ? 'Sin registro'
                    : session.openedByEmployeeName,
                tokens: tokens,
              ),
              if (session.closedByEmployeeName != null &&
                  session.closedByEmployeeName!.isNotEmpty)
                _HeroMetric(
                  label: 'Responsable cierre',
                  value: session.closedByEmployeeName!,
                  tokens: tokens,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
    required this.tokens,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final BackofficeTokens tokens;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: tokens.textSecondary),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasized ? 22 : 16,
            fontWeight: FontWeight.w700,
            color: emphasized ? tokens.brandAccent : tokens.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _CashKpiGrid extends StatelessWidget {
  const _CashKpiGrid({required this.summary, required this.isMobile});

  final CashReconciliationSummary summary;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final items = [
      _CashMetricItem(
        title: 'Fondo inicial',
        value: BackofficeSalesAdapter.formatMoney(summary.openingCashAmount),
        subtitle:
            'Efectivo cobrado: ${BackofficeSalesAdapter.formatMoney(summary.cashCollected)}',
        icon: Icons.payments_outlined,
        color: tokens.brandAccent,
      ),
      _CashMetricItem(
        title: 'Tarjeta y plataformas',
        value: BackofficeSalesAdapter.formatMoney(
          summary.cardCollected + summary.platformCollected,
        ),
        subtitle:
            'Tarjeta ${BackofficeSalesAdapter.formatMoney(summary.cardCollected)} · Plat. ${BackofficeSalesAdapter.formatMoney(summary.platformCollected)}',
        icon: Icons.credit_card_outlined,
        color: tokens.info,
      ),
      _CashMetricItem(
        title: 'Retiros y gastos',
        value: BackofficeSalesAdapter.formatMoney(
          summary.approvedWithdrawalsTotal,
        ),
        subtitle:
            'Pendientes: ${BackofficeSalesAdapter.formatMoney(summary.pendingWithdrawalsTotal)}',
        icon: Icons.outbox_outlined,
        color: tokens.warning,
      ),
      _CashMetricItem(
        title: 'Propinas registradas',
        value: BackofficeSalesAdapter.formatMoney(summary.tipsTotal),
        subtitle:
            'Dif. neta: ${BackofficeSalesAdapter.formatMoney(summary.netDifference)}',
        icon: Icons.volunteer_activism_outlined,
        color: tokens.success,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 980
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width = (constraints.maxWidth - (12 * (cols - 1))) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: SaasCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(item.icon, size: 17, color: item.color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.title,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          item.value,
                          style: TextStyle(
                            fontSize: isMobile ? 19 : 21,
                            fontWeight: FontWeight.w700,
                            color: tokens.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.subtitle,
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

class _CashMetricItem {
  const _CashMetricItem({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _NonMonetaryCard extends StatelessWidget {
  const _NonMonetaryCard({required this.summary});

  final CashReconciliationSummary summary;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return SaasCard(
      title: 'Consumos internos, descuentos y cancelaciones',
      subtitle:
          'Conceptos operativos separados del flujo monetario de caja para preservar exactitud financiera.',
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          _InfoPair(
            label: 'Comida de empleados',
            value: BackofficeSalesAdapter.formatMoney(
              summary.employeeFreeMealTotal,
            ),
            tokens: tokens,
          ),
          _InfoPair(
            label: 'Consumo independiente de empleados',
            value: BackofficeSalesAdapter.formatMoney(
              summary.employeeConsumptionTotal,
            ),
            tokens: tokens,
          ),
          _InfoPair(
            label: 'Descuentos aplicados',
            value: BackofficeSalesAdapter.formatMoney(
              summary.explicitDiscountsTotal,
            ),
            tokens: tokens,
          ),
          _InfoPair(
            label: 'Órdenes canceladas',
            value:
                '${summary.cancelledOrdersCount} (${BackofficeSalesAdapter.formatMoney(summary.cancelledAmount)})',
            tokens: tokens,
          ),
        ],
      ),
    );
  }
}

class _InfoPair extends StatelessWidget {
  const _InfoPair({
    required this.label,
    required this.value,
    required this.tokens,
  });

  final String label;
  final String value;
  final BackofficeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: tokens.textSecondary),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _CashSessionsSection extends StatelessWidget {
  const _CashSessionsSection({
    required this.sessions,
    required this.selectedId,
    required this.branchNames,
    required this.isMobile,
    required this.canExport,
    required this.exporting,
    required this.onExport,
    required this.onSelect,
  });

  final List<CashSession> sessions;
  final String? selectedId;
  final Map<String, String> branchNames;
  final bool isMobile;
  final bool canExport;
  final bool exporting;
  final VoidCallback onExport;
  final ValueChanged<CashSession> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return SaasCard(
      title: 'Historial de cortes de caja',
      subtitle: 'Selecciona un turno para inspeccionar su arqueo completo.',
      padding: EdgeInsets.zero,
      trailing: canExport
          ? OutlinedButton.icon(
              onPressed: exporting ? null : onExport,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: Text(exporting ? 'Exportando...' : 'Exportar CSV'),
            )
          : null,
      child: isMobile
          ? ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sessions.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
              itemBuilder: (context, index) {
                final s = sessions[index];
                final isSelected = s.id == selectedId;
                return InkWell(
                  onTap: () => onSelect(s),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    color: isSelected
                        ? tokens.brandAccentSoft.withValues(alpha: 0.35)
                        : Colors.transparent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${s.businessDate} · ${branchNames[s.branchId] ?? s.branchName}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            StatusPill(
                              label: _statusLabel(s),
                              tone: _statusTone(s),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Abrió: ${s.openedByEmployeeName}',
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Esperado: ${BackofficeSalesAdapter.formatMoney(s.expectedCashAmount)}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            Text(
                              'Dif: ${BackofficeSalesAdapter.formatMoney(s.netDifference)}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: s.shortageAmount > 0
                                    ? tokens.danger
                                    : s.overAmount > 0
                                    ? tokens.warning
                                    : tokens.success,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Fecha')),
                  DataColumn(label: Text('Sucursal')),
                  DataColumn(label: Text('Estado')),
                  DataColumn(label: Text('Cajero')),
                  DataColumn(label: Text('Fondo'), numeric: true),
                  DataColumn(label: Text('Efec. esperado'), numeric: true),
                  DataColumn(label: Text('Efec. contado'), numeric: true),
                  DataColumn(label: Text('Retiros'), numeric: true),
                  DataColumn(label: Text('Diferencia'), numeric: true),
                ],
                rows: sessions.map((s) {
                  final isSelected = s.id == selectedId;
                  return DataRow(
                    selected: isSelected,
                    onSelectChanged: (_) => onSelect(s),
                    cells: [
                      DataCell(Text(s.businessDate)),
                      DataCell(Text(branchNames[s.branchId] ?? s.branchName)),
                      DataCell(
                        StatusPill(
                          label: _statusLabel(s),
                          tone: _statusTone(s),
                        ),
                      ),
                      DataCell(Text(s.openedByEmployeeName)),
                      DataCell(
                        Text(
                          BackofficeSalesAdapter.formatMoney(
                            s.openingCashAmount,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          BackofficeSalesAdapter.formatMoney(
                            s.expectedCashAmount,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          BackofficeSalesAdapter.formatMoney(
                            s.countedCashAmount,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          BackofficeSalesAdapter.formatMoney(
                            s.approvedWithdrawalsTotal,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          BackofficeSalesAdapter.formatMoney(s.netDifference),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: s.shortageAmount > 0
                                ? tokens.danger
                                : s.overAmount > 0
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
    );
  }
}

class _WithdrawalsSection extends StatelessWidget {
  const _WithdrawalsSection({
    required this.withdrawals,
    required this.branchNames,
    required this.isMobile,
  });

  final List<CashWithdrawalRequest> withdrawals;
  final Map<String, String> branchNames;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return SaasCard(
      title: 'Retiros y gastos de caja',
      subtitle: 'Movimientos asociados al corte o rango seleccionado.',
      padding: withdrawals.isEmpty
          ? const EdgeInsets.all(20)
          : EdgeInsets.zero,
      child: withdrawals.isEmpty
          ? Text(
              'No se registraron retiros de caja en este corte.',
              style: TextStyle(fontSize: 13, color: tokens.textSecondary),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: withdrawals.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
              itemBuilder: (context, index) {
                final w = withdrawals[index];
                final tone = w.isApproved
                    ? StatusTone.success
                    : w.isRejected
                    ? StatusTone.danger
                    : StatusTone.warning;
                final statusText = w.isApproved
                    ? 'Aprobado'
                    : w.isRejected
                    ? 'Rechazado'
                    : 'Pendiente';
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
                              w.reason.isEmpty ? 'Retiro de efectivo' : w.reason,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${branchNames[w.branchId] ?? w.branchName} · Solicita: ${w.requestedByEmployeeName} · ${w.businessDate}',
                              style: TextStyle(
                                fontSize: 12,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            BackofficeSalesAdapter.formatMoney(w.amount),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 4),
                          StatusPill(label: statusText, tone: tone),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
