import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../models/employee.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';
import '../../services/app_session.dart';
import '../../services/live_presence_service.dart';
import '../../services/taco_pos_repository.dart';
import '../../utils/app_snackbar.dart';
import '../../utils/formatters.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';
import '../../widgets/status_badge.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _repository = TacoPosRepository();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    LivePresenceService.instance.update(
      appMode: 'cash',
      currentScreen: 'Cobro',
      currentOrderId: widget.orderId,
      currentAction: 'Cobrando',
    );
  }

  Future<bool> _payFullTable(
    PosOrder order, {
    required String method,
    CashPaymentDetails? cashDetails,
    Employee? employee,
  }) async {
    if (!_validateEmployee(method, employee: employee)) {
      return false;
    }

    final resolvedCashDetails =
        cashDetails ??
        await _cashDetailsIfNeeded(method: method, total: order.pendingTotal);
    if (resolvedCashDetails == null && method == 'cash') {
      return false;
    }
    if (method != 'cash') {
      final confirmed = await _confirm(
        title: 'Cobrar mesa completa',
        message: 'Se cubrira todo el pendiente de ${order.displayName}.',
      );
      if (!confirmed) {
        return false;
      }
    }

    if (!mounted) {
      return false;
    }

    return _runPayment(
      () => _repository.payFullTable(
        orderId: widget.orderId,
        method: method,
        employeeId: employee?.id,
        employeeName: employee?.name,
        cashDetails: resolvedCashDetails,
      ),
    );
  }

  Future<bool> _payPeople(
    List<int> personNumbers,
    String personName, {
    required String method,
    required double total,
    CashPaymentDetails? cashDetails,
    Employee? employee,
  }) async {
    if (!_validateEmployee(method, employee: employee)) {
      return false;
    }

    final resolvedCashDetails =
        cashDetails ?? await _cashDetailsIfNeeded(method: method, total: total);
    if (resolvedCashDetails == null && method == 'cash') {
      return false;
    }
    if (method != 'cash') {
      final confirmed = await _confirm(
        title: 'Cobrar $personName',
        message: 'Solo se marcaran pagados los items seleccionados.',
      );
      if (!confirmed) {
        return false;
      }
    }

    if (!mounted) {
      return false;
    }

    return _runPayment(
      () => _repository.payPeople(
        orderId: widget.orderId,
        personNumbers: personNumbers,
        method: method,
        employeeId: employee?.id,
        employeeName: employee?.name,
        cashDetails: resolvedCashDetails,
      ),
    );
  }

  Future<void> _payPlatformOrder(PosOrder order) async {
    final confirmed = await _confirm(
      title: 'Registrar pagado en plataforma',
      message: 'Se cerrara ${order.displayName} como pagado en plataforma.',
    );
    if (!confirmed) {
      return;
    }

    await _runPayment(
      () => _repository.payPlatformOrder(orderId: widget.orderId),
    );
  }

  bool _validateEmployee(String method, {Employee? employee}) {
    if (method == 'employee_consumption' && employee == null) {
      _showMessage('Selecciona un empleado para consumo empleado.');
      return false;
    }
    return true;
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmar cobro'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<CashPaymentDetails?> _cashDetailsIfNeeded({
    required String method,
    required double total,
  }) {
    if (method != 'cash') {
      return Future.value(null);
    }
    return showDialog<CashPaymentDetails>(
      context: context,
      builder: (_) => _CashPaymentDialog(total: total),
    );
  }

  Future<bool> _runPayment(
    Future<PaymentResult> Function() action, {
    VoidCallback? afterSuccess,
  }) async {
    if (_busy) {
      return false;
    }

    setState(() {
      _busy = true;
    });

    try {
      final result = await action();
      if (!mounted) {
        return false;
      }

      afterSuccess?.call();
      _showMessage('Pago registrado.');

      if (result.allPaid) {
        await LivePresenceService.instance.clearCurrentOrder(
          currentAction: 'Viendo mesas',
        );
        if (!mounted) {
          return true;
        }
        Navigator.pop(context);
        Navigator.pop(context);
      }
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      _showMessage(_paymentErrorText(error));
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _cancelPayment(Payment payment) async {
    if (AppSession.instance.employee?.canCancelPayments != true &&
        AppSession.instance.employee?.canViewAdmin != true) {
      _showMessage('No tienes permiso para cancelar pagos.');
      return;
    }
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(title: 'Cancelar pago'),
    );
    if (!mounted || reason == null) {
      return;
    }

    try {
      await _repository.cancelPayment(
        orderId: widget.orderId,
        paymentId: payment.id,
        reason: reason,
      );
      if (!mounted) {
        return;
      }
      _showMessage('Pago cancelado.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('$error'.replaceFirst('Bad state: ', ''));
    }
  }

  void _showMessage(String message) {
    showAppSnackBar(context, message);
  }

  String _paymentErrorText(Object error) {
    final message = error.toString().replaceFirst('Bad state: ', '');
    if (message == 'Debes abrir caja antes de cobrar.') {
      return message;
    }
    return 'No se pudo cobrar: $message';
  }

  Future<void> _openFullTableSheet({
    required PosOrder order,
    required List<Employee> employees,
    required bool hasClientPayment,
    required bool hasPersonPayments,
  }) async {
    if (hasPersonPayments) {
      _showMessage('Esta cuenta ya inicio cobro por persona.');
      return;
    }
    if (order.pendingTotal <= 0.01) {
      _showMessage('No hay saldo pendiente por cobrar.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _PaymentMethodSheet(
        title: 'Cobrar mesa completa',
        subtitle: order.displayName,
        total: order.pendingTotal,
        employees: employees,
        employeeDisabled: hasClientPayment,
        primaryIcon: Icons.point_of_sale_outlined,
        onConfirm: (method, cashDetails, employee) {
          return _payFullTable(
            order,
            method: method,
            cashDetails: cashDetails,
            employee: employee,
          );
        },
      ),
    );
  }

  Future<void> _openPeopleSheet({
    required PosOrder order,
    required List<OrderItem> items,
    required List<Employee> employees,
    required bool hasClientPayment,
    required bool hasPartialPayments,
  }) async {
    if (hasPartialPayments) {
      _showMessage('Esta cuenta ya tiene pagos parciales.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _PeoplePaymentSheet(
        order: order,
        items: items,
        employees: employees,
        employeeDisabled: hasClientPayment,
        personName: _personName,
        pendingForItems: _pendingForItems,
        onConfirm: (people, label, total, method, cashDetails, employee) {
          return _payPeople(
            people,
            label,
            method: method,
            total: total,
            cashDetails: cashDetails,
            employee: employee,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (AppSession.instance.employee?.canCharge != true) {
      return const BrandedScaffold(
        title: 'Cobro',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Sin permiso',
          message: 'No tienes permiso para cobrar.',
        ),
      );
    }

    return BrandedScaffold(
      title: 'Cobro',
      body: StreamBuilder<PosOrder?>(
        stream: _repository.watchOrder(widget.orderId),
        builder: (context, orderSnapshot) {
          if (orderSnapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudo cargar la cuenta',
              message: '${orderSnapshot.error}',
            );
          }

          final order = orderSnapshot.data;
          if (orderSnapshot.connectionState == ConnectionState.waiting ||
              order == null) {
            return const LoadingPanel(message: 'Cargando cuenta...');
          }

          return StreamBuilder<List<OrderItem>>(
            stream: _repository.watchOrderItems(widget.orderId),
            builder: (context, itemSnapshot) {
              if (itemSnapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudieron cargar articulos',
                  message: '${itemSnapshot.error}',
                );
              }

              final items = itemSnapshot.data ?? [];
              return StreamBuilder<List<Employee>>(
                stream: _repository.watchEmployees(),
                builder: (context, employeeSnapshot) {
                  if (employeeSnapshot.hasError) {
                    return EmptyState(
                      icon: Icons.error_outline,
                      title: 'No se pudieron cargar empleados',
                      message: '${employeeSnapshot.error}',
                    );
                  }

                  final employees = employeeSnapshot.data ?? [];
                  return StreamBuilder<List<Payment>>(
                    stream: _repository.watchOrderPayments(widget.orderId),
                    builder: (context, paymentSnapshot) {
                      if (paymentSnapshot.hasError) {
                        return EmptyState(
                          icon: Icons.error_outline,
                          title: 'No se pudieron cargar pagos',
                          message: '${paymentSnapshot.error}',
                        );
                      }

                      final payments = paymentSnapshot.data ?? [];
                      final activePayments = payments
                          .where((payment) => payment.isActive)
                          .toList();
                      final hasPartialPayments = activePayments.any(
                        (payment) => payment.type == 'partial',
                      );
                      final hasPersonPayments = activePayments.any(
                        (payment) => payment.type == 'person',
                      );
                      final hasClientPayment = activePayments.any(
                        (payment) =>
                            payment.method == 'cash' ||
                            payment.method == 'card',
                      );
                      final platformOnlyPayment =
                          order.orderType == 'takeout' &&
                          order.platformId != null &&
                          order.platformId != 'en_persona';

                      if (platformOnlyPayment) {
                        return _PlatformPaymentView(
                          order: order,
                          busy: _busy,
                          onPay: () => _payPlatformOrder(order),
                        );
                      }

                      final people = _people(items);
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final compact =
                              constraints.maxWidth < 650 ||
                              MediaQuery.sizeOf(context).height < 750;
                          final padding = compact ? 12.0 : 22.0;
                          final gap = compact ? 10.0 : 16.0;

                          return ListView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(
                              padding,
                              padding,
                              padding,
                              padding +
                                  MediaQuery.viewInsetsOf(context).bottom +
                                  12,
                            ),
                            children: [
                              _TotalsPanel(order: order, compact: compact),
                              SizedBox(height: gap),
                              _PaymentMainActions(
                                peopleCount: people.length,
                                tableDisabled:
                                    hasPersonPayments ||
                                    order.pendingTotal <= 0.01,
                                personDisabled: hasPartialPayments,
                                onTableSelected: () {
                                  LivePresenceService.instance.update(
                                    currentAction: 'Cobrando mesa completa',
                                  );
                                  _openFullTableSheet(
                                    order: order,
                                    employees: employees,
                                    hasClientPayment: hasClientPayment,
                                    hasPersonPayments: hasPersonPayments,
                                  );
                                },
                                onPersonSelected: () {
                                  LivePresenceService.instance.update(
                                    currentAction: 'Cobrando por persona',
                                  );
                                  _openPeopleSheet(
                                    order: order,
                                    items: items,
                                    employees: employees,
                                    hasClientPayment: hasClientPayment,
                                    hasPartialPayments: hasPartialPayments,
                                  );
                                },
                              ),
                              if (payments.isNotEmpty) ...[
                                SizedBox(height: gap),
                                _PaymentsHistory(
                                  payments: payments,
                                  compact: true,
                                  canCancel:
                                      order.paymentStatus != 'paid' &&
                                      order.status != 'paid' &&
                                      (AppSession
                                                  .instance
                                                  .employee
                                                  ?.canCancelPayments ==
                                              true ||
                                          AppSession
                                                  .instance
                                                  .employee
                                                  ?.canViewAdmin ==
                                              true),
                                  onCancel: _cancelPayment,
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
            },
          );
        },
      ),
    );
  }

  List<int> _people(List<OrderItem> items) {
    final people = items.map((item) => item.personNumber).toSet().toList()
      ..sort();
    return people;
  }

  String _personName(int person, List<OrderItem> items, PosOrder order) {
    final orderName = order.personName(person);
    if (orderName != 'Persona $person') {
      return orderName;
    }

    for (final item in items) {
      final itemName = item.personName.trim();
      if (itemName.isNotEmpty && itemName != 'Persona $person') {
        return itemName;
      }
    }

    return orderName;
  }

  double _pendingForItems(List<OrderItem> items) {
    return items
        .where((item) => item.paymentStatus != 'paid' && !item.isCancelled)
        .fold<double>(0, (runningTotal, item) => runningTotal + item.total);
  }
}

class _PaymentMainActions extends StatelessWidget {
  const _PaymentMainActions({
    required this.peopleCount,
    required this.tableDisabled,
    required this.personDisabled,
    required this.onTableSelected,
    required this.onPersonSelected,
  });

  final int peopleCount;
  final bool tableDisabled;
  final bool personDisabled;
  final VoidCallback onTableSelected;
  final VoidCallback onPersonSelected;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 650;
    final children = [
      Expanded(
        child: _ChargeModeCard(
          title: 'Cobrar mesa completa',
          subtitle: 'Liquida todo el pendiente.',
          icon: Icons.table_restaurant_outlined,
          disabled: tableDisabled,
          onTap: onTableSelected,
        ),
      ),
      SizedBox(width: compact ? 0 : 12, height: compact ? 10 : 0),
      Expanded(
        child: _ChargeModeCard(
          title: 'Cobrar por persona',
          subtitle: '$peopleCount personas con cuenta.',
          icon: Icons.groups_2_outlined,
          disabled: personDisabled,
          onTap: onPersonSelected,
        ),
      ),
    ];

    return GlassPanel(
      padding: EdgeInsets.all(compact ? 14 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Como quieres cobrar?',
            subtitle: 'Elige una opcion para continuar en un panel.',
          ),
          const SizedBox(height: 12),
          compact
              ? Column(children: children)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
        ],
      ),
    );
  }
}

class _ChargeModeCard extends StatelessWidget {
  const _ChargeModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.disabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accent: BrandColors.accentOrange,
      onTap: disabled ? null : onTap,
      padding: const EdgeInsets.all(13),
      child: Opacity(
        opacity: disabled ? 0.48 : 1,
        child: Row(
          children: [
            Icon(icon, color: BrandColors.accentYellow),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BrandColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
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

typedef _PaymentConfirmCallback =
    Future<bool> Function(
      String method,
      CashPaymentDetails? cashDetails,
      Employee? employee,
    );

class _PaymentSheetFrame extends StatelessWidget {
  const _PaymentSheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, bottomInset + 12),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: size.height * 0.86,
            ),
            child: Material(
              color: Colors.transparent,
              child: GlassPanel(
                borderRadius: 24,
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(16),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentMethodSheet extends StatefulWidget {
  const _PaymentMethodSheet({
    required this.title,
    required this.subtitle,
    required this.total,
    required this.employees,
    required this.employeeDisabled,
    required this.primaryIcon,
    required this.onConfirm,
  });

  final String title;
  final String subtitle;
  final double total;
  final List<Employee> employees;
  final bool employeeDisabled;
  final IconData primaryIcon;
  final _PaymentConfirmCallback onConfirm;

  @override
  State<_PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends State<_PaymentMethodSheet> {
  final _cashController = TextEditingController();
  String? _method;
  Employee? _employee;
  String _error = '';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _cashController.addListener(_handleCashChanged);
  }

  @override
  void dispose() {
    _cashController.removeListener(_handleCashChanged);
    _cashController.dispose();
    super.dispose();
  }

  void _handleCashChanged() {
    if (mounted) {
      setState(() => _error = '');
    }
  }

  void _selectMethod(String method) {
    setState(() {
      _method = method;
      _employee = null;
      _error = '';
      if (method == 'cash') {
        _cashController.text = widget.total.toStringAsFixed(2);
        _cashController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _cashController.text.length,
        );
      }
    });
  }

  CashPaymentDetails? _cashDetails() {
    final received = double.tryParse(
      _cashController.text.trim().replaceAll(',', '.'),
    );
    if (received == null || received + 0.01 < widget.total) {
      setState(() => _error = 'El efectivo recibido no cubre el total.');
      return null;
    }
    return CashPaymentDetails(
      receivedAmount: received,
      changeAmount: received - widget.total,
    );
  }

  Future<void> _submit() async {
    final method = _method;
    if (method == null) {
      setState(() => _error = 'Selecciona una forma de pago.');
      return;
    }
    if (method == 'employee_consumption' && _employee == null) {
      setState(() => _error = 'Selecciona un empleado.');
      return;
    }
    final cashDetails = method == 'cash' ? _cashDetails() : null;
    if (method == 'cash' && cashDetails == null) {
      return;
    }

    setState(() => _submitting = true);
    final ok = await widget.onConfirm(method, cashDetails, _employee);
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    if (ok) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final method = _method;
    return _PaymentSheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionHeader(title: widget.title, subtitle: widget.subtitle),
          const SizedBox(height: 12),
          _PaymentMethodSelector(
            selected: method,
            employees: widget.employees,
            selectedEmployee: _employee,
            employeeDisabled: widget.employeeDisabled,
            onMethodChanged: _selectMethod,
            onEmployeeChanged: (employee) =>
                setState(() => _employee = employee),
          ),
          if (method != null) ...[
            const SizedBox(height: 8),
            _SelectedMethodChip(method: method),
            if (method == 'cash') ...[
              const SizedBox(height: 8),
              _CashInlinePanel(
                total: widget.total,
                controller: _cashController,
              ),
            ] else ...[
              const SizedBox(height: 8),
              _CompactTotalLine(total: widget.total),
            ],
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _error,
              style: const TextStyle(
                color: BrandColors.danger,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: Icon(widget.primaryIcon),
                  label: Text(_submitting ? 'Cobrando...' : 'Confirmar pago'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CashInlinePanel extends StatelessWidget {
  const _CashInlinePanel({required this.total, required this.controller});

  final double total;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final received =
        double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;
    final change = (received - total).clamp(0, double.infinity);
    final compact = MediaQuery.sizeOf(context).width < 650;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: BrandColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BrandColors.success.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total a cobrar',
                    style: TextStyle(
                      color: BrandColors.textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                MoneyText(
                  value: total,
                  style: TextStyle(
                    color: BrandColors.accentYellow,
                    fontSize: compact ? 22 : 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              style: TextStyle(
                fontSize: compact ? 22 : 28,
                fontWeight: FontWeight.w900,
              ),
              decoration: const InputDecoration(
                labelText: 'Con cuanto pagan?',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cambio',
                    style: TextStyle(
                      color: BrandColors.textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                MoneyText(
                  value: change.toDouble(),
                  style: TextStyle(
                    color: BrandColors.success,
                    fontSize: compact ? 30 : 38,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedMethodChip extends StatelessWidget {
  const _SelectedMethodChip({required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: BrandColors.accentYellow.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: BrandColors.accentYellow.withValues(alpha: 0.36),
          ),
        ),
        child: Text(
          formatPaymentMethod(method),
          style: const TextStyle(
            color: BrandColors.accentYellow,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _CompactTotalLine extends StatelessWidget {
  const _CompactTotalLine({required this.total});

  final double total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Total a cobrar',
            style: TextStyle(
              color: BrandColors.textMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        MoneyText(
          value: total,
          style: const TextStyle(
            color: BrandColors.accentYellow,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

typedef _PeoplePaymentConfirmCallback =
    Future<bool> Function(
      List<int> people,
      String label,
      double total,
      String method,
      CashPaymentDetails? cashDetails,
      Employee? employee,
    );

class _PeoplePaymentSheet extends StatefulWidget {
  const _PeoplePaymentSheet({
    required this.order,
    required this.items,
    required this.employees,
    required this.employeeDisabled,
    required this.personName,
    required this.pendingForItems,
    required this.onConfirm,
  });

  final PosOrder order;
  final List<OrderItem> items;
  final List<Employee> employees;
  final bool employeeDisabled;
  final String Function(int person, List<OrderItem> items, PosOrder order)
  personName;
  final double Function(List<OrderItem> items) pendingForItems;
  final _PeoplePaymentConfirmCallback onConfirm;

  @override
  State<_PeoplePaymentSheet> createState() => _PeoplePaymentSheetState();
}

class _PeoplePaymentSheetState extends State<_PeoplePaymentSheet> {
  final Set<int> _selected = {};
  bool _paymentStep = false;

  List<int> get _people {
    final people =
        widget.items.map((item) => item.personNumber).toSet().toList()..sort();
    return people;
  }

  List<OrderItem> _itemsFor(int person) {
    return widget.items.where((item) => item.personNumber == person).toList();
  }

  double _pendingFor(int person) {
    return widget.pendingForItems(_itemsFor(person));
  }

  double get _selectedTotal {
    return _selected.fold<double>(
      0,
      (total, person) => total + _pendingFor(person),
    );
  }

  String get _selectedLabel {
    final names = _selected.map(
      (person) => widget.personName(person, _itemsFor(person), widget.order),
    );
    return names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    if (_paymentStep) {
      return _PaymentMethodSheet(
        title: 'Cobrar personas seleccionadas',
        subtitle: _selectedLabel,
        total: _selectedTotal,
        employees: widget.employees,
        employeeDisabled: widget.employeeDisabled,
        primaryIcon: Icons.groups_2_outlined,
        onConfirm: (method, cashDetails, employee) {
          return widget.onConfirm(
            _selected.toList()..sort(),
            _selectedLabel,
            _selectedTotal,
            method,
            cashDetails,
            employee,
          );
        },
      );
    }

    return _PaymentSheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SectionHeader(
            title: 'Seleccionar personas',
            subtitle: 'Elige una o varias personas con saldo pendiente.',
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.42,
            ),
            child: ListView(
              shrinkWrap: true,
              children: _people.map((person) {
                final personItems = _itemsFor(person);
                final name = widget.personName(
                  person,
                  personItems,
                  widget.order,
                );
                final pending = widget.pendingForItems(personItems);
                final paid = pending <= 0.01;
                final selected = _selected.contains(person);
                final summary = _itemsSummary(personItems);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    selected: selected,
                    accent: paid
                        ? BrandColors.success
                        : BrandColors.accentOrange,
                    onTap: paid
                        ? null
                        : () {
                            setState(() {
                              selected
                                  ? _selected.remove(person)
                                  : _selected.add(person);
                            });
                          },
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.check_circle
                              : paid
                              ? Icons.check_circle_outline
                              : Icons.radio_button_unchecked,
                          color: paid || selected
                              ? BrandColors.success
                              : BrandColors.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (summary.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  summary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: BrandColors.textMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        paid
                            ? const StatusBadge(
                                style: StatusStyle(
                                  label: 'Pagada',
                                  color: BrandColors.success,
                                  background: Color(0x1F55D98B),
                                ),
                              )
                            : MoneyText(
                                value: pending,
                                style: const TextStyle(
                                  color: BrandColors.accentYellow,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 18),
          _PreviewRow(
            label: 'Total seleccionado',
            value: _selectedTotal,
            highlight: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => setState(() => _paymentStep = true),
                  child: const Text('Continuar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _itemsSummary(List<OrderItem> items) {
    final active = items
        .where((item) => item.paymentStatus != 'paid' && !item.isCancelled)
        .take(3)
        .map((item) => '${item.qty} ${item.productName}')
        .toList();
    if (active.isEmpty) {
      return '';
    }
    final extra = items.length > active.length ? '...' : '';
    return '${active.join(', ')}$extra';
  }
}

class _TotalsPanel extends StatelessWidget {
  const _TotalsPanel({required this.order, this.compact = false});

  final PosOrder order;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SectionHeader(
                  title: order.displayName,
                  subtitle: 'Cuenta actual',
                ),
              ),
              StatusBadge(style: tableStatusStyle(order.status)),
            ],
          ),
          SizedBox(height: compact ? 12 : 18),
          Row(
            children: [
              Expanded(
                child: _MoneyStat(label: 'Total', value: order.total),
              ),
              Expanded(
                child: _MoneyStat(label: 'Pagado', value: order.paidTotal),
              ),
              Expanded(
                child: _MoneyStat(
                  label: 'Pendiente',
                  value: order.pendingTotal,
                  highlight: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});

  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Captura el motivo.');
      return;
    }
    Navigator.pop(context, reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Motivo obligatorio'),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_error, style: const TextStyle(color: BrandColors.danger)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Confirmar')),
      ],
    );
  }
}

class _MoneyStat extends StatelessWidget {
  const _MoneyStat({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final double value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: BrandColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        MoneyText(
          value: value,
          style: TextStyle(
            color: highlight
                ? BrandColors.accentYellow
                : BrandColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PlatformPaymentView extends StatelessWidget {
  const _PlatformPaymentView({
    required this.order,
    required this.busy,
    required this.onPay,
  });

  final PosOrder order;
  final bool busy;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _TotalsPanel(order: order),
        const SizedBox(height: 16),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                title: 'Pagado en plataforma',
                subtitle:
                    'Este pedido se liquida fuera de caja por su plataforma.',
              ),
              const SizedBox(height: 14),
              _PreviewRow(label: 'Plataforma', textValue: order.platformName),
              _PreviewRow(label: 'Total pendiente', value: order.pendingTotal),
              const Divider(height: 18),
              _PreviewRow(
                label: 'Total a registrar',
                value: order.pendingTotal,
                highlight: true,
              ),
              const SizedBox(height: 14),
              GlassButton(
                icon: Icons.check_circle_outline,
                label: busy ? 'Registrando...' : 'Registrar como pagado',
                prominent: true,
                onTap: busy || order.pendingTotal <= 0.01 ? null : onPay,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodSelector extends StatelessWidget {
  const _PaymentMethodSelector({
    required this.selected,
    required this.employees,
    required this.selectedEmployee,
    required this.employeeDisabled,
    required this.onMethodChanged,
    required this.onEmployeeChanged,
  });

  final String? selected;
  final List<Employee> employees;
  final Employee? selectedEmployee;
  final bool employeeDisabled;
  final ValueChanged<String> onMethodChanged;
  final ValueChanged<Employee?> onEmployeeChanged;

  @override
  Widget build(BuildContext context) {
    final selectedValue = _selectedEmployeeFromList();

    const methods = {
      'cash': 'Efectivo',
      'card': 'Tarjeta',
      'employee_consumption': 'Consumo empleado',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Con que quieres pagar?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: methods.entries.map((entry) {
            return ChoiceChip(
              selected: selected == entry.key,
              label: Text(entry.value),
              onSelected:
                  entry.key == 'employee_consumption' && employeeDisabled
                  ? null
                  : (_) => onMethodChanged(entry.key),
            );
          }).toList(),
        ),
        if (employeeDisabled) ...[
          const SizedBox(height: 10),
          const Text(
            'Consumo empleado no disponible porque ya existe un pago de cliente.',
            style: TextStyle(
              color: BrandColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (selected == 'employee_consumption') ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<Employee>(
            initialValue: selectedValue,
            decoration: const InputDecoration(labelText: 'Empleado'),
            items: employees
                .map(
                  (employee) => DropdownMenuItem(
                    value: employee,
                    child: Text(employee.name),
                  ),
                )
                .toList(),
            onChanged: onEmployeeChanged,
          ),
        ],
      ],
    );
  }

  Employee? _selectedEmployeeFromList() {
    final id = selectedEmployee?.id;
    if (id == null) {
      return null;
    }

    for (final employee in employees) {
      if (employee.id == id) {
        return employee;
      }
    }

    return null;
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    this.value,
    this.textValue,
    this.highlight = false,
  });

  final String label;
  final double? value;
  final String? textValue;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
          if (value != null)
            MoneyText(
              value: value!,
              style: TextStyle(
                color: highlight
                    ? BrandColors.accentYellow
                    : BrandColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            )
          else
            Text(
              textValue ?? '',
              textAlign: TextAlign.end,
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

class _CashPaymentDialog extends StatefulWidget {
  const _CashPaymentDialog({required this.total});

  final double total;

  @override
  State<_CashPaymentDialog> createState() => _CashPaymentDialogState();
}

class _CashPaymentDialogState extends State<_CashPaymentDialog> {
  late final TextEditingController _receivedController;
  late final FocusNode _receivedFocusNode;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _receivedController = TextEditingController(
      text: widget.total.toStringAsFixed(2),
    );
    _receivedFocusNode = FocusNode();
    _receivedFocusNode.addListener(() {
      if (_receivedFocusNode.hasFocus) {
        _receivedController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _receivedController.text.length,
        );
      }
    });
    _receivedController.addListener(_handleReceivedChanged);
  }

  @override
  void dispose() {
    _receivedController.removeListener(_handleReceivedChanged);
    _receivedController.dispose();
    _receivedFocusNode.dispose();
    super.dispose();
  }

  double get _received =>
      double.tryParse(_receivedController.text.trim().replaceAll(',', '.')) ??
      0;

  double get _change => (_received - widget.total).clamp(0, double.infinity);

  void _handleReceivedChanged() {
    if (_error.isNotEmpty && _received + 0.01 >= widget.total) {
      setState(() => _error = '');
      return;
    }
    setState(() {});
  }

  void _confirm() {
    final received = _received;
    if (received + 0.01 < widget.total) {
      setState(() {
        _error = 'El efectivo recibido no cubre el total.';
      });
      return;
    }
    Navigator.pop(
      context,
      CashPaymentDetails(
        receivedAmount: received,
        changeAmount: received - widget.total,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _received + 0.01 >= widget.total;
    return SafeArea(
      child: Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Pago en efectivo',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 16),
                _PreviewRow(
                  label: 'Total a pagar',
                  value: widget.total,
                  highlight: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _receivedController,
                  focusNode: _receivedFocusNode,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Recibido',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(height: 12),
                _PreviewRow(label: 'Cambio', value: _change, highlight: true),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error,
                    style: const TextStyle(
                      color: BrandColors.danger,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: canConfirm ? _confirm : null,
                      child: const Text('Confirmar pago'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentsHistory extends StatelessWidget {
  const _PaymentsHistory({
    required this.payments,
    required this.canCancel,
    required this.onCancel,
    this.compact = false,
  });

  final List<Payment> payments;
  final bool canCancel;
  final ValueChanged<Payment> onCancel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Pagos realizados',
            subtitle: 'Historial de esta cuenta.',
          ),
          SizedBox(height: compact ? 6 : 12),
          if (payments.isEmpty)
            const Text(
              'Aun no hay pagos registrados.',
              style: TextStyle(color: BrandColors.textMuted),
            )
          else
            ...payments.map(
              (payment) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  payment.isCancelled
                      ? '${_paymentTitle(payment)} | Anulado'
                      : _paymentTitle(payment),
                ),
                subtitle: Text(_paymentSubtitle(payment)),
                trailing: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    MoneyText(
                      value: payment.chargedAmount,
                      style: TextStyle(
                        color: payment.isCancelled
                            ? BrandColors.textMuted
                            : BrandColors.accentYellow,
                        decoration: payment.isCancelled
                            ? TextDecoration.lineThrough
                            : null,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (canCancel && payment.isActive)
                      OutlinedButton.icon(
                        onPressed: () => onCancel(payment),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancelar pago'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _paymentTitle(Payment payment) {
    final method = formatPaymentMethod(payment.method);
    final type = switch (payment.type) {
      'person' => payment.personName ?? 'Persona',
      'platform' => payment.platformName ?? 'Plataforma',
      'partial' => 'Pago parcial',
      _ => 'Mesa completa',
    };
    return '$type | $method';
  }

  String _paymentSubtitle(Payment payment) {
    final employee = payment.employeeName == null
        ? ''
        : ' | ${payment.employeeName}';
    final cashChange =
        payment.method == 'cash' && payment.cashReceivedAmount != null
        ? ' | Recibido \$${payment.cashReceivedAmount!.toStringAsFixed(2)} | Cambio \$${(payment.cashChangeAmount ?? 0).toStringAsFixed(2)}'
        : '';
    final cancelled = payment.isCancelled
        ? ' | Anulado: ${payment.cancelReason ?? 'Sin motivo'}'
        : '';
    return 'Total \$${payment.baseAmount.toStringAsFixed(2)}$cashChange$employee$cancelled';
  }
}
