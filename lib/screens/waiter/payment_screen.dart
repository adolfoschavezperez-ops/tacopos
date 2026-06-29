import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../core/theme/status_styles.dart';
import '../../models/employee.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';
import '../../services/taco_pos_repository.dart';
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
  final _partialController = TextEditingController();
  String _method = 'cash';
  Employee? _selectedEmployee;
  bool _busy = false;

  @override
  void dispose() {
    _partialController.dispose();
    super.dispose();
  }

  Future<void> _payFullTable(PosOrder order) async {
    if (!_validateEmployee()) {
      return;
    }

    final confirmed = await _confirm(
      title: 'Cobrar mesa completa',
      message: 'Se cubrira todo el pendiente de ${order.displayName}.',
    );
    if (!confirmed) {
      return;
    }

    await _runPayment(
      () => _repository.payFullTable(
        orderId: widget.orderId,
        method: _method,
        employeeId: _selectedEmployee?.id,
        employeeName: _selectedEmployee?.name,
      ),
    );
  }

  Future<void> _payPerson(int personNumber, String personName) async {
    if (!_validateEmployee()) {
      return;
    }

    final confirmed = await _confirm(
      title: 'Cobrar $personName',
      message: 'Solo se marcaran pagados los items de esta persona.',
    );
    if (!confirmed) {
      return;
    }

    await _runPayment(
      () => _repository.payPerson(
        orderId: widget.orderId,
        personNumber: personNumber,
        method: _method,
        employeeId: _selectedEmployee?.id,
        employeeName: _selectedEmployee?.name,
      ),
    );
  }

  Future<void> _payPartial(PosOrder order) async {
    if (!_validateEmployee()) {
      return;
    }

    final amount = double.tryParse(
      _partialController.text.replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0 || amount > order.pendingTotal + 0.01) {
      _showMessage('Captura un monto valido menor o igual al pendiente.');
      return;
    }

    final confirmed = await _confirm(
      title: 'Agregar pago parcial',
      message: 'Se abonara este monto a la cuenta de ${order.displayName}.',
    );
    if (!confirmed) {
      return;
    }

    await _runPayment(
      () => _repository.payPartialAmount(
        orderId: widget.orderId,
        baseAmount: amount,
        method: _method,
        employeeId: _selectedEmployee?.id,
        employeeName: _selectedEmployee?.name,
      ),
      afterSuccess: () => _partialController.clear(),
    );
  }

  bool _validateEmployee() {
    if (_method == 'employee_consumption' && _selectedEmployee == null) {
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
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('No se pudo cobrar: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
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
                      final hasPartialPayments = payments.any(
                        (payment) => payment.type == 'partial',
                      );
                      final hasPersonPayments = payments.any(
                        (payment) => payment.type == 'person',
                      );

                      return ListView(
                        padding: const EdgeInsets.all(22),
                        children: [
                          _TotalsPanel(order: order),
                          const SizedBox(height: 16),
                          _PaymentMethodSelector(
                            selected: _method,
                            employees: employees,
                            selectedEmployee: _selectedEmployee,
                            onMethodChanged: (value) {
                              setState(() {
                                _method = value;
                                if (value != 'employee_consumption') {
                                  _selectedEmployee = null;
                                }
                              });
                            },
                            onEmployeeChanged: (employee) {
                              setState(() {
                                _selectedEmployee = employee;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          _ChargePreview(
                            baseAmount: order.pendingTotal,
                            method: _method,
                          ),
                          const SizedBox(height: 16),
                          GlassButton(
                            icon: Icons.point_of_sale_outlined,
                            label: _busy
                                ? 'Cobrando...'
                                : hasPersonPayments
                                ? 'Cobro por persona iniciado'
                                : 'Cobrar mesa completa',
                            prominent: true,
                            onTap:
                                _busy ||
                                    order.pendingTotal <= 0.01 ||
                                    hasPersonPayments
                                ? null
                                : () => _payFullTable(order),
                          ),
                          const SizedBox(height: 20),
                          _PartialPaymentPanel(
                            controller: _partialController,
                            order: order,
                            method: _method,
                            busy: _busy,
                            onPay: () => _payPartial(order),
                            disabledReason: hasPersonPayments
                                ? 'Esta cuenta ya inicio cobro por persona. Termina el cobro por persona.'
                                : null,
                          ),
                          const SizedBox(height: 20),
                          SectionHeader(
                            title: 'Por persona',
                            subtitle:
                                '${_people(items).length} cuentas separadas',
                          ),
                          const SizedBox(height: 12),
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
                            const SizedBox(height: 12),
                          ],
                          ..._people(items).map((person) {
                            final personItems = items
                                .where((item) => item.personNumber == person)
                                .toList();
                            final personName = _personName(
                              person,
                              personItems,
                              order,
                            );
                            return _PersonPaymentCard(
                              key: ValueKey('payment-person-$person'),
                              personNumber: person,
                              personName: personName,
                              items: personItems,
                              method: _method,
                              busy: _busy,
                              disabled: hasPartialPayments,
                              onPay: () => _payPerson(person, personName),
                            );
                          }),
                          const SizedBox(height: 20),
                          _PaymentsHistory(payments: payments),
                        ],
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
}

class _TotalsPanel extends StatelessWidget {
  const _TotalsPanel({required this.order});

  final PosOrder order;

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
          const SizedBox(height: 18),
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

class _PaymentMethodSelector extends StatelessWidget {
  const _PaymentMethodSelector({
    required this.selected,
    required this.employees,
    required this.selectedEmployee,
    required this.onMethodChanged,
    required this.onEmployeeChanged,
  });

  final String selected;
  final List<Employee> employees;
  final Employee? selectedEmployee;
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

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Metodo de pago',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: methods.entries.map((entry) {
              return ChoiceChip(
                selected: selected == entry.key,
                label: Text(entry.value),
                onSelected: (_) => onMethodChanged(entry.key),
              );
            }).toList(),
          ),
          if (selected == 'employee_consumption') ...[
            const SizedBox(height: 14),
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
      ),
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
    final surcharge = method == 'card'
        ? baseAmount * TacoPosRepository.cardSurchargeRate
        : 0.0;
    final charged = baseAmount + surcharge;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen de cobro',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _PreviewRow(label: 'Monto base', value: baseAmount),
          if (method == 'card')
            _PreviewRow(label: 'Comision tarjeta 4%', value: surcharge),
          const Divider(height: 18),
          _PreviewRow(label: 'Total a cobrar', value: charged, highlight: true),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
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
              labelText: 'Monto base a cubrir',
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

class _PersonPaymentCard extends StatelessWidget {
  const _PersonPaymentCard({
    super.key,
    required this.personNumber,
    required this.personName,
    required this.items,
    required this.method,
    required this.busy,
    required this.disabled,
    required this.onPay,
  });

  final int personNumber;
  final String personName;
  final List<OrderItem> items;
  final String method;
  final bool busy;
  final bool disabled;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final subtotal = items.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.total,
    );
    final pending = items
        .where((item) => item.paymentStatus != 'paid')
        .fold<double>(0, (runningTotal, item) => runningTotal + item.total);
    final paid = pending <= 0.01;
    final surcharge = method == 'card'
        ? pending * TacoPosRepository.cardSurchargeRate
        : 0.0;
    final charged = pending + surcharge;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        selected: paid,
        accent: paid ? BrandColors.success : BrandColors.accentOrange,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    personName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                MoneyText(
                  value: subtotal,
                  style: const TextStyle(
                    color: BrandColors.accentYellow,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                paid
                    ? const StatusBadge(
                        style: StatusStyle(
                          label: 'Pagado',
                          color: BrandColors.success,
                          background: Color(0x1F55D98B),
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: busy || disabled ? null : onPay,
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Cobrar persona'),
                      ),
              ],
            ),
            const SizedBox(height: 10),
            if (paid)
              const Text(
                'Pagado',
                style: TextStyle(color: BrandColors.textMuted),
              )
            else ...[
              _PersonChargeRow(label: 'Subtotal base', value: pending),
              if (method == 'card')
                _PersonChargeRow(
                  label: 'Comision tarjeta 4%',
                  value: surcharge,
                ),
              const Divider(height: 14),
              _PersonChargeRow(
                label: 'Total a cobrar',
                value: charged,
                highlight: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PersonChargeRow extends StatelessWidget {
  const _PersonChargeRow({
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
      padding: const EdgeInsets.symmetric(vertical: 2),
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

class _PaymentsHistory extends StatelessWidget {
  const _PaymentsHistory({required this.payments});

  final List<Payment> payments;

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
                title: Text(_paymentTitle(payment)),
                subtitle: Text(_paymentSubtitle(payment)),
                trailing: MoneyText(
                  value: payment.chargedAmount,
                  style: const TextStyle(
                    color: BrandColors.accentYellow,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _paymentTitle(Payment payment) {
    final method = switch (payment.method) {
      'card' => 'Tarjeta',
      'employee_consumption' => 'Consumo empleado',
      _ => 'Efectivo',
    };
    final type = switch (payment.type) {
      'person' => payment.personName ?? 'Persona',
      'partial' => 'Pago parcial',
      _ => 'Mesa completa',
    };
    return '$type · $method';
  }

  String _paymentSubtitle(Payment payment) {
    final employee = payment.employeeName == null
        ? ''
        : ' · ${payment.employeeName}';
    final fee = payment.surchargeAmount <= 0
        ? ''
        : ' · Comision \$${payment.surchargeAmount.toStringAsFixed(2)}';
    return 'Base \$${payment.baseAmount.toStringAsFixed(2)}$fee$employee';
  }
}
