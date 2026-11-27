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
  });

  final List<PosOrder> orders;
  final int readCount;
  final int chunkCount;
  final bool truncated;
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

  /// Bounded range search (strictly capped to prevent unbounded reads).
  Future<SalesBoundedBatch> searchOrdersInRange({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
    String? statusFilter,
    int maxSearchLimit = 250,
  }) async {
    final query = _buildOrdersQuery(
      restaurantId: restaurantId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      branchId: branchId,
      statusFilter: statusFilter,
    );
    final snapshot = await query.limit(maxSearchLimit + 1).get();
    final truncated = snapshot.docs.length > maxSearchLimit;
    final docs = truncated
        ? snapshot.docs.take(maxSearchLimit).toList(growable: false)
        : snapshot.docs;
    return SalesBoundedBatch(
      orders: docs.map(PosOrder.fromDoc).toList(growable: false),
      readCount: snapshot.docs.length,
      chunkCount: 1,
      truncated: truncated,
    );
  }

  /// Chunked cursor-paginated bulk export, bounded by [maxExportLimit].
  Future<SalesBoundedBatch> exportOrdersInRange({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
    String? statusFilter,
    int pageSize = 200,
    int maxExportLimit = 1000,
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

    while (orders.length < maxExportLimit) {
      final remaining = maxExportLimit - orders.length;
      final batchLimit = remaining < pageSize ? remaining : pageSize;
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
      if (!hasMore || batchDocs.isEmpty) {
        break;
      }
      if (orders.length >= maxExportLimit) {
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
