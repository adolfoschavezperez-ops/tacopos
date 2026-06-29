import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/cash_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
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
  bool _closing = false;

  @override
  void dispose() {
    _countedCashFocusNode.dispose();
    _terminalFocusNode.dispose();
    _notesFocusNode.dispose();
    _countedCashController.dispose();
    _terminalController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double _amount(TextEditingController controller) {
    return double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;
  }

  Future<void> _confirmClose() async {
    if (_closing) {
      return;
    }

    final countedCash = _amount(_countedCashController);
    final terminalReported = _amount(_terminalController);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar caja'),
        content: const Text(
          'Se guardara el conteo fisico y el sistema calculara el corte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar caja'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _closing = true;
    });

    try {
      final result = await _repository.closeCashSession(
        cashSessionId: widget.session.id,
        countedCashAmount: countedCash,
        terminalReportedAmount: terminalReported,
        notes: _notesController.text,
      );
      if (!mounted) {
        return;
      }
      Navigator.pop(context, result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorText(error))));
    } finally {
      if (mounted) {
        setState(() {
          _closing = false;
        });
      }
    }
  }

  String _errorText(Object error) {
    return error.toString().replaceFirst('Bad state: ', '');
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
                  enabled: !_closing,
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
                  enabled: !_closing,
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
                  enabled: !_closing,
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
              'El desglose del sistema se guardara internamente y solo estara disponible para Admin.',
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
              label: _closing ? 'Cerrando...' : 'Confirmar cierre',
              prominent: true,
              onTap: _closing ? null : _confirmClose,
            ),
          ),
        ],
      ),
    );
  }
}
