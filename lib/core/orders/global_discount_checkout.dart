const globalDiscountSource = 'global';
const noDiscountSource = 'none';
const globalDiscountCatalogId = 'discounts';
const checkoutScopeMismatchMessage =
    'El importe del cobro ya no coincide con la orden actual. '
    'Se actualizaron los datos; revisa nuevamente antes de confirmar.';

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

class CheckoutAccountTotals {
  const CheckoutAccountTotals({
    required this.grossSubtotal,
    required this.discountAmount,
    required this.netTotal,
    required this.paidTotal,
    required this.pendingTotal,
  });

  final double grossSubtotal;
  final double discountAmount;
  final double netTotal;
  final double paidTotal;
  final double pendingTotal;

  bool get hasDiscount => discountAmount > 0.01;
}

double roundCheckoutMoney(double value) {
  return (value * 100).roundToDouble() / 100;
}

CheckoutAccountTotals calculateCheckoutAccountTotals({
  required double orderTotal,
  required double discountAmount,
  required Iterable<double> activePaymentAmounts,
  double? grossSubtotal,
  double? netTotal,
}) {
  final gross = roundCheckoutMoney(
    (grossSubtotal ?? orderTotal).clamp(0, double.infinity).toDouble(),
  );
  final discount = roundCheckoutMoney(
    discountAmount.clamp(0, gross).toDouble(),
  );
  final savedNetIsValid =
      netTotal != null && netTotal.isFinite && netTotal >= 0;
  final resolvedNet = roundCheckoutMoney(
    savedNetIsValid ? netTotal : gross - discount,
  );
  final paid = roundCheckoutMoney(
    activePaymentAmounts.fold<double>(
      0,
      (total, amount) => total + amount.clamp(0, double.infinity).toDouble(),
    ),
  );
  return CheckoutAccountTotals(
    grossSubtotal: gross,
    discountAmount: discount,
    netTotal: resolvedNet,
    paidTotal: paid,
    pendingTotal: roundCheckoutMoney(
      (resolvedNet - paid).clamp(0, double.infinity).toDouble(),
    ),
  );
}

double checkoutAppliedPaymentAmount({
  required double baseAmount,
  required double chargedAmount,
  required double totalAfterDiscount,
  required double discountAmount,
  double? appliedAmount,
}) {
  if (appliedAmount != null && appliedAmount.isFinite && appliedAmount >= 0) {
    return roundCheckoutMoney(appliedAmount);
  }
  if (totalAfterDiscount > 0 || discountAmount > 0) {
    return roundCheckoutMoney(
      totalAfterDiscount.clamp(0, double.infinity).toDouble(),
    );
  }
  if (chargedAmount > 0) {
    return roundCheckoutMoney(chargedAmount);
  }
  return roundCheckoutMoney(
    (baseAmount - discountAmount).clamp(0, double.infinity).toDouble(),
  );
}

String checkoutAccountTitle({
  required String orderType,
  required String displayName,
  String? customerName,
}) {
  final customer = customerName?.trim() ?? '';
  return switch (orderType) {
    'takeout' when customer.isNotEmpty =>
      'Cuenta actual · Para llevar · $customer',
    'standing' when customer.isNotEmpty =>
      'Cuenta actual · Parados sin mesa · $customer',
    'standing' => 'Cuenta actual · Parados sin mesa',
    _ => 'Cuenta actual · $displayName',
  };
}

String? checkoutDiscountIndicator({
  required bool hasDiscount,
  required String? concept,
  required double percent,
}) {
  if (!hasDiscount) return null;
  final cleanConcept = concept?.trim();
  final name = cleanConcept == null || cleanConcept.isEmpty
      ? 'Descuento aplicado'
      : cleanConcept;
  if (percent <= 0) return name;
  final formattedPercent = percent.toStringAsFixed(percent % 1 == 0 ? 0 : 2);
  return '$name · $formattedPercent% aplicado';
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

String? validateCheckoutDraftScope({
  required String currentOrderId,
  required double currentOrderTotal,
  required double currentSelectedAmount,
  String? currentRestaurantId,
  String? currentBranchId,
  String? currentBusinessDate,
  String? draftOrderId,
  String? draftRestaurantId,
  String? draftBranchId,
  String? draftBusinessDate,
  double? draftTotalSnapshot,
  double? draftAmountBeforeDiscount,
  double tolerance = 0.02,
}) {
  bool differs(String? draft, String? current) {
    final cleanDraft = draft?.trim();
    final cleanCurrent = current?.trim();
    return cleanDraft != null &&
        cleanDraft.isNotEmpty &&
        cleanCurrent != null &&
        cleanCurrent.isNotEmpty &&
        cleanDraft != cleanCurrent;
  }

  if (differs(draftOrderId, currentOrderId) ||
      differs(draftRestaurantId, currentRestaurantId) ||
      differs(draftBranchId, currentBranchId) ||
      differs(draftBusinessDate, currentBusinessDate)) {
    return checkoutScopeMismatchMessage;
  }
  if (draftTotalSnapshot != null &&
      (roundCheckoutMoney(draftTotalSnapshot) -
                  roundCheckoutMoney(currentOrderTotal))
              .abs() >
          tolerance) {
    return checkoutScopeMismatchMessage;
  }
  if (draftAmountBeforeDiscount != null &&
      (roundCheckoutMoney(draftAmountBeforeDiscount) -
                  roundCheckoutMoney(currentSelectedAmount))
              .abs() >
          tolerance) {
    return checkoutScopeMismatchMessage;
  }
  return null;
}
