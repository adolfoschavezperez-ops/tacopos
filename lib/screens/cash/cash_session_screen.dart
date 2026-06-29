import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/cash_session.dart';
import '../../models/cash_withdrawal_request.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';
import 'close_cash_session_screen.dart';

class CashSessionScreen extends StatefulWidget {
  const CashSessionScreen({super.key});

  @override
  State<CashSessionScreen> createState() => _CashSessionScreenState();
}

class _CashSessionScreenState extends State<CashSessionScreen> {
  final _repository = TacoPosRepository();
  final _openingCashController = TextEditingController(text: '0');
  late DateTime _selectedDate;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
  }

  @override
  void dispose() {
    _openingCashController.dispose();
    super.dispose();
  }

  String get _businessDate => DateFormat('yyyy-MM-dd').format(_selectedDate);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (!mounted || picked == null) {
      return;
    }

    setState(() {
      _selectedDate = picked;
    });
  }

  Future<void> _openCashSession() async {
    if (_opening) {
      return;
    }

    final openingCash = _parseAmount(_openingCashController.text);
    if (openingCash == null || openingCash < 0) {
      _showMessage('Captura un fondo inicial valido.');
      return;
    }

    setState(() {
      _opening = true;
    });

    try {
      await _repository.openCashSession(
        businessDate: _businessDate,
        openingCashAmount: openingCash,
      );
      if (!mounted) {
        return;
      }
      _showMessage('Caja abierta para $_businessDate.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(_errorText(error));
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
        });
      }
    }
  }

  Future<void> _closeCashSession(CashSession session) async {
    final result = await Navigator.push<CashSession>(
      context,
      MaterialPageRoute(
        builder: (_) => CloseCashSessionScreen(session: session),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    if (result.shortageAmount > 0) {
      _showMessage(
        'Corte realizado con faltante de \$${result.shortageAmount.toStringAsFixed(2)}.',
      );
    } else {
      _showMessage('Corte realizado correctamente.');
    }
  }

  Future<void> _requestWithdrawal(CashSession session) async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _WithdrawalRequestDialog(repository: _repository, session: session),
    );

    if (!mounted || sent != true) {
      return;
    }

    _showMessage('Solicitud enviada. Pendiente de autorizacion.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorText(Object error) {
    return error.toString().replaceFirst('Bad state: ', '');
  }

  double? _parseAmount(String text) {
    return double.tryParse(text.trim().replaceAll(',', '.'));
  }

  @override
  Widget build(BuildContext context) {
    final employee = AppSession.instance.employee;
    final canView =
        employee?.canCharge == true || employee?.canManageCash == true;
    final canOpenCash =
        employee?.canCharge == true || employee?.canManageCash == true;
    if (!canView) {
      return const BrandedScaffold(
        title: 'Caja / Corte',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para ver caja.',
        ),
      );
    }

    return BrandedScaffold(
      title: 'Caja / Corte',
      body: StreamBuilder<CashSession?>(
        stream: _repository.watchOpenCashSession(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudo cargar caja',
              message: '${snapshot.error}',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Cargando caja...');
          }

          final session = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              const SectionHeader(
                title: 'Caja / Corte',
                subtitle: 'Apertura, totales del dia y cierre operativo.',
              ),
              const SizedBox(height: 18),
              if (session == null)
                _OpenCashPanel(
                  businessDate: _businessDate,
                  openingController: _openingCashController,
                  canOpenCash: canOpenCash,
                  opening: _opening,
                  onPickDate: _pickDate,
                  onOpen: _openCashSession,
                )
              else
                _OpenSessionPanel(
                  session: session,
                  canManageCash: employee?.canManageCash == true,
                  canRequestWithdrawal:
                      employee?.canCharge == true ||
                      employee?.canManageCash == true,
                  currentEmployeeId: employee?.id ?? '',
                  repository: _repository,
                  onClose: () => _closeCashSession(session),
                  onRequestWithdrawal: () => _requestWithdrawal(session),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _OpenCashPanel extends StatelessWidget {
  const _OpenCashPanel({
    required this.businessDate,
    required this.openingController,
    required this.canOpenCash,
    required this.opening,
    required this.onPickDate,
    required this.onOpen,
  });

  final String businessDate;
  final TextEditingController openingController;
  final bool canOpenCash;
  final bool opening;
  final VoidCallback onPickDate;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'No hay caja abierta',
            subtitle: 'Abre caja antes de registrar pagos.',
          ),
          const SizedBox(height: 16),
          if (!canOpenCash) ...[
            const Text(
              'Pide a un encargado con permiso de caja que abra el dia.',
              style: TextStyle(
                color: BrandColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: opening ? null : onPickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text('Fecha operativa: $businessDate'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: openingController,
              enabled: !opening,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Fondo inicial de caja',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 16),
            GlassButton(
              icon: Icons.lock_open_outlined,
              label: opening ? 'Abriendo...' : 'Abrir caja',
              prominent: true,
              onTap: opening ? null : onOpen,
            ),
          ],
        ],
      ),
    );
  }
}

class _OpenSessionPanel extends StatelessWidget {
  const _OpenSessionPanel({
    required this.session,
    required this.canManageCash,
    required this.canRequestWithdrawal,
    required this.currentEmployeeId,
    required this.repository,
    required this.onClose,
    required this.onRequestWithdrawal,
  });

  final CashSession session;
  final bool canManageCash;
  final bool canRequestWithdrawal;
  final String currentEmployeeId;
  final TacoPosRepository repository;
  final VoidCallback onClose;
  final VoidCallback onRequestWithdrawal;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CashWithdrawalRequest>>(
      stream: repository.watchCashWithdrawalRequests(
        cashSessionId: session.id,
        requestedByEmployeeId: currentEmployeeId.isEmpty
            ? null
            : currentEmployeeId,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudieron cargar retiros',
            message: '${snapshot.error}',
          );
        }

        final requests = snapshot.data ?? [];
        final hasPending = requests.any((request) => request.isPending);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: 'Caja abierta',
                    subtitle:
                        '${session.businessDate} | abierta por ${session.openedByEmployeeName.isEmpty ? 'Empleado' : session.openedByEmployeeName}',
                    trailing: const Icon(
                      Icons.point_of_sale_outlined,
                      color: BrandColors.success,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _MoneyLine(
                    label: 'Fondo inicial',
                    value: session.openingCashAmount,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Los totales del sistema se calculan al cerrar y solo se muestran en Admin.',
                    style: TextStyle(
                      color: BrandColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: 'Retiros solicitados',
                    subtitle: hasPending
                        ? 'Hay retiros pendientes de autorizacion.'
                        : 'Solicitudes del dia para este usuario.',
                    trailing: canRequestWithdrawal
                        ? IconButton(
                            tooltip: 'Solicitar retiro',
                            onPressed: onRequestWithdrawal,
                            icon: const Icon(Icons.request_quote_outlined),
                          )
                        : null,
                  ),
                  const SizedBox(height: 10),
                  if (requests.isEmpty)
                    const Text(
                      'Sin solicitudes registradas.',
                      style: TextStyle(color: BrandColors.textMuted),
                    )
                  else
                    ...requests.map(
                      (request) => _WithdrawalRequestTile(request: request),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (canManageCash)
              Align(
                alignment: Alignment.centerRight,
                child: GlassButton(
                  icon: Icons.lock_outline,
                  label: 'Cerrar caja',
                  prominent: true,
                  onTap: onClose,
                ),
              )
            else
              const GlassPanel(
                child: Text(
                  'Solo un encargado con permiso de caja puede cerrar el dia.',
                  style: TextStyle(
                    color: BrandColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WithdrawalRequestDialog extends StatefulWidget {
  const _WithdrawalRequestDialog({
    required this.repository,
    required this.session,
  });

  final TacoPosRepository repository;
  final CashSession session;

  @override
  State<_WithdrawalRequestDialog> createState() =>
      _WithdrawalRequestDialogState();
}

class _WithdrawalRequestDialogState extends State<_WithdrawalRequestDialog> {
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  final _amountFocusNode = FocusNode();
  final _reasonFocusNode = FocusNode();
  bool _saving = false;
  String _error = '';

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    _amountFocusNode.dispose();
    _reasonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) {
      setState(() {
        _error = 'Captura un monto valido.';
      });
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      setState(() {
        _error = 'Captura el motivo.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = '';
    });

    try {
      await widget.repository.requestCashWithdrawal(
        cashSessionId: widget.session.id,
        amount: amount,
        reason: _reasonController.text,
      );
      if (!mounted) {
        return;
      }
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Solicitar retiro'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amountController,
              focusNode: _amountFocusNode,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Monto',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              focusNode: _reasonFocusNode,
              enabled: !_saving,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Motivo'),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _error,
                style: const TextStyle(
                  color: BrandColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'Enviando...' : 'Enviar'),
        ),
      ],
    );
  }
}

class _WithdrawalRequestTile extends StatelessWidget {
  const _WithdrawalRequestTile({required this.request});

  final CashWithdrawalRequest request;

  @override
  Widget build(BuildContext context) {
    final color = request.isApproved
        ? BrandColors.success
        : request.isRejected
        ? BrandColors.danger
        : BrandColors.accentYellow;
    final label = request.isApproved
        ? 'Aprobado'
        : request.isRejected
        ? 'Rechazado'
        : 'Pendiente';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.request_quote_outlined, color: color),
      title: Text(
        request.reason,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(label, style: TextStyle(color: color)),
      trailing: MoneyText(
        value: request.amount,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _MoneyLine extends StatelessWidget {
  const _MoneyLine({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: BrandColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          MoneyText(
            value: value,
            style: const TextStyle(
              color: BrandColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
