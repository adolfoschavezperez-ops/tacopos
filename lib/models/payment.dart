import 'package:cloud_firestore/cloud_firestore.dart';

class Payment {
  const Payment({
    required this.id,
    required this.orderId,
    required this.tableId,
    required this.tableName,
    required this.type,
    required this.method,
    required this.baseAmount,
    required this.surchargeRate,
    required this.surchargeAmount,
    required this.chargedAmount,
    this.personNumber,
    this.personName,
    this.employeeId,
    this.employeeName,
    this.platformId,
    this.platformName,
    this.cashSessionId,
    this.businessDate,
    this.cashReceivedAmount,
    this.cashChangeAmount,
    this.createdAt,
    this.createdBy,
  });

  final String id;
  final String orderId;
  final String tableId;
  final String tableName;
  final String type;
  final String method;
  final double baseAmount;
  final double surchargeRate;
  final double surchargeAmount;
  final double chargedAmount;
  final int? personNumber;
  final String? personName;
  final String? employeeId;
  final String? employeeName;
  final String? platformId;
  final String? platformName;
  final String? cashSessionId;
  final String? businessDate;
  final double? cashReceivedAmount;
  final double? cashChangeAmount;
  final DateTime? createdAt;
  final String? createdBy;

  double get amount => baseAmount;

  factory Payment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final legacyAmount = (data['amount'] as num?)?.toDouble();
    final baseAmount =
        (data['baseAmount'] as num?)?.toDouble() ?? legacyAmount ?? 0;
    final surchargeAmount = (data['surchargeAmount'] as num?)?.toDouble() ?? 0;

    return Payment(
      id: doc.id,
      orderId: data['orderId'] as String? ?? '',
      tableId: data['tableId'] as String? ?? '',
      tableName: data['tableName'] as String? ?? '',
      type: data['type'] as String? ?? 'full_table',
      method: data['method'] as String? ?? 'cash',
      baseAmount: baseAmount,
      surchargeRate: (data['surchargeRate'] as num?)?.toDouble() ?? 0,
      surchargeAmount: surchargeAmount,
      chargedAmount:
          (data['chargedAmount'] as num?)?.toDouble() ??
          legacyAmount ??
          baseAmount + surchargeAmount,
      personNumber: (data['personNumber'] as num?)?.toInt(),
      personName: data['personName'] as String?,
      employeeId: data['employeeId'] as String?,
      employeeName: data['employeeName'] as String?,
      platformId: data['platformId'] as String?,
      platformName: data['platformName'] as String?,
      cashSessionId: data['cashSessionId'] as String?,
      businessDate: data['businessDate'] as String?,
      cashReceivedAmount: (data['cashReceivedAmount'] as num?)?.toDouble(),
      cashChangeAmount: (data['cashChangeAmount'] as num?)?.toDouble(),
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
