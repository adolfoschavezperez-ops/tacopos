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

enum _ChargeMode { table, person }

class _PaymentScreenState extends State<PaymentScreen> {
  final _repository = TacoPosRepository();
  final _partialController = TextEditingController();
  final _cashReceivedController = TextEditingController();
  String _method = 'cash';
  _ChargeMode? _chargeMode;
  int? _selectedPersonNumber;
  Employee? _selectedEmployee;
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
    _cashReceivedController.addListener(_handleCashChanged);
  }

  @override
  void dispose() {
    _partialController.dispose();
    _cashReceivedController.removeListener(_handleCashChanged);
    _cashReceivedController.dispose();
    super.dispose();
  }

  void _handleCashChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _payFullTable(
    PosOrder order, {
    required String method,
    CashPaymentDetails? cashDetails,
  }) async {
    if (!_validateEmployee(method)) {
      return;
    }

    final resolvedCashDetails =
        cashDetails ??
        await _cashDetailsIfNeeded(method: method, total: order.pendingTotal);
    if (resolvedCashDetails == null && method == 'cash') {
      return;
    }
    if (method != 'cash') {
      final confirmed = await _confirm(
        title: 'Cobrar mesa completa',
        message: 'Se cubrira todo el pendiente de ${order.displayName}.',
      );
      if (!confirmed) {
        return;
      }
    }

    if (!mounted) {
      return;
    }

    await _runPayment(
      () => _repository.payFullTable(
        orderId: widget.orderId,
        method: method,
        employeeId: _selectedEmployee?.id,
        employeeName: _selectedEmployee?.name,
        cashDetails: resolvedCashDetails,
      ),
    );
  }

  Future<void> _payPerson(
    int personNumber,
    String personName, {
    required String method,
    required double total,
    CashPaymentDetails? cashDetails,
  }) async {
    if (!_validateEmployee(method)) {
      return;
    }

    final resolvedCashDetails =
        cashDetails ?? await _cashDetailsIfNeeded(method: method, total: total);
    if (resolvedCashDetails == null && method == 'cash') {
      return;
    }
    if (method != 'cash') {
      final confirmed = await _confirm(
        title: 'Cobrar $personName',
        message: 'Solo se marcaran pagados los items de esta persona.',
      );
      if (!confirmed) {
        return;
      }
    }

    if (!mounted) {
      return;
    }

    await _runPayment(
      () => _repository.payPerson(
        orderId: widget.orderId,
        personNumber: personNumber,
        method: method,
        employeeId: _selectedEmployee?.id,
        employeeName: _selectedEmployee?.name,
        cashDetails: resolvedCashDetails,
      ),
    );
  }

  Future<void> _payPartial(
    PosOrder order, {
    required String method,
    CashPaymentDetails? cashDetails,
  }) async {
    if (!_validateEmployee(method)) {
      return;
    }

    final amount = double.tryParse(
      _partialController.text.replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0 || amount > order.pendingTotal + 0.01) {
      _showMessage('Captura un monto valido menor o igual al pendiente.');
      return;
    }

    final resolvedCashDetails =
        cashDetails ??
        await _cashDetailsIfNeeded(method: method, total: amount);
    if (resolvedCashDetails == null && method == 'cash') {
      return;
    }
    if (method != 'cash') {
      final confirmed = await _confirm(
        title: 'Agregar pago parcial',
        message: 'Se abonara este monto a la cuenta de ${order.displayName}.',
      );
      if (!confirmed) {
        return;
      }
    }

    if (!mounted) {
      return;
    }

    await _runPayment(
      () => _repository.payPartialAmount(
        orderId: widget.orderId,
        baseAmount: amount,
        method: method,
        employeeId: _selectedEmployee?.id,
        employeeName: _selectedEmployee?.name,
        cashDetails: resolvedCashDetails,
      ),
      afterSuccess: () => _partialController.clear(),
    );
  }

  CashPaymentDetails? _cashDetailsFromInline(double total) {
    final received = double.tryParse(
      _cashReceivedController.text.trim().replaceAll(',', '.'),
    );
    if (received == null || received + 0.01 < total) {
      _showMessage('El efectivo recibido no cubre el total.');
      return null;
    }
    return CashPaymentDetails(
      receivedAmount: received,
      changeAmount: received - total,
    );
  }

  void _prepareCashAmount(double total) {
    _cashReceivedController.removeListener(_handleCashChanged);
    _cashReceivedController.text = total.toStringAsFixed(2);
    _cashReceivedController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _cashReceivedController.text.length,
    );
    _cashReceivedController.addListener(_handleCashChanged);
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

  bool _validateEmployee(String method) {
    if (method == 'employee_consumption' && _selectedEmployee == null) {
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

  Future<void> _runPayment(
    Future<PaymentResult> Function() action, {
    VoidCallback? afterSuccess,
  }) async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      final result = await action();
      if (!mounted) {
        return;
      }

      afterSuccess?.call();
      _showMessage('Pago registrado.');

      if (result.allPaid) {
        await LivePresenceService.instance.clearCurrentOrder(
          currentAction: 'Viendo mesas',
        );
        if (!mounted) {
          return;
        }
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(_paymentErrorText(error));
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
                      final selectedMethod =
                          hasClientPayment && _method == 'employee_consumption'
                          ? 'cash'
                          : _method;
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
                      final selectedPerson =
                          _selectedPersonNumber != null &&
                              people.contains(_selectedPersonNumber)
                          ? _selectedPersonNumber
                          : null;
                      final selectedPersonItems = selectedPerson == null
                          ? <OrderItem>[]
                          : items
                                .where(
                                  (item) => item.personNumber == selectedPerson,
                                )
                                .toList();
                      final selectedPersonName = selectedPerson == null
                          ? null
                          : _personName(
                              selectedPerson,
                              selectedPersonItems,
                              order,
                            );
                      final selectedPersonPending = _pendingForItems(
                        selectedPersonItems,
                      );
                      final partialAmount =
                          double.tryParse(
                            _partialController.text.replaceAll(',', '.'),
                          ) ??
                          0;

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
                              _ChargeModeSelector(
                                selected: _chargeMode,
                                peopleCount: people.length,
                                tableDisabled:
                                    hasPersonPayments ||
                                    order.pendingTotal <= 0.01,
                                personDisabled: hasPartialPayments,
                                onTableSelected: () {
                                  setState(() {
                                    _chargeMode = _ChargeMode.table;
                                    _selectedPersonNumber = null;
                                    _method = selectedMethod;
                                    if (_method != 'employee_consumption') {
                                      _selectedEmployee = null;
                                    }
                                    _prepareCashAmount(order.pendingTotal);
                                  });
                                  LivePresenceService.instance.update(
                                    currentAction: 'Cobrando mesa completa',
                                  );
                                },
                                onPersonSelected: () {
                                  setState(() {
                                    _chargeMode = _ChargeMode.person;
                                    _selectedPersonNumber = null;
                                    _method = selectedMethod;
                                    if (_method != 'employee_consumption') {
                                      _selectedEmployee = null;
                                    }
                                  });
                                  LivePresenceService.instance.update(
                                    currentAction: 'Cobrando por persona',
                                  );
                                },
                              ),
                              if (_chargeMode == null) ...[
                                SizedBox(height: gap),
                                const _NextStepHint(),
                              ],
                              if (_chargeMode == _ChargeMode.table) ...[
                                SizedBox(height: gap),
                                _PaymentStepPanel(
                                  title: 'Mesa completa',
                                  subtitle:
                                      'Primero elige la forma de pago y confirma el pendiente.',
                                  total: order.pendingTotal,
                                  method: selectedMethod,
                                  employees: employees,
                                  selectedEmployee: _selectedEmployee,
                                  employeeDisabled: hasClientPayment,
                                  cashReceivedController:
                                      _cashReceivedController,
                                  busy: _busy,
                                  primaryLabel: _busy
                                      ? 'Cobrando...'
                                      : hasPersonPayments
                                      ? 'Cobro por persona iniciado'
                                      : 'Confirmar pago',
                                  primaryIcon: Icons.point_of_sale_outlined,
                                  primaryDisabled:
                                      _busy ||
                                      order.pendingTotal <= 0.01 ||
                                      hasPersonPayments,
                                  onMethodChanged: (value) {
                                    setState(() {
                                      _method = value;
                                      if (value != 'employee_consumption') {
                                        _selectedEmployee = null;
                                      }
                                      if (value == 'cash') {
                                        _prepareCashAmount(order.pendingTotal);
                                      }
                                    });
                                    LivePresenceService.instance.update(
                                      currentAction:
                                          'Cobrando con ${formatPaymentMethod(value)}',
                                    );
                                  },
                                  onEmployeeChanged: (employee) {
                                    setState(() {
                                      _selectedEmployee = employee;
                                    });
                                  },
                                  onConfirm: () {
                                    final cashDetails = selectedMethod == 'cash'
                                        ? _cashDetailsFromInline(
                                            order.pendingTotal,
                                          )
                                        : null;
                                    if (selectedMethod == 'cash' &&
                                        cashDetails == null) {
                                      return;
                                    }
                                    _payFullTable(
                                      order,
                                      method: selectedMethod,
                                      cashDetails: cashDetails,
                                    );
                                  },
                                ),
                                SizedBox(height: gap),
                                _PartialPaymentPanel(
                                  controller: _partialController,
                                  order: order,
                                  method: selectedMethod,
                                  busy: _busy,
                                  onPay: () {
                                    final cashDetails =
                                        selectedMethod == 'cash' &&
                                            partialAmount > 0
                                        ? _cashDetailsFromInline(partialAmount)
                                        : null;
                                    if (selectedMethod == 'cash' &&
                                        cashDetails == null) {
                                      return;
                                    }
                                    _payPartial(
                                      order,
                                      method: selectedMethod,
                                      cashDetails: cashDetails,
                                    );
                                  },
                                  disabledReason: hasPersonPayments
                                      ? 'Esta cuenta ya inicio cobro por persona. Termina el cobro por persona.'
                                      : null,
                                ),
                              ],
                              if (_chargeMode == _ChargeMode.person) ...[
                                SizedBox(height: gap),
                                if (hasPartialPayments) ...[
                                  const GlassPanel(
                                    child: Text(
                                      'Esta cuenta ya tiene pagos parciales. Termina el cobro por parcialidades.',
                                      style: TextStyle(
                                        color: BrandColors.textMuted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: gap),
                                ],
                                _PersonPickerPanel(
                                  people: people,
                                  items: items,
                                  order: order,
                                  selectedPerson: selectedPerson,
                                  disabled: hasPartialPayments,
                                  onSelected: (person) {
                                    final personItems = items
                                        .where(
                                          (item) => item.personNumber == person,
                                        )
                                        .toList();
                                    setState(() {
                                      _selectedPersonNumber = person;
                                      _method = selectedMethod;
                                      if (_method != 'employee_consumption') {
                                        _selectedEmployee = null;
                                      }
                                      _prepareCashAmount(
                                        _pendingForItems(personItems),
                                      );
                                    });
                                  },
                                ),
                                if (selectedPerson != null &&
                                    selectedPersonName != null) ...[
                                  SizedBox(height: gap),
                                  _PaymentStepPanel(
                                    title: selectedPersonName,
                                    subtitle:
                                        'Resumen de persona y forma de pago.',
                                    total: selectedPersonPending,
                                    method: selectedMethod,
                                    employees: employees,
                                    selectedEmployee: _selectedEmployee,
                                    employeeDisabled: hasClientPayment,
                                    cashReceivedController:
                                        _cashReceivedController,
                                    busy: _busy,
                                    primaryLabel: _busy
                                        ? 'Cobrando...'
                                        : 'Confirmar pago',
                                    primaryIcon: Icons.person_outline,
                                    primaryDisabled:
                                        _busy ||
                                        selectedPersonPending <= 0.01 ||
                                        hasPartialPayments,
                                    onMethodChanged: (value) {
                                      setState(() {
                                        _method = value;
                                        if (value != 'employee_consumption') {
                                          _selectedEmployee = null;
                                        }
                                        if (value == 'cash') {
                                          _prepareCashAmount(
                                            selectedPersonPending,
                                          );
                                        }
                                      });
                                      LivePresenceService.instance.update(
                                        currentAction:
                                            'Cobrando $selectedPersonName con ${formatPaymentMethod(value)}',
                                      );
                                    },
                                    onEmployeeChanged: (employee) {
                                      setState(() {
                                        _selectedEmployee = employee;
                                      });
                                    },
                                    onConfirm: () {
                                      final cashDetails =
                                          selectedMethod == 'cash'
                                          ? _cashDetailsFromInline(
                                              selectedPersonPending,
                                            )
                                          : null;
                                      if (selectedMethod == 'cash' &&
                                          cashDetails == null) {
                                        return;
                                      }
                                      _payPerson(
                                        selectedPerson,
                                        selectedPersonName,
                                        method: selectedMethod,
                                        total: selectedPersonPending,
                                        cashDetails: cashDetails,
                                      );
                                    },
                                  ),
                                ],
                              ],
                              const SizedBox(height: 20),
                              _PaymentsHistory(
                                payments: payments,
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

class _ChargeModeSelector extends StatelessWidget {
  const _ChargeModeSelector({
    required this.selected,
    required this.peopleCount,
    required this.tableDisabled,
    required this.personDisabled,
    required this.onTableSelected,
    required this.onPersonSelected,
  });

  final _ChargeMode? selected;
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
          selected: selected == _ChargeMode.table,
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
          selected: selected == _ChargeMode.person,
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
            title: 'Que quieres cobrar?',
            subtitle: 'Elige primero el tipo de cobro.',
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
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      selected: selected,
      accent: selected ? BrandColors.accentYellow : BrandColors.accentOrange,
      onTap: disabled ? null : onTap,
      padding: const EdgeInsets.all(13),
      child: Opacity(
        opacity: disabled ? 0.48 : 1,
        child: Row(
          children: [
            Icon(
              icon,
              color: selected
                  ? BrandColors.accentYellow
                  : BrandColors.textMuted,
            ),
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

class _NextStepHint extends StatelessWidget {
  const _NextStepHint();

  @override
  Widget build(BuildContext context) {
    return const GlassPanel(
      padding: EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(Icons.touch_app_outlined, color: BrandColors.textMuted),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Selecciona mesa completa o por persona para mostrar las formas de pago.',
              style: TextStyle(
                color: BrandColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentStepPanel extends StatelessWidget {
  const _PaymentStepPanel({
    required this.title,
    required this.subtitle,
    required this.total,
    required this.method,
    required this.employees,
    required this.selectedEmployee,
    required this.employeeDisabled,
    required this.cashReceivedController,
    required this.busy,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.primaryDisabled,
    required this.onMethodChanged,
    required this.onEmployeeChanged,
    required this.onConfirm,
  });

  final String title;
  final String subtitle;
  final double total;
  final String method;
  final List<Employee> employees;
  final Employee? selectedEmployee;
  final bool employeeDisabled;
  final TextEditingController cashReceivedController;
  final bool busy;
  final String primaryLabel;
  final IconData primaryIcon;
  final bool primaryDisabled;
  final ValueChanged<String> onMethodChanged;
  final ValueChanged<Employee?> onEmployeeChanged;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final received =
        double.tryParse(
          cashReceivedController.text.trim().replaceAll(',', '.'),
        ) ??
        0;
    final canConfirmCash = method != 'cash' || received + 0.01 >= total;
    final actionDisabled = primaryDisabled || !canConfirmCash;

    return GlassPanel(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 650 ? 14 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: title, subtitle: subtitle),
          const SizedBox(height: 12),
          _PaymentMethodSelector(
            selected: method,
            employees: employees,
            selectedEmployee: selectedEmployee,
            employeeDisabled: employeeDisabled,
            onMethodChanged: onMethodChanged,
            onEmployeeChanged: onEmployeeChanged,
          ),
          const SizedBox(height: 12),
          _ChargePreview(baseAmount: total, method: method),
          if (method == 'cash') ...[
            const SizedBox(height: 12),
            _CashInlinePanel(total: total, controller: cashReceivedController),
          ],
          const SizedBox(height: 12),
          GlassButton(
            icon: primaryIcon,
            label: primaryLabel,
            prominent: true,
            onTap: actionDisabled || busy ? null : onConfirm,
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

class _PersonPickerPanel extends StatelessWidget {
  const _PersonPickerPanel({
    required this.people,
    required this.items,
    required this.order,
    required this.selectedPerson,
    required this.disabled,
    required this.onSelected,
  });

  final List<int> people;
  final List<OrderItem> items;
  final PosOrder order;
  final int? selectedPerson;
  final bool disabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 650 ? 14 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Elige persona',
            subtitle: '${people.length} cuentas separadas.',
          ),
          const SizedBox(height: 12),
          if (people.isEmpty)
            const Text(
              'No hay personas con articulos en esta cuenta.',
              style: TextStyle(color: BrandColors.textMuted),
            )
          else
            ...people.map((person) {
              final personItems = items
                  .where((item) => item.personNumber == person)
                  .toList();
              final name = _personNameStatic(person, personItems, order);
              final subtotal = personItems.fold<double>(
                0,
                (runningTotal, item) =>
                    item.isCancelled ? runningTotal : runningTotal + item.total,
              );
              final pending = personItems
                  .where(
                    (item) => item.paymentStatus != 'paid' && !item.isCancelled,
                  )
                  .fold<double>(
                    0,
                    (runningTotal, item) => runningTotal + item.total,
                  );
              final paid = pending <= 0.01;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  selected: selectedPerson == person,
                  accent: paid ? BrandColors.success : BrandColors.accentOrange,
                  onTap: disabled || paid ? null : () => onSelected(person),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
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
                            const SizedBox(height: 3),
                            Text(
                              paid
                                  ? 'Pagado'
                                  : 'Pendiente \$${pending.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: paid
                                    ? BrandColors.success
                                    : BrandColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      MoneyText(
                        value: subtotal,
                        style: const TextStyle(
                          color: BrandColors.accentYellow,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  static String _personNameStatic(
    int person,
    List<OrderItem> items,
    PosOrder order,
  ) {
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

  final String selected;
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

class _ChargePreview extends StatelessWidget {
  const _ChargePreview({required this.baseAmount, required this.method});

  final double baseAmount;
  final String method;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: BrandColors.glassFill.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BrandColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _PreviewRow(
                  label: 'Forma de pago',
                  textValue: formatPaymentMethod(method),
                ),
                const Divider(height: 16),
                _PreviewRow(
                  label: 'Total a cobrar',
                  value: baseAmount,
                  highlight: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

class _PartialPaymentPanel extends StatefulWidget {
  const _PartialPaymentPanel({
    required this.controller,
    required this.order,
    required this.method,
    required this.busy,
    required this.onPay,
    this.disabledReason,
  });

  final TextEditingController controller;
  final PosOrder order;
  final String method;
  final bool busy;
  final VoidCallback onPay;
  final String? disabledReason;

  @override
  State<_PartialPaymentPanel> createState() => _PartialPaymentPanelState();
}

class _PartialPaymentPanelState extends State<_PartialPaymentPanel> {
  double _amount = 0;

  @override
  void initState() {
    super.initState();
    _amount = _parseAmount();
    widget.controller.addListener(_handleAmountChanged);
  }

  @override
  void didUpdateWidget(covariant _PartialPaymentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleAmountChanged);
      widget.controller.addListener(_handleAmountChanged);
      _amount = _parseAmount();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleAmountChanged);
    super.dispose();
  }

  void _handleAmountChanged() {
    final nextAmount = _parseAmount();
    if (nextAmount == _amount) {
      return;
    }
    setState(() {
      _amount = nextAmount;
    });
  }

  double _parseAmount() {
    return double.tryParse(widget.controller.text.replaceAll(',', '.')) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final disabledReason = widget.disabledReason;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Pago parcial',
            subtitle: 'Agrega un abono por monto a la cuenta.',
          ),
          const SizedBox(height: 12),
          if (disabledReason != null) ...[
            Text(
              disabledReason,
              style: const TextStyle(
                color: BrandColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: widget.controller,
            enabled: disabledReason == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monto a cubrir',
              helperText:
                  'Pendiente maximo: \$${widget.order.pendingTotal.toStringAsFixed(2)}',
            ),
          ),
          if (_amount > 0) ...[
            const SizedBox(height: 12),
            _ChargePreview(baseAmount: _amount, method: widget.method),
          ],
          const SizedBox(height: 12),
          GlassButton(
            icon: Icons.add_card_outlined,
            label: 'Agregar pago parcial',
            prominent: false,
            onTap: widget.busy || disabledReason != null ? null : widget.onPay,
          ),
        ],
      ),
    );
  }
}

class _PaymentsHistory extends StatelessWidget {
  const _PaymentsHistory({
    required this.payments,
    required this.canCancel,
    required this.onCancel,
  });

  final List<Payment> payments;
  final bool canCancel;
  final ValueChanged<Payment> onCancel;

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
          const SizedBox(height: 12),
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
