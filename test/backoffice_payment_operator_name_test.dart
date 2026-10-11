import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/models/payment.dart';

void main() {
  group('Backoffice payment operator', () {
    test('shows the employee who registered payment, not the device UID', () {
      final payment = _payment(
        createdBy: 'H86pxMMMzaeuiDhlZfBqZkkzieE3',
        createdByEmployeeId: 'cashier-andres',
        createdByEmployeeName: '  Andrés  ',
        employeeName: 'Ricardo',
      );

      expect(payment.registeredByName, 'Andrés');
      expect(payment.registeredByName, isNot(payment.createdBy));
      expect(payment.registeredByName, isNot(payment.employeeName));
    });

    test('does not identify cashier from discount beneficiary or anonymous UID', () {
      final payment = _payment(
        createdBy: 'vEqa5yZKodPGGnBl2tXxPDxLUiU2',
        employeeName: 'Yamilet',
      );

      expect(payment.registeredByName, 'No identificado');
    });

    test('does not expose UID when operator name is empty', () {
      final payment = _payment(
        createdBy: 'firebase-anonymous-uid',
        createdByEmployeeName: '   ',
      );

      expect(payment.registeredByName, 'No identificado');
    });

    test('preserves operator audit fields when copying payment', () {
      final payment = _payment(
        createdBy: 'device-uid',
        createdByEmployeeId: 'cashier-andres',
        createdByEmployeeName: 'Andrés',
      );

      final updated = payment.copyWith(branchName: 'Aviación');

      expect(updated.registeredByName, 'Andrés');
      expect(updated.createdByEmployeeId, 'cashier-andres');
      expect(updated.createdBy, 'device-uid');
      expect(updated.branchName, 'Aviación');
    });
  });
}

Payment _payment({
  String? createdBy,
  String? createdByEmployeeId,
  String? createdByEmployeeName,
  String? employeeName,
}) {
  return Payment(
    id: 'payment-1',
    orderId: 'order-1',
    tableId: 'table-1',
    tableName: 'Mesa 1',
    type: 'full_table',
    method: 'cash',
    baseAmount: 140,
    surchargeRate: 0,
    surchargeAmount: 0,
    chargedAmount: 140,
    employeeName: employeeName,
    createdBy: createdBy,
    createdByEmployeeId: createdByEmployeeId,
    createdByEmployeeName: createdByEmployeeName,
  );
}
