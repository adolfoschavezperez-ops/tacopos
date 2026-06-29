import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/cash_session.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';

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
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _countedCashController.addListener(_handleAmountChanged);
    _terminalController.addListener(_handleAmountChanged);
  }

  @override
  void dispose() {
    _countedCashController.removeListener(_handleAmountChanged);
    _terminalController.removeListener(_handleAmountChanged);
    _countedCashController.dispose();
    _terminalController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _handleAmountChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  double _amount(TextEditingController controller) {
    return double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;
  }

  Future<void> _confirmClose(CashSessionTotals totals) async {
    if (_closing) {
      return;
    }

    final countedCash = _amount(_countedCashController);
    final terminalReported = _amount(_terminalController);
    final shortage = totals.shortageAmount(
      countedCashAmount: countedCash,
      terminalReportedAmount: terminalReported,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar caja'),
        content: Text(
          shortage > 0
              ? 'Se cerrara caja con faltante de \$${shortage.toStringAsFixed(2)}.'
              : 'Se cerrara caja correctamente.',
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
      body: StreamBuilder<CashSessionTotals>(
        stream: _repository.watchCashSessionTotals(widget.session.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudo cargar el cierre',
              message: '${snapshot.error}',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(message: 'Calculando corte...');
          }

          final totals = snapshot.data ?? const CashSessionTotals();
          final countedCash = _amount(_countedCashController);
          final terminalReported = _amount(_terminalController);
          final cashDifference = totals.cashDifference(countedCash);
          final cardDifference = totals.cardDifference(terminalReported);
          final netDifference = totals.netDifference(
            countedCashAmount: countedCash,
            terminalReportedAmount: terminalReported,
          );
          final shortage = totals.shortageAmount(
            countedCashAmount: countedCash,
            terminalReportedAmount: terminalReported,
          );
          final over = totals.overAmount(
            countedCashAmount: countedCash,
            terminalReportedAmount: terminalReported,
          );

          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              SectionHeader(
                title: 'Cierre ${widget.session.businessDate}',
                subtitle: 'Compara sistema contra efectivo y terminal.',
              ),
              const SizedBox(height: 18),
              GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Resumen del sistema',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _MoneyLine(
                      label: 'Efectivo esperado',
                      value: totals.expectedCashAmount,
                    ),
                    _MoneyLine(
                      label: 'Tarjeta base',
                      value: totals.expectedCardBaseAmount,
                    ),
                    _MoneyLine(
                      label: 'Comision tarjeta',
                      value: totals.expectedCardSurchargeAmount,
                    ),
                    _MoneyLine(
                      label: 'Tarjeta cobrada real',
                      value: totals.expectedCardChargedAmount,
                    ),
                    _MoneyLine(
                      label: 'Pagado en plataforma',
                      value: totals.expectedPlatformAmount,
                    ),
                    _MoneyLine(
                      label: 'Consumo empleado',
                      value: totals.expectedEmployeeConsumptionAmount,
                    ),
                    const Divider(height: 22),
                    _MoneyLine(
                      label: 'Dinero real esperado',
                      value: totals.totalExpectedRealMoney,
                      highlight: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Conteo fisico',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _countedCashController,
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
              GlassPanel(
                borderColor: shortage > 0
                    ? BrandColors.danger
                    : BrandColors.glassBorder,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Diferencias',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _MoneyLine(
                      label: 'Diferencia efectivo',
                      value: cashDifference,
                    ),
                    _MoneyLine(
                      label: 'Diferencia tarjeta',
                      value: cardDifference,
                    ),
                    _MoneyLine(
                      label: 'Diferencia neta',
                      value: netDifference,
                      highlight: true,
                    ),
                    const SizedBox(height: 10),
                    if (shortage > 0)
                      Text(
                        'Faltante de caja: \$${shortage.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: BrandColors.danger,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    else if (over > 0)
                      Text(
                        'Corte realizado correctamente. Sobrante: \$${over.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: BrandColors.success,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    else
                      const Text(
                        'Corte realizado correctamente.',
                        style: TextStyle(
                          color: BrandColors.success,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: GlassButton(
                  icon: Icons.check_circle_outline,
                  label: _closing ? 'Cerrando...' : 'Confirmar cierre',
                  prominent: true,
                  onTap: _closing ? null : () => _confirmClose(totals),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MoneyLine extends StatelessWidget {
  const _MoneyLine({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final double value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = value < 0 ? BrandColors.danger : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: highlight
                    ? BrandColors.textPrimary
                    : BrandColors.textMuted,
                fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          MoneyText(
            value: value,
            style: TextStyle(
              color:
                  color ??
                  (highlight
                      ? BrandColors.accentYellow
                      : BrandColors.textSecondary),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
