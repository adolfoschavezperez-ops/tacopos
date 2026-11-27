import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/reports/canonical_sales_summary.dart';
import '../../../models/order.dart';
import '../../../models/order_item.dart';
import '../../../models/payment.dart';
import '../../core/adapters/sales_adapter.dart';

class SalesCursorPage {
  const SalesCursorPage({
    required this.orders,
    required this.lastDocument,
    required this.hasNext,
    this.readCount = 0,
  });

  final List<PosOrder> orders;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasNext;
  final int readCount;
}

class SalesBoundedBatch {
  const SalesBoundedBatch({
    required this.orders,
    required this.readCount,
    required this.chunkCount,
    required this.truncated,
    this.wasCancelled = false,
  });

  final List<PosOrder> orders;
  final int readCount;
  final int chunkCount;
  final bool truncated;
  final bool wasCancelled;
}

class SaleDetailData {
  const SaleDetailData({
    required this.order,
    required this.items,
    required this.payments,
    required this.canonicalSummary,
  });

  final PosOrder order;
  final List<OrderItem> items;
  final List<Payment> payments;
  final CanonicalSalesSummary canonicalSummary;
}

/// Cursor-paginated Sales Repository.
///
/// Never downloads entire historical collections; pages in Firestore using
/// `limit(pageSize + 1)` and `startAfterDocument(cursor)`.
class SalesRepository {
  SalesRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<SalesCursorPage> fetchSalesPage({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
    String? statusFilter,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int pageSize = 20,
  }) async {
    final query = _buildOrdersQuery(
      restaurantId: restaurantId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      branchId: branchId,
      statusFilter: statusFilter,
    );

    final effectiveQuery = startAfter != null
        ? query.startAfterDocument(startAfter)
        : query;

    final snapshot = await effectiveQuery.limit(pageSize + 1).get();
    final hasNext = snapshot.docs.length > pageSize;
    final pageDocs = hasNext
        ? snapshot.docs.take(pageSize).toList(growable: false)
        : snapshot.docs;

    return SalesCursorPage(
      orders: pageDocs.map(PosOrder.fromDoc).toList(growable: false),
      lastDocument: pageDocs.isEmpty ? null : pageDocs.last,
      hasNext: hasNext,
      readCount: snapshot.docs.length,
    );
  }

  /// Bounded range search with cursor batching.
  ///
  /// When [maxSearchLimit] is reached, `truncated` is set to `true` so the UI
  /// informs the user that additional records exist in the selected range.
  Future<SalesBoundedBatch> searchOrdersInRange({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
    String? statusFilter,
    int pageSize = 200,
    int maxSearchLimit = 250,
    bool Function()? isCancelled,
  }) async {
    return _fetchRangeInChunks(
      restaurantId: restaurantId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      branchId: branchId,
      statusFilter: statusFilter,
      pageSize: pageSize,
      maxLimit: maxSearchLimit,
      isCancelled: isCancelled,
    );
  }

  /// Complete cursor-paginated bulk export for all authorized records in the
  /// selected date range.
  ///
  /// Processes in chunks of [pageSize], reports progress via [onProgress], and
  /// supports cooperative cancellation via [isCancelled]. Never marks a
  /// cancelled or capped export as complete (`truncated == true`).
  Future<SalesBoundedBatch> exportOrdersInRange({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
    String? statusFilter,
    int pageSize = 200,
    int? maxExportLimit,
    void Function(int loadedCount, int chunkCount)? onProgress,
    bool Function()? isCancelled,
  }) async {
    return _fetchRangeInChunks(
      restaurantId: restaurantId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      branchId: branchId,
      statusFilter: statusFilter,
      pageSize: pageSize,
      maxLimit: maxExportLimit,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  Future<SalesBoundedBatch> _fetchRangeInChunks({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
    String? statusFilter,
    required int pageSize,
    int? maxLimit,
    void Function(int loadedCount, int chunkCount)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final baseQuery = _buildOrdersQuery(
      restaurantId: restaurantId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      branchId: branchId,
      statusFilter: statusFilter,
    );

    final orders = <PosOrder>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    var readCount = 0;
    var chunkCount = 0;
    var truncated = false;
    var wasCancelled = false;

    while (true) {
      if (isCancelled?.call() == true) {
        wasCancelled = true;
        truncated = true;
        break;
      }

      var batchLimit = pageSize;
      if (maxLimit != null) {
        final remaining = maxLimit - orders.length;
        if (remaining <= 0) {
          truncated = true;
          break;
        }
        batchLimit = remaining < pageSize ? remaining : pageSize;
      }

      final effectiveQuery = cursor != null
          ? baseQuery.startAfterDocument(cursor)
          : baseQuery;
      final snapshot = await effectiveQuery.limit(batchLimit + 1).get();
      chunkCount += 1;
      readCount += snapshot.docs.length;

      final hasMore = snapshot.docs.length > batchLimit;
      final batchDocs = hasMore
          ? snapshot.docs.take(batchLimit).toList(growable: false)
          : snapshot.docs;

      orders.addAll(batchDocs.map(PosOrder.fromDoc));
      onProgress?.call(orders.length, chunkCount);

      if (!hasMore || batchDocs.isEmpty) {
        break;
      }
      if (maxLimit != null && orders.length >= maxLimit) {
        truncated = true;
        break;
      }
      cursor = batchDocs.last;
    }

    return SalesBoundedBatch(
      orders: orders,
      readCount: readCount,
      chunkCount: chunkCount,
      truncated: truncated,
      wasCancelled: wasCancelled,
    );
  }

  Query<Map<String, dynamic>> _buildOrdersQuery({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
    String? statusFilter,
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('orders')
        .where('businessDate', isGreaterThanOrEqualTo: startBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: endBusinessDate)
        .orderBy('businessDate', descending: true)
        .orderBy('createdAt', descending: true);

    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }
    if (statusFilter != null && statusFilter.isNotEmpty) {
      query = query.where('status', isEqualTo: statusFilter);
    }
    return query;
  }

  Future<SaleDetailData?> loadSaleDetail({
    required String restaurantId,
    required String orderId,
  }) async {
    final orderRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('orders')
        .doc(orderId);

    final orderSnap = await orderRef.get();
    if (!orderSnap.exists) return null;

    final order = PosOrder.fromDoc(orderSnap);
    final results = await Future.wait([
      orderRef.collection('items').get(),
      orderRef.collection('payments').get(),
    ]);

    final items = results[0].docs.map(OrderItem.fromDoc).toList(growable: false);
    final payments = results[1].docs
        .map(Payment.fromDoc)
        .toList(growable: false);

    final summary = BackofficeSalesAdapter.buildCanonicalSummary(
      orders: [order],
      itemsByOrder: {order.id: items},
      paymentsByOrder: {order.id: payments},
    );

    return SaleDetailData(
      order: order,
      items: items,
      payments: payments,
      canonicalSummary: summary,
    );
  }
}
