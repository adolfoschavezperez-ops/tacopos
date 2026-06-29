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
    required this.personNames,
    this.createdAt,
    this.updatedAt,
    this.sentToKitchenAt,
    this.paidAt,
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
  final Map<int, String> personNames;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? sentToKitchenAt;
  final DateTime? paidAt;

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
      personNames: _readPersonNames(data['personNames']),
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
      sentToKitchenAt: _toDate(data['sentToKitchenAt']),
      paidAt: _toDate(data['paidAt']),
    );
  }

  String personName(int personNumber) {
    final custom = personNames[personNumber]?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    return 'Persona $personNumber';
  }

  static Map<int, String> _readPersonNames(Object? value) {
    if (value is! Map) {
      return const {};
    }

    final names = <int, String>{};
    for (final entry in value.entries) {
      final key = int.tryParse(entry.key.toString());
      final name = entry.value?.toString().trim();
      if (key != null && name != null && name.isNotEmpty) {
        names[key] = name;
      }
    }
    return names;
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    return null;
  }
}
