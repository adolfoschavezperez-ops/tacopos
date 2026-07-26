import 'package:flutter/material.dart';

import '../../core/cash/cash_close_execution.dart';
import '../../core/theme/brand_colors.dart';
import '../../models/cash_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/cash_close_progress_dialog.dart';
import '../../widgets/glass.dart';

class CloseCashSessionScreen extends StatefulWidget {
  const CloseCashSessionScreen({super.key, required this.session});

  final CashSession session;

  @override
  State<CloseCashSessionScreen> createState() => _CloseCashSessionScreenState();
}

class _CloseCashSessionScreenState extends State<CloseCashSessionScreen> {
  final _repository = TacoPosRepository();
  final _countedCashController = TextEditingController();
  final _terminalController = TextEditingController();
  final _notesController = TextEditingController();
  final _countedCashFocusNode = FocusNode();
  final _terminalFocusNode = FocusNode();
  final _notesFocusNode = FocusNode();
  final _closeGuard = CashCloseExecutionGuard();
  final _progressStage = ValueNotifier(CashCloseProgressStage.validating);
  BuildContext? _progressDialogContext;
  Future<void>? _progressDialogFuture;

  bool get _isClosingCash => _closeGuard.isActive;

  @override
  void dispose() {
    _countedCashFocusNode.dispose();
    _terminalFocusNode.dispose();
    _notesFocusNode.dispose();
    _countedCashController.dispose();
    _terminalController.dispose();
    _notesController.dispose();
    _progressStage.dispose();
    super.dispose();
  }

  double _amount(TextEditingController controller) {
    return double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;
  }

  Future<void> _confirmClose() async {
    if (!_closeGuard.tryStart()) {
      return;
    }

    setState(() {});

    try {
      final countedCash = _amount(_countedCashController);
      final terminalReported = _amount(_terminalController);
      await _showProgressDialog(CashCloseProgressStage.validating);

      final blockers = await _repository.cashCloseBlockers(widget.session.id);
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

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cerrar caja'),
          content: const Text(
            'Se guardara el conteo fisico y el sistema calculara el corte.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Cerrar caja'),
            ),
          ],
        ),
      );

      if (!mounted || confirmed != true) {
        return;
      }

      _closeGuard.markSaving();
      setState(() {});
      await _showProgressDialog(CashCloseProgressStage.saving);
      final result = await _repository.closeCashSession(
        cashSessionId: widget.session.id,
        countedCashAmount: countedCash,
        terminalReportedAmount: terminalReported,
        notes: _notesController.text,
      );
      await _dismissProgressDialog();
      if (!mounted) {
        return;
      }
      Navigator.pop(context, result);
    } catch (error, stackTrace) {
      await _dismissProgressDialog();
      debugPrint(
        'Error al cerrar caja ${widget.session.id}: $error\n$stackTrace',
      );
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        _closeErrorText(error),
        type: AppSnackBarType.error,
      );
    } finally {
      await _dismissProgressDialog();
      _closeGuard.release();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _showProgressDialog(CashCloseProgressStage stage) async {
    if (!mounted || _progressDialogFuture != null) {
      return;
    }
    _progressStage.value = stage;
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

  String _closeErrorText(Object error) {
    if (error is StateError || error is ArgumentError) {
      return _errorText(error);
    }
    return 'No se pudo grabar el corte. Revisa tu conexión e inténtalo nuevamente.';
  }

  String _errorText(Object error) {
    return error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Invalid argument(s): ', '');
  }

  @override
  Widget build(BuildContext context) {
    return BrandedScaffold(
      title: 'Cerrar caja',
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          SectionHeader(
            title: 'Cierre ${widget.session.businessDate}',
            subtitle: 'Captura el conteo fisico para cerrar caja.',
          ),
          const SizedBox(height: 18),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Conteo fisico',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _countedCashController,
                  focusNode: _countedCashFocusNode,
                  enabled: !_isClosingCash,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Efectivo contado',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _terminalController,
                  focusNode: _terminalFocusNode,
                  enabled: !_isClosingCash,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Total terminal bancaria',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  focusNode: _notesFocusNode,
                  enabled: !_isClosingCash,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notas opcionales',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const GlassPanel(
            child: Text(
              'La terminal debe capturarse con lo cobrado al cliente. La comision de tarjeta absorbida se guarda solo como dato administrativo.',
              style: TextStyle(
                color: BrandColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: GlassButton(
              icon: Icons.check_circle_outline,
              label: _closeGuard.stage?.buttonLabel ?? 'Grabar corte',
              prominent: true,
              loading: _isClosingCash,
              onTap: _isClosingCash ? null : _confirmClose,
            ),
          ),
        ],
      ),
    );
  }
}
