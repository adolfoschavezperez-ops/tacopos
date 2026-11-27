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
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return ListView(
      padding: EdgeInsets.all(isMobile ? 14 : 22),
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
                title: 'Error al cargar el detalle',
                message: 'No se pudo obtener la información de esta venta.',
                onRetry: _load,
              );
            }
            final data = snapshot.data;
            if (data == null) {
              return SaasEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Venta no encontrada',
                message: 'No se encontró la orden solicitada.',
                action: OutlinedButton(
                  onPressed: widget.onBack,
                  child: const Text('Volver a Ventas'),
                ),
              );
            }

            final order = data.order;
            final summary = data.canonicalSummary;
            final branchName =
                widget.session.branches
                    .where((b) => b.id == order.branchId)
                    .map((b) => b.name)
                    .firstOrNull ??
                order.branchId;
            final folio = BackofficeSalesAdapter.resolveFolioLabel(order);
            final businessDate = BackofficeSalesAdapter.resolveOrderBusinessDate(
              order,
            );

            final timelineEvents = <({String label, String time, IconData icon})>[
              if (order.createdAt != null)
                (
                  label: 'Orden abierta',
                  time: BackofficeSalesAdapter.formatDateTime(order.createdAt),
                  icon: Icons.add_circle_outline_rounded,
                ),
              if (order.sentToKitchenAt != null)
                (
                  label: 'Enviada a cocina',
                  time: BackofficeSalesAdapter.formatDateTime(
                    order.sentToKitchenAt,
                  ),
                  icon: Icons.soup_kitchen_outlined,
                ),
              if (order.paidAt != null)
                (
                  label: 'Cobro completado',
                  time: BackofficeSalesAdapter.formatDateTime(order.paidAt),
                  icon: Icons.check_circle_outline_rounded,
                ),
              if (order.cancelledAt != null)
                (
                  label: 'Orden cancelada',
                  time: BackofficeSalesAdapter.formatDateTime(
                    order.cancelledAt,
                  ),
                  icon: Icons.cancel_outlined,
                ),
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero Header Card
                Container(
                  padding: EdgeInsets.all(isMobile ? 16 : 22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      BackofficeSpacing.radiusLg,
                    ),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF111318), Color(0xFF1B1F28)],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 14,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Orden $folio',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                  color: Color(0xFFFAFAF9),
                                ),
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
                          const SizedBox(height: 6),
                          Text(
                            '$branchName • ${BackofficeSalesAdapter.orderChannelDisplay(order)} • $businessDate',
                            style: TextStyle(
                              fontSize: 13,
                              color: const Color(0xFFFAFAF9)
                                  .withValues(alpha: 0.68),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Importe total',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: const Color(0xFFFAFAF9)
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                              Text(
                                BackofficeSalesAdapter.formatMoney(order.total),
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.6,
                                  color: Color(0xFFFAFAF9),
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          OutlinedButton.icon(
                            onPressed: widget.onBack,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFFAFAF9),
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.08,
                              ),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.16),
                              ),
                            ),
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              size: 15,
                            ),
                            label: const Text('Volver'),
                          ),
                        ],
                      ),
                    ],
                  ),
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
                            message: 'Esta orden no contiene productos.',
                          )
                        else
                          DataTablePro<OrderItem>(
                            items: data.items,
                            footerSummary: '${data.items.length} producto(s)',
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
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
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
                                  BackofficeSalesAdapter.formatMoney(
                                    i.unitPrice,
                                  ),
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
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
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
                                  children: data.payments
                                      .map((p) => _PaymentCardRow(payment: p))
                                      .toList(),
                                ),
                        ),
                      ],
                    );

                    final rightCol = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SaasCard(
                          title: 'Resumen de cobro',
                          subtitle: 'Desglose financiero de la orden',
                          trailing: StatusPill(
                            label: summary.hasReconciliationDifference
                                ? 'Con diferencia'
                                : 'Cuadrado',
                            tone: summary.hasReconciliationDifference
                                ? StatusTone.warning
                                : StatusTone.success,
                          ),
                          child: Column(
                            children: [
                              _SummaryLine(
                                'Subtotal bruto',
                                BackofficeSalesAdapter.formatMoney(
                                  summary.grossSales,
                                ),
                              ),
                              _SummaryLine(
                                'Descuentos',
                                '-${BackofficeSalesAdapter.formatMoney(summary.discountTotal)}',
                              ),
                              _SummaryLine(
                                'Consumo interno',
                                '-${BackofficeSalesAdapter.formatMoney(summary.employeeFreeMealTotal)}',
                              ),
                              const Divider(height: 18),
                              _SummaryLine(
                                'Total neto',
                                BackofficeSalesAdapter.formatMoney(
                                  summary.netSales,
                                ),
                                bold: true,
                              ),
                              _SummaryLine(
                                'Total cobrado',
                                BackofficeSalesAdapter.formatMoney(
                                  summary.totalCollected,
                                ),
                                bold: true,
                              ),
                              if (order.discountApplied &&
                                  (order.discountName ?? '').isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: tokens.brandAccentSoft,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Promoción: ${order.discountName}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: tokens.brandAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SaasCard(
                          title: 'Información de la venta',
                          child: Column(
                            children: [
                              _SummaryLine('Sucursal', branchName),
                              _SummaryLine(
                                'Canal de venta',
                                BackofficeSalesAdapter.orderTypeLabel(
                                  order.orderType,
                                ),
                              ),
                              _SummaryLine(
                                'Mesa o plataforma',
                                BackofficeSalesAdapter.orderChannelDisplay(
                                  order,
                                ),
                              ),
                              _SummaryLine(
                                'Comensales / Referencia',
                                order.personNames.isNotEmpty
                                    ? order.personNames.values.join(', ')
                                    : (order.customerName ?? '—'),
                              ),
                            ],
                          ),
                        ),
                        if (timelineEvents.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SaasCard(
                            title: 'Cronología',
                            child: Column(
                              children: timelineEvents.map((ev) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    children: [
                                      Icon(
                                        ev.icon,
                                        size: 16,
                                        color: tokens.brandAccent,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          ev.label,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                        ),
                                      ),
                                      Text(
                                        ev.time,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
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

class _PaymentCardRow extends StatelessWidget {
  const _PaymentCardRow({required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final isCancelled = payment.status == 'cancelled';
    final methodLabel = BackofficeSalesAdapter.paymentMethodLabel(
      payment.method,
    );
    final operatorName =
        payment.createdByEmployeeName ??
        payment.employeeName ??
        'Personal en turno';

    final icon = switch (payment.method.trim().toLowerCase()) {
      'cash' => Icons.payments_outlined,
      'card' => Icons.credit_card_rounded,
      'platform_paid' => Icons.delivery_dining_outlined,
      'employee_consumption' => Icons.restaurant_menu_rounded,
      _ => Icons.account_balance_wallet_outlined,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surfaceSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tokens.border),
            ),
            child: Icon(icon, size: 17, color: tokens.brandAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  methodLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
                Text(
                  'Atendido por: $operatorName',
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
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
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
