import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/order_payment_reconciliation.dart';

void main() {
  final cases =
      (jsonDecode(
                File(
                  'test/fixtures/local_capture_finance_cases.json',
                ).readAsStringSync(),
              )
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  for (final testCase in cases) {
    test('canonical Dart aggregate: ${testCase['name']}', () {
      final itemTotals = (testCase['itemTotals'] as List<dynamic>)
          .cast<num>()
          .map((value) => value.toDouble());
      final grossTotal = itemTotals.fold<double>(
        0,
        (sum, value) => sum + value,
      );
      final payments = (testCase['payments'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final active = <PaymentSettlementInput>[];
      for (var index = 0; index < payments.length; index++) {
        final data = payments[index];
        final entry = PaymentSettlementInput.fromPaymentData('$index', data);
        final status = '${data['status'] ?? 'active'}'.trim().toLowerCase();
        if (!const {
              'cancelled',
              'canceled',
              'cancelado',
              'cancelada',
              'voided',
              'anulado',
              'anulada',
            }.contains(status) &&
            data['cancelledAt'] == null &&
            (entry.monetaryAmount > 0 ||
                entry.discountAmount > 0 ||
                entry.grossAmount > 0)) {
          active.add(entry);
        }
      }
      final totals = reconcileOrderPayments(
        orderGrossTotal: grossTotal,
        activePayments: active,
      );
      final expected = testCase['expected'] as Map<String, dynamic>;
      expect(totals.orderGrossTotal, expected['total']);
      expect(totals.orderGrossTotal, expected['grossSubtotal']);
      expect(totals.netTotal, expected['netTotal']);
      expect(totals.discountAmount, expected['discountAmount']);
      expect(totals.totalLiquidated, expected['totalLiquidated']);
      expect(totals.paidTotal, expected['paidTotal']);
      expect(totals.pendingTotal, expected['pendingTotal']);
      expect(totals.paymentStatus, expected['paymentStatus']);
    });
  }
}
