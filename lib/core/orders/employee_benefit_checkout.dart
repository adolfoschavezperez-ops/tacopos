import 'global_discount_checkout.dart';

const employeeDailyMealDiscountType = 'employee_free_meal';
const employeeRegularDiscountType = 'employee_30';
const employeeDailyMealDiscountName = 'Comida empleado del dia';
const employeeRegularDiscountName = 'Descuento empleado 30%';
const employeeDailyMealDiscountPercent = 100.0;
const employeeRegularDiscountPercent = 30.0;

enum EmployeeBenefitType { dailyMeal, regularDiscount }

class EmployeeBenefitCheckoutResult {
  const EmployeeBenefitCheckoutResult({
    required this.type,
    required this.discountType,
    required this.name,
    required this.percent,
    required this.amountBeforeDiscount,
    required this.discountAmount,
    required this.totalAfterDiscount,
  });

  final EmployeeBenefitType type;
  final String discountType;
  final String name;
  final double percent;
  final double amountBeforeDiscount;
  final double discountAmount;
  final double totalAfterDiscount;
}

EmployeeBenefitType? employeeBenefitTypeFromDiscountType(String value) {
  return switch (value.trim()) {
    employeeDailyMealDiscountType => EmployeeBenefitType.dailyMeal,
    employeeRegularDiscountType => EmployeeBenefitType.regularDiscount,
    _ => null,
  };
}

String employeeBenefitDiscountType(EmployeeBenefitType type) {
  return switch (type) {
    EmployeeBenefitType.dailyMeal => employeeDailyMealDiscountType,
    EmployeeBenefitType.regularDiscount => employeeRegularDiscountType,
  };
}

String employeeBenefitName(EmployeeBenefitType type) {
  return switch (type) {
    EmployeeBenefitType.dailyMeal => employeeDailyMealDiscountName,
    EmployeeBenefitType.regularDiscount => employeeRegularDiscountName,
  };
}

double employeeBenefitPercent(EmployeeBenefitType type) {
  return switch (type) {
    EmployeeBenefitType.dailyMeal => employeeDailyMealDiscountPercent,
    EmployeeBenefitType.regularDiscount => employeeRegularDiscountPercent,
  };
}

EmployeeBenefitCheckoutResult calculateEmployeeBenefitCheckout({
  required EmployeeBenefitType type,
  required double eligiblePendingAmount,
}) {
  final cleanEligibleAmount = eligiblePendingAmount.isFinite
      ? eligiblePendingAmount
      : 0.0;
  final subtotal = roundCheckoutMoney(
    cleanEligibleAmount.clamp(0, double.infinity).toDouble(),
  );
  final percent = employeeBenefitPercent(type);
  final discount = switch (type) {
    EmployeeBenefitType.dailyMeal => subtotal,
    EmployeeBenefitType.regularDiscount => roundCheckoutMoney(
      subtotal * percent / 100,
    ),
  }.clamp(0, subtotal).toDouble();

  return EmployeeBenefitCheckoutResult(
    type: type,
    discountType: employeeBenefitDiscountType(type),
    name: employeeBenefitName(type),
    percent: percent,
    amountBeforeDiscount: subtotal,
    discountAmount: roundCheckoutMoney(discount),
    totalAfterDiscount: roundCheckoutMoney(subtotal - discount),
  );
}
