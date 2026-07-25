import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/canonical_sales_summary.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/payment.dart';

void main() {
  test('sin descuentos: venta bruta = venta neta = cobrado real', () {
    final summary = buildCanonicalSalesSummary([
      bundle(total: 100, payment: payment(base: 100, charged: 100)),
    ]);

    expect(summary.grossSales, 100);
    expect(summary.discountTotal, 0);
    expect(summary.netSales, 100);
    expect(summary.totalCollected, 100);
    expect(summary.reconciliationDifference, 0);
  });

  test('descuento 20%: bruto 100 descuento 20 neto 80 cobrado 80', () {
    final summary = buildCanonicalSalesSummary([
      bundle(
        total: 80,
        discountFields: const {'discountPercent': 20},
        payment: payment(base: 100, charged: 80, applied: 80),
      ),
    ]);

    expect(summary.grossSales, 100);
    expect(summary.discountTotal, 20);
    expect(summary.netSales, 80);
    expect(summary.totalCollected, 80);
  });

  test(
    'descuento 100%: bruto 100 descuento 100 neto 0 cobrado monetario 0',
    () {
      final summary = buildCanonicalSalesSummary([
        SalesOrderBundleInput(
          order: order(total: 0, fields: const {'discountPercent': 100}),
          items: [item(total: 100)],
          payments: const [],
        ),
      ]);

      expect(summary.grossSales, 100);
      expect(summary.discountTotal, 100);
      expect(summary.netSales, 0);
      expect(summary.totalCollected, 0);
    },
  );

  test('efectivo con cambio: neto 80 recibido 100 cambio 20 cobrado 80', () {
    final summary = buildCanonicalSalesSummary([
      bundle(
        total: 80,
        discountFields: const {'discountAmount': 20},
        payment: payment(
          method: 'cash',
          base: 100,
          charged: 80,
          received: 100,
          change: 20,
        ),
      ),
    ]);

    expect(summary.cashCollected, 80);
    expect(summary.totalCollected, 80);
    expect(summary.reconciliationDifference, 0);
  });

  test('tarjeta: comision separada y cobrado real 100', () {
    final summary = buildCanonicalSalesSummary([
      bundle(
        total: 100,
        payment: payment(
          method: 'card',
          base: 100,
          charged: 100,
          cardFee: 4.06,
        ),
      ),
    ]);

    expect(summary.cardCollected, 100);
    expect(summary.totalCollected, 100);
  });

  test('discrepancia real: bruto 110 sin descuento y pago inconsistente', () {
    final summary = buildCanonicalSalesSummary([
      bundle(total: 110, gross: 110, payment: payment(base: 88, charged: 88)),
    ]);

    expect(summary.grossSales, 110);
    expect(summary.discountTotal, 0);
    expect(summary.netSales, 110);
    expect(summary.totalCollected, 88);
    expect(summary.hasReconciliationDifference, isTrue);
    expect(summary.integrityIssues.single.message, contains('auditoria'));
  });
}

SalesOrderBundleInput bundle({
  required double total,
  double gross = 100,
  Map<String, double> discountFields = const {},
  required Payment payment,
}) {
  return SalesOrderBundleInput(
    order: order(total: total, fields: discountFields),
    items: [item(total: gross)],
    payments: [payment],
  );
}

PosOrder order({required double total, Map<String, double> fields = const {}}) {
  return PosOrder(
    id: 'order-$total',
    tableId: 't1',
    tableName: 'Mesa 1',
    status: 'paid',
    kitchenStatus: 'ready',
    paymentStatus: 'paid',
    total: total,
    paidTotal: total,
    pendingTotal: 0,
    personNames: const {},
    orderType: 'dine_in',
    explicitDiscountFields: fields,
  );
}

OrderItem item({required double total}) {
  return OrderItem(
    id: 'item-$total',
    personNumber: 1,
    personName: 'Persona 1',
    productId: 'p1',
    productName: 'Taco',
    category: 'Tacos',
    qty: 1,
    unitPrice: total,
    total: total,
    notes: '',
    sendToKitchen: true,
    kitchenStatus: 'ready',
    paymentStatus: 'paid',
  );
}

Payment payment({
  String method = 'cash',
  required double base,
  required double charged,
  double? applied,
  double? received,
  double? change,
  double cardFee = 0,
}) {
  return Payment(
    id: 'payment-$base-$charged',
    orderId: 'order',
    tableId: 't1',
    tableName: 'Mesa 1',
    type: 'full_table',
    method: method,
    baseAmount: base,
    surchargeRate: 0,
    surchargeAmount: 0,
    chargedAmount: charged,
    appliedAmount: applied,
    cashReceivedAmount: received,
    cashChangeAmount: change,
    cardFeeAbsorbedAmount: cardFee,
  );
}
