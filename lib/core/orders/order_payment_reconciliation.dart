import '../../models/payment.dart';
import 'global_discount_checkout.dart';

class PaymentSettlementInput {
  const PaymentSettlementInput({
    required this.id,
    required this.grossAmount,
    required this.monetaryAmount,
    required this.discountAmount,
    this.discountType,
    this.discountName,
    this.discountPercent = 0,
  });

  factory PaymentSettlementInput.fromPayment(Payment payment) {
    return PaymentSettlementInput(
      id: payment.id,
      grossAmount: payment.baseAmount,
      monetaryAmount: payment.chargedAmount,
      discountAmount: payment.discountAmount,
      discountType: payment.appliedDiscountType ?? payment.discountSource,
      discountName: payment.appliedDiscountName ?? payment.discountName,
      discountPercent: payment.appliedDiscountPercent,
    );
  }

  factory PaymentSettlementInput.fromPaymentData(
    String id,
    Map<String, Object?> data,
  ) {
    final discountPercent = _readMoney(data['appliedDiscountPercent']) > 0
        ? _readMoney(data['appliedDiscountPercent'])
        : _readMoney(data['discountPercent']);
    return PaymentSettlementInput(
      id: id,
      grossAmount: _readMoney(data['baseAmount']),
      monetaryAmount: _readMoney(data['chargedAmount']),
      discountAmount: _readMoney(data['discountAmount']),
      discountType:
          data['appliedDiscountType']?.toString() ??
          data['discountSource']?.toString(),
      discountName:
          data['appliedDiscountName']?.toString() ??
          data['discountName']?.toString(),
      discountPercent: discountPercent,
    );
  }

  final String id;
  final double grossAmount;
  final double monetaryAmount;
  final double discountAmount;
  final String? discountType;
  final String? discountName;
  final double discountPercent;
}

class OrderPaymentReconciliationTotals {
  const OrderPaymentReconciliationTotals({
    required this.orderGrossTotal,
    required this.paidTotal,
    required this.pendingTotal,
    required this.monetaryPaid,
    required this.discountAmount,
    required this.totalLiquidated,
    required this.netTotal,
    required this.effectiveDiscountPercent,
    required this.paymentStatus,
    required this.discountApplied,
    this.lastDiscountType,
    this.lastDiscountName,
    this.lastDiscountPercent = 0,
  });

  final double orderGrossTotal;
  final double paidTotal;
  final double pendingTotal;
  final double monetaryPaid;
  final double discountAmount;
  final double totalLiquidated;
  final double netTotal;
  final double effectiveDiscountPercent;
  final String paymentStatus;
  final bool discountApplied;
  final String? lastDiscountType;
  final String? lastDiscountName;
  final double lastDiscountPercent;
}

OrderPaymentReconciliationTotals reconcileOrderPayments({
  required double orderGrossTotal,
  required Iterable<PaymentSettlementInput> activePayments,
}) {
  final grossTotal = roundCheckoutMoney(
    orderGrossTotal.clamp(0, double.infinity).toDouble(),
  );
  var paidTotal = 0.0;
  var monetaryPaid = 0.0;
  var discountAmount = 0.0;
  PaymentSettlementInput? lastDiscount;
  for (final payment in activePayments) {
    final gross = payment.grossAmount.clamp(0, double.infinity).toDouble();
    final discount = payment.discountAmount.clamp(0, gross).toDouble();
    paidTotal += gross;
    monetaryPaid += payment.monetaryAmount.clamp(0, double.infinity).toDouble();
    discountAmount += discount;
    if (discount > 0.01) {
      lastDiscount = payment;
    }
  }
  paidTotal = roundCheckoutMoney(paidTotal.clamp(0, grossTotal).toDouble());
  discountAmount = roundCheckoutMoney(
    discountAmount.clamp(0, grossTotal).toDouble(),
  );
  monetaryPaid = roundCheckoutMoney(monetaryPaid);
  final pendingTotal = roundCheckoutMoney(
    (grossTotal - paidTotal).clamp(0, double.infinity).toDouble(),
  );
  final netTotal = roundCheckoutMoney(
    (grossTotal - discountAmount).clamp(0, double.infinity).toDouble(),
  );
  final percent = grossTotal <= 0
      ? 0.0
      : roundCheckoutMoney((discountAmount / grossTotal) * 100);
  final paymentStatus = paidTotal <= 0.01
      ? 'pending'
      : pendingTotal <= 0.01
      ? 'paid'
      : 'partial';
  return OrderPaymentReconciliationTotals(
    orderGrossTotal: grossTotal,
    paidTotal: paidTotal,
    pendingTotal: pendingTotal,
    monetaryPaid: monetaryPaid,
    discountAmount: discountAmount,
    totalLiquidated: paidTotal,
    netTotal: netTotal,
    effectiveDiscountPercent: percent,
    paymentStatus: paymentStatus,
    discountApplied: discountAmount > 0.01,
    lastDiscountType: lastDiscount?.discountType,
    lastDiscountName: lastDiscount?.discountName,
    lastDiscountPercent: lastDiscount?.discountPercent ?? 0,
  );
}

double _readMoney(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim().replaceAll(',', '')) ?? 0;
  }
  return 0;
}
