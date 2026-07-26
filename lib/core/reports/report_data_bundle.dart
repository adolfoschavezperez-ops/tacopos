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

class ReportDataRepository {
  ReportDataRepository({this.ttl = const Duration(seconds: 60)});

  final Duration ttl;
  final Map<ReportDataKey, _ReportDataCacheEntry> _cache = {};
  final Map<ReportDataKey, Future<ReportDataBundle>> _inFlight = {};

  Future<ReportDataLoadResult> load({
    required ReportDataKey key,
    required Future<ReportDataBundle> Function() loader,
    bool forceRefresh = false,
  }) async {
    final cached = _cache[key];
    if (!forceRefresh && cached != null && cached.isFresh(ttl)) {
      return ReportDataLoadResult(
        bundle: cached.bundle,
        fromCache: true,
        sharedInFlight: false,
      );
    }

    final pending = _inFlight[key];
    if (!forceRefresh && pending != null) {
      return ReportDataLoadResult(
        bundle: await pending,
        fromCache: false,
        sharedInFlight: true,
      );
    }

    final future = loader();
    _inFlight[key] = future;
    try {
      final bundle = await future;
      _cache[key] = _ReportDataCacheEntry(
        createdAt: DateTime.now(),
        bundle: bundle,
      );
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
      if (startBusinessDate != null &&
          key.startBusinessDate != startBusinessDate) {
        return false;
      }
      if (endBusinessDate != null && key.endBusinessDate != endBusinessDate) {
        return false;
      }
      return true;
    });
  }

  void clear() {
    _cache.clear();
  }
}

class _ReportDataCacheEntry {
  const _ReportDataCacheEntry({required this.createdAt, required this.bundle});

  final DateTime createdAt;
  final ReportDataBundle bundle;

  bool isFresh(Duration ttl) => DateTime.now().difference(createdAt) < ttl;
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
