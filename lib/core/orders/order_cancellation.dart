import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;

import '../payments/payment_cancellation.dart' show firestoreDataEquals;

/// Commit attempts for one confirmed cancellation. Only technical contention
/// (`aborted`) on an unchanged confirmed scope is retried.
const int orderMutationMaxAttempts = 3;

const String orderCancellationScopeChangedMessage =
    'La orden cambio mientras intentabas cancelarla. Revisa los productos y '
    'vuelve a confirmar.';

const String emptyOrderCloseScopeChangedMessage =
    'La orden cambio mientras intentabas cerrarla. Revisa la orden y vuelve a '
    'confirmar.';

enum OrderCancellationKind { cancelOrder, closeEmptyOrder }

/// Immutable identity of what the operator reviewed and confirmed: the order
/// document, its items and payments exactly as read from the server before
/// the confirmation dialog. A cancellation may only commit while the server
/// still holds this same state; it never widens to documents the operator did
/// not see.
class OrderCancellationScope {
  OrderCancellationScope({
    required this.kind,
    required this.orderId,
    required this.captureRevision,
    required Map<String, dynamic> orderData,
    required Map<String, Map<String, dynamic>> itemsById,
    required Map<String, Map<String, dynamic>> paymentsById,
    required this.itemsToCancelCount,
    required this.itemsToCancelTotal,
  }) : orderData = _frozenMap(orderData),
       itemsById = Map.unmodifiable({
         for (final entry in itemsById.entries)
           entry.key: _frozenMap(entry.value),
       }),
       paymentsById = Map.unmodifiable({
         for (final entry in paymentsById.entries)
           entry.key: _frozenMap(entry.value),
       });

  final OrderCancellationKind kind;
  final String orderId;
  final int captureRevision;
  final Map<String, dynamic> orderData;
  final Map<String, Map<String, dynamic>> itemsById;
  final Map<String, Map<String, dynamic>> paymentsById;

  /// Items the confirmed cancellation will cancel, shown to the operator.
  final int itemsToCancelCount;
  final double itemsToCancelTotal;

  String get changedMessage => kind == OrderCancellationKind.cancelOrder
      ? orderCancellationScopeChangedMessage
      : emptyOrderCloseScopeChangedMessage;
}

/// The server no longer holds the confirmed scope. Nothing was written and the
/// operation must not be retried without a new confirmation.
class OrderCancellationScopeChanged extends StateError {
  OrderCancellationScopeChanged(this.reason, String message) : super(message);

  /// Technical description of the first difference found (for logs/tests).
  final String reason;
}

/// Returns null when the current server documents equal the confirmed scope,
/// otherwise the first difference. Item and payment sets must match exactly:
/// a new, removed or modified document requires a new confirmation.
String? describeScopeChange({
  required OrderCancellationScope scope,
  required int currentRevision,
  required Map<String, dynamic>? currentOrderData,
  required Map<String, Map<String, dynamic>> currentItemsById,
  required Map<String, Map<String, dynamic>> currentPaymentsById,
}) {
  if (currentOrderData == null) return 'order-missing';
  if (currentRevision != scope.captureRevision) return 'order-revision';
  if (!firestoreDataEquals(scope.orderData, currentOrderData)) {
    return 'order-fields';
  }
  final itemChange = _describeSetChange(
    'item',
    scope.itemsById,
    currentItemsById,
  );
  if (itemChange != null) return itemChange;
  return _describeSetChange('payment', scope.paymentsById, currentPaymentsById);
}

/// Only the document IDs; used to reject a changed scope before reading.
String? describeScopeIdChange({
  required OrderCancellationScope scope,
  required Iterable<String> currentItemIds,
  required Iterable<String> currentPaymentIds,
}) {
  final items = currentItemIds.toSet();
  final payments = currentPaymentIds.toSet();
  if (!_sameIds(scope.itemsById.keys, items)) return 'item-set';
  if (!_sameIds(scope.paymentsById.keys, payments)) return 'payment-set';
  return null;
}

bool isRetryableOrderMutationError(Object error) {
  return error is FirebaseException && error.code == 'aborted';
}

bool isOrderMutationConnectivityError(Object error) {
  return error is FirebaseException &&
      const {'unavailable', 'deadline-exceeded'}.contains(error.code);
}

/// Deterministic identity of the single `order_cancelled` event of an order.
/// A whole-order cancellation records its cancelled items inside this event
/// (`cancelledItems`) instead of one event per item.
String orderCancelledActivityId(String orderId) =>
    'order_cancelled_${orderId.trim()}';

/// Conservative write budget for one atomic cancellation transaction.
///
/// Current Firestore docs list no per-transaction write count (only 10 MiB per
/// request, 270 s per transaction, a 20 s lock deadline and 500 field
/// transforms per document), while the historical client limit was 500 writes
/// with each field transform counted as an extra write. Until the production
/// limit is verified on the Android SDK, a cancellation must fit 500 under
/// that stricter accounting.
const int orderCancellationWriteBudget = 500;

/// Cost of [documentWrites] under the strict accounting: every cancellation
/// write carries a `serverTimestamp` (and the order an `increment`), so each
/// document counts as one write plus one transform write.
int conservativeTransactionWriteCost(int documentWrites) => documentWrites * 2;

/// The cancellation cannot be applied atomically within the write budget.
/// Raised before any write; the order is left untouched.
class OrderCancellationTooLarge extends StateError {
  OrderCancellationTooLarge({
    required this.documentWrites,
    required this.itemCount,
  }) : super(
         'Esta orden tiene demasiados productos ($itemCount) para cancelarse '
         'en una sola operacion segura. No se hizo ningun cambio; solicita '
         'apoyo de un administrador.',
       );

  final int documentWrites;
  final int itemCount;

  int get conservativeCost => conservativeTransactionWriteCost(documentWrites);
}

/// Throws [OrderCancellationTooLarge] when [documentWrites] exceeds the
/// conservative budget.
void ensureCancellationWithinWriteBudget({
  required int documentWrites,
  required int itemCount,
}) {
  if (conservativeTransactionWriteCost(documentWrites) >
      orderCancellationWriteBudget) {
    throw OrderCancellationTooLarge(
      documentWrites: documentWrites,
      itemCount: itemCount,
    );
  }
}

class OrderCancellationResult {
  const OrderCancellationResult({
    required this.outcome,
    this.releasedTableIds = const [],
    this.skippedTableIds = const [],
  });

  final OrderCancellationOutcome outcome;

  /// Tables released by this call because they still pointed to the order.
  final List<String> releasedTableIds;

  /// Tables linked by the order but already owned by another order or
  /// missing. They were left untouched and recorded in the activity log.
  final List<String> skippedTableIds;
}

enum OrderCancellationOutcome {
  /// This call cancelled the order.
  cancelled,

  /// The server already had the order cancelled; nothing was written.
  alreadyCancelled,
}

class TableReleasePlan {
  const TableReleasePlan({required this.release, required this.skipped});

  final List<String> release;
  final List<String> skipped;
}

/// Decides which tables a cancelled order may release, from the table
/// documents read inside the transaction. A table is released only while its
/// current owner is this order; a table owned by another order, or missing, is
/// never written and is reported as skipped.
///
/// [currentOrderIdByTable] maps every candidate table ID to its current
/// `currentOrderId` (null or empty when free); a missing key means the table
/// document does not exist.
TableReleasePlan planTableRelease({
  required String orderId,
  required Iterable<String> candidateTableIds,
  required Map<String, String?> currentOrderIdByTable,
}) {
  final cleanOrderId = orderId.trim();
  final release = <String>[];
  final skipped = <String>[];
  final seen = <String>{};
  for (final rawId in candidateTableIds) {
    final tableId = rawId.trim();
    if (tableId.isEmpty || !seen.add(tableId)) continue;
    if (!currentOrderIdByTable.containsKey(tableId)) {
      skipped.add(tableId);
      continue;
    }
    final owner = currentOrderIdByTable[tableId]?.trim() ?? '';
    if (owner == cleanOrderId) {
      release.add(tableId);
    } else if (owner.isNotEmpty) {
      skipped.add(tableId);
    }
    // A free table needs no write.
  }
  return TableReleasePlan(release: release, skipped: skipped);
}

String? _describeSetChange(
  String label,
  Map<String, Map<String, dynamic>> confirmed,
  Map<String, Map<String, dynamic>> current,
) {
  for (final id in current.keys) {
    if (!confirmed.containsKey(id)) return '$label-added:$id';
  }
  for (final entry in confirmed.entries) {
    final now = current[entry.key];
    if (now == null) return '$label-removed:${entry.key}';
    if (!firestoreDataEquals(entry.value, now)) {
      return '$label-changed:${entry.key}';
    }
  }
  return null;
}

bool _sameIds(Iterable<String> a, Set<String> b) {
  final setA = a.toSet();
  return setA.length == b.length && setA.containsAll(b);
}

Map<String, dynamic> _frozenMap(Map<String, dynamic> source) =>
    Map.unmodifiable({
      for (final entry in source.entries) entry.key: _frozen(entry.value),
    });

Object? _frozen(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final entry in value.entries) '${entry.key}': _frozen(entry.value),
    });
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_frozen));
  return value;
}
