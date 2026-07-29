import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';
import '../orders/order_activity.dart';
import '../orders/order_types.dart';

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

  List<OperationalOrderBlocker> get tableBlockers => blockers
      .where((row) => normalizeOrderType(row.order.orderType) == 'table')
      .toList(growable: false);
  List<OperationalOrderBlocker> get takeoutBlockers => blockers
      .where((row) => normalizeOrderType(row.order.orderType) == 'takeout')
      .toList(growable: false);
  List<OperationalOrderBlocker> get standingBlockers => blockers
      .where((row) => normalizeOrderType(row.order.orderType) == 'standing')
      .toList(growable: false);

  int get openTableCount => tableBlockers.length;
  int get openTakeoutCount => takeoutBlockers.length;
  int get openStandingCount => standingBlockers.length;
  int get viewerOrderCount =>
      openTableCount + openTakeoutCount + openStandingCount;
  int get pendingPaymentCount => blockers
      .where(
        (row) =>
            row.order.pendingTotal > ghostOrderTolerance ||
            row.activePaymentCount > 0,
      )
      .length;
  bool get hasBlockers => blockers.isNotEmpty;
}

class OperationalViewerReconciliation {
  const OperationalViewerReconciliation({
    required this.dashboardOpen,
    required this.viewerTables,
    required this.viewerTakeout,
    required this.viewerStanding,
  });

  final int dashboardOpen;
  final int viewerTables;
  final int viewerTakeout;
  final int viewerStanding;

  int get viewerTotal => viewerTables + viewerTakeout + viewerStanding;
  int get difference => dashboardOpen - viewerTotal;
  bool get valid => difference == 0;
}

OperationalViewerReconciliation reconcileOperationalViewer(
  OperationalOpenOrdersSummary summary,
) {
  return OperationalViewerReconciliation(
    dashboardOpen: summary.blockers.length,
    viewerTables: summary.openTableCount,
    viewerTakeout: summary.openTakeoutCount,
    viewerStanding: summary.openStandingCount,
  );
}

OperationalOrderBlocker? evaluateOperationalOrderBlocker({
  required PosOrder order,
  required List<OrderItem> items,
  required List<Payment> payments,
  required bool belongsToBranchAndDate,
}) {
  if (!belongsToBranchAndDate || !isActiveOrderState(order)) return null;
  final evaluation = evaluateGhostOrder(order, items, payments);
  if (evaluation.isGhost) return null;
  if (!isOperationalOrderActive(
    order: order,
    items: items,
    payments: payments,
  )) {
    return null;
  }

  final reasonParts = <String>[
    if (order.pendingTotal > ghostOrderTolerance) 'saldo pendiente',
    if (evaluation.activeItemsCount > 0) 'items activos pendientes',
    if (evaluation.activePaymentsCount > 0) 'pagos activos',
    'estado ${order.status}',
    'pago ${order.paymentStatus}',
  ];
  return OperationalOrderBlocker(
    order: order,
    reason: reasonParts.join(', '),
    activeItemCount: evaluation.activeItemsCount,
    activePaymentCount: evaluation.activePaymentsCount,
  );
}

String operationalDiscardReason({
  required PosOrder order,
  required List<OrderItem> items,
  required List<Payment> payments,
  required bool belongsToBranchAndDate,
}) {
  if (!belongsToBranchAndDate) return 'otra sucursal o fecha operativa';
  if (!isActiveOrderState(order)) return 'pagada/cancelada/cerrada';
  if (isGhostOrder(order, items, payments)) return 'orden fantasma';
  return 'sin saldo ni items pendientes';
}
