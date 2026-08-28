import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/services/taco_pos_repository.dart';

OrderItem kitchenItem({int? kitchenSequence, String batchId = 'batch'}) {
  return OrderItem(
    id: 'item-$batchId',
    personNumber: 1,
    personName: 'Adolfo',
    productId: 'pastor',
    productName: 'Pastor',
    category: 'tacos',
    qty: 2,
    unitPrice: 20,
    total: 40,
    notes: '',
    sendToKitchen: true,
    kitchenStatus: 'sent',
    paymentStatus: 'pending',
    kitchenBatchId: batchId,
    kitchenSequence: kitchenSequence,
  );
}

PosOrder kitchenOrder() {
  return const PosOrder(
    id: 'order-1',
    tableId: 'table-4',
    tableName: 'Mesa 4',
    status: 'sent',
    kitchenStatus: 'sent',
    paymentStatus: 'pending',
    total: 40,
    paidTotal: 0,
    pendingTotal: 40,
    personNames: {1: 'Adolfo'},
    orderType: 'dine_in',
  );
}

void main() {
  test('batch exposes its daily kitchen sequence', () {
    final bundle = KitchenOrderBundle(
      order: kitchenOrder(),
      items: [kitchenItem(kitchenSequence: 17)],
    );

    expect(bundle.kitchenSequence, 17);
    expect(bundle.stableKitchenKey, 'order:order-1:batch');
    expect(bundle.personLabel, 'Adolfo');
  });

  test('historical batch without a sequence keeps the fallback identity', () {
    final bundle = KitchenOrderBundle(
      order: kitchenOrder(),
      items: [kitchenItem(kitchenSequence: null)],
    );

    expect(bundle.kitchenSequence, isNull);
    expect(bundle.stableKitchenKey, 'order:order-1:batch');
  });
}
