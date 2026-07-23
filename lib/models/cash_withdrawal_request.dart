import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';

class CashWithdrawalRequest {
  const CashWithdrawalRequest({
    required this.id,
    required this.cashSessionId,
    required this.businessDate,
    required this.amount,
    required this.reason,
    required this.requestedByEmployeeId,
    required this.requestedByEmployeeName,
    required this.status,
    this.requestedAt,
    this.authorizedByEmployeeId,
    this.authorizedByEmployeeName,
    this.authorizedAt,
    this.adminNotes,
    this.approvedByEmployeeId,
    this.approvedByEmployeeName,
    this.approvedAt,
    this.rejectedByEmployeeId,
    this.rejectedByEmployeeName,
    this.rejectedAt,
    this.rejectReason,
    this.restaurantId = AppConstants.restaurantId,
    this.restaurantName = AppConstants.restaurantName,
    this.branchId = AppConstants.defaultBranchId,
    this.branchName = AppConstants.defaultBranchName,
    this.source = '',
    this.sourceName = '',
    this.isHistorical = false,
  });

  final String id;
  final String cashSessionId;
  final String businessDate;
  final double amount;
  final String reason;
  final String requestedByEmployeeId;
  final String requestedByEmployeeName;
  final DateTime? requestedAt;
  final String status;
  final String? authorizedByEmployeeId;
  final String? authorizedByEmployeeName;
  final DateTime? authorizedAt;
  final String? adminNotes;
  final String? approvedByEmployeeId;
  final String? approvedByEmployeeName;
  final DateTime? approvedAt;
  final String? rejectedByEmployeeId;
  final String? rejectedByEmployeeName;
  final DateTime? rejectedAt;
  final String? rejectReason;
  final String restaurantId;
  final String restaurantName;
  final String branchId;
  final String branchName;
  final String source;
  final String sourceName;
  final bool isHistorical;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory CashWithdrawalRequest.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return CashWithdrawalRequest(
      id: doc.id,
      cashSessionId: data['cashSessionId'] as String? ?? '',
      businessDate: data['businessDate'] as String? ?? '',
      amount: _toDouble(data['amount']),
      reason: data['reason'] as String? ?? '',
      requestedByEmployeeId: data['requestedByEmployeeId'] as String? ?? '',
      requestedByEmployeeName: data['requestedByEmployeeName'] as String? ?? '',
      requestedAt: _toDate(data['requestedAt']),
      status: data['status'] as String? ?? 'pending',
      authorizedByEmployeeId: data['authorizedByEmployeeId'] as String?,
      authorizedByEmployeeName: data['authorizedByEmployeeName'] as String?,
      authorizedAt: _toDate(data['authorizedAt']),
      adminNotes: data['adminNotes'] as String?,
      approvedByEmployeeId: data['approvedByEmployeeId'] as String?,
      approvedByEmployeeName: data['approvedByEmployeeName'] as String?,
      approvedAt: _toDate(data['approvedAt']),
      rejectedByEmployeeId: data['rejectedByEmployeeId'] as String?,
      rejectedByEmployeeName: data['rejectedByEmployeeName'] as String?,
      rejectedAt: _toDate(data['rejectedAt']),
      rejectReason:
          data['rejectReason'] as String? ?? data['adminNotes'] as String?,
      restaurantId:
          data['restaurantId'] as String? ?? AppConstants.restaurantId,
      restaurantName:
          data['restaurantName'] as String? ?? AppConstants.restaurantName,
      branchId: data['branchId'] as String? ?? AppConstants.defaultBranchId,
      branchName:
          data['branchName'] as String? ?? AppConstants.defaultBranchName,
      source: data['source'] as String? ?? '',
      sourceName: data['sourceName'] as String? ?? '',
      isHistorical: data['isHistorical'] as bool? ?? false,
    );
  }

  static double _toDouble(Object? value) {
    return value is num ? value.toDouble() : 0;
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }
}
