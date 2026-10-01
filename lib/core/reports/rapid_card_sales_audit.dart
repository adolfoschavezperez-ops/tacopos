import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';
import 'canonical_sales_summary.dart';

enum RapidCardAuditTimingBasis {
  orderCreated,
  lastItemCaptured,
  sentToKitchen,
  lastReady,
}

class RapidCardSaleAuditRow {
  const RapidCardSaleAuditRow({
    required this.order,
    required this.payment,
    required this.activeItems,
    required this.kitchenItems,
    required this.cardAmount,
    required this.chargedAmount,
    required this.cardFeeAmount,
    required this.orderCreatedAt,
    required this.firstItemCreatedAt,
    required this.lastItemCreatedAt,
    required this.sentToKitchenAt,
    required this.firstReadyAt,
    required this.lastReadyAt,
    required this.paymentAt,
    required this.readyKitchenItems,
  });

  final PosOrder order;
  final Payment payment;
  final List<OrderItem> activeItems;
  final List<OrderItem> kitchenItems;
  final double cardAmount;
  final double chargedAmount;
  final double cardFeeAmount;
  final DateTime? orderCreatedAt;
  final DateTime? firstItemCreatedAt;
  final DateTime? lastItemCreatedAt;
  final DateTime? sentToKitchenAt;
  final DateTime? firstReadyAt;
  final DateTime? lastReadyAt;
  final DateTime? paymentAt;
  final int readyKitchenItems;

  int get kitchenItemCount => kitchenItems.length;
  int get productQty => activeItems.fold<int>(0, (sum, item) => sum + item.qty);

  String get cashierName {
    final employee = payment.employeeName?.trim();
    if (employee != null && employee.isNotEmpty) return employee;
    final createdBy = payment.createdBy?.trim();
    if (createdBy != null && createdBy.isNotEmpty) return createdBy;
    return 'Sin usuario';
  }

  String get folio {
    for (final value in [
      payment.saleFolioFull,
      payment.saleFolioDisplay,
      order.saleFolioFull,
      order.saleFolioDisplay,
    ]) {
      final clean = value?.trim();
      if (clean != null && clean.isNotEmpty) return clean;
    }
    return order.id;
  }

  String get orderLabel => order.displayName;

  String get productsLabel {
    if (activeItems.isEmpty) return 'Sin productos';
    return activeItems
        .map((item) => '${item.qty}x ${item.productName}')
        .join(', ');
  }

  Duration? get orderToPayment => _between(orderCreatedAt, paymentAt);
  Duration? get lastItemToPayment => _between(lastItemCreatedAt, paymentAt);
  Duration? get kitchenSendToPayment => _between(sentToKitchenAt, paymentAt);
  Duration? get lastReadyToPayment => _between(lastReadyAt, paymentAt);
  Duration? get orderToLastReady => _between(orderCreatedAt, lastReadyAt);

  bool get hasKitchenTrace =>
      kitchenItems.isNotEmpty &&
      (sentToKitchenAt != null ||
          kitchenItems.any(
            (item) =>
                item.sentToKitchenAt != null ||
                item.cookingAt != null ||
                item.readyAt != null,
          ));

  bool get allKitchenItemsHaveReadyTimestamp =>
      kitchenItems.isNotEmpty && readyKitchenItems == kitchenItems.length;

  bool get kitchenCompleteBeforePayment {
    final paid = paymentAt;
    final ready = lastReadyAt;
    if (paid == null ||
        ready == null ||
        !allKitchenItemsHaveReadyTimestamp) {
      return false;
    }
    return !ready.isAfter(paid);
  }

  int? secondsFor(RapidCardAuditTimingBasis basis) {
    final duration = switch (basis) {
      RapidCardAuditTimingBasis.orderCreated => orderToPayment,
      RapidCardAuditTimingBasis.lastItemCaptured => lastItemToPayment,
      RapidCardAuditTimingBasis.sentToKitchen => kitchenSendToPayment,
      RapidCardAuditTimingBasis.lastReady => lastReadyToPayment,
    };
    return duration?.inSeconds;
  }

  bool matchesSeconds(
    int maxSeconds, {
    RapidCardAuditTimingBasis basis = RapidCardAuditTimingBasis.orderCreated,
  }) {
    final seconds = secondsFor(basis);
    return seconds != null && seconds >= 0 && seconds <= maxSeconds;
  }

  bool get isRapidOrderToCard60 => matchesSeconds(60);

  bool get isStrongRapidKitchenMatch =>
      isRapidOrderToCard60 && kitchenCompleteBeforePayment;
}

List<RapidCardSaleAuditRow> buildRapidCardSalesAudit({
  required Iterable<PosOrder> orders,
  required Map<String, List<OrderItem>> itemsByOrder,
  required Map<String, List<Payment>> paymentsByOrder,
}) {
  final rows = <RapidCardSaleAuditRow>[];

  for (final order in orders) {
    if (_isCancelledOrder(order)) continue;

    final activeItems = (itemsByOrder[order.id] ?? const <OrderItem>[])
        .where(isCanonicalActiveItem)
        .toList(growable: false);
    final kitchenItems = activeItems
        .where((item) => item.sendToKitchen)
        .toList(growable: false);
    final cardPayments = (paymentsByOrder[order.id] ?? const <Payment>[])
        .where(isCanonicalActivePayment)
        .where((payment) => payment.method.trim().toLowerCase() == 'card')
        .toList(growable: false);

    if (cardPayments.isEmpty) continue;

    final itemCreatedTimes = activeItems
        .map((item) => item.createdAt)
        .whereType<DateTime>()
        .toList(growable: false);
    final sentTimes = kitchenItems
        .map(
          (item) =>
              item.sentToKitchenAt ??
              item.kitchenBatchCreatedAt,
        )
        .whereType<DateTime>()
        .toList(growable: false);
    final readyTimes = kitchenItems
        .map((item) => item.readyAt)
        .whereType<DateTime>()
        .toList(growable: false);

    final firstItemCreatedAt = _minDate(itemCreatedTimes);
    final lastItemCreatedAt = _maxDate(itemCreatedTimes);
    final sentToKitchenAt =
        order.sentToKitchenAt ?? _minDate(sentTimes);
    final firstReadyAt = _minDate(readyTimes);
    final lastReadyAt = _maxDate(readyTimes);

    for (final payment in cardPayments) {
      rows.add(
        RapidCardSaleAuditRow(
          order: order,
          payment: payment,
          activeItems: activeItems,
          kitchenItems: kitchenItems,
          cardAmount: canonicalPaymentAppliedAmount(payment),
          chargedAmount: payment.chargedAmount,
          cardFeeAmount:
              payment.cardFeeAbsorbedAmount > 0
                  ? payment.cardFeeAbsorbedAmount
                  : payment.surchargeAmount,
          orderCreatedAt: order.createdAt,
          firstItemCreatedAt: firstItemCreatedAt,
          lastItemCreatedAt: lastItemCreatedAt,
          sentToKitchenAt: sentToKitchenAt,
          firstReadyAt: firstReadyAt,
          lastReadyAt: lastReadyAt,
          paymentAt: payment.createdAt ?? order.paidAt,
          readyKitchenItems: readyTimes.length,
        ),
      );
    }
  }

  rows.sort((a, b) {
    final aSeconds = a.orderToPayment?.inSeconds;
    final bSeconds = b.orderToPayment?.inSeconds;
    if (aSeconds != null && bSeconds != null) {
      final byTime = aSeconds.compareTo(bSeconds);
      if (byTime != 0) return byTime;
    } else if (aSeconds != null) {
      return -1;
    } else if (bSeconds != null) {
      return 1;
    }
    final aPaid = a.paymentAt;
    final bPaid = b.paymentAt;
    if (aPaid != null && bPaid != null) return bPaid.compareTo(aPaid);
    return a.folio.compareTo(b.folio);
  });

  return rows;
}

DateTime? _minDate(Iterable<DateTime> values) {
  DateTime? result;
  for (final value in values) {
    if (result == null || value.isBefore(result)) result = value;
  }
  return result;
}

DateTime? _maxDate(Iterable<DateTime> values) {
  DateTime? result;
  for (final value in values) {
    if (result == null || value.isAfter(result)) result = value;
  }
  return result;
}

Duration? _between(DateTime? start, DateTime? end) {
  if (start == null || end == null) return null;
  return end.difference(start);
}

bool _isCancelledOrder(PosOrder order) {
  final values = [
    order.status,
    order.paymentStatus,
  ].map((value) => value.trim().toLowerCase()).toSet();
  return values.any(
    const {
      'cancelled',
      'canceled',
      'cancelado',
      'cancelada',
      'voided',
      'anulado',
      'anulada',
    }.contains,
  ) ||
      order.cancelledAt != null ||
      order.canceledAt != null;
}
