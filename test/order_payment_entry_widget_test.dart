import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/order_capture_queue.dart';
import 'package:tacopos/core/orders/order_payment_reconciliation.dart';
import 'package:tacopos/core/theme/app_theme.dart';
import 'package:tacopos/models/cash_session.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/payment.dart';
import 'package:tacopos/models/product.dart';
import 'package:tacopos/models/product_category.dart';
import 'package:tacopos/models/purchase_models.dart';
import 'package:tacopos/screens/waiter/order_screen.dart';
import 'package:tacopos/screens/waiter/payment_screen.dart';
import 'package:tacopos/services/app_session.dart';
import 'package:tacopos/services/live_presence_service.dart';
import 'package:tacopos/services/taco_pos_repository.dart';
import 'package:tacopos/widgets/money_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    await Firebase.initializeApp();
    // Presence writes are unrelated to checkout; no network is used by tests.
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

  for (final size in [const Size(412, 915), const Size(1280, 720)]) {
    testWidgets(
      'capture hides order/person totals before and after adding at $size',
      (tester) async {
        final repo = _CheckoutRepository();
        await _showOrder(tester, repo, size: size);
        _expectNoCaptureTotal(tester);
        final before = tester
            .widgetList<MoneyText>(find.byType(MoneyText))
            .length;
        await tester.tap(find.text('Producto 30').last);
        await tester.pumpAndSettle();
        _expectNoCaptureTotal(tester);
        expect(repo.items.length, 3);
        expect(
          tester.widgetList<MoneyText>(find.byType(MoneyText)).length,
          greaterThanOrEqualTo(before),
        );
        expect(find.text('Cobrar'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty queue validates on server then opens the current total', (
    tester,
  ) async {
    final repo = _CheckoutRepository();
    await _showOrder(tester, repo);
    await tester.tap(find.text('Cobrar'));
    await tester.pumpAndSettle();
    expect(find.byType(PaymentScreen), findsOneWidget);
    expect(repo.events, [
      'flush',
      'recalculate-server',
      'prepare-server',
      'read-server',
    ]);
    _expectStat(tester, 'Total', 100);
    _expectStat(tester, 'Pendiente', 100);
  });

  testWidgets(
    'last product plus immediate double Cobrar waits for all writes and includes 190',
    (tester) async {
      final repo = _CheckoutRepository()..writeGate = Completer<void>();
      await _showOrder(tester, repo);
      for (final price in [30, 40, 20]) {
        await tester.tap(find.text('Producto $price').last);
        await tester.pump();
      }
      final charge = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Cobrar'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      // Invoke twice before a rebuild, the race that a disabled button cannot prevent.
      charge.onPressed!();
      charge.onPressed!();
      await tester.pump();
      expect(find.byType(PaymentScreen), findsNothing);
      expect(repo.events, ['flush']);
      expect(
        find.byWidgetPredicate(
          (w) => w is LinearProgressIndicator && w.value == null,
        ),
        findsOneWidget,
      );
      _expectNoCaptureTotal(tester);
      repo.writeGate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        repo.events,
        ['flush', 'recalculate-server', 'prepare-server', 'read-server'],
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join('\n'),
      );
      expect(find.byType(PaymentScreen), findsOneWidget);
      expect(repo.events.where((event) => event == 'flush').length, 1);
      _expectStat(tester, 'Total', 190);
      _expectStat(tester, 'Pendiente', 190);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    },
  );

  testWidgets('remote change before checkout replaces stale capture order', (
    tester,
  ) async {
    final repo = _CheckoutRepository();
    await _showOrder(tester, repo);
    repo.items.add(_item('remote', 75));
    await tester.tap(find.text('Cobrar'));
    await tester.pumpAndSettle();
    _expectStat(tester, 'Total', 175);
  });

  final cases =
      <
        ({
          String name,
          List<Payment> payments,
          double net,
          double paid,
          double pending,
        })
      >[
        (
          name: 'partial cash',
          payments: [_payment('cash', 30, 30)],
          net: 100,
          paid: 30,
          pending: 70,
        ),
        (
          name: 'split cash/card',
          payments: [_payment('cash', 30, 30), _payment('card', 20, 20)],
          net: 100,
          paid: 50,
          pending: 50,
        ),
        (
          name: 'person payment',
          payments: [_payment('cash', 30, 30, type: 'person')],
          net: 100,
          paid: 30,
          pending: 70,
        ),
        (
          name: 'Employee 30',
          payments: [
            _payment(
              'cash',
              50,
              35,
              discount: 15,
              discountType: 'employee',
              percent: 30,
            ),
          ],
          net: 85,
          paid: 50,
          pending: 50,
        ),
        (
          name: 'Partner 50',
          payments: [
            _payment(
              'cash',
              50,
              25,
              discount: 25,
              discountType: 'partner',
              percent: 50,
            ),
          ],
          net: 75,
          paid: 50,
          pending: 50,
        ),
        (
          name: 'Family/Friend',
          payments: [
            _payment(
              'cash',
              50,
              40,
              discount: 10,
              discountType: 'family_friend',
              percent: 20,
            ),
          ],
          net: 90,
          paid: 50,
          pending: 50,
        ),
        (
          name: 'free meal with remaining balance',
          payments: [
            _payment(
              'employee_consumption',
              50,
              0,
              discount: 50,
              discountType: 'employee_daily_meal',
              percent: 100,
            ),
          ],
          net: 50,
          paid: 50,
          pending: 50,
        ),
        (
          name: 'full free meal',
          payments: [
            _payment(
              'employee_consumption',
              100,
              0,
              discount: 100,
              discountType: 'employee_daily_meal',
              percent: 100,
            ),
          ],
          net: 0,
          paid: 100,
          pending: 0,
        ),
      ];
  for (final fixture in cases) {
    testWidgets('checkout preserves canonical ${fixture.name}', (tester) async {
      final repo = _CheckoutRepository()..payments.addAll(fixture.payments);
      await _showOrder(tester, repo);
      await tester.tap(find.text('Cobrar'));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentScreen), findsOneWidget);
      _expectStat(tester, 'Total', fixture.net);
      // The checkout panel displays monetary paid, as defined by existing logic.
      _expectStat(tester, 'Pendiente', fixture.pending);
      expect(repo.order.paidTotal, fixture.paid);
    });
  }

  for (final stage in [
    'flush',
    'recalculate-server',
    'prepare-server',
    'read-server',
  ]) {
    testWidgets(
      '$stage failure keeps payment closed and allows explicit retry',
      (tester) async {
        final repo = _CheckoutRepository()..failureStage = stage;
        await _showOrder(tester, repo);
        await tester.tap(find.text('Cobrar'));
        await tester.pumpAndSettle();
        expect(find.byType(PaymentScreen), findsNothing);
        expect(
          find.textContaining('No se pudo validar el total'),
          findsOneWidget,
        );
        _expectNoCaptureTotal(tester);
        repo.failureStage = null;
        await tester.tap(find.text('Cobrar'));
        await tester.pumpAndSettle();
        expect(find.byType(PaymentScreen), findsOneWidget);
      },
    );
  }

  testWidgets(
    'does not display a provisional balance while prior payments load',
    (tester) async {
      final repo = _CheckoutRepository()
        ..paymentsGate = Completer<List<Payment>>();
      repo.payments.add(_payment('cash', 30, 30));
      await _showOrder(tester, repo);
      await tester.tap(find.text('Cobrar'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(PaymentScreen), findsOneWidget);
      expect(find.byType(MoneyText), findsNothing);
      repo.paymentsGate!.complete(repo.payments);
      await tester.pumpAndSettle();
      _expectStat(tester, 'Pendiente', 70);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
}

Future<void> _showOrder(
  WidgetTester tester,
  _CheckoutRepository repo, {
  Size size = const Size(412, 915),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(repo.queue.dispose);
  AppSession.instance.signIn(Employee.fromDoc(_EmployeeDoc()));
  // Keep permissions while avoiding the presence heartbeat in widget fake time.
  await LivePresenceService.instance.stop();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: OrderScreen(
        orderId: 'order',
        tableName: 'Mesa 1',
        repository: repo,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectNoCaptureTotal(WidgetTester tester) {
  for (final label in ['TOTAL', 'Total', 'Total mesa', 'Total a pagar']) {
    expect(find.text(label), findsNothing);
  }
  // Unit/menu and item amounts remain, but no order/person aggregate is rendered.
  expect(
    tester.widgetList<MoneyText>(find.byType(MoneyText)).map((w) => w.value),
    isNot(contains(100)),
  );
}

void _expectStat(WidgetTester tester, String label, double amount) {
  final labelFinder = find.text(label);
  final parent = find
      .ancestor(of: labelFinder, matching: find.byType(Column))
      .first;
  expect(
    tester
        .widget<MoneyText>(
          find.descendant(of: parent, matching: find.byType(MoneyText)),
        )
        .value,
    amount,
  );
}

OrderItem _item(String id, double price) => OrderItem(
  id: id,
  personNumber: 1,
  personName: 'Persona 1',
  productId: id,
  productName: 'Producto $id',
  category: 'Bebidas',
  qty: 1,
  unitPrice: price,
  total: price,
  notes: '',
  sendToKitchen: false,
  kitchenStatus: 'not_required',
  paymentStatus: 'pending',
);

Payment _payment(
  String method,
  double gross,
  double monetary, {
  String type = 'partial',
  double discount = 0,
  String? discountType,
  double percent = 0,
}) => Payment(
  id: '$method-$gross',
  orderId: 'order',
  tableId: 'table',
  tableName: 'Mesa 1',
  type: type,
  method: method,
  baseAmount: gross,
  surchargeRate: 0,
  surchargeAmount: 0,
  chargedAmount: monetary,
  appliedAmount: monetary,
  subtotalBeforeDiscount: gross,
  discountAmount: discount,
  totalAfterDiscount: monetary,
  appliedDiscountType: discountType,
  appliedDiscountPercent: percent,
);

// Test snapshot used to establish the same permissions as a waiter login.
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

class _CheckoutRepository implements TacoPosRepository {
  final queue = OrderCaptureQueue();
  final items = [_item('base-60', 60), _item('base-40', 40)];
  final payments = <Payment>[];
  final events = <String>[];
  Completer<void>? writeGate;
  Completer<List<Payment>>? paymentsGate;
  String? failureStage;
  late PosOrder order = _reconciledOrder();

  PosOrder _reconciledOrder() {
    final gross = activeOrderItemsTotal(items);
    final totals = reconcileOrderPayments(
      orderGrossTotal: gross,
      activePayments: payments.map(PaymentSettlementInput.fromPayment),
    );
    return PosOrder(
      id: 'order',
      tableId: 'table',
      tableName: 'Mesa 1',
      status: 'open',
      kitchenStatus: 'ready',
      paymentStatus: totals.paymentStatus,
      total: gross,
      grossSubtotal: gross,
      netTotal: totals.netTotal,
      explicitDiscount: totals.discountAmount,
      paidTotal: totals.paidTotal,
      pendingTotal: totals.pendingTotal,
      personNames: const {},
      orderType: 'table',
    );
  }

  void _stage(String stage) {
    events.add(stage);
    if (failureStage == stage) throw StateError('sin conexion: $stage');
  }

  @override
  Future<void> flushPendingMutations(String orderId) async {
    _stage('flush');
    await queue.flush(orderId, recalculate: () async {});
  }

  @override
  Future<void> recalculateOrderTotal(
    String orderId, {
    Source source = Source.serverAndCache,
  }) async {
    expectSync(source, Source.server);
    _stage('recalculate-server');
    order = _reconciledOrder();
  }

  @override
  Future<CheckoutPreparation> prepareOrderForCheckout(
    String orderId, {
    Source source = Source.serverAndCache,
  }) async {
    expectSync(source, Source.server);
    _stage('prepare-server');
    return CheckoutPreparation(
      orderId: orderId,
      grossSubtotal: order.total,
      discountAmount: order.explicitDiscount,
      netTotal: order.netTotal!,
      discountSource: 'none',
      discountCatalogId: null,
      discountName: null,
      discountPercent: 0,
      frozenByPayments: payments.isNotEmpty,
    );
  }

  @override
  Future<PosOrder> getOrderOnce(
    String orderId, {
    Source source = Source.serverAndCache,
  }) async {
    expectSync(source, Source.server);
    _stage('read-server');
    return order;
  }

  @override
  Future<void> addProductToOrder({
    required String orderId,
    required Product product,
    required int personNumber,
    bool? knownStockedOut,
    String? itemId,
    String? operationId,
  }) {
    return queue.enqueue(orderId, () async {
      await writeGate?.future;
      items.add(_item(itemId!, product.price));
    }, recalculate: () async {});
  }

  @override
  Stream<PosOrder?> watchOrder(String orderId, {bool requireServer = false}) {
    if (events.isNotEmpty) expectSync(requireServer, isTrue);
    return Stream.value(order);
  }

  @override
  Stream<List<OrderItem>> watchOrderItems(
    String orderId, {
    bool requireServer = false,
  }) => Stream.value(List.of(items));
  @override
  Future<List<OrderItem>> getOrderItemsOnce(String orderId) async =>
      List.of(items);
  @override
  Stream<List<Payment>> watchOrderPayments(
    String orderId, {
    bool requireServer = false,
  }) {
    expectSync(requireServer, isTrue);
    return Stream.fromFuture(
      paymentsGate?.future ?? Future.value(List.of(payments)),
    );
  }

  @override
  Stream<List<Product>> watchProducts({bool activeOnly = true}) =>
      Stream.value([
        for (final price in [30, 40, 20])
          Product.fromMap('$price', {
            'name': 'Producto $price',
            'category': 'Bebidas',
            'price': price,
            'active': true,
            'sendToKitchen': false,
          }),
      ]);
  @override
  Stream<List<ProductCategory>> watchProductCategories({
    bool activeOnly = true,
  }) => Stream.value([]);
  @override
  Future<CashSession?> getOpenCashSession() async => null;
  @override
  Stream<Map<String, ProductStockOutRow>> watchActiveProductStockOuts({
    Future<String>? businessDateFuture,
  }) => Stream.value({});
  @override
  Stream<List<Employee>> watchEmployees({bool activeOnly = true}) =>
      Stream.value([]);
  @override
  Stream<List<Partner>> watchPartners({bool activeOnly = false}) =>
      Stream.value([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
