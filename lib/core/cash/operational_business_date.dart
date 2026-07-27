import '../../models/cash_session.dart';
import '../../models/order.dart';
import '../../models/payment.dart';

enum OperationalBusinessDateSource {
  order,
  cashSession,
  payment,
  historicalFallback,
  unavailable,
}

class OperationalBusinessDateResolution {
  const OperationalBusinessDateResolution({
    required this.businessDate,
    required this.source,
  });

  final String businessDate;
  final OperationalBusinessDateSource source;

  bool get usedHistoricalFallback =>
      source == OperationalBusinessDateSource.historicalFallback;
}

class OperationalSessionMembership {
  const OperationalSessionMembership({
    required this.included,
    required this.reason,
    this.inconsistency,
  });

  final bool included;
  final String reason;
  final String? inconsistency;
}

OperationalBusinessDateResolution resolveOperationalBusinessDateDetails({
  PosOrder? order,
  CashSession? cashSession,
  Payment? payment,
  DateTime? historicalFallback,
}) {
  final orderBusinessDate = _orderBusinessDate(order);
  if (orderBusinessDate != null) {
    return OperationalBusinessDateResolution(
      businessDate: orderBusinessDate,
      source: OperationalBusinessDateSource.order,
    );
  }

  final sessionBusinessDate = _clean(cashSession?.businessDate);
  if (sessionBusinessDate != null) {
    return OperationalBusinessDateResolution(
      businessDate: sessionBusinessDate,
      source: OperationalBusinessDateSource.cashSession,
    );
  }

  final paymentBusinessDate = _clean(payment?.businessDate);
  if (paymentBusinessDate != null) {
    return OperationalBusinessDateResolution(
      businessDate: paymentBusinessDate,
      source: OperationalBusinessDateSource.payment,
    );
  }

  if (historicalFallback != null) {
    return OperationalBusinessDateResolution(
      businessDate: formatOperationalBusinessDate(historicalFallback),
      source: OperationalBusinessDateSource.historicalFallback,
    );
  }

  return const OperationalBusinessDateResolution(
    businessDate: '',
    source: OperationalBusinessDateSource.unavailable,
  );
}

String resolveOperationalBusinessDate({
  PosOrder? order,
  CashSession? cashSession,
  Payment? payment,
  DateTime? historicalFallback,
}) {
  return resolveOperationalBusinessDateDetails(
    order: order,
    cashSession: cashSession,
    payment: payment,
    historicalFallback: historicalFallback,
  ).businessDate;
}

String businessDateForOpenCashSession(CashSession session) {
  if (!session.isOpen) {
    throw StateError('La sesion de caja ya esta cerrada.');
  }
  final businessDate = _clean(session.businessDate);
  if (businessDate == null || !_businessDatePattern.hasMatch(businessDate)) {
    throw StateError('La sesion de caja no tiene una fecha operativa valida.');
  }
  return businessDate;
}

OperationalSessionMembership belongsToOperationalSession({
  required PosOrder order,
  required String selectedCashSessionId,
  required String selectedBusinessDate,
  required String branchId,
  Iterable<String> paymentCashSessionIds = const [],
}) {
  if (_clean(order.branchId) != _clean(branchId)) {
    return const OperationalSessionMembership(
      included: false,
      reason: 'branch_mismatch',
    );
  }

  final selectedSessionId = _clean(selectedCashSessionId);
  final orderSessionId = _clean(order.cashSessionId);
  final orderBusinessDate = _orderBusinessDate(order);

  if (selectedSessionId != null && orderSessionId != null) {
    if (orderSessionId != selectedSessionId) {
      return const OperationalSessionMembership(
        included: false,
        reason: 'cash_session_mismatch',
      );
    }
    final inconsistency =
        orderBusinessDate != null && orderBusinessDate != selectedBusinessDate
        ? 'cash_session_matches_but_business_date_is_$orderBusinessDate'
        : null;
    return OperationalSessionMembership(
      included: true,
      reason: 'cash_session_match',
      inconsistency: inconsistency,
    );
  }

  if (orderSessionId != null && selectedSessionId == null) {
    if (orderBusinessDate == selectedBusinessDate) {
      return const OperationalSessionMembership(
        included: true,
        reason: 'exact_business_date_without_selected_session',
      );
    }
    return const OperationalSessionMembership(
      included: false,
      reason: 'selected_cash_session_unavailable',
    );
  }

  if (orderBusinessDate == selectedBusinessDate) {
    return const OperationalSessionMembership(
      included: true,
      reason: 'legacy_exact_business_date',
    );
  }

  final paymentSessionMatches =
      selectedSessionId != null &&
      paymentCashSessionIds.any(
        (paymentSessionId) => _clean(paymentSessionId) == selectedSessionId,
      );
  if (orderSessionId == null &&
      orderBusinessDate == null &&
      paymentSessionMatches) {
    return const OperationalSessionMembership(
      included: true,
      reason: 'legacy_payment_cash_session_match',
    );
  }

  return OperationalSessionMembership(
    included: false,
    reason: orderBusinessDate == null
        ? 'missing_operational_scope'
        : 'business_date_mismatch',
  );
}

String formatOperationalBusinessDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String? _orderBusinessDate(PosOrder? order) {
  return _clean(order?.businessDate) ?? _clean(order?.operationalDate);
}

String? _clean(String? value) {
  final clean = value?.trim();
  return clean == null || clean.isEmpty ? null : clean;
}

final RegExp _businessDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
