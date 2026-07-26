const globalDiscountSource = 'global';
const noDiscountSource = 'none';
const globalDiscountCatalogId = 'discounts';

class CheckoutDiscountAmounts {
  const CheckoutDiscountAmounts({
    required this.grossSubtotal,
    required this.discountAmount,
    required this.netTotal,
  });

  final double grossSubtotal;
  final double discountAmount;
  final double netTotal;
}

double roundCheckoutMoney(double value) {
  return (value * 100).roundToDouble() / 100;
}

CheckoutDiscountAmounts calculateGlobalDiscountAmounts({
  required double grossSubtotal,
  required double percent,
}) {
  final gross = roundCheckoutMoney(
    grossSubtotal.clamp(0, double.infinity).toDouble(),
  );
  final cleanPercent = percent.clamp(0, 100).toDouble();
  final discount = roundCheckoutMoney(
    gross * cleanPercent / 100,
  ).clamp(0, gross);
  return CheckoutDiscountAmounts(
    grossSubtotal: gross,
    discountAmount: discount.toDouble(),
    netTotal: roundCheckoutMoney(gross - discount),
  );
}

double allocateGlobalDiscount({
  required double orderGrossSubtotal,
  required double orderDiscountAmount,
  required double selectedGrossSubtotal,
  required double remainingGrossSubtotal,
  required double previouslyAllocatedDiscount,
}) {
  final orderGross = roundCheckoutMoney(orderGrossSubtotal);
  final orderDiscount = roundCheckoutMoney(
    orderDiscountAmount,
  ).clamp(0, orderGross);
  final selectedGross = roundCheckoutMoney(
    selectedGrossSubtotal,
  ).clamp(0, remainingGrossSubtotal);
  final remainingDiscount = roundCheckoutMoney(
    orderDiscount - previouslyAllocatedDiscount,
  ).clamp(0, orderDiscount);

  if (orderGross <= 0 || selectedGross <= 0 || remainingDiscount <= 0) {
    return 0;
  }
  if (selectedGross + 0.01 >= roundCheckoutMoney(remainingGrossSubtotal)) {
    return remainingDiscount.toDouble();
  }

  return roundCheckoutMoney(
    orderDiscount * selectedGross / orderGross,
  ).clamp(0, remainingDiscount).toDouble();
}

bool shouldRefreshGlobalDiscountSnapshot({required bool hasActivePayments}) {
  return !hasActivePayments;
}
