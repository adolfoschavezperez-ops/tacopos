import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/cash_withdrawal_request.dart';
import '../../models/discount_authorization_request.dart';
import '../../models/purchase_models.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';

class AuthorizationAdminScreen extends StatefulWidget {
  const AuthorizationAdminScreen({super.key});

  @override
  State<AuthorizationAdminScreen> createState() =>
      _AuthorizationAdminScreenState();
}

class _AuthorizationAdminScreenState extends State<AuthorizationAdminScreen> {
  final _repository = TacoPosRepository();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Gastos extras de caja'),
              Tab(text: 'Descuentos familia/amigos'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _CashWithdrawalAuthorizations(repository: _repository),
                _DiscountAuthorizations(repository: _repository),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CashWithdrawalAuthorizations extends StatelessWidget {
  const _CashWithdrawalAuthorizations({required this.repository});

  final TacoPosRepository repository;

  @override
  Widget build(BuildContext context) {
    final canAuthorize =
        AppSession.instance.employee?.canAuthorizeCashWithdrawals == true;
    return StreamBuilder<List<CashWithdrawalRequest>>(
      stream: repository.watchCashWithdrawalRequests(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudieron cargar gastos',
            message: '${snapshot.error}',
          );
        }
        if (!snapshot.hasData) {
          return const LoadingPanel(message: 'Cargando autorizaciones...');
        }
        final requests = snapshot.data ?? const [];
        final pending = requests.where((request) => request.isPending).toList();
        final history = requests.where((request) => !request.isPending);
        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const SectionHeader(
              title: 'Gastos extras de caja',
              subtitle: 'Solicitudes pendientes y atendidas por sucursal.',
            ),
            const SizedBox(height: 14),
            if (pending.isEmpty)
              const EmptyState(
                icon: Icons.request_quote_outlined,
                title: 'Sin gastos pendientes',
                message: 'Las solicitudes nuevas apareceran aqui.',
              )
            else
              ...pending.map(
                (request) => _WithdrawalAuthorizationCard(
                  request: request,
                  repository: repository,
                  canAuthorize: canAuthorize,
                ),
              ),
            const SizedBox(height: 22),
            const SectionHeader(title: 'Historial'),
            const SizedBox(height: 12),
            if (history.isEmpty)
              const GlassPanel(
                child: Text(
                  'Aun no hay gastos atendidos.',
                  style: TextStyle(color: BrandColors.textMuted),
                ),
              )
            else
              ...history
                  .take(40)
                  .map(
                    (request) => _WithdrawalAuthorizationCard(
                      request: request,
                      repository: repository,
                      canAuthorize: false,
                    ),
                  ),
          ],
        );
      },
    );
  }
}

class _WithdrawalAuthorizationCard extends StatelessWidget {
  const _WithdrawalAuthorizationCard({
    required this.request,
    required this.repository,
    required this.canAuthorize,
  });

  final CashWithdrawalRequest request;
  final TacoPosRepository repository;
  final bool canAuthorize;

  @override
  Widget build(BuildContext context) {
    final color = request.isApproved
        ? BrandColors.success
        : request.isRejected
        ? BrandColors.danger
        : BrandColors.accentYellow;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        borderColor: request.isPending ? BrandColors.accentYellow : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payments_outlined, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    request.reason,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                MoneyText(
                  value: request.amount,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _InfoLine('Estado', _withdrawalStatus(request)),
            _InfoLine('Sucursal', request.branchName),
            _InfoLine('Caja', request.businessDate),
            _InfoLine('Solicitado por', request.requestedByEmployeeName),
            _InfoLine('Solicitado', _dateTime(request.requestedAt)),
            if (!request.isPending) ...[
              _InfoLine(
                request.isApproved ? 'Autorizado por' : 'Rechazado por',
                request.isApproved
                    ? request.approvedByEmployeeName ??
                          request.authorizedByEmployeeName ??
                          '-'
                    : request.rejectedByEmployeeName ??
                          request.authorizedByEmployeeName ??
                          '-',
              ),
              _InfoLine(
                request.isApproved ? 'Autorizado' : 'Rechazado',
                _dateTime(
                  request.isApproved
                      ? request.approvedAt ?? request.authorizedAt
                      : request.rejectedAt ?? request.authorizedAt,
                ),
              ),
              if (request.isRejected)
                _InfoLine(
                  'Motivo rechazo',
                  request.rejectReason?.isNotEmpty == true
                      ? request.rejectReason!
                      : request.adminNotes ?? '-',
                ),
            ],
            if (canAuthorize && request.isPending) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _resolve(context, approved: false),
                    icon: const Icon(Icons.close),
                    label: const Text('Rechazar'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () => _resolve(context, approved: true),
                    icon: const Icon(Icons.check),
                    label: const Text('Autorizar'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _resolve(BuildContext context, {required bool approved}) async {
    final reason = await _askReason(
      context,
      title: approved ? 'Autorizar gasto' : 'Rechazar gasto',
      label: approved ? 'Notas opcionales' : 'Motivo del rechazo',
      requiredValue: !approved,
    );
    if (reason == null || !context.mounted) return;
    try {
      await repository.authorizeCashWithdrawal(
        requestId: request.id,
        approved: approved,
        adminNotes: reason,
      );
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        approved ? 'Gasto autorizado.' : 'Gasto rechazado.',
        type: AppSnackBarType.success,
      );
    } catch (error) {
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
        type: AppSnackBarType.error,
      );
    }
  }
}

class _DiscountAuthorizations extends StatefulWidget {
  const _DiscountAuthorizations({required this.repository});

  final TacoPosRepository repository;

  @override
  State<_DiscountAuthorizations> createState() =>
      _DiscountAuthorizationsState();
}

class _DiscountAuthorizationsState extends State<_DiscountAuthorizations> {
  String _status = 'all';
  String? _partnerId;
  String? _employeeId;
  DateTime? _startDate;
  DateTime? _endDate;

  String? get _startBusinessDate =>
      _startDate == null ? null : DateFormat('yyyy-MM-dd').format(_startDate!);
  String? get _endBusinessDate =>
      _endDate == null ? null : DateFormat('yyyy-MM-dd').format(_endDate!);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Partner?>(
      future: widget.repository.currentEmployeeActivePartner(),
      builder: (context, partnerSnapshot) {
        final currentPartner = partnerSnapshot.data;
        return StreamBuilder<List<Partner>>(
          stream: widget.repository.watchPartners(activeOnly: true),
          builder: (context, partnersSnapshot) {
            final partners = partnersSnapshot.data ?? const [];
            return StreamBuilder<List<DiscountAuthorizationRequest>>(
              stream: widget.repository.watchDiscountAuthorizationRequests(
                status: _status == 'all' ? null : _status,
                startBusinessDate: _startBusinessDate,
                endBusinessDate: _endBusinessDate,
                partnerId: _partnerId,
                requestedByEmployeeId: _employeeId,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyState(
                    icon: Icons.error_outline,
                    title: 'No se pudieron cargar descuentos',
                    message: '${snapshot.error}',
                  );
                }
                if (!snapshot.hasData) {
                  return const LoadingPanel(
                    message: 'Cargando autorizaciones...',
                  );
                }
                final requests = snapshot.data ?? const [];
                final employees = _employeesFromRequests(requests);
                return ListView(
                  padding: const EdgeInsets.all(22),
                  children: [
                    const SectionHeader(
                      title: 'Descuentos familia/amigos',
                      subtitle:
                          'Historial de descuentos y autorizaciones automaticas.',
                    ),
                    const SizedBox(height: 12),
                    _DiscountFilters(
                      status: _status,
                      partnerId: _partnerId,
                      employeeId: _employeeId,
                      partners: partners,
                      employees: employees,
                      startDate: _startDate,
                      endDate: _endDate,
                      onStatusChanged: (value) =>
                          setState(() => _status = value ?? 'pending'),
                      onPartnerChanged: (value) =>
                          setState(() => _partnerId = value),
                      onEmployeeChanged: (value) =>
                          setState(() => _employeeId = value),
                      onPickStart: () => _pickDate(isStart: true),
                      onPickEnd: () => _pickDate(isStart: false),
                      onClearDates: () => setState(() {
                        _startDate = null;
                        _endDate = null;
                      }),
                    ),
                    const SizedBox(height: 14),
                    if (requests.isEmpty)
                      const EmptyState(
                        icon: Icons.verified_user_outlined,
                        title: 'Sin solicitudes',
                        message:
                            'Las autorizaciones de familia/amigos apareceran aqui.',
                      )
                    else
                      ...requests.map(
                        (request) => _DiscountAuthorizationCard(
                          request: request,
                          repository: widget.repository,
                          canResolve:
                              currentPartner != null && request.isPending,
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  List<_EmployeeFilter> _employeesFromRequests(
    List<DiscountAuthorizationRequest> requests,
  ) {
    final byId = <String, String>{};
    for (final request in requests) {
      if (request.requestedByEmployeeId.isNotEmpty) {
        byId[request.requestedByEmployeeId] = request.requestedByEmployeeName;
      }
    }
    final result =
        byId.entries
            .map((entry) => _EmployeeFilter(entry.key, entry.value))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? _startDate ?? DateTime.now()
        : _endDate ?? _startDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = DateTime(picked.year, picked.month, picked.day);
        if (_endDate != null && _endDate!.isBefore(_startDate!)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = DateTime(picked.year, picked.month, picked.day);
        if (_startDate != null && _startDate!.isAfter(_endDate!)) {
          _startDate = _endDate;
        }
      }
    });
  }
}

class _DiscountFilters extends StatelessWidget {
  const _DiscountFilters({
    required this.status,
    required this.partnerId,
    required this.employeeId,
    required this.partners,
    required this.employees,
    required this.startDate,
    required this.endDate,
    required this.onStatusChanged,
    required this.onPartnerChanged,
    required this.onEmployeeChanged,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onClearDates,
  });

  final String status;
  final String? partnerId;
  final String? employeeId;
  final List<Partner> partners;
  final List<_EmployeeFilter> employees;
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onPartnerChanged;
  final ValueChanged<String?> onEmployeeChanged;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onClearDates;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Pendientes')),
                DropdownMenuItem(value: 'approved', child: Text('Aprobadas')),
                DropdownMenuItem(value: 'rejected', child: Text('Rechazadas')),
                DropdownMenuItem(value: 'cancelled', child: Text('Canceladas')),
                DropdownMenuItem(value: 'used', child: Text('Usadas')),
                DropdownMenuItem(value: 'all', child: Text('Todas')),
              ],
              onChanged: onStatusChanged,
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              initialValue: partnerId,
              decoration: const InputDecoration(labelText: 'Socio'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todos'),
                ),
                ...partners.map(
                  (partner) => DropdownMenuItem<String?>(
                    value: partner.id,
                    child: Text(partner.name),
                  ),
                ),
              ],
              onChanged: onPartnerChanged,
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              initialValue: employeeId,
              decoration: const InputDecoration(labelText: 'Cajero'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todos'),
                ),
                ...employees.map(
                  (employee) => DropdownMenuItem<String?>(
                    value: employee.id,
                    child: Text(employee.name),
                  ),
                ),
              ],
              onChanged: onEmployeeChanged,
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPickStart,
            icon: const Icon(Icons.event_outlined),
            label: Text(
              startDate == null
                  ? 'Desde'
                  : DateFormat('dd/MM/yyyy').format(startDate!),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPickEnd,
            icon: const Icon(Icons.event_available_outlined),
            label: Text(
              endDate == null
                  ? 'Hasta'
                  : DateFormat('dd/MM/yyyy').format(endDate!),
            ),
          ),
          if (startDate != null || endDate != null)
            TextButton(
              onPressed: onClearDates,
              child: const Text('Limpiar fechas'),
            ),
        ],
      ),
    );
  }
}

class _DiscountAuthorizationCard extends StatelessWidget {
  const _DiscountAuthorizationCard({
    required this.request,
    required this.repository,
    required this.canResolve,
  });

  final DiscountAuthorizationRequest request;
  final TacoPosRepository repository;
  final bool canResolve;

  @override
  Widget build(BuildContext context) {
    final color = _discountStatusColor(request);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        borderColor: request.isPending ? BrandColors.accentYellow : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.percent_outlined, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    request.requestedDiscountName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _StatusChip(label: _discountStatusText(request), color: color),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                _InfoText('Sucursal', request.branchName),
                _InfoText('Pedido', request.tableName),
                _InfoText('Solicita', request.requestedByEmployeeName),
                if (!request.isAutoApproved)
                  _InfoText('Socio solicitado', request.requestedPartnerName),
                _InfoText('Fecha', _dateTime(request.requestedAt)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              request.requestReason,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _AmountBox('Subtotal', request.amountBeforeDiscount),
                _AmountBox('Desc. estimado', request.estimatedDiscountAmount),
                _AmountBox(
                  'Total estimado',
                  request.estimatedTotalAfterDiscount,
                ),
              ],
            ),
            if (!request.isPending) ...[
              const SizedBox(height: 10),
              _InfoLine(
                request.isAutoApproved
                    ? 'Modo'
                    : request.isRejected
                    ? 'Rechazado por'
                    : 'Autorizado por',
                request.isAutoApproved
                    ? 'Autorizacion automatica'
                    : request.isRejected
                    ? request.rejectedByPartnerName
                    : request.approvedByPartnerName,
              ),
              _InfoLine(
                request.isAutoApproved
                    ? 'Autorizada'
                    : request.isRejected
                    ? 'Rechazado'
                    : 'Autorizado',
                _dateTime(
                  request.isRejected ? request.rejectedAt : request.approvedAt,
                ),
              ),
              if (request.isRejected)
                _InfoLine('Motivo rechazo', request.rejectReason),
              if (request.isUsed)
                _InfoLine('Pago ligado', request.usedPaymentId),
            ],
            if (request.isPending && !canResolve) ...[
              const SizedBox(height: 10),
              const Text(
                'Solo un socio puede autorizar este descuento.',
                style: TextStyle(
                  color: BrandColors.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            if (canResolve) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _resolve(context, approved: false),
                    icon: const Icon(Icons.close),
                    label: const Text('Rechazar'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () => _resolve(context, approved: true),
                    icon: const Icon(Icons.check),
                    label: const Text('Autorizar'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _resolve(BuildContext context, {required bool approved}) async {
    final reason = await _askReason(
      context,
      title: approved ? 'Autorizar descuento' : 'Rechazar descuento',
      label: approved ? 'Notas opcionales' : 'Motivo del rechazo',
      requiredValue: !approved,
    );
    if (reason == null || !context.mounted) return;
    try {
      await repository.resolveDiscountAuthorizationRequest(
        requestId: request.id,
        approved: approved,
        rejectReason: reason,
      );
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        approved ? 'Descuento autorizado.' : 'Descuento rechazado.',
        type: AppSnackBarType.success,
      );
    } catch (error) {
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
        type: AppSnackBarType.error,
      );
    }
  }
}

class _AmountBox extends StatelessWidget {
  const _AmountBox(this.label, this.value);

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: BrandColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          MoneyText(
            value: value,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.7)),
      backgroundColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w900),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 135,
            child: Text(
              label,
              style: const TextStyle(
                color: BrandColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoText extends StatelessWidget {
  const _InfoText(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: ${value.isEmpty ? '-' : value}',
      style: const TextStyle(
        color: BrandColors.textMuted,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _EmployeeFilter {
  const _EmployeeFilter(this.id, this.name);

  final String id;
  final String name;
}

Future<String?> _askReason(
  BuildContext context, {
  required String title,
  required String label,
  required bool requiredValue,
}) async {
  final controller = TextEditingController();
  String error = '';
  final result = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: label),
            ),
            if (error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: const TextStyle(
                  color: BrandColors.danger,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (requiredValue && controller.text.trim().isEmpty) {
                setState(() => error = 'Captura el motivo.');
                return;
              }
              Navigator.pop(context, controller.text.trim());
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}

String _withdrawalStatus(CashWithdrawalRequest request) {
  if (request.isApproved) return 'Aprobado';
  if (request.isRejected) return 'Rechazado';
  return 'Pendiente';
}

String _discountStatusText(DiscountAuthorizationRequest request) {
  if (request.isAutoApproved) return 'Autorizacion automatica';
  if (request.isUsed) return 'Usada';
  if (request.isApproved) return 'Aprobada';
  if (request.isRejected) return 'Rechazada';
  if (request.isCancelled) return 'Cancelada';
  return 'Pendiente';
}

Color _discountStatusColor(DiscountAuthorizationRequest request) {
  if (request.isUsed) return BrandColors.info;
  if (request.isApproved) return BrandColors.success;
  if (request.isRejected || request.isCancelled) return BrandColors.danger;
  return BrandColors.accentYellow;
}

String _dateTime(DateTime? value) {
  if (value == null) return '-';
  return DateFormat('dd/MM/yyyy HH:mm').format(value);
}
