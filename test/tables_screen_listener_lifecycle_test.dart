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
import 'package:tacopos/models/pos_table.dart';
import 'package:tacopos/screens/waiter/tables_screen.dart';
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

  testWidgets('rebuilds and navigation keep one live orders subscription', (
    tester,
  ) async {
    final repository = _TablesRepository();
    addTearDown(repository.close);
    await _signIn();
    late StateSetter rebuildParent;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuildParent = setState;
            return TablesScreen(repository: repository);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.orderStreamCalls, 1);
    // The nested orders builder attaches once the first nonempty table list arrives.
    repository.tablesFor('aviacion').add([_table('Mesa Uno')]);
    await tester.pumpAndSettle();
    expect(repository.ordersFor('aviacion').attaches, 1);
    expect(repository.ordersFor('aviacion').active, 1);
    repository.ordersFor('aviacion').add([]);
    await tester.pumpAndSettle();
    expect(find.text('Mesa Uno'), findsOneWidget);

    rebuildParent(() {});
    await tester.pumpAndSettle();
    expect(repository.orderStreamCalls, 1);
    expect(repository.ordersFor('aviacion').attaches, 1);

    repository.tablesFor('aviacion').add([
      _table('Mesa Uno'),
      _table('Mesa Dos', orderId: 'partial'),
    ]);
    repository.ordersFor('aviacion').add([
      _order('partial', 'Pedido parcial', 'partial'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Mesa Uno'), findsOneWidget);
    expect(find.text('Pedido parcial'), findsOneWidget);

    repository.ordersFor('aviacion').add([
      _order('partial', 'Pedido actualizado', 'partial'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Pedido actualizado'), findsOneWidget);
    expect(find.text('Pedido parcial'), findsNothing);

    final context = tester.element(find.byType(TablesScreen));
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Detalle de orden')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.ordersFor('aviacion').attaches, 1);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(find.text('Pedido actualizado'), findsOneWidget);
    expect(repository.ordersFor('aviacion').attaches, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(repository.ordersFor('aviacion').active, 0);
    expect(repository.ordersFor('aviacion').cancels, 1);
    expect(repository.tablesFor('aviacion').active, 0);

    await tester.pumpWidget(
      MaterialApp(home: TablesScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(repository.orderStreamCalls, 2);
    repository.tablesFor('aviacion').add([_table('Mesa Uno')]);
    await tester.pumpAndSettle();
    expect(repository.ordersFor('aviacion').attaches, 2);
    expect(repository.ordersFor('aviacion').active, 1);
  });

  testWidgets('kitchen item changes update table state on one stable stream', (
    tester,
  ) async {
    final repository = _TablesRepository();
    addTearDown(repository.close);
    await _signIn();
    await tester.pumpWidget(
      MaterialApp(home: TablesScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    repository.tablesFor('aviacion').add([_table('Mesa Uno', orderId: 'open')]);
    await tester.pumpAndSettle();
    repository.ordersFor('aviacion').add([
      _order('open', 'Orden de Mesa Uno', 'open'),
    ]);
    await tester.pumpAndSettle();
    final itemStream = repository.itemsFor('open');
    expect(repository.itemStreamCalls, 1);
    expect(itemStream.active, 1);

    itemStream.add([_kitchenItem(kitchenStatus: 'pending')]);
    await tester.pumpAndSettle();
    expect(find.text('Pendiente de enviar'), findsWidgets);

    itemStream.add([_kitchenItem(kitchenStatus: 'pending', sent: true)]);
    await tester.pumpAndSettle();
    expect(find.text('En cocina'), findsWidgets);

    itemStream.add([_kitchenItem(kitchenStatus: 'cooking', sent: true)]);
    await tester.pumpAndSettle();
    expect(find.text('En preparacion'), findsWidgets);

    itemStream.add([_kitchenItem(kitchenStatus: 'ready', sent: true)]);
    await tester.pumpAndSettle();
    expect(find.text('Listo para cobrar'), findsWidgets);

    // A normal parent/table/order rebuild must retain the same item listener.
    repository.tablesFor('aviacion').add([_table('Mesa Uno', orderId: 'open')]);
    repository.ordersFor('aviacion').add([
      _order('open', 'Orden de Mesa Uno', 'partial'),
    ]);
    await tester.pumpAndSettle();
    expect(repository.itemStreamCalls, 1);
    expect(itemStream.attaches, 1);
    expect(itemStream.active, 1);

    itemStream.add([
      _kitchenItem(kitchenStatus: 'ready', sent: true),
      _kitchenItem(id: 'extra', kitchenStatus: 'pending'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Pendiente de enviar'), findsWidgets);

    repository.tablesFor('aviacion').add([_table('Mesa Uno')]);
    repository.ordersFor('aviacion').add([]);
    await tester.pumpAndSettle();
    expect(itemStream.active, 0);
    expect(find.text('Lista para tomar orden'), findsOneWidget);
  });

  testWidgets('branch switch clears old rows and attaches only new streams', (
    tester,
  ) async {
    final repository = _TablesRepository();
    addTearDown(repository.close);
    await _signIn();
    await tester.pumpWidget(
      MaterialApp(home: TablesScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    repository.tablesFor('aviacion').add([
      _table('Mesa anterior', orderId: 'open'),
    ]);
    await tester.pumpAndSettle();
    repository.ordersFor('aviacion').add([
      _order('open', 'Orden histórica activa', 'open'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Orden histórica activa'), findsOneWidget);

    AppSession.instance.selectBranch(
      const Branch(
        id: 'centro',
        name: 'Centro',
        normalizedName: 'centro',
        active: true,
        sortOrder: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Orden histórica activa'), findsNothing);
    expect(repository.ordersFor('aviacion').active, 0);
    expect(repository.ordersFor('aviacion').cancels, 1);
    expect(repository.orderStreamCalls, 2);

    repository.tablesFor('centro').add([
      _table('Mesa Centro', orderId: 'partial-centro'),
    ]);
    await tester.pumpAndSettle();
    repository.ordersFor('centro').add([
      _order('partial-centro', 'Orden parcial Centro', 'partial'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Orden parcial Centro'), findsOneWidget);
    expect(find.text('Mesa anterior'), findsNothing);
    expect(repository.ordersFor('centro').attaches, 1);
    expect(repository.ordersFor('centro').active, 1);

    repository.tablesFor('aviacion').add([_table('Cambio tardío')]);
    repository.ordersFor('aviacion').add([
      _order('open', 'Dato de sucursal anterior', 'open'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Dato de sucursal anterior'), findsNothing);
    expect(find.text('Orden parcial Centro'), findsOneWidget);
  });

  testWidgets('replacing the repository renews the stream once', (
    tester,
  ) async {
    final first = _TablesRepository();
    final second = _TablesRepository();
    addTearDown(first.close);
    addTearDown(second.close);
    await _signIn();
    await tester.pumpWidget(MaterialApp(home: TablesScreen(repository: first)));
    await tester.pumpAndSettle();
    first.tablesFor('aviacion').add([_table('Mesa primera')]);
    await tester.pumpAndSettle();
    first.ordersFor('aviacion').add([]);
    await tester.pumpAndSettle();
    expect(first.ordersFor('aviacion').active, 1);

    await tester.pumpWidget(
      MaterialApp(home: TablesScreen(repository: second)),
    );
    await tester.pumpAndSettle();
    expect(first.ordersFor('aviacion').active, 0);
    expect(second.orderStreamCalls, 1);
    expect(find.text('Mesa primera'), findsNothing);
    second.tablesFor('aviacion').add([_table('Mesa segunda')]);
    await tester.pumpAndSettle();
    second.ordersFor('aviacion').add([]);
    await tester.pumpAndSettle();
    expect(second.ordersFor('aviacion').attaches, 1);
    expect(find.text('Mesa segunda'), findsOneWidget);
  });
}

Future<void> _signIn() async {
  AppSession.instance.signIn(Employee.fromDoc(_EmployeeDoc()));
  await LivePresenceService.instance.stop();
}

PosTable _table(String name, {String? orderId}) => PosTable(
  id: name,
  name: name,
  type: 'table',
  status: orderId == null ? 'available' : 'occupied',
  active: true,
  sortOrder: 0,
  currentOrderId: orderId,
);

PosOrder _order(String id, String name, String paymentStatus) => PosOrder(
  id: id,
  tableId: id,
  tableName: name,
  status: 'open',
  kitchenStatus: 'ready',
  paymentStatus: paymentStatus,
  total: 100,
  paidTotal: paymentStatus == 'partial' ? 50 : 0,
  pendingTotal: paymentStatus == 'partial' ? 50 : 100,
  personNames: const {},
  orderType: 'dine_in',
);

class _TrackedStream<T> {
  late final StreamController<T> controller = StreamController<T>.broadcast(
    onListen: () {
      attaches++;
      active++;
    },
    onCancel: () {
      cancels++;
      active--;
    },
  );
  int attaches = 0;
  int cancels = 0;
  int active = 0;

  Stream<T> get stream => controller.stream;
  void add(T value) => controller.add(value);
  Future<void> close() => controller.close();
}

class _TablesRepository implements TacoPosRepository {
  final _orders = <String, _TrackedStream<List<PosOrder>>>{};
  final _tables = <String, _TrackedStream<List<PosTable>>>{};
  final _items = <String, _TrackedStream<List<OrderItem>>>{};
  int orderStreamCalls = 0;
  int itemStreamCalls = 0;

  _TrackedStream<List<PosOrder>> ordersFor(String branch) =>
      _orders.putIfAbsent(branch, _TrackedStream<List<PosOrder>>.new);
  _TrackedStream<List<PosTable>> tablesFor(String branch) =>
      _tables.putIfAbsent(branch, _TrackedStream<List<PosTable>>.new);
  _TrackedStream<List<OrderItem>> itemsFor(String orderId) =>
      _items.putIfAbsent(orderId, _TrackedStream<List<OrderItem>>.new);

  @override
  Stream<List<PosOrder>> watchOpenOrders() {
    orderStreamCalls++;
    return ordersFor(AppSession.instance.currentBranchId).stream;
  }

  @override
  Stream<List<PosTable>> watchTables({bool activeOnly = true}) =>
      tablesFor(AppSession.instance.currentBranchId).stream;

  @override
  Stream<List<OrderItem>> watchOrderItems(
    String orderId, {
    bool requireServer = false,
  }) {
    itemStreamCalls++;
    return itemsFor(orderId).stream;
  }

  @override
  Future<GhostOrderReconciliationResult> reconcileGhostOrdersAndTableLinks({
    String restaurantId = '',
    required String branchId,
    String? businessDate,
    String triggeredBy = 'operational_reconciliation',
  }) async => GhostOrderReconciliationResult(
    businessDate: '2026-11-21',
    branchId: branchId,
    candidatesChecked: 0,
    cancelledOrderIds: const [],
    staleTableLinks: 0,
    releasedTableLinks: 0,
  );

  Future<void> close() async {
    for (final stream in [
      ..._orders.values,
      ..._tables.values,
      ..._items.values,
    ]) {
      await stream.close();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

OrderItem _kitchenItem({
  String id = 'item-1',
  required String kitchenStatus,
  bool sent = false,
}) => OrderItem(
  id: id,
  personNumber: 1,
  personName: 'Persona 1',
  productId: 'taco',
  productName: 'Taco',
  category: 'tacos',
  qty: 1,
  unitPrice: 20,
  total: 20,
  notes: '',
  sendToKitchen: true,
  kitchenStatus: kitchenStatus,
  paymentStatus: 'pending',
  sentToKitchenAt: sent ? DateTime.utc(2026, 11, 24) : null,
  kitchenBatchId: sent ? 'batch-1' : null,
);

// ignore: subtype_of_sealed_class
class _EmployeeDoc implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  String get id => 'waiter';

  @override
  Map<String, dynamic> data() => {
    'name': 'Mesero',
    'canTakeOrders': true,
    'canCharge': true,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
