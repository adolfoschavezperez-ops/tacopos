import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/payments/payment_operational_scope.dart';
import 'package:tacopos/models/cash_session.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/payment.dart';

void main() {
  group('resolveNewPaymentOperationalScope', () {
    test('order session == active session -> payment OK', () {
      final order = _order(cashSessionId: 'session-b');
      final scope = resolveNewPaymentOperationalScope(
        order: order,
        activeCashSession: _session('session-b'),
      );

      expect(scope.cashSessionId, 'session-b');
      expect(scope.businessDate, '2026-08-22');
    });

    test('order session != active session -> payment OK in active session', () {
      final order = _order(cashSessionId: 'session-a');
      final scope = resolveNewPaymentOperationalScope(
        order: order,
        activeCashSession: _session('session-b'),
      );

      expect(scope.cashSessionId, 'session-b');
      expect(scope.businessDate, '2026-08-22');
      expect(order.cashSessionId, 'session-a');
    });

    test(
      'previous payment session A + new payment session B are preserved',
      () {
        final previousPayment = _payment(
          id: 'payment-a',
          amount: 200,
          cashSessionId: 'session-a',
        );
        final order = _order(
          cashSessionId: 'session-a',
          total: 500,
          paidTotal: 200,
          pendingTotal: 300,
        );
        final scope = resolveNewPaymentOperationalScope(
          order: order,
          activeCashSession: _session('session-b'),
        );
        final newPayment = _payment(
          id: 'payment-b',
          amount: 300,
          cashSessionId: scope.cashSessionId,
          businessDate: scope.businessDate,
        );

        expect(previousPayment.cashSessionId, 'session-a');
        expect(newPayment.cashSessionId, 'session-b');
        expect(previousPayment.chargedAmount + newPayment.chargedAmount, 500);
      },
    );

    test('no active cash session blocks payment', () {
      final order = _order();

      expect(
        () => resolveNewPaymentOperationalScope(
          order: order,
          activeCashSession: null,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'No hay una caja abierta para registrar el pago.',
          ),
        ),
      );
    });

    test('closed active session blocks payment', () {
      final order = _order();

      expect(
        () => resolveNewPaymentOperationalScope(
          order: order,
          activeCashSession: _session('session-b', status: 'closed'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'La sesion de caja ya esta cerrada.',
          ),
        ),
      );
    });

    test('cancelled order blocks payment', () {
      final order = _order(status: 'cancelled', paymentStatus: 'cancelled');

      expect(
        () => resolveNewPaymentOperationalScope(
          order: order,
          activeCashSession: _session('session-b'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'No se puede cobrar una orden cancelada.',
          ),
        ),
      );
    });

    test('zero pending total blocks duplicate payment', () {
      final order = _order(
        paymentStatus: 'paid',
        total: 500,
        paidTotal: 500,
        pendingTotal: 0,
      );

      expect(
        () => resolveNewPaymentOperationalScope(
          order: order,
          activeCashSession: _session('session-b'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'La orden no tiene saldo pendiente por cobrar.',
          ),
        ),
      );
    });

    test('cash/card split payments use active session', () {
      final order = _order(cashSessionId: 'session-a', pendingTotal: 300);
      final scope = resolveNewPaymentOperationalScope(
        order: order,
        activeCashSession: _session('session-b'),
      );
      final cashPayment = _payment(
        id: 'cash',
        method: 'cash',
        amount: 120,
        cashSessionId: scope.cashSessionId,
      );
      final cardPayment = _payment(
        id: 'card',
        method: 'card',
        amount: 180,
        cashSessionId: scope.cashSessionId,
      );

      expect(cashPayment.cashSessionId, 'session-b');
      expect(cardPayment.cashSessionId, 'session-b');
      expect(cashPayment.method, 'cash');
      expect(cardPayment.method, 'card');
    });

    test('new payment impacts current cash session B only', () {
      final order = _order(
        cashSessionId: 'session-a',
        businessDate: '2026-08-21',
      );
      final scope = resolveNewPaymentOperationalScope(
        order: order,
        activeCashSession: _session('session-b', businessDate: '2026-08-22'),
      );

      expect(scope.cashSessionId, 'session-b');
      expect(scope.businessDate, '2026-08-22');
      expect(scope.cashSessionId, isNot(order.cashSessionId));
      expect(scope.businessDate, isNot(order.businessDate));
    });
  });
}

PosOrder _order({
  String id = 'order-1',
  String status = 'open',
  String paymentStatus = 'pending',
  String? cashSessionId = 'session-a',
  String businessDate = '2026-08-21',
  double total = 500,
  double paidTotal = 0,
  double pendingTotal = 500,
}) {
  return PosOrder(
    id: id,
    tableId: 'table-1',
    tableName: 'Mesa 1',
    status: status,
    kitchenStatus: 'ready',
    paymentStatus: paymentStatus,
    total: total,
    paidTotal: paidTotal,
    pendingTotal: pendingTotal,
    personNames: const {},
    orderType: 'dine_in',
    businessDate: businessDate,
    cashSessionId: cashSessionId,
  );
}

CashSession _session(
  String id, {
  String status = 'open',
  String businessDate = '2026-08-22',
}) {
  return CashSession(
    id: id,
    businessDate: businessDate,
    status: status,
    openingCashAmount: 500,
    openedByEmployeeId: 'employee-1',
    openedByEmployeeName: 'Empleado',
    countedCashAmount: 0,
    terminalReportedAmount: 0,
    expectedCashAmount: 0,
    expectedCardChargedAmount: 0,
    expectedCardBaseAmount: 0,
    expectedCardSurchargeAmount: 0,
    expectedCardFeeAbsorbedAmount: 0,
    expectedPlatformAmount: 0,
    expectedEmployeeConsumptionAmount: 0,
    totalExpectedRealMoney: 0,
    totalCountedRealMoney: 0,
    cashDifference: 0,
    cardDifference: 0,
    netDifference: 0,
    shortageAmount: 0,
    overAmount: 0,
    approvedWithdrawalsTotal: 0,
    pendingWithdrawalsTotal: 0,
    withdrawalRequestCount: 0,
    notes: '',
  );
}

Payment _payment({
  required String id,
  String method = 'cash',
  required double amount,
  required String cashSessionId,
  String businessDate = '2026-08-22',
}) {
  return Payment(
    id: id,
    orderId: 'order-1',
    tableId: 'table-1',
    tableName: 'Mesa 1',
    type: 'partial',
    method: method,
    baseAmount: amount,
    surchargeRate: 0,
    surchargeAmount: 0,
    chargedAmount: amount,
    cashSessionId: cashSessionId,
    businessDate: businessDate,
  );
}
