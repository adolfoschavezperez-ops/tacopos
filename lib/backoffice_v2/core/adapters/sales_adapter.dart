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
