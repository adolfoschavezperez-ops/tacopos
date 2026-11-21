import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/constants/app_constants.dart';
import 'package:tacopos/core/payments/payment_cancellation.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/services/app_session.dart';
import 'package:tacopos/services/live_presence_service.dart';
import 'package:tacopos/services/taco_pos_repository.dart';

// Exercises the production TacoPosRepository.cancelPayment against an
// in-memory Firestore that reproduces the client SDK transaction contract:
// reads are versioned, a commit whose read set changed re-runs the handler
// (like the SDK), and writes apply atomically or not at all.

const _root = 'restaurants/${AppConstants.restaurantId}';
const _order = '$_root/orders/o1';
const _cashSession = '$_root/cashSessions/cs1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    await Firebase.initializeApp();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceSet',
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
    AppSession.instance.signIn(Employee.fromDoc(_EmployeeDoc()));
  });
  tearDownAll(() async {
    await LivePresenceService.instance.stop();
    AppSession.instance.signOut();
  });

  group('componentes puros', () {
    test('comparacion profunda detecta cualquier cambio de la orden', () {
      final base = {
        'total': 300,
        'captureRevision': 5,
        'updatedAt': Timestamp(100, 5),
        'tableIds': ['t1'],
        'discount': {'name': 'x', 'percent': 10},
      };
      expect(
        orderSnapshotUnchanged(discovered: base, current: _copy(base)),
        isTrue,
      );
      for (final change in <Map<String, dynamic>>[
        {'total': 301},
        {'updatedAt': Timestamp(100, 6)},
        {
          'tableIds': ['t1', 't2'],
        },
        {
          'discount': {'name': 'x', 'percent': 15},
        },
        {'paidTotal': 0},
      ]) {
        final current = {..._copy(base), ...change};
        expect(
          orderSnapshotUnchanged(discovered: base, current: current),
          isFalse,
          reason: '$change',
        );
      }
      final removed = _copy(base)..remove('discount');
      expect(
        orderSnapshotUnchanged(discovered: base, current: removed),
        isFalse,
      );
      expect(orderSnapshotUnchanged(discovered: null, current: base), isFalse);
    });

    test('la autorizacion solo se libera si la usa el pago cancelado', () {
      bool restore(Map<String, dynamic>? data) =>
          shouldRestoreDiscountAuthorization(
            authorization: data,
            paymentId: 'p1',
          );
      expect(restore({'status': 'used', 'usedPaymentId': 'p1'}), isTrue);
      expect(restore({'status': 'used', 'usedPaymentId': 'p2'}), isFalse);
      expect(restore({'status': 'used', 'usedPaymentId': ''}), isFalse);
      expect(restore({'status': 'approved', 'usedPaymentId': 'p1'}), isFalse);
      expect(restore(null), isFalse);
    });

    test(
      'usos de descuento se localizan por paymentId y se cancelan todos los activos',
      () {
        expect(
          discountUsageIdsToCancel(
            orderId: 'o1',
            paymentId: 'p1',
            usagesById: {
              'random-b': {
                'paymentId': 'p1',
                'orderId': 'o1',
                'status': 'active',
              },
              'random-a': {'paymentId': 'p1', 'status': 'active'},
              'old': {
                'paymentId': 'p1',
                'orderId': 'o1',
                'status': 'cancelled',
              },
              'other': {'paymentId': 'p2', 'orderId': 'o1', 'status': 'active'},
            },
          ),
          ['random-a', 'random-b'],
        );
        expect(
          () => discountUsageIdsToCancel(
            orderId: 'o1',
            paymentId: 'p1',
            usagesById: {
              'x': {'paymentId': 'p1', 'orderId': 'o9', 'status': 'active'},
            },
          ),
          throwsStateError,
        );
      },
    );

    test('solo conflictos se reintentan; permisos y red no', () {
      FirebaseException fe(String code) =>
          FirebaseException(plugin: 'cloud_firestore', code: code);
      expect(
        isRetryablePaymentCancellationError(
          const PaymentCancellationConflict('x'),
        ),
        isTrue,
      );
      expect(isRetryablePaymentCancellationError(fe('aborted')), isTrue);
      for (final code in [
        'permission-denied',
        'failed-precondition',
        'invalid-argument',
        'unavailable',
        'not-found',
      ]) {
        expect(
          isRetryablePaymentCancellationError(fe(code)),
          isFalse,
          reason: code,
        );
      }
      expect(isPaymentCancellationConnectivityError(fe('unavailable')), isTrue);
      expect(
        isPaymentCancellationConnectivityError(fe('permission-denied')),
        isFalse,
      );
      expect(
        paymentCancellationActivityId(orderId: 'o1', paymentId: 'p1'),
        'payment_cancelled_o1_p1',
      );
    });
  });

  group('cancelPayment real: concurrencia', () {
    test('1. cancelar P1 mientras otra tablet registra P2 (C1)', () async {
      final db = _seed();
      db.beforeTransaction = (call) async {
        if (call == 1) _registerPayment(db, 'p2', 100);
      };
      final result = await _cancel(db, 'p1');
      expect(result.outcome, PaymentCancellationOutcome.cancelled);
      _expectConsistent(db, total: 300, paid: 100);
      expect(db.data('$_order/payments/p2')!['status'], 'active');
      expect(db.transactionCalls, 2);
    });

    test('2. dos tablets cancelan pagos distintos (C2)', () async {
      final db = _seed(payments: {'p1': 100, 'p2': 100});
      db.beforeTransaction = (call) async {
        if (call == 1) {
          db.beforeTransaction = null;
          await _cancel(db, 'p2');
        }
      };
      await _cancel(db, 'p1');
      _expectConsistent(db, total: 300, paid: 0);
      expect(db.data('$_order/payments/p1')!['status'], 'cancelled');
      expect(db.data('$_order/payments/p2')!['status'], 'cancelled');
    });

    test(
      '3. dos tablets cancelan el mismo pago: una sola cancelacion y un registro',
      () async {
        final db = _seed(payments: {'p1': 100, 'p2': 50});
        PaymentCancellationResult? other;
        db.beforeTransaction = (call) async {
          if (call == 1) {
            db.beforeTransaction = null;
            other = await _cancel(db, 'p1');
          }
        };
        final mine = await _cancel(db, 'p1');
        expect(other!.outcome, PaymentCancellationOutcome.cancelled);
        expect(mine.outcome, PaymentCancellationOutcome.alreadyCancelled);
        _expectConsistent(db, total: 300, paid: 50);
        expect(db.docsUnder('$_root/activityLog'), hasLength(1));
        expect(db.data(_order)!['captureRevision'], 6);
      },
    );

    test('4. cancelar mientras se agrega un articulo (C4)', () async {
      final db = _seed();
      db.beforeTransaction = (call) async {
        if (call == 1) _addItem28(db, 'i2', 50);
      };
      await _cancel(db, 'p1');
      _expectConsistent(db, total: 350, paid: 0);
    });

    test('5. cancelar mientras se modifica una cantidad', () async {
      final db = _seed();
      db.beforeTransaction = (call) async {
        if (call == 1) {
          db.write('$_order/items/i1', {'qty': 2, 'total': 600});
          db.write(_order, {'captureRevision': 6});
        }
      };
      await _cancel(db, 'p1');
      _expectConsistent(db, total: 600, paid: 0);
    });

    test(
      '6. cancelar mientras otra tablet cierra la venta: no escribe nada',
      () async {
        final db = _seed();
        db.beforeTransaction = (call) async {
          if (call == 1) {
            _registerPayment(db, 'pf', 200);
            db.write(_order, {
              'status': 'paid',
              'paymentStatus': 'paid',
              'pendingTotal': 0,
              'paidTotal': 300,
            });
          }
        };
        await expectLater(
          _cancel(db, 'p1'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('orden cerrada'),
            ),
          ),
        );
        expect(db.data('$_order/payments/p1')!['status'], 'active');
        expect(db.data(_order)!['status'], 'paid');
        expect(db.data(_order)!['paidTotal'], 300);
        expect(db.docsUnder('$_root/activityLog'), isEmpty);
      },
    );

    test('7. cancelar durante una modificacion del total', () async {
      final db = _seed(items: {'i1': 300, 'i2': 40});
      db.write(_order, {'total': 300});
      db.beforeTransaction = (call) async {
        if (call == 1) db.write(_order, {'total': 340, 'captureRevision': 6});
      };
      await _cancel(db, 'p1');
      _expectConsistent(db, total: 340, paid: 0);
    });

    test(
      '8-9. cambio de la orden sin cambiar captureRevision se detecta',
      () async {
        final db = _seed();
        db.beforeTransaction = (call) async {
          if (call == 1) {
            // Legacy +27 writer: updates the parent without a revision.
            _registerPayment(db, 'p27', 100, bumpRevision: false);
          }
        };
        await _cancel(db, 'p1');
        expect(db.transactionCalls, 2);
        _expectConsistent(db, total: 300, paid: 100);
      },
    );

    test(
      '10/20. conflicto continuo agota reintentos sin escrituras parciales',
      () async {
        final db = _seed();
        var n = 0;
        db.beforeTransaction = (_) async => db.write(_order, {'touch': ++n});
        final before = db.snapshotExcept('touch');
        await expectLater(
          _cancel(db, 'p1'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('No se cancelo'),
            ),
          ),
        );
        expect(db.transactionCalls, paymentCancellationMaxAttempts);
        expect(db.snapshotExcept('touch'), before);
      },
    );

    test(
      '25. pago modificado durante la transaccion: el SDK reintenta con datos vigentes',
      () async {
        final db = _seed(payments: {'p1': 100, 'p2': 100});
        var once = true;
        db.beforeCommit = () async {
          if (!once) return;
          once = false;
          db.write('$_order/payments/p2', {'status': 'cancelled'});
        };
        await _cancel(db, 'p1');
        _expectConsistent(db, total: 300, paid: 0);
        expect(db.handlerRuns, greaterThan(db.transactionCalls));
      },
    );
  });

  group('cancelPayment real: descuentos', () {
    test(
      '11/13. uso historico con ID aleatorio y autorizacion del mismo pago',
      () async {
        final db = _seed();
        db.write('$_order/payments/p1', {
          'discountAuthorizationRequestId': 'a1',
        });
        db.write('$_root/discountUsage/zR4nd0m', {
          'paymentId': 'p1',
          'orderId': 'o1',
          'status': 'active',
        });
        db.write('$_root/discountAuthorizationRequests/a1', {
          'status': 'used',
          'usedPaymentId': 'p1',
        });
        await _cancel(db, 'p1');
        expect(db.data('$_root/discountUsage/zR4nd0m')!['status'], 'cancelled');
        expect(db.data('$_root/discountUsage/p1'), isNull);
        expect(
          db.data('$_root/discountAuthorizationRequests/a1')!['status'],
          'approved',
        );
        expect(
          db.data('$_root/discountAuthorizationRequests/a1')!['usedPaymentId'],
          '',
        );
      },
    );

    test('12. autorizacion usada por otro pago no se libera', () async {
      final db = _seed();
      db.write('$_order/payments/p1', {'discountAuthorizationRequestId': 'a1'});
      db.write('$_root/discountAuthorizationRequests/a1', {
        'status': 'used',
        'usedPaymentId': 'p2',
      });
      await _cancel(db, 'p1');
      expect(
        db.data('$_root/discountAuthorizationRequests/a1')!['status'],
        'used',
      );
      expect(
        db.data('$_root/discountAuthorizationRequests/a1')!['usedPaymentId'],
        'p2',
      );
    });

    test(
      '14. cancelacion repetida del mismo descuento no repite cambios',
      () async {
        final db = _seed();
        db.write('$_order/payments/p1', {
          'discountAuthorizationRequestId': 'a1',
        });
        db.write('$_root/discountUsage/u1', {
          'paymentId': 'p1',
          'orderId': 'o1',
          'status': 'active',
        });
        db.write('$_root/discountAuthorizationRequests/a1', {
          'status': 'used',
          'usedPaymentId': 'p1',
        });
        await _cancel(db, 'p1');
        db.write('$_root/discountAuthorizationRequests/a1', {
          'status': 'used',
          'usedPaymentId': 'p9',
        });
        final before = db.snapshot();
        final again = await _cancel(db, 'p1');
        expect(again.outcome, PaymentCancellationOutcome.alreadyCancelled);
        expect(db.snapshot(), before);
      },
    );

    test(
      '15. autorizacion reutilizada durante la cancelacion no se libera',
      () async {
        final db = _seed();
        db.write('$_order/payments/p1', {
          'discountAuthorizationRequestId': 'a1',
        });
        db.write('$_root/discountAuthorizationRequests/a1', {
          'status': 'used',
          'usedPaymentId': 'p1',
        });
        var once = true;
        db.beforeCommit = () async {
          if (!once) return;
          once = false;
          // Another flow consumed the authorization while this one was running.
          db.write('$_root/discountAuthorizationRequests/a1', {
            'usedPaymentId': 'p9',
          });
        };
        await _cancel(db, 'p1');
        expect(
          db.data('$_root/discountAuthorizationRequests/a1')!['status'],
          'used',
        );
        expect(
          db.data('$_root/discountAuthorizationRequests/a1')!['usedPaymentId'],
          'p9',
        );
      },
    );
  });

  group('cancelPayment real: caja y conectividad', () {
    test('16. sesion de caja abierta', () async {
      final db = _seed();
      final result = await _cancel(db, 'p1');
      expect(result.authoritativePendingTotal, 300);
    });

    test('17. caja en cierre: rechaza sin escribir', () async {
      final db = _seed();
      db.write(_cashSession, {'status': 'closing'});
      final before = db.snapshot();
      await expectLater(_cancel(db, 'p1'), throwsA(isA<StateError>()));
      expect(db.snapshot(), before);
    });

    test('18. sin conexion: error claro y sin escrituras', () async {
      final db = _seed()..offline = true;
      final before = db.snapshot();
      await expectLater(
        _cancel(db, 'p1'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Sin conexion'),
          ),
        ),
      );
      expect(db.snapshot(), before);
    });

    test(
      '19. respuesta perdida tras confirmar: reintento seguro sin duplicar',
      () async {
        final db = _seed()..loseResponseOnNextCommit = true;
        await expectLater(_cancel(db, 'p1'), throwsA(isA<StateError>()));
        expect(db.data('$_order/payments/p1')!['status'], 'cancelled');
        final retry = await _cancel(db, 'p1');
        expect(retry.outcome, PaymentCancellationOutcome.alreadyCancelled);
        expect(db.docsUnder('$_root/activityLog'), hasLength(1));
        _expectConsistent(db, total: 300, paid: 0);
      },
    );

    test('21. error de permisos no se reintenta ni escribe', () async {
      final db = _seed()..denyCommitCode = 'permission-denied';
      final before = db.snapshot();
      await expectLater(
        _cancel(db, 'p1'),
        throwsA(
          isA<FirebaseException>().having(
            (e) => e.code,
            'code',
            'permission-denied',
          ),
        ),
      );
      expect(db.transactionCalls, 1);
      expect(db.snapshot(), before);
    });
  });

  group('cancelPayment real: compatibilidad', () {
    test(
      '22-23. orden creada por +27 sin captureRevision ni orderId en pagos',
      () async {
        final db = _seed(revision: null, paymentOrderId: false);
        db.write(_order, {'tableIds': null});
        await _cancel(db, 'p1');
        _expectConsistent(db, total: 300, paid: 0);
        expect(db.data(_order)!['captureRevision'], 1);
      },
    );

    test(
      '24. orden modificada por escritor antiguo antes de la transaccion',
      () async {
        final db = _seed();
        db.beforeTransaction = (call) async {
          if (call == 1) {
            db.write(_order, {
              'paidTotal': 999,
              'updatedAt': Timestamp(200, 0),
            });
          }
        };
        await _cancel(db, 'p1');
        expect(db.transactionCalls, 2);
        _expectConsistent(db, total: 300, paid: 0);
      },
    );

    test(
      'riesgo residual documentado: articulo legacy creado sin tocar la orden',
      () async {
        final db = _seed();
        db.beforeTransaction = (call) async {
          // +27 writes only the item; its later recalculation is a separate write.
          if (call == 1) db.write('$_order/items/i27', _item(80));
        };
        await _cancel(db, 'p1');
        expect(
          db.data(_order)!['total'],
          300,
          reason: 'el articulo legacy no se descubre en esta ventana',
        );
      },
    );
  });

  group('consumidor Live Operations (flujo de operador real)', () {
    Future<OperatorPaymentCancellationReport> operator(
      _Db db,
      List<String> interventions, {
      Future<void> Function()? failIntervention,
    }) {
      return runOperatorPaymentCancellation(
        cancel: () => _cancel(db, 'p1'),
        recordIntervention: () async {
          if (failIntervention != null) await failIntervention();
          interventions.add('cancel_payment:p1');
        },
      );
    }

    void expectNoSuccess(OperatorPaymentCancellationReport report) {
      expect(report.status, OperatorPaymentCancellationStatus.failed);
      expect(report.paymentIsCancelled, isFalse);
      expect(report.message, isNot(startsWith('Pago cancelado')));
      expect(report.message, isNot(contains('ya había')));
    }

    test('1. primera cancelacion registra una intervencion', () async {
      final db = _seed();
      final interventions = <String>[];
      final report = await operator(db, interventions);
      expect(report.status, OperatorPaymentCancellationStatus.cancelled);
      expect(report.message, 'Pago cancelado.');
      expect(interventions, ['cancel_payment:p1']);
      expect(db.data('$_order/payments/p1')!['status'], 'cancelled');
    });

    test('2. segunda cancelacion no registra otra intervencion', () async {
      final db = _seed();
      final interventions = <String>[];
      await operator(db, interventions);
      final again = await operator(db, interventions);
      expect(again.status, OperatorPaymentCancellationStatus.alreadyCancelled);
      expect(again.message, startsWith('El pago ya había sido cancelado.'));
      expect(interventions, hasLength(1));
    });

    test('3. dos dispositivos simultaneos: una intervencion', () async {
      final db = _seed();
      final interventions = <String>[];
      OperatorPaymentCancellationReport? other;
      db.beforeTransaction = (call) async {
        if (call == 1) {
          db.beforeTransaction = null;
          other = await operator(db, interventions);
        }
      };
      final mine = await operator(db, interventions);
      expect(
        {other!.status, mine.status},
        {
          OperatorPaymentCancellationStatus.cancelled,
          OperatorPaymentCancellationStatus.alreadyCancelled,
        },
      );
      expect(interventions, hasLength(1));
      expect(db.docsUnder('$_root/activityLog'), hasLength(1));
    });

    test('5. sin conexion: sin exito ni intervencion', () async {
      final db = _seed()..offline = true;
      final interventions = <String>[];
      final report = await operator(db, interventions);
      expectNoSuccess(report);
      expect(report.message, contains('Sin conexion'));
      expect(interventions, isEmpty);
    });

    test('6. permisos: sin exito ni intervencion', () async {
      final db = _seed()..denyCommitCode = 'permission-denied';
      final interventions = <String>[];
      final report = await operator(db, interventions);
      expectNoSuccess(report);
      expect(report.message, contains('permisos'));
      expect(interventions, isEmpty);
      expect(db.data('$_order/payments/p1')!['status'], 'active');
    });

    test('7. caja cerrada: sin exito ni intervencion', () async {
      final db = _seed();
      db.write(_cashSession, {'status': 'closed'});
      final interventions = <String>[];
      final report = await operator(db, interventions);
      expectNoSuccess(report);
      expect(report.message, contains('caja'));
      expect(interventions, isEmpty);
    });

    test(
      '8. falla la intervencion tras cancelar: no se informa reversion ni se duplica',
      () async {
        final db = _seed();
        final interventions = <String>[];
        final report = await operator(
          db,
          interventions,
          failIntervention: () async => throw StateError('activityLog offline'),
        );
        expect(
          report.status,
          OperatorPaymentCancellationStatus.cancelledInterventionNotRecorded,
        );
        expect(report.paymentIsCancelled, isTrue);
        expect(report.message, startsWith('Pago cancelado.'));
        expect(report.message, contains('sigue vigente'));
        expect(report.message.toLowerCase(), isNot(contains('revert')));
        expect(db.data('$_order/payments/p1')!['status'], 'cancelled');
        final retry = await operator(db, interventions);
        expect(
          retry.status,
          OperatorPaymentCancellationStatus.alreadyCancelled,
        );
        expect(interventions, isEmpty);
        _expectConsistent(db, total: 300, paid: 0);
      },
    );

    test('9. mensajes de error no incluyen confirmaciones de exito', () {
      for (final error in <Object>[
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        FirebaseException(plugin: 'cloud_firestore', code: 'internal'),
        StateError('La caja de este pago ya no esta abierta.'),
        ArgumentError('Pago u orden invalidos.'),
        Exception('x'),
      ]) {
        final message = paymentCancellationFailureMessage(error);
        expect(message, isNot(startsWith('Pago cancelado')), reason: '$error');
        expect(message, isNot(contains('ya había')), reason: '$error');
      }
      expect(
        paymentCancellationSuccessMessage(PaymentCancellationOutcome.cancelled),
        'Pago cancelado.',
      );
      expect(
        paymentCancellationSuccessMessage(
          PaymentCancellationOutcome.alreadyCancelled,
        ),
        'El pago ya había sido cancelado.',
      );
    });
  });
}

Future<PaymentCancellationResult> _cancel(_Db db, String paymentId) {
  return TacoPosRepository(
    firestore: db,
    auth: _Auth(),
  ).cancelPayment(orderId: 'o1', paymentId: paymentId, reason: 'Prueba');
}

Map<String, dynamic> _item(num total) => {
  'qty': 1,
  'unitPrice': total,
  'total': total,
  'status': 'active',
  'paymentStatus': 'pending',
  'kitchenStatus': 'ready',
};

_Db _seed({
  Map<String, num> items = const {'i1': 300},
  Map<String, num> payments = const {'p1': 100},
  int? revision = 5,
  bool paymentOrderId = true,
}) {
  final db = _Db();
  final total = items.values.fold<num>(0, (a, b) => a + b);
  final paid = payments.values.fold<num>(0, (a, b) => a + b);
  db.write(_cashSession, {'status': 'open'});
  db.write(_order, {
    'restaurantId': AppConstants.restaurantId,
    'branchId': 'aviacion',
    'status': 'ready',
    'kitchenStatus': 'ready',
    'total': total,
    'paidTotal': paid,
    'pendingTotal': total - paid,
    'paymentStatus': paid > 0 ? 'partial' : 'pending',
    'updatedAt': Timestamp(100, 0),
    'captureRevision': ?revision,
  });
  items.forEach((id, value) => db.write('$_order/items/$id', _item(value)));
  payments.forEach((id, value) {
    db.write('$_order/payments/$id', {
      if (paymentOrderId) 'orderId': 'o1',
      'status': 'active',
      'type': 'partial',
      'method': 'cash',
      'baseAmount': value,
      'appliedAmount': value,
      'chargedAmount': value,
      'cashSessionId': 'cs1',
    });
  });
  return db;
}

void _registerPayment(
  _Db db,
  String id,
  num amount, {
  bool bumpRevision = true,
}) {
  db.write('$_order/payments/$id', {
    'orderId': 'o1',
    'status': 'active',
    'type': 'partial',
    'method': 'cash',
    'baseAmount': amount,
    'appliedAmount': amount,
    'chargedAmount': amount,
    'cashSessionId': 'cs1',
  });
  final order = db.data(_order)!;
  db.write(_order, {
    'paidTotal': (order['paidTotal'] as num) + amount,
    'pendingTotal': (order['pendingTotal'] as num) - amount,
    'updatedAt': Timestamp(150, db.version),
    if (bumpRevision)
      'captureRevision': ((order['captureRevision'] as num?) ?? 0) + 1,
  });
}

void _addItem28(_Db db, String id, num value) {
  db.write('$_order/items/$id', _item(value));
  final order = db.data(_order)!;
  db.write(_order, {
    'captureRevision': ((order['captureRevision'] as num?) ?? 0) + 1,
  });
}

void _expectConsistent(_Db db, {required num total, required num paid}) {
  final order = db.data(_order)!;
  final activePaid = db
      .docsUnder('$_order/payments')
      .values
      .where((p) => p['status'] == 'active')
      .fold<num>(0, (a, p) => a + (p['baseAmount'] as num));
  expect(activePaid, paid, reason: 'pagos activos');
  expect(order['total'], total);
  expect(order['paidTotal'], paid);
  expect(order['pendingTotal'], total - paid);
}

Map<String, dynamic> _copy(Map<String, dynamic> source) => {
  for (final entry in source.entries)
    entry.key: entry.value is Map
        ? _copy(Map<String, dynamic>.from(entry.value as Map))
        : entry.value is List
        ? List.of(entry.value as List)
        : entry.value,
};

// ignore: subtype_of_sealed_class
class _EmployeeDoc implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  String get id => 'cajero';
  @override
  Map<String, dynamic> data() => {'name': 'Caja', 'canCancelPayments': true};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements FirebaseAuth {
  @override
  User? get currentUser => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Db implements FirebaseFirestore {
  final _docs = <String, Map<String, dynamic>>{};
  final _versions = <String, int>{};
  int version = 0;
  int transactionCalls = 0;
  int handlerRuns = 0;
  bool offline = false;
  bool loseResponseOnNextCommit = false;
  String? denyCommitCode;
  Future<void> Function(int call)? beforeTransaction;
  Future<void> Function()? beforeCommit;

  Map<String, dynamic>? data(String path) => _docs[path];

  Map<String, Map<String, dynamic>> docsUnder(String collectionPath) => {
    for (final entry in _docs.entries)
      if (_parentOf(entry.key) == collectionPath) entry.key: entry.value,
  };

  void write(String path, Map<String, dynamic> data) {
    _docs[path] = {...?_docs[path], ...data}..removeWhere((_, v) => v == null);
    _versions[path] = ++version;
  }

  String snapshot() => _canonical(_docs);
  String snapshotExcept(String field) => _canonical({
    for (final e in _docs.entries) e.key: {...e.value}..remove(field),
  });

  void ensureOnline() {
    if (offline) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
  }

  void apply(Map<String, (String, Map<Object, Object?>)> writes) {
    for (final entry in writes.entries) {
      final (kind, data) = entry.value;
      final current = kind == 'set'
          ? <String, dynamic>{}
          : {...?_docs[entry.key]};
      if (kind == 'update' && !_docs.containsKey(entry.key)) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
      }
      for (final field in data.entries) {
        final key = field.key as String;
        final value = field.value;
        if (value == FieldValue.delete()) {
          current.remove(key);
        } else if (value == FieldValue.serverTimestamp()) {
          current[key] = Timestamp(1000 + version, 0);
        } else if (value == FieldValue.increment(1)) {
          current[key] = ((current[key] as num?) ?? 0) + 1;
        } else if (value is FieldValue) {
          throw UnimplementedError('$value');
        } else {
          current[key] = value;
        }
      }
      _docs[entry.key] = current;
      _versions[entry.key] = ++version;
    }
  }

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    transactionCalls++;
    await beforeTransaction?.call(transactionCalls);
    ensureOnline();
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      handlerRuns++;
      final tx = _Tx(this);
      final result = await transactionHandler(tx);
      await beforeCommit?.call();
      final stale = tx.readVersions.entries.any(
        (e) => (_versions[e.key] ?? 0) != e.value,
      );
      if (stale) continue;
      final denied = denyCommitCode;
      if (denied != null) {
        throw FirebaseException(plugin: 'cloud_firestore', code: denied);
      }
      apply(tx.writes);
      if (loseResponseOnNextCommit) {
        loseResponseOnNextCommit = false;
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      }
      return result;
    }
    throw FirebaseException(plugin: 'cloud_firestore', code: 'aborted');
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Col(this, path);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _parentOf(String path) => path.substring(0, path.lastIndexOf('/'));

String _canonical(Map<String, Map<String, dynamic>> docs) {
  final keys = docs.keys.toList()..sort();
  return keys
      .map((k) {
        final fields = docs[k]!.keys.toList()..sort();
        return '$k{${fields.map((f) => '$f=${docs[k]![f]}').join(',')}}';
      })
      .join('\n');
}

class _Tx implements Transaction {
  _Tx(this.db);
  final _Db db;
  final readVersions = <String, int>{};
  final writes = <String, (String, Map<Object, Object?>)>{};

  @override
  Future<DocumentSnapshot<T>> get<T>(DocumentReference<T> documentRef) async {
    if (writes.isNotEmpty) throw StateError('reads must precede writes');
    readVersions[documentRef.path] = db._versions[documentRef.path] ?? 0;
    return _Snap(db, documentRef.path) as DocumentSnapshot<T>;
  }

  @override
  Transaction update(DocumentReference documentRef, Map<Object, Object?> data) {
    final previous = writes[documentRef.path];
    writes[documentRef.path] = (
      previous?.$1 ?? 'update',
      {...?previous?.$2, ...data},
    );
    return this;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> documentRef,
    T data, [
    SetOptions? options,
  ]) {
    writes[documentRef.path] = ('set', Map<Object, Object?>.from(data as Map));
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Col implements CollectionReference<Map<String, dynamic>> {
  _Col(this.db, this.path, [this.filter]);
  final _Db db;
  @override
  final String path;
  final (String, Object?)? filter;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      _Ref(db, '$path/$id');

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    db.ensureOnline();
    final docs = db.docsUnder(path).entries.where((e) {
      final f = filter;
      return f == null || e.value[f.$1] == f.$2;
    });
    return _QSnap([for (final e in docs) _QDoc(db, e.key)]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) {
      return _Col(db, path, (
        invocation.positionalArguments.first as String,
        invocation.namedArguments[#isEqualTo],
      ));
    }
    return super.noSuchMethod(invocation);
  }
}

// ignore: subtype_of_sealed_class
class _Ref implements DocumentReference<Map<String, dynamic>> {
  _Ref(this.db, this.path);
  final _Db db;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Map<String, dynamic>> collection(String name) =>
      _Col(db, '$path/$name');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    db.ensureOnline();
    return _Snap(db, path);
  }

  @override
  bool operator ==(Object other) => other is _Ref && other.path == path;
  @override
  int get hashCode => path.hashCode;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Point-in-time document read; data() is null when the document is missing.
// ignore: subtype_of_sealed_class
class _Snap implements DocumentSnapshot<Map<String, dynamic>> {
  _Snap(_Db db, this.path)
    : _ref = _Ref(db, path),
      _data = db.data(path) == null ? null : _copy(db.data(path)!);
  final String path;
  final _Ref _ref;
  final Map<String, dynamic>? _data;
  @override
  String get id => path.split('/').last;
  @override
  DocumentReference<Map<String, dynamic>> get reference => _ref;
  @override
  bool get exists => _data != null;
  @override
  Map<String, dynamic>? data() => _data == null ? null : _copy(_data);
  @override
  SnapshotMetadata get metadata => const _Meta();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Query results always exist.
// ignore: subtype_of_sealed_class
class _QDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _QDoc(_Db db, this.path)
    : _ref = _Ref(db, path),
      _data = _copy(db.data(path)!);
  final String path;
  final _Ref _ref;
  final Map<String, dynamic> _data;
  @override
  String get id => path.split('/').last;
  @override
  DocumentReference<Map<String, dynamic>> get reference => _ref;
  @override
  bool get exists => true;
  @override
  Map<String, dynamic> data() => _copy(_data);
  @override
  SnapshotMetadata get metadata => const _Meta();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QSnap implements QuerySnapshot<Map<String, dynamic>> {
  _QSnap(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Meta implements SnapshotMetadata {
  const _Meta();
  @override
  bool get isFromCache => false;
  @override
  bool get hasPendingWrites => false;
}
