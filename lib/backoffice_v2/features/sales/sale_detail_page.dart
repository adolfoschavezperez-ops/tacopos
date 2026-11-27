import 'package:flutter/material.dart';

import '../../../models/order_item.dart';
import '../../../models/payment.dart';
import '../../auth/backoffice_session.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/design/design_tokens.dart';
import '../../widgets/data_table_pro.dart';
import '../../widgets/empty_error_state.dart';
import '../../widgets/saas_card.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/status_pill.dart';
import 'sales_repository.dart';

class SaleDetailPage extends StatefulWidget {
  const SaleDetailPage({
    super.key,
    required this.session,
    required this.repository,
    required this.orderId,
    required this.onBack,
  });

  final BackofficeSession session;
  final SalesRepository repository;
  final String orderId;
  final VoidCallback onBack;

  @override
  State<SaleDetailPage> createState() => _SaleDetailPageState();
}

class _SaleDetailPageState extends State<SaleDetailPage> {
  late Future<SaleDetailData?> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SaleDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) {
      _load();
    }
  }

  void _load() {
    setState(() {
      _future = widget.repository.loadSaleDetail(
        restaurantId: widget.session.restaurantId,
        orderId: widget.orderId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        FutureBuilder<SaleDetailData?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Column(
                children: [
                  DashboardSkeleton(),
                  SizedBox(height: 16),
                  TableSkeleton(rows: 5),
                ],
              );
            }
            if (snapshot.hasError) {
              return SaasErrorState(
                title: 'Error al cargar detalle de venta',
                message: snapshot.error.toString(),
                onRetry: _load,
              );
            }
            final data = snapshot.data;
            if (data == null) {
              return SaasEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Venta no encontrada',
                message: 'No existe la orden "${widget.orderId}" en este restaurante.',
                action: OutlinedButton(
                  onPressed: widget.onBack,
                  child: const Text('Volver a Ventas'),
                ),
              );
            }

            final order = data.order;
            final summary = data.canonicalSummary;
            final branchName = widget.session.branches
                .where((b) => b.id == order.branchId)
                .map((b) => b.name)
                .firstOrNull ??
                order.branchId;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Orden ${BackofficeSalesAdapter.resolveFolioLabel(order)}',
                                style: Theme.of(context).textTheme.headlineMedium,
                              ),
                              const SizedBox(width: 10),
                              switch (order.status) {
                                'paid' => const StatusPill(
                                  label: 'Pagada',
                                  tone: StatusTone.success,
                                ),
                                'cancelled' => const StatusPill(
                                  label: 'Cancelada',
                                  tone: StatusTone.danger,
                                ),
                                _ => const StatusPill(
                                  label: 'Abierta',
                                  tone: StatusTone.warning,
                                ),
                              },
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$branchName • Fecha operativa ${BackofficeSalesAdapter.resolveOrderBusinessDate(order)} • ID: ${order.id}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back, size: 15),
                      label: const Text('Volver'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 960;
                    final leftCol = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (data.items.isEmpty)
                          const SaasEmptyState(
                            icon: Icons.fastfood_outlined,
                            title: 'Sin artículos registrados',
                            message: 'Esta orden no contiene partidas en subcolección items.',
                          )
                        else
                          DataTablePro<OrderItem>(
                            items: data.items,
                            footerSummary: '${data.items.length} partida(s)',
                            columns: [
                              SaasColumn(
                                label: 'Producto',
                                flex: 3,
                                cellBuilder: (i) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      i.productName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                    if (i.notes.isNotEmpty)
                                      Text(
                                        i.notes,
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                              SaasColumn(
                                label: 'Cant.',
                                flex: 1,
                                alignRight: true,
                                cellBuilder: (i) => Text(
                                  '${i.qty}',
                                  style: const TextStyle(
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                              SaasColumn(
                                label: 'Unitario',
                                flex: 1,
                                alignRight: true,
                                cellBuilder: (i) => Text(
                                  BackofficeSalesAdapter.formatMoney(i.unitPrice),
                                  style: const TextStyle(
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                              SaasColumn(
                                label: 'Importe',
                                flex: 1,
                                alignRight: true,
                                cellBuilder: (i) => Text(
                                  BackofficeSalesAdapter.formatMoney(i.total),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: tokens.textPrimary,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 14),
                        SaasCard(
                          title: 'Pagos aplicados',
                          subtitle: '${data.payments.length} registro(s)',
                          child: data.payments.isEmpty
                              ? Text(
                                  'Sin pagos registrados.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                )
                              : Column(
                                  children: data.payments.map((p) {
                                    return _PaymentRow(payment: p);
                                  }).toList(),
                                ),
                        ),
                      ],
                    );

                    final rightCol = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SaasCard(
                          title: 'Conciliación canónica',
                          subtitle: 'Regla compartida con Android',
                          trailing: StatusPill(
                            label: summary.hasReconciliationDifference
                                ? 'Diferencia'
                                : 'Cuadrado',
                            tone: summary.hasReconciliationDifference
                                ? StatusTone.warning
                                : StatusTone.success,
                          ),
                          child: Column(
                            children: [
                              _SummaryLine(
                                'Venta bruta',
                                BackofficeSalesAdapter.formatMoney(summary.grossSales),
                              ),
                              _SummaryLine(
                                'Descuentos',
                                '-${BackofficeSalesAdapter.formatMoney(summary.discountTotal)}',
                              ),
                              _SummaryLine(
                                'Comida empleado',
                                '-${BackofficeSalesAdapter.formatMoney(summary.employeeFreeMealTotal)}',
                              ),
                              const Divider(height: 18),
                              _SummaryLine(
                                'Venta neta',
                                BackofficeSalesAdapter.formatMoney(summary.netSales),
                                bold: true,
                              ),
                              _SummaryLine(
                                'Total cobrado',
                                BackofficeSalesAdapter.formatMoney(summary.totalCollected),
                                bold: true,
                              ),
                              _SummaryLine(
                                'Diferencia conciliación',
                                BackofficeSalesAdapter.formatMoney(
                                  summary.reconciliationDifference,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SaasCard(
                          title: 'Metadatos operativos',
                          child: Column(
                            children: [
                              _SummaryLine('Tipo', order.orderType),
                              _SummaryLine(
                                'Mesa / Plataforma',
                                order.tableName.isNotEmpty
                                    ? order.tableName
                                    : ((order.platformName ?? '').isNotEmpty
                                          ? order.platformName!
                                          : 'Mostrador'),
                              ),
                              _SummaryLine(
                                'Comensales / Referencia',
                                order.personNames.isNotEmpty
                                    ? order.personNames.values.join(', ')
                                    : (order.customerName ?? '—'),
                              ),
                              _SummaryLine(
                                'Creada',
                                BackofficeSalesAdapter.formatDateTime(order.createdAt),
                              ),
                              _SummaryLine(
                                'Pagada',
                                BackofficeSalesAdapter.formatDateTime(order.paidAt),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );

                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: leftCol),
                          const SizedBox(width: 14),
                          Expanded(flex: 4, child: rightCol),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        leftCol,
                        const SizedBox(height: 14),
                        rightCol,
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                color: bold ? tokens.textPrimary : tokens.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: tokens.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final isCancelled = payment.status == 'cancelled';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.method.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
                Text(
                  'Operador: ${(payment.createdByEmployeeName ?? payment.employeeName ?? payment.createdBy ?? "—")} • Sesión: ${(payment.cashSessionId ?? "").isNotEmpty ? payment.cashSessionId : "—"}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (isCancelled) ...[
            const StatusPill(label: 'Cancelado', tone: StatusTone.danger),
            const SizedBox(width: 8),
          ],
          Text(
            BackofficeSalesAdapter.formatMoney(payment.chargedAmount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isCancelled ? tokens.textMuted : tokens.textPrimary,
              decoration: isCancelled ? TextDecoration.lineThrough : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
