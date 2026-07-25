import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';

class OperationalOrderBlocker {
  const OperationalOrderBlocker({
    required this.order,
    required this.reason,
    required this.activeItemCount,
    required this.activePaymentCount,
  });

  final PosOrder order;
  final String reason;
  final int activeItemCount;
  final int activePaymentCount;
}

class OperationalOpenOrdersSummary {
  const OperationalOpenOrdersSummary({
    required this.businessDate,
    required this.branchId,
    required this.cashSessionId,
    required this.ordersChecked,
    required this.discardedReasons,
    required this.staleTableLinks,
    required this.releasedTableLinks,
    required this.blockers,
  });

  final String businessDate;
  final String branchId;
  final String cashSessionId;
  final int ordersChecked;
  final Map<String, int> discardedReasons;
  final int staleTableLinks;
  final int releasedTableLinks;
  final List<OperationalOrderBlocker> blockers;

  int get openTableCount =>
      blockers.where((row) => row.order.orderType != 'takeout').length;
  int get openTakeoutCount =>
      blockers.where((row) => row.order.orderType == 'takeout').length;
  int get pendingPaymentCount =>
      blockers.where((row) => row.order.pendingTotal > 0.02).length;
  bool get hasBlockers => blockers.isNotEmpty;
}

OperationalOrderBlocker? evaluateOperationalOrderBlocker({
  required PosOrder order,
  required List<OrderItem> items,
  required List<Payment> payments,
  required bool belongsToBranchAndDate,
}) {
  if (!belongsToBranchAndDate) return null;
  final status = _normalizeStatus(order.status);
  final paymentStatus = _normalizeStatus(order.paymentStatus);
  final kitchenStatus = _normalizeStatus(order.kitchenStatus);
  if (_inactiveOrderStatuses.contains(status) ||
      _inactiveOrderStatuses.contains(kitchenStatus) ||
      _inactivePaymentStatuses.contains(paymentStatus) ||
      order.cancelledAt != null ||
      order.canceledAt != null ||
      order.closedAt != null) {
    return null;
  }

  final activeItems = items.where(_isActiveOrderItem).toList();
  final activePayments = payments.where(_isActivePayment).toList();
  final hasPendingItems = activeItems.any((item) {
    final itemPaymentStatus = _normalizeStatus(item.paymentStatus);
    return !_inactivePaymentStatuses.contains(itemPaymentStatus);
  });
  final pendingBalance = order.pendingTotal > 0.02;
  final emptyOrder =
      activeItems.isEmpty &&
      activePayments.isEmpty &&
      order.sentToKitchenAt == null &&
      order.total.abs() <= 0.02 &&
      order.pendingTotal.abs() <= 0.02;
  if (emptyOrder) return null;

  final activeStatus =
      _activeOrderStatuses.contains(status) ||
      _activePaymentStatuses.contains(paymentStatus) ||
      pendingBalance ||
      hasPendingItems;
  if (!activeStatus) return null;
  if (!pendingBalance && !hasPendingItems) return null;

  final reasonParts = <String>[
    if (pendingBalance) 'saldo pendiente',
    if (hasPendingItems) 'items activos pendientes',
    if (_activeOrderStatuses.contains(status)) 'estado ${order.status}',
    if (_activePaymentStatuses.contains(paymentStatus))
      'pago ${order.paymentStatus}',
  ];
  return OperationalOrderBlocker(
    order: order,
    reason: reasonParts.isEmpty ? 'orden activa' : reasonParts.join(', '),
    activeItemCount: activeItems.length,
    activePaymentCount: activePayments.length,
  );
}

String operationalDiscardReason({
  required PosOrder order,
  required List<OrderItem> items,
  required List<Payment> payments,
  required bool belongsToBranchAndDate,
}) {
  if (!belongsToBranchAndDate) return 'otra sucursal o fecha operativa';
  final status = _normalizeStatus(order.status);
  final paymentStatus = _normalizeStatus(order.paymentStatus);
  final kitchenStatus = _normalizeStatus(order.kitchenStatus);
  if (_inactiveOrderStatuses.contains(status) ||
      _inactiveOrderStatuses.contains(kitchenStatus) ||
      _inactivePaymentStatuses.contains(paymentStatus) ||
      order.cancelledAt != null ||
      order.canceledAt != null ||
      order.closedAt != null) {
    return 'pagada/cancelada/cerrada';
  }
  final activeItems = items.where(_isActiveOrderItem).toList();
  final activePayments = payments.where(_isActivePayment).toList();
  if (activeItems.isEmpty &&
      activePayments.isEmpty &&
      order.sentToKitchenAt == null &&
      order.total.abs() <= 0.02 &&
      order.pendingTotal.abs() <= 0.02) {
    return 'orden vacia';
  }
  return 'sin saldo ni items pendientes';
}

const _activeOrderStatuses = {
  'open',
  'abierta',
  'sent',
  'enviada',
  'cooking',
  'en_preparacion',
  'ready',
  'lista',
  'partial',
  'parcial',
};

const _activePaymentStatuses = {'pending', 'pendiente', 'partial', 'parcial'};

const _inactiveOrderStatuses = {
  'paid',
  'pagada',
  'pagado',
  'closed',
  'cerrada',
  'cerrado',
  'cancelled',
  'canceled',
  'cancelada',
  'cancelado',
  'voided',
  'anulado',
  'anulada',
};

const _inactivePaymentStatuses = {
  'paid',
  'pagada',
  'pagado',
  'closed',
  'cerrada',
  'cerrado',
  'cancelled',
  'canceled',
  'cancelada',
  'cancelado',
};

String _normalizeStatus(Object? value) {
  return value
      .toString()
      .toLowerCase()
      .trim()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll('Ã¡', 'a')
      .replaceAll('Ã©', 'e')
      .replaceAll('Ã­', 'i')
      .replaceAll('Ã³', 'o')
      .replaceAll('Ãº', 'u')
      .replaceAll('Ã±', 'n');
}

bool _isActivePayment(Payment payment) {
  final status = _normalizeStatus(payment.status);
  return !_inactivePaymentStatuses.contains(status) &&
      payment.cancelledAt == null;
}

bool _isActiveOrderItem(OrderItem item) {
  final status = _normalizeStatus(item.status);
  final kitchenStatus = _normalizeStatus(item.kitchenStatus);
  final paymentStatus = _normalizeStatus(item.paymentStatus);
  final cancelStatus = _normalizeStatus(item.cancelStatus);
  return !_inactiveOrderStatuses.contains(status) &&
      !_inactiveOrderStatuses.contains(kitchenStatus) &&
      !_inactivePaymentStatuses.contains(paymentStatus) &&
      !_inactiveOrderStatuses.contains(cancelStatus) &&
      cancelStatus != 'accepted' &&
      item.cancelAcceptedAt == null &&
      item.cancelledAt == null;
}
