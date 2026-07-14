import 'package:cloud_firestore/cloud_firestore.dart';

class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.type,
    required this.employeeName,
    required this.actionSource,
    this.orderId,
    this.targetId,
    this.note,
    this.reason,
    this.tableName,
    this.productName,
    this.itemName,
    this.createdAt,
  });

  final String id;
  final String type;
  final String employeeName;
  final String actionSource;
  final String? orderId;
  final String? targetId;
  final String? note;
  final String? reason;
  final String? tableName;
  final String? productName;
  final String? itemName;
  final DateTime? createdAt;

  factory ActivityEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ActivityEvent(
      id: doc.id,
      type: data['type'] as String? ?? 'actividad',
      employeeName:
          data['employeeName'] as String? ??
          data['adminEmployeeName'] as String? ??
          'Empleado',
      actionSource: data['actionSource'] as String? ?? 'app',
      orderId: data['orderId'] as String?,
      targetId: data['targetId'] as String?,
      note: data['note'] as String?,
      reason:
          data['reason'] as String? ??
          data['cancelReason'] as String? ??
          data['cancelRejectReason'] as String?,
      tableName: data['tableName'] as String?,
      productName: data['productName'] as String?,
      itemName: data['itemName'] as String?,
      createdAt: _toDate(data['createdAt'] ?? data['timestamp']),
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
