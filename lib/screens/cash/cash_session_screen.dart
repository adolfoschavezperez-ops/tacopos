import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/cash_session.dart';
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
                  repository: _repository,
                  onClose: () => _closeCashSession(session),
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
    required this.repository,
    required this.onClose,
  });

  final CashSession session;
  final bool canManageCash;
  final TacoPosRepository repository;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CashSessionTotals>(
      stream: repository.watchCashSessionTotals(session.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudieron cargar totales de caja',
            message: '${snapshot.error}',
          );
        }

        final totals = snapshot.data ?? const CashSessionTotals();
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
                  _MoneyLine(
                    label: 'Efectivo esperado',
                    value: totals.expectedCashAmount,
                  ),
                  _MoneyLine(
                    label: 'Tarjeta cobrada',
                    value: totals.expectedCardChargedAmount,
                  ),
                  _MoneyLine(
                    label: 'Comision tarjeta',
                    value: totals.expectedCardSurchargeAmount,
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
              color: highlight
                  ? BrandColors.accentYellow
                  : BrandColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
