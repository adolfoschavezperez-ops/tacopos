import 'package:intl/intl.dart';

import '../../models/order.dart';
import '../orders/order_types.dart';
import 'canonical_sales_summary.dart';

const visitClassificationCsvHeaders = [
  'Semana',
  'Tipo semana',
  'Nuevas',
  'Recurrentes',
  'Total clasificadas',
  'Sin clasificar',
  'Cambio nuevas',
  'Cambio recurrentes',
  'Cambio total',
  '% nuevas',
  '% recurrentes',
];

class VisitClassificationWeeklyReport {
  const VisitClassificationWeeklyReport({
    required this.startBusinessDate,
    required this.endBusinessDate,
    required this.rows,
  });

  final String startBusinessDate;
  final String endBusinessDate;
  final List<VisitClassificationWeekRow> rows;

  int get firstTimeTotal => rows.fold(0, (sum, row) => sum + row.firstTime);
  int get returningTotal => rows.fold(0, (sum, row) => sum + row.returning);
  int get classifiedTotal => rows.fold(0, (sum, row) => sum + row.classified);
  int get unknownTotal => rows.fold(0, (sum, row) => sum + row.unknown);
  bool get hasPartialWeeks => rows.any((row) => row.isPartial);

  double get firstTimeWeeklyAverage => _average((row) => row.firstTime);
  double get returningWeeklyAverage => _average((row) => row.returning);
  double get classifiedWeeklyAverage => _average((row) => row.classified);

  double _average(int Function(VisitClassificationWeekRow row) read) {
    if (rows.isEmpty) return 0;
    return rows.fold<int>(0, (sum, row) => sum + read(row)) / rows.length;
  }

  List<List<String>> get csvRows => rows.map((row) => row.csvRow).toList();
}

class VisitClassificationWeekRow {
  const VisitClassificationWeekRow({
    required this.weekStart,
    required this.weekEnd,
    required this.isPartial,
    required this.firstTime,
    required this.returning,
    required this.unknown,
    required this.firstTimeChange,
    required this.returningChange,
    required this.classifiedChange,
  });

  final DateTime weekStart;
  final DateTime weekEnd;
  final bool isPartial;
  final int firstTime;
  final int returning;
  final int unknown;
  final int? firstTimeChange;
  final int? returningChange;
  final int? classifiedChange;

  int get classified => firstTime + returning;
  int get auditedTotal => classified + unknown;
  double get firstTimePercent => classified == 0 ? 0 : firstTime / classified;
  double get returningPercent => classified == 0 ? 0 : returning / classified;

  String get weekLabel =>
      '${_displayDate(weekStart)} al ${_displayDate(weekEnd)}';
  String get weekTypeLabel => isPartial ? 'Semana parcial' : 'Semana completa';

  List<String> get csvRow => [
    weekLabel,
    weekTypeLabel,
    '$firstTime',
    '$returning',
    '$classified',
    '$unknown',
    _changeLabel(firstTimeChange),
    _changeLabel(returningChange),
    _changeLabel(classifiedChange),
    _percentLabel(firstTimePercent),
    _percentLabel(returningPercent),
  ];
}

VisitClassificationWeeklyReport buildVisitClassificationWeeklyReport({
  required Iterable<PosOrder> orders,
  required String startBusinessDate,
  required String endBusinessDate,
}) {
  final start = _parseBusinessDate(startBusinessDate);
  final end = _parseBusinessDate(endBusinessDate);
  if (start == null || end == null || end.isBefore(start)) {
    return VisitClassificationWeeklyReport(
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      rows: const [],
    );
  }

  final weekStarts = <DateTime>[];
  for (
    var cursor = _weekStart(start);
    !cursor.isAfter(end);
    cursor = cursor.add(const Duration(days: 7))
  ) {
    weekStarts.add(cursor);
  }

  final buckets = {
    for (final weekStart in weekStarts) _key(weekStart): _VisitBucket(),
  };

  for (final order in orders) {
    if (!_isEligibleVisitOrder(order)) continue;
    final businessDate = resolveOperationalBusinessDate(
      order: order,
      historicalFallback: order.paidAt ?? order.createdAt ?? order.updatedAt,
    );
    final date = _parseBusinessDate(businessDate);
    if (date == null || date.isBefore(start) || date.isAfter(end)) continue;
    final bucket = buckets[_key(_weekStart(date))];
    if (bucket == null) continue;
    switch (order.visitClassificationStatus) {
      case 'first_time':
        bucket.firstTime++;
        break;
      case 'returning':
        bucket.returning++;
        break;
      default:
        bucket.unknown++;
    }
  }

  final rows = <VisitClassificationWeekRow>[];
  _VisitBucket? previous;
  for (final weekStart in weekStarts) {
    final bucket = buckets[_key(weekStart)] ?? _VisitBucket();
    final weekEnd = weekStart.add(const Duration(days: 6));
    rows.add(
      VisitClassificationWeekRow(
        weekStart: weekStart,
        weekEnd: weekEnd,
        isPartial: weekStart.isBefore(start) || weekEnd.isAfter(end),
        firstTime: bucket.firstTime,
        returning: bucket.returning,
        unknown: bucket.unknown,
        firstTimeChange: previous == null
            ? null
            : bucket.firstTime - previous.firstTime,
        returningChange: previous == null
            ? null
            : bucket.returning - previous.returning,
        classifiedChange: previous == null
            ? null
            : bucket.classified - previous.classified,
      ),
    );
    previous = bucket;
  }

  return VisitClassificationWeeklyReport(
    startBusinessDate: startBusinessDate,
    endBusinessDate: endBusinessDate,
    rows: rows,
  );
}

bool _isEligibleVisitOrder(PosOrder order) {
  final type = normalizeOrderType(order.orderType);
  final isTrackedType =
      type == 'table' || type == takeoutOrderType || type == standingOrderType;
  final paid =
      order.status.trim().toLowerCase() == 'paid' ||
      order.paymentStatus.trim().toLowerCase() == 'paid';
  return isTrackedType && paid && !isCanonicalCancelledOrder(order);
}

class _VisitBucket {
  int firstTime = 0;
  int returning = 0;
  int unknown = 0;

  int get classified => firstTime + returning;
}

DateTime? _parseBusinessDate(String value) {
  try {
    return DateTime.parse(value);
  } on FormatException {
    return null;
  }
}

DateTime _weekStart(DateTime date) {
  final start = DateTime(date.year, date.month, date.day);
  return start.subtract(Duration(days: start.weekday - DateTime.monday));
}

String _key(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

String _displayDate(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

String _changeLabel(int? value) {
  if (value == null) return '-';
  if (value > 0) return '+$value';
  return '$value';
}

String _percentLabel(double value) => '${(value * 100).toStringAsFixed(1)}%';
