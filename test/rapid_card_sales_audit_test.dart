import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/rapid_card_sales_audit.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/payment.dart';

void main() {
  group('rapid card sales audit', () {
    test('detects a card sale created, served and paid inside 60 seconds', () {
      final created = DateTime(2026, 9, 28, 21, 10, 0);
      final sent = created.add(const Duration(seconds: 12));
      final ready = created.add(const Duration(seconds: 38));
      final paid = created.add(const Duration(seconds: 52));

      final order = _order(
        createdAt: created,
        sentToKitchenAt: sent,
        paidAt: paid,
      );
      final item = _item(
        createdAt: created.add(const Duration(seconds: 5)),
        sentToKitchenAt: sent,
        readyAt: ready,
        paidAt: paid,
      );
      final payment = _payment(createdAt: paid);

      final rows = buildRapidCardSalesAudit(
        orders: [order],
        itemsByOrder: {
          order.id: [item],
        },
        paymentsByOrder: {
          order.id: [payment],
        },
      );

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.orderToPayment?.inSeconds, 52);
      expect(row.lastItemToPayment?.inSeconds, 47);
      expect(row.kitchenSendToPayment?.inSeconds, 40);
      expect(row.lastReadyToPayment?.inSeconds, 14);
      expect(row.matchesSeconds(60), isTrue);
      expect(row.kitchenCompleteBeforePayment, isTrue);
      expect(row.isStrongRapidKitchenMatch, isTrue);
    });

    test('keeps rapid card sale when kitchen ready timestamp is missing', () {
      final created = DateTime(2026, 9, 28, 21, 10, 0);
      final paid = created.add(const Duration(seconds: 45));
      final order = _order(createdAt: created, paidAt: paid);
      final item = _item(
        createdAt: created.add(const Duration(seconds: 4)),
        sentToKitchenAt: created.add(const Duration(seconds: 10)),
      );

      final rows = buildRapidCardSalesAudit(
        orders: [order],
        itemsByOrder: {
          order.id: [item],
        },
        paymentsByOrder: {
          order.id: [_payment(createdAt: paid)],
        },
      );

      expect(rows.single.matchesSeconds(60), isTrue);
      expect(rows.single.kitchenCompleteBeforePayment, isFalse);
      expect(rows.single.readyKitchenItems, 0);
    });

    test('can measure from last captured item for an older open order', () {
      final created = DateTime(2026, 9, 28, 20, 30, 0);
      final lastItem = DateTime(2026, 9, 28, 21, 10, 30);
      final paid = DateTime(2026, 9, 28, 21, 11, 0);
      final order = _order(createdAt: created, paidAt: paid);
      final item = _item(
        createdAt: lastItem,
        sentToKitchenAt: lastItem.add(const Duration(seconds: 5)),
        readyAt: lastItem.add(const Duration(seconds: 20)),
      );

      final rows = buildRapidCardSalesAudit(
        orders: [order],
        itemsByOrder: {
          order.id: [item],
        },
        paymentsByOrder: {
          order.id: [_payment(createdAt: paid)],
        },
      );

      final row = rows.single;
      expect(row.matchesSeconds(60), isFalse);
      expect(
        row.matchesSeconds(
          60,
          basis: RapidCardAuditTimingBasis.lastItemCaptured,
        ),
        isTrue,
      );
    });

    test('ignores cash and cancelled card payments', () {
      final created = DateTime(2026, 9, 28, 21, 10, 0);
      final paid = created.add(const Duration(seconds: 30));
      final order = _order(createdAt: created, paidAt: paid);

      final rows = buildRapidCardSalesAudit(
        orders: [order],
        itemsByOrder: {
          order.id: [_item(createdAt: created)],
        },
        paymentsByOrder: {
          order.id: [
            _payment(createdAt: paid, method: 'cash'),
            _payment(
              id: 'cancelled-card',
              createdAt: paid,
              status: 'cancelled',
            ),
          ],
        },
      );

      expect(rows, isEmpty);
    });

    test('ignores cancelled orders', () {
      final created = DateTime(2026, 9, 28, 21, 10, 0);
      final paid = created.add(const Duration(seconds: 30));
      final order = _order(
        createdAt: created,
        paidAt: paid,
        status: 'cancelled',
      );

      final rows = buildRapidCardSalesAudit(
        orders: [order],
        itemsByOrder: {
          order.id: [_item(createdAt: created)],
        },
        paymentsByOrder: {
          order.id: [_payment(createdAt: paid)],
        },
      );

      expect(rows, isEmpty);
    });
  });
}

PosOrder _order({
  DateTime? createdAt,
  DateTime? sentToKitchenAt,
  DateTime? paidAt,
  String status = 'paid',
}) {
  return PosOrder(
    id: 'order-1',
    tableId: 'mesa-1',
    tableName: 'Mesa 1',
    status: status,
    kitchenStatus: 'ready',
    paymentStatus: status == 'cancelled' ? 'cancelled' : 'paid',
    total: 100,
    paidTotal: status == 'cancelled' ? 0 : 100,
    pendingTotal: 0,
    personNames: const {1: 'Persona 1'},
    orderType: 'dine_in',
    createdAt: createdAt,
    sentToKitchenAt: sentToKitchenAt,
    paidAt: paidAt,
    saleFolioDisplay: '0012',
    saleFolioFull: 'AVI-2026-09-28-0012',
  );
}

OrderItem _item({
  DateTime? createdAt,
  DateTime? sentToKitchenAt,
  DateTime? readyAt,
  DateTime? paidAt,
}) {
  return OrderItem(
    id: 'item-1',
    personNumber: 1,
    personName: 'Persona 1',
    productId: 'taco-bistec',
    productName: 'Taco bistec',
    category: 'Tacos',
    qty: 4,
    unitPrice: 25,
    total: 100,
    notes: '',
    sendToKitchen: true,
    kitchenStatus: readyAt == null ? 'cooking' : 'ready',
    paymentStatus: paidAt == null ? 'pending' : 'paid',
    createdAt: createdAt,
    sentToKitchenAt: sentToKitchenAt,
    readyAt: readyAt,
    paidAt: paidAt,
  );
}

Payment _payment({
  String id = 'payment-1',
  DateTime? createdAt,
  String method = 'card',
  String status = 'active',
}) {
  return Payment(
    id: id,
    orderId: 'order-1',
    tableId: 'mesa-1',
    tableName: 'Mesa 1',
    type: 'full_table',
    method: method,
    baseAmount: 100,
    surchargeRate: method == 'card' ? 0.04 : 0,
    surchargeAmount: method == 'card' ? 4 : 0,
    chargedAmount: method == 'card' ? 104 : 100,
    employeeName: 'Andrés',
    createdAt: createdAt,
    status: status,
    saleFolioDisplay: '0012',
    saleFolioFull: 'AVI-2026-09-28-0012',
  );
}
