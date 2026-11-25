import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/constants/app_constants.dart';
import 'package:tacopos/models/branch.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/models/kitchen_session.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/screens/kitchen/kitchen_bundles_feed.dart';
import 'package:tacopos/screens/admin/live_operations_screen.dart';
import 'package:tacopos/screens/kitchen/kitchen_screen.dart';
import 'package:tacopos/screens/kitchen/kitchen_order_detail_screen.dart';
import 'package:tacopos/services/app_session.dart';
import 'package:tacopos/services/live_presence_service.dart';
import 'package:tacopos/services/taco_pos_repository.dart';

const _ordersPath = 'restaurants/${AppConstants.restaurantId}/orders';
String _itemsPath(String id) => '$_ordersPath/$id/items';

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
  });
  final originalPrint = debugPrint;
  final logs = <String>[];
  setUp(() {
    logs.clear();
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });
  tearDown(() async {
    debugPrint = originalPrint;
    await LivePresenceService.instance.stop();
    AppSession.instance.signOut();
    AppSession.instance.selectBranch(Branch.defaultBranch);
  });

  test(
    'typed startup cache is displayable, partial is explicit, server confirmation completes it',
    () async {
      final h = _SyncHarness();
      h.db.orders.emit({'a': _order(), 'b': _order()}, cache: true);
      await _flush();
      expect(h.states.last.status, KitchenSyncStatus.partial);
      expect(h.states.last.hasData, isFalse);
      h.db.items('a').emit({'i': _item()}, cache: true);
      h.db.items('b').emit({}, cache: true);
      await _flush();
      expect(h.states.last.bundles.single.order.id, 'a');
      expect(h.states.last.loadingItemOrderIds, {'b'});
      expect(h.states.last.hasData, isTrue);
      expect(h.states.last.isConfirmed, isFalse);
      h.db.orders.emit({'a': _order(), 'b': _order()});
      h.db.items('a').emit({'i': _item()}, changed: []);
      h.db.items('b').emit({}, changed: []);
      await _flush();
      expect(h.states.last.isConfirmed, isTrue);
      expect(h.states.last.bundles.single.order.id, 'a');
      expect(h.db.attaches, 3);
      await h.close();
    },
  );

  test(
    'offline without cache does not claim a confirmed empty kitchen',
    () async {
      final h = _SyncHarness();
      h.db.orders.emit({}, cache: true);
      await _flush();
      expect(h.states.last.status, KitchenSyncStatus.cache);
      expect(h.states.last.hasData, isFalse);
      h.db.orders.emit({}, changed: []);
      await _flush();
      expect(h.states.last.isConfirmed, isTrue);
      expect(h.states.last.hasData, isTrue);
      expect(h.states.last.bundles, isEmpty);
      await h.close();
    },
  );

  test(
    'cache subset cannot delete a coherent board, pending changes remain provisional',
    () async {
      final h = _SyncHarness();
      h.db.orders.emit({'a': _order()});
      h.db.items('a').emit({
        'i': _item(),
        'extra': _item(batch: 'extra', express: true),
      });
      await _flush();
      h.db.orders.emit({}, cache: true);
      h.db.items('a').emit({}, cache: true);
      await _flush();
      expect(h.states.last.bundles, hasLength(2));
      expect(h.states.last.hasCache, isTrue);
      h.db.items('a').emit({'i': _item(qty: 3)}, pending: true);
      await _flush();
      expect(h.states.last.hasPendingWrites, isTrue);
      expect(h.states.last.bundles.first.items.first.qty, 3);
      expect(h.states.last.bundles, hasLength(2));
      h.db.orders.emit({'a': _order(status: 'closed')});
      await _flush();
      expect(h.states.last.isConfirmed, isTrue);
      expect(h.states.last.bundles, isEmpty);
      h.db.orders.emit({'a': _order()}, cache: true);
      h.db.items('a').emit({'i': _item()}, cache: true);
      await _flush();
      expect(h.states.last.bundles, isEmpty);
      expect(h.db.items('a').active, 0);
      await h.close();
    },
  );

  testWidgets(
    'terminal transient errors retry at 2/5/15 seconds, bounded per listener lifetime',
    (tester) async {
      debugPrint = tester.binding.debugPrintOverride;
      final h = _SyncHarness();
      h.db.orders.emit({'a': _order()});
      h.db.items('a').emit({'i': _item()});
      await tester.pump();
      for (final seconds in [2, 5, 15]) {
        final before = h.db.attaches;
        h.db
            .items('a')
            .error(
              FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
            );
        await tester.pump();
        expect(h.states.last.status, KitchenSyncStatus.reconnecting);
        expect(h.states.last.bundles, hasLength(1));
        expect(h.db.active, 1);
        await tester.pump(Duration(seconds: seconds - 1));
        expect(h.db.attaches, before);
        await tester.pump(const Duration(seconds: 1));
        expect(
          h.db.attaches,
          before + 1,
          reason: h.states.last.issues
              .map(
                (issue) =>
                    '${issue.error} attempt=${issue.retryAttempt} scheduled=${issue.retryScheduled}',
              )
              .join(';'),
        );
        expect(h.db.active, 2);
        h.db.items('a').emit({'i': _item()});
        await tester.pump();
      }
      h.db
          .items('a')
          .error(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          );
      await tester.pump();
      expect(h.states.last.status, KitchenSyncStatus.transientError);
      await tester.pump(const Duration(minutes: 2));
      expect(h.db.attaches, 5);
      await h.close();
      expect(h.db.active, 0);
    },
  );

  for (final code in [
    'permission-denied',
    'unauthenticated',
    'failed-precondition',
  ]) {
    testWidgets(
      'permanent $code is visible, preserves data and never retries',
      (tester) async {
        debugPrint = tester.binding.debugPrintOverride;
        final h = _SyncHarness();
        h.db.orders.emit({'a': _order()});
        h.db.items('a').emit({'i': _item()});
        h.db
            .items('a')
            .error(FirebaseException(plugin: 'cloud_firestore', code: code));
        await tester.pump();
        expect(h.states.last.status, KitchenSyncStatus.permanentError);
        expect(h.states.last.bundles, hasLength(1));
        await tester.pump(const Duration(minutes: 2));
        expect(h.db.attaches, 2);
        await h.close();
        expect(h.db.active, 0);
      },
    );
  }

  testWidgets(
    'closing while retrying cancels timer; closing order prevents stale retry resurrection',
    (tester) async {
      debugPrint = tester.binding.debugPrintOverride;
      final h = _SyncHarness();
      h.db.orders.emit({'a': _order()});
      h.db.items('a').emit({'i': _item()});
      h.db
          .items('a')
          .error(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          );
      await tester.pump();
      h.db.orders.emit({'a': _order(status: 'paid')});
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(h.db.attaches, 2);
      expect(h.states.last.bundles, isEmpty);
      h.db.orders.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );
      await tester.pump();
      await h.close();
      await tester.pump(const Duration(seconds: 30));
      expect(h.db.attaches, 2);
      expect(h.db.active, 0);
    },
  );

  testWidgets(
    'cache-only microcuts keep SDK listeners; no manual reconnect storm',
    (tester) async {
      debugPrint = tester.binding.debugPrintOverride;
      final h = _SyncHarness();
      h.db.orders.emit({'a': _order()});
      h.db.items('a').emit({'i': _item()});
      for (var cycle = 0; cycle < 5; cycle++) {
        h.db.orders.emit({'a': _order()}, cache: true);
        h.db.items('a').emit({'i': _item()}, cache: true);
        await tester.pump(const Duration(seconds: 30));
        expect(h.db.attaches, 2);
        expect(h.states.last.status, KitchenSyncStatus.cache);
        h.db.orders.emit({'a': _order()});
        h.db.items('a').emit({'i': _item()});
        await tester.pump();
        expect(h.states.last.isConfirmed, isTrue);
      }
      await h.close();
      expect(h.db.active, 0);
    },
  );

  testWidgets(
    'real Kitchen list/detail display cache read-only, recover, and beep once for a new express',
    (tester) async {
      debugPrint = tester.binding.debugPrintOverride;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppSession.instance.signIn(Employee.fromDoc(_KitchenEmployeeDoc()));
      await LivePresenceService.instance.stop();
      final sounds = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('tacopos/kitchen_sound'),
            (call) async {
              sounds.add(call.method);
              return null;
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('tacopos/kitchen_sound'),
              null,
            ),
      );
      final repo = _KitchenUiRepository();
      await tester.pumpWidget(
        MaterialApp(home: KitchenScreen(repository: repo)),
      );
      await _pumpUi(tester);
      repo.db.orders.emit({'a': _order()}, cache: true);
      repo.db.items('a').emit({
        'i': _item(),
        'historical': _item(batch: 'historical', express: true),
      }, cache: true);
      await _pumpUi(tester);
      expect(find.text('Mesa'), findsWidgets);
      expect(find.textContaining('caché'), findsOneWidget);
      expect(sounds, isEmpty);
      expect(repo.markedCooking, 0);
      await tester.tap(find.text('Abrir comanda').first);
      await _pumpUi(tester);
      expect(find.byType(KitchenOrderDetailScreen), findsOneWidget);
      expect(repo.db.active, 2);
      expect(repo.markedCooking, 0);
      // Cached kitchen validation was false. Full confirmation must revalidate
      // actions, without preventing the already visible cache-only detail.
      repo.open = true;
      repo.db.orders.emit({'a': _order()});
      repo.db.items('a').emit({
        'i': _item(),
        'historical': _item(batch: 'historical', express: true),
      });
      await _pumpUi(tester);
      expect(repo.markedCooking, 1);
      expect(sounds, isEmpty);
      final extra = {
        'i': _item(),
        'historical': _item(batch: 'historical', express: true),
        'new': _item(batch: 'new', express: true),
      };
      repo.db.orders.emit({'a': _order()}, cache: true);
      repo.db.items('a').emit(extra, cache: true);
      await _pumpUi(tester);
      expect(sounds, isEmpty);
      repo.db.orders.emit({'a': _order()});
      repo.db.items('a').emit(extra);
      await _pumpUi(tester);
      expect(
        sounds.where((sound) => sound == 'playKitchenExpressBeep'),
        hasLength(1),
      );
      repo.db.items('a').emit(extra, cache: true);
      repo.db.items('a').emit(extra, changed: []);
      await _pumpUi(tester);
      expect(
        sounds.where((sound) => sound == 'playKitchenExpressBeep'),
        hasLength(1),
      );
      Navigator.of(tester.element(find.byType(KitchenOrderDetailScreen))).pop();
      await _pumpUi(tester);
      expect(repo.db.attaches, 2);
      expect(repo.db.active, 2);
      await tester.pumpWidget(const SizedBox());
      await _pumpUi(tester);
      expect(repo.db.active, 0);
    },
  );

  testWidgets(
    'Kitchen actions recover after transient open-session validation errors',
    (tester) async {
      debugPrint = tester.binding.debugPrintOverride;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppSession.instance.signIn(Employee.fromDoc(_KitchenEmployeeDoc()));
      await LivePresenceService.instance.stop();

      final repo = _KitchenUiRepository()
        ..open = true
        ..openValidationFailuresRemaining = 2;
      await tester.pumpWidget(
        MaterialApp(home: KitchenScreen(repository: repo)),
      );
      await _pumpUi(tester);
      repo.db.orders.emit({'a': _order()});
      repo.db.items('a').emit({
        'person-1': _item(personNumber: 1),
        'person-2': _item(personNumber: 2),
      });
      await _pumpUi(tester);
      expect(repo.markedCooking, 0);
      await tester.tap(find.text('Abrir comanda').first);
      await _pumpUi(tester);
      expect(find.byType(KitchenOrderDetailScreen), findsOneWidget);
      expect(find.text('Siguiente plato'), findsOneWidget);
      await tester.tap(find.text('Siguiente plato'));
      await tester.pump();
      expect(find.text('Listo'), findsNothing);

      // The feed stays server-confirmed while the separate kitchen-session
      // validation fails twice. The bounded retry must unlock only after the
      // repository confirms that the kitchen is open.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump();
      expect(repo.openValidations, 3);
      expect(repo.markedCooking, 1);

      await tester.tap(find.text('Siguiente plato'));
      await _pumpUi(tester);
      expect(find.text('Listo'), findsOneWidget);
      await tester.tap(find.text('Listo'));
      await _pumpUi(tester);
      expect(repo.kitchenStatusUpdates, hasLength(1));
      expect(repo.kitchenStatusUpdates.single.orderId, 'a');
      expect(
        repo.kitchenStatusUpdates.single.itemIds,
        unorderedEquals(['person-1', 'person-2']),
      );
      expect(repo.kitchenStatusUpdates.single.status, 'ready');
      expect(find.byType(KitchenOrderDetailScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Kitchen actions recover when opening changes after feed confirmation',
    (tester) async {
      debugPrint = tester.binding.debugPrintOverride;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppSession.instance.signIn(Employee.fromDoc(_KitchenEmployeeDoc()));
      await LivePresenceService.instance.stop();

      final repo = _KitchenUiRepository();
      addTearDown(repo.close);
      await tester.pumpWidget(
        MaterialApp(home: KitchenScreen(repository: repo)),
      );
      await _pumpUi(tester);
      repo.db.orders.emit({'a': _order()});
      repo.db.items('a').emit({'i': _item()});
      await _pumpUi(tester);
      expect(repo.open, isFalse);
      expect(repo.markedCooking, 0);

      await tester.tap(find.text('Abrir comanda').first);
      await _pumpUi(tester);
      expect(find.byType(KitchenOrderDetailScreen), findsOneWidget);
      expect(find.textContaining('Acciones pausadas'), findsOneWidget);

      repo.open = true;
      repo.kitchenSessions.add(
        const KitchenSession(
          id: 'kitchen-2026-11-24',
          businessDate: '2026-11-24',
          status: 'open',
          notes: '',
        ),
      );
      await _pumpUi(tester);
      expect(repo.markedCooking, 1);
      expect(find.text('Listo'), findsOneWidget);
      await tester.tap(find.text('Listo'));
      await _pumpUi(tester);
      expect(repo.kitchenStatusUpdates, hasLength(1));
      expect(repo.kitchenStatusUpdates.single.status, 'ready');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'permanent kitchen validation errors are shown without retrying',
    (tester) async {
      debugPrint = tester.binding.debugPrintOverride;
      AppSession.instance.signIn(Employee.fromDoc(_KitchenEmployeeDoc()));
      await LivePresenceService.instance.stop();

      final repo = _KitchenUiRepository()
        ..open = true
        ..openValidationErrorCode = 'permission-denied';
      await tester.pumpWidget(
        MaterialApp(home: KitchenScreen(repository: repo)),
      );
      await _pumpUi(tester);
      repo.db.orders.emit({'a': _order()});
      repo.db.items('a').emit({'i': _item()});
      await _pumpUi(tester);

      expect(repo.openValidations, 2);
      expect(repo.markedCooking, 0);
      expect(
        find.textContaining('No tienes permiso para validar'),
        findsOneWidget,
      );
      expect(find.textContaining('permission-denied'), findsNothing);
      await tester.pump(const Duration(seconds: 30));
      expect(repo.openValidations, 2);
      expect(repo.markedCooking, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'kitchen actions recover by explicit retry after 60s and exhausted backoff',
    (tester) async {
      debugPrint = tester.binding.debugPrintOverride;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppSession.instance.signIn(Employee.fromDoc(_KitchenEmployeeDoc()));
      await LivePresenceService.instance.stop();

      final repo = _KitchenUiRepository()
        ..open = true
        ..openValidationFailuresRemaining = 20;
      await tester.pumpWidget(
        MaterialApp(home: KitchenScreen(repository: repo)),
      );
      await _pumpUi(tester);
      repo.db.orders.emit({'a': _order()});
      repo.db.items('a').emit({
        'person-1': _item(personNumber: 1),
        'person-2': _item(personNumber: 2),
      });
      await _pumpUi(tester);
      await tester.tap(find.text('Abrir comanda').first);
      await _pumpUi(tester);

      // Exercise the complete 2/5/15-second retry budget, then leave the
      // network unavailable for a minute. No periodic retries should continue.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(repo.openValidations, 5);
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.pump(const Duration(seconds: 60));
      expect(repo.openValidations, 5);
      expect(repo.markedCooking, 0);

      // Connectivity is back. The operator can explicitly refresh the
      // authoritative kitchen-open check without reopening the screen.
      repo.openValidationFailuresRemaining = 0;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();
      expect(repo.openValidations, 6);
      expect(repo.markedCooking, 1);
      await tester.tap(find.text('Siguiente plato'));
      await _pumpUi(tester);
      expect(find.text('Listo'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'direct detail and real Live Operations show offline/no-cache and permanent errors honestly',
    (tester) async {
      debugPrint = tester.binding.debugPrintOverride;
      final repo = _KitchenUiRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: KitchenOrderDetailScreen(
            orderId: 'a',
            kitchenBatchId: 'initial',
            repository: repo,
          ),
        ),
      );
      repo.db.orders.emit({}, cache: true);
      await _pumpUi(tester);
      expect(
        find.textContaining('sin comandas guardadas disponibles'),
        findsOneWidget,
      );
      expect(find.byType(KitchenOrderDetailScreen), findsOneWidget);
      expect(repo.markedCooking, 0);
      repo.db.orders.emit({'a': _order()}, cache: true);
      repo.db.items('a').emit({'i': _item()}, cache: true);
      await _pumpUi(tester);
      expect(find.textContaining('Pastor'), findsWidgets);
      expect(find.textContaining('caché'), findsOneWidget);
      expect(repo.markedCooking, 0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KitchenLiveTab(
              repository: repo,
              canControl: true,
              onOpenOrder: (_) {},
            ),
          ),
        ),
      );
      await _pumpUi(tester);
      repo.db.orders.emit({}, cache: true);
      await _pumpUi(tester);
      expect(
        find.textContaining('sin comandas guardadas disponibles'),
        findsOneWidget,
      );
      repo.db.orders.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      await _pumpUi(tester);
      expect(find.textContaining('permission-denied'), findsOneWidget);
      expect(find.textContaining('Cargando'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _pumpUi(tester);
      expect(repo.db.active, 0);
    },
  );

  test(
    'A: unchanged active order keeps 2 listeners, no gets or rebuilds',
    () async {
      final h = _Harness();
      await h.seed(
        {'a': _order()},
        {
          'a': {'i': _item()},
        },
      );
      final before = logs.lastWhere(
        (line) => line.contains('orders_confirmed'),
      );
      h.db.orders.emit({'a': _order()}, changed: []);
      await _flush();
      expect(h.db.active, 2);
      expect(h.db.attaches, 2);
      expect(h.db.gets, 0);
      expect(_counter(logs.last, 'bundleRebuilds'), 1);
      expect(_counter(before, 'orderSnapshots'), 1);
      expect(h.values, hasLength(1));
      await h.close();
      expect(h.db.active, 0);
      expect(h.db.cancels, 2);
    },
  );

  test(
    'B: 10 orders, one parent and one item change rebuild only affected order',
    () async {
      final h = _Harness();
      final orders = {for (var i = 0; i < 10; i++) 'o$i': _order()};
      final items = {
        for (final id in orders.keys) id: {'i': _item()},
      };
      await h.seed(orders, items);
      expect(h.db.active, 11);
      expect(_counter(logs.last, 'bundleRebuilds'), 10);
      h.db.orders.emit({...orders, 'o3': _order(updated: 42)}, changed: ['o3']);
      await _flush();
      expect(_counter(logs.last, 'bundleRebuilds'), 11);
      h.db.items('o3').emit({'i': _item(qty: 2)});
      await _flush();
      expect(_counter(logs.last, 'bundleRebuilds'), 12);
      expect(h.db.attaches, 11);
      expect(h.db.gets, 0);
      expect(_signature(h.values.last), _signature(_reference(h.db)));
      // Measure the previous per-parent-event loop against the same boundary.
      for (final id in orders.keys) {
        await h.repo.getActiveKitchenItems(id);
      }
      expect(h.db.gets, 10);
      await h.close();
    },
  );

  test(
    'C: no initial snapshot is not empty; truly empty active order retains listener for extras',
    () async {
      final h = _Harness();
      h.db.orders.emit({'a': _order()});
      await _flush();
      expect(h.values, isEmpty);
      h.db.items('a').emit({});
      await _flush();
      expect(h.values.single, isEmpty);
      expect(h.db.active, 2);
      h.db.items('a').emit({'extra': _item(batch: 'extra', express: true)});
      await _flush();
      expect(h.values.last.single.stableKitchenKey, 'order:a:extra');
      h.db.items('a').emit({
        'extra': _item(batch: 'extra', express: true),
        'extra2': _item(batch: 'extra2', express: true),
      });
      await _flush();
      expect(h.values.last.map((b) => b.kitchenBatchId), ['extra', 'extra2']);
      expect(h.db.orders.snapshots, 1);
      expect(h.db.attaches, 2);
      expect(h.db.gets, 0);
      await h.close();
    },
  );

  test(
    'D/E: shared feed gives latest state to detail; 5 exits cancel every listener',
    () async {
      final db = _Firestore();
      final repo = TacoPosRepository(firestore: db, auth: _Auth());
      for (var cycle = 0; cycle < 5; cycle++) {
        final feed = KitchenBundlesFeed(repo.watchKitchenOrderBundles)..start();
        db.orders.emit({'a': _order()});
        await _flush();
        db.items('a').emit({'i': _item()});
        await _flush();
        final list = <List<KitchenOrderBundle>>[];
        final detail = <List<KitchenOrderBundle>>[];
        void listListener() {
          if (feed.value.hasData) list.add(feed.value.data!);
        }

        void detailListener() {
          if (feed.value.hasData) detail.add(feed.value.data!);
        }

        feed.addListener(listListener);
        feed.addListener(detailListener);
        // Late consumer sees exactly the last snapshot, without a new listen.
        final latest = feed.value.data!;
        feed.start();
        expect(db.active, 2);
        expect(db.attaches, (cycle + 1) * 2);
        db.items('a').emit({
          'i': _item(),
          'extra': _item(batch: 'extra', express: true),
        });
        await _flush();
        expect(identical(list.single, detail.single), isTrue);
        expect(latest.single.kitchenBatchId, 'initial');
        feed.removeListener(detailListener);
        expect(db.active, 2);
        feed.removeListener(listListener);
        feed.dispose();
        await _flush();
        expect(db.active, 0);
        expect(db.cancels, (cycle + 1) * 2);
      }
      expect(db.gets, 0);
    },
  );

  test(
    'F: cache, pending writes and server confirmation recover without attaching again',
    () async {
      final h = _Harness();
      h.db.orders.emit({'a': _order()}, cache: true);
      await _flush();
      expect(h.db.active, 2);
      expect(h.values, isEmpty);
      h.db.orders.emit({'a': _order()}, changed: []);
      await _flush();
      h.db.items('a').emit({}, cache: true);
      await _flush();
      expect(h.values, isEmpty);
      h.db.items('a').emit({'i': _item()});
      await _flush();
      final initial = _signature(h.values.last);
      final extra = {
        'i': _item(),
        'extra': _item(batch: 'extra', express: true),
      };
      h.db.items('a').emit(extra, cache: true);
      h.db.items('a').emit(extra, pending: true);
      h.db.orders.emit({}, cache: true);
      await _flush();
      expect(_signature(h.values.last), initial);
      expect(h.db.active, 2);
      // SDK may deliver only metadata on server acknowledgement.
      h.db.orders.emit({'a': _order()}, changed: []);
      h.db.items('a').emit(extra, changed: []);
      await _flush();
      expect(h.values.last, hasLength(2));
      expect(_signature(h.values.last), _signature(_reference(h.db)));
      expect(h.db.attaches, 2);
      expect(h.db.gets, 0);
      final count = h.values.length;
      h.db.items('a').emit(extra, changed: []);
      await _flush();
      expect(h.values, hasLength(count));
      await h.close();
    },
  );

  for (final terminal in ['paid', 'closed', 'cancelled']) {
    test(
      '$terminal cancels items; queued stale callback cannot revive or replace a new generation',
      () async {
        final h = _Harness();
        await h.seed(
          {'a': _order()},
          {
            'a': {'i': _item()},
          },
        );
        final oldCallback = h.db.items('a').listeners.single.dataCallback!;
        // Queue the closing parent first, then an old item callback. The fake
        // deliberately delivers queued callbacks even after cancellation.
        h.db.orders.emit({'a': _order(status: terminal)}, queued: true);
        h.db.items('a').emit({'stale': _item(batch: 'stale')}, queued: true);
        await _flush();
        expect(h.values.last, isEmpty);
        expect(h.db.items('a').active, 0);
        h.db.orders.emit({'a': _order()});
        await _flush();
        h.db.items('a').emit({'fresh': _item(batch: 'fresh')});
        await _flush();
        oldCallback(
          _Query(
            [_Doc('stale', _item(batch: 'stale'))],
            const _Metadata(false, false),
            ['stale'],
          ),
        );
        await _flush();
        expect(h.values.last.single.kitchenBatchId, 'fresh');
        await h.close();
      },
    );
  }

  test(
    'preparation, ready, cancellation and a second waiter update only their own state',
    () async {
      final h = _Harness();
      await h.seed(
        {'a': _order(), 'b': _order()},
        {
          'a': {'i': _item()},
          'b': {'i': _item()},
        },
      );
      h.db.items('a').emit({'i': _item(kitchen: 'cooking')});
      h.db.items('b').emit({
        'i': _item(),
        'e': _item(batch: 'extra', express: true),
      });
      await _flush();
      expect(_signature(h.values.last), _signature(_reference(h.db)));
      expect(h.values.last.first.items.first.kitchenStatus, 'cooking');
      h.db.items('a').emit({'i': _item(kitchen: 'ready')});
      h.db.items('b').emit({
        'i': _item(kitchen: 'cancelled'),
        'e': _item(batch: 'extra', express: true),
      });
      await _flush();
      expect(h.values.last.single.kitchenBatchId, 'extra');
      expect(h.db.active, 3); // Active parents retain their item listeners.
      await h.close();
    },
  );

  test(
    'item read errors propagate, never emit false empty, and recover with next valid snapshot',
    () async {
      final h = _Harness();
      await h.seed(
        {'a': _order()},
        {
          'a': {'i': _item()},
        },
      );
      h.db.items('a').error(StateError('temporary'));
      await _flush();
      expect(h.errors, hasLength(1));
      expect(h.values.last, hasLength(1));
      h.db.orders.emit({'a': _order(updated: 2)});
      await _flush();
      expect(h.values, hasLength(1));
      h.db.items('a').emit({'i': _item()}, changed: []);
      await _flush();
      expect(h.values, hasLength(2));
      expect(h.db.attaches, 2);
      await h.close();
    },
  );

  test(
    'new loading/error order never turns a known board into a partial successful list',
    () async {
      final h = _Harness();
      await h.seed(
        {'a': _order()},
        {
          'a': {'i': _item()},
        },
      );
      h.db.orders.emit({'a': _order(), 'b': _order()}, changed: ['b']);
      await _flush();
      h.db.items('b').error(StateError('unavailable'));
      h.db.items('a').emit({'i': _item(qty: 2)});
      await _flush();
      expect(h.values, hasLength(1));
      expect(h.errors, hasLength(1));
      h.db.items('b').emit({});
      await _flush();
      expect(h.values.last.single.items.single.qty, 2);
      await h.close();
    },
  );

  test(
    'historical fields, cross-day orders, branch scope and exact legacy sort/group equivalence',
    () async {
      final h = _Harness();
      final orders = {
        'legacy': <String, dynamic>{},
        'a': _order(updated: 25),
        'old': {
          ..._order(updated: 1),
          'businessDate': '2020-01-01',
          'orderType': 'standing',
          'customerName': 'Client',
        },
        'other': {..._order(), 'branchId': 'other'},
      };
      await h.seed(orders, {
        'legacy': {'z': _item(batch: ''), 'a': _item(batch: '')},
        'a': {
          'z': _item(batch: 'two', sequence: 2),
          'b': _item(batch: 'one', sequence: 1),
          'a': _item(batch: 'one', sequence: 1),
        },
        'old': {'a': _item(batch: '', kitchen: 'preparing')},
      });
      expect(h.db.items('other').attaches, 0);
      expect(_signature(h.values.last), _signature(_reference(h.db)));
      final oldListeners = h.db.attaches;
      h.db.orders.emit(
        {
          ...orders,
          'a': {...orders['a']!, 'businessDate': '2026-11-22'},
        },
        changed: ['a'],
      );
      await _flush();
      expect(h.db.attaches, oldListeners);
      expect(_signature(h.values.last), _signature(_reference(h.db)));
      await h.close();
    },
  );

  test(
    'branch change through unchanged shared feed cancels all old item subscriptions',
    () async {
      final db = _Firestore();
      final repo = TacoPosRepository(firestore: db, auth: _Auth());
      final feed = KitchenBundlesFeed(repo.watchKitchenOrderBundles)..start();
      db.orders.emit({
        'a': _order(),
        'b': {..._order(), 'branchId': 'centro'},
      });
      await _flush();
      db.items('a').emit({'i': _item()});
      await _flush();
      AppSession.instance.selectBranch(
        const Branch(
          id: 'centro',
          name: 'Centro',
          normalizedName: 'centro',
          active: true,
          sortOrder: 2,
        ),
      );
      expect(feed.value.hasData, isFalse);
      await _flush();
      expect(db.items('a').active, 0);
      db.orders.emit({
        'a': _order(),
        'b': {..._order(), 'branchId': 'centro'},
      });
      await _flush();
      db.items('b').emit({'i': _item()});
      await _flush();
      expect(feed.value.data!.single.order.id, 'b');
      feed.dispose();
      await _flush();
      expect(db.active, 0);
    },
  );

  testWidgets(
    'real Live Operations kitchen consumer: cache, server, update, transient error and dispose',
    (tester) async {
      debugPrint = tester.binding.debugPrintOverride;
      final db = _Firestore();
      final repo = TacoPosRepository(firestore: db, auth: _Auth());
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return KitchenLiveTab(
                  repository: repo,
                  canControl: true,
                  onOpenOrder: (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.textContaining('Cargando comandas'), findsOneWidget);
      db.orders.emit({'a': _order()}, cache: true);
      await tester.pump();
      db.items('a').emit({'i': _item()}, cache: true);
      await tester.pump();
      await tester.pump();
      expect(find.text('Mesa'), findsOneWidget);
      expect(find.textContaining('caché'), findsOneWidget);
      expect(
        find.text('Listo'),
        findsNothing,
      ); // Display does not enable offline actions.
      rebuild(() {});
      await tester.pump();
      expect(db.attaches, 2);
      db.orders.emit({'a': _order()});
      db.items('a').emit({'i': _item()});
      await tester.pump();
      await tester.pump();
      expect(find.text('Sincronizado con el servidor'), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
      db.items('a').emit({'i': _item(qty: 2, kitchen: 'cooking')});
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('2 Pastor'), findsWidgets);
      db
          .items('a')
          .error(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          );
      await tester.pump();
      await tester.pump();
      expect(find.text('Mesa'), findsOneWidget);
      expect(find.textContaining('Reconexión pendiente'), findsOneWidget);
      expect(db.active, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(db.active, 2);
      db.items('a').emit({'i': _item(qty: 3)});
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('3 Pastor'), findsWidgets);
      expect(find.text('Sincronizado con el servidor'), findsOneWidget);
      db
          .items('a')
          .error(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
            ),
          );
      await tester.pump();
      await tester.pump();
      expect(find.text('Mesa'), findsOneWidget);
      expect(find.textContaining('permission-denied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(db.attaches, 3);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(db.active, 0);
      expect(db.attaches, db.cancels);
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

int _counter(String log, String name) =>
    int.parse(RegExp('$name=(\\d+)').firstMatch(log)!.group(1)!);
Map<String, dynamic> _order({String status = 'open', int updated = 0}) => {
  'status': status,
  'updatedAt': Timestamp.fromMillisecondsSinceEpoch(updated),
};
Map<String, dynamic> _item({
  String batch = 'initial',
  String kitchen = 'sent',
  bool express = false,
  int qty = 1,
  int? sequence,
  int personNumber = 1,
}) => {
  'personNumber': personNumber,
  'personName': 'person',
  'productId': 'p',
  'productName': 'Pastor',
  'category': 'tacos',
  'qty': qty,
  'unitPrice': 20,
  'total': qty * 20,
  'sendToKitchen': true,
  'kitchenStatus': kitchen,
  'paymentStatus': 'pending',
  'kitchenBatchId': batch,
  'isKitchenExpress': express,
  'kitchenSequence': ?sequence,
};

class _Harness {
  _Harness() {
    repo = TacoPosRepository(firestore: db, auth: _Auth());
    subscription = repo.watchKitchenOrderBundles().listen(
      values.add,
      onError: (Object error) => errors.add(error),
    );
  }
  final db = _Firestore();
  late final TacoPosRepository repo;
  late final StreamSubscription<List<KitchenOrderBundle>> subscription;
  final values = <List<KitchenOrderBundle>>[];
  final errors = <Object>[];
  Future<void> seed(
    Map<String, Map<String, dynamic>> orders,
    Map<String, Map<String, Map<String, dynamic>>> items,
  ) async {
    db.orders.emit(orders);
    await _flush();
    for (final entry in items.entries) {
      db.items(entry.key).emit(entry.value);
    }
    await _flush();
  }

  Future<void> close() => subscription.cancel();
}

class _SyncHarness {
  _SyncHarness() {
    repo = TacoPosRepository(firestore: db, auth: _Auth());
    subscription = repo.watchKitchenOrderBundlesState().listen(states.add);
  }
  final db = _Firestore();
  late final TacoPosRepository repo;
  late final StreamSubscription<KitchenBundlesState> subscription;
  final states = <KitchenBundlesState>[];
  Future<void> close() => subscription.cancel();
}

class _Auth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _KitchenUiRepository implements TacoPosRepository {
  final db = _Firestore();
  final kitchenSessions = StreamController<KitchenSession?>.broadcast();
  late final delegate = TacoPosRepository(firestore: db, auth: _Auth());
  int markedCooking = 0;
  bool open = false;
  int openValidationFailuresRemaining = 0;
  int openValidations = 0;
  String? openValidationErrorCode;
  final kitchenStatusUpdates = <_KitchenStatusUpdate>[];
  @override
  Stream<KitchenBundlesState> watchKitchenOrderBundlesState() =>
      delegate.watchKitchenOrderBundlesState();
  @override
  Stream<KitchenSession?> watchOpenKitchenSession() => kitchenSessions.stream;
  @override
  Future<bool> hasCompletedOpenKitchenForCurrentBusinessDate() async {
    openValidations++;
    if (openValidationErrorCode != null) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: openValidationErrorCode!,
      );
    }
    if (openValidationFailuresRemaining > 0) {
      openValidationFailuresRemaining--;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return open;
  }

  Future<void> close() => kitchenSessions.close();

  @override
  Future<void> reconcileOpenOrdersForKitchen() async {}
  @override
  Future<void> markActiveKitchenItemsCooking(
    String orderId, {
    String? kitchenBatchId,
  }) async {
    markedCooking++;
  }

  @override
  Future<void> updateKitchenItemsStatus({
    required String orderId,
    required Iterable<String> itemIds,
    required String status,
  }) async {
    kitchenStatusUpdates.add(
      _KitchenStatusUpdate(orderId, itemIds.toList(), status),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _KitchenStatusUpdate {
  const _KitchenStatusUpdate(this.orderId, this.itemIds, this.status);
  final String orderId;
  final List<String> itemIds;
  final String status;
}

// ignore: subtype_of_sealed_class
class _KitchenEmployeeDoc implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  String get id => 'kitchen';
  @override
  Map<String, dynamic> data() => {'name': 'Cocina', 'canViewKitchen': true};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Firestore implements FirebaseFirestore {
  final channels = <String, _Channel>{};
  int gets = 0;
  _Channel channel(String path) => channels.putIfAbsent(path, _Channel.new);
  _Channel get orders => channel(_ordersPath);
  _Channel items(String id) => channel(_itemsPath(id));
  int get active => channels.values.fold(0, (n, c) => n + c.active);
  int get attaches => channels.values.fold(0, (n, c) => n + c.attaches);
  int get cancels => channels.values.fold(0, (n, c) => n + c.cancels);
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection(this, collectionPath);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.db, this.path);
  final _Firestore db;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(db, '${this.path}/$path');
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    expectSync(includeMetadataChanges, isTrue);
    return _InputStream(db.channel(path));
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    db.gets++;
    return db.channel(path).last!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Document implements DocumentReference<Map<String, dynamic>> {
  _Document(this.db, this.path);
  final _Firestore db;
  @override
  final String path;
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection(db, '$path/$collectionPath');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Channel {
  final listeners = <_Subscription>[];
  _Query? last;
  int snapshots = 0;
  int attaches = 0;
  int cancels = 0;
  int get active => listeners.where((s) => !s.cancelled).length;
  void emit(
    Map<String, Map<String, dynamic>> data, {
    List<String>? changed,
    bool cache = false,
    bool pending = false,
    bool queued = false,
  }) {
    final docs = data.entries
        .map((entry) => _Doc(entry.key, Map.of(entry.value)))
        .toList();
    final query = _Query(
      docs,
      _Metadata(cache, pending),
      changed ?? data.keys.toList(),
    );
    last = query;
    snapshots++;
    for (final subscription in listeners.where((s) => !s.cancelled).toList()) {
      if (queued) {
        scheduleMicrotask(() => subscription.dataCallback?.call(query));
      } else {
        subscription.dataCallback?.call(query);
      }
    }
  }

  void error(Object error) {
    for (final subscription in listeners.where((s) => !s.cancelled).toList()) {
      scheduleMicrotask(
        () => Function.apply(subscription.errorCallback!, [
          error,
          StackTrace.current,
        ]),
      );
    }
  }
}

class _InputStream extends Stream<QuerySnapshot<Map<String, dynamic>>> {
  _InputStream(this.channel);
  final _Channel channel;
  @override
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> listen(
    void Function(QuerySnapshot<Map<String, dynamic>>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    channel.attaches++;
    final subscription = _Subscription(channel, onData, onError);
    channel.listeners.add(subscription);
    return subscription;
  }
}

class _Subscription
    implements StreamSubscription<QuerySnapshot<Map<String, dynamic>>> {
  _Subscription(this.channel, this.dataCallback, this.errorCallback);
  final _Channel channel;
  final void Function(QuerySnapshot<Map<String, dynamic>>)? dataCallback;
  final Function? errorCallback;
  bool cancelled = false;
  @override
  Future<void> cancel() async {
    if (cancelled) return;
    cancelled = true;
    channel.cancels++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Doc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Doc(this.id, this.value);
  @override
  final String id;
  final Map<String, dynamic> value;
  @override
  Map<String, dynamic> data() => value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Query implements QuerySnapshot<Map<String, dynamic>> {
  _Query(this.docs, this.metadata, this.changed);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  final SnapshotMetadata metadata;
  final List<String> changed;
  @override
  List<DocumentChange<Map<String, dynamic>>> get docChanges => [
    for (final id in changed) _Change(_Doc(id, {})),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Change implements DocumentChange<Map<String, dynamic>> {
  _Change(this.doc);
  @override
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Metadata implements SnapshotMetadata {
  const _Metadata(this.isFromCache, this.hasPendingWrites);
  @override
  final bool isFromCache;
  @override
  final bool hasPendingWrites;
}

// Independent legacy oracle: the previous full recomputation, including input
// iteration order, local item sorting, batching and all comparator fallbacks.
List<KitchenOrderBundle> _reference(_Firestore db) {
  final result = <KitchenOrderBundle>[];
  for (final doc in db.orders.last!.docs) {
    final order = PosOrder.fromDoc(doc);
    if (!isActiveOrder(order)) continue;
    if (order.branchId != AppSession.instance.currentBranchId) continue;
    final items =
        db
            .items(order.id)
            .last!
            .docs
            .map(OrderItem.fromDoc)
            .where(isKitchenPendingItem)
            .toList()
          ..sort((a, b) {
            final person = a.personNumber.compareTo(b.personNumber);
            return person != 0
                ? person
                : a.productName.compareTo(b.productName);
          });
    final batches = <String, List<OrderItem>>{};
    for (final item in items) {
      final batch = item.kitchenBatchId?.trim();
      final key = batch == null || batch.isEmpty
          ? 'order:${order.id}'
          : 'batch:$batch';
      batches.putIfAbsent(key, () => []).add(item);
    }
    for (final batch in batches.values) {
      if (batch.isNotEmpty) {
        result.add(KitchenOrderBundle(order: order, items: batch));
      }
    }
  }
  result.sort((a, b) {
    final asq = a.kitchenSequence;
    final bsq = b.kitchenSequence;
    if (asq != null && bsq != null) {
      final compare = asq.compareTo(bsq);
      if (compare != 0) return compare;
    } else if (asq != null) {
      return -1;
    } else if (bsq != null) {
      return 1;
    }
    DateTime start(KitchenOrderBundle bundle) {
      final dates =
          bundle.items
              .map((item) => item.sentToKitchenAt)
              .whereType<DateTime>()
              .toList()
            ..sort();
      return dates.isNotEmpty
          ? dates.first
          : bundle.order.updatedAt ??
                bundle.order.createdAt ??
                DateTime.fromMillisecondsSinceEpoch(0);
    }

    return start(a).compareTo(start(b));
  });
  return result;
}

List<String> _signature(List<KitchenOrderBundle> bundles) => [
  for (final bundle in bundles)
    '${bundle.stableKitchenKey}|${bundle.kitchenSequence}|${bundle.isKitchenExpress}|${bundle.order.customerName}|${bundle.items.map((i) => '${i.id}:${i.qty}:${i.kitchenStatus}').join(',')}',
];
