import 'package:flutter/material.dart';

import '../../../models/cash_withdrawal_request.dart';
import '../../../models/discount_authorization_request.dart';
import '../../auth/backoffice_session.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/filter_bar.dart';
import '../../widgets/saas_card.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/status_pill.dart';
import 'authorizations_repository.dart';

enum _AuthTab { all, withdrawals, discounts }

class AuthorizationsPage extends StatefulWidget {
  const AuthorizationsPage({
    super.key,
    required this.session,
    required this.repository,
  });

  final BackofficeSession session;
  final AuthorizationsRepository repository;

  @override
  State<AuthorizationsPage> createState() => _AuthorizationsPageState();
}

class _AuthorizationsPageState extends State<AuthorizationsPage> {
  DatePreset _preset = DatePreset.last7Days;
  late DateTime _startDate;
  late DateTime _endDate;
  String? _statusFilter;
  _AuthTab _tab = _AuthTab.all;
  Future<AuthorizationsData>? _future;
  String? _lastBranchId;

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
      _load();
    });
  }

  void _load() {
    setState(() {
      _future = widget.repository.loadAuthorizations(
        restaurantId: widget.session.restaurantId,
        startBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_startDate),
        endBusinessDate: BackofficeSalesAdapter.formatBusinessDate(_endDate),
        branchId: widget.session.selectedBranchId,
        statusFilter: _statusFilter,
      );
    });
  }

  Future<String?> _promptNotes({
    required String title,
    required bool requiredReason,
  }) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 380,
            child: TextField(
              controller: ctrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: requiredReason
                    ? 'Motivo del rechazo (obligatorio)'
                    : 'Notas de autorización (opcional)',
              ),
              onChanged: (_) => setDialogState(() {}),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: (!requiredReason || ctrl.text.trim().isNotEmpty)
                  ? () => Navigator.of(ctx).pop(ctrl.text.trim())
                  : null,
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resolveWithdrawal(
    CashWithdrawalRequest w, {
    required bool approved,
  }) async {
    final notes = await _promptNotes(
      title: approved ? 'Autorizar retiro' : 'Rechazar retiro',
      requiredReason: !approved,
    );
    if (notes == null) return;
    try {
      await widget.repository.resolveCashWithdrawal(
        restaurantId: widget.session.restaurantId,
        requestId: w.id,
        approved: approved,
        notesOrReason: notes,
        employeeId: widget.session.employee?.id ?? '',
        employeeName: widget.session.employee?.name ?? '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved ? 'Retiro autorizado.' : 'Retiro rechazado.',
          ),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  Future<void> _resolveDiscount(
    DiscountAuthorizationRequest d, {
    required bool approved,
  }) async {
    final notes = await _promptNotes(
      title: approved ? 'Autorizar descuento' : 'Rechazar descuento',
      requiredReason: !approved,
    );
    if (notes == null) return;
    try {
      await widget.repository.resolveDiscountAuthorization(
        restaurantId: widget.session.restaurantId,
        requestId: d.id,
        approved: approved,
        rejectReason: notes,
        employeeId: widget.session.employee?.id ?? '',
        employeeName: widget.session.employee?.name ?? '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved ? 'Descuento autorizado.' : 'Descuento rechazado.',
          ),
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
      );
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
              Text(
                'Autorizaciones',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Seguimiento de solicitudes de retiros de efectivo y descuentos especiales por sucursal.',
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
                trailingActions: [
                  SegmentedButton<_AuthTab>(
                    segments: const [
                      ButtonSegment(value: _AuthTab.all, label: Text('Todas')),
                      ButtonSegment(
                        value: _AuthTab.withdrawals,
                        label: Text('Retiros'),
                      ),
                      ButtonSegment(
                        value: _AuthTab.discounts,
                        label: Text('Descuentos'),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (v) => setState(() => _tab = v.first),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusChip(
                    label: 'Todos',
                    selected: _statusFilter == null,
                    onTap: () {
                      _statusFilter = null;
                      _load();
                    },
                  ),
                  _StatusChip(
                    label: 'Pendientes',
                    selected: _statusFilter == 'pending',
                    onTap: () {
                      _statusFilter = 'pending';
                      _load();
                    },
                  ),
                  _StatusChip(
                    label: 'Aprobados',
                    selected: _statusFilter == 'approved',
                    onTap: () {
                      _statusFilter = 'approved';
                      _load();
                    },
                  ),
                  _StatusChip(
                    label: 'Rechazados',
                    selected: _statusFilter == 'rejected',
                    onTap: () {
                      _statusFilter = 'rejected';
                      _load();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),
              FutureBuilder<AuthorizationsData>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const TableSkeleton(rows: 6);
                  }
                  if (snapshot.hasError) {
                    return SaasErrorState(
                      title: 'Error al cargar autorizaciones',
                      message:
                          'No se pudieron consultar las solicitudes. Intenta de nuevo.',
                      onRetry: _load,
                    );
                  }
                  final data = snapshot.data;
                  if (data == null ||
                      (data.withdrawals.isEmpty && data.discounts.isEmpty)) {
                    return const SaasEmptyState(
                      icon: Icons.verified_outlined,
                      title: 'Sin solicitudes en el periodo',
                      message:
                          'No hay retiros ni descuentos pendientes o históricos con los filtros actuales.',
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SummaryRow(data: data, isMobile: isMobile),
                      const SizedBox(height: 16),
                      if (_tab != _AuthTab.discounts) ...[
                        _WithdrawalsTableCard(
                          items: data.withdrawals,
                          branchNames: branchNames,
                          isMobile: isMobile,
                          canAuthorize:
                              widget.session.permissions.canViewAuthorizations,
                          onResolve: (w, approved) =>
                              _resolveWithdrawal(w, approved: approved),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_tab != _AuthTab.withdrawals)
                        _DiscountsTableCard(
                          items: data.discounts,
                          branchNames: branchNames,
                          isMobile: isMobile,
                          canAuthorize:
                              widget.session.permissions.canViewAuthorizations,
                          onResolve: (d, approved) =>
                              _resolveDiscount(d, approved: approved),
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
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.data, required this.isMobile});

  final AuthorizationsData data;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final cards = [
      (
        'Pendientes',
        '${data.pendingCount}',
        'Requieren revisión',
        tokens.warning,
      ),
      (
        'Aprobadas',
        '${data.approvedCount}',
        'Autorizadas en periodo',
        tokens.success,
      ),
      (
        'Retiros aprobados',
        BackofficeSalesAdapter.formatMoney(data.approvedWithdrawalsAmount),
        'Salidas de efectivo',
        tokens.brandAccent,
      ),
      (
        'Descuentos autorizados',
        BackofficeSalesAdapter.formatMoney(data.approvedDiscountsAmount),
        'Impacto en ventas',
        tokens.info,
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

class _WithdrawalsTableCard extends StatelessWidget {
  const _WithdrawalsTableCard({
    required this.items,
    required this.branchNames,
    required this.isMobile,
    required this.canAuthorize,
    required this.onResolve,
  });

  final List<CashWithdrawalRequest> items;
  final Map<String, String> branchNames;
  final bool isMobile;
  final bool canAuthorize;
  final void Function(CashWithdrawalRequest, bool) onResolve;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return SaasCard(
      title: 'Solicitudes de retiro de caja',
      subtitle: '${items.length} registro(s) encontrado(s)',
      padding: items.isEmpty ? const EdgeInsets.all(20) : EdgeInsets.zero,
      child: items.isEmpty
          ? Text(
              'Sin solicitudes de retiro con los filtros actuales.',
              style: TextStyle(fontSize: 13, color: tokens.textSecondary),
            )
          : isMobile
          ? ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
              itemBuilder: (context, index) {
                final w = items[index];
                final resolver = w.isApproved
                    ? (w.approvedByEmployeeName ??
                          w.authorizedByEmployeeName ??
                          '—')
                    : w.isRejected
                    ? (w.rejectedByEmployeeName ?? '—')
                    : 'En espera';
                return Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              w.reason.isEmpty ? 'Retiro de caja' : w.reason,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          _authPill(w.status),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${branchNames[w.branchId] ?? w.branchName} · ${w.businessDate}',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Solicita: ${w.requestedByEmployeeName} · Resuelve: $resolver',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        BackofficeSalesAdapter.formatMoney(w.amount),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (canAuthorize && w.isPending) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => onResolve(w, false),
                                child: const Text('Rechazar'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => onResolve(w, true),
                                child: const Text('Autorizar'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Fecha')),
                  DataColumn(label: Text('Sucursal')),
                  DataColumn(label: Text('Motivo')),
                  DataColumn(label: Text('Solicitante')),
                  DataColumn(label: Text('Responsable')),
                  DataColumn(label: Text('Estado')),
                  DataColumn(label: Text('Monto'), numeric: true),
                  DataColumn(label: Text('Acciones')),
                ],
                rows: items.map((w) {
                  final resolver = w.isApproved
                      ? (w.approvedByEmployeeName ??
                            w.authorizedByEmployeeName ??
                            '—')
                      : w.isRejected
                      ? (w.rejectedByEmployeeName ?? '—')
                      : 'En espera';
                  return DataRow(
                    cells: [
                      DataCell(Text(w.businessDate)),
                      DataCell(Text(branchNames[w.branchId] ?? w.branchName)),
                      DataCell(Text(w.reason.isEmpty ? 'Retiro' : w.reason)),
                      DataCell(Text(w.requestedByEmployeeName)),
                      DataCell(Text(resolver)),
                      DataCell(_authPill(w.status)),
                      DataCell(
                        Text(
                          BackofficeSalesAdapter.formatMoney(w.amount),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(
                        canAuthorize && w.isPending
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () => onResolve(w, false),
                                    child: const Text('Rechazar'),
                                  ),
                                  FilledButton.tonal(
                                    onPressed: () => onResolve(w, true),
                                    child: const Text('Autorizar'),
                                  ),
                                ],
                              )
                            : const Text('—'),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }
}

class _DiscountsTableCard extends StatelessWidget {
  const _DiscountsTableCard({
    required this.items,
    required this.branchNames,
    required this.isMobile,
    required this.canAuthorize,
    required this.onResolve,
  });

  final List<DiscountAuthorizationRequest> items;
  final Map<String, String> branchNames;
  final bool isMobile;
  final bool canAuthorize;
  final void Function(DiscountAuthorizationRequest, bool) onResolve;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return SaasCard(
      title: 'Autorizaciones de descuento',
      subtitle: '${items.length} registro(s) encontrado(s)',
      padding: items.isEmpty ? const EdgeInsets.all(20) : EdgeInsets.zero,
      child: items.isEmpty
          ? Text(
              'Sin solicitudes de descuento con los filtros actuales.',
              style: TextStyle(fontSize: 13, color: tokens.textSecondary),
            )
          : isMobile
          ? ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: tokens.border),
              itemBuilder: (context, index) {
                final d = items[index];
                final resolver = d.isApproved
                    ? (d.approvedByEmployeeName.isNotEmpty
                          ? d.approvedByEmployeeName
                          : d.approvedByPartnerName.isNotEmpty
                          ? d.approvedByPartnerName
                          : '—')
                    : d.isRejected
                    ? (d.rejectedByEmployeeName.isNotEmpty
                          ? d.rejectedByEmployeeName
                          : '—')
                    : 'En espera';
                return Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${d.requestedDiscountName} (${d.requestedDiscountPercent.toStringAsFixed(0)}%)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          _authPill(d.status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${d.tableName} · ${branchNames[d.branchId] ?? d.branchName} · ${d.businessDate}',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textSecondary,
                        ),
                      ),
                      if (d.requestReason.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Motivo: ${d.requestReason}',
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Resuelve: $resolver',
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.textSecondary,
                            ),
                          ),
                          Text(
                            '-${BackofficeSalesAdapter.formatMoney(d.estimatedDiscountAmount)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: tokens.brandAccent,
                            ),
                          ),
                        ],
                      ),
                      if (canAuthorize && d.isPending) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => onResolve(d, false),
                                child: const Text('Rechazar'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => onResolve(d, true),
                                child: const Text('Autorizar'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Fecha')),
                  DataColumn(label: Text('Sucursal')),
                  DataColumn(label: Text('Mesa / Canal')),
                  DataColumn(label: Text('Descuento')),
                  DataColumn(label: Text('Motivo')),
                  DataColumn(label: Text('Solicita')),
                  DataColumn(label: Text('Resuelve')),
                  DataColumn(label: Text('Estado')),
                  DataColumn(label: Text('Importe'), numeric: true),
                  DataColumn(label: Text('Acciones')),
                ],
                rows: items.map((d) {
                  final resolver = d.isApproved
                      ? (d.approvedByEmployeeName.isNotEmpty
                            ? d.approvedByEmployeeName
                            : d.approvedByPartnerName.isNotEmpty
                            ? d.approvedByPartnerName
                            : '—')
                      : d.isRejected
                      ? (d.rejectedByEmployeeName.isNotEmpty
                            ? d.rejectedByEmployeeName
                            : '—')
                      : 'En espera';
                  return DataRow(
                    cells: [
                      DataCell(Text(d.businessDate)),
                      DataCell(Text(branchNames[d.branchId] ?? d.branchName)),
                      DataCell(Text(d.tableName)),
                      DataCell(
                        Text(
                          '${d.requestedDiscountName} (${d.requestedDiscountPercent.toStringAsFixed(0)}%)',
                        ),
                      ),
                      DataCell(
                        Text(d.requestReason.isEmpty ? '—' : d.requestReason),
                      ),
                      DataCell(Text(d.requestedByEmployeeName)),
                      DataCell(Text(resolver)),
                      DataCell(_authPill(d.status)),
                      DataCell(
                        Text(
                          BackofficeSalesAdapter.formatMoney(
                            d.estimatedDiscountAmount,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(
                        canAuthorize && d.isPending
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () => onResolve(d, false),
                                    child: const Text('Rechazar'),
                                  ),
                                  FilledButton.tonal(
                                    onPressed: () => onResolve(d, true),
                                    child: const Text('Autorizar'),
                                  ),
                                ],
                              )
                            : const Text('—'),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }
}

StatusPill _authPill(String status) {
  switch (status.trim().toLowerCase()) {
    case 'approved':
      return const StatusPill(label: 'Aprobado', tone: StatusTone.success);
    case 'rejected':
      return const StatusPill(label: 'Rechazado', tone: StatusTone.danger);
    default:
      return const StatusPill(label: 'Pendiente', tone: StatusTone.warning);
  }
}
