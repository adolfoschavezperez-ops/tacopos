import 'expense_policy.dart';

const autoPolicyEmployeeId = 'auto_policy';
const autoPolicyEmployeeName = 'Politica de gasto';
const devicePolicyApprovalSource = 'device_policy';

class LocalExpenseRequestInput {
  const LocalExpenseRequestInput({
    required this.restaurantId,
    required this.branchId,
    required this.branchName,
    required this.cashSessionId,
    required this.businessDate,
    required this.amount,
    required this.reason,
    required this.policy,
    required this.settings,
    required this.paymentSource,
    required this.clientRequestId,
    required this.requesterId,
    required this.requesterName,
    required this.requesterRole,
    required this.deviceId,
    this.restaurantName = '',
    this.supplierId = '',
    this.receiptReference = '',
    this.hasReceipt = false,
    this.additionalNotes = '',
    this.requestedAt,
  });

  final String restaurantId;
  final String restaurantName;
  final String branchId;
  final String branchName;
  final String cashSessionId;
  final String businessDate;
  final double amount;
  final String reason;
  final ExpensePolicy policy;
  final ExpensePolicySettings settings;
  final String paymentSource;
  final String supplierId;
  final String receiptReference;
  final bool hasReceipt;
  final String additionalNotes;
  final String clientRequestId;
  final String requesterId;
  final String requesterName;
  final String requesterRole;
  final String deviceId;
  final DateTime? requestedAt;
}

class LocalExpenseTransactionPlan {
  const LocalExpenseTransactionPlan({
    required this.requestId,
    required this.status,
    required this.liveApproved,
    required this.wouldAutoApprove,
    required this.decision,
    required this.periodKey,
    required this.usageDocId,
    required this.requestData,
    required this.activityLogData,
    this.usageData,
  });

  final String requestId;
  final String status;
  final bool liveApproved;
  final bool wouldAutoApprove;
  final ExpensePolicyDecision decision;
  final String periodKey;
  final String usageDocId;
  final Map<String, Object?> requestData;
  final Map<String, Object?>? usageData;
  final Map<String, Object?> activityLogData;

  Map<String, Object?> result(double previousAmountUsed) {
    return {
      'requestId': requestId,
      'expenseId': requestId,
      'status': status,
      'autoApproved': liveApproved,
      'wouldAutoApprove': wouldAutoApprove,
      'policyId': requestData['policyId'],
      'policyVersion': requestData['policyVersion'],
      'reason': decision.message,
      'reasonCode': decision.reasonCode,
      'periodUsage': liveApproved
          ? (usageData?['amountUsed'] as double? ?? previousAmountUsed)
          : previousAmountUsed,
      'periodLimit': requestData['policySnapshot'] is Map
          ? (requestData['policySnapshot'] as Map)['maxAmountPerPeriodSnapshot']
          : 0,
    };
  }
}

LocalExpenseTransactionPlan buildLocalExpenseTransactionPlan({
  required LocalExpenseRequestInput input,
  required ExpensePolicyUsage usage,
  required Object serverTimestamp,
}) {
  final decision = evaluateExpensePolicy(
    ExpensePolicyEvaluationInput(
      settings: input.settings,
      policy: input.policy,
      usage: usage,
      amount: input.amount,
      businessDate: input.businessDate,
      requestedAt: input.requestedAt ?? DateTime.now(),
      paymentSource: input.paymentSource,
      supplierId: input.supplierId,
      requesterRole: input.requesterRole,
      requesterId: input.requesterId,
      hasReceipt: input.hasReceipt || input.receiptReference.trim().isNotEmpty,
      reason: input.reason,
    ),
  );
  final mode = input.settings.expensePolicyMode;
  final liveApproved = mode == ExpensePolicyMode.live && decision.autoApproved;
  final shadowWouldApprove =
      mode == ExpensePolicyMode.shadow && decision.autoApproved;
  final status = liveApproved ? 'approved' : 'pending';
  final requestId = input.clientRequestId.trim();
  final snapshot = input.policy.snapshotForExpense();
  final requestData = <String, Object?>{
    'id': requestId,
    'cashSessionId': input.cashSessionId,
    'businessDate': input.businessDate,
    'restaurantId': input.restaurantId,
    if (input.restaurantName.trim().isNotEmpty)
      'restaurantName': input.restaurantName,
    'branchId': input.branchId,
    if (input.branchName.trim().isNotEmpty) 'branchName': input.branchName,
    'amount': money(input.amount),
    'reason': input.reason.trim(),
    'additionalNotes': input.additionalNotes.trim(),
    'source': input.paymentSource,
    'sourceName': input.paymentSource,
    'supplierId': input.supplierId.trim(),
    'receiptReference': input.receiptReference.trim(),
    'hasReceipt': input.hasReceipt || input.receiptReference.trim().isNotEmpty,
    'requestedByEmployeeId': input.requesterId,
    'requestedByEmployeeName': input.requesterName,
    'requestedByDeviceId': input.deviceId,
    'requestedAt': serverTimestamp,
    'status': status,
    'authorizedByEmployeeId': liveApproved ? autoPolicyEmployeeId : null,
    'authorizedByEmployeeName': liveApproved ? autoPolicyEmployeeName : null,
    'authorizedAt': liveApproved ? serverTimestamp : null,
    'approvalSource': liveApproved ? devicePolicyApprovalSource : null,
    'adminNotes': null,
    'approvedAt': liveApproved ? serverTimestamp : null,
    'approvedByEmployeeId': liveApproved ? autoPolicyEmployeeId : null,
    'approvedByEmployeeName': liveApproved ? autoPolicyEmployeeName : null,
    'rejectedAt': null,
    'rejectedByEmployeeId': null,
    'rejectedByEmployeeName': null,
    'rejectReason': null,
    'policyId': input.policy.id,
    'policyVersion': input.policy.policyVersion,
    'policyName': input.policy.name,
    'policySnapshot': snapshot,
    'autoApproved': liveApproved,
    'autoApprovedAt': liveApproved ? serverTimestamp : null,
    'wouldAutoApprove': shadowWouldApprove,
    'policyEvaluationMode': mode.name,
    'policyDecisionReasonCode': decision.reasonCode,
    'policyDecisionMessage': decision.message,
    'policyEvaluationReason': decision.message,
    'clientRequestId': requestId,
    'createdAt': serverTimestamp,
    'updatedAt': serverTimestamp,
  };
  final periodKey = decision.periodKey;
  final nextAmountUsed = money(usage.amountUsed + input.amount);
  final nextUsesUsed = usage.usesUsed + 1;
  final usageData = liveApproved
      ? <String, Object?>{
          'policyId': input.policy.id,
          'branchId': input.policy.branchId,
          'periodKey': periodKey,
          'amountUsed': nextAmountUsed,
          'usesUsed': nextUsesUsed,
          'expenseIds': [
            ...usage.expenseIds.where((id) => id != requestId),
            requestId,
          ],
          'updatedAt': serverTimestamp,
        }
      : null;
  return LocalExpenseTransactionPlan(
    requestId: requestId,
    status: status,
    liveApproved: liveApproved,
    wouldAutoApprove: shadowWouldApprove,
    decision: decision,
    periodKey: periodKey,
    usageDocId: expensePolicyUsageDocId(
      policyId: input.policy.id,
      branchId: input.policy.branchId,
      periodKey: periodKey,
    ),
    requestData: requestData,
    usageData: usageData,
    activityLogData: {
      'type': liveApproved
          ? 'EXPENSE_AUTO_APPROVED_DEVICE'
          : shadowWouldApprove
          ? 'EXPENSE_POLICY_SHADOW_MATCH'
          : 'EXPENSE_SENT_TO_MANUAL_APPROVAL',
      'restaurantId': input.restaurantId,
      'branchId': input.branchId,
      'expenseId': requestId,
      'policyId': input.policy.id,
      'policyName': input.policy.name,
      'policyVersion': input.policy.policyVersion,
      'policyDecisionReasonCode': decision.reasonCode,
      'policyDecisionMessage': decision.message,
      'policyEvaluationMode': mode.name,
      'amount': money(input.amount),
      'employeeId': input.requesterId,
      'employeeName': input.requesterName,
      'deviceId': input.deviceId,
      'approvalSource': liveApproved ? devicePolicyApprovalSource : null,
      'createdAt': serverTimestamp,
    },
  );
}

Map<String, Object?> buildCancelledExpenseUpdate({
  required Object serverTimestamp,
  required String cancelledByUid,
  required String reason,
  required bool quotaRestored,
  required int policyVersion,
}) {
  return {
    'status': 'cancelled',
    'cancelledAt': serverTimestamp,
    'cancelledByUid': cancelledByUid,
    'cancellationReason': reason.trim(),
    'quotaRestored': quotaRestored,
    'cancelledPolicyVersion': policyVersion,
    'updatedAt': serverTimestamp,
  };
}

Map<String, Object?> restoredUsageData({
  required ExpensePolicyUsage usage,
  required String requestId,
  required double amount,
  required Object serverTimestamp,
}) {
  return {
    'amountUsed': money(usage.amountUsed - amount).clamp(0, double.infinity),
    'usesUsed': (usage.usesUsed - 1).clamp(0, 1 << 31),
    'expenseIds': usage.expenseIds.where((id) => id != requestId).toList(),
    'updatedAt': serverTimestamp,
  };
}

String expensePolicyUsageDocId({
  required String policyId,
  required String branchId,
  required String periodKey,
}) {
  return '${policyId.trim()}|${branchId.trim()}|${periodKey.trim()}'.replaceAll(
    RegExp(r'[^A-Za-z0-9_-]'),
    '_',
  );
}

double money(double value) => (value * 100).roundToDouble() / 100;
