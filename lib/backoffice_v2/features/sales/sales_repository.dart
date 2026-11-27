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
  });

  final List<PosOrder> orders;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasNext;
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
    );
  }

  /// Bounded full-range fetch for full-set search and complete CSV export.
  Future<List<PosOrder>> fetchOrdersInRange({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
    String? statusFilter,
    int limit = 600,
  }) async {
    final query = _buildOrdersQuery(
      restaurantId: restaurantId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      branchId: branchId,
      statusFilter: statusFilter,
    );
    final snapshot = await query.limit(limit).get();
    return snapshot.docs.map(PosOrder.fromDoc).toList(growable: false);
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
