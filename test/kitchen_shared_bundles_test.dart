import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/models/branch.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/screens/kitchen/kitchen_bundles_feed.dart';
import 'package:tacopos/screens/kitchen/kitchen_screen.dart';
import 'package:tacopos/screens/kitchen/kitchen_order_detail_screen.dart';
import 'package:tacopos/services/app_session.dart';
import 'package:tacopos/services/live_presence_service.dart';
import 'package:tacopos/services/taco_pos_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  final sounds = <String>[];
  setUpAll(() async {
    await Firebase.initializeApp();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceSet',
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('tacopos/kitchen_sound'),
          (call) async {
            sounds.add(call.method);
            return null;
          },
        );
  });
  setUp(() {
    sounds.clear();
  });
  tearDown(() async {
    await LivePresenceService.instance.stop();
    AppSession.instance.signOut();
  });

  testWidgets(
    'list and detail share upstream, replay extras and deduplicate reconnect sounds',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _login();
      final repo = _Repository();
      addTearDown(repo.controller.close);
      await tester.pumpWidget(
        MaterialApp(home: KitchenScreen(repository: repo)),
      );
      await _pump(tester);
      expect(repo.calls, 1);
      expect(repo.attaches, 1);
      repo.emit([_bundle('initial')]);
      await _pump(tester);
      await tester.tap(find.text('Mesa 4').first);
      // Arrives while the detail route is opening.
      repo.emit([_bundle('initial'), _bundle('extra-1', express: true)]);
      await _pump(tester);
      expect(find.byType(KitchenOrderDetailScreen), findsOneWidget);
      expect(find.textContaining('express pendientes'), findsNothing);
      expect(find.text('Surtido express'), findsWidgets);
      expect(repo.calls, 1);
      expect(repo.attaches, 1);
      expect(sounds.where((s) => s == 'playKitchenExpressBeep'), hasLength(1));

      repo.emit([
        _bundle('initial'),
        _bundle('extra-1', express: true),
        _bundle('extra-2', express: true),
      ]);
      await _pump(tester);
      expect(find.text('+1 express pendientes'), findsOneWidget);
      expect(sounds.where((s) => s == 'playKitchenExpressBeep'), hasLength(2));
      // Repeated snapshot after a simulated microcut must not attach or beep again.
      repo.emit([
        _bundle('initial'),
        _bundle('extra-1', express: true),
        _bundle('extra-2', express: true),
      ]);
      await _pump(tester);
      expect(sounds.where((s) => s == 'playKitchenExpressBeep'), hasLength(2));
      expect(repo.attaches, 1);

      final detailContext = tester.element(
        find.byType(KitchenOrderDetailScreen),
      );
      Navigator.of(detailContext).pop();
      await _pump(tester);
      expect(repo.cancels, 0);
      expect(find.byType(KitchenOrderDetailScreen), findsNothing);
      expect(find.text('Surtido express'), findsWidgets);
      // Paid/cancelled orders disappear as supplied by the unchanged repository.
      repo.emit([]);
      await _pump(tester);
      expect(find.text('Sin comandas activas'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _pump(tester);
      expect(repo.cancels, 1);
    },
  );

  testWidgets('branch switch clears list and cancels the prior upstream', (
    tester,
  ) async {
    await _login();
    final repo = _Repository();
    addTearDown(repo.controller.close);
    await tester.pumpWidget(MaterialApp(home: KitchenScreen(repository: repo)));
    await _pump(tester);
    repo.emit([_bundle('initial')]);
    await _pump(tester);
    expect(find.text('Mesa 4'), findsWidgets);
    AppSession.instance.selectBranch(
      const Branch(
        id: 'centro',
        name: 'Centro',
        normalizedName: 'centro',
        active: true,
        sortOrder: 2,
      ),
    );
    await _pump(tester);
    expect(find.text('Mesa 4'), findsNothing);
    expect(repo.calls, 2);
    expect(repo.cancels, 1);
    repo.emit([]);
    await _pump(tester);
    expect(find.text('Sin comandas activas'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
    expect(repo.cancels, 2);
  });

  testWidgets('direct detail owns one feed and exposes loading errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _login();
    final repo = _Repository();
    addTearDown(repo.controller.close);
    await tester.pumpWidget(
      MaterialApp(
        home: KitchenOrderDetailScreen(
          orderId: 'order',
          kitchenBatchId: 'initial',
          repository: repo,
        ),
      ),
    );
    await _pump(tester);
    expect(repo.attaches, 1);
    expect(find.text('Cargando comandas express...'), findsOneWidget);
    repo.controller.addError(StateError('offline'));
    await _pump(tester);
    expect(
      find.textContaining('No se pudieron cargar comandas express'),
      findsOneWidget,
    );
    repo.emit([_bundle('extra', express: true)]);
    await _pump(tester);
    expect(find.text('Surtido express'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
    expect(repo.cancels, 1);
  });

  test(
    'shared state preserves snapshot identity, order, batches and clears branch data',
    () async {
      final repo = _Repository();
      final feed = KitchenBundlesFeed(repo.watchKitchenOrderBundles);
      feed.start();
      feed.start();
      final values = [_bundle('b', express: true), _bundle('a')];
      repo.emit(values);
      await Future<void>.delayed(Duration.zero);
      expect(identical(feed.value.data, values), isTrue);
      expect(feed.value.data!.map((b) => b.kitchenBatchId), ['b', 'a']);
      // A late consumer reads the exact same last state, without another watch.
      expect(feed.value.data!.first.stableKitchenKey, 'order:order:b');
      expect(repo.calls, 1);
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
      expect(feed.value.connectionState, ConnectionState.waiting);
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls, 2);
      expect(repo.cancels, 1);
      repo.emit([_bundle('centro')]);
      await Future<void>.delayed(Duration.zero);
      expect(feed.value.data!.single.kitchenBatchId, 'centro');
      feed.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(repo.cancels, 2);
      await repo.controller.close();
    },
  );
}

Future<void> _login() async {
  AppSession.instance.signIn(Employee.fromDoc(_EmployeeDoc()));
  await LivePresenceService.instance.stop();
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

const _order = PosOrder(
  id: 'order',
  tableId: 'table',
  tableName: 'Mesa 4',
  status: 'sent',
  kitchenStatus: 'sent',
  paymentStatus: 'pending',
  total: 20,
  paidTotal: 0,
  pendingTotal: 20,
  personNames: {1: 'Persona'},
  orderType: 'dine_in',
);
OrderItem _item(String batch, {bool express = false}) => OrderItem(
  id: batch,
  personNumber: 1,
  personName: 'Persona',
  productId: 'pastor',
  productName: 'Pastor',
  category: 'tacos',
  qty: 1,
  unitPrice: 20,
  total: 20,
  notes: '',
  sendToKitchen: true,
  kitchenStatus: 'sent',
  paymentStatus: 'pending',
  kitchenBatchId: batch,
  isKitchenExpress: express,
);
KitchenOrderBundle _bundle(String batch, {bool express = false}) =>
    KitchenOrderBundle(
      order: _order,
      items: [_item(batch, express: express)],
    );

class _Repository implements TacoPosRepository {
  int calls = 0;
  int attaches = 0;
  int cancels = 0;
  late final controller = StreamController<List<KitchenOrderBundle>>.broadcast(
    onListen: () {
      attaches++;
    },
    onCancel: () {
      cancels++;
    },
  );
  void emit(List<KitchenOrderBundle> bundles) => controller.add(bundles);
  @override
  Stream<List<KitchenOrderBundle>> watchKitchenOrderBundles() {
    calls++;
    return controller.stream;
  }

  @override
  Future<void> reconcileOpenOrdersForKitchen() async {}
  @override
  Future<bool> hasCompletedOpenKitchenForCurrentBusinessDate() async => true;
  @override
  Stream<PosOrder?> watchOrder(String orderId, {bool requireServer = false}) =>
      Stream.value(_order);
  @override
  Stream<List<OrderItem>> watchKitchenItems(
    String orderId, {
    String? kitchenBatchId,
  }) => Stream.value([_item('initial')]);
  @override
  Future<void> markActiveKitchenItemsCooking(
    String orderId, {
    String? kitchenBatchId,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _EmployeeDoc implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  String get id => 'kitchen';
  @override
  Map<String, dynamic> data() => {'name': 'Cocina', 'canViewKitchen': true};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
