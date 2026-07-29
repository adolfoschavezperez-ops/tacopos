import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/cash/operational_business_date.dart';
import 'package:tacopos/core/orders/order_types.dart';
import 'package:tacopos/core/reports/operational_blockers.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';

void main() {
  group('operational viewer canonical classification', () {
    test('A active takeout appears in viewer', () {
      final summary = _summary([_activeBlocker(_order(type: 'takeout'))]);

      expect(summary.openTakeoutCount, 1);
      expect(summary.openTableCount, 0);
      expect(summary.openStandingCount, 0);
    });

    test('B active standing appears in its own section', () {
      final summary = _summary([_activeBlocker(_order(type: 'standing'))]);

      expect(summary.openStandingCount, 1);
      expect(summary.openTakeoutCount, 0);
      expect(summary.openTableCount, 0);
    });

    test('C table order appears in tables', () {
      final summary = _summary([_activeBlocker(_order(type: 'dine_in'))]);

      expect(summary.openTableCount, 1);
    });

    test('D takeout without tableId is not excluded', () {
      final order = _order(type: 'para llevar', tableId: '');

      expect(isTakeoutOrder(order), isTrue);
      expect(_activeBlocker(order).order.id, order.id);
    });

    test('E standing without tableId is not excluded', () {
      final order = _order(type: 'standing_no_table', tableId: '');

      expect(isStandingOrder(order), isTrue);
      expect(_activeBlocker(order).order.id, order.id);
    });

    test('F paid order does not appear', () {
      final order = _order(
        type: 'takeout',
        status: 'paid',
        paymentStatus: 'paid',
        pendingTotal: 0,
        paidTotal: 100,
      );

      expect(_evaluate(order), isNull);
    });

    test('G cancelled order does not appear', () {
      final order = _order(
        type: 'standing',
        status: 'cancelada',
        paymentStatus: 'cancelled',
      );

      expect(_evaluate(order), isNull);
    });

    test('H pending order without kitchen still appears', () {
      final order = _order(type: 'take_out', kitchenStatus: 'not_required');

      expect(_evaluate(order, item: _item(sendToKitchen: false)), isNotNull);
    });

    test(
      'I after-midnight order is scoped by businessDate and cash session',
      () {
        final order = _order(
          type: 'takeaway',
          businessDate: '2026-07-28',
          cashSessionId: 'cash-28',
          createdAt: DateTime(2026, 7, 29, 1, 20),
        );
        final membership = belongsToOperationalSession(
          order: order,
          selectedCashSessionId: 'cash-28',
          selectedBusinessDate: '2026-07-28',
          branchId: 'aviacion',
        );

        expect(membership.included, isTrue);
        expect(membership.reason, 'cash_session_match');
      },
    );

    test('J dashboard count equals viewer total', () {
      final summary = _summary([
        _activeBlocker(_order(id: 'table', type: 'mesa')),
        _activeBlocker(_order(id: 'takeout', type: 'para_llevar')),
        _activeBlocker(_order(id: 'standing', type: 'parados_sin_mesa')),
      ]);
      final reconciliation = reconcileOperationalViewer(summary);

      expect(reconciliation.dashboardOpen, 3);
      expect(reconciliation.viewerTables, 1);
      expect(reconciliation.viewerTakeout, 1);
      expect(reconciliation.viewerStanding, 1);
      expect(reconciliation.viewerTotal, 3);
      expect(reconciliation.difference, 0);
      expect(reconciliation.valid, isTrue);
    });

    test('K branch change does not mix orders', () {
      final otherBranch = _order(type: 'takeout', branchId: 'centro');
      final membership = belongsToOperationalSession(
        order: otherBranch,
        selectedCashSessionId: 'cash-28',
        selectedBusinessDate: '2026-07-28',
        branchId: 'aviacion',
      );

      expect(membership.included, isFalse);
      expect(membership.reason, 'branch_mismatch');
    });

    test('normalizes all supported historical order type aliases', () {
      for (final value in ['dine_in', 'dinein', 'table', 'mesa']) {
        expect(normalizeOrderType(value), 'table');
      }
      for (final value in [
        'takeout',
        'take_out',
        'takeaway',
        'para_llevar',
        'para llevar',
      ]) {
        expect(normalizeOrderType(value), 'takeout');
      }
      for (final value in [
        'standing',
        'standing_no_table',
        'walk_in_standing',
        'parado',
        'parados_sin_mesa',
      ]) {
        expect(normalizeOrderType(value), 'standing');
      }
    });
  });
}

OperationalOrderBlocker? _evaluate(
  PosOrder order, {
  OrderItem? item,
  bool belongsToBranchAndDate = true,
}) {
  return evaluateOperationalOrderBlocker(
    order: order,
    items: [item ?? _item()],
    payments: const [],
    belongsToBranchAndDate: belongsToBranchAndDate,
  );
}

OperationalOrderBlocker _activeBlocker(PosOrder order) {
  return _evaluate(order)!;
}

OperationalOpenOrdersSummary _summary(List<OperationalOrderBlocker> blockers) {
  return OperationalOpenOrdersSummary(
    businessDate: '2026-07-28',
    branchId: 'aviacion',
    cashSessionId: 'cash-28',
    ordersChecked: blockers.length,
    discardedReasons: const {},
    staleTableLinks: 0,
    releasedTableLinks: 0,
    blockers: blockers,
  );
}

PosOrder _order({
  String id = 'order',
  required String type,
  String tableId = '',
  String status = 'open',
  String kitchenStatus = 'pending',
  String paymentStatus = 'pending',
  double pendingTotal = 100,
  double paidTotal = 0,
  String businessDate = '2026-07-28',
  String cashSessionId = 'cash-28',
  String branchId = 'aviacion',
  DateTime? createdAt,
}) {
  return PosOrder(
    id: id,
    tableId: tableId,
    tableName: tableId.isEmpty ? '' : 'Mesa 1',
    status: status,
    kitchenStatus: kitchenStatus,
    paymentStatus: paymentStatus,
    total: 100,
    paidTotal: paidTotal,
    pendingTotal: pendingTotal,
    personNames: const {1: 'Cliente'},
    orderType: type,
    customerName: 'Cliente',
    businessDate: businessDate,
    cashSessionId: cashSessionId,
    branchId: branchId,
    branchName: branchId,
    createdAt: createdAt,
  );
}

OrderItem _item({bool sendToKitchen = true}) {
  return OrderItem(
    id: 'item',
    personNumber: 1,
    personName: 'Cliente',
    productId: 'product',
    productName: 'Producto',
    category: sendToKitchen ? 'Tacos' : 'Bebidas',
    qty: 1,
    unitPrice: 100,
    total: 100,
    notes: '',
    sendToKitchen: sendToKitchen,
    kitchenStatus: sendToKitchen ? 'sent' : 'not_required',
    paymentStatus: 'pending',
  );
}
