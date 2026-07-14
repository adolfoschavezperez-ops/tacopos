import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';

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
    this.cardFeeRate = 0,
    this.cardFeeAbsorbedAmount = 0,
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
    this.status = 'active',
    this.cancelledAt,
    this.cancelledByEmployeeId,
    this.cancelledByEmployeeName,
    this.cancelReason,
    this.restaurantId = AppConstants.restaurantId,
    this.restaurantName = AppConstants.restaurantName,
    this.branchId = AppConstants.defaultBranchId,
    this.branchName = AppConstants.defaultBranchName,
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
  final double cardFeeRate;
  final double cardFeeAbsorbedAmount;
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
  final String status;
  final DateTime? cancelledAt;
  final String? cancelledByEmployeeId;
  final String? cancelledByEmployeeName;
  final String? cancelReason;
  final String restaurantId;
  final String restaurantName;
  final String branchId;
  final String branchName;

  double get amount => baseAmount;
  bool get isActive => status == 'active';
  bool get isCancelled => status == 'cancelled';

  factory Payment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final legacyAmount = (data['amount'] as num?)?.toDouble();
    final baseAmount =
        (data['baseAmount'] as num?)?.toDouble() ?? legacyAmount ?? 0;
    final surchargeAmount = (data['surchargeAmount'] as num?)?.toDouble() ?? 0;
    final method = data['method'] as String? ?? 'cash';
    final cardFeeAbsorbedAmount =
        (data['cardFeeAbsorbedAmount'] as num?)?.toDouble() ??
        (method == 'card' && surchargeAmount > 0 ? surchargeAmount : 0);

    return Payment(
      id: doc.id,
      orderId: data['orderId'] as String? ?? '',
      tableId: data['tableId'] as String? ?? '',
      tableName: data['tableName'] as String? ?? '',
      type: data['type'] as String? ?? 'full_table',
      method: method,
      baseAmount: baseAmount,
      surchargeRate: (data['surchargeRate'] as num?)?.toDouble() ?? 0,
      surchargeAmount: surchargeAmount,
      chargedAmount:
          (data['chargedAmount'] as num?)?.toDouble() ??
          legacyAmount ??
          baseAmount + surchargeAmount,
      cardFeeRate:
          (data['cardFeeRate'] as num?)?.toDouble() ??
          (cardFeeAbsorbedAmount > 0 && baseAmount > 0
              ? cardFeeAbsorbedAmount / baseAmount
              : 0),
      cardFeeAbsorbedAmount: cardFeeAbsorbedAmount,
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
      status: data['status'] as String? ?? 'active',
      cancelledAt: _toDate(data['cancelledAt']),
      cancelledByEmployeeId: data['cancelledByEmployeeId'] as String?,
      cancelledByEmployeeName: data['cancelledByEmployeeName'] as String?,
      cancelReason: data['cancelReason'] as String?,
      restaurantId:
          data['restaurantId'] as String? ?? AppConstants.restaurantId,
      restaurantName:
          data['restaurantName'] as String? ?? AppConstants.restaurantName,
      branchId: data['branchId'] as String? ?? AppConstants.defaultBranchId,
      branchName:
          data['branchName'] as String? ?? AppConstants.defaultBranchName,
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    return null;
  }
}
