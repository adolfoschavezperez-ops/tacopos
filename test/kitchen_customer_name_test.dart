import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/screens/kitchen/kitchen_screen.dart';
import 'package:tacopos/screens/kitchen/kitchen_order_detail_screen.dart';
import 'package:tacopos/services/app_session.dart';
import 'package:tacopos/services/live_presence_service.dart';
import 'package:tacopos/services/taco_pos_repository.dart';

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
  tearDown(() async {
    await LivePresenceService.instance.stop();
    AppSession.instance.signOut();
  });

  for (final size in [const Size(1024, 768), const Size(1280, 900)]) {
    for (final fixture in [
      (type: 'takeout', name: 'Ana López'),
      (type: 'standing', name: 'Luis Pérez'),
      (type: 'dine_in', name: 'No mostrar en mesa'),
      (type: 'takeout', name: ''),
      (type: 'standing', name: '   '),
      (
        type: 'takeout',
        name:
            'María con un nombre de cliente muy largo que debe caber sin desplazar los controles de la cocina',
      ),
    ]) {
      testWidgets('${fixture.type} customer name at $size: ${fixture.name}', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        _order = PosOrder(
          id: 'order',
          tableId: 'table',
          tableName: 'Mesa 4',
          status: 'sent',
          kitchenStatus: 'sent',
          paymentStatus: 'pending',
          total: 20,
          paidTotal: 0,
          pendingTotal: 20,
          personNames: const {1: 'Persona'},
          orderType: fixture.type,
          customerName: fixture.name,
          takeoutNumber: 12,
        );
        await _login();
        final repo = _Repository();
        addTearDown(repo.controller.close);
        await tester.pumpWidget(
          MaterialApp(home: KitchenScreen(repository: repo)),
        );
        await _pump(tester);
        repo.emit([_bundle('initial', express: fixture.name.length > 50)]);
        await _pump(tester);
        final showName =
            fixture.type != 'dine_in' && fixture.name.trim().isNotEmpty;
        expect(
          find.text('Cliente: ${fixture.name.trim()}'),
          showName ? findsOneWidget : findsNothing,
        );
        expect(find.text('#17'), findsOneWidget);
        expect(find.text(_order.displayName), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Abrir comanda'));
        await _pump(tester);
        expect(find.byType(KitchenOrderDetailScreen), findsOneWidget);
        expect(
          find.text('Cliente: ${fixture.name.trim()}'),
          showName ? findsOneWidget : findsNothing,
        );
        expect(find.text('#17'), findsOneWidget);
        expect(find.byIcon(Icons.close), findsOneWidget);
        expect(repo.calls, 1);
        expect(repo.attaches, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await _pump(tester);
        expect(repo.cancels, 1);
      });
    }
  }
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

late PosOrder _order;
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
  kitchenSequence: 17,
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
