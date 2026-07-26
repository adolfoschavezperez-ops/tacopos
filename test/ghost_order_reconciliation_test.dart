import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/order_activity.dart';
import 'package:tacopos/core/reports/operational_blockers.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/payment.dart';
import 'package:tacopos/models/pos_table.dart';

void main() {
  group('ghost order reconciliation decisions', () {
    test('A last cancelled item cancels order and releases matching table', () {
      final order = _order(total: 0, pendingTotal: 0);
      final table = _table(currentOrderId: order.id);
      final evaluation = evaluateGhostOrder(order, [
        _item(status: 'cancelled', cancelStatus: 'accepted'),
      ], const []);

      expect(evaluation.isGhost, isTrue);
      expect(evaluation.activeItemsCount, 0);
      expect(evaluation.activePaymentsCount, 0);
      expect(evaluation.cancelledItemsCount, 1);
      expect(
        shouldReleaseTableForGhostOrder(order: order, table: table),
        isTrue,
      );
    });

    test('B one cancelled item and one active item keeps order and table', () {
      final order = _order(total: 100, pendingTotal: 100);
      final table = _table(currentOrderId: order.id);
      final evaluation = evaluateGhostOrder(order, [
        _item(id: 'cancelled', status: 'cancelled'),
        _item(id: 'active'),
      ], const []);

      expect(evaluation.isGhost, isFalse);
      expect(evaluation.activeItemsCount, 1);
      expect(
        evaluation.isGhost &&
            shouldReleaseTableForGhostOrder(order: order, table: table),
        isFalse,
      );
    });

    test('C active payment prevents automatic cancellation', () {
      final order = _order(total: 0, pendingTotal: 0);
      final evaluation = evaluateGhostOrder(
        order,
        [_item(status: 'cancelled')],
        [_payment(amount: 50)],
      );

      expect(evaluation.isGhost, isFalse);
      expect(evaluation.activePaymentsCount, 1);
      expect(
        isOperationalOrderActive(
          order: order,
          items: [_item(status: 'cancelled')],
          payments: [_payment(amount: 50)],
        ),
        isTrue,
      );
      expect(
        evaluateOperationalOrderBlocker(
          order: order,
          items: [_item(status: 'cancelled')],
          payments: [_payment(amount: 50)],
          belongsToBranchAndDate: true,
        ),
        isNotNull,
      );
    });

    test('D empty order without payments is a ghost', () {
      final evaluation = evaluateGhostOrder(
        _order(total: 0, pendingTotal: 0),
        const [],
        const [],
      );

      expect(evaluation.isGhost, isTrue);
    });

    test('E paid order is never modified as a ghost', () {
      final evaluation = evaluateGhostOrder(
        _order(
          status: 'paid',
          paymentStatus: 'paid',
          total: 0,
          pendingTotal: 0,
          paidAt: DateTime(2026, 7, 26),
        ),
        const [],
        const [],
      );

      expect(evaluation.isGhost, isFalse);
      expect(isActiveOrderState(_paidOrder()), isFalse);
    });

    test('F currentOrderId pointing to cancelled order is stale', () {
      final table = _table(currentOrderId: 'cancelled-order');

      expect(isStaleTableLink(table, activeOrderIds: const {}), isTrue);
      expect(
        isStaleTableLink(table, activeOrderIds: const {'cancelled-order'}),
        isFalse,
      );
    });

    test('G ghost takeout is cancelled without releasing a table', () {
      final order = _order(
        id: 'takeout',
        orderType: 'takeout',
        total: 0,
        pendingTotal: 0,
      );
      final evaluation = evaluateGhostOrder(order, [
        _item(status: 'cancelled'),
      ], const []);

      expect(evaluation.isGhost, isTrue);
      expect(
        shouldReleaseTableForGhostOrder(
          order: order,
          table: _table(currentOrderId: order.id),
        ),
        isFalse,
      );
    });

    test('requested cancellation remains active until accepted', () {
      final item = _item(
        kitchenStatus: 'cancel_requested',
        cancelStatus: 'requested',
      );

      expect(isActiveOrderItem(item), isTrue);
      expect(
        isGhostOrder(_order(total: 100, pendingTotal: 100), [item], const []),
        isFalse,
      );
    });
  });
}

PosOrder _paidOrder() {
  return _order(
    status: 'paid',
    paymentStatus: 'paid',
    total: 100,
    pendingTotal: 0,
    paidAt: DateTime(2026, 7, 26),
  );
}

PosOrder _order({
  String id = 'order',
  String orderType = 'dine_in',
  String status = 'open',
  String paymentStatus = 'pending',
  double total = 0,
  double pendingTotal = 0,
  DateTime? paidAt,
}) {
  return PosOrder(
    id: id,
    tableId: orderType == 'takeout' ? 'takeout' : 'table-2',
    tableName: orderType == 'takeout' ? 'Para llevar' : 'Mesa 2',
    status: status,
    kitchenStatus: 'not_required',
    paymentStatus: paymentStatus,
    total: total,
    paidTotal: total - pendingTotal,
    pendingTotal: pendingTotal,
    personNames: const {},
    orderType: orderType,
    paidAt: paidAt,
    businessDate: '2026-07-26',
    branchId: 'aviacion',
    branchName: 'Aviacion',
  );
}

OrderItem _item({
  String id = 'item',
  String status = 'active',
  String kitchenStatus = 'not_required',
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
    unitPrice: 100,
    total: 100,
    notes: '',
    sendToKitchen: false,
    kitchenStatus: kitchenStatus,
    paymentStatus: 'pending',
    status: status,
    cancelStatus: cancelStatus,
  );
}

Payment _payment({required double amount}) {
  return Payment(
    id: 'payment',
    orderId: 'order',
    tableId: 'table-2',
    tableName: 'Mesa 2',
    type: 'partial',
    method: 'cash',
    baseAmount: amount,
    surchargeRate: 0,
    surchargeAmount: 0,
    chargedAmount: amount,
  );
}

PosTable _table({required String? currentOrderId}) {
  return PosTable(
    id: 'table-2',
    name: 'Mesa 2',
    type: 'table',
    status: currentOrderId == null ? 'available' : 'occupied',
    active: true,
    sortOrder: 2,
    currentOrderId: currentOrderId,
    branchId: 'aviacion',
    branchName: 'Aviacion',
  );
}
