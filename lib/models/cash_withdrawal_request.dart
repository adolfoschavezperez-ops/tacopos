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
    this.createdAt,
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
    this.policyId = '',
    this.policyVersion = 0,
    this.policyName = '',
    this.policySnapshot = const {},
    this.autoApproved = false,
    this.autoApprovedAt,
    this.wouldAutoApprove = false,
    this.policyEvaluationMode = '',
    this.policyEvaluationReason = '',
    this.policyDecisionReasonCode = '',
    this.policyDecisionMessage = '',
  });

  final String id;
  final String cashSessionId;
  final String businessDate;
  final double amount;
  final String reason;
  final String requestedByEmployeeId;
  final String requestedByEmployeeName;
  final DateTime? requestedAt;
  final DateTime? createdAt;
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
  final String policyId;
  final int policyVersion;
  final String policyName;
  final Map<String, dynamic> policySnapshot;
  final bool autoApproved;
  final DateTime? autoApprovedAt;
  final bool wouldAutoApprove;
  final String policyEvaluationMode;
  final String policyEvaluationReason;
  final String policyDecisionReasonCode;
  final String policyDecisionMessage;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  String get policyOutcomeLabel {
    if (autoApproved) return 'Autoautorizado';
    if (wouldAutoApprove) return 'Cumpliria politica';
    if (policyId.trim().isEmpty) return 'Manual';
    return 'No cumplio politica';
  }

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
      createdAt: _toDate(data['createdAt']),
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
      policyId: data['policyId'] as String? ?? '',
      policyVersion: data['policyVersion'] is num
          ? (data['policyVersion'] as num).toInt()
          : 0,
      policyName: data['policyName'] as String? ?? '',
      policySnapshot: data['policySnapshot'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(
              data['policySnapshot'] as Map<String, dynamic>,
            )
          : const {},
      autoApproved: data['autoApproved'] as bool? ?? false,
      autoApprovedAt: _toDate(data['autoApprovedAt']),
      wouldAutoApprove: data['wouldAutoApprove'] as bool? ?? false,
      policyEvaluationMode: data['policyEvaluationMode'] as String? ?? '',
      policyEvaluationReason: data['policyEvaluationReason'] as String? ?? '',
      policyDecisionReasonCode:
          data['policyDecisionReasonCode'] as String? ?? '',
      policyDecisionMessage: data['policyDecisionMessage'] as String? ?? '',
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
