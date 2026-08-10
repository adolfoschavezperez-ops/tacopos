import '../../models/payment.dart';
import 'global_discount_checkout.dart';

class PaymentSettlementInput {
  const PaymentSettlementInput({
    required this.id,
    this.method = '',
    required this.grossAmount,
    required this.monetaryAmount,
    required this.discountAmount,
    this.cardFeeAmount = 0,
    this.tipAmount = 0,
    this.discountType,
    this.discountName,
    this.discountPercent = 0,
  });

  factory PaymentSettlementInput.fromPayment(Payment payment) {
    return PaymentSettlementInput(
      id: payment.id,
      method: payment.method,
      grossAmount: payment.baseAmount,
      monetaryAmount: paymentMonetaryAppliedToSale(payment),
      discountAmount: paymentDiscountAppliedToSale(payment),
      cardFeeAmount: payment.cardFeeAbsorbedAmount > 0
          ? payment.cardFeeAbsorbedAmount
          : payment.surchargeAmount,
      tipAmount: payment.tipAmount,
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
    final grossAmount = _readMoney(data['baseAmount']) > 0
        ? _readMoney(data['baseAmount'])
        : _readMoney(data['subtotalBeforeDiscount']);
    final discountAmount = _paymentDataDiscountAppliedToSale(
      data,
      grossAmount: grossAmount,
    );
    return PaymentSettlementInput(
      id: id,
      method: data['method']?.toString() ?? '',
      grossAmount: grossAmount,
      monetaryAmount: _paymentDataMonetaryAppliedToSale(
        data,
        grossAmount: grossAmount,
        discountAmount: discountAmount,
      ),
      discountAmount: discountAmount,
      cardFeeAmount: _readMoney(data['cardFeeAbsorbedAmount']) > 0
          ? _readMoney(data['cardFeeAbsorbedAmount'])
          : _readMoney(data['surchargeAmount']),
      tipAmount: _readTip(data),
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
  final String method;
  final double grossAmount;
  final double monetaryAmount;
  final double discountAmount;
  final double cardFeeAmount;
  final double tipAmount;
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
    required this.overLiquidatedTotal,
    required this.netTotal,
    required this.cashPaid,
    required this.cardPaid,
    required this.employeeConsumptionMonetary,
    required this.otherMonetaryPaid,
    required this.cardFeeTotal,
    required this.tipTotal,
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
  final double overLiquidatedTotal;
  final double netTotal;
  final double cashPaid;
  final double cardPaid;
  final double employeeConsumptionMonetary;
  final double otherMonetaryPaid;
  final double cardFeeTotal;
  final double tipTotal;
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
  var grossCovered = 0.0;
  var monetaryPaid = 0.0;
  var discountAmount = 0.0;
  var cashPaid = 0.0;
  var cardPaid = 0.0;
  var employeeConsumptionMonetary = 0.0;
  var otherMonetaryPaid = 0.0;
  var cardFeeTotal = 0.0;
  var tipTotal = 0.0;
  PaymentSettlementInput? lastDiscount;
  for (final payment in activePayments) {
    final gross = payment.grossAmount.clamp(0, double.infinity).toDouble();
    final discount = payment.discountAmount.clamp(0, gross).toDouble();
    final monetary = payment.monetaryAmount
        .clamp(0, double.infinity)
        .toDouble();
    grossCovered += gross;
    monetaryPaid += monetary;
    discountAmount += discount;
    cardFeeTotal += payment.cardFeeAmount.clamp(0, double.infinity).toDouble();
    tipTotal += payment.tipAmount.clamp(0, double.infinity).toDouble();
    switch (_normalizeMethod(payment.method)) {
      case 'cash':
        cashPaid += monetary;
        break;
      case 'card':
        cardPaid += monetary;
        break;
      case 'employee_consumption':
        employeeConsumptionMonetary += monetary;
        break;
      default:
        otherMonetaryPaid += monetary;
    }
    if (discount > 0.01) {
      lastDiscount = payment;
    }
  }
  grossCovered = roundCheckoutMoney(
    grossCovered.clamp(0, grossTotal).toDouble(),
  );
  discountAmount = roundCheckoutMoney(
    discountAmount.clamp(0, grossTotal).toDouble(),
  );
  monetaryPaid = roundCheckoutMoney(monetaryPaid);
  final totalLiquidated = roundCheckoutMoney(monetaryPaid + discountAmount);
  final overLiquidatedTotal = roundCheckoutMoney(
    (totalLiquidated - grossTotal).clamp(0, double.infinity).toDouble(),
  );
  final paidTotal = totalLiquidated > 0
      ? totalLiquidated.clamp(0, grossTotal).toDouble()
      : grossCovered;
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
    totalLiquidated: totalLiquidated,
    overLiquidatedTotal: overLiquidatedTotal,
    netTotal: netTotal,
    cashPaid: roundCheckoutMoney(cashPaid),
    cardPaid: roundCheckoutMoney(cardPaid),
    employeeConsumptionMonetary: roundCheckoutMoney(
      employeeConsumptionMonetary,
    ),
    otherMonetaryPaid: roundCheckoutMoney(otherMonetaryPaid),
    cardFeeTotal: roundCheckoutMoney(cardFeeTotal),
    tipTotal: roundCheckoutMoney(tipTotal),
    effectiveDiscountPercent: percent,
    paymentStatus: paymentStatus,
    discountApplied: discountAmount > 0.01,
    lastDiscountType: lastDiscount?.discountType,
    lastDiscountName: lastDiscount?.discountName,
    lastDiscountPercent: lastDiscount?.discountPercent ?? 0,
  );
}

double paymentMonetaryAppliedToSale(Payment payment, {double? tipOverride}) {
  return paymentRecordedSaleAmount(payment, tipOverride: tipOverride);
}

double paymentRecordedSaleAmount(Payment payment, {double? tipOverride}) {
  final tip = (tipOverride ?? payment.tipAmount)
      .clamp(0, double.infinity)
      .toDouble();
  if (payment.appliedAmount != null && payment.appliedAmount! >= 0) {
    return roundCheckoutMoney(
      payment.appliedAmount!.clamp(0, double.infinity).toDouble(),
    );
  }
  if (payment.totalAfterDiscount > 0) {
    return roundCheckoutMoney(
      (payment.totalAfterDiscount - tip).clamp(0, double.infinity).toDouble(),
    );
  }
  if (payment.chargedAmount > 0 &&
      payment.baseAmount > 0 &&
      payment.chargedAmount < payment.baseAmount - 0.02) {
    return roundCheckoutMoney(
      (payment.chargedAmount - tip).clamp(0, double.infinity).toDouble(),
    );
  }
  final discount = paymentDiscountAppliedToSale(payment);
  final baseNet = payment.baseAmount > 0
      ? (payment.baseAmount - discount).clamp(0, double.infinity).toDouble()
      : 0.0;
  if (baseNet > 0 || discount > 0) return roundCheckoutMoney(baseNet);
  final fee = payment.cardFeeAbsorbedAmount > 0
      ? payment.cardFeeAbsorbedAmount
      : payment.surchargeAmount;
  return roundCheckoutMoney(
    (payment.chargedAmount - tip - fee).clamp(0, double.infinity).toDouble(),
  );
}

double paymentDiscountAppliedToSale(Payment payment) {
  final explicit = payment.discountAmount.clamp(0, double.infinity).toDouble();
  if (explicit > 0) return roundCheckoutMoney(explicit);
  final percent = payment.appliedDiscountPercent > 0
      ? payment.appliedDiscountPercent
      : payment.discountPercent;
  if (percent <= 0 || payment.baseAmount <= 0) return 0;
  final normalized = percent > 1 ? percent / 100 : percent;
  return roundCheckoutMoney(
    (payment.baseAmount * normalized).clamp(0, payment.baseAmount).toDouble(),
  );
}

double _paymentDataMonetaryAppliedToSale(
  Map<String, Object?> data, {
  required double grossAmount,
  required double discountAmount,
}) {
  final applied = _readMoney(data['appliedAmount']);
  if (applied >= 0 && data.containsKey('appliedAmount')) {
    return roundCheckoutMoney(applied);
  }
  final baseNet = grossAmount > 0
      ? (grossAmount - discountAmount).clamp(0, double.infinity).toDouble()
      : 0.0;
  if (baseNet > 0 || discountAmount > 0) return roundCheckoutMoney(baseNet);
  final tip = _readTip(data);
  final fee = _readMoney(data['cardFeeAbsorbedAmount']) > 0
      ? _readMoney(data['cardFeeAbsorbedAmount'])
      : _readMoney(data['surchargeAmount']);
  final totalAfterDiscount = _readMoney(data['totalAfterDiscount']);
  if (totalAfterDiscount > 0) {
    return roundCheckoutMoney(
      (totalAfterDiscount - tip).clamp(0, double.infinity).toDouble(),
    );
  }
  return roundCheckoutMoney(
    (_readMoney(data['chargedAmount']) - tip - fee)
        .clamp(0, double.infinity)
        .toDouble(),
  );
}

double _paymentDataDiscountAppliedToSale(
  Map<String, Object?> data, {
  required double grossAmount,
}) {
  final explicit = _readMoney(data['discountAmount']);
  if (explicit > 0) return roundCheckoutMoney(explicit);
  final percent = _readMoney(data['appliedDiscountPercent']) > 0
      ? _readMoney(data['appliedDiscountPercent'])
      : _readMoney(data['discountPercent']);
  if (percent <= 0 || grossAmount <= 0) return 0;
  final normalized = percent > 1 ? percent / 100 : percent;
  return roundCheckoutMoney(
    (grossAmount * normalized).clamp(0, grossAmount).toDouble(),
  );
}

double _readMoney(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim().replaceAll(',', '')) ?? 0;
  }
  return 0;
}

double _readTip(Map<String, Object?> data) {
  for (final key in const [
    'tipAmount',
    'tip',
    'tips',
    'propina',
    'gratuity',
    'employeeTip',
  ]) {
    final value = _readMoney(data[key]);
    if (value > 0) return value;
  }
  return 0;
}

String _normalizeMethod(String method) {
  final value = method
      .trim()
      .toLowerCase()
      .replaceAll(' ', '_')
      .replaceAll('-', '_');
  if (value == 'efectivo') return 'cash';
  if ({
    'tarjeta',
    'credit_card',
    'debit_card',
    'terminal',
    'mercado_pago',
    'mp',
    'bancaria',
  }.contains(value)) {
    return 'card';
  }
  if (value == 'consumo_empleado') return 'employee_consumption';
  return value;
}
