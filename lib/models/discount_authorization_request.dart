import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';

class DiscountAuthorizationRequest {
  const DiscountAuthorizationRequest({
    required this.id,
    required this.orderId,
    required this.requestedDiscountType,
    required this.requestedDiscountName,
    required this.requestedDiscountPercent,
    required this.amountBeforeDiscount,
    required this.estimatedDiscountAmount,
    required this.estimatedTotalAfterDiscount,
    required this.requestedPartnerId,
    required this.requestedPartnerName,
    required this.requestReason,
    required this.status,
    this.authorizationMode = '',
    this.discountReason = '',
    this.businessDate = '',
    this.tableId = '',
    this.tableName = '',
    this.orderType = '',
    this.requestedAt,
    this.requestedByEmployeeId = '',
    this.requestedByEmployeeName = '',
    this.approvedAt,
    this.approvedByEmployeeId = '',
    this.approvedByEmployeeName = '',
    this.approvedByPartnerId = '',
    this.approvedByPartnerName = '',
    this.rejectedAt,
    this.rejectedByEmployeeId = '',
    this.rejectedByEmployeeName = '',
    this.rejectedByPartnerId = '',
    this.rejectedByPartnerName = '',
    this.rejectReason = '',
    this.cancelledAt,
    this.cancelledByEmployeeId = '',
    this.cancelledByEmployeeName = '',
    this.cancelReason = '',
    this.usedAt,
    this.usedPaymentId = '',
    this.restaurantId = AppConstants.restaurantId,
    this.restaurantName = AppConstants.restaurantName,
    this.branchId = AppConstants.defaultBranchId,
    this.branchName = AppConstants.defaultBranchName,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String branchId;
  final String branchName;
  final String businessDate;
  final String orderId;
  final String tableId;
  final String tableName;
  final String orderType;
  final String requestedDiscountType;
  final String requestedDiscountName;
  final double requestedDiscountPercent;
  final double amountBeforeDiscount;
  final double estimatedDiscountAmount;
  final double estimatedTotalAfterDiscount;
  final String requestedPartnerId;
  final String requestedPartnerName;
  final String requestReason;
  final String status;
  final String authorizationMode;
  final String discountReason;
  final DateTime? requestedAt;
  final String requestedByEmployeeId;
  final String requestedByEmployeeName;
  final DateTime? approvedAt;
  final String approvedByEmployeeId;
  final String approvedByEmployeeName;
  final String approvedByPartnerId;
  final String approvedByPartnerName;
  final DateTime? rejectedAt;
  final String rejectedByEmployeeId;
  final String rejectedByEmployeeName;
  final String rejectedByPartnerId;
  final String rejectedByPartnerName;
  final String rejectReason;
  final DateTime? cancelledAt;
  final String cancelledByEmployeeId;
  final String cancelledByEmployeeName;
  final String cancelReason;
  final DateTime? usedAt;
  final String usedPaymentId;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved' || status == 'auto_approved';
  bool get isAutoApproved =>
      status == 'auto_approved' || authorizationMode == 'automatic';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';
  bool get isUsed => status == 'used' || usedPaymentId.trim().isNotEmpty;
  bool get isUsable => isApproved && !isUsed;

  factory DiscountAuthorizationRequest.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return DiscountAuthorizationRequest(
      id: doc.id,
      restaurantId:
          data['restaurantId'] as String? ?? AppConstants.restaurantId,
      restaurantName:
          data['restaurantName'] as String? ?? AppConstants.restaurantName,
      branchId: data['branchId'] as String? ?? AppConstants.defaultBranchId,
      branchName:
          data['branchName'] as String? ?? AppConstants.defaultBranchName,
      businessDate: data['businessDate'] as String? ?? '',
      orderId: data['orderId'] as String? ?? '',
      tableId: data['tableId'] as String? ?? '',
      tableName: data['tableName'] as String? ?? '',
      orderType: data['orderType'] as String? ?? '',
      requestedDiscountType:
          data['requestedDiscountType'] as String? ?? 'family_friend_20',
      requestedDiscountName:
          data['requestedDiscountName'] as String? ?? 'Familia / amigos 20%',
      requestedDiscountPercent: _toDouble(data['requestedDiscountPercent']),
      amountBeforeDiscount: _toDouble(data['amountBeforeDiscount']),
      estimatedDiscountAmount: _toDouble(data['estimatedDiscountAmount']),
      estimatedTotalAfterDiscount: _toDouble(
        data['estimatedTotalAfterDiscount'],
      ),
      requestedPartnerId: data['requestedPartnerId'] as String? ?? '',
      requestedPartnerName: data['requestedPartnerName'] as String? ?? '',
      requestReason: data['requestReason'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
      authorizationMode: data['authorizationMode'] as String? ?? '',
      discountReason:
          data['discountReason'] as String? ??
          data['requestReason'] as String? ??
          '',
      requestedAt: _toDate(data['requestedAt']),
      requestedByEmployeeId: data['requestedByEmployeeId'] as String? ?? '',
      requestedByEmployeeName: data['requestedByEmployeeName'] as String? ?? '',
      approvedAt: _toDate(data['approvedAt']),
      approvedByEmployeeId: data['approvedByEmployeeId'] as String? ?? '',
      approvedByEmployeeName: data['approvedByEmployeeName'] as String? ?? '',
      approvedByPartnerId: data['approvedByPartnerId'] as String? ?? '',
      approvedByPartnerName: data['approvedByPartnerName'] as String? ?? '',
      rejectedAt: _toDate(data['rejectedAt']),
      rejectedByEmployeeId: data['rejectedByEmployeeId'] as String? ?? '',
      rejectedByEmployeeName: data['rejectedByEmployeeName'] as String? ?? '',
      rejectedByPartnerId: data['rejectedByPartnerId'] as String? ?? '',
      rejectedByPartnerName: data['rejectedByPartnerName'] as String? ?? '',
      rejectReason: data['rejectReason'] as String? ?? '',
      cancelledAt: _toDate(data['cancelledAt']),
      cancelledByEmployeeId: data['cancelledByEmployeeId'] as String? ?? '',
      cancelledByEmployeeName: data['cancelledByEmployeeName'] as String? ?? '',
      cancelReason: data['cancelReason'] as String? ?? '',
      usedAt: _toDate(data['usedAt']),
      usedPaymentId: data['usedPaymentId'] as String? ?? '',
    );
  }

  static double _toDouble(Object? value) => value is num ? value.toDouble() : 0;

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}
