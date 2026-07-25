import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/canonical_sales_summary.dart';
import 'package:tacopos/core/reports/discounts_by_day_report.dart';
import 'package:tacopos/core/reports/operational_blockers.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/payment.dart';

void main() {
  test('clasifica comida gratis empleado separada de descuentos normales', () {
    final report = buildDiscountsByDayReport(
      orderRows: [
        discountRow(
          order: order(
            id: 'employee-free',
            discountType: 'employee_free_meal',
            discountName: 'Comida empleado del dia',
            discountBeneficiaryEmployeeName: 'Ana',
          ),
          discountAmount: 100,
        ),
        discountRow(
          order: order(
            id: 'partner',
            discountType: 'partner_discount',
            discountName: 'Socio 20',
            discountBeneficiaryPartnerName: 'Luis',
          ),
          discountAmount: 20,
        ),
      ],
      paymentsByOrder: const {},
    );

    expect(
      classifyDiscountType(type: 'employee_free_meal').name,
      DiscountReportCategory.employeeFreeMeal.name,
    );
    expect(report.discountTotal, 120);
    expect(report.employeeFreeMeals, 100);
    expect(report.normalDiscounts, 20);
  });

  test('no clasifica cortesia 100 como comida gratis empleado', () {
    final category = classifyDiscountType(
      type: 'courtesy',
      name: 'Cortesia 100',
    );
    expect(category, DiscountReportCategory.courtesy);
  });

  test('orden pagada con currentOrderId obsoleto no bloquea', () {
    final blocker = evaluateOperationalOrderBlocker(
      order: order(
        status: 'paid',
        paymentStatus: 'paid',
        pendingTotal: 0,
        paidAt: DateTime(2026, 7, 23, 23, 50),
      ),
      items: [item(paymentStatus: 'paid')],
      payments: [payment()],
      belongsToBranchAndDate: true,
    );

    expect(blocker, isNull);
  });

  test('orden vacia no bloquea el cierre', () {
    final blocker = evaluateOperationalOrderBlocker(
      order: order(total: 0, pendingTotal: 0),
      items: const [],
      payments: const [],
      belongsToBranchAndDate: true,
    );

    expect(blocker, isNull);
  });

  test('orden real abierta bloquea con folio y motivo', () {
    final blocker = evaluateOperationalOrderBlocker(
      order: order(
        id: 'ABC123',
        status: 'open',
        paymentStatus: 'pending',
        total: 91,
        pendingTotal: 91,
      ),
      items: [item()],
      payments: const [],
      belongsToBranchAndDate: true,
    );

    expect(blocker, isNotNull);
    expect(blocker!.order.id, 'ABC123');
    expect(blocker.reason, contains('saldo pendiente'));
  });

  test('pedido para llevar pagado no cuenta como abierto', () {
    final blocker = evaluateOperationalOrderBlocker(
      order: order(
        orderType: 'takeout',
        status: 'paid',
        paymentStatus: 'paid',
        pendingTotal: 0,
        paidAt: DateTime(2026, 7, 23, 23, 50),
      ),
      items: [item(paymentStatus: 'paid')],
      payments: [payment()],
      belongsToBranchAndDate: true,
    );

    expect(blocker, isNull);
  });

  test('orden de otra fecha no aparece como bloqueo actual', () {
    final blocker = evaluateOperationalOrderBlocker(
      order: order(total: 50, pendingTotal: 50),
      items: [item()],
      payments: const [],
      belongsToBranchAndDate: false,
    );

    expect(blocker, isNull);
  });
}

CanonicalOrderSalesRow discountRow({
  required PosOrder order,
  double discountAmount = 10,
}) {
  return CanonicalOrderSalesRow(
    order: order,
    grossSales: 100,
    discountTotal: discountAmount,
    netSales: 100 - discountAmount,
    totalCollected: 100 - discountAmount,
    reconciliationDifference: 0,
    businessDate: order.businessDate ?? '2026-07-23',
  );
}

PosOrder order({
  String id = 'order',
  String orderType = 'dine_in',
  String status = 'open',
  String paymentStatus = 'pending',
  double total = 100,
  double pendingTotal = 100,
  DateTime? paidAt,
  String? discountType,
  String? discountName,
  String? discountBeneficiaryEmployeeName,
  String? discountBeneficiaryPartnerName,
}) {
  return PosOrder(
    id: id,
    tableId: orderType == 'takeout' ? 'takeout' : 't1',
    tableName: orderType == 'takeout' ? 'Para llevar' : 'Mesa 1',
    status: status,
    kitchenStatus: status == 'paid' ? 'ready' : 'sent',
    paymentStatus: paymentStatus,
    total: total,
    paidTotal: total - pendingTotal,
    pendingTotal: pendingTotal,
    personNames: const {},
    orderType: orderType,
    paidAt: paidAt,
    businessDate: '2026-07-23',
    discountType: discountType,
    discountName: discountName,
    discountBeneficiaryEmployeeName: discountBeneficiaryEmployeeName,
    discountBeneficiaryPartnerName: discountBeneficiaryPartnerName,
  );
}

OrderItem item({String paymentStatus = 'pending'}) {
  return OrderItem(
    id: 'item',
    personNumber: 1,
    personName: 'Persona 1',
    productId: 'p1',
    productName: 'Taco',
    category: 'Tacos',
    qty: 1,
    unitPrice: 100,
    total: 100,
    notes: '',
    sendToKitchen: true,
    kitchenStatus: 'sent',
    paymentStatus: paymentStatus,
  );
}

Payment payment() {
  return const Payment(
    id: 'payment',
    orderId: 'order',
    tableId: 't1',
    tableName: 'Mesa 1',
    type: 'full_table',
    method: 'cash',
    baseAmount: 100,
    surchargeRate: 0,
    surchargeAmount: 0,
    chargedAmount: 100,
  );
}
