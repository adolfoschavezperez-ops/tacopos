import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/sales_discrepancy_audit.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/payment.dart';

void main() {
  group('sales discrepancy audit', () {
    test('does not flag a correct pending order', () {
      final result = auditSalesIntegrity(
        _order(
          status: 'open',
          kitchenStatus: 'cooking',
          paymentStatus: 'pending',
          total: 160,
          paidTotal: 0,
          pendingTotal: 160,
        ),
        [_item(total: 160)],
        const [],
      );

      expect(result.hasDiscrepancy, isFalse);
    });

    test('does not flag a correct partial order', () {
      final result = auditSalesIntegrity(
        _order(
          status: 'open',
          paymentStatus: 'partial',
          total: 200,
          paidTotal: 80,
          pendingTotal: 120,
        ),
        [_item(total: 200)],
        [_payment(baseAmount: 80)],
      );

      expect(result.hasDiscrepancy, isFalse);
    });

    test('does not flag a paid order with a real discount', () {
      final result = auditSalesIntegrity(
        _order(total: 88, paidTotal: 88, explicitDiscount: 22),
        [_item(total: 110)],
        [_payment(baseAmount: 88, received: 110, change: 22)],
      );

      expect(result.explicitDiscountTotal, 22);
      expect(result.expectedOrderTotal, 88);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('uses payment discount fields as the applied amount source', () {
      final result = auditSalesIntegrity(
        _order(total: 88, paidTotal: 88),
        [_item(total: 110)],
        [
          _payment(
            baseAmount: 110,
            chargedAmount: 88,
            received: 110,
            change: 22,
            discountAmount: 22,
            totalAfterDiscount: 88,
          ),
        ],
      );

      expect(result.explicitDiscountTotal, 22);
      expect(result.paymentsAppliedTotal, 88);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('flags a paid order with missing discount', () {
      final result = auditSalesIntegrity(
        _order(id: 'Z7nGWf', total: 88, paidTotal: 88),
        [_item(total: 110)],
        [_payment(baseAmount: 88, received: 110, change: 22)],
      );

      expect(result.hasDiscrepancy, isTrue);
      expect(result.failedCodes, contains('items_order'));
      expect(result.failedCodes, contains('discount_inconsistent'));
      expect(result.diffItemsOrder, -22);
    });

    test('does not flag correct cash received and change', () {
      final result = auditSalesIntegrity(
        _order(total: 88, paidTotal: 88),
        [_item(total: 88)],
        [_payment(baseAmount: 88, received: 110, change: 22)],
      );

      expect(result.failedCodes, isNot(contains('cash_net')));
      expect(result.hasDiscrepancy, isFalse);
    });

    test('flags incorrect cash received and change', () {
      final result = auditSalesIntegrity(
        _order(total: 110, paidTotal: 110),
        [_item(total: 110)],
        [_payment(baseAmount: 110, received: 110, change: 22)],
      );

      expect(result.hasDiscrepancy, isTrue);
      expect(result.failedCodes, contains('cash_net'));
    });
  });
}

PosOrder _order({
  String id = 'order',
  String status = 'paid',
  String kitchenStatus = 'ready',
  String paymentStatus = 'paid',
  double total = 0,
  double paidTotal = 0,
  double pendingTotal = 0,
  double explicitDiscount = 0,
}) {
  return PosOrder(
    id: id,
    tableId: 'table',
    tableName: 'Mesa 1',
    status: status,
    kitchenStatus: kitchenStatus,
    paymentStatus: paymentStatus,
    total: total,
    paidTotal: paidTotal,
    pendingTotal: pendingTotal,
    personNames: const {},
    orderType: 'dine_in',
    explicitDiscount: explicitDiscount,
    explicitDiscountFields: explicitDiscount > 0
        ? {'discountAmount': explicitDiscount}
        : const {},
    paidAt: paymentStatus == 'paid' ? DateTime(2026) : null,
  );
}

OrderItem _item({
  String id = 'item',
  double total = 0,
  String status = 'active',
  String kitchenStatus = 'ready',
  String cancelStatus = 'none',
}) {
  return OrderItem(
    id: id,
    personNumber: 1,
    personName: 'Persona 1',
    productId: 'product',
    productName: 'Producto',
    category: 'General',
    qty: 1,
    unitPrice: total,
    total: total,
    notes: '',
    sendToKitchen: true,
    kitchenStatus: kitchenStatus,
    paymentStatus: 'pending',
    status: status,
    cancelStatus: cancelStatus,
  );
}

Payment _payment({
  String id = 'payment',
  String method = 'cash',
  double baseAmount = 0,
  double chargedAmount = 0,
  double? received,
  double? change,
  double discountAmount = 0,
  double totalAfterDiscount = 0,
  DateTime? createdAt,
}) {
  return Payment(
    id: id,
    orderId: 'order',
    tableId: 'table',
    tableName: 'Mesa 1',
    type: 'full_table',
    method: method,
    baseAmount: baseAmount,
    surchargeRate: 0,
    surchargeAmount: 0,
    chargedAmount: chargedAmount == 0 ? baseAmount : chargedAmount,
    cashReceivedAmount: received,
    cashChangeAmount: change,
    discountAmount: discountAmount,
    totalAfterDiscount: totalAfterDiscount,
    createdAt: createdAt,
  );
}
