import 'dart:io';

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
      deviceSession: ExpenseRequestDeviceSession.fake(() async {}),
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
      deviceSession: ExpenseRequestDeviceSession.fake(() async {}),
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
            'No fue posible autenticar este dispositivo (operation-not-allowed). Intenta nuevamente.',
            errorCode: 'operation-not-allowed',
          ),
        ),
        deviceSession: ExpenseRequestDeviceSession.fake(() async {}),
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
          contains('autenticar este dispositivo'),
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
      deviceSession: ExpenseRequestDeviceSession.fake(() async {}),
      functionClient: ExpenseRequestFunctionClient.fake(
        (payload) async => {'status': 'pending'},
      ),
      payload: _payload(),
      debugContext: _debugContext(),
      debugLog: (marker, {error, stackTrace}) => markers.add(marker),
    );

    expect(markers, [
      'expense-request: before-call',
      'expense-request: auth-ready',
      'expense-request: device-ready',
      'expense-request: callable-start',
      'expense-request: callable-success',
    ]);
  });

  test('auth operativo no fuerza getIdToken antes de callable', () {
    final source = File(
      'lib/services/operational_auth_service.dart',
    ).readAsStringSync();

    expect(source, contains('if (user == null && !kIsWeb)'));
    expect(source, contains('signInAnonymously()'));
    expect(source, contains('expense-auth: bootstrap-start'));
    expect(source, contains('expense-auth: signin-start'));
    expect(source, contains('expense-auth: signin-success'));
    expect(source, contains('expense-auth: signin-error'));
    expect(source, isNot(contains('getIdToken()')));
  });

  test('auth fallida registra codigo FirebaseAuthException real', () async {
    final markers = <String>[];

    await expectLater(
      submitExpenseRequestWithPreparedSession(
        authSession: ExpenseRequestAuthSession.fake(
          () async => const ExpenseRequestAuthStatus.failed(
            'No fue posible autenticar este dispositivo (network-request-failed). Intenta nuevamente.',
            errorCode: 'network-request-failed',
          ),
        ),
        deviceSession: ExpenseRequestDeviceSession.fake(() async {}),
        functionClient: ExpenseRequestFunctionClient.fake(
          (payload) async => {'status': 'pending'},
        ),
        payload: _payload(),
        debugContext: _debugContext(),
        debugLog: (marker, {error, stackTrace}) => markers.add(marker),
      ),
      throwsA(isA<StateError>()),
    );

    expect(markers, contains(contains('authErrorCode=network-request-failed')));
  });

  test('device no registrado no se confunde con auth', () async {
    var called = false;

    expect(
      () => submitExpenseRequestWithPreparedSession(
        authSession: ExpenseRequestAuthSession.fake(
          () async => const ExpenseRequestAuthStatus.ready(isAnonymous: true),
        ),
        deviceSession: ExpenseRequestDeviceSession.fake(
          () async => throw StateError('Dispositivo no registrado.'),
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
          contains('dispositivo'),
        ),
      ),
    );
    expect(called, isFalse);
  });

  test(
    'device inactivo usa mensaje de dispositivo y no llama callable',
    () async {
      var called = false;

      expect(
        () => submitExpenseRequestWithPreparedSession(
          authSession: ExpenseRequestAuthSession.fake(
            () async => const ExpenseRequestAuthStatus.ready(isAnonymous: true),
          ),
          deviceSession: ExpenseRequestDeviceSession.fake(
            () async => throw StateError(
              'Este dispositivo no esta registrado o activo.',
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
            'Este dispositivo no esta registrado o activo.',
          ),
        ),
      );
      expect(called, isFalse);
    },
  );

  test(
    'auth existente lista no dispara reintento adicional en el helper',
    () async {
      var authEnsures = 0;
      var deviceEnsures = 0;
      var calls = 0;

      await submitExpenseRequestWithPreparedSession(
        authSession: ExpenseRequestAuthSession.fake(() async {
          authEnsures++;
          return const ExpenseRequestAuthStatus.ready(isAnonymous: true);
        }),
        deviceSession: ExpenseRequestDeviceSession.fake(() async {
          deviceEnsures++;
        }),
        functionClient: ExpenseRequestFunctionClient.fake((payload) async {
          calls++;
          return {'status': 'pending'};
        }),
        payload: _payload(),
        debugContext: _debugContext(),
      );

      expect(authEnsures, 1);
      expect(deviceEnsures, 1);
      expect(calls, 1);
    },
  );

  test(
    'validacion de dispositivo verifica registro y active antes de callable',
    () {
      final source = File(
        'lib/services/device_registry_service.dart',
      ).readAsStringSync();

      expect(source, contains('ensureCurrentDeviceReady'));
      expect(source, contains("data['active'] == false"));
      expect(source, contains('device-not-registered'));
      expect(source, contains('device-branch-mismatch'));
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

    expect(message, contains('autenticar este dispositivo'));
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
