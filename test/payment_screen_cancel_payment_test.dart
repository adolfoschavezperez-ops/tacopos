import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/payments/payment_cancellation.dart';
import 'package:tacopos/core/theme/app_theme.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/payment.dart';
import 'package:tacopos/models/purchase_models.dart';
import 'package:tacopos/screens/waiter/payment_screen.dart';
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

  Future<_Repo> cancelFromScreen(
    WidgetTester tester,
    Future<PaymentCancellationResult> Function() behavior,
  ) async {
    final repo = _Repo(behavior);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppSession.instance.signIn(Employee.fromDoc(_CashierDoc()));
    await LivePresenceService.instance.stop();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: PaymentScreen(orderId: 'order', repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar pago').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Cobro duplicado');
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('cancelacion confirmada muestra "Pago cancelado."', (
    tester,
  ) async {
    final repo = await cancelFromScreen(
      tester,
      () async => const PaymentCancellationResult(
        outcome: PaymentCancellationOutcome.cancelled,
        authoritativePendingTotal: 100,
      ),
    );
    expect(repo.calls, ['order/cash-30:Cobro duplicado']);
    expect(find.text('Pago cancelado.'), findsOneWidget);
    expect(find.text('El pago ya había sido cancelado.'), findsNothing);
  });

  testWidgets('pago ya cancelado muestra su propio mensaje', (tester) async {
    await cancelFromScreen(
      tester,
      () async => const PaymentCancellationResult(
        outcome: PaymentCancellationOutcome.alreadyCancelled,
      ),
    );
    expect(find.text('El pago ya había sido cancelado.'), findsOneWidget);
    expect(find.text('Pago cancelado.'), findsNothing);
  });

  testWidgets('error conserva el comportamiento actual sin exito falso', (
    tester,
  ) async {
    await cancelFromScreen(
      tester,
      () async => throw StateError('Sin conexion con el servidor.'),
    );
    expect(find.text('Sin conexion con el servidor.'), findsOneWidget);
    expect(find.text('Pago cancelado.'), findsNothing);
    expect(find.text('El pago ya había sido cancelado.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'Live Operations registra la intervencion solo via el flujo probado',
    () {
      final source = File(
        'lib/screens/admin/live_operations_screen.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final start = source.indexOf(
        'Future<void> _cancelPayment(BuildContext context, Payment payment)',
      );
      expect(start, isNonNegative);
      final body = source.substring(start, source.indexOf('\n  }\n', start));
      expect(body, contains('runOperatorPaymentCancellation('));
      expect(body, contains('recordIntervention: () => repository'));
      expect(body, contains('if (!context.mounted) return;'));
      expect(
        RegExp(r'await\s+repository\.logBackofficeIntervention').hasMatch(body),
        isFalse,
      );
      expect(
        RegExp(r'await\s+repository\.cancelPayment').hasMatch(body),
        isFalse,
      );
    },
  );
}

// ignore: subtype_of_sealed_class
class _CashierDoc implements DocumentSnapshot<Map<String, dynamic>> {
  @override
  String get id => 'cashier';
  @override
  Map<String, dynamic> data() => {
    'name': 'Caja',
    'canCharge': true,
    'canCancelPayments': true,
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repo implements TacoPosRepository {
  _Repo(this.behavior);

  final Future<PaymentCancellationResult> Function() behavior;
  final calls = <String>[];

  @override
  Future<PaymentCancellationResult> cancelPayment({
    required String orderId,
    required String paymentId,
    required String reason,
  }) {
    calls.add('$orderId/$paymentId:$reason');
    return behavior();
  }

  @override
  Stream<PosOrder?> watchOrder(String orderId, {bool requireServer = false}) =>
      Stream.value(
        PosOrder(
          id: 'order',
          tableId: 'table',
          tableName: 'Mesa 1',
          status: 'ready',
          kitchenStatus: 'ready',
          paymentStatus: 'partial',
          total: 130,
          grossSubtotal: 130,
          netTotal: 130,
          explicitDiscount: 0,
          paidTotal: 30,
          pendingTotal: 100,
          personNames: const {},
          orderType: 'table',
        ),
      );

  @override
  Stream<List<OrderItem>> watchOrderItems(
    String orderId, {
    bool requireServer = false,
  }) => Stream.value([
    OrderItem(
      id: 'item',
      personNumber: 1,
      personName: 'Persona 1',
      productId: 'p',
      productName: 'Producto',
      category: 'Bebidas',
      qty: 1,
      unitPrice: 130,
      total: 130,
      notes: '',
      sendToKitchen: false,
      kitchenStatus: 'not_required',
      paymentStatus: 'pending',
    ),
  ]);

  @override
  Stream<List<Payment>> watchOrderPayments(
    String orderId, {
    bool requireServer = false,
  }) => Stream.value([
    Payment(
      id: 'cash-30',
      orderId: 'order',
      tableId: 'table',
      tableName: 'Mesa 1',
      type: 'partial',
      method: 'cash',
      baseAmount: 30,
      surchargeRate: 0,
      surchargeAmount: 0,
      chargedAmount: 30,
      appliedAmount: 30,
      subtotalBeforeDiscount: 30,
      discountAmount: 0,
      totalAfterDiscount: 30,
    ),
  ]);

  @override
  Stream<List<Employee>> watchEmployees({bool activeOnly = true}) =>
      Stream.value([]);

  @override
  Stream<List<Partner>> watchPartners({bool activeOnly = false}) =>
      Stream.value([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
