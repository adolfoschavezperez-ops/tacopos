import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/employee_benefit_checkout.dart';
import 'package:tacopos/core/orders/order_payment_reconciliation.dart';
import 'package:tacopos/models/payment.dart';

void main() {
  group('employee benefit aggregate reconciliation', () {
    test('fixture real 325 con free meal 230 y 95 acumula descuento 325', () {
      final totals = reconcileOrderPayments(
        orderGrossTotal: 325,
        activePayments: const [
          PaymentSettlementInput(
            id: 'free-230',
            grossAmount: 230,
            monetaryAmount: 0,
            discountAmount: 230,
            discountType: employeeDailyMealDiscountType,
            discountName: employeeDailyMealDiscountName,
            discountPercent: 100,
          ),
          PaymentSettlementInput(
            id: 'free-95',
            grossAmount: 95,
            monetaryAmount: 0,
            discountAmount: 95,
            discountType: employeeDailyMealDiscountType,
            discountName: employeeDailyMealDiscountName,
            discountPercent: 100,
          ),
        ],
      );

      expect(totals.discountAmount, 325);
      expect(totals.totalLiquidated, 325);
      expect(totals.paidTotal, 325);
      expect(totals.pendingTotal, 0);
      expect(totals.monetaryPaid, 0);
      expect(totals.netTotal, 0);
      expect(totals.effectiveDiscountPercent, 100);
      expect(totals.paymentStatus, 'paid');
    });

    test('un solo free meal de 100 liquida con descuento total', () {
      final totals = reconcileOrderPayments(
        orderGrossTotal: 100,
        activePayments: const [
          PaymentSettlementInput(
            id: 'free-100',
            grossAmount: 100,
            monetaryAmount: 0,
            discountAmount: 100,
            discountType: employeeDailyMealDiscountType,
            discountPercent: 100,
          ),
        ],
      );

      expect(totals.discountAmount, 100);
      expect(totals.paidTotal, 100);
      expect(totals.pendingTotal, 0);
      expect(totals.netTotal, 0);
    });

    test(
      'free meal con payment historico stale reconstruye descuento total',
      () {
        final payment = _payment(
          id: 'free-stale-174',
          method: 'employee_consumption',
          baseAmount: 174,
          chargedAmount: 0,
          discountAmount: 94,
          totalAfterDiscount: 0,
          appliedDiscountPercent: 100,
          appliedDiscountType: employeeDailyMealDiscountType,
          appliedDiscountName: employeeDailyMealDiscountName,
        );
        final totals = reconcileOrderPayments(
          orderGrossTotal: 174,
          activePayments: [PaymentSettlementInput.fromPayment(payment)],
        );

        expect(totals.discountAmount, 174);
        expect(totals.monetaryPaid, 0);
        expect(totals.totalLiquidated, 174);
        expect(totals.paidTotal, 174);
        expect(totals.pendingTotal, 0);
        expect(totals.effectiveDiscountPercent, 100);
      },
    );

    test('free meal en cobro parcial conserva saldo pendiente', () {
      final totals = reconcileOrderPayments(
        orderGrossTotal: 325,
        activePayments: const [
          PaymentSettlementInput(
            id: 'free-230',
            grossAmount: 230,
            monetaryAmount: 0,
            discountAmount: 230,
            discountType: employeeDailyMealDiscountType,
            discountPercent: 100,
          ),
        ],
      );

      expect(totals.discountAmount, 230);
      expect(totals.paidTotal, 230);
      expect(totals.pendingTotal, 95);
      expect(totals.paymentStatus, 'partial');
    });

    test('free meal seguido de saldo adicional no reemplaza el acumulado', () {
      final totals = reconcileOrderPayments(
        orderGrossTotal: 325,
        activePayments: const [
          PaymentSettlementInput(
            id: 'free-230',
            grossAmount: 230,
            monetaryAmount: 0,
            discountAmount: 230,
            discountType: employeeDailyMealDiscountType,
            discountPercent: 100,
          ),
          PaymentSettlementInput(
            id: 'cash-95',
            grossAmount: 95,
            monetaryAmount: 95,
            discountAmount: 0,
          ),
        ],
      );

      expect(totals.discountAmount, 230);
      expect(totals.monetaryPaid, 95);
      expect(totals.paidTotal, 325);
      expect(totals.pendingTotal, 0);
    });

    test('dos pagos validos suman total liquidado', () {
      final totals = reconcileOrderPayments(
        orderGrossTotal: 325,
        activePayments: const [
          PaymentSettlementInput(
            id: 'cash-200',
            grossAmount: 200,
            monetaryAmount: 200,
            discountAmount: 0,
          ),
          PaymentSettlementInput(
            id: 'card-125',
            grossAmount: 125,
            monetaryAmount: 125,
            discountAmount: 0,
          ),
        ],
      );

      expect(totals.paidTotal, 325);
      expect(totals.monetaryPaid, 325);
      expect(totals.pendingTotal, 0);
    });

    test('ultimo pago no reemplaza descuento acumulado', () {
      final totals = reconcileOrderPayments(
        orderGrossTotal: 325,
        activePayments: const [
          PaymentSettlementInput(
            id: 'free-230',
            grossAmount: 230,
            monetaryAmount: 0,
            discountAmount: 230,
          ),
          PaymentSettlementInput(
            id: 'free-95',
            grossAmount: 95,
            monetaryAmount: 0,
            discountAmount: 95,
          ),
        ],
      );

      expect(totals.discountAmount, isNot(95));
      expect(totals.discountAmount, 325);
    });

    test('cancelacion de pago recalcula agregados con pagos restantes', () {
      final totals = reconcileOrderPayments(
        orderGrossTotal: 325,
        activePayments: const [
          PaymentSettlementInput(
            id: 'free-230',
            grossAmount: 230,
            monetaryAmount: 0,
            discountAmount: 230,
          ),
        ],
      );

      expect(totals.discountAmount, 230);
      expect(totals.paidTotal, 230);
      expect(totals.pendingTotal, 95);
    });

    test(
      'reintento con mismo pago activo no se modela como descuento nuevo',
      () {
        final totals = reconcileOrderPayments(
          orderGrossTotal: 230,
          activePayments: const [
            PaymentSettlementInput(
              id: 'free-230',
              grossAmount: 230,
              monetaryAmount: 0,
              discountAmount: 230,
            ),
          ],
        );

        expect(totals.discountAmount, 230);
        expect(totals.pendingTotal, 0);
      },
    );

    test('doble tap que no crea segundo pago no duplica beneficio', () {
      final payment = _payment(
        id: 'free-230',
        baseAmount: 230,
        chargedAmount: 0,
        discountAmount: 230,
      );
      final totals = reconcileOrderPayments(
        orderGrossTotal: 230,
        activePayments: [PaymentSettlementInput.fromPayment(payment)],
      );

      expect(totals.discountAmount, 230);
      expect(totals.paidTotal, 230);
    });

    test('items cancelados no entran al subtotal usado para conciliar', () {
      final activeItemsTotal = 325.0;
      final totals = reconcileOrderPayments(
        orderGrossTotal: activeItemsTotal,
        activePayments: const [
          PaymentSettlementInput(
            id: 'free-325',
            grossAmount: 325,
            monetaryAmount: 0,
            discountAmount: 325,
          ),
        ],
      );

      expect(totals.orderGrossTotal, 325);
      expect(totals.discountAmount, 325);
    });

    test('descuento normal 30 por ciento sigue correcto', () {
      final totals = reconcileOrderPayments(
        orderGrossTotal: 100,
        activePayments: const [
          PaymentSettlementInput(
            id: 'employee-30',
            grossAmount: 100,
            monetaryAmount: 70,
            discountAmount: 30,
            discountType: employeeRegularDiscountType,
            discountPercent: 30,
          ),
        ],
      );

      expect(totals.discountAmount, 30);
      expect(totals.monetaryPaid, 70);
      expect(totals.effectiveDiscountPercent, 30);
      expect(totals.netTotal, 70);
    });

    test('comida del dia sigue siendo 100 por ciento', () {
      final totals = reconcileOrderPayments(
        orderGrossTotal: 235.50,
        activePayments: const [
          PaymentSettlementInput(
            id: 'daily-meal',
            grossAmount: 235.50,
            monetaryAmount: 0,
            discountAmount: 235.50,
            discountType: employeeDailyMealDiscountType,
            discountPercent: 100,
          ),
        ],
      );

      expect(totals.discountAmount, 235.50);
      expect(totals.effectiveDiscountPercent, 100);
      expect(totals.netTotal, 0);
    });

    test('paidTotal y totalLiquidado quedan consistentes', () {
      final totals = reconcileOrderPayments(
        orderGrossTotal: 325,
        activePayments: const [
          PaymentSettlementInput(
            id: 'free-325',
            grossAmount: 325,
            monetaryAmount: 0,
            discountAmount: 325,
          ),
        ],
      );

      expect(totals.paidTotal, totals.totalLiquidated);
    });

    test('pago monetario cero mas descuento total cubre la orden', () {
      final totals = reconcileOrderPayments(
        orderGrossTotal: 325,
        activePayments: const [
          PaymentSettlementInput(
            id: 'free-325',
            grossAmount: 325,
            monetaryAmount: 0,
            discountAmount: 325,
          ),
        ],
      );

      expect(totals.monetaryPaid, 0);
      expect(totals.discountAmount + totals.monetaryPaid, 325);
    });

    test('no genera saldo negativo', () {
      final totals = reconcileOrderPayments(
        orderGrossTotal: 100,
        activePayments: const [
          PaymentSettlementInput(
            id: 'overpaid',
            grossAmount: 120,
            monetaryAmount: 120,
            discountAmount: 0,
          ),
        ],
      );

      expect(totals.paidTotal, 100);
      expect(totals.pendingTotal, 0);
    });

    test('no genera descuentos superiores al subtotal activo', () {
      final totals = reconcileOrderPayments(
        orderGrossTotal: 100,
        activePayments: const [
          PaymentSettlementInput(
            id: 'over-discount',
            grossAmount: 150,
            monetaryAmount: 0,
            discountAmount: 150,
          ),
        ],
      );

      expect(totals.discountAmount, 100);
      expect(totals.netTotal, 0);
    });
  });
}

Payment _payment({
  required String id,
  String method = 'employee_consumption',
  required double baseAmount,
  required double chargedAmount,
  required double discountAmount,
  double? totalAfterDiscount,
  double appliedDiscountPercent = 0,
  String? appliedDiscountType,
  String? appliedDiscountName,
}) {
  return Payment(
    id: id,
    orderId: 'order',
    tableId: 'table',
    tableName: 'Mesa 1',
    type: 'partial',
    method: method,
    baseAmount: baseAmount,
    surchargeRate: 0,
    surchargeAmount: 0,
    chargedAmount: chargedAmount,
    discountAmount: discountAmount,
    totalAfterDiscount: totalAfterDiscount ?? chargedAmount,
    appliedDiscountPercent: appliedDiscountPercent,
    appliedDiscountType: appliedDiscountType,
    appliedDiscountName: appliedDiscountName,
  );
}
