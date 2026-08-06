import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/employee_benefit_checkout.dart';
import 'package:tacopos/services/taco_pos_repository.dart';

void main() {
  group('employee discount usage persistence model', () {
    test('lee comida del dia con porcentaje 100 e importe completo', () {
      final row = DiscountUsageRow.fromMap('usage-daily-meal', {
        'businessDate': '2026-08-06',
        'discountType': employeeDailyMealDiscountType,
        'discountName': employeeDailyMealDiscountName,
        'discountPercent': 100,
        'amountBeforeDiscount': 80,
        'discountAmount': 80,
        'totalAfterDiscount': 0,
        'employeeName': 'Ana',
        'orderId': 'order-1',
        'status': 'active',
      });

      expect(row.discountType, employeeDailyMealDiscountType);
      expect(row.discountPercent, 100);
      expect(row.amountBeforeDiscount, 80);
      expect(row.discountAmount, 80);
      expect(row.totalAfterDiscount, 0);
      expect(row.employeeName, 'Ana');
      expect(row.orderId, 'order-1');
    });

    test('lee descuento normal con porcentaje 30 e importe neto', () {
      final row = DiscountUsageRow.fromMap('usage-regular', {
        'businessDate': '2026-08-06',
        'discountType': employeeRegularDiscountType,
        'discountName': employeeRegularDiscountName,
        'discountPercent': 30,
        'amountBeforeDiscount': 100,
        'discountAmount': 30,
        'totalAfterDiscount': 70,
        'employeeName': 'Luis',
        'orderId': 'order-2',
        'status': 'active',
      });

      expect(row.discountType, employeeRegularDiscountType);
      expect(row.discountPercent, 30);
      expect(row.amountBeforeDiscount, 100);
      expect(row.discountAmount, 30);
      expect(row.totalAfterDiscount, 70);
    });
  });
}
