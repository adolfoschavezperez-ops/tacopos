import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../models/employee.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';
import '../../models/purchase_models.dart';
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
    AppliedDiscountDetails? discount,
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
        discount: discount,
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
    AppliedDiscountDetails? discount,
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
        discount: discount,
      ),
    );
  }

  Future<bool> _payPartial(
    PosOrder order, {
    required double amount,
    required String method,
    CashPaymentDetails? cashDetails,
    AppliedDiscountDetails? discount,
  }) async {
    if (amount <= 0 || amount > order.pendingTotal + 0.01) {
      _showMessage('Captura un monto valido menor o igual al pendiente.');
      return false;
    }

    final resolvedCashDetails =
        cashDetails ??
        await _cashDetailsIfNeeded(method: method, total: amount);
    if (resolvedCashDetails == null && method == 'cash') {
      return false;
    }
    if (method != 'cash') {
      final confirmed = await _confirm(
        title: 'Pago parcial',
        message: 'Se abonara \$${amount.toStringAsFixed(2)} a la cuenta.',
      );
      if (!confirmed) {
        return false;
      }
    }

    if (!mounted) {
      return false;
    }

    return _runPayment(
      () => _repository.payPartialAmount(
        orderId: widget.orderId,
        baseAmount: amount,
        method: method,
        cashDetails: resolvedCashDetails,
        discount: discount,
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

    final initialDiscount = await _autoGeneralDiscount(
      order,
      order.pendingTotal,
    );
    if (!mounted) return;
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
        initialDiscount: initialDiscount,
        onApplyDiscount: (amount) => _openDiscountDialog(order, amount),
        onConfirm: (method, cashDetails, employee, discount) {
          return _payFullTable(
            order,
            method: method,
            cashDetails: cashDetails,
            employee: employee,
            discount: discount,
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
        onAutoDiscount: (amount) => _autoGeneralDiscount(order, amount),
        onApplyDiscount: (amount) => _openDiscountDialog(order, amount),
        onConfirm:
            (people, label, total, method, cashDetails, employee, discount) {
              return _payPeople(
                people,
                label,
                method: method,
                total: total,
                cashDetails: cashDetails,
                employee: employee,
                discount: discount,
              );
            },
      ),
    );
  }

  Future<void> _openPartialSheet({
    required PosOrder order,
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
      builder: (sheetContext) => _PartialPaymentSheet(
        order: order,
        onAutoDiscount: (amount) => _autoGeneralDiscount(order, amount),
        onApplyDiscount: (amount) => _openDiscountDialog(order, amount),
        onConfirm: (amount, method, cashDetails, discount) {
          return _payPartial(
            order,
            amount: amount,
            method: method,
            cashDetails: cashDetails,
            discount: discount,
          );
        },
      ),
    );
  }

  Future<AppliedDiscountDetails?> _openDiscountDialog(
    PosOrder order,
    double amount,
  ) async {
    try {
      final employees = await _repository.getEmployeesOnce(activeOnly: true);
      final partners = await _repository.getPartnersOnce(activeOnly: true);
      final general = await _repository.getGeneralDiscountConfigOnce();
      if (!mounted) return null;
      return showDialog<AppliedDiscountDetails>(
        context: context,
        builder: (_) => _DiscountDialog(
          repository: _repository,
          order: order,
          amount: amount,
          employees: employees,
          partners: partners,
          generalDiscount: general,
        ),
      );
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString().replaceFirst('Bad state: ', ''));
      }
      return null;
    }
  }

  Future<AppliedDiscountDetails?> _autoGeneralDiscount(
    PosOrder order,
    double amount,
  ) async {
    try {
      final config = await _repository.getGeneralDiscountConfigOnce();
      if (!config.appliesToCurrentBranch(AppSession.instance.currentBranchId)) {
        return null;
      }
      return _repository.authorizeDiscount(
        order: order,
        amountBeforeDiscount: amount,
        discountType: 'general',
      );
    } catch (_) {
      return null;
    }
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
                                partialDisabled:
                                    hasPersonPayments ||
                                    order.pendingTotal <= 0.01,
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
                                onPartialSelected: () {
                                  LivePresenceService.instance.update(
                                    currentAction: 'Cobrando pago parcial',
                                  );
                                  _openPartialSheet(
                                    order: order,
                                    hasPersonPayments: hasPersonPayments,
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
    required this.partialDisabled,
    required this.onTableSelected,
    required this.onPersonSelected,
    required this.onPartialSelected,
  });

  final int peopleCount;
  final bool tableDisabled;
  final bool personDisabled;
  final bool partialDisabled;
  final VoidCallback onTableSelected;
  final VoidCallback onPersonSelected;
  final VoidCallback onPartialSelected;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 650;
    final cards = [
      _ChargeModeCard(
        title: 'Cobrar mesa completa',
        subtitle: 'Liquida todo el pendiente.',
        icon: Icons.table_restaurant_outlined,
        disabled: tableDisabled,
        onTap: onTableSelected,
      ),
      _ChargeModeCard(
        title: 'Pago parcial',
        subtitle: 'Abona una parte del saldo.',
        icon: Icons.payments_outlined,
        disabled: partialDisabled,
        onTap: onPartialSelected,
      ),
      _ChargeModeCard(
        title: 'Cobrar por persona',
        subtitle: '$peopleCount personas con cuenta.',
        icon: Icons.groups_2_outlined,
        disabled: personDisabled,
        onTap: onPersonSelected,
      ),
    ];

    return GlassPanel(
      padding: EdgeInsets.all(compact ? 14 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Como quieres cobrar?',
            subtitle: 'Elige una opcion para continuar.',
          ),
          const SizedBox(height: 12),
          compact
              ? Column(
                  children: [
                    for (final card in cards) ...[
                      card,
                      if (card != cards.last) const SizedBox(height: 10),
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final card in cards) ...[
                      Expanded(child: card),
                      if (card != cards.last) const SizedBox(width: 12),
                    ],
                  ],
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
      AppliedDiscountDetails? discount,
    );

typedef _PartialPaymentConfirmCallback =
    Future<bool> Function(
      double amount,
      String method,
      CashPaymentDetails? cashDetails,
      AppliedDiscountDetails? discount,
    );

typedef _ApplyDiscountCallback =
    Future<AppliedDiscountDetails?> Function(double amount);

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
    required this.onApplyDiscount,
    this.initialDiscount,
    this.allowEmployeeConsumption = true,
  });

  final String title;
  final String subtitle;
  final double total;
  final List<Employee> employees;
  final bool employeeDisabled;
  final IconData primaryIcon;
  final _PaymentConfirmCallback onConfirm;
  final _ApplyDiscountCallback onApplyDiscount;
  final AppliedDiscountDetails? initialDiscount;
  final bool allowEmployeeConsumption;

  @override
  State<_PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends State<_PaymentMethodSheet> {
  final _cashController = TextEditingController();
  String? _method;
  Employee? _employee;
  AppliedDiscountDetails? _discount;
  String _error = '';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _discount = widget.initialDiscount;
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
        _cashController.text = _totalToCharge.toStringAsFixed(2);
        _cashController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _cashController.text.length,
        );
      }
    });
  }

  double get _totalToCharge => _discount?.totalAfterDiscount ?? widget.total;

  CashPaymentDetails? _cashDetails() {
    final received = double.tryParse(
      _cashController.text.trim().replaceAll(',', '.'),
    );
    if (received == null || received + 0.01 < _totalToCharge) {
      setState(() => _error = 'El efectivo recibido no cubre el total.');
      return null;
    }
    return CashPaymentDetails(
      receivedAmount: received,
      changeAmount: received - _totalToCharge,
    );
  }

  Future<void> _applyDiscount() async {
    final discount = await widget.onApplyDiscount(widget.total);
    if (!mounted || discount == null) return;
    if (_discount != null && discount.percent < _discount!.percent) {
      setState(() {
        _error = 'Ya hay un descuento mayor aplicado.';
      });
      return;
    }
    setState(() {
      _discount = discount;
      _error = '';
      if (_method == 'cash') {
        _cashController.text = _totalToCharge.toStringAsFixed(2);
        _cashController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _cashController.text.length,
        );
      }
    });
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
    final ok = await widget.onConfirm(
      method,
      cashDetails,
      _employee,
      _discount,
    );
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
          const SizedBox(height: 8),
          _DiscountSummary(
            subtotal: widget.total,
            discount: _discount,
            onApply: _applyDiscount,
            onClear: _discount == null
                ? null
                : () => setState(() {
                    _discount = null;
                    if (_method == 'cash') {
                      _cashController.text = _totalToCharge.toStringAsFixed(2);
                    }
                  }),
          ),
          const SizedBox(height: 10),
          _PaymentMethodSelector(
            selected: method,
            employees: widget.employees,
            selectedEmployee: _employee,
            employeeDisabled: widget.employeeDisabled,
            allowEmployeeConsumption: widget.allowEmployeeConsumption,
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
                total: _totalToCharge,
                controller: _cashController,
              ),
            ] else ...[
              const SizedBox(height: 8),
              _CompactTotalLine(total: _totalToCharge),
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

class _PartialPaymentSheet extends StatefulWidget {
  const _PartialPaymentSheet({
    required this.order,
    required this.onAutoDiscount,
    required this.onApplyDiscount,
    required this.onConfirm,
  });

  final PosOrder order;
  final _ApplyDiscountCallback onAutoDiscount;
  final _ApplyDiscountCallback onApplyDiscount;
  final _PartialPaymentConfirmCallback onConfirm;

  @override
  State<_PartialPaymentSheet> createState() => _PartialPaymentSheetState();
}

class _PartialPaymentSheetState extends State<_PartialPaymentSheet> {
  final _amountController = TextEditingController();
  String _error = '';
  bool _paymentStep = false;
  bool _loadingDiscount = false;
  double _amount = 0;
  AppliedDiscountDetails? _initialDiscount;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_handleAmountChanged);
  }

  @override
  void dispose() {
    _amountController.removeListener(_handleAmountChanged);
    _amountController.dispose();
    super.dispose();
  }

  void _handleAmountChanged() {
    if (_error.isNotEmpty) {
      setState(() => _error = '');
    }
  }

  Future<void> _continue() async {
    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Captura un monto mayor a cero.');
      return;
    }
    if (amount > widget.order.pendingTotal + 0.01) {
      setState(() => _error = 'No puedes pagar mas del saldo pendiente.');
      return;
    }
    setState(() => _loadingDiscount = true);
    final discount = await widget.onAutoDiscount(amount);
    if (!mounted) return;
    setState(() {
      _amount = amount;
      _initialDiscount = discount;
      _paymentStep = true;
      _error = '';
      _loadingDiscount = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_paymentStep) {
      return _PaymentMethodSheet(
        title: 'Pago parcial',
        subtitle: 'Monto parcial \$${_amount.toStringAsFixed(2)}',
        total: _amount,
        employees: const [],
        employeeDisabled: true,
        allowEmployeeConsumption: false,
        primaryIcon: Icons.payments_outlined,
        initialDiscount: _initialDiscount,
        onApplyDiscount: widget.onApplyDiscount,
        onConfirm: (method, cashDetails, employee, discount) {
          return widget.onConfirm(_amount, method, cashDetails, discount);
        },
      );
    }

    return _PaymentSheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionHeader(
            title: 'Pago parcial',
            subtitle:
                'Saldo pendiente \$${widget.order.pendingTotal.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Monto a pagar',
              prefixText: '\$ ',
            ),
            onSubmitted: (_) => _continue(),
          ),
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
                  onPressed: _loadingDiscount ? null : _continue,
                  child: Text(_loadingDiscount ? 'Preparando...' : 'Continuar'),
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

class _DiscountSummary extends StatelessWidget {
  const _DiscountSummary({
    required this.subtotal,
    required this.discount,
    required this.onApply,
    required this.onClear,
  });

  final double subtotal;
  final AppliedDiscountDetails? discount;
  final VoidCallback onApply;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final current = discount;
    if (current == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onApply,
          icon: const Icon(Icons.percent_outlined),
          label: const Text('Aplicar descuento'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                current.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            TextButton(onPressed: onClear, child: const Text('Quitar')),
          ],
        ),
        _PreviewRow(label: 'Subtotal', value: subtotal),
        _PreviewRow(label: 'Descuento', value: current.discountAmount),
        _PreviewRow(
          label: 'Total a cobrar',
          value: current.totalAfterDiscount,
          highlight: true,
        ),
      ],
    );
  }
}

class _DiscountDialog extends StatefulWidget {
  const _DiscountDialog({
    required this.repository,
    required this.order,
    required this.amount,
    required this.employees,
    required this.partners,
    required this.generalDiscount,
  });

  final TacoPosRepository repository;
  final PosOrder order;
  final double amount;
  final List<Employee> employees;
  final List<Partner> partners;
  final GeneralDiscountConfig generalDiscount;

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  String _type = 'general';
  Employee? _employee;
  Partner? _partner;
  final _pinController = TextEditingController();
  final _reasonController = TextEditingController();
  String _error = '';
  bool _busy = false;

  @override
  void dispose() {
    _pinController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = <DropdownMenuItem<String>>[
      if (widget.generalDiscount.appliesToCurrentBranch(
        AppSession.instance.currentBranchId,
      ))
        DropdownMenuItem(
          value: 'general',
          child: Text(
            '${widget.generalDiscount.name} ${widget.generalDiscount.percent.toStringAsFixed(0)}%',
          ),
        ),
      const DropdownMenuItem(
        value: 'employee_free_meal',
        child: Text('Comida empleado del dia'),
      ),
      const DropdownMenuItem(value: 'employee_30', child: Text('Empleado 30%')),
      const DropdownMenuItem(
        value: 'family_friend_20',
        child: Text('Familia / amigos 20%'),
      ),
      const DropdownMenuItem(value: 'partner_50', child: Text('Socio 50%')),
    ];
    if (!options.any((item) => item.value == _type)) {
      _type = options.first.value!;
    }
    final needsEmployee =
        _type == 'employee_free_meal' || _type == 'employee_30';
    final needsPartner = _type == 'family_friend_20' || _type == 'partner_50';

    return AlertDialog(
      title: const Text('Aplicar descuento'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Descuento'),
                items: options,
                onChanged: (value) => setState(() {
                  _type = value ?? _type;
                  _error = '';
                }),
              ),
              if (needsEmployee) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<Employee>(
                  initialValue: _employee,
                  decoration: const InputDecoration(labelText: 'Empleado'),
                  items: widget.employees
                      .map(
                        (employee) => DropdownMenuItem(
                          value: employee,
                          child: Text(employee.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _employee = value),
                ),
              ],
              if (needsPartner) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<Partner>(
                  initialValue: _partner,
                  decoration: const InputDecoration(labelText: 'Socio'),
                  items: widget.partners
                      .map(
                        (partner) => DropdownMenuItem(
                          value: partner,
                          child: Text(partner.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _partner = value),
                ),
              ],
              if (needsEmployee || needsPartner) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'PIN'),
                ),
              ],
              if (_type == 'family_friend_20') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _reasonController,
                  decoration: const InputDecoration(labelText: 'Motivo'),
                ),
              ],
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _apply,
          child: Text(_busy ? 'Validando...' : 'Aplicar'),
        ),
      ],
    );
  }

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final discount = await widget.repository.authorizeDiscount(
        order: widget.order,
        amountBeforeDiscount: widget.amount,
        discountType: _type,
        employeeId: _employee?.id,
        partnerId: _partner?.id,
        pin: _pinController.text,
        reason: _reasonController.text,
      );
      if (!mounted) return;
      Navigator.pop(context, discount);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
        _busy = false;
      });
    }
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
      AppliedDiscountDetails? discount,
    );

class _PeoplePaymentSheet extends StatefulWidget {
  const _PeoplePaymentSheet({
    required this.order,
    required this.items,
    required this.employees,
    required this.employeeDisabled,
    required this.personName,
    required this.pendingForItems,
    required this.onAutoDiscount,
    required this.onApplyDiscount,
    required this.onConfirm,
  });

  final PosOrder order;
  final List<OrderItem> items;
  final List<Employee> employees;
  final bool employeeDisabled;
  final String Function(int person, List<OrderItem> items, PosOrder order)
  personName;
  final double Function(List<OrderItem> items) pendingForItems;
  final _ApplyDiscountCallback onAutoDiscount;
  final _ApplyDiscountCallback onApplyDiscount;
  final _PeoplePaymentConfirmCallback onConfirm;

  @override
  State<_PeoplePaymentSheet> createState() => _PeoplePaymentSheetState();
}

class _PeoplePaymentSheetState extends State<_PeoplePaymentSheet> {
  final Set<int> _selected = {};
  bool _paymentStep = false;
  bool _loadingDiscount = false;
  AppliedDiscountDetails? _initialDiscount;

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
        initialDiscount: _initialDiscount,
        onApplyDiscount: widget.onApplyDiscount,
        onConfirm: (method, cashDetails, employee, discount) {
          return widget.onConfirm(
            _selected.toList()..sort(),
            _selectedLabel,
            _selectedTotal,
            method,
            cashDetails,
            employee,
            discount,
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
                  onPressed: _selected.isEmpty || _loadingDiscount
                      ? null
                      : _continue,
                  child: Text(_loadingDiscount ? 'Preparando...' : 'Continuar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _continue() async {
    setState(() => _loadingDiscount = true);
    final discount = await widget.onAutoDiscount(_selectedTotal);
    if (!mounted) return;
    setState(() {
      _initialDiscount = discount;
      _paymentStep = true;
      _loadingDiscount = false;
    });
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
    required this.allowEmployeeConsumption,
    required this.onMethodChanged,
    required this.onEmployeeChanged,
  });

  final String? selected;
  final List<Employee> employees;
  final Employee? selectedEmployee;
  final bool employeeDisabled;
  final bool allowEmployeeConsumption;
  final ValueChanged<String> onMethodChanged;
  final ValueChanged<Employee?> onEmployeeChanged;

  @override
  Widget build(BuildContext context) {
    final selectedValue = _selectedEmployeeFromList();

    final methods = {
      'cash': 'Efectivo',
      'card': 'Tarjeta',
      if (allowEmployeeConsumption) 'employee_consumption': 'Consumo empleado',
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
        if (allowEmployeeConsumption && employeeDisabled) ...[
          const SizedBox(height: 10),
          const Text(
            'Consumo empleado no disponible porque ya existe un pago de cliente.',
            style: TextStyle(
              color: BrandColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (allowEmployeeConsumption && selected == 'employee_consumption') ...[
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
    final discount = payment.discountAmount <= 0
        ? ''
        : ' | ${payment.appliedDiscountName ?? 'Descuento'} -\$${payment.discountAmount.toStringAsFixed(2)}';
    final cancelled = payment.isCancelled
        ? ' | Anulado: ${payment.cancelReason ?? 'Sin motivo'}'
        : '';
    return 'Total \$${payment.baseAmount.toStringAsFixed(2)}$discount$cashChange$employee$cancelled';
  }
}
