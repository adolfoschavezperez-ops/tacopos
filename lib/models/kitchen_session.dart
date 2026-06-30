import 'package:cloud_firestore/cloud_firestore.dart';

class KitchenSession {
  const KitchenSession({
    required this.id,
    required this.businessDate,
    required this.status,
    required this.notes,
    this.cashSessionId,
    this.openedAt,
    this.openedByEmployeeId,
    this.openedByEmployeeName,
    this.closedAt,
    this.closedByEmployeeId,
    this.closedByEmployeeName,
  });

  final String id;
  final String businessDate;
  final String status;
  final String? cashSessionId;
  final DateTime? openedAt;
  final String? openedByEmployeeId;
  final String? openedByEmployeeName;
  final DateTime? closedAt;
  final String? closedByEmployeeId;
  final String? closedByEmployeeName;
  final String notes;

  bool get isOpen => status == 'open';
  bool get isClosed => status == 'closed';

  factory KitchenSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return KitchenSession(
      id: doc.id,
      businessDate: data['businessDate'] as String? ?? '',
      status: data['status'] as String? ?? 'open',
      cashSessionId: data['cashSessionId'] as String?,
      openedAt: _toDate(data['openedAt']),
      openedByEmployeeId: data['openedByEmployeeId'] as String?,
      openedByEmployeeName: data['openedByEmployeeName'] as String?,
      closedAt: _toDate(data['closedAt']),
      closedByEmployeeId: data['closedByEmployeeId'] as String?,
      closedByEmployeeName: data['closedByEmployeeName'] as String?,
      notes: data['notes'] as String? ?? '',
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }
}

class KitchenSessionItem {
  const KitchenSessionItem({
    required this.id,
    required this.kitchenStockItemId,
    required this.name,
    required this.category,
    required this.unit,
    required this.previousRemainingQty,
    required this.todayInputQty,
    required this.availableQty,
    required this.finalRemainingQty,
    required this.wasteQty,
    required this.usedQty,
    required this.usefulConsumedQty,
    required this.soldQty,
    required this.yieldQtyPerUnit,
    required this.notes,
  });

  final String id;
  final String kitchenStockItemId;
  final String name;
  final String category;
  final String unit;
  final double previousRemainingQty;
  final double todayInputQty;
  final double availableQty;
  final double finalRemainingQty;
  final double wasteQty;
  final double usedQty;
  final double usefulConsumedQty;
  final double soldQty;
  final double yieldQtyPerUnit;
  final String notes;

  factory KitchenSessionItem.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return KitchenSessionItem(
      id: doc.id,
      kitchenStockItemId: data['kitchenStockItemId'] as String? ?? doc.id,
      name: data['name'] as String? ?? doc.id,
      category: data['category'] as String? ?? 'other',
      unit: data['unit'] as String? ?? 'kg',
      previousRemainingQty: _toDouble(data['previousRemainingQty']),
      todayInputQty: _toDouble(data['todayInputQty']),
      availableQty: _toDouble(data['availableQty']),
      finalRemainingQty: _toDouble(data['finalRemainingQty']),
      wasteQty: _toDouble(data['wasteQty']),
      usedQty: _toDouble(data['usedQty']),
      usefulConsumedQty: _toDouble(data['usefulConsumedQty']),
      soldQty: _toDouble(data['soldQty']),
      yieldQtyPerUnit: _toDouble(data['yieldQtyPerUnit']),
      notes: data['notes'] as String? ?? '',
    );
  }

  static double _toDouble(Object? value) {
    return value is num ? value.toDouble() : 0;
  }
}
