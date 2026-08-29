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

    test('legacy gross employee payment is not a discrepancy', () {
      final result = auditSalesIntegrity(
        _order(
          total: 290,
          paidTotal: 290,
          explicitDiscount: 87,
          discountPercent: 30,
        ),
        [_item(total: 290)],
        [
          _payment(
            id: 'legacy-employee',
            baseAmount: 290,
            chargedAmount: 290,
            appliedAmount: 290,
            received: 203,
            change: 0,
            appliedDiscountPercent: 30,
            appliedDiscountType: 'employee_30',
            orderGrossSubtotal: 290,
            orderNetTotal: 203,
          ),
        ],
      );

      expect(result.moneyPaymentsApplied, 203);
      expect(result.monetaryDiscountApplied, 87);
      expect(result.settledTotal, 290);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('legacy gross partner payment is not a discrepancy', () {
      final result = auditSalesIntegrity(
        _order(
          total: 374,
          paidTotal: 374,
          explicitDiscount: 187,
          discountPercent: 50,
        ),
        [_item(total: 374)],
        [
          _payment(
            id: 'legacy-partner',
            method: 'card',
            baseAmount: 374,
            chargedAmount: 374,
            appliedAmount: 374,
            appliedDiscountPercent: 50,
            appliedDiscountType: 'partner_50',
            orderGrossSubtotal: 374,
            orderNetTotal: 187,
          ),
        ],
      );

      expect(result.moneyPaymentsApplied, 187);
      expect(result.monetaryDiscountApplied, 187);
      expect(result.settledTotal, 374);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('does not flag a correct 100 percent discount settlement', () {
      final result = auditSalesIntegrity(
        _order(total: 80, paidTotal: 80),
        [_item(total: 80)],
        [
          _payment(
            baseAmount: 80,
            chargedAmount: 0,
            received: 0,
            change: 0,
            discountAmount: 80,
            totalAfterDiscount: 0,
            appliedDiscountPercent: 100,
            appliedDiscountType: 'courtesy',
            appliedDiscountName: 'Cortesia gerencia',
          ),
        ],
      );

      expect(result.monetaryDiscountApplied, 80);
      expect(result.moneyPaymentsApplied, 0);
      expect(result.settledTotal, 80);
      expect(result.discountPercentNormalized, 1);
      expect(result.discountTypeLabel, 'Cortesia');
      expect(result.hasDiscrepancy, isFalse);
    });

    test('reconstruye caso historico 325 con free meal 230 y 95', () {
      final result = auditSalesIntegrity(
        _order(
          id: 'Z7nGWf',
          total: 325,
          paidTotal: 325,
          pendingTotal: 0,
          explicitDiscount: 95,
          discountPercent: 100,
        ),
        [
          _item(id: 'active-1', total: 230),
          _item(id: 'active-2', total: 95),
          _item(id: 'cancelled-1', total: 66, status: 'cancelled'),
        ],
        [
          _payment(
            id: 'free-230',
            method: 'employee_consumption',
            baseAmount: 230,
            chargedAmount: 0,
            received: 0,
            change: 0,
            discountAmount: 230,
            totalAfterDiscount: 0,
            appliedDiscountPercent: 100,
            appliedDiscountType: 'employee_free_meal',
            appliedDiscountName: 'Employee free meal',
          ),
          _payment(
            id: 'free-95',
            method: 'employee_consumption',
            baseAmount: 95,
            chargedAmount: 0,
            received: 0,
            change: 0,
            discountAmount: 95,
            totalAfterDiscount: 0,
            appliedDiscountPercent: 100,
            appliedDiscountType: 'employee_free_meal',
            appliedDiscountName: 'Employee free meal',
          ),
        ],
      );

      expect(result.storedOrderDiscount, 95);
      expect(result.reconstructedPaymentDiscount, 325);
      expect(result.historicalDiscountDifference, 230);
      expect(result.monetaryDiscountApplied, 325);
      expect(result.discountPercentNormalized, 1);
      expect(result.netCustomerDue, 0);
      expect(result.moneyPaymentsApplied, 0);
      expect(result.settledTotal, 325);
      expect(result.diffPaidTotal, 0);
      expect(result.diffPendingTotal, 0);
      expect(result.failedCodes, contains('historical_discount_aggregate'));
      expect(result.hasHistoricalDiscountAggregateMismatch, isTrue);
      expect(result.failedCodes, isNot(contains('payments_order')));
      expect(result.failedCodes, isNot(contains('paid_total')));
      expect(result.failedCodes, isNot(contains('pending_total')));
    });

    test('reconstruye free meal con discountAmount historico stale', () {
      final result = auditSalesIntegrity(
        _order(
          total: 174,
          paidTotal: 174,
          pendingTotal: 0,
          explicitDiscount: 94,
        ),
        [_item(total: 174)],
        [
          _payment(
            method: 'employee_consumption',
            baseAmount: 174,
            chargedAmount: 0,
            received: 0,
            change: 0,
            discountAmount: 94,
            totalAfterDiscount: 0,
            appliedDiscountPercent: 100,
            appliedDiscountType: 'employee_free_meal',
            appliedDiscountName: 'Comida empleado del dia',
          ),
        ],
      );

      expect(result.storedOrderDiscount, 94);
      expect(result.reconstructedPaymentDiscount, 174);
      expect(result.monetaryDiscountApplied, 174);
      expect(result.discountPercentNormalized, 1);
      expect(result.moneyPaymentsApplied, 0);
      expect(result.settledTotal, 174);
      expect(result.expectedPendingTotal, 0);
      expect(result.diffSettlement, 0);
      expect(result.diffPaidTotal, 0);
      expect(result.diffPendingTotal, 0);
      expect(result.discountTypeLabel, 'Comida empleado');
      expect(result.failedCodes, contains('historical_discount_aggregate'));
      expect(result.failedCodes, isNot(contains('payments_order')));
    });

    test('cinco free meal historicos suman descuento canonico completo', () {
      final cases = [
        (gross: 174.0, stored: 94.0),
        (gross: 325.0, stored: 95.0),
        (gross: 168.0, stored: 95.0),
        (gross: 168.0, stored: 66.0),
        (gross: 176.0, stored: 88.0),
      ];
      final results = [
        for (final entry in cases)
          auditSalesIntegrity(
            _order(
              total: entry.gross,
              paidTotal: entry.gross,
              pendingTotal: 0,
              explicitDiscount: entry.stored,
            ),
            [_item(total: entry.gross)],
            [
              _payment(
                method: 'employee_consumption',
                baseAmount: entry.gross,
                chargedAmount: 0,
                received: 0,
                change: 0,
                discountAmount: entry.stored,
                totalAfterDiscount: 0,
                appliedDiscountPercent: 100,
                appliedDiscountType: 'employee_free_meal',
                appliedDiscountName: 'Comida empleado del dia',
              ),
            ],
          ),
      ];

      expect(
        results.fold<double>(0, (sum, result) => sum + result.grossItemsTotal),
        1011,
      );
      expect(
        results.fold<double>(
          0,
          (sum, result) => sum + result.monetaryDiscountApplied,
        ),
        1011,
      );
      expect(
        results.fold<double>(
          0,
          (sum, result) => sum + result.moneyPaymentsApplied,
        ),
        0,
      );
      expect(
        results.fold<double>(0, (sum, result) => sum + result.settledTotal),
        1011,
      );
      expect(
        results.fold<double>(
          0,
          (sum, result) => sum + result.expectedPendingTotal,
        ),
        0,
      );
      for (final result in results) {
        expect(result.discountPercentNormalized, 1);
        expect(result.discountTypeLabel, 'Comida empleado');
        expect(result.failedCodes, contains('historical_discount_aggregate'));
        expect(result.failedCodes, isNot(contains('payments_order')));
        expect(result.failedCodes, isNot(contains('paid_total')));
        expect(result.failedCodes, isNot(contains('pending_total')));
      }
    });

    test('employee 30 permanece en 30 porciento', () {
      final result = auditSalesIntegrity(
        _order(
          total: 100,
          paidTotal: 100,
          pendingTotal: 0,
          explicitDiscount: 30,
          discountPercent: 30,
        ),
        [_item(total: 100)],
        [
          _payment(
            method: 'cash',
            baseAmount: 100,
            chargedAmount: 70,
            received: 70,
            change: 0,
            discountAmount: 30,
            totalAfterDiscount: 70,
            appliedDiscountPercent: 30,
            appliedDiscountType: 'employee_30',
            appliedDiscountName: 'Descuento empleado 30%',
          ),
        ],
      );

      expect(result.monetaryDiscountApplied, 30);
      expect(result.discountPercentNormalized, 0.3);
      expect(result.moneyPaymentsApplied, 70);
      expect(result.settledTotal, 100);
      expect(result.discountTypeLabel, 'Empleado 30%');
      expect(result.hasDiscrepancy, isFalse);
    });

    test('maps discount type labels from payment metadata', () {
      final result = auditSalesIntegrity(
        _order(total: 100, paidTotal: 100),
        [_item(total: 100)],
        [
          _payment(
            baseAmount: 100,
            chargedAmount: 50,
            received: 50,
            change: 0,
            discountAmount: 50,
            totalAfterDiscount: 50,
            appliedDiscountPercent: 50,
            appliedDiscountType: 'friends_family',
            appliedDiscountName: 'Familia',
            discountReason: 'Autorizado',
          ),
        ],
      );

      expect(result.discountTypeLabel, 'Amigos/Familia');
      expect(result.discountName, 'Familia');
      expect(result.discountReason, 'Autorizado');
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

    test('simple cash sale reconciles without differences', () {
      final result = auditSalesIntegrity(
        _order(total: 100, paidTotal: 100),
        [_item(total: 100)],
        [_payment(baseAmount: 100, received: 100, change: 0)],
      );

      expect(result.cashPaid, 100);
      expect(result.cardPaid, 0);
      expect(result.settledTotal, 100);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('simple card sale reconciles as sale amount, not extra income', () {
      final result = auditSalesIntegrity(
        _order(total: 100, paidTotal: 100),
        [_item(total: 100)],
        [_payment(method: 'card', baseAmount: 100, chargedAmount: 100)],
      );

      expect(result.cardPaid, 100);
      expect(result.moneyPaymentsApplied, 100);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('card fee does not inflate sale liquidation', () {
      final result = auditSalesIntegrity(
        _order(total: 100, paidTotal: 100),
        [_item(total: 100)],
        [
          _payment(
            method: 'card',
            baseAmount: 100,
            chargedAmount: 104,
            cardFee: 4,
          ),
        ],
      );

      expect(result.cardPaid, 100);
      expect(result.cardFeeTotal, 4);
      expect(result.settledTotal, 100);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('cash and card mixed payment reconciles', () {
      final result = auditSalesIntegrity(
        _order(total: 200, paidTotal: 200),
        [_item(total: 200)],
        [
          _payment(id: 'cash-1', baseAmount: 80, received: 100, change: 20),
          _payment(id: 'card-1', method: 'card', baseAmount: 120),
        ],
      );

      expect(result.cashPaid, 80);
      expect(result.cardPaid, 120);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('tip is reported but does not liquidate sale items', () {
      final result = auditSalesIntegrity(
        _order(total: 100, paidTotal: 100),
        [_item(total: 100)],
        [
          _payment(
            baseAmount: 100,
            chargedAmount: 120,
            received: 120,
            change: 0,
            tip: 20,
          ),
        ],
      );

      expect(result.tipTotal, 20);
      expect(result.moneyPaymentsApplied, 100);
      expect(result.settledTotal, 100);
      expect(result.failedCodes, isNot(contains('payments_order')));
    });

    test('card with tip separates sale and tip', () {
      final result = auditSalesIntegrity(
        _order(total: 100, paidTotal: 100),
        [_item(total: 100)],
        [
          _payment(
            method: 'card',
            baseAmount: 100,
            chargedAmount: 120,
            tip: 20,
          ),
        ],
      );

      expect(result.cardPaid, 100);
      expect(result.tipTotal, 20);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('employee 30 percent discount has net revenue 70', () {
      final result = auditSalesIntegrity(
        _order(total: 100, paidTotal: 100),
        [_item(total: 100)],
        [
          _payment(
            baseAmount: 100,
            chargedAmount: 70,
            discountAmount: 30,
            totalAfterDiscount: 70,
            appliedDiscountPercent: 30,
            appliedDiscountType: 'employee',
          ),
        ],
      );

      expect(result.moneyPaymentsApplied, 70);
      expect(result.monetaryDiscountApplied, 30);
      expect(result.netCustomerDue, 70);
      expect(result.settledTotal, 100);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('employee free meal 100 percent has zero monetary revenue', () {
      final result = auditSalesIntegrity(
        _order(total: 100, paidTotal: 100),
        [_item(total: 100)],
        [
          _payment(
            method: 'employee_consumption',
            baseAmount: 100,
            chargedAmount: 0,
            discountAmount: 100,
            totalAfterDiscount: 0,
            appliedDiscountPercent: 100,
            appliedDiscountType: 'employee_free_meal',
          ),
        ],
      );

      expect(result.moneyPaymentsApplied, 0);
      expect(result.monetaryDiscountApplied, 100);
      expect(result.netCustomerDue, 0);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('cash plus discount reconciles', () {
      final result = auditSalesIntegrity(
        _order(total: 100, paidTotal: 100),
        [_item(total: 100)],
        [
          _payment(
            baseAmount: 100,
            chargedAmount: 80,
            received: 80,
            change: 0,
            discountAmount: 20,
            totalAfterDiscount: 80,
          ),
        ],
      );

      expect(result.cashPaid, 80);
      expect(result.monetaryDiscountApplied, 20);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('card plus discount reconciles', () {
      final result = auditSalesIntegrity(
        _order(total: 100, paidTotal: 100),
        [_item(total: 100)],
        [
          _payment(
            method: 'card',
            baseAmount: 100,
            chargedAmount: 75,
            discountAmount: 25,
            totalAfterDiscount: 75,
          ),
        ],
      );

      expect(result.cardPaid, 75);
      expect(result.monetaryDiscountApplied, 25);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('two partial payments keep pending consistent', () {
      final result = auditSalesIntegrity(
        _order(
          status: 'open',
          paymentStatus: 'partial',
          total: 300,
          paidTotal: 200,
          pendingTotal: 100,
        ),
        [_item(total: 300)],
        [
          _payment(id: 'p1', baseAmount: 100),
          _payment(id: 'p2', method: 'card', baseAmount: 100),
        ],
      );

      expect(result.settledTotal, 200);
      expect(result.expectedPendingTotal, 100);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('three partial payments can close an order', () {
      final result = auditSalesIntegrity(
        _order(total: 300, paidTotal: 300),
        [_item(total: 300)],
        [
          _payment(id: 'p1', baseAmount: 100),
          _payment(id: 'p2', method: 'card', baseAmount: 100),
          _payment(id: 'p3', baseAmount: 100),
        ],
      );

      expect(result.moneyPaymentsApplied, 300);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('cancelled payment is excluded from liquidation', () {
      final result = auditSalesIntegrity(
        _order(total: 100, paidTotal: 100),
        [_item(total: 100)],
        [
          _payment(id: 'active', baseAmount: 100),
          _payment(id: 'cancelled', baseAmount: 100, status: 'cancelled'),
        ],
      );

      expect(result.activePayments.map((payment) => payment.id), ['active']);
      expect(result.moneyPaymentsApplied, 100);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('cancelled item does not inflate active total', () {
      final result = auditSalesIntegrity(
        _order(total: 100, paidTotal: 100),
        [
          _item(id: 'active', total: 100),
          _item(id: 'cancelled', total: 50, status: 'cancelled'),
        ],
        [_payment(baseAmount: 100)],
      );

      expect(result.grossItemsTotal, 100);
      expect(result.cancelledItems.length, 1);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('cancellation after payment is shown as over liquidation', () {
      final result = auditSalesIntegrity(
        _order(total: 150, paidTotal: 150),
        [
          _item(id: 'active', total: 150),
          _item(id: 'cancelled', total: 50, status: 'cancelled'),
        ],
        [_payment(baseAmount: 200, chargedAmount: 200)],
      );

      expect(result.overLiquidatedTotal, 50);
      expect(result.failedCodes, contains('cancellation_after_payment'));
      expect(
        result.discrepancies
            .singleWhere((entry) => entry.code == 'cancellation_after_payment')
            .label,
        'CANCELLATION_AFTER_PAYMENT',
      );
    });

    test('paidTotal represents liquidated amount, not extra money', () {
      final result = auditSalesIntegrity(
        _order(total: 100, paidTotal: 100),
        [_item(total: 100)],
        [
          _payment(
            method: 'card',
            baseAmount: 100,
            chargedAmount: 104,
            cardFee: 4,
          ),
        ],
      );

      expect(result.diffPaidTotal, 0);
      expect(result.moneyPaymentsApplied, 100);
    });

    test('payment amount is not treated as money for free meal', () {
      final payment = _payment(
        method: 'employee_consumption',
        baseAmount: 230,
        chargedAmount: 0,
        discountAmount: 230,
        totalAfterDiscount: 0,
      );
      final result = auditSalesIntegrity(
        _order(total: 230, paidTotal: 230),
        [_item(total: 230)],
        [payment],
      );

      expect(payment.amount, 230);
      expect(result.moneyPaymentsApplied, 0);
      expect(result.settledTotal, 230);
      expect(result.hasDiscrepancy, isFalse);
    });

    test('header stale is classified but does not create cash difference', () {
      final result = auditSalesIntegrity(
        _order(total: 325, paidTotal: 325, explicitDiscount: 95),
        [_item(total: 325)],
        [
          _payment(
            id: 'free-230',
            method: 'employee_consumption',
            baseAmount: 230,
            chargedAmount: 0,
            discountAmount: 230,
            totalAfterDiscount: 0,
          ),
          _payment(
            id: 'free-95',
            method: 'employee_consumption',
            baseAmount: 95,
            chargedAmount: 0,
            discountAmount: 95,
            totalAfterDiscount: 0,
          ),
        ],
      );

      expect(result.moneyPaymentsApplied, 0);
      expect(result.settledTotal, 325);
      expect(result.failedCodes, contains('historical_discount_aggregate'));
      expect(result.failedCodes, isNot(contains('payments_order')));
    });

    test('does not double count header discount and payment discounts', () {
      final result = auditSalesIntegrity(
        _order(total: 200, paidTotal: 200, explicitDiscount: 20),
        [_item(total: 200)],
        [
          _payment(
            baseAmount: 200,
            chargedAmount: 160,
            discountAmount: 40,
            totalAfterDiscount: 160,
          ),
        ],
      );

      expect(result.monetaryDiscountApplied, 40);
      expect(result.settledTotal, 200);
      expect(result.hasDiscrepancy, isTrue);
      expect(result.failedCodes, contains('historical_discount_aggregate'));
      expect(result.failedCodes, isNot(contains('payments_order')));
    });

    test(
      'does not emit NaN or Infinity with invalid numeric-looking inputs',
      () {
        final result = auditSalesIntegrity(
          _order(total: 0, paidTotal: 0),
          [_item(total: 0)],
          [_payment(baseAmount: 0, chargedAmount: 0)],
        );

        for (final value in [
          result.grossItemsTotal,
          result.moneyPaymentsApplied,
          result.monetaryDiscountApplied,
          result.settledTotal,
          result.expectedPendingTotal,
          result.primarySafeDifferenceForTest,
        ]) {
          expect(value.isNaN, isFalse);
          expect(value.isInfinite, isFalse);
        }
      },
    );
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
  double? discountPercent,
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
    explicitDiscountFields: _discountFields(explicitDiscount, discountPercent),
    paidAt: paymentStatus == 'paid' ? DateTime(2026) : null,
  );
}

Map<String, double> _discountFields(
  double explicitDiscount,
  double? discountPercent,
) {
  if (explicitDiscount <= 0) return const {};
  final fields = {
    'totalDiscountAmount': explicitDiscount,
    'discountAmount': explicitDiscount,
  };
  if (discountPercent != null) {
    fields['discountPercent'] = discountPercent;
  }
  return fields;
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
  double? chargedAmount,
  double? received,
  double? change,
  double discountAmount = 0,
  double totalAfterDiscount = 0,
  double appliedDiscountPercent = 0,
  double cardFee = 0,
  double tip = 0,
  String? appliedDiscountType,
  String? appliedDiscountName,
  String? discountReason,
  String status = 'active',
  DateTime? createdAt,
  double? appliedAmount,
  double orderGrossSubtotal = 0,
  double orderNetTotal = 0,
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
    chargedAmount: chargedAmount ?? baseAmount,
    appliedAmount: appliedAmount,
    cardFeeAbsorbedAmount: cardFee,
    cashReceivedAmount: received,
    cashChangeAmount: change,
    tipAmount: tip,
    discountAmount: discountAmount,
    totalAfterDiscount: totalAfterDiscount,
    appliedDiscountPercent: appliedDiscountPercent,
    appliedDiscountType: appliedDiscountType,
    orderGrossSubtotal: orderGrossSubtotal,
    orderNetTotal: orderNetTotal,
    appliedDiscountName: appliedDiscountName,
    discountReason: discountReason,
    status: status,
    createdAt: createdAt,
  );
}

extension on SalesAuditResult {
  double get primarySafeDifferenceForTest {
    if (diffItemsOrder.abs() > salesAuditMoneyTolerance) return diffItemsOrder;
    if (diffSettlement.abs() > salesAuditMoneyTolerance) return diffSettlement;
    if (diffPaidTotal.abs() > salesAuditMoneyTolerance) return diffPaidTotal;
    if (diffPendingTotal.abs() > salesAuditMoneyTolerance) {
      return diffPendingTotal;
    }
    return 0;
  }
}
