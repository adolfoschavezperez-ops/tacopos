import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/expenses/expense_policy.dart';
import 'package:tacopos/core/expenses/local_expense_policy_flow.dart';

void main() {
  group('local expense policy flow', () {
    test('LIVE cumple -> approved y consume usage', () {
      final plan = _plan(amount: 40);

      expect(plan.status, 'approved');
      expect(plan.requestData['autoApproved'], isTrue);
      expect(plan.requestData['approvalSource'], devicePolicyApprovalSource);
      expect(plan.usageData?['amountUsed'], 40);
      expect(plan.usageData?['usesUsed'], 1);
      expect(plan.usageData?['expenseIds'], ['request-1']);
    });

    test('LIVE excede max transaction -> pending sin usage', () {
      final plan = _plan(amount: 130);

      expect(plan.status, 'pending');
      expect(plan.decision.reasonCode, 'max_transaction_amount');
      expect(plan.usageData, isNull);
    });

    test('LIVE excede total del periodo -> pending sin incrementar usage', () {
      final plan = _plan(
        amount: 30,
        usage: _usage(amountUsed: 80, usesUsed: 1),
      );

      expect(plan.status, 'pending');
      expect(plan.decision.reasonCode, 'max_period_amount');
      expect(plan.usageData, isNull);
    });

    test('LIVE excede useCount -> pending', () {
      final plan = _plan(
        amount: 10,
        policy: _policy(maxUsesPerPeriod: 1),
        usage: _usage(amountUsed: 40, usesUsed: 1),
      );

      expect(plan.status, 'pending');
      expect(plan.decision.reasonCode, 'max_uses');
    });

    test('SHADOW cumple -> pending + wouldAutoApprove true', () {
      final plan = _plan(settings: _settings(ExpensePolicyMode.shadow));

      expect(plan.status, 'pending');
      expect(plan.requestData['autoApproved'], isFalse);
      expect(plan.requestData['wouldAutoApprove'], isTrue);
      expect(plan.usageData, isNull);
    });

    test('OFF -> pending', () {
      final plan = _plan(settings: _settings(ExpensePolicyMode.off));

      expect(plan.status, 'pending');
      expect(plan.decision.reasonCode, anyOf('kill_switch_off', 'mode_off'));
      expect(plan.usageData, isNull);
    });

    test('policy inactive -> pending/no autoapproval', () {
      final plan = _plan(policy: _policy(active: false));

      expect(plan.status, 'pending');
      expect(plan.requestData['autoApproved'], isFalse);
      expect(plan.decision.reasonCode, 'policy_inactive');
    });

    test('supplier invalid -> pending', () {
      final plan = _plan(
        policy: _policy(
          supplierRestrictionEnabled: true,
          allowedSupplierIds: ['supplier-ok'],
        ),
        supplierId: 'supplier-bad',
      );

      expect(plan.status, 'pending');
      expect(plan.decision.reasonCode, 'supplier_not_allowed');
    });

    test('paymentSource invalid -> pending', () {
      final plan = _plan(
        policy: _policy(allowedPaymentSources: ['card']),
        paymentSource: 'cash',
      );

      expect(plan.status, 'pending');
      expect(plan.decision.reasonCode, 'payment_source_not_allowed');
    });

    test('employee invalid -> pending', () {
      final plan = _plan(policy: _policy(requesterIds: ['other']));

      expect(plan.status, 'pending');
      expect(plan.decision.reasonCode, 'requester_not_allowed');
    });

    test('time invalid -> pending', () {
      final plan = _plan(
        policy: _policy(allowedStartTime: '08:00', allowedEndTime: '09:00'),
        requestedAt: DateTime(2026, 8, 18, 10),
      );

      expect(plan.status, 'pending');
      expect(plan.decision.reasonCode, 'time_not_allowed');
    });

    test('validUntil vencida -> pending', () {
      final plan = _plan(policy: _policy(validUntil: DateTime(2026, 8, 17)));

      expect(plan.status, 'pending');
      expect(plan.decision.reasonCode, 'expired');
    });

    test('usage doc id es compatible con backend', () {
      expect(
        expensePolicyUsageDocId(
          policyId: 'hielo',
          branchId: 'aviacion',
          periodKey: 'hielo_aviacion:2026-08-18',
        ),
        'hielo_aviacion_hielo_aviacion_2026-08-18',
      );
    });

    test('duplicate clientRequestId conserva mismo request id', () {
      final first = _plan(requestId: 'same-request');
      final retry = _plan(requestId: 'same-request');

      expect(first.requestId, retry.requestId);
      expect(first.requestData['id'], 'same-request');
    });

    test('concurrent usage logico: solo una queda dentro del limite', () {
      final first = _plan(
        amount: 60,
        policy: _policy(maxAmountPerPeriod: 100, maxUsesPerPeriod: 2),
      );
      final second = _plan(
        amount: 60,
        policy: _policy(maxAmountPerPeriod: 100, maxUsesPerPeriod: 2),
        usage: _usage(amountUsed: 60, usesUsed: 1),
      );

      expect(first.status, 'approved');
      expect(second.status, 'pending');
      expect(second.decision.reasonCode, 'max_period_amount');
    });

    test('cancellation restoreQuota true resta sin negativos', () {
      final restored = restoredUsageData(
        usage: _usage(amountUsed: 40, usesUsed: 1, expenseIds: ['request-1']),
        requestId: 'request-1',
        amount: 40,
        serverTimestamp: 'server',
      );

      expect(restored['amountUsed'], 0);
      expect(restored['usesUsed'], 0);
      expect(restored['expenseIds'], isEmpty);
    });

    test('cancellation twice no resta dos veces por ausencia de expenseId', () {
      final restored = restoredUsageData(
        usage: _usage(amountUsed: 0, usesUsed: 0),
        requestId: 'request-1',
        amount: 40,
        serverTimestamp: 'server',
      );

      expect(restored['amountUsed'], 0);
      expect(restored['usesUsed'], 0);
    });
  });
}

LocalExpenseTransactionPlan _plan({
  double amount = 40,
  ExpensePolicy? policy,
  ExpensePolicySettings? settings,
  ExpensePolicyUsage? usage,
  String requestId = 'request-1',
  String supplierId = '',
  String paymentSource = 'cash',
  DateTime? requestedAt,
}) {
  final effectivePolicy = policy ?? _policy();
  return buildLocalExpenseTransactionPlan(
    input: LocalExpenseRequestInput(
      restaurantId: 'tacopos',
      restaurantName: 'TacoPOS',
      branchId: 'aviacion',
      branchName: 'Aviacion',
      cashSessionId: 'cash-open',
      businessDate: '2026-08-18',
      amount: amount,
      reason: 'Hielo',
      policy: effectivePolicy,
      settings: settings ?? _settings(ExpensePolicyMode.live),
      paymentSource: paymentSource,
      supplierId: supplierId,
      clientRequestId: requestId,
      requesterId: 'employee-1',
      requesterName: 'Empleado',
      requesterRole: 'staff',
      deviceId: 'device-1',
      requestedAt: requestedAt ?? DateTime(2026, 8, 18, 8),
    ),
    usage:
        usage ??
        _usage(
          policyId: effectivePolicy.id,
          branchId: effectivePolicy.branchId,
        ),
    serverTimestamp: 'server',
  );
}

ExpensePolicySettings _settings(ExpensePolicyMode mode) {
  return ExpensePolicySettings(
    expensePoliciesEnabled: mode != ExpensePolicyMode.off,
    expensePolicyMode: mode,
  );
}

ExpensePolicy _policy({
  bool active = true,
  bool autoApproveEnabled = true,
  double maxAmountPerTransaction = 100,
  double maxAmountPerPeriod = 100,
  int maxUsesPerPeriod = 3,
  bool supplierRestrictionEnabled = false,
  List<String> allowedSupplierIds = const [],
  List<String> allowedPaymentSources = const [],
  List<String> requesterIds = const [],
  String allowedStartTime = '',
  String allowedEndTime = '',
  DateTime? validUntil,
}) {
  return ExpensePolicy(
    id: 'hielo',
    restaurantId: 'tacopos',
    branchId: 'aviacion',
    name: 'Hielo',
    code: 'hielo',
    active: active,
    autoApproveEnabled: autoApproveEnabled,
    maxAmountPerTransaction: maxAmountPerTransaction,
    maxAmountPerPeriod: maxAmountPerPeriod,
    maxUsesPerPeriod: maxUsesPerPeriod,
    supplierRestrictionEnabled: supplierRestrictionEnabled,
    allowedSupplierIds: allowedSupplierIds,
    allowedPaymentSources: allowedPaymentSources,
    requesterIds: requesterIds,
    allowedStartTime: allowedStartTime,
    allowedEndTime: allowedEndTime,
    validUntil: validUntil,
    policyVersion: 2,
    restoreQuotaOnCancellation: true,
  );
}

ExpensePolicyUsage _usage({
  String policyId = 'hielo',
  String branchId = 'aviacion',
  double amountUsed = 0,
  int usesUsed = 0,
  List<String> expenseIds = const [],
}) {
  return ExpensePolicyUsage(
    id: 'usage',
    policyId: policyId,
    branchId: branchId,
    periodKey: 'period',
    amountUsed: amountUsed,
    usesUsed: usesUsed,
    expenseIds: expenseIds,
  );
}
