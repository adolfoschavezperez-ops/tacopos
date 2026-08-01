import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/order_activity.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/payment.dart';

void main() {
  group('operational state reconciliation rules', () {
    test('A mesa available con orden activa debe mantenerse ocupada', () {
      final order = _order(pendingTotal: 120);
      final items = [_item(total: 120)];

      expect(
        shouldKeepTableOccupiedForOrder(
          order: order,
          items: items,
          payments: const [],
        ),
        isTrue,
      );
    });

    test('B orden con items pendientes aparece en Cocina', () {
      final items = [
        _item(kitchenStatus: 'sent', sentToKitchenAt: DateTime(2026, 7, 29)),
      ];

      expect(items.any(isKitchenPendingItem), isTrue);
      expect(kitchenStatusForItems(items), 'sent');
    });

    test('B2 item recien agregado queda pendiente sin aparecer en Cocina', () {
      final item = _item(kitchenStatus: 'pending', kitchenBatchId: null);

      expect(itemIsAwaitingKitchenSend(item), isTrue);
      expect(itemCanBeSentToKitchenBatch(item), isTrue);
      expect(isKitchenPendingItem(item), isFalse);
      expect(itemWasSentToKitchen(item), isFalse);
      expect(kitchenStatusForItems([item]), 'pending');
    });

    test('B3 pending con batch explicito si aparece en Cocina', () {
      final item = _item(
        kitchenStatus: 'pending',
        kitchenBatchId: 'batch-a',
        sentToKitchenAt: DateTime(2026, 7, 29),
      );

      expect(itemIsAwaitingKitchenSend(item), isFalse);
      expect(itemCanBeSentToKitchenBatch(item), isFalse);
      expect(itemWasSentToKitchen(item), isTrue);
      expect(isKitchenPendingItem(item), isTrue);
    });

    test(
      'C kitchen pending sin items pendientes permite limpiar estado obsoleto',
      () {
        final items = [
          _item(kitchenStatus: 'ready', readyAt: DateTime(2026, 7, 29)),
        ];

        expect(hasPendingKitchenItems(items), isFalse);
        expect(kitchenStatusForItems(items), 'ready');
      },
    );

    test('D item cancelado no bloquea cobro', () {
      final item = _item(
        status: 'cancelled',
        kitchenStatus: 'sent',
        cancelStatus: 'accepted',
      );

      expect(isKitchenPendingItem(item), isFalse);
    });

    test('E bebida no bloquea Cocina', () {
      final item = _item(
        category: 'Bebidas',
        sendToKitchen: false,
        kitchenStatus: 'not_required',
      );

      expect(itemRequiresKitchen(item), isFalse);
      expect(isKitchenPendingItem(item), isFalse);
    });

    test('F dos batches con uno pendiente siguen bloqueando', () {
      final items = [
        _item(
          id: 'ready-batch',
          kitchenStatus: 'ready',
          kitchenBatchId: 'batch-ready',
          readyAt: DateTime(2026, 7, 29),
        ),
        _item(
          id: 'sent-batch',
          kitchenStatus: 'sent',
          kitchenBatchId: 'batch-sent',
          sentToKitchenAt: DateTime(2026, 7, 29),
        ),
      ];

      expect(pendingKitchenItemsCount(items), 1);
      expect(kitchenStatusForItems(items), 'sent');
    });

    test('F2 orden extra solo selecciona productos nuevos pendientes', () {
      final previous = _item(
        id: 'sent-before',
        kitchenStatus: 'sent',
        kitchenBatchId: 'batch-initial',
        sentToKitchenAt: DateTime(2026, 7, 29),
      );
      final extra = _item(
        id: 'new-extra',
        kitchenStatus: 'pending',
        kitchenBatchId: null,
      );

      expect(itemCanBeSentToKitchenBatch(previous), isFalse);
      expect(itemCanBeSentToKitchenBatch(extra), isTrue);
      expect(awaitingKitchenSendItemsCount([previous, extra]), 1);
      expect(pendingKitchenItemsCount([previous, extra]), 1);
    });

    test('F3 reintento no considera enviados anteriores', () {
      final sent = _item(
        kitchenStatus: 'sent',
        kitchenBatchId: 'batch-initial',
        sentToKitchenAt: DateTime(2026, 7, 29),
      );
      final ready = _item(
        id: 'ready',
        kitchenStatus: 'ready',
        kitchenBatchId: 'batch-initial',
        readyAt: DateTime(2026, 7, 29, 1),
      );

      expect([sent, ready].where(itemCanBeSentToKitchenBatch), isEmpty);
      expect(awaitingKitchenSendItemsCount([sent, ready]), 0);
      expect(kitchenStatusForItems([sent, ready]), 'sent');
    });

    test(
      'G todos los batches listos permiten cobrar y mantienen mesa ocupada',
      () {
        final order = _order(status: 'ready', pendingTotal: 200);
        final items = [
          _item(
            kitchenStatus: 'ready',
            kitchenBatchId: 'batch-a',
            readyAt: DateTime(2026, 7, 29),
          ),
        ];

        expect(hasPendingKitchenItems(items), isFalse);
        expect(
          shouldKeepTableOccupiedForOrder(
            order: order,
            items: items,
            payments: const [],
          ),
          isTrue,
        );
      },
    );

    test('H orden pagada ya no mantiene ocupada la mesa', () {
      final order = _order(
        status: 'paid',
        paymentStatus: 'paid',
        pendingTotal: 0,
        paidAt: DateTime(2026, 7, 29),
      );

      expect(
        shouldKeepTableOccupiedForOrder(
          order: order,
          items: [_item(kitchenStatus: 'ready')],
          payments: [_payment(amount: 100)],
        ),
        isFalse,
      );
    });

    test('I evaluar dos veces no cambia el resultado', () {
      final items = [
        _item(kitchenStatus: 'sent', sentToKitchenAt: DateTime(2026, 7, 29)),
      ];

      expect(kitchenStatusForItems(items), kitchenStatusForItems(items));
      expect(pendingKitchenItemsCount(items), pendingKitchenItemsCount(items));
    });

    test('J despues de medianoche conserva businessDate de la orden', () {
      final order = _order(businessDate: '2026-07-29', pendingTotal: 100);
      final items = [
        _item(kitchenStatus: 'sent', sentToKitchenAt: DateTime(2026, 7, 30)),
      ];

      expect(order.businessDate, '2026-07-29');
      expect(
        shouldKeepTableOccupiedForOrder(
          order: order,
          items: items,
          payments: const [],
        ),
        isTrue,
      );
    });
  });
}

PosOrder _order({
  String id = 'order',
  String status = 'open',
  String paymentStatus = 'pending',
  double total = 100,
  double pendingTotal = 100,
  String businessDate = '2026-07-29',
  DateTime? paidAt,
}) {
  return PosOrder(
    id: id,
    tableId: 'mesa_1',
    tableName: 'Mesa 1',
    status: status,
    kitchenStatus: 'sent',
    paymentStatus: paymentStatus,
    total: total,
    paidTotal: total - pendingTotal,
    pendingTotal: pendingTotal,
    personNames: const {},
    orderType: 'dine_in',
    tableIds: const ['mesa_1'],
    tableNames: const ['Mesa 1'],
    businessDate: businessDate,
    branchId: 'aviacion',
    branchName: 'Aviacion',
    paidAt: paidAt,
  );
}

OrderItem _item({
  String id = 'item',
  String category = 'Tacos',
  bool sendToKitchen = true,
  String status = 'active',
  String kitchenStatus = 'sent',
  String cancelStatus = 'none',
  String? kitchenBatchId = 'batch',
  DateTime? sentToKitchenAt,
  DateTime? readyAt,
  double total = 100,
}) {
  return OrderItem(
    id: id,
    personNumber: 1,
    personName: 'Persona 1',
    productId: 'product',
    productName: 'Producto',
    category: category,
    qty: 1,
    unitPrice: total,
    total: total,
    notes: '',
    sendToKitchen: sendToKitchen,
    kitchenStatus: kitchenStatus,
    kitchenBatchId: kitchenBatchId,
    sentToKitchenAt: sentToKitchenAt,
    readyAt: readyAt,
    paymentStatus: 'pending',
    status: status,
    cancelStatus: cancelStatus,
    branchId: 'aviacion',
    branchName: 'Aviacion',
  );
}

Payment _payment({required double amount}) {
  return Payment(
    id: 'payment',
    orderId: 'order',
    tableId: 'mesa_1',
    tableName: 'Mesa 1',
    type: 'full',
    method: 'cash',
    baseAmount: amount,
    surchargeRate: 0,
    surchargeAmount: 0,
    chargedAmount: amount,
    status: 'paid',
  );
}
