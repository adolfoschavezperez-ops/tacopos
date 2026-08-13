import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/order_activity.dart';
import 'package:tacopos/core/orders/table_operational_status.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/pos_table.dart';

void main() {
  group('waiterTableStatusKey', () {
    test('marks a free table as available', () {
      expect(
        waiterTableStatusKey(
          table: _table(currentOrderId: null),
          order: null,
          items: const [],
        ),
        tableStatusAvailable,
      );
    });

    test('marks kitchen items awaiting send as pending send', () {
      expect(
        waiterTableStatusKey(
          table: _table(),
          order: _order(),
          items: [_item(kitchenStatus: 'pending')],
        ),
        tableStatusPendingSend,
      );
    });

    test('treats kitchenStatus pending without batch as pending send', () {
      final item = _item(kitchenStatus: 'pending', sent: false);

      expect(itemIsAwaitingKitchenSend(item), isTrue);
      expect(
        waiterTableStatusKey(table: _table(), order: _order(), items: [item]),
        tableStatusPendingSend,
      );
    });

    test('marks sent items as in kitchen after sending to kitchen', () {
      expect(
        waiterTableStatusKey(
          table: _table(),
          order: _order(),
          items: [_item(kitchenStatus: 'pending', sent: true)],
        ),
        tableStatusInKitchen,
      );
    });

    test('uses kitchenBatchId as send evidence', () {
      expect(
        waiterTableStatusKey(
          table: _table(),
          order: _order(),
          items: [_item(kitchenStatus: 'pending', kitchenBatchId: 'batch-1')],
        ),
        tableStatusInKitchen,
      );
    });

    test('marks cooking items as preparing', () {
      expect(
        waiterTableStatusKey(
          table: _table(),
          order: _order(),
          items: [_item(kitchenStatus: 'cooking', sent: true)],
        ),
        tableStatusPreparing,
      );
    });

    test('marks ready kitchen items as ready to charge', () {
      expect(
        waiterTableStatusKey(
          table: _table(),
          order: _order(),
          items: [_item(kitchenStatus: 'ready', sent: true)],
        ),
        tableStatusReadyToCharge,
      );
    });

    test('marks paid or closed orders as available', () {
      expect(
        waiterTableStatusKey(
          table: _table(),
          order: _order(status: 'paid', pendingTotal: 0),
          items: [_item(kitchenStatus: 'ready', sent: true)],
        ),
        tableStatusAvailable,
      );
    });

    test('prioritizes ready item plus new extra as pending send', () {
      expect(
        waiterTableStatusKey(
          table: _table(),
          order: _order(),
          items: [
            _item(id: 'ready', kitchenStatus: 'ready', sent: true),
            _item(id: 'extra', kitchenStatus: 'pending'),
          ],
        ),
        tableStatusPendingSend,
      );
    });

    test('prioritizes new unsent item over preparing item', () {
      expect(
        waiterTableStatusKey(
          table: _table(),
          order: _order(),
          items: [
            _item(id: 'cooking', kitchenStatus: 'cooking', sent: true),
            _item(id: 'extra', kitchenStatus: 'pending'),
          ],
        ),
        tableStatusPendingSend,
      );
    });

    test('cancelled item does not mark table as pending send', () {
      expect(
        waiterTableStatusKey(
          table: _table(),
          order: _order(),
          items: [_item(kitchenStatus: 'pending', status: 'cancelled')],
        ),
        tableStatusInKitchen,
      );
    });

    test('does not block charge readiness with non kitchen items', () {
      expect(
        waiterTableStatusKey(
          table: _table(),
          order: _order(),
          items: [
            _item(kitchenStatus: 'ready', sent: true),
            _item(
              id: 'drink',
              productName: 'Agua',
              category: 'bebidas',
              sendToKitchen: false,
            ),
          ],
        ),
        tableStatusReadyToCharge,
      );
    });

    test('does not mark not_required beverages as pending send', () {
      expect(
        waiterTableStatusKey(
          table: _table(),
          order: _order(),
          items: [
            _item(
              id: 'drink',
              productName: 'Agua',
              category: 'bebidas',
              kitchenStatus: 'not_required',
              sendToKitchen: false,
            ),
          ],
        ),
        tableStatusReadyToCharge,
      );
    });

    test('reopened order with unsent extra stays pending send', () {
      final initialReady = _item(
        id: 'initial',
        kitchenStatus: 'ready',
        sent: true,
      );
      final reopenedExtra = _item(id: 'extra', kitchenStatus: 'pending');

      expect(itemCanBeSentToKitchenBatch(reopenedExtra), isTrue);
      expect(
        waiterTableStatusKey(
          table: _table(),
          order: _order(),
          items: [initialReady, reopenedExtra],
        ),
        tableStatusPendingSend,
      );
    });

    test('table status matches canonical kitchen send helper', () {
      final item = _item(kitchenStatus: 'pending');

      expect(itemCanBeSentToKitchenBatch(item), isTrue);
      expect(
        waiterTableStatusKey(table: _table(), order: _order(), items: [item]),
        tableStatusPendingSend,
      );
    });
  });
}

PosTable _table({String? currentOrderId = 'order-1'}) {
  return PosTable(
    id: 'table-1',
    name: 'Mesa 1',
    type: 'table',
    status: currentOrderId == null ? 'available' : 'occupied',
    active: true,
    sortOrder: 1,
    currentOrderId: currentOrderId,
  );
}

PosOrder _order({String status = 'open', double pendingTotal = 120}) {
  return PosOrder(
    id: 'order-1',
    tableId: 'table-1',
    tableName: 'Mesa 1',
    status: status,
    kitchenStatus: 'pending',
    paymentStatus: 'pending',
    total: pendingTotal,
    paidTotal: 0,
    pendingTotal: pendingTotal,
    personNames: const {},
    orderType: 'dine_in',
    tableIds: const ['table-1'],
  );
}

OrderItem _item({
  String id = 'item-1',
  String productName = 'Taco',
  String category = 'tacos',
  String kitchenStatus = 'pending',
  bool sendToKitchen = true,
  bool sent = false,
  String? kitchenBatchId,
  String status = 'active',
}) {
  return OrderItem(
    id: id,
    personNumber: 1,
    personName: 'Persona 1',
    productId: id,
    productName: productName,
    category: category,
    qty: 1,
    unitPrice: 60,
    total: 60,
    notes: '',
    sendToKitchen: sendToKitchen,
    kitchenStatus: kitchenStatus,
    paymentStatus: 'pending',
    kitchenBatchId: kitchenBatchId,
    sentToKitchenAt: sent ? DateTime(2026) : null,
    status: status,
  );
}
