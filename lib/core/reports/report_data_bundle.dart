import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';
import 'canonical_sales_summary.dart';

class ReportDataKey {
  const ReportDataKey({
    required this.restaurantId,
    required this.branchId,
    required this.startBusinessDate,
    required this.endBusinessDate,
    required this.includeItems,
  });

  final String restaurantId;
  final String branchId;
  final String startBusinessDate;
  final String endBusinessDate;
  final bool includeItems;

  String get value => [
    restaurantId,
    branchId,
    startBusinessDate,
    endBusinessDate,
    includeItems ? 'full' : 'summary',
  ].join('|');

  ReportDataKey copyWith({
    String? restaurantId,
    String? branchId,
    String? startBusinessDate,
    String? endBusinessDate,
    bool? includeItems,
  }) {
    return ReportDataKey(
      restaurantId: restaurantId ?? this.restaurantId,
      branchId: branchId ?? this.branchId,
      startBusinessDate: startBusinessDate ?? this.startBusinessDate,
      endBusinessDate: endBusinessDate ?? this.endBusinessDate,
      includeItems: includeItems ?? this.includeItems,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReportDataKey &&
        restaurantId == other.restaurantId &&
        branchId == other.branchId &&
        startBusinessDate == other.startBusinessDate &&
        endBusinessDate == other.endBusinessDate &&
        includeItems == other.includeItems;
  }

  @override
  int get hashCode => Object.hash(
    restaurantId,
    branchId,
    startBusinessDate,
    endBusinessDate,
    includeItems,
  );
}

class ReportDataBundle {
  const ReportDataBundle({
    required this.key,
    required this.orders,
    required this.payments,
    required this.paymentsByOrder,
    required this.itemsByOrder,
    required this.canonicalSummary,
    required this.firestoreQueries,
    required this.orderDocuments,
    required this.paymentDocuments,
    required this.itemDocuments,
    this.loadedAt,
    this.fromCache = false,
    this.sharedInFlight = false,
    this.cacheHits = 0,
    this.cacheMisses = 0,
    this.listenerCount = 0,
  });

  final ReportDataKey key;
  final List<PosOrder> orders;
  final List<Payment> payments;
  final Map<String, List<Payment>> paymentsByOrder;
  final Map<String, List<OrderItem>> itemsByOrder;
  final CanonicalSalesSummary? canonicalSummary;
  final int firestoreQueries;
  final int orderDocuments;
  final int paymentDocuments;
  final int itemDocuments;
  final DateTime? loadedAt;
  final bool fromCache;
  final bool sharedInFlight;
  final int cacheHits;
  final int cacheMisses;
  final int listenerCount;

  bool get hasLiveData =>
      startAndEndDates(key).any(ReportDataRepository.isCurrentBusinessDate);

  ReportDataBundle withCacheMetadata({
    DateTime? loadedAt,
    bool? fromCache,
    bool? sharedInFlight,
    int? cacheHits,
    int? cacheMisses,
    int? listenerCount,
  }) {
    return ReportDataBundle(
      key: key,
      orders: orders,
      payments: payments,
      paymentsByOrder: paymentsByOrder,
      itemsByOrder: itemsByOrder,
      canonicalSummary: canonicalSummary,
      firestoreQueries: firestoreQueries,
      orderDocuments: orderDocuments,
      paymentDocuments: paymentDocuments,
      itemDocuments: itemDocuments,
      loadedAt: loadedAt ?? this.loadedAt,
      fromCache: fromCache ?? this.fromCache,
      sharedInFlight: sharedInFlight ?? this.sharedInFlight,
      cacheHits: cacheHits ?? this.cacheHits,
      cacheMisses: cacheMisses ?? this.cacheMisses,
      listenerCount: listenerCount ?? this.listenerCount,
    );
  }
}

class ReportDataLoadResult {
  const ReportDataLoadResult({
    required this.bundle,
    required this.fromCache,
    required this.sharedInFlight,
  });

  final ReportDataBundle bundle;
  final bool fromCache;
  final bool sharedInFlight;
}

class BackofficeReportDiagnostics {
  const BackofficeReportDiagnostics({
    required this.firestoreQueries,
    required this.documentsReceived,
    required this.cacheHits,
    required this.cacheMisses,
    required this.listenersCreated,
    required this.listenersReused,
    required this.datasetsReused,
    required this.inFlightReused,
  });

  final int firestoreQueries;
  final int documentsReceived;
  final int cacheHits;
  final int cacheMisses;
  final int listenersCreated;
  final int listenersReused;
  final int datasetsReused;
  final int inFlightReused;
}

class ReportDataRepository {
  ReportDataRepository({
    this.currentTtl = const Duration(seconds: 45),
    this.historicalTtl = const Duration(hours: 8),
    String Function()? currentBusinessDateProvider,
  }) : _currentBusinessDateProvider =
           currentBusinessDateProvider ?? _defaultBusinessDate;

  final Duration currentTtl;
  final Duration historicalTtl;
  final String Function() _currentBusinessDateProvider;
  final Map<ReportDataKey, _ReportDataCacheEntry> _cache = {};
  final Map<ReportDataKey, Future<ReportDataBundle>> _inFlight = {};
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _inFlightReused = 0;
  int _datasetsReused = 0;

  Future<ReportDataLoadResult> load({
    required ReportDataKey key,
    required Future<ReportDataBundle> Function() loader,
    bool forceRefresh = false,
  }) async {
    final cached = _cache[key];
    if (!forceRefresh && cached != null && cached.isFresh(_ttlForKey(key))) {
      _cacheHits++;
      return ReportDataLoadResult(
        bundle: cached.bundle.withCacheMetadata(
          fromCache: true,
          sharedInFlight: false,
          cacheHits: 1,
          cacheMisses: 0,
          loadedAt: cached.createdAt,
        ),
        fromCache: true,
        sharedInFlight: false,
      );
    }

    final pending = _inFlight[key];
    if (!forceRefresh && pending != null) {
      _inFlightReused++;
      return ReportDataLoadResult(
        bundle: (await pending).withCacheMetadata(
          fromCache: false,
          sharedInFlight: true,
          cacheHits: 0,
          cacheMisses: 0,
        ),
        fromCache: false,
        sharedInFlight: true,
      );
    }

    _cacheMisses++;
    final future = loader();
    _inFlight[key] = future;
    try {
      final loadedAt = DateTime.now();
      final bundle = (await future).withCacheMetadata(
        loadedAt: loadedAt,
        fromCache: false,
        sharedInFlight: false,
        cacheHits: 0,
        cacheMisses: 1,
      );
      _cache[key] = _ReportDataCacheEntry(createdAt: loadedAt, bundle: bundle);
      return ReportDataLoadResult(
        bundle: bundle,
        fromCache: false,
        sharedInFlight: false,
      );
    } finally {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    }
  }

  Future<ReportDataLoadResult> loadRange({
    required ReportDataKey key,
    required Future<ReportDataBundle> Function(ReportDataKey key) dayLoader,
    bool forceRefresh = false,
  }) async {
    final days = startAndEndDates(key);
    if (days.length <= 1) {
      return load(
        key: key,
        forceRefresh: forceRefresh,
        loader: () => dayLoader(key),
      );
    }

    final results = await Future.wait(
      days.map((day) {
        final dayKey = key.copyWith(
          startBusinessDate: day,
          endBusinessDate: day,
        );
        return load(
          key: dayKey,
          forceRefresh: forceRefresh,
          loader: () => dayLoader(dayKey),
        );
      }),
    );
    final bundles = results.map((result) => result.bundle).toList();
    final merged = mergeReportDataBundles(key: key, bundles: bundles);
    final cacheHits = results.where((result) => result.fromCache).length;
    final shared = results.where((result) => result.sharedInFlight).length;
    final misses = results.length - cacheHits - shared;
    if (cacheHits > 0 || shared > 0) {
      _datasetsReused += cacheHits + shared;
    }
    return ReportDataLoadResult(
      bundle: merged.withCacheMetadata(
        loadedAt: bundles
            .map((bundle) => bundle.loadedAt)
            .whereType<DateTime>()
            .fold<DateTime?>(
              null,
              (latest, value) =>
                  latest == null || value.isAfter(latest) ? value : latest,
            ),
        fromCache: misses == 0,
        sharedInFlight: shared > 0,
        cacheHits: cacheHits,
        cacheMisses: misses,
      ),
      fromCache: misses == 0,
      sharedInFlight: shared > 0,
    );
  }

  void invalidate({
    String? restaurantId,
    String? branchId,
    String? startBusinessDate,
    String? endBusinessDate,
  }) {
    _cache.removeWhere((key, _) {
      if (restaurantId != null && key.restaurantId != restaurantId) {
        return false;
      }
      if (branchId != null && key.branchId != branchId) return false;
      if (startBusinessDate != null || endBusinessDate != null) {
        final start = startBusinessDate ?? endBusinessDate!;
        final end = endBusinessDate ?? startBusinessDate!;
        if (key.endBusinessDate.compareTo(start) < 0 ||
            key.startBusinessDate.compareTo(end) > 0) {
          return false;
        }
      }
      return true;
    });
  }

  void clear() {
    _cache.clear();
  }

  BackofficeReportDiagnostics diagnosticsSnapshot() {
    final documents = _cache.values.fold<int>(0, (total, entry) {
      final bundle = entry.bundle;
      return total +
          bundle.orderDocuments +
          bundle.paymentDocuments +
          bundle.itemDocuments;
    });
    final queries = _cache.values.fold<int>(
      0,
      (total, entry) => total + entry.bundle.firestoreQueries,
    );
    return BackofficeReportDiagnostics(
      firestoreQueries: queries,
      documentsReceived: documents,
      cacheHits: _cacheHits,
      cacheMisses: _cacheMisses,
      listenersCreated: 0,
      listenersReused: 0,
      datasetsReused: _datasetsReused,
      inFlightReused: _inFlightReused,
    );
  }

  Duration _ttlForKey(ReportDataKey key) {
    final days = startAndEndDates(key);
    return days.any((day) => day == _currentBusinessDateProvider())
        ? currentTtl
        : historicalTtl;
  }

  static bool isCurrentBusinessDate(String value) =>
      value == _defaultBusinessDate();
}

class _ReportDataCacheEntry {
  const _ReportDataCacheEntry({required this.createdAt, required this.bundle});

  final DateTime createdAt;
  final ReportDataBundle bundle;

  bool isFresh(Duration ttl) => DateTime.now().difference(createdAt) < ttl;
}

List<String> startAndEndDates(ReportDataKey key) {
  final start = DateTime.parse(key.startBusinessDate);
  final end = DateTime.parse(key.endBusinessDate);
  final days = <String>[];
  for (
    var cursor = DateTime(start.year, start.month, start.day);
    !cursor.isAfter(end);
    cursor = cursor.add(const Duration(days: 1))
  ) {
    days.add(_businessDate(cursor));
  }
  return days;
}

ReportDataBundle mergeReportDataBundles({
  required ReportDataKey key,
  required Iterable<ReportDataBundle> bundles,
}) {
  final orderById = <String, PosOrder>{};
  final paymentsByKey = <String, Payment>{};
  final paymentsByOrder = <String, List<Payment>>{};
  final itemsByOrder = <String, List<OrderItem>>{};
  var firestoreQueries = 0;
  var orderDocuments = 0;
  var paymentDocuments = 0;
  var itemDocuments = 0;

  for (final bundle in bundles) {
    firestoreQueries += bundle.firestoreQueries;
    orderDocuments += bundle.orderDocuments;
    paymentDocuments += bundle.paymentDocuments;
    itemDocuments += bundle.itemDocuments;
    for (final order in bundle.orders) {
      orderById[order.id] = order;
    }
    for (final payment in bundle.payments) {
      paymentsByKey['${payment.orderId}|${payment.id}'] = payment;
    }
    for (final entry in bundle.paymentsByOrder.entries) {
      paymentsByOrder
          .putIfAbsent(entry.key, () => <Payment>[])
          .addAll(entry.value);
    }
    for (final entry in bundle.itemsByOrder.entries) {
      itemsByOrder
          .putIfAbsent(entry.key, () => <OrderItem>[])
          .addAll(entry.value);
    }
  }

  final orders = orderById.values.toList()
    ..sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
  final payments = paymentsByKey.values.toList()
    ..sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
  final canonicalSummary = key.includeItems
      ? buildCanonicalSalesSummary(
          orders.map(
            (order) => SalesOrderBundleInput(
              order: order,
              items: itemsByOrder[order.id] ?? const [],
              payments: paymentsByOrder[order.id] ?? const [],
            ),
          ),
        )
      : null;

  return ReportDataBundle(
    key: key,
    orders: orders,
    payments: payments,
    paymentsByOrder: paymentsByOrder,
    itemsByOrder: itemsByOrder,
    canonicalSummary: canonicalSummary,
    firestoreQueries: firestoreQueries,
    orderDocuments: orderDocuments,
    paymentDocuments: paymentDocuments,
    itemDocuments: itemDocuments,
  );
}

String _defaultBusinessDate() => _businessDate(DateTime.now());

String _businessDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

Future<List<R>> runInBatches<T, R>(
  Iterable<T> items, {
  int batchSize = 15,
  required Future<R> Function(T item) action,
}) async {
  if (batchSize < 1) {
    throw ArgumentError.value(batchSize, 'batchSize', 'Debe ser mayor a cero.');
  }
  final source = items.toList(growable: false);
  final results = <R>[];
  for (var offset = 0; offset < source.length; offset += batchSize) {
    final end = (offset + batchSize).clamp(0, source.length);
    results.addAll(await Future.wait(source.sublist(offset, end).map(action)));
  }
  return results;
}
