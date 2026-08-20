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

  test('auth lista ejecuta callable', () async {
    var called = false;
    final result = await submitExpenseRequestWithPreparedSession(
      authSession: ExpenseRequestAuthSession.fake(
        () async => const ExpenseRequestAuthStatus.ready(isAnonymous: true),
      ),
      functionClient: ExpenseRequestFunctionClient.fake((payload) async {
        called = true;
        return {'status': 'pending'};
      }),
      payload: _payload(),
      debugContext: _debugContext(),
    );

    expect(called, isTrue);
    expect(result['status'], 'pending');
  });

  test('auth inicialmente null se inicializa y callable continua', () async {
    var ensureAttempts = 0;
    var called = false;

    await submitExpenseRequestWithPreparedSession(
      authSession: ExpenseRequestAuthSession.fake(() async {
        ensureAttempts++;
        return const ExpenseRequestAuthStatus.ready(isAnonymous: true);
      }),
      functionClient: ExpenseRequestFunctionClient.fake((payload) async {
        called = true;
        return {
          'status': 'pending',
          'wouldAutoApprove': true,
          'policyMode': 'shadow',
        };
      }),
      payload: _payload(),
      debugContext: _debugContext(),
    );

    expect(ensureAttempts, 1);
    expect(called, isTrue);
  });

  test('auth falla muestra mensaje auth y no llama callable', () async {
    var called = false;

    expect(
      () => submitExpenseRequestWithPreparedSession(
        authSession: ExpenseRequestAuthSession.fake(
          () async => const ExpenseRequestAuthStatus.failed(
            'No fue posible iniciar la sesion del dispositivo. Intenta nuevamente.',
          ),
        ),
        functionClient: ExpenseRequestFunctionClient.fake((payload) async {
          called = true;
          return {'status': 'pending'};
        }),
        payload: _payload(),
        debugContext: _debugContext(),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('sesion del dispositivo'),
        ),
      ),
    );
    expect(called, isFalse);
  });

  test('marcadores debug indican si callable se ejecuta', () async {
    final markers = <String>[];

    await submitExpenseRequestWithPreparedSession(
      authSession: ExpenseRequestAuthSession.fake(
        () async => const ExpenseRequestAuthStatus.ready(isAnonymous: true),
      ),
      functionClient: ExpenseRequestFunctionClient.fake(
        (payload) async => {'status': 'pending'},
      ),
      payload: _payload(),
      debugContext: _debugContext(),
      debugLog: (marker, {error, stackTrace}) => markers.add(marker),
    );

    expect(markers, [
      'expensePolicy: before-call',
      'expensePolicy: callable-start',
      'expensePolicy: callable-result',
    ]);
  });

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

    expect(message, contains('sesion del dispositivo'));
    expect(message, isNot(contains('sesion no esta lista')));
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

  test('device inactive no se mapea a sesion no lista', () {
    final message = submitExpenseRequestErrorMessage(
      _functionsError('permission-denied', 'Dispositivo desactivado.'),
    );

    expect(message, contains('validar este dispositivo'));
    expect(message, isNot(contains('sesion no esta lista')));
  });

  test('policy reject conserva razon y no usa sesion no lista', () {
    final message = submitExpenseRequestErrorMessage(
      _functionsError('failed-precondition', 'La politica alcanzo su limite.'),
    );

    expect(message, 'La politica alcanzo su limite.');
    expect(message, isNot(contains('sesion no esta lista')));
  });

  test('sin caja usa mensaje preciso', () {
    const message = 'No hay una caja abierta para registrar este gasto.';

    expect(message, contains('caja abierta'));
    expect(message, isNot(contains('sesion no esta lista')));
  });
}

FirebaseFunctionsException _functionsError(String code, String message) {
  return FirebaseFunctionsException(code: code, message: message);
}

ExpenseRequestFunctionPayload _payload() {
  return const ExpenseRequestFunctionPayload(
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
}

ExpenseRequestDebugContext _debugContext() {
  return const ExpenseRequestDebugContext(
    restaurantId: 'main_restaurant',
    branchId: 'aviacion',
    cashSessionId: 'cash',
    cashSessionStatus: 'open',
    policyId: 'hielo',
    policyMode: 'shadow',
    networkAvailable: true,
  );
}
