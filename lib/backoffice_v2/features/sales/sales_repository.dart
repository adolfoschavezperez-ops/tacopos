import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/orders/backoffice_sales_cancellation.dart';
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

  /// Atomically cancels a customer payment and recalculates order totals,
  /// preserving Android/1.0 cancellation contracts and writing an audit log.
  Future<void> cancelCustomerPayment({
    required String restaurantId,
    required String orderId,
    required String paymentId,
    required String reason,
    required String employeeId,
    required String employeeName,
  }) async {
    final cleanReason = reason.trim();
    if (!isValidCancellationReason(cleanReason)) {
      throw ArgumentError('Captura el motivo de cancelación.');
    }

    final orderRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('orders')
        .doc(orderId);
    final paymentRef = orderRef.collection('payments').doc(paymentId);
    final paymentsSnap = await orderRef.collection('payments').get();
    final itemsSnap = await orderRef.collection('items').get();
    final activityRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('activityLog')
        .doc();

    await _db.runTransaction((tx) async {
      final orderDoc = await tx.get(orderRef);
      final paymentDoc = await tx.get(paymentRef);
      if (!orderDoc.exists) throw StateError('La orden ya no existe.');
      if (!paymentDoc.exists) throw StateError('El pago ya no existe.');

      final freshPayments = <Payment>[];
      for (final pDoc in paymentsSnap.docs) {
        final fresh = await tx.get(pDoc.reference);
        if (fresh.exists) freshPayments.add(Payment.fromDoc(fresh));
      }
      final freshItems = <OrderItem>[];
      for (final iDoc in itemsSnap.docs) {
        final fresh = await tx.get(iDoc.reference);
        if (fresh.exists) freshItems.add(OrderItem.fromDoc(fresh));
      }

      final order = PosOrder.fromDoc(orderDoc);
      final payment = Payment.fromDoc(paymentDoc);
      if (isTerminalCancellationStatus(payment.status) ||
          payment.cancelledAt != null) {
        throw StateError('Este pago ya fue cancelado.');
      }

      final remainingActiveAmounts = freshPayments
          .where(
            (p) =>
                p.id != paymentId &&
                isBackofficeActivePayment(
                  status: p.status,
                  hasCancelledAt: p.cancelledAt != null,
                  appliedAmount: p.appliedAmount ?? p.baseAmount,
                ),
          )
          .map((p) => p.appliedAmount ?? p.baseAmount);

      final netTotal = order.netTotal ?? order.total;
      final totals = deriveCustomerPaymentCancellationTotals(
        orderNetTotal: netTotal,
        activePaymentAmounts: remainingActiveAmounts,
      );

      final hasActiveItems = freshItems.any(
        (item) => !isTerminalCancellationStatus(item.status),
      );
      final nextStatus = isTerminalCancellationStatus(order.status)
          ? order.status
          : totals.paymentStatus == 'paid'
          ? 'paid'
          : hasActiveItems
          ? 'open'
          : 'pending';

      final now = FieldValue.serverTimestamp();
      tx.update(paymentRef, {
        'status': 'cancelled',
        'cancelledAt': now,
        'cancelledByEmployeeId': employeeId,
        'cancelledByEmployeeName': employeeName,
        'cancelReason': cleanReason,
        'updatedAt': now,
      });

      tx.update(orderRef, {
        'paidTotal': totals.paidTotal,
        'pendingTotal': totals.pendingTotal,
        'paymentStatus': totals.paymentStatus,
        'status': nextStatus,
        'updatedAt': now,
      });

      tx.set(activityRef, {
        'id': activityRef.id,
        'restaurantId': restaurantId,
        'branchId': order.branchId,
        'branchName': order.branchName,
        'type': 'payment_cancelled',
        'actionType': 'payment_cancelled',
        'orderId': orderId,
        'paymentId': paymentId,
        'amount': payment.chargedAmount,
        'cancelReason': cleanReason,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'message':
            'Pago cancelado en orden ${BackofficeSalesAdapter.resolveFolioLabel(order)} (\$${payment.chargedAmount.toStringAsFixed(2)})',
        'timestamp': now,
        'createdAt': now,
      });
    });
  }

  /// Atomically cancels an order that has no remaining active payments.
  Future<void> cancelCustomerOrder({
    required String restaurantId,
    required String orderId,
    required String reason,
    required String employeeId,
    required String employeeName,
  }) async {
    final cleanReason = reason.trim();
    if (!isValidCancellationReason(cleanReason)) {
      throw ArgumentError('Captura el motivo de cancelación.');
    }

    final orderRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('orders')
        .doc(orderId);
    final paymentsSnap = await orderRef.collection('payments').get();
    final itemsSnap = await orderRef.collection('items').get();
    final activityRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('activityLog')
        .doc();

    await _db.runTransaction((tx) async {
      final orderDoc = await tx.get(orderRef);
      if (!orderDoc.exists) throw StateError('La orden ya no existe.');

      final freshPayments = <Payment>[];
      for (final pDoc in paymentsSnap.docs) {
        final fresh = await tx.get(pDoc.reference);
        if (fresh.exists) freshPayments.add(Payment.fromDoc(fresh));
      }
      final freshItems = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final iDoc in itemsSnap.docs) {
        final fresh = await tx.get(iDoc.reference);
        if (fresh.exists) freshItems.add(fresh);
      }

      final order = PosOrder.fromDoc(orderDoc);
      if (isTerminalCancellationStatus(order.status) ||
          order.cancelledAt != null ||
          order.canceledAt != null) {
        throw StateError('Esta orden ya fue cancelada.');
      }

      final activePaymentsTotal = freshPayments
          .where(
            (p) => isBackofficeActivePayment(
              status: p.status,
              hasCancelledAt: p.cancelledAt != null,
              appliedAmount: p.appliedAmount ?? p.baseAmount,
            ),
          )
          .fold<double>(
            0.0,
            (acc, p) => acc + (p.appliedAmount ?? p.baseAmount),
          );

      if (!canCancelBackofficeSale(activePaymentsTotal)) {
        throw StateError(
          'No puedes cancelar esta venta porque tiene pagos activos por \$${activePaymentsTotal.toStringAsFixed(2)}. Cancela primero los pagos.',
        );
      }

      final now = FieldValue.serverTimestamp();
      tx.update(orderRef, {
        'status': 'cancelled',
        'kitchenStatus': 'cancelled',
        'paymentStatus': 'cancelled',
        'cancelStatus': 'accepted',
        'cancelledAt': now,
        'cancelledByEmployeeId': employeeId,
        'cancelledByEmployeeName': employeeName,
        'cancelReason': cleanReason,
        'pendingTotal': 0.0,
        'paidTotal': 0.0,
        'updatedAt': now,
      });

      for (final itemDoc in freshItems) {
        final item = OrderItem.fromDoc(itemDoc);
        if (!isTerminalCancellationStatus(item.status)) {
          tx.update(itemDoc.reference, {
            'status': 'cancelled',
            'kitchenStatus': 'cancelled',
            'paymentStatus': 'cancelled',
            'cancelledAt': now,
            'cancelledByEmployeeId': employeeId,
            'cancelledByEmployeeName': employeeName,
            'cancelReason': cleanReason,
          });
        }
      }

      tx.set(activityRef, {
        'id': activityRef.id,
        'restaurantId': restaurantId,
        'branchId': order.branchId,
        'branchName': order.branchName,
        'type': 'order_cancelled',
        'actionType': 'order_cancelled',
        'orderId': orderId,
        'amount': order.total,
        'cancelReason': cleanReason,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'message':
            'Orden ${BackofficeSalesAdapter.resolveFolioLabel(order)} cancelada (\$${order.total.toStringAsFixed(2)})',
        'timestamp': now,
        'createdAt': now,
      });
    });
  }
}
