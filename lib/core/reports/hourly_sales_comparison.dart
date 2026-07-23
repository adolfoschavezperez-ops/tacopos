import '../../models/order.dart';
import '../../models/payment.dart';

enum HourlyComparisonMode { yesterdayVsLastSales, previousWeek }

class HourlyBucket {
  const HourlyBucket({this.sales = 0, this.orderCount = 0});

  final double sales;
  final int orderCount;
}

class HourlyComparisonRow {
  const HourlyComparisonRow({
    required this.hour,
    required this.a,
    required this.b,
  });

  final int hour;
  final HourlyBucket a;
  final HourlyBucket b;

  double get diff => a.sales - b.sales;
}

class HourlyComparisonReport {
  const HourlyComparisonReport({
    required this.mode,
    required this.aDate,
    required this.bDate,
    required this.aLabel,
    required this.bLabel,
    required this.rows,
  });

  final HourlyComparisonMode mode;
  final DateTime aDate;
  final DateTime bDate;
  final String aLabel;
  final String bLabel;
  final List<HourlyComparisonRow> rows;

  String get title => mode == HourlyComparisonMode.yesterdayVsLastSales
      ? 'Ventas por hora: dia seleccionado vs ultimo dia con ventas'
      : 'Ventas por hora: semana anterior';
  double get totalA => rows.fold(0, (sum, row) => sum + row.a.sales);
  double get totalB => rows.fold(0, (sum, row) => sum + row.b.sales);
  HourlyComparisonRow? get bestA => _best(rows, (row) => row.a.sales);
  HourlyComparisonRow? get bestB => _best(rows, (row) => row.b.sales);
  HourlyComparisonRow? get lowestA {
    final nonZero = rows.where((row) => row.a.sales > 0).toList();
    if (nonZero.isEmpty) return null;
    nonZero.sort((a, b) => a.a.sales.compareTo(b.a.sales));
    return nonZero.first;
  }

  List<List<String>> get csvRows {
    return rows
        .map(
          (row) => [
            title,
            businessDateFor(aDate),
            businessDateFor(bDate),
            hourRange(row.hour),
            row.a.sales.toStringAsFixed(2),
            row.b.sales.toStringAsFixed(2),
            row.diff.toStringAsFixed(2),
            hourlyPercentLabel(row.a.sales, row.b.sales),
            '${row.a.orderCount}',
            '${row.b.orderCount}',
          ],
        )
        .toList();
  }

  static HourlyComparisonRow? _best(
    List<HourlyComparisonRow> rows,
    double Function(HourlyComparisonRow row) selector,
  ) {
    final nonZero = rows.where((row) => selector(row) > 0).toList();
    if (nonZero.isEmpty) return null;
    nonZero.sort((a, b) => selector(b).compareTo(selector(a)));
    return nonZero.first;
  }
}

class _MutableHourlyBucket {
  double sales = 0;
  final Set<String> orderIds = {};
}

HourlyComparisonReport? buildHourlySalesComparison({
  required HourlyComparisonMode mode,
  required List<Payment> payments,
  required List<PosOrder> orders,
  required DateTime baseDate,
}) {
  final orderById = {for (final order in orders) order.id: order};
  final activePayments = payments.where((payment) {
    if (!isHourlySalesActivePayment(payment)) return false;
    final order = orderById[payment.orderId];
    if (order == null) return true;
    return !isHourlySalesCancelledOrder(order);
  }).toList();
  final aDate = startOfDay(baseDate);
  final bDate = mode == HourlyComparisonMode.yesterdayVsLastSales
      ? _lastSalesDateBefore(activePayments, aDate)
      : aDate.subtract(const Duration(days: 7));
  if (bDate == null) return null;
  final aBuckets = hourlyBucketsForDate(activePayments, orderById, aDate);
  final bBuckets = hourlyBucketsForDate(activePayments, orderById, bDate);
  return HourlyComparisonReport(
    mode: mode,
    aDate: aDate,
    bDate: bDate,
    aLabel: 'Dia seleccionado',
    bLabel: mode == HourlyComparisonMode.yesterdayVsLastSales
        ? 'Ultimo dia con ventas'
        : 'Semana anterior',
    rows: List.generate(
      24,
      (hour) => HourlyComparisonRow(
        hour: hour,
        a: aBuckets[hour] ?? const HourlyBucket(),
        b: bBuckets[hour] ?? const HourlyBucket(),
      ),
    ),
  );
}

Map<int, HourlyBucket> hourlyBucketsForDate(
  List<Payment> payments,
  Map<String, PosOrder> orderById,
  DateTime date,
) {
  final key = businessDateFor(date);
  final buckets = <int, _MutableHourlyBucket>{};
  for (final payment in payments.where(
    (payment) => paymentBusinessDate(payment) == key,
  )) {
    final order = orderById[payment.orderId];
    final saleDate = payment.createdAt ?? order?.paidAt ?? order?.createdAt;
    final hour = (saleDate ?? date).hour;
    final bucket = buckets.putIfAbsent(hour, _MutableHourlyBucket.new);
    bucket.sales += hourlySalesCollectedAmount(payment);
    if (payment.orderId.trim().isNotEmpty) {
      bucket.orderIds.add(payment.orderId);
    }
  }
  return {
    for (final entry in buckets.entries)
      entry.key: HourlyBucket(
        sales: entry.value.sales,
        orderCount: entry.value.orderIds.length,
      ),
  };
}

bool isHourlySalesActivePayment(Payment payment) {
  final status = payment.status.trim().toLowerCase();
  const inactiveStatuses = {
    'cancelled',
    'canceled',
    'cancelado',
    'cancelada',
    'voided',
    'anulado',
    'anulada',
  };
  return !inactiveStatuses.contains(status) &&
      payment.cancelledAt == null &&
      hourlySalesCollectedAmount(payment) > 0;
}

double hourlySalesCollectedAmount(Payment payment) {
  if (payment.baseAmount > 0) return payment.baseAmount;
  if (payment.chargedAmount > 0) return payment.chargedAmount;
  return 0;
}

bool isHourlySalesCancelledOrder(PosOrder order) {
  final status = order.status.toLowerCase().trim();
  return status == 'cancelled' ||
      status == 'canceled' ||
      status == 'voided' ||
      order.cancelledAt != null ||
      order.canceledAt != null;
}

String paymentBusinessDate(Payment payment) {
  final businessDate = payment.businessDate?.trim();
  if (businessDate != null && businessDate.isNotEmpty) return businessDate;
  final createdAt = payment.createdAt;
  return createdAt == null ? '' : businessDateFor(createdAt);
}

DateTime startOfDay(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

String businessDateFor(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String hourRange(int hour) {
  final text = hour.toString().padLeft(2, '0');
  return '$text:00 - $text:59';
}

String hourlyPercentLabel(double a, double b) {
  if (b.abs() <= 0.01) {
    if (a.abs() <= 0.01) return '0.0%';
    return '+100.0%';
  }
  final percent = ((a - b) / b) * 100;
  final sign = percent > 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(1)}%';
}

DateTime? _lastSalesDateBefore(List<Payment> payments, DateTime date) {
  for (var offset = 1; offset <= 30; offset++) {
    final candidate = date.subtract(Duration(days: offset));
    final key = businessDateFor(candidate);
    final total = payments
        .where((payment) => paymentBusinessDate(payment) == key)
        .fold<double>(
          0,
          (sum, payment) => sum + hourlySalesCollectedAmount(payment),
        );
    if (total > 0.01) return candidate;
  }
  return null;
}
