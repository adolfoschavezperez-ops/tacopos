const double backofficeCancellationTolerance = 0.02;

const _cancelledStatuses = {
  'cancelled',
  'canceled',
  'cancelado',
  'cancelada',
  'voided',
  'anulado',
  'anulada',
};

class CustomerPaymentCancellationTotals {
  const CustomerPaymentCancellationTotals({
    required this.paidTotal,
    required this.pendingTotal,
    required this.paymentStatus,
  });

  final double paidTotal;
  final double pendingTotal;
  final String paymentStatus;
}

class BackofficeCancellationGuard {
  bool _active = false;

  bool get isActive => _active;

  bool tryStart() {
    if (_active) return false;
    _active = true;
    return true;
  }

  void release() {
    _active = false;
  }
}

bool hasBackofficeCancellationPermission({
  required bool specificPermission,
  required bool canViewAdmin,
  required bool hasAdminAccess,
}) {
  return specificPermission || canViewAdmin || hasAdminAccess;
}

bool isValidCancellationReason(String reason) => reason.trim().isNotEmpty;

bool isTerminalCancellationStatus(String status) {
  return _cancelledStatuses.contains(_normalize(status));
}

bool isBackofficeActivePayment({
  required String status,
  required bool hasCancelledAt,
  required double appliedAmount,
}) {
  return !isTerminalCancellationStatus(status) &&
      !hasCancelledAt &&
      appliedAmount > backofficeCancellationTolerance;
}

bool canCancelBackofficeSale(double activePaymentsTotal) {
  return activePaymentsTotal <= backofficeCancellationTolerance;
}

CustomerPaymentCancellationTotals deriveCustomerPaymentCancellationTotals({
  required double orderNetTotal,
  required Iterable<double> activePaymentAmounts,
}) {
  final netTotal = _money(orderNetTotal.clamp(0, double.infinity).toDouble());
  final paidTotal = _money(
    activePaymentAmounts.fold<double>(
      0,
      (total, amount) => total + amount.clamp(0, double.infinity).toDouble(),
    ),
  );
  final pendingTotal = _money(
    (netTotal - paidTotal).clamp(0, double.infinity).toDouble(),
  );
  final paymentStatus = paidTotal <= backofficeCancellationTolerance
      ? 'pending'
      : pendingTotal <= backofficeCancellationTolerance
      ? 'paid'
      : 'partial';
  return CustomerPaymentCancellationTotals(
    paidTotal: paidTotal,
    pendingTotal: pendingTotal,
    paymentStatus: paymentStatus,
  );
}

String deriveOrderStatusAfterCustomerPaymentCancellation({
  required String currentOrderStatus,
  required String paymentStatus,
  required bool hasActiveItems,
  required Iterable<String> activeKitchenStatuses,
}) {
  if (paymentStatus == 'paid') return 'paid';
  final current = _normalize(currentOrderStatus);
  if (hasActiveItems &&
      !_cancelledStatuses.contains(current) &&
      !const {'paid', 'closed', 'cerrado', 'cerrada'}.contains(current)) {
    return current;
  }
  if (!hasActiveItems) return 'open';

  final kitchenStatuses = activeKitchenStatuses.map(_normalize).toSet();
  if (kitchenStatuses.contains('cooking')) return 'cooking';
  if (kitchenStatuses.contains('sent') ||
      kitchenStatuses.contains('pending') ||
      kitchenStatuses.contains('cancel_requested')) {
    return 'sent';
  }
  if (kitchenStatuses.contains('ready')) return 'ready';
  return 'open';
}

bool shouldReleaseBackofficeCancelledOrderTable({
  required String? currentOrderId,
  required String cancelledOrderId,
}) {
  return currentOrderId?.trim() == cancelledOrderId.trim();
}

double _money(double value) => (value * 100).roundToDouble() / 100;

String _normalize(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');
}
