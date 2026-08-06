import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/canonical_sales_summary.dart';
import 'package:tacopos/core/reports/hourly_sales_comparison.dart';
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

  test('comida del dia al 100 no genera ingreso de consumo empleado', () {
    final summary = buildCanonicalSalesSummary([
      bundle(
        total: 0,
        discountFields: const {'discountAmount': 100, 'discountPercent': 100},
        payment: payment(
          method: 'employee_consumption',
          base: 100,
          charged: 0,
          discountAmount: 100,
          applied: 0,
        ),
      ),
    ]);

    expect(summary.grossSales, 100);
    expect(summary.discountTotal, 100);
    expect(summary.netSales, 0);
    expect(summary.employeeConsumption, 0);
    expect(summary.totalCollected, 0);
  });

  test('descuento empleado 30 cobra solo el neto', () {
    final summary = buildCanonicalSalesSummary([
      bundle(
        total: 70,
        discountFields: const {'discountAmount': 30, 'discountPercent': 30},
        payment: payment(
          method: 'employee_consumption',
          base: 100,
          charged: 70,
          discountAmount: 30,
          applied: 70,
        ),
      ),
    ]);

    expect(summary.grossSales, 100);
    expect(summary.discountTotal, 30);
    expect(summary.netSales, 70);
    expect(summary.employeeConsumption, 70);
    expect(summary.totalCollected, 70);
  });

  test('pago historico con descuento 100 y charged cero no cae al bruto', () {
    final summary = buildCanonicalSalesSummary([
      bundle(
        total: 0,
        discountFields: const {'discountAmount': 100},
        payment: payment(
          method: 'employee_consumption',
          base: 100,
          charged: 0,
          discountAmount: 100,
        ),
      ),
    ]);

    expect(summary.employeeConsumption, 0);
    expect(summary.totalCollected, 0);
  });

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

  test('pago despues de medianoche pertenece al businessDate de la orden', () {
    final orderDate = order(
      total: 91,
      businessDate: '2026-07-24',
      createdAt: DateTime(2026, 7, 24, 23, 40),
    );
    final latePayment = payment(
      base: 91,
      charged: 91,
      createdAt: DateTime(2026, 7, 25, 0, 10),
    );

    expect(
      resolveOperationalBusinessDate(order: orderDate, payment: latePayment),
      '2026-07-24',
    );
    expect(latePayment.createdAt!.day, 25);
  });

  test(
    'fallback usa fecha del pago solo si no hay fecha operativa de orden',
    () {
      final legacyOrder = order(total: 50);
      final latePayment = payment(
        base: 50,
        charged: 50,
        businessDate: '2026-07-25',
        createdAt: DateTime(2026, 7, 25, 0, 10),
      );

      expect(
        resolveOperationalBusinessDate(
          order: legacyOrder,
          payment: latePayment,
        ),
        '2026-07-25',
      );
    },
  );

  test('reporte por hora usa fecha operativa y hora real del pago', () {
    final businessOrder = order(
      total: 91,
      businessDate: '2026-07-24',
      createdAt: DateTime(2026, 7, 24, 23, 40),
    );
    final latePayment = payment(
      orderId: businessOrder.id,
      base: 91,
      charged: 91,
      createdAt: DateTime(2026, 7, 25, 0, 10),
    );

    final report24 = buildHourlySalesComparison(
      mode: HourlyComparisonMode.previousWeek,
      payments: [latePayment],
      orders: [businessOrder],
      baseDate: DateTime(2026, 7, 24),
    )!;
    expect(report24.rows[0].a.sales, 91);
    expect(report24.totalA, 91);

    final report25 = buildHourlySalesComparison(
      mode: HourlyComparisonMode.previousWeek,
      payments: [latePayment],
      orders: [businessOrder],
      baseDate: DateTime(2026, 7, 25),
    )!;
    expect(report25.totalA, 0);
  });

  test('pago anidado sin orderId se agrupa con la orden padre', () {
    final businessOrder = order(
      total: 91,
      businessDate: '2026-07-23',
      createdAt: DateTime(2026, 7, 23, 23, 42),
    );
    final rawPayment = payment(
      orderId: '',
      base: 91,
      charged: 91,
      businessDate: '2026-07-24',
      createdAt: DateTime(2026, 7, 24, 0, 2),
    );
    final paymentWithOrderContext = rawPayment.copyWith(
      orderId: businessOrder.id,
      businessDate: businessOrder.businessDate,
    );

    final report23 = buildHourlySalesComparison(
      mode: HourlyComparisonMode.previousWeek,
      payments: [paymentWithOrderContext],
      orders: [businessOrder],
      baseDate: DateTime(2026, 7, 23),
    )!;
    expect(report23.totalA, 91);

    final report24 = buildHourlySalesComparison(
      mode: HourlyComparisonMode.previousWeek,
      payments: [paymentWithOrderContext],
      orders: [businessOrder],
      baseDate: DateTime(2026, 7, 24),
    )!;
    expect(report24.totalA, 0);
  });

  test('pago cancelado se conserva pero no cuenta como cobrado real', () {
    final summary = buildCanonicalSalesSummary([
      bundle(
        total: 100,
        payment: payment(
          base: 100,
          charged: 100,
          status: 'cancelled',
          cancelledAt: DateTime(2026, 7, 26),
        ),
      ),
    ]);

    expect(summary.grossSales, 100);
    expect(summary.netSales, 100);
    expect(summary.totalCollected, 0);
  });

  test('orden cancelada se conserva pero no cuenta en ventas', () {
    final summary = buildCanonicalSalesSummary([
      SalesOrderBundleInput(
        order: order(
          total: 100,
          status: 'cancelled',
          cancelledAt: DateTime(2026, 7, 26),
        ),
        items: [item(total: 100)],
        payments: [payment(base: 100, charged: 100)],
      ),
    ]);

    expect(summary.grossSales, 0);
    expect(summary.netSales, 0);
    expect(summary.totalCollected, 0);
    expect(summary.paidOrdersCount, 0);
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

PosOrder order({
  required double total,
  Map<String, double> fields = const {},
  String? businessDate,
  DateTime? createdAt,
  String status = 'paid',
  DateTime? cancelledAt,
}) {
  return PosOrder(
    id: 'order-$total',
    tableId: 't1',
    tableName: 'Mesa 1',
    status: status,
    kitchenStatus: 'ready',
    paymentStatus: 'paid',
    total: total,
    paidTotal: total,
    pendingTotal: 0,
    personNames: const {},
    orderType: 'dine_in',
    explicitDiscountFields: fields,
    businessDate: businessDate,
    createdAt: createdAt,
    cancelledAt: cancelledAt,
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
  String orderId = 'order',
  required double base,
  required double charged,
  double? applied,
  double discountAmount = 0,
  double? received,
  double? change,
  double cardFee = 0,
  String? businessDate,
  DateTime? createdAt,
  String status = 'active',
  DateTime? cancelledAt,
}) {
  return Payment(
    id: 'payment-$base-$charged',
    orderId: orderId,
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
    discountAmount: discountAmount,
    cardFeeAbsorbedAmount: cardFee,
    businessDate: businessDate,
    createdAt: createdAt,
    status: status,
    cancelledAt: cancelledAt,
  );
}
