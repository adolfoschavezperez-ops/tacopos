import 'package:cloud_firestore/cloud_firestore.dart';

class PosOrder {
  const PosOrder({
    required this.id,
    required this.tableId,
    required this.tableName,
    required this.status,
    required this.kitchenStatus,
    required this.paymentStatus,
    required this.total,
    required this.paidTotal,
    required this.pendingTotal,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String tableId;
  final String tableName;
  final String status;
  final String kitchenStatus;
  final String paymentStatus;
  final double total;
  final double paidTotal;
  final double pendingTotal;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PosOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return PosOrder(
      id: doc.id,
      tableId: data['tableId'] as String? ?? '',
      tableName: data['tableName'] as String? ?? 'Mesa',
      status: data['status'] as String? ?? 'open',
      kitchenStatus: data['kitchenStatus'] as String? ?? 'pending',
      paymentStatus: data['paymentStatus'] as String? ?? 'pending',
      total: (data['total'] as num?)?.toDouble() ?? 0,
      paidTotal: (data['paidTotal'] as num?)?.toDouble() ?? 0,
      pendingTotal: (data['pendingTotal'] as num?)?.toDouble() ?? 0,
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    return null;
  }
}
