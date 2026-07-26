import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';
import '../../models/pos_table.dart';
import 'order_types.dart';

const double ghostOrderTolerance = 0.02;

const _cancelledStatuses = {
  'cancelled',
  'canceled',
  'cancelado',
  'cancelada',
  'voided',
  'anulado',
  'anulada',
};

const _paidStatuses = {
  'paid',
  'pagado',
  'pagada',
  'closed',
  'cerrado',
  'cerrada',
};

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

class GhostOrderEvaluation {
  const GhostOrderEvaluation({
    required this.isGhost,
    required this.activeItemsCount,
    required this.activePaymentsCount,
    required this.cancelledItemsCount,
    required this.activeItemsTotal,
  });

  final bool isGhost;
  final int activeItemsCount;
  final int activePaymentsCount;
  final int cancelledItemsCount;
  final double activeItemsTotal;
}

String normalizeOperationalStatus(Object? value) {
  return value
      .toString()
      .toLowerCase()
      .trim()
      .replaceAll('\u00e1', 'a')
      .replaceAll('\u00e9', 'e')
      .replaceAll('\u00ed', 'i')
      .replaceAll('\u00f3', 'o')
      .replaceAll('\u00fa', 'u')
      .replaceAll('\u00f1', 'n')
      .replaceAll('\u00c3\u00a1', 'a')
      .replaceAll('\u00c3\u00a9', 'e')
      .replaceAll('\u00c3\u00ad', 'i')
      .replaceAll('\u00c3\u00b3', 'o')
      .replaceAll('\u00c3\u00ba', 'u')
      .replaceAll('\u00c3\u00b1', 'n');
}

bool isCancelledOrder(PosOrder order) {
  return _cancelledStatuses.contains(
        normalizeOperationalStatus(order.status),
      ) ||
      _cancelledStatuses.contains(
        normalizeOperationalStatus(order.kitchenStatus),
      ) ||
      _cancelledStatuses.contains(
        normalizeOperationalStatus(order.paymentStatus),
      ) ||
      order.cancelledAt != null ||
      order.canceledAt != null;
}

bool isPaidOrder(PosOrder order) {
  return _paidStatuses.contains(normalizeOperationalStatus(order.status)) ||
      _paidStatuses.contains(normalizeOperationalStatus(order.paymentStatus)) ||
      order.closedAt != null ||
      (order.paidAt != null && order.pendingTotal.abs() <= ghostOrderTolerance);
}

bool isActiveOrderState(PosOrder order) {
  return !isCancelledOrder(order) && !isPaidOrder(order);
}

bool isActiveOrderItem(OrderItem item) {
  final status = normalizeOperationalStatus(item.status);
  final kitchenStatus = normalizeOperationalStatus(item.kitchenStatus);
  final cancelStatus = normalizeOperationalStatus(item.cancelStatus);
  return !_cancelledStatuses.contains(status) &&
      !_cancelledStatuses.contains(kitchenStatus) &&
      !_cancelledStatuses.contains(cancelStatus) &&
      cancelStatus != 'accepted' &&
      item.cancelledAt == null &&
      item.cancelAcceptedAt == null;
}

double activeCustomerPaymentAmount(Payment payment) {
  final cashNet =
      (payment.cashReceivedAmount ?? 0) - (payment.cashChangeAmount ?? 0);
  return [
    payment.appliedAmount ?? 0,
    payment.chargedAmount,
    payment.baseAmount,
    payment.totalAfterDiscount,
    cashNet,
  ].fold<double>(0, (largest, value) => value > largest ? value : largest);
}

bool isActiveCustomerPayment(Payment payment) {
  final status = normalizeOperationalStatus(payment.status);
  return !_cancelledStatuses.contains(status) &&
      payment.cancelledAt == null &&
      activeCustomerPaymentAmount(payment) > ghostOrderTolerance;
}

bool isActivePayment(Payment payment) => isActiveCustomerPayment(payment);

GhostOrderEvaluation evaluateGhostOrder(
  PosOrder order,
  Iterable<OrderItem> items,
  Iterable<Payment> payments,
) {
  final itemList = items.toList(growable: false);
  final activeItems = itemList.where(isActiveOrderItem).toList();
  final activePayments = payments
      .where(isActiveCustomerPayment)
      .toList(growable: false);
  final activeItemsTotal = activeItems.fold<double>(
    0,
    (total, item) => total + item.qty * item.unitPrice,
  );
  final cancelledItemsCount = itemList.length - activeItems.length;
  final ghost =
      isActiveOrderState(order) &&
      activeItems.isEmpty &&
      activePayments.isEmpty &&
      (order.total.abs() <= ghostOrderTolerance ||
          activeItemsTotal.abs() <= ghostOrderTolerance) &&
      order.pendingTotal.abs() <= ghostOrderTolerance;
  return GhostOrderEvaluation(
    isGhost: ghost,
    activeItemsCount: activeItems.length,
    activePaymentsCount: activePayments.length,
    cancelledItemsCount: cancelledItemsCount,
    activeItemsTotal: activeItemsTotal,
  );
}

bool isGhostOrder(
  PosOrder order,
  Iterable<OrderItem> items,
  Iterable<Payment> payments,
) {
  return evaluateGhostOrder(order, items, payments).isGhost;
}

bool isOperationalOrderActive({
  required PosOrder order,
  required Iterable<OrderItem> items,
  required Iterable<Payment> payments,
}) {
  if (!isActiveOrderState(order)) return false;
  if (isGhostOrder(order, items, payments)) return false;
  if (items.any(isActiveOrderItem)) return true;
  if (payments.any(isActiveCustomerPayment)) return true;
  if (order.pendingTotal > ghostOrderTolerance) return true;
  final status = normalizeOperationalStatus(order.status);
  final paymentStatus = normalizeOperationalStatus(order.paymentStatus);
  return _activeOrderStatuses.contains(status) ||
      _activePaymentStatuses.contains(paymentStatus);
}

bool shouldReleaseTableForGhostOrder({
  required PosOrder order,
  required PosTable? table,
}) {
  return order.orderType != 'takeout' &&
      orderUsesPhysicalTables(order) &&
      table != null &&
      table.currentOrderId?.trim() == order.id.trim();
}

bool isStaleTableLink(PosTable table, {required Set<String> activeOrderIds}) {
  final currentOrderId = table.currentOrderId?.trim();
  return currentOrderId != null &&
      currentOrderId.isNotEmpty &&
      !activeOrderIds.contains(currentOrderId);
}
