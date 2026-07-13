import 'package:cloud_firestore/cloud_firestore.dart';

class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.type,
    required this.employeeName,
    required this.actionSource,
    this.orderId,
    this.createdAt,
  });

  final String id;
  final String type;
  final String employeeName;
  final String actionSource;
  final String? orderId;
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
      createdAt: _toDate(data['createdAt'] ?? data['timestamp']),
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
