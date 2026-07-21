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
        _order(total: 110, paidTotal: 110, explicitDiscount: 22),
        [_item(total: 110)],
        [_payment(baseAmount: 88, received: 110, change: 22)],
      );

      expect(result.monetaryDiscountApplied, 22);
      expect(result.netCustomerDue, 88);
      expect(result.settledTotal, 110);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('uses payment discount fields as the applied amount source', () {
      final result = auditSalesIntegrity(
        _order(total: 110, paidTotal: 110),
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

      expect(result.monetaryDiscountApplied, 22);
      expect(result.moneyPaymentsApplied, 88);
      expect(result.settledTotal, 110);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('does not flag a correct 20 percent discount settlement', () {
      final result = auditSalesIntegrity(
        _order(total: 309, paidTotal: 309),
        [_item(total: 309)],
        [
          _payment(
            baseAmount: 309,
            chargedAmount: 247.20,
            received: 247.20,
            change: 0,
            discountAmount: 61.80,
            totalAfterDiscount: 247.20,
            appliedDiscountPercent: 20,
          ),
        ],
      );

      expect(result.monetaryDiscountApplied, 61.80);
      expect(result.moneyPaymentsApplied, 247.20);
      expect(result.settledTotal, 309);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('does not flag a correct 50 percent discount settlement', () {
      final result = auditSalesIntegrity(
        _order(total: 148, paidTotal: 148),
        [_item(total: 148)],
        [
          _payment(
            baseAmount: 148,
            chargedAmount: 74,
            received: 74,
            change: 0,
            discountAmount: 74,
            totalAfterDiscount: 74,
            appliedDiscountPercent: 50,
          ),
        ],
      );

      expect(result.monetaryDiscountApplied, 74);
      expect(result.moneyPaymentsApplied, 74);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('does not flag a correct 30 percent discount settlement', () {
      final result = auditSalesIntegrity(
        _order(total: 113, paidTotal: 113),
        [_item(total: 113)],
        [
          _payment(
            baseAmount: 113,
            chargedAmount: 79.10,
            received: 79.10,
            change: 0,
            discountAmount: 33.90,
            totalAfterDiscount: 79.10,
            appliedDiscountPercent: 30,
          ),
        ],
      );

      expect(result.monetaryDiscountApplied, 33.90);
      expect(result.moneyPaymentsApplied, 79.10);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('calculates a monetary discount from percent only when needed', () {
      final result = auditSalesIntegrity(
        _order(total: 200, paidTotal: 200),
        [_item(total: 200)],
        [
          _payment(
            baseAmount: 200,
            chargedAmount: 160,
            received: 160,
            change: 0,
            totalAfterDiscount: 160,
            appliedDiscountPercent: 0.20,
          ),
        ],
      );

      expect(result.monetaryDiscountApplied, 40);
      expect(result.settledTotal, 200);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('flags a paid order with missing discount', () {
      final result = auditSalesIntegrity(
        _order(id: 'Z7nGWf', total: 88, paidTotal: 88),
        [_item(total: 110)],
        [_payment(baseAmount: 110, received: 110, change: 22)],
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
  double appliedDiscountPercent = 0,
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
    appliedDiscountPercent: appliedDiscountPercent,
    createdAt: createdAt,
  );
}
