import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/employee_benefit_checkout.dart';

void main() {
  group('employee benefit checkout', () {
    test('comida del dia con subtotal 100 descuenta 100 y deja total 0', () {
      final result = calculateEmployeeBenefitCheckout(
        type: EmployeeBenefitType.dailyMeal,
        eligiblePendingAmount: 100,
      );

      expect(result.discountType, employeeDailyMealDiscountType);
      expect(result.name, employeeDailyMealDiscountName);
      expect(result.percent, 100);
      expect(result.amountBeforeDiscount, 100);
      expect(result.discountAmount, 100);
      expect(result.totalAfterDiscount, 0);
    });

    test('comida del dia con subtotal 235.50 descuenta 235.50', () {
      final result = calculateEmployeeBenefitCheckout(
        type: EmployeeBenefitType.dailyMeal,
        eligiblePendingAmount: 235.50,
      );

      expect(result.discountAmount, 235.50);
      expect(result.totalAfterDiscount, 0);
    });

    test('descuento normal con subtotal 100 descuenta 30 y deja total 70', () {
      final result = calculateEmployeeBenefitCheckout(
        type: EmployeeBenefitType.regularDiscount,
        eligiblePendingAmount: 100,
      );

      expect(result.discountType, employeeRegularDiscountType);
      expect(result.name, employeeRegularDiscountName);
      expect(result.percent, 30);
      expect(result.discountAmount, 30);
      expect(result.totalAfterDiscount, 70);
    });

    test('descuento normal con subtotal 235.50 descuenta 70.65', () {
      final result = calculateEmployeeBenefitCheckout(
        type: EmployeeBenefitType.regularDiscount,
        eligiblePendingAmount: 235.50,
      );

      expect(result.discountAmount, 70.65);
      expect(result.totalAfterDiscount, 164.85);
    });

    test('comida del dia no aplica adicionalmente el 30 por ciento', () {
      final result = calculateEmployeeBenefitCheckout(
        type: EmployeeBenefitType.dailyMeal,
        eligiblePendingAmount: 100,
      );

      expect(result.discountAmount, isNot(30));
      expect(result.totalAfterDiscount, isNot(70));
    });

    test('descuento normal no aplica el 100 por ciento', () {
      final result = calculateEmployeeBenefitCheckout(
        type: EmployeeBenefitType.regularDiscount,
        eligiblePendingAmount: 100,
      );

      expect(result.discountAmount, isNot(100));
      expect(result.totalAfterDiscount, isNot(0));
    });

    test(
      'cambiar de comida del dia a descuento normal recalcula desde subtotal',
      () {
        final dailyMeal = calculateEmployeeBenefitCheckout(
          type: EmployeeBenefitType.dailyMeal,
          eligiblePendingAmount: 235.50,
        );
        final regular = calculateEmployeeBenefitCheckout(
          type: EmployeeBenefitType.regularDiscount,
          eligiblePendingAmount: dailyMeal.amountBeforeDiscount,
        );

        expect(regular.discountAmount, 70.65);
        expect(regular.totalAfterDiscount, 164.85);
      },
    );

    test(
      'cambiar de descuento normal a comida del dia reemplaza el beneficio',
      () {
        final regular = calculateEmployeeBenefitCheckout(
          type: EmployeeBenefitType.regularDiscount,
          eligiblePendingAmount: 235.50,
        );
        final dailyMeal = calculateEmployeeBenefitCheckout(
          type: EmployeeBenefitType.dailyMeal,
          eligiblePendingAmount: regular.amountBeforeDiscount,
        );

        expect(dailyMeal.discountAmount, 235.50);
        expect(dailyMeal.totalAfterDiscount, 0);
      },
    );

    test('el descuento nunca supera el saldo pendiente', () {
      final dailyMeal = calculateEmployeeBenefitCheckout(
        type: EmployeeBenefitType.dailyMeal,
        eligiblePendingAmount: 80,
      );
      final regular = calculateEmployeeBenefitCheckout(
        type: EmployeeBenefitType.regularDiscount,
        eligiblePendingAmount: 80,
      );

      expect(dailyMeal.discountAmount, lessThanOrEqualTo(80));
      expect(regular.discountAmount, lessThanOrEqualTo(80));
    });

    test('un saldo pendiente de 80 genera descuento maximo 80 en comida', () {
      final result = calculateEmployeeBenefitCheckout(
        type: EmployeeBenefitType.dailyMeal,
        eligiblePendingAmount: 80,
      );

      expect(result.discountAmount, 80);
      expect(result.totalAfterDiscount, 0);
    });

    test('mantiene calculos monetarios a dos decimales sin negativos', () {
      final result = calculateEmployeeBenefitCheckout(
        type: EmployeeBenefitType.regularDiscount,
        eligiblePendingAmount: 33.335,
      );

      expect(result.amountBeforeDiscount, 33.34);
      expect(result.discountAmount, 10);
      expect(result.totalAfterDiscount, 23.34);
      expect(result.totalAfterDiscount, greaterThanOrEqualTo(0));
    });

    test('normaliza importes invalidos como cero', () {
      final result = calculateEmployeeBenefitCheckout(
        type: EmployeeBenefitType.dailyMeal,
        eligiblePendingAmount: double.infinity,
      );

      expect(result.amountBeforeDiscount, 0);
      expect(result.discountAmount, 0);
      expect(result.totalAfterDiscount, 0);
    });

    test('resuelve tipos persistidos de beneficios', () {
      expect(
        employeeBenefitTypeFromDiscountType(employeeDailyMealDiscountType),
        EmployeeBenefitType.dailyMeal,
      );
      expect(
        employeeBenefitTypeFromDiscountType(employeeRegularDiscountType),
        EmployeeBenefitType.regularDiscount,
      );
      expect(employeeBenefitTypeFromDiscountType('general'), isNull);
    });
  });
}
