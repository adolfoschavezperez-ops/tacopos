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
    required this.orderType,
    this.platformId,
    this.platformName,
    this.takeoutNumber,
    this.customerName,
    this.createdAt,
    this.updatedAt,
    this.sentToKitchenAt,
    this.paidAt,
    this.cancelledAt,
    this.canceledAt,
    this.closedAt,
    this.cancelledByEmployeeId,
    this.cancelledByEmployeeName,
    this.cancelReason,
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
  final String orderType;
  final String? platformId;
  final String? platformName;
  final int? takeoutNumber;
  final String? customerName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? sentToKitchenAt;
  final DateTime? paidAt;
  final DateTime? cancelledAt;
  final DateTime? canceledAt;
  final DateTime? closedAt;
  final String? cancelledByEmployeeId;
  final String? cancelledByEmployeeName;
  final String? cancelReason;

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
      orderType: data['orderType'] as String? ?? 'dine_in',
      platformId: data['platformId'] as String?,
      platformName: data['platformName'] as String?,
      takeoutNumber: (data['takeoutNumber'] as num?)?.toInt(),
      customerName: data['customerName'] as String?,
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
      sentToKitchenAt: _toDate(data['sentToKitchenAt']),
      paidAt: _toDate(data['paidAt']),
      cancelledAt: _toDate(data['cancelledAt']),
      canceledAt: _toDate(data['canceledAt']),
      closedAt: _toDate(data['closedAt']),
      cancelledByEmployeeId: data['cancelledByEmployeeId'] as String?,
      cancelledByEmployeeName: data['cancelledByEmployeeName'] as String?,
      cancelReason: data['cancelReason'] as String?,
    );
  }

  String personName(int personNumber) {
    final custom = personNames[personNumber]?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    return 'Persona $personNumber';
  }

  String get displayName {
    if (orderType == 'takeout') {
      final platform = platformName?.trim();
      final number = takeoutNumber == null ? '' : ' · #$takeoutNumber';
      if (platform != null && platform.isNotEmpty) {
        return 'Para llevar · $platform$number';
      }
      return 'Para llevar$number';
    }
    return tableName;
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
