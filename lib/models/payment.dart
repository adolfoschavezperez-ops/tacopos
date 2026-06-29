import 'package:cloud_firestore/cloud_firestore.dart';

class Payment {
  const Payment({
    required this.id,
    required this.orderId,
    required this.tableId,
    required this.tableName,
    required this.type,
    required this.method,
    required this.amount,
    this.personNumber,
    this.personName,
    this.createdAt,
    this.createdBy,
  });

  final String id;
  final String orderId;
  final String tableId;
  final String tableName;
  final String type;
  final String method;
  final double amount;
  final int? personNumber;
  final String? personName;
  final DateTime? createdAt;
  final String? createdBy;

  factory Payment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return Payment(
      id: doc.id,
      orderId: data['orderId'] as String? ?? '',
      tableId: data['tableId'] as String? ?? '',
      tableName: data['tableName'] as String? ?? '',
      type: data['type'] as String? ?? 'full_table',
      method: data['method'] as String? ?? 'cash',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      personNumber: (data['personNumber'] as num?)?.toInt(),
      personName: data['personName'] as String?,
      createdAt: _toDate(data['createdAt']),
      createdBy: data['createdBy'] as String?,
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    return null;
  }
}
