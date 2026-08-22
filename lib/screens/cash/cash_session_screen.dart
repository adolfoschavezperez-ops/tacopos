import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/cash/cash_close_execution.dart';
import '../../core/expenses/expense_policy.dart';
import '../../core/theme/brand_colors.dart';
import '../../models/cash_session.dart';
import '../../models/cash_withdrawal_request.dart';
import '../../services/app_session.dart';
import '../../services/live_presence_service.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/cash_close_progress_dialog.dart';
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
  final _closeGuard = CashCloseExecutionGuard();
  final _progressStage = ValueNotifier(CashCloseProgressStage.validatingOrders);
  BuildContext? _progressDialogContext;
  Future<void>? _progressDialogFuture;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    LivePresenceService.instance.update(
      appMode: 'cash',
      currentScreen: 'Caja',
      currentAction: 'Administrando caja',
    );
  }

  @override
  void dispose() {
    _openingCashController.dispose();
    _progressStage.dispose();
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
    if (!_closeGuard.tryStart()) {
      return;
    }

    setState(() {});
    try {
      await _showProgressDialog();
      final blockers = await _repository.cashCloseBlockers(session.id);
      await _dismissProgressDialog();
      if (!mounted) {
        return;
      }
      if (!blockers.canClose) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Cierre bloqueado'),
            content: Text('${blockers.message}\n\n${blockers.detail}'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        return;
      }

      final result = await Navigator.push<CashSession>(
        context,
        MaterialPageRoute(
          builder: (_) => CloseCashSessionScreen(session: session),
        ),
      );

      if (!mounted || result == null) {
        return;
      }

      _showMessage('Corte guardado correctamente.');
      if (result.netDifference < 0) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Corte con diferencias'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'El corte cuenta con diferencias. Hizo falta \$${result.shortageAmount.toStringAsFixed(2)} en caja.',
                ),
                const SizedBox(height: 12),
                _CashCloseDiffRow(
                  label: 'Efectivo esperado',
                  value: result.expectedCashAmount,
                ),
                _CashCloseDiffRow(
                  label: 'Efectivo contado',
                  value: result.countedCashAmount,
                ),
                _CashCloseDiffRow(
                  label: 'Diferencia efectivo',
                  value: result.cashDifference,
                ),
                _CashCloseDiffRow(
                  label: 'Tarjeta esperada',
                  value: result.expectedCardChargedAmount,
                ),
                _CashCloseDiffRow(
                  label: 'Comision absorbida',
                  value: result.expectedCardFeeAbsorbedAmount,
                ),
                _CashCloseDiffRow(
                  label: 'Neto estimado tarjeta',
                  value: result.estimatedCardNetAmount,
                ),
                _CashCloseDiffRow(
                  label: 'Terminal reportada',
                  value: result.terminalReportedAmount,
                ),
                _CashCloseDiffRow(
                  label: 'Diferencia tarjeta',
                  value: result.cardDifference,
                ),
                _CashCloseDiffRow(
                  label: 'Retiros aprobados',
                  value: result.approvedWithdrawalsTotal,
                ),
                _CashCloseDiffRow(
                  label: 'Faltante neto',
                  value: result.netDifference,
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
    } catch (error, stackTrace) {
      await _dismissProgressDialog();
      debugPrint(
        'Error al validar cierre de caja ${session.id}: $error\n$stackTrace',
      );
      if (!mounted) {
        return;
      }
      debugPrintCashCloseFailure(
        error: error,
        stackTrace: stackTrace,
        businessDate: session.businessDate,
        cashSessionId: session.id,
      );
      _showMessage(cashCloseErrorMessage(error), type: AppSnackBarType.error);
    } finally {
      await _dismissProgressDialog();
      _closeGuard.release();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _showProgressDialog() async {
    if (!mounted || _progressDialogFuture != null) {
      return;
    }
    _progressStage.value = CashCloseProgressStage.validatingOrders;
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _progressDialogContext = dialogContext;
        return CashCloseProgressDialog(stageListenable: _progressStage);
      },
    );
    _progressDialogFuture = dialogFuture;
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _dismissProgressDialog() async {
    final dialogContext = _progressDialogContext;
    final dialogFuture = _progressDialogFuture;
    _progressDialogContext = null;
    _progressDialogFuture = null;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
    await dialogFuture;
  }

  Future<void> _requestWithdrawal(CashSession session) async {
    final sent = await showWithdrawalRequestDialog(
      context,
      repository: _repository,
      session: session,
    );

    if (!mounted || sent != true) {
      return;
    }

    _showMessage('Solicitud enviada. Pendiente de autorizacion.');
  }

  void _showMessage(
    String message, {
    AppSnackBarType type = AppSnackBarType.success,
  }) {
    showAppSnackBar(context, message, type: type);
  }

  String _errorText(Object error) {
    return error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Invalid argument(s): ', '');
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
                  closing: _closeGuard.isActive,
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

Future<bool?> showWithdrawalRequestDialog(
  BuildContext context, {
  required TacoPosRepository repository,
  required CashSession session,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) =>
        WithdrawalRequestDialog(repository: repository, session: session),
  );
}

class _CashCloseDiffRow extends StatelessWidget {
  const _CashCloseDiffRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          MoneyText(
            value: value,
            style: TextStyle(
              color: value < 0 ? BrandColors.danger : BrandColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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
    required this.closing,
    required this.repository,
    required this.onClose,
    required this.onRequestWithdrawal,
  });

  final CashSession session;
  final bool canManageCash;
  final bool canRequestWithdrawal;
  final bool closing;
  final TacoPosRepository repository;
  final VoidCallback onClose;
  final VoidCallback onRequestWithdrawal;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CashWithdrawalRequest>>(
      stream: repository.watchCashWithdrawalRequests(cashSessionId: session.id),
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
                        ? 'Hay solicitudes de gasto pendientes de autorizacion.'
                        : 'Solicitudes registradas para esta caja.',
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
                  label: closing ? 'Validando...' : 'Cerrar caja',
                  prominent: true,
                  loading: closing,
                  onTap: hasPending || closing ? null : onClose,
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

class WithdrawalRequestDialog extends StatefulWidget {
  const WithdrawalRequestDialog({
    required this.repository,
    required this.session,
    super.key,
  });

  final TacoPosRepository repository;
  final CashSession session;

  @override
  State<WithdrawalRequestDialog> createState() =>
      _WithdrawalRequestDialogState();
}

class _WithdrawalRequestDialogState extends State<WithdrawalRequestDialog> {
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  final _amountFocusNode = FocusNode();
  final _reasonFocusNode = FocusNode();
  StreamSubscription<List<ExpensePolicyUsage>>? _usageSubscription;
  List<ExpensePolicy> _policies = const [];
  List<ExpensePolicyUsage> _usageRows = const [];
  String _selectedPolicyId = '';
  bool _selectedPolicyAllowsFreeConcept = true;
  bool _policyPickerOpen = false;
  bool _policiesLoaded = false;
  bool _usageLoaded = false;
  bool _usageFailed = false;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadPolicies();
    _usageSubscription = widget.repository
        .watchCurrentBranchExpensePolicyUsage()
        .listen(
          (usageRows) {
            if (!mounted) return;
            setState(() {
              _usageRows = usageRows;
              _usageLoaded = true;
              _usageFailed = false;
            });
            _clearUnavailableSelection();
          },
          onError: (_) {
            if (!mounted) return;
            setState(() {
              _usageRows = const [];
              _usageLoaded = true;
              _usageFailed = true;
            });
            _clearUnavailableSelection();
          },
        );
  }

  @override
  void dispose() {
    unawaited(_usageSubscription?.cancel());
    _amountController.dispose();
    _reasonController.dispose();
    _amountFocusNode.dispose();
    _reasonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadPolicies() async {
    try {
      final policies = await widget.repository.getActiveExpensePoliciesOnce();
      if (!mounted) return;
      setState(() {
        _policies = policies;
        _policiesLoaded = true;
      });
      _clearUnavailableSelection();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _policies = const [];
        _policiesLoaded = true;
        _error = 'No fue posible cargar los tipos de gasto.';
      });
    }
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
        policyId: _selectedPolicyId,
        paymentSource: 'cash',
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

  Map<String, ExpensePolicyAvailability> _availabilityByPolicy() {
    final usageByPeriod = {
      for (final usage in _usageRows) usage.periodKey: usage,
    };
    return {
      for (final policy in _policies)
        policy.id: evaluateExpensePolicyAvailability(
          policy: policy,
          usage: _usageFailed
              ? null
              : _usageForCurrentPeriod(
                  policy: policy,
                  usageByPeriod: usageByPeriod,
                ),
          businessDate: widget.session.businessDate,
          usageLoaded: _usageLoaded,
        ),
    };
  }

  bool _isPolicyExhausted(ExpensePolicyAvailability? availability) {
    return availability?.reasonCode == 'max_uses' ||
        availability?.reasonCode == 'max_period_amount';
  }

  List<ExpensePolicy> _selectablePolicies(
    Map<String, ExpensePolicyAvailability> availabilityByPolicy,
  ) {
    return _policies
        .where((policy) => !_isPolicyExhausted(availabilityByPolicy[policy.id]))
        .toList();
  }

  ExpensePolicyUsage? _usageForCurrentPeriod({
    required ExpensePolicy policy,
    required Map<String, ExpensePolicyUsage> usageByPeriod,
  }) {
    final periodKey = expensePolicyPeriodKey(
      policy: policy,
      businessDate: widget.session.businessDate,
    );
    return usageByPeriod[periodKey] ??
        ExpensePolicyUsage(
          id: '',
          policyId: policy.id,
          branchId: policy.branchId,
          periodKey: periodKey,
        );
  }

  ExpensePolicy? _findPolicy(List<ExpensePolicy> policies, String policyId) {
    for (final policy in policies) {
      if (policy.id == policyId) return policy;
    }
    return null;
  }

  void _clearUnavailableSelection() {
    if (_selectedPolicyId.isEmpty || !_policiesLoaded) return;
    final policy = _findPolicy(_policies, _selectedPolicyId);
    final availability = policy == null
        ? null
        : _availabilityByPolicy()[_selectedPolicyId];
    if (policy != null && !_isPolicyExhausted(availability)) return;
    if (!mounted) return;
    setState(() {
      _selectedPolicyId = '';
      _selectedPolicyAllowsFreeConcept = true;
      _reasonController.clear();
    });
  }

  Widget _buildPolicySelector() {
    final availabilityByPolicy = _availabilityByPolicy();
    final policies = _selectablePolicies(availabilityByPolicy);
    final selectedPolicy = _findPolicy(policies, _selectedPolicyId);
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: _saving
              ? null
              : () => setState(() => _policyPickerOpen = !_policyPickerOpen),
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Tipo de gasto'),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    !_policiesLoaded
                        ? 'Cargando tipos de gasto'
                        : selectedPolicy?.name ?? 'Solicitud manual',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Icon(_policyPickerOpen ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        if (_policyPickerOpen) ...[
          const SizedBox(height: 8),
          _InlinePolicyPicker(
            policies: policies,
            selectedPolicyId: _selectedPolicyId,
            onManualSelected: () => _selectPolicy(''),
            onPolicySelected: _selectPolicy,
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  void _selectPolicy(String selectedId) {
    final policy = _findPolicy(
      _selectablePolicies(_availabilityByPolicy()),
      selectedId,
    );
    setState(() {
      _selectedPolicyId = selectedId;
      _policyPickerOpen = false;
      if (policy != null && !policy.allowFreeConcept) {
        _selectedPolicyAllowsFreeConcept = false;
        _reasonController.text = policy.name;
      } else if (policy == null) {
        _selectedPolicyAllowsFreeConcept = true;
        _reasonController.clear();
      } else {
        _selectedPolicyAllowsFreeConcept = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final targetWidth = size.width < 380 ? size.width - 32 : size.width * 0.85;
    final dialogWidth = targetWidth.clamp(280.0, 780.0).toDouble();
    return AlertDialog(
      title: const Text('Solicitar retiro'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: dialogWidth,
          maxWidth: dialogWidth,
          maxHeight: MediaQuery.sizeOf(context).height * 0.58,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPolicySelector(),
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
                enabled: !_saving && _selectedPolicyAllowsFreeConcept,
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

class _InlinePolicyPicker extends StatelessWidget {
  const _InlinePolicyPicker({
    required this.policies,
    required this.selectedPolicyId,
    required this.onManualSelected,
    required this.onPolicySelected,
  });

  final List<ExpensePolicy> policies;
  final String selectedPolicyId;
  final VoidCallback onManualSelected;
  final ValueChanged<String> onPolicySelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: BrandColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BrandColors.glassBorder),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          ListTile(
            dense: true,
            title: const Text(
              'Solicitud manual',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            selected: selectedPolicyId.isEmpty,
            onTap: onManualSelected,
            trailing: selectedPolicyId.isEmpty
                ? const Icon(Icons.check, color: BrandColors.accentYellow)
                : null,
          ),
          for (final policy in policies)
            _PolicyPickerTile(
              policy: policy,
              selected: policy.id == selectedPolicyId,
              onSelected: () => onPolicySelected(policy.id),
            ),
        ],
      ),
    );
  }
}

class _PolicyPickerTile extends StatelessWidget {
  const _PolicyPickerTile({
    required this.policy,
    required this.selected,
    required this.onSelected,
  });

  final ExpensePolicy policy;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      onTap: onSelected,
      title: Text(
        policy.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: BrandColors.accentYellow)
          : null,
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
      subtitle: Text(
        request.policyName.trim().isEmpty
            ? label
            : '$label - ${request.policyOutcomeLabel}: ${request.policyName}',
        style: TextStyle(color: color),
      ),
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
