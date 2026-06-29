import 'package:flutter/material.dart';

import '../../core/theme/brand_colors.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../services/taco_pos_repository.dart';
import '../../widgets/branded_scaffold.dart';
import '../../widgets/glass.dart';
import '../../widgets/loading_panel.dart';
import '../../widgets/money_text.dart';
import '../../widgets/status_badge.dart';
import '../../core/theme/status_styles.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _repository = TacoPosRepository();
  String _method = 'cash';
  bool _busy = false;

  Future<void> _payFullTable(PosOrder order) async {
    final confirmed = await _confirm(
      title: 'Cobrar mesa completa',
      message: 'Se pagara el total pendiente de ${order.tableName}.',
    );
    if (!confirmed) {
      return;
    }

    await _runPayment(
      () => _repository.payFullTable(orderId: widget.orderId, method: _method),
      closeToTables: true,
    );
  }

  Future<void> _payPerson(int personNumber) async {
    final confirmed = await _confirm(
      title: 'Cobrar Persona $personNumber',
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
      ),
    );
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
    Future<void> Function() action, {
    bool closeToTables = false,
  }) async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await action();
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pago registrado.')));

      if (closeToTables) {
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo cobrar: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrandedScaffold(
      title: 'Cobro',
      body: StreamBuilder<PosOrder?>(
        stream: _repository.watchOrder(widget.orderId),
        builder: (context, orderSnapshot) {
          final order = orderSnapshot.data;
          if (orderSnapshot.connectionState == ConnectionState.waiting ||
              order == null) {
            return const LoadingPanel(message: 'Cargando cuenta...');
          }

          return StreamBuilder<List<OrderItem>>(
            stream: _repository.watchOrderItems(widget.orderId),
            builder: (context, itemSnapshot) {
              final items = itemSnapshot.data ?? [];
              return ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  _TotalsPanel(order: order),
                  const SizedBox(height: 16),
                  _PaymentMethodSelector(
                    selected: _method,
                    onChanged: (value) {
                      setState(() {
                        _method = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  GlassButton(
                    icon: Icons.point_of_sale_outlined,
                    label: _busy ? 'Cobrando...' : 'Cobrar mesa completa',
                    prominent: true,
                    onTap: _busy || order.pendingTotal <= 0.01
                        ? null
                        : () => _payFullTable(order),
                  ),
                  const SizedBox(height: 20),
                  SectionHeader(
                    title: 'Por persona',
                    subtitle: '${_people(items).length} cuentas separadas',
                  ),
                  const SizedBox(height: 12),
                  ..._people(items).map(
                    (person) => _PersonPaymentCard(
                      key: ValueKey('payment-person-$person'),
                      personNumber: person,
                      items: items
                          .where((item) => item.personNumber == person)
                          .toList(),
                      busy: _busy,
                      onPay: () => _payPerson(person),
                    ),
                  ),
                ],
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
                  title: order.tableName,
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
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const methods = {
      'cash': 'Efectivo',
      'card': 'Tarjeta',
      'transfer': 'Transferencia',
      'mixed': 'Mixto',
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
                onSelected: (_) => onChanged(entry.key),
              );
            }).toList(),
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
    required this.items,
    required this.busy,
    required this.onPay,
  });

  final int personNumber;
  final List<OrderItem> items;
  final bool busy;
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        selected: paid,
        accent: paid ? BrandColors.success : BrandColors.accentOrange,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Persona $personNumber',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    paid ? 'Pagado' : '${items.length} productos pendientes',
                    style: const TextStyle(color: BrandColors.textMuted),
                  ),
                ],
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
                    onPressed: busy ? null : onPay,
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Cobrar persona'),
                  ),
          ],
        ),
      ),
    );
  }
}
