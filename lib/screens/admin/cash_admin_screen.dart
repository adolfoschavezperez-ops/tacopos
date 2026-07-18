import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/branch.dart';
import '../../models/cash_session.dart';
import '../../models/cash_withdrawal_request.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../services/app_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';

class CashAdminScreen extends StatefulWidget {
  const CashAdminScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  State<CashAdminScreen> createState() => _CashAdminScreenState();
}

class _CashAdminScreenState extends State<CashAdminScreen> {
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

  String get _rangeLabel {
    if (_startBusinessDate == _endBusinessDate) {
      return _isToday(_startDate) ? 'Hoy' : _startBusinessDate;
    }
    return '$_startBusinessDate a $_endBusinessDate';
  }

  Future<void> _pickStartDate() async {
    final picked = await _pickDate(_startDate);
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _startDate = picked;
      if (_endDate.isBefore(_startDate)) {
        _endDate = _startDate;
      }
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await _pickDate(_endDate);
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _endDate = picked;
      if (_startDate.isAfter(_endDate)) {
        _startDate = _endDate;
      }
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

  void _resetToday() {
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
    final canOpenCashAdmin =
        employee?.canViewAdmin == true ||
        employee?.canAuthorizeCashWithdrawals == true;
    if (!canOpenCashAdmin) {
      return const BrandedScaffold(
        title: 'Caja Admin',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para ver cortes.',
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex,
      child: BrandedScaffold(
        title: 'Caja Admin',
        body: Column(
          children: [
            _DateRangePanel(
              label: _rangeLabel,
              startBusinessDate: _startBusinessDate,
              endBusinessDate: _endBusinessDate,
              onPickStart: _pickStartDate,
              onPickEnd: _pickEndDate,
              onToday: _resetToday,
            ),
            const TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              labelPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              dividerHeight: 0,
              tabs: [
                Tab(
                  height: 42,
                  iconMargin: EdgeInsets.only(bottom: 2),
                  icon: Icon(Icons.receipt_long, size: 19),
                  text: 'Cortes',
                ),
                Tab(
                  height: 42,
                  iconMargin: EdgeInsets.only(bottom: 2),
                  icon: Icon(Icons.verified_user_outlined, size: 19),
                  text: 'Retiros',
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _CashSessionsTab(
                    startBusinessDate: _startBusinessDate,
                    endBusinessDate: _endBusinessDate,
                  ),
                  _WithdrawalAuthorizationTab(
                    startBusinessDate: _startBusinessDate,
                    endBusinessDate: _endBusinessDate,
                  ),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        borderRadius: 14,
        child: Wrap(
          spacing: 8,
          runSpacing: 7,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 130),
              child: Text(
                'Viendo: $label',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
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

class _CashSessionsTab extends StatelessWidget {
  const _CashSessionsTab({
    required this.startBusinessDate,
    required this.endBusinessDate,
  });

  final String startBusinessDate;
  final String endBusinessDate;

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();
    return StreamBuilder<List<CashSession>>(
      stream: repository.watchCashSessions(
        startBusinessDate: startBusinessDate,
        endBusinessDate: endBusinessDate,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudieron cargar cortes',
            message: '${snapshot.error}',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPanel(message: 'Cargando cortes...');
        }

        final sessions = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          children: [
            SectionHeader(
              title: 'Cortes de caja',
              subtitle: 'Desglose completo para Admin / Socio.',
              trailing: AppSession.instance.employee?.hasAdminAccess == true
                  ? FilledButton.icon(
                      onPressed: () => _openHistoricalCorrection(context),
                      icon: const Icon(Icons.history_toggle_off_outlined),
                      label: const Text('Rehacer corte histórico'),
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            if (sessions.isEmpty)
              const SizedBox(
                height: 320,
                child: EmptyState(
                  icon: Icons.point_of_sale_outlined,
                  title: 'Sin cortes',
                  message: 'Aun no hay cajas registradas.',
                ),
              )
            else
              ...sessions.map(
                (session) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CashSessionDetailCard(session: session),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _openHistoricalCorrection(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      useSafeArea: true,
      builder: (context) =>
          _HistoricalCashCorrectionDialog(repository: TacoPosRepository()),
    );
    if (saved == true && context.mounted) {
      showAppSnackBar(
        context,
        'Corte histórico guardado.',
        type: AppSnackBarType.success,
      );
    }
  }
}

class _HistoricalCashCorrectionDialog extends StatefulWidget {
  const _HistoricalCashCorrectionDialog({required this.repository});

  final TacoPosRepository repository;

  @override
  State<_HistoricalCashCorrectionDialog> createState() =>
      _HistoricalCashCorrectionDialogState();
}

class _HistoricalCashCorrectionDialogState
    extends State<_HistoricalCashCorrectionDialog> {
  final _openingCashController = TextEditingController();
  final _cashController = TextEditingController();
  final _terminalController = TextEditingController();
  final _notesController = TextEditingController();
  final _pinController = TextEditingController();
  late final Future<List<Branch>> _branchesFuture;
  late DateTime _businessDate;
  String _branchId = '';
  HistoricalCashCorrectionPreview? _preview;
  String? _error;
  bool _loading = false;
  bool _saving = false;
  bool _confirmNoMovements = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _businessDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));
    _branchId = AppSession.instance.currentBranchId;
    _branchesFuture = widget.repository.getBranchesOnce();
    _openingCashController.addListener(_clearPreview);
    _cashController.addListener(_clearPreview);
    _terminalController.addListener(_clearPreview);
  }

  @override
  void dispose() {
    _openingCashController.dispose();
    _cashController.dispose();
    _terminalController.dispose();
    _notesController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _clearPreview() {
    if (_preview == null) return;
    setState(() {
      _preview = null;
      _confirmNoMovements = false;
    });
  }

  String get _businessDateText =>
      DateFormat('yyyy-MM-dd').format(_businessDate);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _businessDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _businessDate = DateTime(picked.year, picked.month, picked.day);
      _preview = null;
      _confirmNoMovements = false;
    });
  }

  Future<void> _previewCorrection(Branch branch) async {
    final cash = _amount(_cashController.text);
    final terminal = _amount(_terminalController.text);
    final openingCash = _optionalAmount(_openingCashController.text);
    final pin = _pinController.text.trim();
    final validation = _validationError(
      branch: branch,
      countedCash: cash,
      terminalReported: terminal,
      pin: pin,
      openingCash: openingCash,
    );
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
      _confirmNoMovements = false;
    });
    try {
      final preview = await widget.repository.previewHistoricalCashCorrection(
        branch: branch,
        businessDate: _businessDateText,
        countedCashAmount: cash!,
        terminalReportedAmount: terminal!,
        adminPin: pin,
        openingCashAmount: openingCash,
      );
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (error, stackTrace) {
      debugPrint(
        '[TacoPOS][HistoricalCashCorrection.preview] $error\n$stackTrace',
      );
      if (!mounted) return;
      setState(
        () => _error =
            'No se pudo recalcular el corte. Intenta nuevamente o revisa la conexión.',
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save(Branch branch) async {
    final cash = _amount(_cashController.text);
    final terminal = _amount(_terminalController.text);
    final openingCash = _optionalAmount(_openingCashController.text);
    final pin = _pinController.text.trim();
    final validation = _validationError(
      branch: branch,
      countedCash: cash,
      terminalReported: terminal,
      pin: pin,
      openingCash: openingCash,
    );
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    final preview = _preview;
    if (preview == null) {
      setState(() => _error = 'Recalcula el corte antes de guardar.');
      return;
    }
    if (!preview.hasMovements && !_confirmNoMovements) {
      setState(
        () => _error = 'Confirma que deseas guardar un corte sin movimientos.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveHistoricalCashCorrection(
        branch: branch,
        businessDate: _businessDateText,
        countedCashAmount: cash!,
        terminalReportedAmount: terminal!,
        notes: _notesController.text,
        adminPin: pin,
        openingCashAmount: openingCash,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error, stackTrace) {
      debugPrint(
        '[TacoPOS][HistoricalCashCorrection.save] $error\n$stackTrace',
      );
      if (!mounted) return;
      setState(
        () => _error =
            'No se pudo recalcular el corte. Intenta nuevamente o revisa la conexión.',
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String? _validationError({
    required Branch branch,
    required double? countedCash,
    required double? terminalReported,
    required String pin,
    required double? openingCash,
  }) {
    if (branch.id.trim().isEmpty) return 'Selecciona una sucursal.';
    if (_businessDate.isAfter(DateTime.now())) {
      return 'No se puede usar una fecha futura.';
    }
    if (countedCash == null || countedCash < 0) {
      return 'Captura efectivo contado valido.';
    }
    if (terminalReported == null || terminalReported < 0) {
      return 'Captura terminal reportada valida.';
    }
    if (_openingCashController.text.trim().isNotEmpty && openingCash == null) {
      return 'Captura fondo inicial valido.';
    }
    if (openingCash != null && openingCash < 0) {
      return 'Captura fondo inicial valido.';
    }
    if (pin.isEmpty) return 'Captura PIN de administrador.';
    if (pin != '072026') return 'PIN de administrador incorrecto.';
    return null;
  }

  double? _amount(String value) {
    final clean = value.replaceAll(RegExp(r'[\$, ]'), '').trim();
    if (clean.isEmpty) return null;
    return double.tryParse(clean);
  }

  double? _optionalAmount(String value) {
    final clean = value.replaceAll(RegExp(r'[\$, ]'), '').trim();
    if (clean.isEmpty) return null;
    return double.tryParse(clean);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 780),
        child: GlassPanel(
          borderRadius: 18,
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<List<Branch>>(
            future: _branchesFuture,
            builder: (context, snapshot) {
              final branches = snapshot.data ?? const <Branch>[];
              final effectiveBranches = branches.isEmpty
                  ? const [Branch.defaultBranch]
                  : branches;
              final selectedBranch = effectiveBranches.firstWhere(
                (branch) => branch.id == _branchId,
                orElse: () => effectiveBranches.first,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: SectionHeader(
                          title: 'Rehacer corte histórico',
                          subtitle:
                              'Recalcula una fecha pasada con ventas y pagos registrados.',
                        ),
                      ),
                      IconButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _CorrectionWarning(
                            text:
                                'Esta accion recalculara el corte con las ventas y pagos registrados para la fecha seleccionada. Usala solo para corregir cortes mal capturados.',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: 230,
                                child: DropdownButtonFormField<String>(
                                  initialValue: selectedBranch.id,
                                  decoration: const InputDecoration(
                                    labelText: 'Sucursal',
                                  ),
                                  items: effectiveBranches
                                      .map(
                                        (branch) => DropdownMenuItem(
                                          value: branch.id,
                                          child: Text(branch.name),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _saving
                                      ? null
                                      : (value) {
                                          if (value == null) return;
                                          setState(() {
                                            _branchId = value;
                                            _preview = null;
                                            _confirmNoMovements = false;
                                          });
                                        },
                                ),
                              ),
                              SizedBox(
                                width: 210,
                                child: OutlinedButton.icon(
                                  onPressed: _saving ? null : _pickDate,
                                  icon: const Icon(Icons.event_outlined),
                                  label: Text(
                                    'Fecha operativa $_businessDateText',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 160,
                                child: TextField(
                                  controller: _openingCashController,
                                  enabled: !_saving,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Fondo inicial',
                                    prefixText: r'$',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 160,
                                child: TextField(
                                  controller: _cashController,
                                  enabled: !_saving,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Efectivo contado',
                                    prefixText: r'$',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 170,
                                child: TextField(
                                  controller: _terminalController,
                                  enabled: !_saving,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Terminal reportada',
                                    prefixText: r'$',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 160,
                                child: TextField(
                                  controller: _pinController,
                                  enabled: !_saving,
                                  obscureText: true,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'PIN admin',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _notesController,
                            enabled: !_saving,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Notas',
                              hintText: 'Motivo de la correccion',
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_error != null) ...[
                            _CorrectionError(text: _error!),
                            const SizedBox(height: 12),
                          ],
                          FilledButton.icon(
                            onPressed: (_loading || _saving)
                                ? null
                                : () => _previewCorrection(selectedBranch),
                            icon: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.calculate_outlined),
                            label: Text(
                              _loading ? 'Recalculando...' : 'Recalcular corte',
                            ),
                          ),
                          if (_preview != null) ...[
                            const SizedBox(height: 12),
                            _HistoricalCorrectionPreviewPanel(
                              preview: _preview!,
                              confirmNoMovements: _confirmNoMovements,
                              onConfirmNoMovementsChanged: (value) {
                                setState(
                                  () => _confirmNoMovements = value ?? false,
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: (_preview == null || _saving)
                              ? null
                              : () => _save(selectedBranch),
                          icon: const Icon(Icons.save_outlined),
                          label: Text(
                            _saving
                                ? 'Guardando...'
                                : 'Confirmar y guardar corte histórico',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CashSessionDetailCard extends StatelessWidget {
  const _CashSessionDetailCard({required this.session});

  final CashSession session;

  @override
  Widget build(BuildContext context) {
    final statusColor = session.isOpen
        ? BrandColors.success
        : BrandColors.textMuted;
    final cashSalesAmount =
        session.expectedCashAmount -
        session.openingCashAmount +
        session.approvedWithdrawalsTotal;
    final cashUserSalesAmount =
        session.countedCashAmount - session.openingCashAmount;
    final cashSalesExpectedAfterWithdrawals =
        cashSalesAmount - session.approvedWithdrawalsTotal;
    final cashDifference =
        cashUserSalesAmount - cashSalesExpectedAfterWithdrawals;
    final cardDifference =
        session.terminalReportedAmount - session.expectedCardChargedAmount;
    final netDifference = cashDifference + cardDifference;
    final netSalesAmount =
        cashSalesAmount +
        session.expectedCardChargedAmount +
        session.expectedPlatformAmount +
        session.expectedEmployeeConsumptionAmount;
    final cardCommission = _cardCommission(session.expectedCardChargedAmount);
    final estimatedCardNet = session.expectedCardChargedAmount - cardCommission;
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Fecha operativa ${session.businessDate}',
            subtitle:
                '${session.isOpen ? 'Abierta' : 'Cerrada'} | abre ${_employeeName(session.openedByEmployeeName)} | cierra ${_employeeName(session.closedByEmployeeName)}',
            trailing: Icon(Icons.point_of_sale_outlined, color: statusColor),
          ),
          const SizedBox(height: 10),
          _CashSection(
            title: 'Resumen de venta',
            icon: Icons.payments_outlined,
            accent: BrandColors.accentYellow,
            child: _MetricWrap(
              children: [
                _CashMetricCard(
                  label: 'Venta total neta',
                  value: netSalesAmount,
                  accent: BrandColors.accentYellow,
                  prominent: true,
                ),
                _CashMetricCard(
                  label: 'Efectivo',
                  value: cashSalesAmount,
                  accent: BrandColors.success,
                ),
                _CashMetricCard(
                  label: 'Tarjeta cobrada',
                  value: session.expectedCardChargedAmount,
                  accent: BrandColors.info,
                ),
                _CashMetricCard(
                  label: 'Comision por pagar tarjeta',
                  value: cardCommission,
                  accent: BrandColors.accentOrange,
                ),
                _CashMetricCard(
                  label: 'Plataforma',
                  value: session.expectedPlatformAmount,
                  accent: const Color(0xFFBCA7FF),
                ),
                _CashMetricCard(
                  label: 'Consumo empleado',
                  value: session.expectedEmployeeConsumptionAmount,
                  accent: BrandColors.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 860;
              final sections = [
                _CashSection(
                  title: 'Efectivo / Arqueo',
                  icon: Icons.account_balance_wallet_outlined,
                  accent: BrandColors.success,
                  child: _AmountGroups(
                    groups: [
                      _AmountGroupData(
                        title: 'Entradas',
                        accent: BrandColors.success,
                        lines: [
                          _AmountLineData(
                            label: 'Fondo inicial',
                            value: session.openingCashAmount,
                            color: BrandColors.textSecondary,
                          ),
                          _AmountLineData(
                            label: 'Efectivo cobrado por ventas',
                            value: cashSalesAmount,
                            color: BrandColors.success,
                            strong: true,
                          ),
                        ],
                      ),
                      _AmountGroupData(
                        title: 'Salidas autorizadas',
                        accent: const Color(0xFFBCA7FF),
                        lines: [
                          _AmountLineData(
                            label: 'Retiros aprobados',
                            value: session.approvedWithdrawalsTotal,
                            color: const Color(0xFFBCA7FF),
                            strong: true,
                          ),
                        ],
                      ),
                      _AmountGroupData(
                        title: 'Esperado en caja',
                        accent: BrandColors.info,
                        lines: [
                          _AmountLineData(
                            label: 'Total efectivo esperado',
                            value: session.expectedCashAmount,
                            color: BrandColors.info,
                            strong: true,
                          ),
                        ],
                      ),
                      _AmountGroupData(
                        title: 'Capturado por usuario',
                        accent: BrandColors.textPrimary,
                        lines: [
                          _AmountLineData(
                            label: 'Efectivo contado usuario',
                            value: session.countedCashAmount,
                            color: BrandColors.textPrimary,
                            strong: true,
                          ),
                          _AmountLineData(
                            label: 'Menos fondo inicial',
                            value: -session.openingCashAmount,
                            color: BrandColors.textSecondary,
                          ),
                          _AmountLineData(
                            label: 'Efectivo usuario venta',
                            value: cashUserSalesAmount,
                            color: BrandColors.info,
                            strong: true,
                          ),
                        ],
                      ),
                      _AmountGroupData(
                        title: 'Comparacion de venta',
                        accent: _differenceColor(cashDifference),
                        lines: [
                          _AmountLineData(
                            label: 'Efectivo venta',
                            value: cashSalesAmount,
                            color: BrandColors.success,
                          ),
                          _AmountLineData(
                            label: 'Menos retiros aprobados',
                            value: -session.approvedWithdrawalsTotal,
                            color: const Color(0xFFBCA7FF),
                          ),
                          _AmountLineData(
                            label: 'Efectivo venta esperado',
                            value: cashSalesExpectedAfterWithdrawals,
                            color: BrandColors.info,
                            strong: true,
                          ),
                          _AmountLineData(
                            label: 'Efectivo usuario venta',
                            value: cashUserSalesAmount,
                            color: BrandColors.textPrimary,
                            strong: true,
                          ),
                          _AmountLineData(
                            label: 'Diferencia efectivo',
                            value: cashDifference,
                            color: _differenceColor(cashDifference),
                            strong: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _CashSection(
                  title: 'Tarjeta / Terminal',
                  icon: Icons.credit_card_outlined,
                  accent: BrandColors.info,
                  child: _AmountGroups(
                    groups: [
                      _AmountGroupData(
                        title: 'Venta con tarjeta',
                        accent: BrandColors.info,
                        lines: [
                          _AmountLineData(
                            label: 'Tarjeta cobrada por ventas',
                            value: session.expectedCardChargedAmount,
                            color: BrandColors.info,
                            strong: true,
                          ),
                        ],
                      ),
                      _AmountGroupData(
                        title: 'Reportado por terminal',
                        accent: BrandColors.textPrimary,
                        lines: [
                          _AmountLineData(
                            label: 'Terminal reportada',
                            value: session.terminalReportedAmount,
                            color: BrandColors.textPrimary,
                            strong: true,
                          ),
                        ],
                      ),
                      _AmountGroupData(
                        title: 'Diferencia',
                        accent: _differenceColor(cardDifference),
                        lines: [
                          _AmountLineData(
                            label: 'Diferencia tarjeta',
                            value: cardDifference,
                            color: _differenceColor(cardDifference),
                            strong: true,
                          ),
                        ],
                      ),
                      _AmountGroupData(
                        title: 'Comision',
                        accent: BrandColors.accentOrange,
                        lines: [
                          _AmountLineData(
                            label: 'Comision por pagar tarjeta',
                            value: cardCommission,
                            color: BrandColors.accentOrange,
                            strong: true,
                          ),
                          _AmountLineData(
                            label: 'Neto estimado tarjeta',
                            value: estimatedCardNet,
                            color: BrandColors.textSecondary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ];
              if (!wide) {
                return Column(
                  children: [
                    sections.first,
                    const SizedBox(height: 12),
                    sections.last,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: sections.first),
                  const SizedBox(width: 12),
                  Expanded(child: sections.last),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final withdrawals = _CashSection(
                title: 'Retiros',
                icon: Icons.request_quote_outlined,
                accent: const Color(0xFFBCA7FF),
                child: _AmountLines(
                  lines: [
                    _AmountLineData(
                      label: 'Retiros aprobados',
                      value: session.approvedWithdrawalsTotal,
                      color: const Color(0xFFBCA7FF),
                      strong: true,
                    ),
                    _AmountLineData(
                      label: 'Retiros pendientes',
                      value: session.pendingWithdrawalsTotal,
                      color: BrandColors.accentOrange,
                    ),
                  ],
                ),
              );
              final result = _CashSection(
                title: 'Resultado final',
                icon: Icons.summarize_outlined,
                accent: _differenceColor(netDifference),
                child: _AmountLines(
                  lines: [
                    _AmountLineData(
                      label: cashDifference < 0
                          ? 'Faltante efectivo'
                          : cashDifference > 0
                          ? 'Sobrante efectivo'
                          : 'Efectivo cuadrado',
                      value: cashDifference.abs(),
                      color: _differenceColor(cashDifference),
                      strong: true,
                    ),
                    _AmountLineData(
                      label: cardDifference < 0
                          ? 'Faltante tarjeta'
                          : cardDifference > 0
                          ? 'Sobrante tarjeta'
                          : 'Tarjeta cuadrada',
                      value: cardDifference.abs(),
                      color: _differenceColor(cardDifference),
                      strong: true,
                    ),
                    _AmountLineData(
                      label: 'Diferencia neta',
                      value: netDifference,
                      color: _differenceColor(netDifference),
                      strong: true,
                    ),
                  ],
                ),
              );
              if (!wide) {
                return Column(
                  children: [withdrawals, const SizedBox(height: 12), result],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: withdrawals),
                  const SizedBox(width: 12),
                  Expanded(child: result),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _CashSection(
            title: 'Detalles del corte',
            icon: Icons.info_outline,
            accent: BrandColors.textSecondary,
            child: Column(
              children: [
                _InfoLine(
                  label: 'Usuario que abrio',
                  value: session.openedByEmployeeName,
                ),
                _InfoLine(
                  label: 'Usuario que cerro',
                  value: session.closedByEmployeeName ?? 'Sin cierre',
                ),
                _InfoLine(
                  label: 'Fecha operativa',
                  value: session.businessDate,
                ),
                _InfoLine(
                  label: 'Notas',
                  value: session.notes.isEmpty ? 'Sin notas' : session.notes,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _CashCancellationSummary(session: session),
        ],
      ),
    );
  }

  String _employeeName(String? name) {
    return name == null || name.isEmpty ? 'Empleado' : name;
  }

  double _cardCommission(double cardTotal) {
    return cardTotal * 0.035 * 1.16;
  }

  Color _differenceColor(double value) {
    if (value < 0) {
      return BrandColors.danger;
    }
    if (value > 0) {
      return BrandColors.success;
    }
    return BrandColors.textSecondary;
  }
}

class _CashSection extends StatelessWidget {
  const _CashSection({
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BrandColors.surfaceHigh.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withValues(alpha: 0.24)),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _MetricWrap extends StatelessWidget {
  const _MetricWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemWidth = width >= 980
            ? (width - 30) / 4
            : width >= 680
            ? (width - 20) / 3
            : width >= 440
            ? (width - 10) / 2
            : width;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }
}

class _CashMetricCard extends StatelessWidget {
  const _CashMetricCard({
    required this.label,
    required this.value,
    required this.accent,
    this.prominent = false,
  });

  final String label;
  final double value;
  final Color accent;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(prominent ? 14 : 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: prominent ? 0.13 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BrandColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          MoneyText(
            value: value,
            style: TextStyle(
              color: accent,
              fontSize: prominent ? 23 : 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountLines extends StatelessWidget {
  const _AmountLines({required this.lines});

  final List<_AmountLineData> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: lines
          .map(
            (line) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      line.label,
                      style: TextStyle(
                        color: line.strong
                            ? BrandColors.textPrimary
                            : BrandColors.textMuted,
                        fontWeight: line.strong
                            ? FontWeight.w800
                            : FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  MoneyText(
                    value: line.value,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: line.color,
                      fontSize: line.strong ? 16 : 14,
                      fontWeight: line.strong
                          ? FontWeight.w900
                          : FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _AmountGroups extends StatelessWidget {
  const _AmountGroups({required this.groups});

  final List<_AmountGroupData> groups;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: groups
          .map(
            (group) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
                decoration: BoxDecoration(
                  color: group.accent.withValues(alpha: 0.055),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: group.accent.withValues(alpha: 0.16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.title.toUpperCase(),
                      style: TextStyle(
                        color: group.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _AmountLines(lines: group.lines),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _AmountGroupData {
  const _AmountGroupData({
    required this.title,
    required this.accent,
    required this.lines,
  });

  final String title;
  final Color accent;
  final List<_AmountLineData> lines;
}

class _AmountLineData {
  const _AmountLineData({
    required this.label,
    required this.value,
    required this.color,
    this.strong = false,
  });

  final String label;
  final double value;
  final Color color;
  final bool strong;
}

class _HistoricalCorrectionPreviewPanel extends StatelessWidget {
  const _HistoricalCorrectionPreviewPanel({
    required this.preview,
    required this.confirmNoMovements,
    required this.onConfirmNoMovementsChanged,
  });

  final HistoricalCashCorrectionPreview preview;
  final bool confirmNoMovements;
  final ValueChanged<bool?> onConfirmNoMovementsChanged;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      borderColor: BrandColors.accentYellow.withValues(alpha: 0.34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (preview.hasExistingSession) ...[
            const _CorrectionWarning(
              text:
                  'Ya existe un corte para esta fecha. Se guardara como correccion administrativa.',
            ),
            const SizedBox(height: 10),
          ],
          if (preview.openingCashAmount == 0 &&
              !preview.hasExistingSession) ...[
            const _CorrectionWarning(
              text:
                  r'No existe corte previo para tomar fondo inicial. Se usara fondo inicial $0.00.',
            ),
            const SizedBox(height: 10),
          ],
          const Text(
            'Resumen antes de guardar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _CorrectionSummaryBox(
                title: 'Venta',
                accent: BrandColors.accentYellow,
                lines: [
                  _CorrectionLineData('Fecha operativa', preview.businessDate),
                  _CorrectionLineData('Sucursal', preview.branch.name),
                  _CorrectionLineData.money(
                    'Venta total',
                    preview.cashSalesAmount +
                        preview.cardSalesAmount +
                        preview.platformAmount +
                        preview.employeeConsumptionAmount,
                  ),
                  _CorrectionLineData.money(
                    'Efectivo ventas',
                    preview.cashSalesAmount,
                  ),
                  _CorrectionLineData.money(
                    'Tarjeta ventas',
                    preview.cardSalesAmount,
                  ),
                  _CorrectionLineData.money(
                    'Plataforma',
                    preview.platformAmount,
                  ),
                  _CorrectionLineData.money(
                    'Consumo empleado',
                    preview.employeeConsumptionAmount,
                  ),
                ],
              ),
              _CorrectionSummaryBox(
                title: 'Efectivo',
                accent: BrandColors.success,
                lines: [
                  _CorrectionLineData.money(
                    'Fondo inicial',
                    preview.openingCashAmount,
                  ),
                  _CorrectionLineData.money(
                    'Retiros aprobados',
                    preview.approvedWithdrawalsTotal,
                  ),
                  _CorrectionLineData.money(
                    'Total efectivo esperado',
                    preview.expectedCashAmount,
                  ),
                  _CorrectionLineData.money(
                    'Efectivo contado',
                    preview.countedCashAmount,
                  ),
                  _CorrectionLineData.money(
                    'Efectivo usuario venta',
                    preview.cashUserSalesAmount,
                  ),
                  _CorrectionLineData.money(
                    'Efectivo venta esperado',
                    preview.cashSalesExpectedAfterWithdrawals,
                  ),
                  _CorrectionLineData.money(
                    'Diferencia efectivo',
                    preview.cashDifference,
                    difference: true,
                  ),
                ],
              ),
              _CorrectionSummaryBox(
                title: 'Tarjeta',
                accent: BrandColors.info,
                lines: [
                  _CorrectionLineData.money(
                    'Tarjeta ventas',
                    preview.cardSalesAmount,
                  ),
                  _CorrectionLineData.money(
                    'Terminal reportada',
                    preview.terminalReportedAmount,
                  ),
                  _CorrectionLineData.money(
                    'Diferencia tarjeta',
                    preview.cardDifference,
                    difference: true,
                  ),
                  _CorrectionLineData.money(
                    'Comision tarjeta',
                    preview.cardCommissionAmount,
                  ),
                  _CorrectionLineData.money(
                    'Neto estimado tarjeta',
                    preview.cardSalesAmount - preview.cardCommissionAmount,
                  ),
                ],
              ),
              _CorrectionSummaryBox(
                title: 'Resultado',
                accent: preview.netDifference < 0
                    ? BrandColors.danger
                    : BrandColors.success,
                lines: [
                  _CorrectionLineData.money(
                    'Retiros pendientes',
                    preview.pendingWithdrawalsTotal,
                  ),
                  _CorrectionLineData.money('Faltante', preview.shortageAmount),
                  _CorrectionLineData.money('Sobrante', preview.overAmount),
                  _CorrectionLineData.money(
                    'Diferencia neta',
                    preview.netDifference,
                    difference: true,
                  ),
                ],
              ),
            ],
          ),
          if (!preview.hasMovements) ...[
            const SizedBox(height: 10),
            CheckboxListTile(
              value: confirmNoMovements,
              onChanged: onConfirmNoMovementsChanged,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Confirmo guardar este corte aunque no hay ventas ni movimientos.',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CorrectionSummaryBox extends StatelessWidget {
  const _CorrectionSummaryBox({
    required this.title,
    required this.accent,
    required this.lines,
  });

  final String title;
  final Color accent;
  final List<_CorrectionLineData> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 330,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          ...lines.map((line) => _CorrectionLine(line: line)),
        ],
      ),
    );
  }
}

class _CorrectionLine extends StatelessWidget {
  const _CorrectionLine({required this.line});

  final _CorrectionLineData line;

  @override
  Widget build(BuildContext context) {
    final color = line.difference
        ? _correctionDifferenceColor(line.amount ?? 0)
        : BrandColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              line.label,
              style: const TextStyle(
                color: BrandColors.textMuted,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            line.value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _CorrectionLineData {
  const _CorrectionLineData(this.label, this.value)
    : amount = null,
      difference = false;

  _CorrectionLineData.money(
    this.label,
    double amountValue, {
    this.difference = false,
  }) : amount = amountValue,
       value = _historicalMoney(amountValue);

  final String label;
  final String value;
  final double? amount;
  final bool difference;
}

class _CorrectionWarning extends StatelessWidget {
  const _CorrectionWarning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BrandColors.accentOrange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: BrandColors.accentOrange.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_outlined,
            color: BrandColors.accentOrange,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: BrandColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CorrectionError extends StatelessWidget {
  const _CorrectionError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BrandColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BrandColors.danger.withValues(alpha: 0.30)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: BrandColors.danger,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _historicalMoney(double value) {
  return NumberFormat.currency(
    locale: 'es_MX',
    symbol: r'$',
    decimalDigits: 2,
  ).format(value);
}

Color _correctionDifferenceColor(double value) {
  if (value < 0) return BrandColors.danger;
  if (value > 0) return BrandColors.success;
  return BrandColors.textSecondary;
}

class _CashCancellationSummary extends StatelessWidget {
  const _CashCancellationSummary({required this.session});

  final CashSession session;

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();
    return StreamBuilder<List<PosOrder>>(
      stream: repository.watchAllOrders(),
      builder: (context, orderSnapshot) {
        final orders = (orderSnapshot.data ?? const <PosOrder>[])
            .where(
              (order) =>
                  order.status == 'cancelled' &&
                  _businessDate(order.cancelledAt ?? order.updatedAt) ==
                      session.businessDate,
            )
            .toList();
        return FutureBuilder<List<Payment>>(
          future: repository.getPaymentsForBranchBusinessDate(
            branch: Branch(
              id: session.branchId,
              restaurantId: session.restaurantId,
              restaurantName: session.restaurantName,
              name: session.branchName,
              normalizedName: session.branchId,
              active: true,
              sortOrder: 0,
            ),
            businessDate: session.businessDate,
            activeOnly: false,
          ),
          builder: (context, paymentSnapshot) {
            final payments = (paymentSnapshot.data ?? const <Payment>[])
                .where((payment) => payment.isCancelled)
                .toList();
            final cancelledTotal = orders.fold<double>(
              0,
              (total, order) => total + order.total,
            );
            final cancelledPaymentsTotal = payments.fold<double>(
              0,
              (total, payment) => total + payment.chargedAmount,
            );

            return FutureBuilder<List<_CancelledItemLine>>(
              future: _cancelledItemLines(repository, orderSnapshot.data ?? []),
              builder: (context, itemSnapshot) {
                final itemLines = itemSnapshot.data ?? const [];
                final itemTotal = itemLines.fold<double>(
                  0,
                  (total, line) => total + line.amount,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cancelaciones del dia',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _MoneyChip(
                          label: '${orders.length} tickets cancelados',
                          value: cancelledTotal,
                        ),
                        _MoneyChip(
                          label: '${itemLines.length} articulos cancelados',
                          value: itemTotal,
                        ),
                        _MoneyChip(
                          label: '${payments.length} pagos cancelados',
                          value: cancelledPaymentsTotal,
                        ),
                      ],
                    ),
                    if (orders.isNotEmpty ||
                        payments.isNotEmpty ||
                        itemLines.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...orders
                          .take(4)
                          .map(
                            (order) => _InfoLine(
                              label:
                                  '${_shortId(order.id)} | ${_time(order.cancelledAt)}',
                              value:
                                  '${order.displayName} | ${order.cancelledByEmployeeName ?? '-'} | ${order.cancelReason ?? '-'}',
                            ),
                          ),
                      ...itemLines
                          .take(6)
                          .map(
                            (line) => _InfoLine(
                              label: '${line.folio} | ${line.time}',
                              value: line.description,
                            ),
                          ),
                      ...payments
                          .take(4)
                          .map(
                            (payment) => _InfoLine(
                              label:
                                  'Pago ${_shortId(payment.id)} | ${_time(payment.cancelledAt)}',
                              value:
                                  '${payment.tableName} | ${payment.cancelledByEmployeeName ?? '-'} | ${payment.cancelReason ?? '-'}',
                            ),
                          ),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  String? _businessDate(DateTime? date) {
    if (date == null) {
      return null;
    }
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _time(DateTime? date) {
    if (date == null) {
      return '--:--';
    }
    return DateFormat('HH:mm').format(date);
  }

  String _shortId(String id) => id.length <= 6 ? id : id.substring(0, 6);

  Future<List<_CancelledItemLine>> _cancelledItemLines(
    TacoPosRepository repository,
    List<PosOrder> orders,
  ) async {
    final lines = <_CancelledItemLine>[];
    for (final order in orders) {
      final items = await repository.getOrderItemsOnce(order.id);
      for (final item in items.where(
        (item) => item.isCancelled || item.wasCancellationRejected,
      )) {
        final date =
            item.cancelledAt ??
            item.cancelRejectedAt ??
            item.cancelRequestedAt ??
            order.updatedAt;
        if (_businessDate(date) != session.businessDate) {
          continue;
        }
        lines.add(
          _CancelledItemLine(
            folio: _shortId(order.id),
            time: _time(date),
            amount: item.isCancelled ? item.total : 0,
            description:
                '${order.displayName} | ${item.productName} x${item.qty} | ${item.isCancelled ? 'Aceptada' : 'Rechazada'} | ${item.cancelReason ?? '-'}',
          ),
        );
      }
    }
    return lines;
  }
}

class _CancelledItemLine {
  const _CancelledItemLine({
    required this.folio,
    required this.time,
    required this.description,
    required this.amount,
  });

  final String folio;
  final String time;
  final String description;
  final double amount;
}

class _WithdrawalAuthorizationTab extends StatelessWidget {
  const _WithdrawalAuthorizationTab({
    required this.startBusinessDate,
    required this.endBusinessDate,
  });

  final String startBusinessDate;
  final String endBusinessDate;

  @override
  Widget build(BuildContext context) {
    final repository = TacoPosRepository();
    final canAuthorize =
        AppSession.instance.employee?.canAuthorizeCashWithdrawals == true;

    return StreamBuilder<List<CashWithdrawalRequest>>(
      stream: repository.watchCashWithdrawalRequests(
        startBusinessDate: startBusinessDate,
        endBusinessDate: endBusinessDate,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudieron cargar retiros',
            message: '${snapshot.error}',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPanel(message: 'Cargando retiros...');
        }

        final requests = snapshot.data ?? [];
        final pending = requests.where((request) => request.isPending).toList();
        final attended = requests.where((request) => !request.isPending);

        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const SectionHeader(
              title: 'Autorizacion de retiros',
              subtitle: 'Aprueba o rechaza gastos eventuales.',
            ),
            const SizedBox(height: 18),
            if (!canAuthorize)
              const GlassPanel(
                borderColor: BrandColors.danger,
                child: Text(
                  'No tienes permiso para autorizar retiros.',
                  style: TextStyle(
                    color: BrandColors.danger,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else if (pending.isEmpty)
              const GlassPanel(
                child: Text(
                  'Sin solicitudes pendientes.',
                  style: TextStyle(color: BrandColors.textMuted),
                ),
              )
            else
              ...pending.map(
                (request) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _WithdrawalAdminCard(
                    request: request,
                    repository: repository,
                    canAuthorize: canAuthorize,
                  ),
                ),
              ),
            const SizedBox(height: 18),
            const SectionHeader(
              title: 'Historial',
              subtitle: 'Solicitudes atendidas recientemente.',
            ),
            const SizedBox(height: 12),
            if (attended.isEmpty)
              const GlassPanel(
                child: Text(
                  'Aun no hay retiros atendidos.',
                  style: TextStyle(color: BrandColors.textMuted),
                ),
              )
            else
              ...attended
                  .take(20)
                  .map(
                    (request) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _WithdrawalAdminCard(
                        request: request,
                        repository: repository,
                        canAuthorize: false,
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }
}

class _WithdrawalAdminCard extends StatelessWidget {
  const _WithdrawalAdminCard({
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

    return GlassPanel(
      borderColor: request.isPending ? BrandColors.accentYellow : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.request_quote_outlined, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  request.reason,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
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
          _InfoLine(label: 'Estado', value: _statusText(request)),
          _InfoLine(
            label: 'Solicitado por',
            value: request.requestedByEmployeeName,
          ),
          _InfoLine(label: 'Fecha operativa', value: request.businessDate),
          _InfoLine(
            label: 'Solicitado',
            value: _formatDate(request.requestedAt),
          ),
          if (!request.isPending) ...[
            _InfoLine(
              label: request.isApproved ? 'Autorizado por' : 'Rechazado por',
              value: request.authorizedByEmployeeName ?? '',
            ),
            _InfoLine(
              label: 'Atendido',
              value: _formatDate(request.authorizedAt),
            ),
            _InfoLine(
              label: 'Notas admin',
              value: request.adminNotes?.isEmpty == false
                  ? request.adminNotes!
                  : 'Sin notas',
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
                  label: const Text('Aprobar'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _resolve(BuildContext context, {required bool approved}) async {
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approved ? 'Aprobar retiro' : 'Rechazar retiro'),
        content: TextField(
          controller: notesController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Notas admin'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approved ? 'Aprobar' : 'Rechazar'),
          ),
        ],
      ),
    );

    if (!context.mounted) {
      notesController.dispose();
      return;
    }
    if (confirmed != true) {
      notesController.dispose();
      return;
    }

    try {
      await repository.authorizeCashWithdrawal(
        requestId: request.id,
        approved: approved,
        adminNotes: notesController.text,
      );
      notesController.dispose();
      if (!context.mounted) {
        return;
      }
      showAppSnackBar(
        context,
        approved ? 'Retiro aprobado.' : 'Retiro rechazado.',
        type: AppSnackBarType.success,
      );
    } catch (error) {
      notesController.dispose();
      if (!context.mounted) {
        return;
      }
      showAppSnackBar(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
        type: AppSnackBarType.error,
      );
    }
  }

  String _statusText(CashWithdrawalRequest request) {
    if (request.isApproved) {
      return 'Aprobado';
    }
    if (request.isRejected) {
      return 'Rechazado';
    }
    return 'Pendiente';
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return 'Sin fecha';
    }
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }
}

class _MoneyChip extends StatelessWidget {
  const _MoneyChip({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final color = value < 0 ? BrandColors.danger : BrandColors.accentYellow;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        accent: color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: BrandColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            MoneyText(
              value: value,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
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
              value.isEmpty ? 'Sin dato' : value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
