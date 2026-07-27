import 'package:flutter/foundation.dart';

class ReportPerformanceTracer {
  ReportPerformanceTracer({
    required this.reportName,
    required this.branchId,
    required this.startBusinessDate,
    required this.endBusinessDate,
    required this.cacheKey,
  }) : loadCount = _nextLoadCount(cacheKey);

  static final Map<String, int> _loadCounts = <String, int>{};

  final String reportName;
  final String branchId;
  final String startBusinessDate;
  final String endBusinessDate;
  final String cacheKey;
  final int loadCount;
  final Stopwatch _total = Stopwatch()..start();
  final Stopwatch _orders = Stopwatch();
  final Stopwatch _payments = Stopwatch();
  final Stopwatch _items = Stopwatch();
  final Stopwatch _processing = Stopwatch();

  int orderDocuments = 0;
  int paymentDocuments = 0;
  int itemDocuments = 0;
  int firestoreQueries = 0;

  static int _nextLoadCount(String key) {
    final count = (_loadCounts[key] ?? 0) + 1;
    _loadCounts[key] = count;
    return count;
  }

  Future<T> traceOrders<T>(
    Future<T> Function() action, {
    required int Function(T result) documents,
    required int queries,
  }) async {
    _orders.start();
    try {
      final result = await action();
      orderDocuments = documents(result);
      firestoreQueries += queries;
      return result;
    } finally {
      _orders.stop();
    }
  }

  Future<T> tracePayments<T>(
    Future<T> Function() action, {
    required int Function(T result) documents,
    required int queries,
  }) async {
    _payments.start();
    try {
      final result = await action();
      paymentDocuments = documents(result);
      firestoreQueries += queries;
      return result;
    } finally {
      _payments.stop();
    }
  }

  Future<T> traceItems<T>(
    Future<T> Function() action, {
    required int Function(T result) documents,
    required int queries,
  }) async {
    _items.start();
    try {
      final result = await action();
      itemDocuments = documents(result);
      firestoreQueries += queries;
      return result;
    } finally {
      _items.stop();
    }
  }

  T traceProcessing<T>(T Function() action) {
    _processing.start();
    try {
      return action();
    } finally {
      _processing.stop();
    }
  }

  void finish({
    required bool cacheUsed,
    bool sharedInFlight = false,
    int? cachedOrders,
    int? cachedPayments,
    int? cachedItems,
    int? cachedQueries,
    Map<String, Object?> extra = const {},
  }) {
    _total.stop();
    if (!kDebugMode) return;
    debugPrint(
      [
        'REPORT_PERF $reportName',
        'branch=$branchId',
        'range=$startBusinessDate..$endBusinessDate',
        'orders=${cachedOrders ?? orderDocuments}',
        'payments=${cachedPayments ?? paymentDocuments}',
        'items=${cachedItems ?? itemDocuments}',
        'queries=${cachedQueries ?? firestoreQueries}',
        'loads=$loadCount',
        'cache=$cacheUsed',
        'sharedInFlight=$sharedInFlight',
        'cacheKey=$cacheKey',
        'ordersMs=${_orders.elapsedMilliseconds}',
        'paymentsMs=${_payments.elapsedMilliseconds}',
        'itemsMs=${_items.elapsedMilliseconds}',
        'processingMs=${_processing.elapsedMilliseconds}',
        'totalMs=${_total.elapsedMilliseconds}',
        ...extra.entries.map((entry) => '${entry.key}=${entry.value}'),
      ].join('\n'),
    );
  }
}
