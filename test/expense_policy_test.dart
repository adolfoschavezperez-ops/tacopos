import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/expenses/expense_policy.dart';

void main() {
  group('expense policies', () {
    test('kill switch OFF no autoautoriza y conserva flujo manual', () {
      final decision = evaluateExpensePolicy(
        _input(settings: const ExpensePolicySettings()),
      );

      expect(decision.autoApproved, isFalse);
      expect(decision.reasonCode, 'kill_switch_off');
    });

    test('hielo diario autoaprueba primer uso y bloquea segundo por usos', () {
      final policy = _policy(
        maxAmountPerTransaction: 45,
        maxAmountPerPeriod: 45,
        maxUsesPerPeriod: 1,
      );
      final first = evaluateExpensePolicy(_input(policy: policy, amount: 40));
      final second = evaluateExpensePolicy(
        _input(
          policy: policy,
          amount: 5,
          usage: _usage(amountUsed: 40, usesUsed: 1),
        ),
      );

      expect(first.autoApproved, isTrue);
      expect(second.autoApproved, isFalse);
      expect(second.reasonCode, 'max_uses');
    });

    test('disponibilidad maxUses 1 con usage 0 queda enabled', () {
      final policy = _policy(id: 'hielo', maxUsesPerPeriod: 1);
      final availability = evaluateExpensePolicyAvailability(
        policy: policy,
        usage: _usage(
          policyId: 'hielo',
          periodKey: 'hielo_branch:2026-08-18',
          usesUsed: 0,
        ),
        businessDate: '2026-08-18',
      );

      expect(availability.enabled, isTrue);
      expect(availability.statusLabel, isEmpty);
    });

    test('disponibilidad maxUses 1 con usage 1 queda Ya utilizado', () {
      final policy = _policy(id: 'hielo', maxUsesPerPeriod: 1);
      final availability = evaluateExpensePolicyAvailability(
        policy: policy,
        usage: _usage(
          policyId: 'hielo',
          periodKey: 'hielo_branch:2026-08-18',
          usesUsed: 1,
        ),
        businessDate: '2026-08-18',
      );

      expect(availability.enabled, isFalse);
      expect(availability.statusLabel, 'Ya utilizado');
      expect(availability.reasonCode, 'max_uses');
    });

    test('disponibilidad maxUses 3 permite usage 2 y bloquea usage 3', () {
      final policy = _policy(id: 'hielo', maxUsesPerPeriod: 3);

      expect(
        evaluateExpensePolicyAvailability(
          policy: policy,
          usage: _usage(
            policyId: 'hielo',
            periodKey: 'hielo_branch:2026-08-18',
            usesUsed: 2,
          ),
          businessDate: '2026-08-18',
        ).enabled,
        isTrue,
      );
      expect(
        evaluateExpensePolicyAvailability(
          policy: policy,
          usage: _usage(
            policyId: 'hielo',
            periodKey: 'hielo_branch:2026-08-18',
            usesUsed: 3,
          ),
          businessDate: '2026-08-18',
        ).enabled,
        isFalse,
      );
    });

    test(
      'disponibilidad con monto acumulado agotado muestra Limite agotado',
      () {
        final policy = _policy(
          id: 'hielo',
          maxUsesPerPeriod: 3,
          maxAmountPerPeriod: 100,
        );
        final availability = evaluateExpensePolicyAvailability(
          policy: policy,
          usage: _usage(
            policyId: 'hielo',
            periodKey: 'hielo_branch:2026-08-18',
            amountUsed: 100,
            usesUsed: 1,
          ),
          businessDate: '2026-08-18',
        );

        expect(availability.enabled, isFalse);
        expect(availability.statusLabel, 'Limite agotado');
        expect(availability.reasonCode, 'max_period_amount');
      },
    );

    test('disponibilidad no bloquea por usage de otro periodo', () {
      final policy = _policy(id: 'hielo', maxUsesPerPeriod: 1);
      final availability = evaluateExpensePolicyAvailability(
        policy: policy,
        usage: _usage(
          policyId: 'hielo',
          periodKey: 'hielo_branch:2026-08-17',
          usesUsed: 1,
        ),
        businessDate: '2026-08-18',
      );

      expect(availability.enabled, isTrue);
    });

    test('disponibilidad no habilita si usage aun no cargo o fallo', () {
      final policy = _policy(id: 'hielo', maxUsesPerPeriod: 1);

      expect(
        evaluateExpensePolicyAvailability(
          policy: policy,
          usage: null,
          businessDate: '2026-08-18',
          usageLoaded: false,
        ).statusLabel,
        'Verificando disponibilidad',
      );
      expect(
        evaluateExpensePolicyAvailability(
          policy: policy,
          usage: null,
          businessDate: '2026-08-18',
        ).statusLabel,
        'No fue posible verificar disponibilidad',
      );
    });

    test('monto maximo por operacion manda a aprobacion manual', () {
      final decision = evaluateExpensePolicy(
        _input(policy: _policy(maxAmountPerTransaction: 45), amount: 46),
      );

      expect(decision.autoApproved, isFalse);
      expect(decision.reasonCode, 'max_transaction_amount');
    });

    test('monto acumulado evita fraccionamiento', () {
      final decision = evaluateExpensePolicy(
        _input(
          policy: _policy(
            maxAmountPerTransaction: 45,
            maxAmountPerPeriod: 60,
            maxUsesPerPeriod: 2,
          ),
          amount: 1,
          usage: _usage(amountUsed: 60, usesUsed: 2),
        ),
      );

      expect(decision.autoApproved, isFalse);
      expect(decision.reasonCode, 'max_uses');
    });

    test('acumulado maximo bloquea aunque queden usos', () {
      final decision = evaluateExpensePolicy(
        _input(
          policy: _policy(
            maxAmountPerTransaction: 45,
            maxAmountPerPeriod: 60,
            maxUsesPerPeriod: 3,
          ),
          amount: 1,
          usage: _usage(amountUsed: 60, usesUsed: 2),
        ),
      );

      expect(decision.autoApproved, isFalse);
      expect(decision.reasonCode, 'max_period_amount');
    });

    test('daily usa businessDate como periodKey', () {
      final policy = _policy(id: 'hielo');

      expect(
        expensePolicyPeriodKey(policy: policy, businessDate: '2026-08-18'),
        'hielo_branch:2026-08-18',
      );
    });

    test(
      'every n days calcula siguiente fecha elegible por fecha operativa',
      () {
        final policy = _policy(
          frequencyType: ExpensePolicyFrequencyType.everyNDays,
          frequencyValue: 3,
        );

        expect(
          nextEligibleBusinessDate(
            policy: policy,
            lastUsedBusinessDate: '2026-08-18',
          ),
          DateTime(2026, 8, 21),
        );
      },
    );

    test('weekly comparte periodo dentro de la misma semana operativa', () {
      final policy = _policy(frequencyType: ExpensePolicyFrequencyType.weekly);

      expect(
        expensePolicyPeriodKey(policy: policy, businessDate: '2026-08-18'),
        expensePolicyPeriodKey(policy: policy, businessDate: '2026-08-20'),
      );
    });

    test('every n weeks genera periodKey estable', () {
      final policy = _policy(
        frequencyType: ExpensePolicyFrequencyType.everyNWeeks,
        frequencyValue: 2,
      );

      expect(
        expensePolicyPeriodKey(policy: policy, businessDate: '2026-08-18'),
        contains('every_2_weeks'),
      );
    });

    test('monthly usa periodo calendario operativo', () {
      final policy = _policy(frequencyType: ExpensePolicyFrequencyType.monthly);

      expect(
        expensePolicyPeriodKey(policy: policy, businessDate: '2026-08-18'),
        'policy_branch:2026-08',
      );
    });

    test('specific weekdays permite solo dias configurados', () {
      final policy = _policy(
        frequencyType: ExpensePolicyFrequencyType.specificWeekdays,
        allowedWeekdays: [DateTime.tuesday, DateTime.friday],
      );

      final allowed = evaluateExpensePolicy(
        _input(policy: policy, businessDate: '2026-08-18'),
      );
      final blocked = evaluateExpensePolicy(
        _input(policy: policy, businessDate: '2026-08-19'),
      );

      expect(allowed.autoApproved, isTrue);
      expect(blocked.autoApproved, isFalse);
      expect(blocked.reasonCode, 'frequency_not_allowed');
    });

    test('receipt false permite sin comprobante y true lo exige', () {
      final optional = evaluateExpensePolicy(
        _input(policy: _policy(receiptRequired: false), hasReceipt: false),
      );
      final required = evaluateExpensePolicy(
        _input(policy: _policy(receiptRequired: true), hasReceipt: false),
      );

      expect(optional.autoApproved, isTrue);
      expect(required.autoApproved, isFalse);
      expect(required.reasonCode, 'receipt_required');
    });

    test('proveedor restringido y proveedor libre', () {
      final restricted = _policy(
        supplierRestrictionEnabled: true,
        allowedSupplierIds: ['noe'],
      );

      expect(
        evaluateExpensePolicy(
          _input(policy: restricted, supplierId: 'otro'),
        ).reasonCode,
        'supplier_not_allowed',
      );
      expect(
        evaluateExpensePolicy(
          _input(policy: restricted, supplierId: 'noe'),
        ).autoApproved,
        isTrue,
      );
      expect(
        evaluateExpensePolicy(
          _input(policy: _policy(supplierRestrictionEnabled: false)),
        ).autoApproved,
        isTrue,
      );
    });

    test('fuente de pago restringida', () {
      final decision = evaluateExpensePolicy(
        _input(
          policy: _policy(allowedPaymentSources: ['cash']),
          paymentSource: 'card',
        ),
      );

      expect(decision.autoApproved, isFalse);
      expect(decision.reasonCode, 'payment_source_not_allowed');
    });

    test('horario permitido y fuera de horario', () {
      final policy = _policy(
        allowedStartTime: '08:00',
        allowedEndTime: '22:00',
      );

      expect(
        evaluateExpensePolicy(
          _input(policy: policy, requestedAt: DateTime(2026, 8, 18, 21, 59)),
        ).autoApproved,
        isTrue,
      );
      expect(
        evaluateExpensePolicy(
          _input(policy: policy, requestedAt: DateTime(2026, 8, 18, 22, 30)),
        ).reasonCode,
        'time_not_allowed',
      );
    });

    test('otros por defecto queda manual', () {
      final decision = evaluateExpensePolicy(
        _input(policy: _policy(code: 'otros', autoApproveEnabled: false)),
      );

      expect(decision.autoApproved, isFalse);
      expect(decision.reasonCode, 'policy_manual');
    });

    test('policy autoapprove OFF queda manual', () {
      final decision = evaluateExpensePolicy(
        _input(policy: _policy(autoApproveEnabled: false)),
      );

      expect(decision.autoApproved, isFalse);
      expect(decision.reasonCode, 'policy_manual');
    });

    test('policy active false queda manual', () {
      final decision = evaluateExpensePolicy(
        _input(policy: _policy(active: false)),
      );

      expect(decision.autoApproved, isFalse);
      expect(decision.reasonCode, 'policy_inactive');
    });

    test('ledger consume monto uso y expense id una sola vez por llamada', () {
      final usage = _usage().consume(amount: 40, expenseId: 'expense-a');

      expect(usage.amountUsed, 40);
      expect(usage.usesUsed, 1);
      expect(usage.expenseIds, ['expense-a']);
    });

    test('offline no autoautoriza aunque cache indique cupo', () {
      final decision = evaluateExpensePolicy(_input(offline: true));

      expect(decision.autoApproved, isFalse);
      expect(decision.reasonCode, 'offline');
    });

    test('snapshot historico conserva version y limites', () {
      final snapshot = _policy(
        id: 'hielo',
        name: 'Hielo',
        policyVersion: 3,
        maxAmountPerTransaction: 45,
      ).snapshotForExpense();

      expect(snapshot['policyId'], 'hielo');
      expect(snapshot['policyVersion'], 3);
      expect(snapshot['maxAmountPerTransactionSnapshot'], 45);
    });

    test(
      'cambio de politica incrementa modelo sin alterar snapshot previo',
      () {
        final v1 = _policy(policyVersion: 1, maxAmountPerTransaction: 45);
        final snapshot = v1.snapshotForExpense();
        final v2 = v1.copyWith(policyVersion: 2, maxAmountPerTransaction: 55);

        expect(v2.maxAmountPerTransaction, 55);
        expect(snapshot['maxAmountPerTransactionSnapshot'], 45);
        expect(snapshot['policyVersion'], 1);
      },
    );

    test('cancelacion respeta bandera de restaurar cupo', () {
      expect(
        _policy(restoreQuotaOnCancellation: false).restoreQuotaOnCancellation,
        isFalse,
      );
      expect(
        _policy(restoreQuotaOnCancellation: true).restoreQuotaOnCancellation,
        isTrue,
      );
    });

    test(
      'tortillas cada 3 dias con comprobante bloquea intento anticipado',
      () {
        final policy = _policy(
          name: 'Tortillas harina',
          maxAmountPerTransaction: 300,
          maxAmountPerPeriod: 300,
          frequencyType: ExpensePolicyFrequencyType.everyNDays,
          frequencyValue: 3,
          receiptRequired: true,
        );
        final noReceipt = evaluateExpensePolicy(
          _input(policy: policy, amount: 300, hasReceipt: false),
        );
        final next = nextEligibleBusinessDate(
          policy: policy,
          lastUsedBusinessDate: '2026-08-18',
        );

        expect(noReceipt.reasonCode, 'receipt_required');
        expect(next, DateTime(2026, 8, 21));
      },
    );

    test('garrafon semanal segundo uso no autoaprueba', () {
      final decision = evaluateExpensePolicy(
        _input(
          policy: _policy(
            name: 'Garrafon',
            maxAmountPerTransaction: 60,
            frequencyType: ExpensePolicyFrequencyType.weekly,
            maxUsesPerPeriod: 1,
          ),
          amount: 60,
          usage: _usage(amountUsed: 60, usesUsed: 1),
        ),
      );

      expect(decision.autoApproved, isFalse);
      expect(decision.reasonCode, 'max_uses');
    });
  });
}

ExpensePolicyEvaluationInput _input({
  ExpensePolicySettings settings = const ExpensePolicySettings(
    expensePoliciesEnabled: true,
  ),
  ExpensePolicy? policy,
  ExpensePolicyUsage? usage,
  double amount = 40,
  String businessDate = '2026-08-18',
  DateTime? requestedAt,
  String paymentSource = 'cash',
  String supplierId = '',
  bool hasReceipt = true,
  bool offline = false,
}) {
  final effectivePolicy = policy ?? _policy();
  return ExpensePolicyEvaluationInput(
    settings: settings,
    policy: effectivePolicy,
    usage:
        usage ??
        _usage(
          policyId: effectivePolicy.id,
          branchId: effectivePolicy.branchId,
        ),
    amount: amount,
    businessDate: businessDate,
    requestedAt: requestedAt ?? DateTime(2026, 8, 18, 20),
    paymentSource: paymentSource,
    supplierId: supplierId,
    hasReceipt: hasReceipt,
    offline: offline,
  );
}

ExpensePolicy _policy({
  String id = 'policy',
  String name = 'Hielo',
  String code = 'hielo',
  bool active = true,
  bool autoApproveEnabled = true,
  double maxAmountPerTransaction = 45,
  double maxAmountPerPeriod = 45,
  int maxUsesPerPeriod = 1,
  ExpensePolicyFrequencyType frequencyType = ExpensePolicyFrequencyType.daily,
  int frequencyValue = 1,
  List<int> allowedWeekdays = const [],
  bool receiptRequired = false,
  bool supplierRestrictionEnabled = false,
  List<String> allowedSupplierIds = const [],
  List<String> allowedPaymentSources = const [],
  String allowedStartTime = '',
  String allowedEndTime = '',
  bool restoreQuotaOnCancellation = false,
  int policyVersion = 1,
}) {
  return ExpensePolicy(
    id: id,
    restaurantId: 'restaurant',
    branchId: 'branch',
    name: name,
    code: code,
    active: active,
    autoApproveEnabled: autoApproveEnabled,
    maxAmountPerTransaction: maxAmountPerTransaction,
    maxAmountPerPeriod: maxAmountPerPeriod,
    maxUsesPerPeriod: maxUsesPerPeriod,
    frequencyType: frequencyType,
    frequencyValue: frequencyValue,
    allowedWeekdays: allowedWeekdays,
    receiptRequired: receiptRequired,
    supplierRestrictionEnabled: supplierRestrictionEnabled,
    allowedSupplierIds: allowedSupplierIds,
    allowedPaymentSources: allowedPaymentSources,
    allowedStartTime: allowedStartTime,
    allowedEndTime: allowedEndTime,
    restoreQuotaOnCancellation: restoreQuotaOnCancellation,
    policyVersion: policyVersion,
  );
}

ExpensePolicyUsage _usage({
  String policyId = 'policy',
  String branchId = 'branch',
  String periodKey = 'period',
  double amountUsed = 0,
  int usesUsed = 0,
}) {
  return ExpensePolicyUsage(
    id: 'usage',
    policyId: policyId,
    branchId: branchId,
    periodKey: periodKey,
    amountUsed: amountUsed,
    usesUsed: usesUsed,
  );
}
