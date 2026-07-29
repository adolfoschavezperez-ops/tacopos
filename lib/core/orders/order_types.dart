import '../../models/order.dart';
import '../../models/order_platform.dart';
import '../../models/pos_table.dart';

const standingOrderType = 'standing';
const takeoutOrderType = 'takeout';
const dineInOrderType = 'dine_in';

String requireCustomerName(String? value, {required String message}) {
  final clean = value?.trim() ?? '';
  if (clean.isEmpty) throw ArgumentError(message);
  return clean;
}

String normalizeOrderTypeName(Object? value) {
  return value
      .toString()
      .toLowerCase()
      .trim()
      .replaceAll('\u00e1', 'a')
      .replaceAll('\u00e9', 'e')
      .replaceAll('\u00ed', 'i')
      .replaceAll('\u00f3', 'o')
      .replaceAll('\u00fa', 'u')
      .replaceAll('\u00f1', 'n');
}

String normalizeOrderType(Object? value) {
  final normalized = normalizeOrderTypeName(
    value,
  ).replaceAll(RegExp(r'[\s-]+'), '_');
  return switch (normalized) {
    'dine_in' || 'dinein' || 'table' || 'mesa' => 'table',
    'takeout' || 'take_out' || 'takeaway' || 'para_llevar' => takeoutOrderType,
    'standing' ||
    'standing_no_table' ||
    'walk_in_standing' ||
    'parado' ||
    'parados_sin_mesa' => standingOrderType,
    _ => normalized,
  };
}

OrderPlatform? findInPersonPlatform(Iterable<OrderPlatform> platforms) {
  for (final platform in platforms) {
    if (normalizeOrderTypeName(platform.name) == 'en persona') {
      return platform;
    }
  }
  return null;
}

bool isStandingOrder(PosOrder order) =>
    normalizeOrderType(order.orderType) == standingOrderType;

bool isTakeoutOrder(PosOrder order) =>
    normalizeOrderType(order.orderType) == takeoutOrderType;

bool isDineInOrder(PosOrder order) {
  return normalizeOrderType(order.orderType) == 'table';
}

bool isTakeoutEntryTableType(String type) {
  return const {'takeout', 'takeout_entry'}.contains(type.trim());
}

bool orderUsesPhysicalTables(PosOrder order) {
  return isDineInOrder(order) && order.linkedTableIds.isNotEmpty;
}

List<PosTable> tablesStillLinkedToOrder(
  PosOrder order,
  Iterable<PosTable> tables,
) {
  final linkedIds = order.linkedTableIds.toSet();
  return tables
      .where(
        (table) =>
            linkedIds.contains(table.id) &&
            table.currentOrderId?.trim() == order.id.trim(),
      )
      .toList(growable: false);
}

List<String> linkedTableIdsForOrderData(Map<String, dynamic>? data) {
  if (data == null) return const [];
  final orderType = normalizeOrderType(
    data['orderType']?.toString() ?? dineInOrderType,
  );
  if (orderType != 'table') return const [];
  final tableIds = (data['tableIds'] as List?)
      ?.map((value) => value.toString().trim())
      .where((value) => value.isNotEmpty)
      .toList();
  if (tableIds != null && tableIds.isNotEmpty) return tableIds;
  final tableId = data['tableId']?.toString().trim() ?? '';
  return tableId.isEmpty ? const [] : [tableId];
}

class TableJoinDecision {
  const TableJoinDecision({
    required this.allowed,
    required this.baseOrderId,
    required this.message,
  });

  final bool allowed;
  final String? baseOrderId;
  final String message;
}

TableJoinDecision evaluateTableJoinSelection(Iterable<PosTable> tables) {
  final selected = tables.toList();
  if (selected.length < 2) {
    return const TableJoinDecision(
      allowed: false,
      baseOrderId: null,
      message: 'Selecciona al menos dos mesas.',
    );
  }
  if (selected.any((table) => !table.active || !table.isPhysicalTable)) {
    return const TableJoinDecision(
      allowed: false,
      baseOrderId: null,
      message: 'Selecciona únicamente mesas físicas activas.',
    );
  }
  final orderIds = selected
      .map((table) => table.currentOrderId?.trim() ?? '')
      .where((value) => value.isNotEmpty)
      .toSet();
  if (orderIds.length > 1) {
    return const TableJoinDecision(
      allowed: false,
      baseOrderId: null,
      message: 'No se pueden juntar mesas que ya tienen órdenes diferentes.',
    );
  }
  return TableJoinDecision(
    allowed: true,
    baseOrderId: orderIds.isEmpty ? null : orderIds.first,
    message: '',
  );
}
