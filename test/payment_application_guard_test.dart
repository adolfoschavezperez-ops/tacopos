import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/payment_application_guard.dart';
import 'package:tacopos/models/payment.dart';

void main() {
  test('full cash aplica solo saldo pendiente y conserva recibido/cambio', () {
    final plan = planPaymentApplication(
      orderNetAmount: 290,
      previousActivePayments: [_payment(id: 'partial', amount: 102)],
      requestedAppliedAmount: 290,
      paymentType: 'full_table',
      method: 'cash',
      cashReceivedAmount: 290,
      cashChangeAmount: 102,
    );

    expect(plan.remainingAmount, 188);
    expect(plan.appliedAmount, 188);
    expect(plan.cashReceivedAmount, 290);
    expect(plan.cashChangeAmount, 102);
    expect(102 + plan.appliedAmount, closeTo(290, paymentApplicationTolerance));
  });

  test('full cash sin pagos previos aplica total y conserva cambio', () {
    final plan = planPaymentApplication(
      orderNetAmount: 290,
      previousActivePayments: const [],
      requestedAppliedAmount: 290,
      paymentType: 'full_table',
      method: 'cash',
      cashReceivedAmount: 300,
      cashChangeAmount: 10,
    );

    expect(plan.remainingAmount, 290);
    expect(plan.appliedAmount, 290);
    expect(plan.cashReceivedAmount, 300);
    expect(plan.cashChangeAmount, 10);
  });

  test('full card con pago parcial previo aplica solo restante', () {
    final plan = planPaymentApplication(
      orderNetAmount: 500,
      previousActivePayments: [_payment(id: 'partial', amount: 200)],
      requestedAppliedAmount: 500,
      paymentType: 'full_table',
      method: 'card',
    );

    expect(plan.remainingAmount, 300);
    expect(plan.appliedAmount, 300);
  });

  test('partial nuevo dentro del saldo conserva importe capturado', () {
    final plan = planPaymentApplication(
      orderNetAmount: 500,
      previousActivePayments: [_payment(id: 'partial-1', amount: 200)],
      requestedAppliedAmount: 100,
      paymentType: 'partial',
      method: 'cash',
    );

    expect(plan.remainingAmount, 300);
    expect(plan.appliedAmount, 100);
    expect(200 + plan.appliedAmount, 300);
  });

  test('normaliza paymentData full_table para no sobreaplicar', () {
    final data = normalizePaymentDataForRemaining(
      paymentData: {
        'type': 'full_table',
        'method': 'cash',
        'subtotalBeforeDiscount': 290.0,
        'discountAmount': 0.0,
        'totalAfterDiscount': 290.0,
        'appliedAmount': 290.0,
        'baseAmount': 290.0,
        'amount': 290.0,
        'chargedAmount': 290.0,
        'cashReceivedAmount': 290.0,
        'cashChangeAmount': 102.0,
      },
      orderNetAmount: 290,
      previousActivePayments: [_payment(id: 'partial', amount: 102)],
    );

    expect(data['appliedAmount'], 188);
    expect(data['amount'], 188);
    expect(data['chargedAmount'], 188);
    expect(data['cashReceivedAmount'], 290);
    expect(data['cashChangeAmount'], 102);
  });

  test('pendingTotal fresco limita el importe aplicado final', () {
    final data = normalizePaymentDataForRemaining(
      paymentData: {
        'type': 'full_table',
        'method': 'cash',
        'subtotalBeforeDiscount': 290.0,
        'discountAmount': 0.0,
        'totalAfterDiscount': 290.0,
        'appliedAmount': 290.0,
        'baseAmount': 290.0,
        'amount': 290.0,
        'chargedAmount': 290.0,
        'cashReceivedAmount': 290.0,
        'cashChangeAmount': 102.0,
      },
      orderNetAmount: 290,
      previousActivePayments: const [],
      freshPendingAmount: 188,
    );

    expect(data['appliedAmount'], 188);
    expect(data['cashReceivedAmount'], 290);
    expect(data['cashChangeAmount'], 102);
  });

  test('partial que excede saldo lanza error', () {
    expect(
      () => planPaymentApplication(
        orderNetAmount: 500,
        previousActivePayments: [_payment(id: 'partial', amount: 200)],
        requestedAppliedAmount: 301,
        paymentType: 'partial',
      ),
      throwsArgumentError,
    );
  });
}

Payment _payment({required String id, required double amount}) {
  return Payment(
    id: id,
    orderId: 'order',
    tableId: 'table',
    tableName: 'Mesa 1',
    type: 'partial',
    method: 'cash',
    baseAmount: amount,
    surchargeRate: 0,
    surchargeAmount: 0,
    chargedAmount: amount,
    appliedAmount: amount,
    status: 'active',
  );
}
