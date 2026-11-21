import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;

/// Full discover-and-commit attempts for one payment cancellation. Each attempt
/// rediscovers payments, items and discount usages from the server.
const int paymentCancellationMaxAttempts = 3;

/// The order changed between server discovery and the transaction. Nothing was
/// written; the caller must rediscover before trying again.
class PaymentCancellationConflict implements Exception {
  const PaymentCancellationConflict(this.reason);

  final String reason;

  @override
  String toString() => 'PaymentCancellationConflict: $reason';
}

enum PaymentCancellationOutcome {
  /// This call cancelled the payment.
  cancelled,

  /// The server already had the payment cancelled; nothing was written.
  alreadyCancelled,
}

class PaymentCancellationResult {
  const PaymentCancellationResult({
    required this.outcome,
    this.authoritativePendingTotal,
  });

  final PaymentCancellationOutcome outcome;

  /// Pending balance computed inside the committing transaction. Null when the
  /// payment was already cancelled.
  final double? authoritativePendingTotal;
}

/// Deep equality for Firestore document data. Maps and lists compare by
/// content; scalars, Timestamps, GeoPoints and references use `==`.
bool firestoreDataEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!firestoreDataEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!firestoreDataEquals(a[index], b[index])) return false;
    }
    return true;
  }
  return a == b;
}

/// The order fence: every field must be identical to the server discovery.
/// It also catches writers that do not increment `captureRevision`, but it
/// cannot see subcollection documents created without touching the order.
bool orderSnapshotUnchanged({
  required Map<String, dynamic>? discovered,
  required Map<String, dynamic>? current,
}) {
  if (discovered == null || current == null) return false;
  return firestoreDataEquals(discovered, current);
}

/// An authorization becomes available again only if it is still consumed by
/// the payment being cancelled. Another payment's use must never be released.
bool shouldRestoreDiscountAuthorization({
  required Map<String, dynamic>? authorization,
  required String paymentId,
}) {
  if (authorization == null) return false;
  final status = (authorization['status'] as String? ?? '')
      .trim()
      .toLowerCase();
  final usedPaymentId = (authorization['usedPaymentId'] as String? ?? '')
      .trim();
  final cleanPaymentId = paymentId.trim();
  return status == 'used' &&
      cleanPaymentId.isNotEmpty &&
      usedPaymentId == cleanPaymentId;
}

/// Discount usages are located by their `paymentId` (legacy +27 documents use
/// random IDs). Every active usage of this payment is cancelled, because each
/// one records a discount granted by the payment being voided. A usage tied to
/// another order is inconsistent data: refuse instead of guessing.
List<String> discountUsageIdsToCancel({
  required String orderId,
  required String paymentId,
  required Map<String, Map<String, dynamic>> usagesById,
}) {
  final cleanOrderId = orderId.trim();
  final cleanPaymentId = paymentId.trim();
  final ids = <String>[];
  for (final entry in usagesById.entries) {
    final data = entry.value;
    if ((data['paymentId'] as String? ?? '').trim() != cleanPaymentId) {
      continue;
    }
    final usageOrderId = (data['orderId'] as String? ?? '').trim();
    if (usageOrderId.isNotEmpty && usageOrderId != cleanOrderId) {
      throw StateError(
        'Un uso de descuento de este pago pertenece a otra orden. '
        'No se cancelo el pago; revisalo en Backoffice.',
      );
    }
    final status = (data['status'] as String? ?? '').trim().toLowerCase();
    if (status == 'active') ids.add(entry.key);
  }
  ids.sort();
  return ids;
}

/// Only order conflicts and exhausted SDK contention are retried. Permission,
/// index, configuration, validation and connectivity errors are surfaced.
bool isRetryablePaymentCancellationError(Object error) {
  if (error is PaymentCancellationConflict) return true;
  return error is FirebaseException && error.code == 'aborted';
}

bool isPaymentCancellationConnectivityError(Object error) {
  return error is FirebaseException &&
      const {'unavailable', 'deadline-exceeded'}.contains(error.code);
}

/// Deterministic activity identity: a retried or duplicated cancellation can
/// never append a second `payment_cancelled` record for the same payment.
String paymentCancellationActivityId({
  required String orderId,
  required String paymentId,
}) {
  return 'payment_cancelled_${orderId.trim()}_${paymentId.trim()}';
}

/// Operator-facing confirmation for a completed cancelPayment call.
String paymentCancellationSuccessMessage(PaymentCancellationOutcome outcome) {
  return switch (outcome) {
    PaymentCancellationOutcome.cancelled => 'Pago cancelado.',
    PaymentCancellationOutcome.alreadyCancelled =>
      'El pago ya había sido cancelado.',
  };
}

/// Operator-facing explanation of a cancellation that did not happen.
String paymentCancellationFailureMessage(Object error) {
  if (error is FirebaseException) {
    if (error.code == 'permission-denied') {
      return 'Firestore rechazo la cancelacion por permisos. '
          'No se cancelo el pago.';
    }
    return 'No se cancelo el pago (${error.code}). Intenta de nuevo.';
  }
  if (error is StateError) return error.message;
  if (error is ArgumentError) return '${error.message}';
  return 'No se cancelo el pago: $error';
}

enum OperatorPaymentCancellationStatus {
  /// The payment was cancelled and the administrative intervention recorded.
  cancelled,

  /// The payment was cancelled; only the administrative record failed.
  cancelledInterventionNotRecorded,

  /// The server already held the cancellation; nothing new was recorded.
  alreadyCancelled,

  /// No cancellation happened.
  failed,
}

class OperatorPaymentCancellationReport {
  const OperatorPaymentCancellationReport(this.status, this.message);

  final OperatorPaymentCancellationStatus status;
  final String message;

  bool get paymentIsCancelled =>
      status != OperatorPaymentCancellationStatus.failed;
}

/// Runs an operator cancellation and records the administrative intervention
/// only for a cancellation performed by this call. A failure to record it is
/// reported separately: the financial cancellation is already committed and
/// must not be retried or described as reverted.
Future<OperatorPaymentCancellationReport> runOperatorPaymentCancellation({
  required Future<PaymentCancellationResult> Function() cancel,
  Future<void> Function()? recordIntervention,
}) async {
  final PaymentCancellationResult result;
  try {
    result = await cancel();
  } catch (error) {
    return OperatorPaymentCancellationReport(
      OperatorPaymentCancellationStatus.failed,
      paymentCancellationFailureMessage(error),
    );
  }
  if (result.outcome == PaymentCancellationOutcome.alreadyCancelled) {
    return OperatorPaymentCancellationReport(
      OperatorPaymentCancellationStatus.alreadyCancelled,
      '${paymentCancellationSuccessMessage(result.outcome)} '
      'No se registro una nueva intervencion.',
    );
  }
  if (recordIntervention != null) {
    try {
      await recordIntervention();
    } catch (error) {
      return const OperatorPaymentCancellationReport(
        OperatorPaymentCancellationStatus.cancelledInterventionNotRecorded,
        'Pago cancelado. No se pudo registrar la intervencion administrativa; '
        'la cancelacion sigue vigente, no la repitas.',
      );
    }
  }
  return OperatorPaymentCancellationReport(
    OperatorPaymentCancellationStatus.cancelled,
    paymentCancellationSuccessMessage(result.outcome),
  );
}
