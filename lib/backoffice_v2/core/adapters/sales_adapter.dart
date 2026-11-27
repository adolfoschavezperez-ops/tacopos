import 'package:intl/intl.dart';

import '../../../core/reports/canonical_sales_summary.dart';
import '../../../models/order.dart';
import '../../../models/order_item.dart';
import '../../../models/payment.dart';

/// Adapter over shared Android/Backoffice financial rules.
///
/// Reuses [CanonicalSalesSummary] and [resolveOperationalBusinessDate] without
/// duplicating business logic.
class BackofficeSalesAdapter {
  const BackofficeSalesAdapter._();

  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'es_MX',
    symbol: '\$',
    decimalDigits: 2,
  );

  static final DateFormat _dateTimeFormat = DateFormat('dd MMM yyyy, HH:mm');
  static final DateFormat _businessDateFormat = DateFormat('yyyy-MM-dd');

  static String formatMoney(double amount) => _currencyFormat.format(amount);

  static String formatDateTime(DateTime? dt) =>
      dt == null ? '—' : _dateTimeFormat.format(dt);

  static String formatBusinessDate(DateTime dt) =>
      _businessDateFormat.format(dt);

  static String resolveOrderBusinessDate(PosOrder order) {
    return resolveOperationalBusinessDate(order: order);
  }

  static String resolveFolioLabel(PosOrder order) {
    final full = (order.saleFolioFull ?? '').trim();
    if (full.isNotEmpty) return full;
    final display = (order.saleFolioDisplay ?? '').trim();
    if (display.isNotEmpty) return display;
    return order.id.length <= 8 ? order.id : order.id.substring(0, 8);
  }

  static String paymentMethodLabel(String method) {
    return switch (method.trim().toLowerCase()) {
      'cash' => 'Efectivo',
      'card' => 'Tarjeta',
      'platform_paid' => 'Pago por plataforma',
      'employee_consumption' => 'Consumo interno',
      'transfer' => 'Transferencia',
      _ => 'Otro método',
    };
  }

  static String orderTypeLabel(String orderType) {
    return switch (orderType.trim().toLowerCase()) {
      'dine_in' => 'Comedor',
      'takeout' => 'Para llevar',
      'standing' => 'En barra',
      _ => 'Mostrador',
    };
  }

  static String orderStatusLabel(String status) {
    return switch (status.trim().toLowerCase()) {
      'paid' => 'Pagada',
      'cancelled' => 'Cancelada',
      _ => 'Abierta',
    };
  }

  static String orderChannelDisplay(PosOrder order) {
    if (order.tableName.trim().isNotEmpty) return order.tableName.trim();
    if ((order.platformName ?? '').trim().isNotEmpty) {
      return order.platformName!.trim();
    }
    return orderTypeLabel(order.orderType);
  }

  static CanonicalSalesSummary buildCanonicalSummary({
    required List<PosOrder> orders,
    required Map<String, List<OrderItem>> itemsByOrder,
    required Map<String, List<Payment>> paymentsByOrder,
  }) {
    final bundles = orders.map(
      (order) => SalesOrderBundleInput(
        order: order,
        items: itemsByOrder[order.id] ?? const [],
        payments: paymentsByOrder[order.id] ?? const [],
      ),
    );
    return buildCanonicalSalesSummary(bundles);
  }
}
