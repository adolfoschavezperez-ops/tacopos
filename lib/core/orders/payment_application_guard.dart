import '../../models/payment.dart';
import 'global_discount_checkout.dart';
import 'order_payment_reconciliation.dart';

const double paymentApplicationTolerance = 0.02;

class PaymentApplicationPlan {
  const PaymentApplicationPlan({
    required this.remainingAmount,
    required this.appliedAmount,
    required this.cashReceivedAmount,
    required this.cashChangeAmount,
  });

  final double remainingAmount;
  final double appliedAmount;
  final double? cashReceivedAmount;
  final double? cashChangeAmount;
}

double remainingPaymentAmount({
  required double orderNetAmount,
  required Iterable<Payment> previousActivePayments,
  double? freshPendingAmount,
}) {
  final paid = previousActivePayments
      .where((payment) => payment.isActive)
      .fold<double>(
        0,
        (total, payment) => total + paymentMonetaryAppliedToSale(payment),
      );
  final byPayments = roundCheckoutMoney(
    (orderNetAmount - paid).clamp(0, double.infinity).toDouble(),
  );
  if (freshPendingAmount == null || freshPendingAmount < 0) return byPayments;
  return roundCheckoutMoney(freshPendingAmount.clamp(0, byPayments).toDouble());
}

PaymentApplicationPlan planPaymentApplication({
  required double orderNetAmount,
  required Iterable<Payment> previousActivePayments,
  required double requestedAppliedAmount,
  required String paymentType,
  String method = '',
  double? cashReceivedAmount,
  double? cashChangeAmount,
  double? freshPendingAmount,
}) {
  final remaining = remainingPaymentAmount(
    orderNetAmount: orderNetAmount,
    previousActivePayments: previousActivePayments,
    freshPendingAmount: freshPendingAmount,
  );
  final normalizedType = paymentType.trim().toLowerCase();
  var applied = roundCheckoutMoney(
    requestedAppliedAmount.clamp(0, double.infinity).toDouble(),
  );

  if (normalizedType == 'full_table') {
    applied = remaining;
  } else if (applied > remaining + paymentApplicationTolerance) {
    throw ArgumentError('El pago excede el saldo pendiente.');
  }

  return PaymentApplicationPlan(
    remainingAmount: remaining,
    appliedAmount: applied,
    cashReceivedAmount: cashReceivedAmount,
    cashChangeAmount: cashChangeAmount,
  );
}

Map<String, Object?> normalizePaymentDataForRemaining({
  required Map<String, Object?> paymentData,
  required double orderNetAmount,
  required Iterable<Payment> previousActivePayments,
  double? freshPendingAmount,
}) {
  final type = paymentData['type']?.toString() ?? '';
  final applied = _money(
    paymentData['appliedAmount'] ??
        paymentData['amount'] ??
        paymentData['chargedAmount'] ??
        paymentData['totalAfterDiscount'] ??
        paymentData['baseAmount'],
  );
  final plan = planPaymentApplication(
    orderNetAmount: orderNetAmount,
    previousActivePayments: previousActivePayments,
    requestedAppliedAmount: applied,
    paymentType: type,
    method: paymentData['method']?.toString() ?? '',
    cashReceivedAmount: _nullableMoney(paymentData['cashReceivedAmount']),
    cashChangeAmount: _nullableMoney(paymentData['cashChangeAmount']),
    freshPendingAmount: freshPendingAmount,
  );
  // A full-table discount is applied against the authoritative gross
  // remainder. Its monetary amount is therefore expected to be lower than
  // the remainder by exactly the discount. Preserve it only when the payment
  // data proves that relationship; otherwise keep the existing normalization
  // that prevents stale or excessive payments from being persisted.
  final discount = _money(paymentData['discountAmount']);
  final grossAmount = _money(
    paymentData['baseAmount'] ?? paymentData['subtotalBeforeDiscount'],
  );
  if (type.trim().toLowerCase() == 'full_table' && discount > 0) {
    final discountMatchesAuthoritativeBalance =
        discount <= grossAmount &&
        (grossAmount - plan.remainingAmount).abs() <=
            paymentApplicationTolerance &&
        (grossAmount - discount - applied).abs() <=
            paymentApplicationTolerance &&
        (plan.remainingAmount - discount - applied).abs() <=
            paymentApplicationTolerance;
    if (discountMatchesAuthoritativeBalance) return paymentData;
    throw StateError(
      'El saldo cambio; revisa el descuento antes de confirmar el cobro.',
    );
  }
  if ((plan.appliedAmount - applied).abs() <= paymentApplicationTolerance) {
    return paymentData;
  }
  return {
    ...paymentData,
    'subtotalBeforeDiscount': plan.appliedAmount,
    'discountAmount': 0.0,
    'totalAfterDiscount': plan.appliedAmount,
    'appliedAmount': plan.appliedAmount,
    'baseAmount': plan.appliedAmount,
    'amount': plan.appliedAmount,
    'chargedAmount': plan.appliedAmount,
    'cardFeeAbsorbedAmount': _recalculateFee(paymentData, plan.appliedAmount),
  };
}

double _recalculateFee(Map<String, Object?> paymentData, double appliedAmount) {
  final rate = _money(paymentData['cardFeeRate']);
  if (rate <= 0) return 0;
  return roundCheckoutMoney(appliedAmount * rate);
}

double _money(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim().replaceAll(',', '')) ?? 0;
  }
  return 0;
}

double? _nullableMoney(Object? value) {
  if (value == null) return null;
  return _money(value);
}
