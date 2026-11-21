import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/constants/app_constants.dart';
import 'package:tacopos/core/orders/order_cancellation.dart';
import 'package:tacopos/models/branch.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/services/app_session.dart';
import 'package:tacopos/services/live_presence_service.dart';
import 'package:tacopos/services/taco_pos_repository.dart';

// Runs the production prepare/cancel flows of cancelOrder and cancelEmptyOrder
// against an in-memory Firestore that reproduces the client SDK transaction
// contract: versioned reads, handler re-run when the read set changed, atomic
// commits, merge sets and equality queries.
//
// The operator confirms an immutable scope read from the server
// (prepare*). Changes made between that confirmation and the cancellation
// are injected directly; changes after discovery use beforeTransaction and
// changes inside the transaction window use beforeCommit.

const _root = 'restaurants/${AppConstants.restaurantId}';
const _order = '$_root/orders/o1';
const _branch = AppConstants.defaultBranchId;

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
    AppSession.instance.signIn(Employee.fromDoc(_ManagerDoc()));
  });
  tearDownAll(() async {
    await LivePresenceService.instance.stop();
    AppSession.instance.signOut();
  });

  group('componentes puros', () {
    test('plan de mesas: solo libera mesas que siguen siendo de la orden', () {
      final plan = planTableRelease(
        orderId: 'o1',
        candidateTableIds: ['t1', 't2', 't3', 't4', 't1'],
        currentOrderIdByTable: {'t1': 'o1', 't2': 'o2', 't3': null},
      );
      expect(plan.release, ['t1']);
      expect(plan.skipped, ['t2', 't4']);
    });

    test('identidad confirmada: cualquier diferencia exige reconfirmar', () {
      final scope = OrderCancellationScope(
        kind: OrderCancellationKind.cancelOrder,
        orderId: 'o1',
        captureRevision: 3,
        orderData: {
          'total': 120,
          'tableIds': ['t1'],
        },
        itemsById: {
          'i1': {'qty': 1, 'total': 120},
        },
        paymentsById: const {},
        itemsToCancelCount: 1,
        itemsToCancelTotal: 120,
      );
      String? diff({
        int revision = 3,
        Map<String, dynamic>? order,
        Map<String, Map<String, dynamic>>? items,
        Map<String, Map<String, dynamic>>? payments,
      }) => describeScopeChange(
        scope: scope,
        currentRevision: revision,
        currentOrderData:
            order ??
            {
              'total': 120,
              'tableIds': ['t1'],
            },
        currentItemsById:
            items ??
            {
              'i1': {'qty': 1, 'total': 120},
            },
        currentPaymentsById: payments ?? const {},
      );
      expect(diff(), isNull);
      expect(diff(revision: 4), 'order-revision');
      expect(
        diff(
          order: {
            'total': 120,
            'tableIds': ['t2'],
          },
        ),
        'order-fields',
      );
      expect(
        diff(
          items: {
            'i1': {'qty': 1, 'total': 120},
            'i2': {'qty': 1},
          },
        ),
        'item-added:i2',
      );
      expect(
        diff(
          items: {
            'i1': {'qty': 2, 'total': 240},
          },
        ),
        'item-changed:i1',
      );
      expect(diff(items: const {}), 'item-removed:i1');
      expect(
        diff(
          payments: {
            'p1': {'status': 'active'},
          },
        ),
        'payment-added:p1',
      );
      expect(
        () => (scope.itemsById['i1'] as Map)['qty'] = 9,
        throwsUnsupportedError,
        reason: 'la identidad confirmada es inmutable',
      );
    });

    test('solo la contencion tecnica es reintentable', () {
      FirebaseException fe(String c) =>
          FirebaseException(plugin: 'cloud_firestore', code: c);
      expect(isRetryableOrderMutationError(fe('aborted')), isTrue);
      expect(
        isRetryableOrderMutationError(
          OrderCancellationScopeChanged('item-added:x', 'm'),
        ),
        isFalse,
      );
      expect(isRetryableOrderMutationError(fe('permission-denied')), isFalse);
      expect(isOrderMutationConnectivityError(fe('unavailable')), isTrue);
      expect(orderCancelledActivityId('o1'), 'order_cancelled_o1');
    });

    test('presupuesto conservador: cada escritura cuenta doble', () {
      expect(conservativeTransactionWriteCost(250), 500);
      ensureCancellationWithinWriteBudget(documentWrites: 250, itemCount: 247);
      expect(
        () => ensureCancellationWithinWriteBudget(
          documentWrites: 251,
          itemCount: 248,
        ),
        throwsA(
          isA<OrderCancellationTooLarge>()
              .having((e) => e.conservativeCost, 'cost', 502)
              .having(
                (e) => e.message,
                'message',
                contains('No se hizo ningun cambio'),
              ),
        ),
      );
    });
  });

  group('cancelOrder: intencion confirmada', () {
    test(
      'control: cancela exactamente lo confirmado con una actividad',
      () async {
        final db = _seed(items: {'i1': 120, 'i2': 30}, batch: 'k1');
        final scope = await _confirm(db);
        expect(scope.itemsToCancelCount, 2);
        expect(scope.itemsToCancelTotal, 150);
        final result = await _cancelWith(db, scope);
        expect(result.outcome, OrderCancellationOutcome.cancelled);
        expect(result.releasedTableIds, ['t1']);
        _expectCancelledClean(db);
        expect(db.data('$_order/kitchenBatches/k1')!['status'], 'cancelled');
        expect(db.data(_order)!['captureRevision'], 4);
        expect(_logs(db, 'order_cancelled'), hasLength(1));
        expect(_logs(db, 'order_item_cancelled'), isEmpty);
        final event = db.data('$_root/activityLog/order_cancelled_o1')!;
        expect(event['cancelledItemCount'], 2);
        expect(
          (event['cancelledItems'] as List).map(
            (item) => (item as Map)['itemId'],
          ),
          unorderedEquals(['i1', 'i2']),
        );
        // Each item keeps its own cancellation trace.
        for (final id in ['i1', 'i2']) {
          final item = db.data('$_order/items/$id')!;
          expect(item['cancelReason'], 'Cliente se fue');
          expect(item['cancelledAt'], isA<Timestamp>());
          expect(item['cancelledByEmployeeId'], 'gerente');
        }
      },
    );

    test(
      '1-6. cuarto articulo antes del descubrimiento: aborta sin cancelar nada',
      () async {
        final db = _seed(items: {'i1': 50, 'i2': 40, 'i3': 30});
        final scope = await _confirm(db);
        _addItem28(db, 'i4', 45); // otro mesero, antes del descubrimiento
        final before = db.snapshot();
        await expectLater(_cancelWith(db, scope), throwsA(_scopeChanged()));
        expect(
          db.transactionCalls,
          0,
          reason: 'rechazado antes de transaccion',
        );
        expect(db.snapshot(), before);
        expect(db.data('$_order/items/i4')!['status'], 'active');
        for (final id in ['i1', 'i2', 'i3']) {
          expect(db.data('$_order/items/$id')!['kitchenStatus'], 'pending');
        }
        expect(db.data(_order)!['status'], 'open');
      },
    );

    test(
      '1b. articulo legacy (sin tocar la orden) antes del descubrimiento tambien aborta',
      () async {
        final db = _seed();
        final scope = await _confirm(db);
        db.write('$_order/items/i27', _item(60));
        await expectLater(_cancelWith(db, scope), throwsA(_scopeChanged()));
        expect(db.data(_order)!['status'], 'open');
        expect(db.data('$_order/items/i27')!['status'], 'active');
      },
    );

    test(
      '7-10. articulo despues del descubrimiento: no se reintenta ni se amplia',
      () async {
        final db = _seed(items: {'i1': 50, 'i2': 40, 'i3': 30});
        final scope = await _confirm(db);
        db.beforeTransaction = (call) async {
          if (call == 1) _addItem28(db, 'i4', 45);
        };
        await expectLater(_cancelWith(db, scope), throwsA(_scopeChanged()));
        expect(
          db.transactionCalls,
          1,
          reason: 'sin redescubrimiento automatico',
        );
        expect(db.data('$_order/items/i4')!['status'], 'active');
        expect(db.data('$_order/items/i4')!['kitchenStatus'], 'pending');
        expect(db.data(_order)!['status'], 'open');
        expect(db.docsUnder('$_root/activityLog'), isEmpty);
      },
    );

    test(
      '7-10b. articulo modificado dentro de la ventana: el SDK reintenta y se rechaza',
      () async {
        final db = _seed(items: {'i1': 50, 'i2': 40});
        final scope = await _confirm(db);
        var once = true;
        db.beforeCommit = () async {
          if (!once) return;
          once = false;
          db.write('$_order/items/i2', {'qty': 2, 'total': 80});
        };
        await expectLater(_cancelWith(db, scope), throwsA(_scopeChanged()));
        expect(db.data('$_order/items/i2')!['kitchenStatus'], 'pending');
        expect(db.data(_order)!['status'], 'open');
      },
    );

    test('11. modificacion de cantidad', () async {
      final db = _seed();
      final scope = await _confirm(db);
      db.write('$_order/items/i1', {'qty': 3, 'total': 360});
      db.write(_order, {'total': 360, 'captureRevision': 4});
      await expectLater(_cancelWith(db, scope), throwsA(_scopeChanged()));
      expect(db.data('$_order/items/i1')!['kitchenStatus'], 'pending');
    });

    test(
      '12. pago nuevo (E1): nunca queda cancelada con pago activo',
      () async {
        final db = _seed();
        final scope = await _confirm(db);
        _payment28(db, 'p2', 50);
        await expectLater(_cancelWith(db, scope), throwsA(_scopeChanged()));
        expect(db.data(_order)!['status'], 'open');
        expect(db.data('$_order/payments/p2')!['status'], 'active');
        expect(db.data('$_root/tables/t1')!['currentOrderId'], 'o1');
      },
    );

    test('12b. pago nuevo despues del descubrimiento', () async {
      final db = _seed();
      final scope = await _confirm(db);
      db.beforeTransaction = (call) async {
        if (call == 1) _payment28(db, 'p2', 50);
      };
      await expectLater(_cancelWith(db, scope), throwsA(_scopeChanged()));
      expect(db.data(_order)!['status'], 'open');
    });

    test(
      '13. producto marcado listo (E3b) antes y dentro de la transaccion',
      () async {
        final db = _seed(itemKitchen: 'cooking');
        final scope = await _confirm(db);
        db.write('$_order/items/i1', {'kitchenStatus': 'ready'});
        db.write(_order, {'kitchenStatus': 'ready', 'status': 'ready'});
        await expectLater(_cancelWith(db, scope), throwsA(_scopeChanged()));
        expect(db.data('$_order/items/i1')!['kitchenStatus'], 'ready');

        final db2 = _seed(itemKitchen: 'cooking');
        final scope2 = await _confirm(db2);
        var once = true;
        db2.beforeCommit = () async {
          if (!once) return;
          once = false;
          db2.write('$_order/items/i1', {'kitchenStatus': 'ready'});
        };
        await expectLater(_cancelWith(db2, scope2), throwsA(_scopeChanged()));
        expect(db2.data('$_order/items/i1')!['kitchenStatus'], 'ready');
        expect(db2.data(_order)!['status'], 'open');
      },
    );

    test(
      '14. cambio de estado de cocina (envio, E3a) exige reconfirmar',
      () async {
        final db = _seed();
        final scope = await _confirm(db);
        db.write('$_order/items/i1', {
          'kitchenStatus': 'sent',
          'kitchenBatchId': 'k1',
        });
        db.write(_order, {
          'kitchenStatus': 'sent',
          'status': 'sent',
          'captureRevision': 4,
        });
        await expectLater(_cancelWith(db, scope), throwsA(_scopeChanged()));
        final reconfirmed = await _confirm(db);
        await _cancelWith(db, reconfirmed);
        _expectCancelledClean(db);
      },
    );

    test(
      '15. cambio de mesa (E7): aborta y la reconfirmacion libera la mesa vigente',
      () async {
        final db = _seed();
        db.write('$_root/tables/t2', {
          'status': 'available',
          'branchId': _branch,
        });
        final scope = await _confirm(db);
        db.write(_order, {
          'tableId': 't2',
          'tableIds': ['t2'],
          'captureRevision': 4,
        });
        db.write('$_root/tables/t1', {
          'status': 'available',
          'currentOrderId': null,
        });
        db.write('$_root/tables/t2', {
          'status': 'occupied',
          'currentOrderId': 'o1',
        });
        await expectLater(_cancelWith(db, scope), throwsA(_scopeChanged()));
        final result = await _cancelWith(db, await _confirm(db));
        expect(result.releasedTableIds, ['t2']);
        _expectCancelledClean(db);
      },
    );

    test(
      '16. respuesta perdida tras confirmar: reintento con la misma identidad',
      () async {
        final db = _seed();
        final scope = await _confirm(db);
        db.loseResponseOnNextCommit = true;
        await expectLater(
          _cancelWith(db, scope),
          throwsA(_stateError('Sin conexion')),
        );
        expect(db.data(_order)!['status'], 'cancelled');
        final retry = await _cancelWith(db, scope);
        expect(retry.outcome, OrderCancellationOutcome.alreadyCancelled);
        expect(_logs(db, 'order_cancelled'), hasLength(1));
      },
    );

    test('17. dos dispositivos cancelan la misma orden (E4)', () async {
      final db = _seed();
      final scopeA = await _confirm(db);
      final scopeB = await _confirm(db);
      final a = await _cancelWith(db, scopeA);
      final b = await _cancelWith(db, scopeB);
      expect(a.outcome, OrderCancellationOutcome.cancelled);
      expect(b.outcome, OrderCancellationOutcome.alreadyCancelled);
      expect(_logs(db, 'order_cancelled'), hasLength(1));
      expect(
        db.data('$_root/activityLog/order_cancelled_o1')!['cancelledItems'],
        hasLength(1),
      );
    });

    test('18. confirmacion repetida sobre orden ya cancelada', () async {
      final db = _seed();
      final scope = await _confirm(db);
      await _cancelWith(db, scope);
      final before = db.snapshot();
      final again = await _cancelWith(db, scope);
      expect(again.outcome, OrderCancellationOutcome.alreadyCancelled);
      expect(db.snapshot(), before);
      await expectLater(
        _confirm(db),
        throwsA(_stateError('ya habia sido cancelada')),
      );
    });
  });

  group('cancelOrder: protecciones conservadas', () {
    test('mesa de otra orden (E8): no se toca y se registra', () async {
      final db = _seed();
      db.write('$_root/tables/t1', {
        'status': 'occupied',
        'currentOrderId': 'o2',
      });
      final tableBefore = Map.of(db.data('$_root/tables/t1')!);
      final result = await _cancel(db);
      expect(result.skippedTableIds, ['t1']);
      expect(db.data('$_root/tables/t1'), tableBefore);
      expect(
        db.data('$_root/activityLog/order_cancelled_o1')!['skippedTableIds'],
        ['t1'],
      );
    });

    test('mesa fantasma que apunta a la orden tambien se libera', () async {
      final db = _seed();
      db.write('$_root/tables/t9', {
        'status': 'occupied',
        'currentOrderId': 'o1',
        'branchId': _branch,
      });
      final result = await _cancel(db);
      expect(result.releasedTableIds, unorderedEquals(['t1', 't9']));
      _expectCancelledClean(db);
    });

    test('22. orden historica sin captureRevision', () async {
      final db = _seed(revision: null);
      db.write(_order, {'tableIds': null});
      await _cancel(db);
      _expectCancelledClean(db);
      expect(db.data(_order)!['captureRevision'], 1);

      final db2 = _seed(revision: null);
      final scope = await _confirm(db2);
      _payment28(db2, 'p27', 50, bumpRevision: false);
      await expectLater(_cancelWith(db2, scope), throwsA(_scopeChanged()));
    });

    test(
      '23. LIMITACION: articulo legacy solo en subcoleccion despues del descubrimiento',
      () async {
        final db = _seed();
        final scope = await _confirm(db);
        db.beforeTransaction = (call) async {
          if (call == 1) db.write('$_order/items/i27', _item(60));
        };
        await _cancelWith(db, scope);
        expect(
          db.data('$_order/items/i27')!['kitchenStatus'],
          'pending',
          reason: 'carrera B: requiere R3 y retiro de escritores sin revision',
        );
      },
    );

    test(
      '24. sin conexion al revisar y al confirmar: sin escrituras',
      () async {
        final offline = _seed()..offline = true;
        await expectLater(
          _confirm(offline),
          throwsA(_stateError('Sin conexion')),
        );
        final db = _seed();
        final scope = await _confirm(db);
        db.offline = true;
        final before = db.snapshot();
        await expectLater(
          _cancelWith(db, scope),
          throwsA(_stateError('Sin conexion')),
        );
        expect(db.snapshot(), before);
      },
    );

    test(
      '25. contencion tecnica: reintentos limitados sin escrituras',
      () async {
        final db = _seed()..denyCommitCode = 'aborted';
        final scope = await _confirm(db);
        final before = db.snapshot();
        await expectLater(
          _cancelWith(db, scope),
          throwsA(_stateError('concurrencia')),
        );
        expect(db.transactionCalls, orderMutationMaxAttempts);
        expect(db.snapshot(), before);
      },
    );

    test(
      '25b. contencion tecnica con estado igual: el reintento si confirma',
      () async {
        final db = _seed()..denyCommitOnce = 'aborted';
        final scope = await _confirm(db);
        final result = await _cancelWith(db, scope);
        expect(result.outcome, OrderCancellationOutcome.cancelled);
        expect(db.transactionCalls, 2);
        _expectCancelledClean(db);
      },
    );

    test('error de permisos no se reintenta ni escribe', () async {
      final db = _seed();
      final scope = await _confirm(db);
      db.denyCommitCode = 'permission-denied';
      final before = db.snapshot();
      await expectLater(
        _cancelWith(db, scope),
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

    test(
      'orden pagada y pago parcial activo: la revision falla sin escribir',
      () async {
        final paid = _seed();
        paid.write(_order, {
          'status': 'paid',
          'paymentStatus': 'paid',
          'paidTotal': 120,
          'pendingTotal': 0,
        });
        await expectLater(
          _confirm(paid),
          throwsA(_stateError('pagada al 100%')),
        );
        final partial = _seed();
        _payment28(partial, 'p1', 40);
        await expectLater(
          _confirm(partial),
          throwsA(_stateError('los pagos cierran la orden')),
        );
      },
    );

    test('articulos cancelados previamente no se vuelven a cancelar', () async {
      final db = _seed(items: {'i1': 120, 'i0': 50});
      db.write('$_order/items/i0', {
        'status': 'cancelled',
        'kitchenStatus': 'cancelled',
        'paymentStatus': 'cancelled',
        'cancelReason': 'Original',
        'cancelStatus': 'accepted',
      });
      final previous = Map.of(db.data('$_order/items/i0')!);
      final scope = await _confirm(db);
      expect(scope.itemsToCancelCount, 1);
      await _cancelWith(db, scope);
      expect(db.data('$_order/items/i0'), previous);
      expect(
        (db.data('$_root/activityLog/order_cancelled_o1')!['cancelledItems']
                as List)
            .map((item) => (item as Map)['itemId']),
        ['i1'],
      );
    });

    test('lotes y secuencias de cocina', () async {
      final db = _seed(items: {'i1': 120, 'i0': 50}, batch: 'k1');
      db.write('$_order/items/i0', {
        'kitchenStatus': 'cancelled',
        'paymentStatus': 'cancelled',
        'kitchenBatchId': 'k0',
      });
      db.write('$_order/kitchenBatches/k0', {
        'status': 'cancelled',
        'cancelReason': 'Original',
      });
      db.write('$_root/branches/$_branch/kitchenDailySequences/2026-11-21', {
        'lastSequence': 7,
      });
      final sequence = Map.of(
        db.data('$_root/branches/$_branch/kitchenDailySequences/2026-11-21')!,
      );
      final k0 = Map.of(db.data('$_order/kitchenBatches/k0')!);
      await _cancel(db);
      expect(db.data('$_order/kitchenBatches/k1')!['status'], 'cancelled');
      expect(db.data('$_order/kitchenBatches/k0'), k0);
      expect(
        db.data('$_root/branches/$_branch/kitchenDailySequences/2026-11-21'),
        sequence,
      );
    });

    test('cambio de sucursal entre la revision y la confirmacion', () async {
      final db = _seed();
      final scope = await _confirm(db);
      AppSession.instance.selectBranch(
        const Branch(
          id: 'test',
          name: 'Test',
          normalizedName: 'test',
          active: true,
          sortOrder: 2,
        ),
      );
      addTearDown(() => AppSession.instance.selectBranch(Branch.defaultBranch));
      final before = db.snapshot();
      await expectLater(
        _cancelWith(db, scope),
        throwsA(_stateError('otra sucursal')),
      );
      expect(db.snapshot(), before);
    });

    test('la identidad de cierre vacio no sirve para cancelar orden', () async {
      final db = _seed(items: const {});
      final scope = await _confirmEmpty(db);
      expect(
        () => TacoPosRepository(
          firestore: db,
          auth: _Auth(),
        ).cancelOrder(scope: scope, reason: 'x'),
        throwsArgumentError,
      );
    });
  });

  group('cancelOrder: volumen y presupuesto de escrituras', () {
    // Each row: items, kitchen batches, grouped tables. Every scenario also
    // carries historical cancelled payments, previously cancelled items and
    // historical activity documents. The fake server applies the strict
    // accounting (documents + field transforms <= 500).
    final metrics = <String>[];
    tearDownAll(() {
      // ignore: avoid_print
      print(
        'VOLUMEN items|lotes|mesas -> resultado | lecturas tx | escrituras | '
        'transformaciones | costo conservador | bytes aprox | ms\n'
        '${metrics.join('\n')}',
      );
    });

    for (final (items, batches, tables) in [
      (1, 1, 1),
      (10, 1, 1),
      (50, 2, 2),
      (100, 3, 2),
      (200, 4, 2),
      (300, 4, 2),
      (600, 6, 2),
    ]) {
      test('$items articulos, $batches lotes, $tables mesas', () async {
        final db = _largeOrder(items: items, batches: batches, tables: tables)
          ..strictServerWriteLimit = 500;
        final docWrites = 1 + items + batches + tables + 1;
        final fits = conservativeTransactionWriteCost(docWrites) <= 500;
        final watch = Stopwatch()..start();
        if (!fits) {
          final before = db.snapshot();
          await expectLater(
            _confirm(db),
            throwsA(isA<OrderCancellationTooLarge>()),
            reason: 'se rechaza al revisar, antes de pedir confirmacion',
          );
          watch.stop();
          expect(db.snapshot(), before);
          expect(db.transactionCalls, 0);
          metrics.add(
            '$items|$batches|$tables -> RECHAZADA antes de escribir | 0 | 0 | '
            '0 | ${conservativeTransactionWriteCost(docWrites)} | 0 | '
            '${watch.elapsedMilliseconds}',
          );
          return;
        }
        final scope = await _confirm(db);
        db.resetCounters();
        await _cancelWith(db, scope);
        watch.stop();
        expect(db.lastCommitWrites, docWrites);
        expect(db.lastCommitTransforms, docWrites);
        expect(
          db.lastCommitWrites + db.lastCommitTransforms,
          lessThanOrEqualTo(500),
        );
        // order + items + payments(2 historical) + tables + batches + event
        expect(db.transactionReads, 1 + items + 1 + 2 + tables + batches + 1);
        expect(db.lastCommitApproxBytes, lessThan(1024 * 1024));
        _expectCancelledClean(db);
        expect(
          db.data('$_root/activityLog/order_cancelled_o1')!['cancelledItems'],
          hasLength(items),
        );
        expect(
          db.data('$_root/activityLog/historico-1')!['type'],
          'order_item_cancelled',
        );
        metrics.add(
          '$items|$batches|$tables -> cancelada | ${db.transactionReads} | '
          '${db.lastCommitWrites} | ${db.lastCommitTransforms} | '
          '${db.lastCommitWrites + db.lastCommitTransforms} | '
          '${db.lastCommitApproxBytes} | ${watch.elapsedMilliseconds}',
        );
      });
    }

    test(
      'orden grande con cambio concurrente: el alcance sigue protegido',
      () async {
        final db = _largeOrder(items: 200, batches: 4, tables: 2);
        final scope = await _confirm(db);
        _addItem28(db, 'i-new', 10);
        final before = db.snapshot();
        await expectLater(_cancelWith(db, scope), throwsA(_scopeChanged()));
        expect(db.snapshot(), before);
      },
    );

    test(
      'excede en la transaccion (mesas fantasma): rechazo sin escrituras',
      () async {
        // The review estimate fits (246 items + 1 linked table), but two ghost
        // tables pointing to the order push the transaction over the budget.
        final db = _largeOrder(items: 246, batches: 0, tables: 1)
          ..strictServerWriteLimit = 500;
        final scope = await _confirm(db);
        for (final ghost in ['g1', 'g2']) {
          db.write('$_root/tables/$ghost', {
            'status': 'occupied',
            'currentOrderId': 'o1',
            'branchId': _branch,
          });
        }
        final before = db.snapshot();
        await expectLater(
          _cancelWith(db, scope),
          throwsA(isA<OrderCancellationTooLarge>()),
        );
        expect(db.snapshot(), before);
      },
    );
  });

  group('cancelEmptyOrder', () {
    test('control: cierra la orden vacia y libera la mesa', () async {
      final db = _seed(items: const {});
      final result = await _cancelEmptyWith(db, await _confirmEmpty(db));
      expect(result.outcome, OrderCancellationOutcome.cancelled);
      expect(db.data(_order)!['status'], 'cancelled');
      expect(db.data(_order)!['captureRevision'], 4);
      expect(db.data('$_root/tables/t1')!['currentOrderId'], isNull);
    });

    test(
      '19/21. articulo antes del descubrimiento (E5): sigue abierta y lo conserva',
      () async {
        final db = _seed(items: const {});
        final scope = await _confirmEmpty(db);
        _addItem28(db, 'i-late', 80);
        await expectLater(
          _cancelEmptyWith(db, scope),
          throwsA(_scopeChanged(empty: true)),
        );
        expect(db.data(_order)!['status'], 'open');
        expect(db.data('$_order/items/i-late')!['status'], 'active');
        expect(db.data('$_root/tables/t1')!['currentOrderId'], 'o1');
      },
    );

    test(
      '20/21. articulo durante la transaccion: sigue abierta y lo conserva',
      () async {
        final db = _seed(items: const {});
        final scope = await _confirmEmpty(db);
        db.beforeTransaction = (call) async {
          if (call == 1) _addItem28(db, 'i-late', 80);
        };
        await expectLater(
          _cancelEmptyWith(db, scope),
          throwsA(_scopeChanged(empty: true)),
        );
        expect(db.data(_order)!['status'], 'open');
        expect(db.data('$_order/items/i-late')!['status'], 'active');
      },
    );

    test(
      '23b. LIMITACION: articulo legacy sin tocar la orden durante la transaccion',
      () async {
        final db = _seed(items: const {});
        final scope = await _confirmEmpty(db);
        db.beforeTransaction = (call) async {
          if (call == 1) db.write('$_order/items/i27', _item(60));
        };
        await _cancelEmptyWith(db, scope);
        expect(
          db.data('$_order/items/i27')!['status'],
          'active',
          reason: 'carrera B: requiere R3 y retiro de escritores sin revision',
        );
      },
    );

    test(
      'repeticion idempotente y revision con pagos, cocina o articulos',
      () async {
        final db = _seed(items: const {});
        final scope = await _confirmEmpty(db);
        await _cancelEmptyWith(db, scope);
        final before = db.snapshot();
        expect(
          (await _cancelEmptyWith(db, scope)).outcome,
          OrderCancellationOutcome.alreadyCancelled,
        );
        expect(db.snapshot(), before);
        for (final setup in <void Function(_Db)>[
          (db) => _payment28(db, 'p1', 10),
          (db) => db.write(_order, {'sentToKitchenAt': Timestamp(10, 0)}),
          (db) => db.write('$_order/items/i1', _item(10)),
        ]) {
          final other = _seed(items: const {});
          setup(other);
          await expectLater(_confirmEmpty(other), throwsA(isA<StateError>()));
        }
      },
    );

    test('sin conexion: no escribe ni deja nada en cola', () async {
      final db = _seed(items: const {});
      final scope = await _confirmEmpty(db);
      db.offline = true;
      final before = db.snapshot();
      await expectLater(
        _cancelEmptyWith(db, scope),
        throwsA(_stateError('Sin conexion')),
      );
      expect(db.snapshot(), before);
    });
  });
}

Matcher _stateError(String fragment) =>
    isA<StateError>().having((e) => e.message, 'message', contains(fragment));

Matcher _scopeChanged({bool empty = false}) =>
    isA<OrderCancellationScopeChanged>().having(
      (e) => e.message,
      'message',
      empty
          ? emptyOrderCloseScopeChangedMessage
          : orderCancellationScopeChangedMessage,
    );

TacoPosRepository _repo(_Db db) =>
    TacoPosRepository(firestore: db, auth: _Auth());

Future<OrderCancellationScope> _confirm(_Db db) =>
    _repo(db).prepareOrderCancellation('o1');

Future<OrderCancellationScope> _confirmEmpty(_Db db) =>
    _repo(db).prepareEmptyOrderClose('o1');

Future<OrderCancellationResult> _cancelWith(
  _Db db,
  OrderCancellationScope scope,
) => _repo(db).cancelOrder(scope: scope, reason: 'Cliente se fue');

Future<OrderCancellationResult> _cancelEmptyWith(
  _Db db,
  OrderCancellationScope scope,
) => _repo(db).cancelEmptyOrder(scope);

Future<OrderCancellationResult> _cancel(_Db db) async =>
    _cancelWith(db, await _confirm(db));

Map<String, dynamic> _item(num total, {String kitchen = 'pending'}) => {
  'qty': 1,
  'unitPrice': total,
  'total': total,
  'status': 'active',
  'paymentStatus': 'pending',
  'kitchenStatus': kitchen,
};

_Db _seed({
  Map<String, num> items = const {'i1': 120},
  int? revision = 3,
  String itemKitchen = 'pending',
  String? batch,
  int batches = 0,
}) {
  final db = _Db();
  final total = items.values.fold<num>(0, (a, b) => a + b);
  db.write(_order, {
    'restaurantId': AppConstants.restaurantId,
    'branchId': _branch,
    'status': 'open',
    'kitchenStatus': 'pending',
    'paymentStatus': 'pending',
    'orderType': 'dine_in',
    'tableId': 't1',
    'tableIds': ['t1'],
    'total': total,
    'paidTotal': 0,
    'pendingTotal': total,
    'updatedAt': Timestamp(100, 0),
    'captureRevision': ?revision,
  });
  var index = 0;
  items.forEach((id, value) {
    final batchId = batch ?? (batches > 0 ? 'k${index % batches}' : null);
    db.write('$_order/items/$id', {
      ..._item(value, kitchen: itemKitchen),
      'kitchenBatchId': ?batchId,
    });
    index++;
  });
  for (final id in {?batch, for (var i = 0; i < batches; i++) 'k$i'}) {
    db.write('$_order/kitchenBatches/$id', {'status': 'sent', 'itemCount': 1});
  }
  db.write('$_root/tables/t1', {
    'status': 'occupied',
    'currentOrderId': 'o1',
    'branchId': _branch,
    'name': 'Mesa 1',
  });
  return db;
}

void _payment28(_Db db, String id, num amount, {bool bumpRevision = true}) {
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
    'paymentStatus': 'partial',
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

/// Order with [items] active items spread over [batches] kitchen batches and
/// grouped over [tables] tables, plus history that must stay untouched: two
/// cancelled payments, one previously cancelled item and an old activity.
_Db _largeOrder({
  required int items,
  required int batches,
  required int tables,
}) {
  final db = _seed(items: const {});
  final tableIds = [for (var i = 1; i <= tables; i++) 't$i'];
  db.write(_order, {
    'tableIds': tableIds,
    'tableId': tableIds.first,
    'total': items * 10,
    'pendingTotal': items * 10,
  });
  for (var i = 0; i < items; i++) {
    db.write('$_order/items/i$i', {
      ..._item(10, kitchen: 'sent'),
      if (batches > 0) 'kitchenBatchId': 'k${i % batches}',
    });
  }
  for (var i = 0; i < batches; i++) {
    db.write('$_order/kitchenBatches/k$i', {'status': 'sent', 'itemCount': 1});
  }
  for (final id in tableIds) {
    db.write('$_root/tables/$id', {
      'status': 'occupied',
      'currentOrderId': 'o1',
      'branchId': _branch,
    });
  }
  db.write('$_order/items/i-old', {
    ..._item(10),
    'status': 'cancelled',
    'kitchenStatus': 'cancelled',
    'paymentStatus': 'cancelled',
  });
  for (final id in ['pc1', 'pc2']) {
    db.write('$_order/payments/$id', {
      'orderId': 'o1',
      'status': 'cancelled',
      'baseAmount': 10,
      'cashSessionId': 'cs1',
    });
  }
  db.write('$_root/activityLog/historico-1', {
    'type': 'order_item_cancelled',
    'orderId': 'o1',
    'itemId': 'i-old',
  });
  return db;
}

List<Map<String, dynamic>> _logs(_Db db, String type) => db
    .docsUnder('$_root/activityLog')
    .values
    .where((log) => log['type'] == type)
    .toList();

/// Cancelled order with no active payment, no active item and no table still
/// pointing to it.
void _expectCancelledClean(_Db db) {
  final order = db.data(_order)!;
  expect(order['status'], 'cancelled');
  expect(order['paymentStatus'], 'cancelled');
  expect(order['total'], 0);
  expect(
    db
        .docsUnder('$_order/payments')
        .values
        .where((p) => p['status'] == 'active'),
    isEmpty,
  );
  for (final item in db.docsUnder('$_order/items').values) {
    expect(item['kitchenStatus'], 'cancelled', reason: '$item');
  }
  for (final table in db.docsUnder('$_root/tables').values) {
    expect(table['currentOrderId'], isNot('o1'), reason: '$table');
  }
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
class _ManagerDoc implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  String get id => 'gerente';
  @override
  Map<String, dynamic> data() => {
    'name': 'Gerente',
    'canCancelOrders': true,
    'canTakeOrders': true,
  };
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
  bool offline = false;
  bool loseResponseOnNextCommit = false;
  String? denyCommitCode;
  String? denyCommitOnce;
  int transactionReads = 0;
  int lastCommitWrites = 0;
  int lastCommitTransforms = 0;
  int lastCommitApproxBytes = 0;

  /// Simulates a server enforcing documents + field transforms <= limit.
  int? strictServerWriteLimit;

  void resetCounters() {
    transactionReads = 0;
    lastCommitWrites = 0;
    lastCommitTransforms = 0;
    lastCommitApproxBytes = 0;
  }

  Future<void> Function(int call)? beforeTransaction;
  Future<void> Function()? beforeCommit;

  Map<String, dynamic>? data(String path) => _docs[path];

  Map<String, Map<String, dynamic>> docsUnder(String collectionPath) => {
    for (final entry in _docs.entries)
      if (entry.key.substring(0, entry.key.lastIndexOf('/')) == collectionPath)
        entry.key: entry.value,
  };

  /// Direct write by a concurrent client (merge semantics, nulls kept).
  void write(String path, Map<String, dynamic> data) {
    _docs[path] = {...?_docs[path], ...data};
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
      if (kind == 'update' && !_docs.containsKey(entry.key)) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
      }
      final current = kind == 'set'
          ? <String, dynamic>{}
          : <String, dynamic>{...?_docs[entry.key]};
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
      final tx = _Tx(this);
      final result = await transactionHandler(tx);
      await beforeCommit?.call();
      final stale = tx.readVersions.entries.any(
        (e) => (_versions[e.key] ?? 0) != e.value,
      );
      if (stale) continue;
      final once = denyCommitOnce;
      if (once != null) {
        denyCommitOnce = null;
        throw FirebaseException(plugin: 'cloud_firestore', code: once);
      }
      final transforms = tx.writes.values
          .where(
            (write) => write.$2.values.any(
              (value) => value is FieldValue && value != FieldValue.delete(),
            ),
          )
          .length;
      final strict = strictServerWriteLimit;
      if (strict != null && tx.writes.length + transforms > strict) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'invalid-argument',
          message: 'too many writes in one transaction',
        );
      }
      final denied = denyCommitCode;
      if (denied != null) {
        throw FirebaseException(plugin: 'cloud_firestore', code: denied);
      }
      apply(tx.writes);
      lastCommitWrites = tx.writes.length;
      lastCommitTransforms = transforms;
      lastCommitApproxBytes = tx.writes.entries.fold<int>(
        0,
        (bytes, write) =>
            bytes + write.key.length + write.value.$2.toString().length,
      );
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
    db.transactionReads++;
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
    writes[documentRef.path] = (
      options?.merge == true ? 'merge' : 'set',
      Map<Object, Object?>.from(data as Map),
    );
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

// ignore: subtype_of_sealed_class
class _Snap implements DocumentSnapshot<Map<String, dynamic>> {
  _Snap(_Db db, this.path)
    : _ref = _Ref(db, path),
      _value = db.data(path) == null ? null : _copy(db.data(path)!);
  final String path;
  final _Ref _ref;
  final Map<String, dynamic>? _value;
  @override
  String get id => path.split('/').last;
  @override
  DocumentReference<Map<String, dynamic>> get reference => _ref;
  @override
  bool get exists => _value != null;
  @override
  Map<String, dynamic>? data() => _value == null ? null : _copy(_value);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _QDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _QDoc(_Db db, this.path)
    : _ref = _Ref(db, path),
      _value = _copy(db.data(path)!);
  final String path;
  final _Ref _ref;
  final Map<String, dynamic> _value;
  @override
  String get id => path.split('/').last;
  @override
  DocumentReference<Map<String, dynamic>> get reference => _ref;
  @override
  bool get exists => true;
  @override
  Map<String, dynamic> data() => _copy(_value);
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
