import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/order_activity.dart';
import 'package:tacopos/core/orders/order_types.dart';
import 'package:tacopos/core/reports/canonical_sales_summary.dart';
import 'package:tacopos/core/reports/operational_blockers.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/order_platform.dart';
import 'package:tacopos/models/pos_table.dart';
import 'package:tacopos/screens/waiter/tables_screen.dart';

void main() {
  group('unseated order rules', () {
    test('customerName is required for takeout and standing', () {
      expect(
        () => requireCustomerName(
          '   ',
          message: 'Captura el nombre del cliente.',
        ),
        throwsArgumentError,
      );
      expect(
        () => requireCustomerName(
          null,
          message: 'Captura el nombre de la persona.',
        ),
        throwsArgumentError,
      );
      expect(requireCustomerName(' Juan ', message: 'required'), 'Juan');
    });

    test('standing finds and forces the real En persona platform', () {
      final platform = findInPersonPlatform(const [
        OrderPlatform(id: 'uber', name: 'Uber', active: true, sortOrder: 2),
        OrderPlatform(
          id: 'walk-in-real',
          name: ' En persona ',
          active: true,
          sortOrder: 1,
        ),
      ]);

      expect(platform?.id, 'walk-in-real');
      expect(platform?.name.trim(), 'En persona');
    });

    test('standing has its own label and kitchen identity', () {
      final order = _order(
        id: 'standing',
        orderType: standingOrderType,
        customerName: 'Juan',
      );

      expect(isStandingOrder(order), isTrue);
      expect(isTakeoutOrder(order), isFalse);
      expect(isDineInOrder(order), isFalse);
      expect(order.orderTypeLabel, 'Parados sin mesa');
      expect(order.displayName, 'Sin mesa · Juan');
    });

    test('active standing is visible in the live operations viewer', () {
      final order = _order(
        id: 'standing-active',
        orderType: standingOrderType,
        status: 'sent',
        paymentStatus: 'pending',
        pendingTotal: 100,
        customerName: 'Juan',
      );

      expect(
        isStandingOrderVisibleInLiveViewer(
          order: order,
          items: [_item()],
          payments: const [],
          belongsToSelectedBranchAndDate: true,
        ),
        isTrue,
      );
    });

    test('paid, cancelled and empty standing orders are not live', () {
      final paid = _order(
        id: 'standing-paid',
        orderType: standingOrderType,
        customerName: 'Ana',
      );
      final cancelled = _order(
        id: 'standing-cancelled',
        orderType: standingOrderType,
        status: 'cancelled',
        paymentStatus: 'cancelled',
        customerName: 'Luis',
      );
      final empty = _order(
        id: 'standing-empty',
        orderType: standingOrderType,
        status: 'open',
        paymentStatus: 'pending',
        customerName: 'Eva',
      );

      for (final order in [paid, cancelled, empty]) {
        expect(
          isStandingOrderVisibleInLiveViewer(
            order: order,
            items: const [],
            payments: const [],
            belongsToSelectedBranchAndDate: true,
          ),
          isFalse,
        );
      }
    });

    test('standing viewer rejects takeout and another branch or date', () {
      final standing = _order(
        id: 'standing',
        orderType: standingOrderType,
        status: 'open',
        paymentStatus: 'pending',
        pendingTotal: 100,
        customerName: 'Juan',
      );
      final takeout = _order(
        id: 'takeout',
        orderType: takeoutOrderType,
        status: 'open',
        paymentStatus: 'pending',
        pendingTotal: 100,
      );

      expect(
        isStandingOrderVisibleInLiveViewer(
          order: standing,
          items: [_item()],
          payments: const [],
          belongsToSelectedBranchAndDate: false,
        ),
        isFalse,
      );
      expect(
        isStandingOrderVisibleInLiveViewer(
          order: takeout,
          items: [_item()],
          payments: const [],
          belongsToSelectedBranchAndDate: true,
        ),
        isFalse,
      );
    });

    test('takeout entry keeps its route decision and motorcycle icon', () {
      expect(isTakeoutEntryTableType('takeout'), isTrue);
      expect(isTakeoutEntryTableType('takeout_entry'), isTrue);
      expect(isTakeoutEntryTableType('table'), isFalse);
      expect(takeoutEntryIcon, Icons.two_wheeler);
    });

    test('paid order counts split into takeout, dine-in and standing', () {
      final summary = buildCanonicalSalesSummary([
        SalesOrderBundleInput(
          order: _order(id: 'takeout', orderType: takeoutOrderType),
          items: const [],
          payments: const [],
        ),
        SalesOrderBundleInput(
          order: _order(id: 'table', orderType: dineInOrderType),
          items: const [],
          payments: const [],
        ),
        SalesOrderBundleInput(
          order: _order(id: 'standing', orderType: standingOrderType),
          items: const [],
          payments: const [],
        ),
      ]);

      expect(summary.paidOrdersCount, 3);
      expect(summary.takeoutOrdersCount, 1);
      expect(summary.dineInOrdersCount, 1);
      expect(summary.standingOrdersCount, 1);
    });
  });

  group('table group rules', () {
    test('two available tables create one new-order decision', () {
      final decision = evaluateTableJoinSelection([
        _table(id: 'mesa_1', name: 'Mesa 1'),
        _table(id: 'mesa_2', name: 'Mesa 2'),
      ]);

      expect(decision.allowed, isTrue);
      expect(decision.baseOrderId, isNull);
    });

    test('available table can join one existing order', () {
      final decision = evaluateTableJoinSelection([
        _table(id: 'mesa_1', name: 'Mesa 1', currentOrderId: 'order-a'),
        _table(id: 'mesa_2', name: 'Mesa 2'),
      ]);

      expect(decision.allowed, isTrue);
      expect(decision.baseOrderId, 'order-a');
    });

    test('two different existing orders cannot be merged', () {
      final decision = evaluateTableJoinSelection([
        _table(id: 'mesa_1', name: 'Mesa 1', currentOrderId: 'order-a'),
        _table(id: 'mesa_2', name: 'Mesa 2', currentOrderId: 'order-b'),
      ]);

      expect(decision.allowed, isFalse);
      expect(
        decision.message,
        'No se pueden juntar mesas que ya tienen órdenes diferentes.',
      );
    });

    test('payment or cancellation releases every still-linked table only', () {
      final order = _order(
        id: 'group-order',
        orderType: dineInOrderType,
        tableIds: const ['mesa_1', 'mesa_2'],
        tableNames: const ['Mesa 1', 'Mesa 2'],
        isTableGroup: true,
        tableGroupLabel: 'Mesa 1 + Mesa 2',
      );
      final linked = tablesStillLinkedToOrder(order, [
        _table(id: 'mesa_1', name: 'Mesa 1', currentOrderId: 'group-order'),
        _table(id: 'mesa_2', name: 'Mesa 2', currentOrderId: 'group-order'),
        _table(id: 'mesa_3', name: 'Mesa 3', currentOrderId: 'other-order'),
      ]);

      expect(linked.map((table) => table.id), ['mesa_1', 'mesa_2']);
      expect(order.displayName, 'Mesa 1 + Mesa 2');
      expect(order.linkedTableIds.length, 2);
    });

    test('group is one cash blocker while occupying multiple tables', () {
      final order = _order(
        id: 'group-order',
        orderType: dineInOrderType,
        status: 'open',
        paymentStatus: 'pending',
        pendingTotal: 100,
        tableIds: const ['mesa_1', 'mesa_2'],
        tableNames: const ['Mesa 1', 'Mesa 2'],
        isTableGroup: true,
        tableGroupLabel: 'Mesa 1 + Mesa 2',
      );
      final blocker = evaluateOperationalOrderBlocker(
        order: order,
        items: [_item()],
        payments: const [],
        belongsToBranchAndDate: true,
      );
      final summary = OperationalOpenOrdersSummary(
        businessDate: '2026-07-26',
        branchId: 'aviacion',
        cashSessionId: 'cash',
        ordersChecked: 1,
        discardedReasons: const {},
        staleTableLinks: 0,
        releasedTableLinks: 0,
        blockers: [blocker!],
      );

      expect(summary.blockers.length, 1);
      expect(summary.openTableCount, 1);
      expect(order.linkedTableIds.length, 2);
    });

    test('active standing order blocks close without counting as table', () {
      final order = _order(
        id: 'standing',
        orderType: standingOrderType,
        status: 'open',
        paymentStatus: 'pending',
        pendingTotal: 50,
        customerName: 'Juan',
      );
      final blocker = evaluateOperationalOrderBlocker(
        order: order,
        items: [_item()],
        payments: const [],
        belongsToBranchAndDate: true,
      );
      final summary = OperationalOpenOrdersSummary(
        businessDate: '2026-07-26',
        branchId: 'aviacion',
        cashSessionId: 'cash',
        ordersChecked: 1,
        discardedReasons: const {},
        staleTableLinks: 0,
        releasedTableLinks: 0,
        blockers: [blocker!],
      );

      expect(summary.openStandingCount, 1);
      expect(summary.openTableCount, 0);
      expect(summary.openTakeoutCount, 0);
    });
  });

  group('change table rules', () {
    test('mesa puede moverse solo a mesa libre', () {
      final order = _order(
        id: 'table-order',
        orderType: dineInOrderType,
        status: 'sent',
        paymentStatus: 'pending',
        pendingTotal: 200,
        tableIds: const ['mesa_1'],
        tableNames: const ['Mesa 1'],
      );

      final decision = evaluateChangeTableDestination(
        order: order,
        destination: _table(id: 'mesa_5', name: 'Mesa 5'),
      );

      expect(decision.allowed, isTrue);
    });

    test('mesa ocupada no es destino de cambio de mesa', () {
      final order = _order(
        id: 'table-order',
        orderType: dineInOrderType,
        status: 'sent',
        paymentStatus: 'pending',
        pendingTotal: 200,
        tableIds: const ['mesa_1'],
      );

      final decision = evaluateChangeTableDestination(
        order: order,
        destination: _table(
          id: 'mesa_5',
          name: 'Mesa 5',
          currentOrderId: 'other-order',
        ),
      );

      expect(decision.allowed, isFalse);
      expect(decision.message, 'Selecciona una mesa libre.');
    });

    test('parados sin mesa puede moverse a mesa libre', () {
      final order = _order(
        id: 'standing-order',
        orderType: standingOrderType,
        status: 'open',
        paymentStatus: 'pending',
        pendingTotal: 120,
        customerName: 'Juan',
      );

      final decision = evaluateChangeTableDestination(
        order: order,
        destination: _table(id: 'mesa_3', name: 'Mesa 3'),
      );

      expect(decision.allowed, isTrue);
    });

    test('para llevar no puede cambiarse a mesa en este flujo', () {
      final order = _order(
        id: 'takeout-order',
        orderType: takeoutOrderType,
        status: 'open',
        paymentStatus: 'pending',
        pendingTotal: 120,
        customerName: 'Ana',
      );

      final decision = evaluateChangeTableDestination(
        order: order,
        destination: _table(id: 'mesa_3', name: 'Mesa 3'),
      );

      expect(decision.allowed, isFalse);
      expect(
        decision.message,
        'Cambiar mesa no aplica para pedidos Para llevar.',
      );
    });
  });
}

PosOrder _order({
  required String id,
  required String orderType,
  String status = 'paid',
  String paymentStatus = 'paid',
  double pendingTotal = 0,
  String? customerName,
  bool isTableGroup = false,
  List<String> tableIds = const [],
  List<String> tableNames = const [],
  String? tableGroupLabel,
}) {
  return PosOrder(
    id: id,
    tableId: orderType == dineInOrderType ? 'mesa_1' : '',
    tableName: orderType == dineInOrderType ? 'Mesa 1' : '',
    status: status,
    kitchenStatus: 'not_required',
    paymentStatus: paymentStatus,
    total: pendingTotal,
    paidTotal: paymentStatus == 'paid' ? pendingTotal : 0,
    pendingTotal: pendingTotal,
    personNames: const {1: 'Persona 1'},
    orderType: orderType,
    customerName: customerName,
    isTableGroup: isTableGroup,
    primaryTableId: isTableGroup ? 'mesa_1' : null,
    primaryTableName: isTableGroup ? 'Mesa 1' : null,
    tableIds: tableIds,
    tableNames: tableNames,
    tableGroupLabel: tableGroupLabel,
    branchId: 'aviacion',
    branchName: 'Aviación',
  );
}

PosTable _table({
  required String id,
  required String name,
  String? currentOrderId,
}) {
  return PosTable(
    id: id,
    name: name,
    type: 'table',
    status: currentOrderId == null ? 'available' : 'occupied',
    active: true,
    sortOrder: int.tryParse(id.split('_').last) ?? 0,
    currentOrderId: currentOrderId,
    branchId: 'aviacion',
    branchName: 'Aviación',
  );
}

OrderItem _item() {
  return const OrderItem(
    id: 'item',
    personNumber: 1,
    personName: 'Persona 1',
    productId: 'product',
    productName: 'Producto',
    category: 'General',
    qty: 1,
    unitPrice: 100,
    total: 100,
    notes: '',
    sendToKitchen: true,
    kitchenStatus: 'sent',
    paymentStatus: 'pending',
  );
}
