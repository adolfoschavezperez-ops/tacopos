import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/payment.dart';
import 'package:tacopos/services/taco_pos_repository.dart';

void main() {
  group('buildRepositoryPaymentPersistencePreview', () {
    test('existing folio with 193 paid and 88 extras persists only 88', () {
      final preview = buildRepositoryPaymentPersistencePreview(
        order: _order(net: 281, pending: 88),
        paymentData: _paymentData(method: 'cash', amount: 88),
        previousActivePayments: [
          _payment(amount: 193, type: 'full_table', id: 'payment-193'),
        ],
        freshPendingAmount: 88,
        newPaymentId: 'attempt-extra-88',
      );

      expect(preview.paymentData['amount'], 88);
      expect(preview.totals.monetaryPaid, 281);
      expect(preview.totals.paidTotal, 281);
      expect(preview.totals.pendingTotal, 0);
      expect(preview.totals.paymentStatus, 'paid');
    });

    test('payment persisted then response lost retries without duplicate', () {
      final retryPayment = _payment(
        amount: 88,
        type: 'full_table',
        id: 'attempt-extra-88',
      );
      final preview = buildRepositoryPaymentPersistencePreview(
        order: _order(net: 281, pending: 88),
        paymentData: _paymentData(method: 'cash', amount: 88),
        previousActivePayments: [
          _payment(amount: 193, type: 'full_table', id: 'payment-193'),
          retryPayment,
        ],
        freshPendingAmount: 88,
        newPaymentId: retryPayment.id,
      );

      expect(preview.totals.monetaryPaid, 281);
      expect(preview.totals.pendingTotal, 0);
    });

    test('full_table cash after partial persists only remaining balance', () {
      final preview = buildRepositoryPaymentPersistencePreview(
        order: _order(net: 290, pending: 188),
        paymentData: _paymentData(
          method: 'cash',
          amount: 290,
          cashReceivedAmount: 290,
          cashChangeAmount: 102,
        ),
        previousActivePayments: [_payment(amount: 102, type: 'partial')],
        freshPendingAmount: 188,
        newPaymentId: 'final-payment',
      );

      final data = preview.paymentData;
      expect(data['amount'], 188);
      expect(data['appliedAmount'], 188);
      expect(data['baseAmount'], 188);
      expect(data['chargedAmount'], 188);
      expect(data['subtotalBeforeDiscount'], 188);
      expect(data['totalAfterDiscount'], 188);
      expect(data['cashReceivedAmount'], 290);
      expect(data['cashChangeAmount'], 102);
      expect(preview.totals.monetaryPaid, 290);
      expect(preview.totals.paidTotal, 290);
      expect(preview.totals.pendingTotal, 0);
    });

    test('full_table card after partial persists only remaining balance', () {
      final preview = buildRepositoryPaymentPersistencePreview(
        order: _order(net: 500, pending: 300),
        paymentData: _paymentData(method: 'card', amount: 500),
        previousActivePayments: [_payment(amount: 200, type: 'partial')],
        freshPendingAmount: 300,
        newPaymentId: 'final-card-payment',
      );

      final data = preview.paymentData;
      expect(data['amount'], 300);
      expect(data['appliedAmount'], 300);
      expect(data['baseAmount'], 300);
      expect(data['chargedAmount'], 300);
      expect(preview.totals.monetaryPaid, 500);
      expect(preview.totals.pendingTotal, 0);
    });
  });

  group('decidePaymentFinalization', () {
    test('folio with pending balance reuses folio and continues payment', () {
      final decision = decidePaymentFinalization(
        pendingTotal: 88,
        existingFolio: '0012',
      );

      expect(decision.alreadyPaid, isFalse);
      expect(decision.reuseExistingFolio, isTrue);
    });

    test('folio with zero pending is idempotently already paid', () {
      final decision = decidePaymentFinalization(
        pendingTotal: 0,
        existingFolio: '0012',
      );

      expect(decision.alreadyPaid, isTrue);
      expect(decision.reuseExistingFolio, isFalse);
    });

    test('normal unpaid order allocates its first folio', () {
      final decision = decidePaymentFinalization(
        pendingTotal: 193,
        existingFolio: null,
      );

      expect(decision.alreadyPaid, isFalse);
      expect(decision.reuseExistingFolio, isFalse);
    });
  });
}

PosOrder _order({required double net, required double pending}) {
  return PosOrder(
    id: 'order',
    tableId: 'table-4',
    tableName: 'Mesa 4',
    status: 'open',
    kitchenStatus: 'ready',
    paymentStatus: 'partial',
    total: net,
    paidTotal: net - pending,
    pendingTotal: pending,
    personNames: const {},
    orderType: 'dine_in',
    grossSubtotal: net,
    netTotal: net,
    businessDate: '2026-08-26',
    cashSessionId: 'cash-session',
    branchId: 'aviacion',
    branchName: 'Aviacion',
  );
}

Payment _payment({required double amount, required String type, String? id}) {
  return Payment(
    id: id ?? '$type-$amount',
    orderId: 'order',
    tableId: 'table-4',
    tableName: 'Mesa 4',
    type: type,
    method: 'cash',
    baseAmount: amount,
    surchargeRate: 0,
    surchargeAmount: 0,
    chargedAmount: amount,
    appliedAmount: amount,
    subtotalBeforeDiscount: amount,
    totalAfterDiscount: amount,
    status: 'active',
    cashSessionId: 'cash-session',
    businessDate: '2026-08-26',
  );
}

Map<String, Object?> _paymentData({
  required String method,
  required double amount,
  double? cashReceivedAmount,
  double? cashChangeAmount,
}) {
  return {
    'orderId': 'order',
    'tableId': 'table-4',
    'tableName': 'Mesa 4',
    'type': 'full_table',
    'paymentType': 'full_table',
    'method': method,
    'status': 'active',
    'subtotalBeforeDiscount': amount,
    'discountAmount': 0.0,
    'totalAfterDiscount': amount,
    'appliedAmount': amount,
    'baseAmount': amount,
    'amount': amount,
    'chargedAmount': amount,
    'cardFeeRate': method == 'card' ? TacoPosRepository.cardSurchargeRate : 0.0,
    'cardFeeAbsorbedAmount': method == 'card'
        ? amount * TacoPosRepository.cardSurchargeRate
        : 0.0,
    'cashReceivedAmount': ?cashReceivedAmount,
    'cashChangeAmount': ?cashChangeAmount,
  };
}
