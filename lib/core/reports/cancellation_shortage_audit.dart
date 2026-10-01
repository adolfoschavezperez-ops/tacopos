import '../../models/cash_session.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';

class CancellationCashAuditRow {
  const CancellationCashAuditRow({
    required this.order,
    required this.businessDate,
    required this.cancelledItems,
    required this.payments,
    required this.initiatedByNames,
    required this.acceptedByNames,
    required this.cancelledAt,
  });

  final PosOrder order;
  final String businessDate;
  final List<OrderItem> cancelledItems;
  final List<Payment> payments;
  final Set<String> initiatedByNames;
  final Set<String> acceptedByNames;
  final DateTime? cancelledAt;

  double get cancelledAmount =>
      cancelledItems.fold<double>(0, (sum, item) => sum + item.total);

  int get cancelledQty =>
      cancelledItems.fold<int>(0, (sum, item) => sum + item.qty);

  int get cancelledLineCount => cancelledItems.length;

  bool get fullOrderCancelled => _isCancelledStatus(order.status);

  int get activePaymentCount => payments.where((p) => p.isActive).length;
  int get cancelledPaymentCount => payments.where((p) => p.isCancelled).length;
  bool get hasAnyPaymentRecord => payments.isNotEmpty;
  bool get hasNoPaymentRecord => payments.isEmpty;

  bool get passedThroughKitchen => cancelledItems.any(
        (item) =>
            item.sentToKitchenAt != null ||
            item.cookingAt != null ||
            item.readyAt != null ||
            (item.kitchenBatchId?.trim().isNotEmpty ?? false),
      );

  bool get hadCookingTimestamp =>
      cancelledItems.any((item) => item.cookingAt != null);

  bool get hadReadyTimestamp =>
      cancelledItems.any((item) => item.readyAt != null);

  bool get readyBeforeCancellation {
    final cancelled = cancelledAt;
    if (cancelled == null) return false;
    return cancelledItems.any(
      (item) => item.readyAt != null && !item.readyAt!.isAfter(cancelled),
    );
  }

  bool get strongCashCancellationCandidate =>
      fullOrderCancelled && hasNoPaymentRecord && passedThroughKitchen;

  bool initiatedBy(String employeeName) =>
      cancelledAmountInitiatedBy(employeeName) > 0;

  double cancelledAmountInitiatedBy(String employeeName) {
    final needle = _normalizeName(employeeName);
    if (needle.isEmpty) return cancelledAmount;

    var amount = 0.0;
    var attributedItems = 0;
    for (final item in cancelledItems) {
      final requestedBy = item.cancelRequestedByEmployeeName?.trim();
      final directBy = item.cancelledByEmployeeName?.trim();
      final initiator = requestedBy != null && requestedBy.isNotEmpty
          ? requestedBy
          : directBy ?? '';
      if (_normalizeName(initiator).contains(needle)) {
        amount += item.total;
        attributedItems++;
      }
    }

    if (attributedItems == 0) {
      final orderActor = order.cancelledByEmployeeName?.trim() ?? '';
      if (_normalizeName(orderActor).contains(needle)) return cancelledAmount;
    }
    return amount;
  }

  int cancelledQtyInitiatedBy(String employeeName) {
    final needle = _normalizeName(employeeName);
    if (needle.isEmpty) return cancelledQty;

    var qty = 0;
    var attributedItems = 0;
    for (final item in cancelledItems) {
      final requestedBy = item.cancelRequestedByEmployeeName?.trim();
      final directBy = item.cancelledByEmployeeName?.trim();
      final initiator = requestedBy != null && requestedBy.isNotEmpty
          ? requestedBy
          : directBy ?? '';
      if (_normalizeName(initiator).contains(needle)) {
        qty += item.qty;
        attributedItems++;
      }
    }

    if (attributedItems == 0) {
      final orderActor = order.cancelledByEmployeeName?.trim() ?? '';
      if (_normalizeName(orderActor).contains(needle)) return cancelledQty;
    }
    return qty;
  }

  String get folio {
    for (final value in [
      order.saleFolioFull,
      order.saleFolioDisplay,
      order.id,
    ]) {
      final clean = value?.trim();
      if (clean != null && clean.isNotEmpty) return clean;
    }
    return order.id;
  }

  String get initiatedByLabel =>
      initiatedByNames.isEmpty ? 'Sin usuario' : initiatedByNames.join(', ');

  String get acceptedByLabel =>
      acceptedByNames.isEmpty ? '-' : acceptedByNames.join(', ');

  String get productsLabel => cancelledItems
      .map((item) => '${item.qty}x ${item.productName}')
      .join(', ');

  String get reasonLabel {
    final reasons = <String>{};
    final orderReason = order.cancelReason?.trim();
    if (orderReason != null && orderReason.isNotEmpty) reasons.add(orderReason);
    for (final item in cancelledItems) {
      for (final reason in [
        item.cancelReason,
        item.cancelRequestedReason,
        item.cancelledReason,
        item.cancelNotes,
        item.reason,
      ]) {
        final clean = reason?.trim();
        if (clean != null && clean.isNotEmpty) reasons.add(clean);
      }
    }
    return reasons.isEmpty ? '-' : reasons.join(' | ');
  }
}

class CancellationCashAuditDay {
  const CancellationCashAuditDay({
    required this.businessDate,
    required this.rows,
    required this.cashSession,
    required this.cashSessionCount,
  });

  final String businessDate;
  final List<CancellationCashAuditRow> rows;
  final CashSession? cashSession;
  final int cashSessionCount;

  double get shortage => cashSession?.shortageAmount ?? 0;
  double get netDifference => cashSession?.netDifference ?? 0;

  List<CancellationCashAuditRow> initiatedBy(String employeeName) =>
      rows.where((row) => row.initiatedBy(employeeName)).toList();

  double cancelledBy(String employeeName) => rows.fold<double>(
        0,
        (sum, row) => sum + row.cancelledAmountInitiatedBy(employeeName),
      );

  double strongCandidateAmountBy(String employeeName) => rows
      .where((row) => row.strongCashCancellationCandidate)
      .fold<double>(
        0,
        (sum, row) => sum + row.cancelledAmountInitiatedBy(employeeName),
      );

  double noPaymentAmountBy(String employeeName) => rows
      .where((row) => row.hasNoPaymentRecord)
      .fold<double>(
        0,
        (sum, row) => sum + row.cancelledAmountInitiatedBy(employeeName),
      );

  /// Hypothesis-only arithmetic:
  /// if these no-payment cancellations were actually cash collected but not
  /// registered, this is the physical cash outflow that would reconcile with
  /// the observed shortage.
  double impliedUnrecordedOutflowBy(String employeeName) =>
      shortage + noPaymentAmountBy(employeeName);
}

class CancellationAmountMatch {
  const CancellationAmountMatch({
    required this.rows,
    required this.total,
    required this.target,
  });

  final List<CancellationCashAuditRow> rows;
  final double total;
  final double target;

  double get difference => total - target;
  double get absoluteDifference => difference.abs();
  bool get isExact => absoluteDifference <= 0.02;
}

List<CancellationCashAuditRow> buildCancellationCashAuditRows({
  required Iterable<PosOrder> orders,
  required Map<String, List<OrderItem>> itemsByOrder,
  required Map<String, List<Payment>> paymentsByOrder,
}) {
  final result = <CancellationCashAuditRow>[];

  for (final order in orders) {
    final items = itemsByOrder[order.id] ?? const <OrderItem>[];
    final cancelledItems = items.where((item) => item.isCancelled).toList();
    if (cancelledItems.isEmpty && !_isCancelledStatus(order.status)) continue;

    final effectiveCancelledItems = cancelledItems.isNotEmpty
        ? cancelledItems
        : items;
    if (effectiveCancelledItems.isEmpty) continue;

    final initiatedBy = <String>{};
    final acceptedBy = <String>{};

    for (final item in effectiveCancelledItems) {
      final requestedBy = item.cancelRequestedByEmployeeName?.trim();
      final directBy = item.cancelledByEmployeeName?.trim();
      final accepted = item.cancelAcceptedByEmployeeName?.trim();

      if (requestedBy != null && requestedBy.isNotEmpty) {
        initiatedBy.add(requestedBy);
      } else if (directBy != null && directBy.isNotEmpty) {
        initiatedBy.add(directBy);
      }
      if (accepted != null && accepted.isNotEmpty) {
        acceptedBy.add(accepted);
      }
    }

    final orderCancelledBy = order.cancelledByEmployeeName?.trim();
    if (initiatedBy.isEmpty &&
        orderCancelledBy != null &&
        orderCancelledBy.isNotEmpty) {
      initiatedBy.add(orderCancelledBy);
    }

    final cancelledAtCandidates = <DateTime>[
      if (order.cancelledAt != null) order.cancelledAt!,
      if (order.canceledAt != null) order.canceledAt!,
      for (final item in effectiveCancelledItems)
        if (item.cancelledAt != null) item.cancelledAt!,
      for (final item in effectiveCancelledItems)
        if (item.cancelAcceptedAt != null) item.cancelAcceptedAt!,
      for (final item in effectiveCancelledItems)
        if (item.cancelRequestedAt != null) item.cancelRequestedAt!,
    ];
    cancelledAtCandidates.sort();

    final businessDate = _businessDateFor(
      order,
      cancelledAtCandidates.isEmpty ? null : cancelledAtCandidates.last,
    );

    result.add(
      CancellationCashAuditRow(
        order: order,
        businessDate: businessDate,
        cancelledItems: effectiveCancelledItems,
        payments: paymentsByOrder[order.id] ?? const <Payment>[],
        initiatedByNames: initiatedBy,
        acceptedByNames: acceptedBy,
        cancelledAt:
            cancelledAtCandidates.isEmpty ? null : cancelledAtCandidates.last,
      ),
    );
  }

  result.sort((a, b) {
    final dateCompare = b.businessDate.compareTo(a.businessDate);
    if (dateCompare != 0) return dateCompare;
    final aAt = a.cancelledAt ?? DateTime(1970);
    final bAt = b.cancelledAt ?? DateTime(1970);
    return bAt.compareTo(aAt);
  });
  return result;
}

List<CancellationCashAuditDay> buildCancellationCashAuditDays({
  required Iterable<CancellationCashAuditRow> rows,
  required Iterable<CashSession> cashSessions,
}) {
  final rowsByDate = <String, List<CancellationCashAuditRow>>{};
  for (final row in rows) {
    rowsByDate.putIfAbsent(row.businessDate, () => []).add(row);
  }

  final sessionsByDate = <String, List<CashSession>>{};
  for (final session in cashSessions) {
    sessionsByDate.putIfAbsent(session.businessDate, () => []).add(session);
  }

  final dates = <String>{...rowsByDate.keys, ...sessionsByDate.keys}.toList()
    ..sort((a, b) => b.compareTo(a));

  return dates.map((date) {
    final sessions = [...sessionsByDate[date] ?? const <CashSession>[]];
    sessions.sort((a, b) {
      DateTime rank(CashSession value) =>
          value.correctedAt ??
          value.closedAt ??
          value.updatedAt ??
          value.openedAt ??
          value.createdAt ??
          DateTime(1970);
      return rank(b).compareTo(rank(a));
    });

    return CancellationCashAuditDay(
      businessDate: date,
      rows: rowsByDate[date] ?? const <CancellationCashAuditRow>[],
      cashSession: sessions.isEmpty ? null : sessions.first,
      cashSessionCount: sessions.length,
    );
  }).toList();
}

List<CancellationAmountMatch> findCancellationAmountMatches({
  required Iterable<CancellationCashAuditRow> rows,
  required double target,
  String employeeName = '',
  int maxItems = 4,
  int maxResults = 10,
  double tolerance = 2,
}) {
  if (target <= 0 || maxItems <= 0 || maxResults <= 0) return const [];

  final candidates = rows
      .where((row) => row.cancelledAmountInitiatedBy(employeeName) > 0)
      .take(25)
      .toList(growable: false);
  final matches = <CancellationAmountMatch>[];

  void walk(int start, List<CancellationCashAuditRow> picked, double total) {
    if (picked.isNotEmpty) {
      matches.add(
        CancellationAmountMatch(
          rows: List.unmodifiable(picked),
          total: total,
          target: target,
        ),
      );
    }
    if (picked.length >= maxItems) return;

    for (var i = start; i < candidates.length; i++) {
      final row = candidates[i];
      final nextTotal =
          total + row.cancelledAmountInitiatedBy(employeeName);
      if (nextTotal > target + tolerance + 500) continue;
      picked.add(row);
      walk(i + 1, picked, nextTotal);
      picked.removeLast();
    }
  }

  walk(0, <CancellationCashAuditRow>[], 0);

  matches.sort((a, b) {
    final diff = a.absoluteDifference.compareTo(b.absoluteDifference);
    if (diff != 0) return diff;
    final length = a.rows.length.compareTo(b.rows.length);
    if (length != 0) return length;
    return a.total.compareTo(b.total);
  });

  final unique = <String>{};
  final result = <CancellationAmountMatch>[];
  for (final match in matches) {
    final key = match.rows.map((row) => row.order.id).toList()..sort();
    if (!unique.add(key.join('|'))) continue;
    result.add(match);
    if (result.length >= maxResults) break;
  }
  return result;
}

bool _isCancelledStatus(String value) {
  final clean = value.trim().toLowerCase();
  return const {
    'cancelled',
    'canceled',
    'cancelado',
    'cancelada',
    'voided',
    'anulado',
    'anulada',
  }.contains(clean);
}

String _businessDateFor(PosOrder order, DateTime? fallback) {
  for (final value in [
    order.businessDate,
    order.operationalDate,
    order.saleFolioBusinessDate,
  ]) {
    final clean = value?.trim();
    if (clean != null && clean.isNotEmpty) return clean;
  }
  final date = fallback ?? order.cancelledAt ?? order.updatedAt ?? order.createdAt;
  if (date == null) return '';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

String _normalizeName(String value) => value.trim().toLowerCase();
