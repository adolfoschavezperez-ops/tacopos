import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/services/taco_pos_repository.dart';

void main() {
  test('callable usa region us-central1 y limited-use App Check', () {
    expect(
      ExpenseRequestFunctionClient.expenseRequestFunctionRegion,
      'us-central1',
    );
    expect(
      ExpenseRequestFunctionClient.submitExpenseRequestFunctionName,
      'submitExpenseRequest',
    );
    expect(expenseRequestCallableOptions().limitedUseAppCheckToken, isTrue);
  });

  test('payload conserva clientRequestId para idempotencia', () {
    const payload = ExpenseRequestFunctionPayload(
      restaurantId: 'main_restaurant',
      branchId: 'aviacion',
      policyId: 'hielo',
      amount: 40,
      supplierId: '',
      paymentSource: 'cash',
      reason: 'Hielo',
      requesterId: 'employee',
      requesterName: 'Empleado',
      requesterRole: 'staff',
      businessDate: '2026-08-20',
      cashSessionId: 'cash',
      clientRequestId: 'request-1',
      hasReceipt: false,
    );

    expect(payload.toMap()['clientRequestId'], 'request-1');
    expect(payload.toMap()['policyId'], 'hielo');
    expect(payload.toMap()['amount'], 40);
  });

  test(
    'success Hielo 40 devuelve respuesta real sin mensaje de conexion',
    () async {
      final client = ExpenseRequestFunctionClient.fake((payload) async {
        expect(payload.policyId, 'hielo');
        expect(payload.amount, 40);
        return {
          'status': 'pending',
          'wouldAutoApprove': true,
          'policyMode': 'shadow',
        };
      });

      const payload = ExpenseRequestFunctionPayload(
        restaurantId: 'main_restaurant',
        branchId: 'aviacion',
        policyId: 'hielo',
        amount: 40,
        supplierId: '',
        paymentSource: 'cash',
        reason: 'Hielo',
        requesterId: 'employee',
        requesterName: 'Empleado',
        requesterRole: 'staff',
        businessDate: '2026-08-20',
        cashSessionId: 'cash',
        clientRequestId: 'request-1',
        hasReceipt: false,
      );

      final result = await client.call(payload);

      expect(result['status'], 'pending');
      expect(result['wouldAutoApprove'], isTrue);
    },
  );

  test('unavailable se mapea a conexion', () {
    final message = submitExpenseRequestErrorMessage(
      _functionsError('unavailable', 'Network unavailable.'),
    );

    expect(message, contains('No hay conexion'));
  });

  test('unauthenticated de sesion no se mapea a offline', () {
    final message = submitExpenseRequestErrorMessage(
      _functionsError('unauthenticated', 'Auth required.'),
    );

    expect(message, contains('sesion'));
    expect(message, isNot(contains('No hay conexion')));
  });

  test('App Check failure no se mapea a offline', () {
    final message = submitExpenseRequestErrorMessage(
      _functionsError('unauthenticated', 'Se requiere App Check.'),
    );

    expect(message, contains('validar este dispositivo'));
    expect(message, isNot(contains('No hay conexion')));
  });

  test('policy rejection conserva razon de backend', () {
    final message = submitExpenseRequestErrorMessage(
      _functionsError('failed-precondition', 'Monto maximo excedido.'),
    );

    expect(message, 'Monto maximo excedido.');
  });

  test('timeout no se mapea a offline', () {
    final message = submitExpenseRequestErrorMessage(
      _functionsError('deadline-exceeded', 'Deadline exceeded.'),
    );

    expect(message, contains('tiempo'));
    expect(message, isNot(contains('No hay conexion')));
  });

  test('replay App Check queda como validacion de dispositivo', () {
    final message = submitExpenseRequestErrorMessage(
      _functionsError('permission-denied', 'Token App Check ya consumido.'),
    );

    expect(message, contains('validar este dispositivo'));
    expect(message, isNot(contains('No hay conexion')));
  });
}

FirebaseFunctionsException _functionsError(String code, String message) {
  return FirebaseFunctionsException(code: code, message: message);
}
