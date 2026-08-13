import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/pos_table.dart';
import 'order_activity.dart';

const tableStatusAvailable = 'available';
const tableStatusInKitchen = 'sent';
const tableStatusPreparing = 'cooking';
const tableStatusReadyToCharge = 'ready';

String waiterTableStatusKey({
  required PosTable table,
  required PosOrder? order,
  required Iterable<OrderItem> items,
}) {
  if (!table.active || !table.isPhysicalTable) {
    return tableStatusAvailable;
  }
  if (order == null || !isActiveOrderState(order)) {
    return tableStatusAvailable;
  }

  final activeItems = items.where(isActiveOrderItem).toList(growable: false);
  final kitchenItems = activeItems
      .where(itemRequiresKitchen)
      .toList(growable: false);

  if (kitchenItems.any(_itemIsPreparing)) {
    return tableStatusPreparing;
  }
  if (kitchenItems.any(
    (item) => itemIsAwaitingKitchenSend(item) || isKitchenPendingItem(item),
  )) {
    return tableStatusInKitchen;
  }
  if (kitchenItems.isNotEmpty &&
      kitchenItems.every(isKitchenReadyItem) &&
      order.pendingTotal > ghostOrderTolerance) {
    return tableStatusReadyToCharge;
  }
  if (kitchenItems.isEmpty &&
      activeItems.isNotEmpty &&
      order.pendingTotal > ghostOrderTolerance) {
    return tableStatusReadyToCharge;
  }

  return tableStatusInKitchen;
}

bool _itemIsPreparing(OrderItem item) {
  if (!isActiveOrderItem(item) || !itemRequiresKitchen(item)) {
    return false;
  }
  final status = normalizeOperationalStatus(
    item.kitchenStatus,
  ).replaceAll(RegExp(r'[\s-]+'), '_');
  return item.cookingAt != null ||
      status == 'cooking' ||
      status == 'cocinando' ||
      status == 'preparing' ||
      status == 'preparando' ||
      status == 'en_preparacion';
}
