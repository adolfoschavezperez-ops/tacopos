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
    this.appliedAmount,
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
    this.subtotalBeforeDiscount = 0,
    this.discountAmount = 0,
    this.totalAfterDiscount = 0,
    this.appliedDiscountType,
    this.appliedDiscountName,
    this.appliedDiscountPercent = 0,
    this.discountApplied = false,
    this.discountSource,
    this.discountCatalogId,
    this.discountName,
    this.discountPercent = 0,
    this.orderDiscountAmount = 0,
    this.orderGrossSubtotal = 0,
    this.orderNetTotal = 0,
    this.discountAuthorizedByPartnerId,
    this.discountAuthorizedByPartnerName,
    this.discountAuthorizedByPartnerLinkedEmployeeId,
    this.discountAuthorizedByPartnerLinkedEmployeeName,
    this.discountEmployeeBeneficiaryId,
    this.discountEmployeeBeneficiaryName,
    this.discountAuthorizationRequestId,
    this.discountAuthorizationMode,
    this.discountAuthorizationStatus,
    this.discountReason,
    this.createdAt,
    this.createdBy,
    this.status = 'active',
    this.cancelledAt,
    this.cancelledByEmployeeId,
    this.cancelledByEmployeeName,
    this.cancelReason,
    this.saleFolioSequence,
    this.saleFolioDisplay,
    this.saleFolioFull,
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
  final double? appliedAmount;
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
  final double subtotalBeforeDiscount;
  final double discountAmount;
  final double totalAfterDiscount;
  final String? appliedDiscountType;
  final String? appliedDiscountName;
  final double appliedDiscountPercent;
  final bool discountApplied;
  final String? discountSource;
  final String? discountCatalogId;
  final String? discountName;
  final double discountPercent;
  final double orderDiscountAmount;
  final double orderGrossSubtotal;
  final double orderNetTotal;
  final String? discountAuthorizedByPartnerId;
  final String? discountAuthorizedByPartnerName;
  final String? discountAuthorizedByPartnerLinkedEmployeeId;
  final String? discountAuthorizedByPartnerLinkedEmployeeName;
  final String? discountEmployeeBeneficiaryId;
  final String? discountEmployeeBeneficiaryName;
  final String? discountAuthorizationRequestId;
  final String? discountAuthorizationMode;
  final String? discountAuthorizationStatus;
  final String? discountReason;
  final DateTime? createdAt;
  final String? createdBy;
  final String status;
  final DateTime? cancelledAt;
  final String? cancelledByEmployeeId;
  final String? cancelledByEmployeeName;
  final String? cancelReason;
  final int? saleFolioSequence;
  final String? saleFolioDisplay;
  final String? saleFolioFull;
  final String restaurantId;
  final String restaurantName;
  final String branchId;
  final String branchName;

  double get amount => baseAmount;
  bool get isActive => status == 'active';
  bool get isCancelled => status == 'cancelled';

  Payment copyWith({
    String? orderId,
    String? tableId,
    String? tableName,
    String? cashSessionId,
    String? businessDate,
    String? restaurantId,
    String? restaurantName,
    String? branchId,
    String? branchName,
  }) {
    return Payment(
      id: id,
      orderId: orderId ?? this.orderId,
      tableId: tableId ?? this.tableId,
      tableName: tableName ?? this.tableName,
      type: type,
      method: method,
      baseAmount: baseAmount,
      surchargeRate: surchargeRate,
      surchargeAmount: surchargeAmount,
      chargedAmount: chargedAmount,
      appliedAmount: appliedAmount,
      cardFeeRate: cardFeeRate,
      cardFeeAbsorbedAmount: cardFeeAbsorbedAmount,
      personNumber: personNumber,
      personName: personName,
      employeeId: employeeId,
      employeeName: employeeName,
      platformId: platformId,
      platformName: platformName,
      cashSessionId: cashSessionId ?? this.cashSessionId,
      businessDate: businessDate ?? this.businessDate,
      cashReceivedAmount: cashReceivedAmount,
      cashChangeAmount: cashChangeAmount,
      subtotalBeforeDiscount: subtotalBeforeDiscount,
      discountAmount: discountAmount,
      totalAfterDiscount: totalAfterDiscount,
      appliedDiscountType: appliedDiscountType,
      appliedDiscountName: appliedDiscountName,
      appliedDiscountPercent: appliedDiscountPercent,
      discountApplied: discountApplied,
      discountSource: discountSource,
      discountCatalogId: discountCatalogId,
      discountName: discountName,
      discountPercent: discountPercent,
      orderDiscountAmount: orderDiscountAmount,
      orderGrossSubtotal: orderGrossSubtotal,
      orderNetTotal: orderNetTotal,
      discountAuthorizedByPartnerId: discountAuthorizedByPartnerId,
      discountAuthorizedByPartnerName: discountAuthorizedByPartnerName,
      discountAuthorizedByPartnerLinkedEmployeeId:
          discountAuthorizedByPartnerLinkedEmployeeId,
      discountAuthorizedByPartnerLinkedEmployeeName:
          discountAuthorizedByPartnerLinkedEmployeeName,
      discountEmployeeBeneficiaryId: discountEmployeeBeneficiaryId,
      discountEmployeeBeneficiaryName: discountEmployeeBeneficiaryName,
      discountAuthorizationRequestId: discountAuthorizationRequestId,
      discountAuthorizationMode: discountAuthorizationMode,
      discountAuthorizationStatus: discountAuthorizationStatus,
      discountReason: discountReason,
      createdAt: createdAt,
      createdBy: createdBy,
      status: status,
      cancelledAt: cancelledAt,
      cancelledByEmployeeId: cancelledByEmployeeId,
      cancelledByEmployeeName: cancelledByEmployeeName,
      cancelReason: cancelReason,
      saleFolioSequence: saleFolioSequence,
      saleFolioDisplay: saleFolioDisplay,
      saleFolioFull: saleFolioFull,
      restaurantId: restaurantId ?? this.restaurantId,
      restaurantName: restaurantName ?? this.restaurantName,
      branchId: branchId ?? this.branchId,
      branchName: branchName ?? this.branchName,
    );
  }

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
      appliedAmount: (data['appliedAmount'] as num?)?.toDouble(),
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
      subtotalBeforeDiscount:
          (data['subtotalBeforeDiscount'] as num?)?.toDouble() ?? baseAmount,
      discountAmount: (data['discountAmount'] as num?)?.toDouble() ?? 0,
      totalAfterDiscount:
          (data['totalAfterDiscount'] as num?)?.toDouble() ??
          (data['chargedAmount'] as num?)?.toDouble() ??
          baseAmount,
      appliedDiscountType: data['appliedDiscountType'] as String?,
      appliedDiscountName: data['appliedDiscountName'] as String?,
      appliedDiscountPercent:
          (data['appliedDiscountPercent'] as num?)?.toDouble() ?? 0,
      discountApplied: data['discountApplied'] as bool? ?? false,
      discountSource: data['discountSource'] as String?,
      discountCatalogId: data['discountCatalogId'] as String?,
      discountName:
          data['discountName'] as String? ??
          data['appliedDiscountName'] as String?,
      discountPercent:
          (data['discountPercent'] as num?)?.toDouble() ??
          (data['appliedDiscountPercent'] as num?)?.toDouble() ??
          0,
      orderDiscountAmount:
          (data['orderDiscountAmount'] as num?)?.toDouble() ?? 0,
      orderGrossSubtotal: (data['orderGrossSubtotal'] as num?)?.toDouble() ?? 0,
      orderNetTotal: (data['orderNetTotal'] as num?)?.toDouble() ?? 0,
      discountAuthorizedByPartnerId:
          data['discountAuthorizedByPartnerId'] as String?,
      discountAuthorizedByPartnerName:
          data['discountAuthorizedByPartnerName'] as String?,
      discountAuthorizedByPartnerLinkedEmployeeId:
          data['discountAuthorizedByPartnerLinkedEmployeeId'] as String?,
      discountAuthorizedByPartnerLinkedEmployeeName:
          data['discountAuthorizedByPartnerLinkedEmployeeName'] as String?,
      discountEmployeeBeneficiaryId:
          data['discountEmployeeBeneficiaryId'] as String?,
      discountEmployeeBeneficiaryName:
          data['discountEmployeeBeneficiaryName'] as String?,
      discountAuthorizationRequestId:
          data['discountAuthorizationRequestId'] as String?,
      discountAuthorizationMode: data['discountAuthorizationMode'] as String?,
      discountAuthorizationStatus:
          data['discountAuthorizationStatus'] as String?,
      discountReason: data['discountReason'] as String?,
      createdAt: _toDate(data['createdAt']),
      createdBy: data['createdBy'] as String?,
      status: data['status'] as String? ?? 'active',
      cancelledAt: _toDate(data['cancelledAt']),
      cancelledByEmployeeId: data['cancelledByEmployeeId'] as String?,
      cancelledByEmployeeName: data['cancelledByEmployeeName'] as String?,
      cancelReason: data['cancelReason'] as String?,
      saleFolioSequence: (data['saleFolioSequence'] as num?)?.toInt(),
      saleFolioDisplay: data['saleFolioDisplay'] as String?,
      saleFolioFull: data['saleFolioFull'] as String?,
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
