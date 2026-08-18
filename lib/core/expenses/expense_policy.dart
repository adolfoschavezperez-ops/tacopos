enum ExpensePolicyFrequencyType {
  daily,
  everyNDays,
  weekly,
  everyNWeeks,
  monthly,
  specificWeekdays,
}

enum ExpensePolicyDecisionStatus {
  autoApproved,
  manualApprovalRequired,
  rejected,
}

enum ExpensePolicyMode { off, shadow, live }

class ExpensePolicySettings {
  const ExpensePolicySettings({
    this.expensePoliciesEnabled = false,
    this.expensePolicyMode = ExpensePolicyMode.off,
    this.manualApprovalCutoffEnabled = false,
    this.manualApprovalCutoffTime = '',
    this.defaultReceiptRequired = false,
  });

  final bool expensePoliciesEnabled;
  final ExpensePolicyMode expensePolicyMode;
  final bool manualApprovalCutoffEnabled;
  final String manualApprovalCutoffTime;
  final bool defaultReceiptRequired;

  factory ExpensePolicySettings.fromMap(Map<String, dynamic>? data) {
    final mode = expensePolicyModeFromName(
      data?['expensePolicyMode'] as String? ?? data?['mode'] as String? ?? '',
      fallback: data?['expensePoliciesEnabled'] as bool? ?? false
          ? ExpensePolicyMode.live
          : ExpensePolicyMode.off,
    );
    return ExpensePolicySettings(
      expensePoliciesEnabled: mode != ExpensePolicyMode.off,
      expensePolicyMode: mode,
      manualApprovalCutoffEnabled:
          data?['manualApprovalCutoffEnabled'] as bool? ?? false,
      manualApprovalCutoffTime:
          data?['manualApprovalCutoffTime'] as String? ?? '',
      defaultReceiptRequired: data?['defaultReceiptRequired'] as bool? ?? false,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'expensePoliciesEnabled': expensePolicyMode == ExpensePolicyMode.live,
      'expensePolicyMode': expensePolicyMode.name,
      'manualApprovalCutoffEnabled': manualApprovalCutoffEnabled,
      'manualApprovalCutoffTime': manualApprovalCutoffTime,
      'defaultReceiptRequired': defaultReceiptRequired,
    };
  }
}

class ExpensePolicy {
  const ExpensePolicy({
    required this.id,
    required this.restaurantId,
    required this.branchId,
    required this.name,
    required this.code,
    this.description = '',
    this.active = true,
    this.autoApproveEnabled = false,
    this.maxAmountPerTransaction = 0,
    this.maxAmountPerPeriod = 0,
    this.maxUsesPerPeriod = 0,
    this.frequencyType = ExpensePolicyFrequencyType.daily,
    this.frequencyValue = 1,
    this.allowedWeekdays = const [],
    this.periodResetWeekday = DateTime.monday,
    this.receiptRequired = false,
    this.supplierRestrictionEnabled = false,
    this.allowedSupplierIds = const [],
    this.allowedPaymentSources = const [],
    this.requesterRoleRestrictions = const [],
    this.requesterIds = const [],
    this.allowedStartTime = '',
    this.allowedEndTime = '',
    this.validFrom,
    this.validUntil,
    this.restoreQuotaOnCancellation = false,
    this.requireReason = true,
    this.allowAdditionalNotes = true,
    this.allowFreeConcept = false,
    this.policyVersion = 1,
    this.sortOrder = 0,
    this.createdBy = '',
    this.updatedBy = '',
  });

  final String id;
  final String restaurantId;
  final String branchId;
  final String name;
  final String code;
  final String description;
  final bool active;
  final bool autoApproveEnabled;
  final double maxAmountPerTransaction;
  final double maxAmountPerPeriod;
  final int maxUsesPerPeriod;
  final ExpensePolicyFrequencyType frequencyType;
  final int frequencyValue;
  final List<int> allowedWeekdays;
  final int periodResetWeekday;
  final bool receiptRequired;
  final bool supplierRestrictionEnabled;
  final List<String> allowedSupplierIds;
  final List<String> allowedPaymentSources;
  final List<String> requesterRoleRestrictions;
  final List<String> requesterIds;
  final String allowedStartTime;
  final String allowedEndTime;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final bool restoreQuotaOnCancellation;
  final bool requireReason;
  final bool allowAdditionalNotes;
  final bool allowFreeConcept;
  final int policyVersion;
  final int sortOrder;
  final String createdBy;
  final String updatedBy;

  bool get isOtherPolicy =>
      allowFreeConcept || code.trim().toLowerCase() == 'otros';

  ExpensePolicy copyWith({
    String? id,
    String? restaurantId,
    String? branchId,
    String? name,
    String? code,
    String? description,
    bool? active,
    bool? autoApproveEnabled,
    double? maxAmountPerTransaction,
    double? maxAmountPerPeriod,
    int? maxUsesPerPeriod,
    ExpensePolicyFrequencyType? frequencyType,
    int? frequencyValue,
    List<int>? allowedWeekdays,
    int? periodResetWeekday,
    bool? receiptRequired,
    bool? supplierRestrictionEnabled,
    List<String>? allowedSupplierIds,
    List<String>? allowedPaymentSources,
    List<String>? requesterRoleRestrictions,
    List<String>? requesterIds,
    String? allowedStartTime,
    String? allowedEndTime,
    DateTime? validFrom,
    DateTime? validUntil,
    bool? restoreQuotaOnCancellation,
    bool? requireReason,
    bool? allowAdditionalNotes,
    bool? allowFreeConcept,
    int? policyVersion,
    int? sortOrder,
    String? createdBy,
    String? updatedBy,
  }) {
    return ExpensePolicy(
      id: id ?? this.id,
      restaurantId: restaurantId ?? this.restaurantId,
      branchId: branchId ?? this.branchId,
      name: name ?? this.name,
      code: code ?? this.code,
      description: description ?? this.description,
      active: active ?? this.active,
      autoApproveEnabled: autoApproveEnabled ?? this.autoApproveEnabled,
      maxAmountPerTransaction:
          maxAmountPerTransaction ?? this.maxAmountPerTransaction,
      maxAmountPerPeriod: maxAmountPerPeriod ?? this.maxAmountPerPeriod,
      maxUsesPerPeriod: maxUsesPerPeriod ?? this.maxUsesPerPeriod,
      frequencyType: frequencyType ?? this.frequencyType,
      frequencyValue: frequencyValue ?? this.frequencyValue,
      allowedWeekdays: allowedWeekdays ?? this.allowedWeekdays,
      periodResetWeekday: periodResetWeekday ?? this.periodResetWeekday,
      receiptRequired: receiptRequired ?? this.receiptRequired,
      supplierRestrictionEnabled:
          supplierRestrictionEnabled ?? this.supplierRestrictionEnabled,
      allowedSupplierIds: allowedSupplierIds ?? this.allowedSupplierIds,
      allowedPaymentSources:
          allowedPaymentSources ?? this.allowedPaymentSources,
      requesterRoleRestrictions:
          requesterRoleRestrictions ?? this.requesterRoleRestrictions,
      requesterIds: requesterIds ?? this.requesterIds,
      allowedStartTime: allowedStartTime ?? this.allowedStartTime,
      allowedEndTime: allowedEndTime ?? this.allowedEndTime,
      validFrom: validFrom ?? this.validFrom,
      validUntil: validUntil ?? this.validUntil,
      restoreQuotaOnCancellation:
          restoreQuotaOnCancellation ?? this.restoreQuotaOnCancellation,
      requireReason: requireReason ?? this.requireReason,
      allowAdditionalNotes: allowAdditionalNotes ?? this.allowAdditionalNotes,
      allowFreeConcept: allowFreeConcept ?? this.allowFreeConcept,
      policyVersion: policyVersion ?? this.policyVersion,
      sortOrder: sortOrder ?? this.sortOrder,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  factory ExpensePolicy.fromMap(String id, Map<String, dynamic> data) {
    return ExpensePolicy(
      id: id,
      restaurantId: data['restaurantId'] as String? ?? '',
      branchId: data['branchId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      code: data['code'] as String? ?? '',
      description: data['description'] as String? ?? '',
      active: data['active'] as bool? ?? true,
      autoApproveEnabled: data['autoApproveEnabled'] as bool? ?? false,
      maxAmountPerTransaction: _toDouble(data['maxAmountPerTransaction']),
      maxAmountPerPeriod: _toDouble(data['maxAmountPerPeriod']),
      maxUsesPerPeriod: _toInt(data['maxUsesPerPeriod']),
      frequencyType: expensePolicyFrequencyTypeFromName(
        data['frequencyType'] as String? ?? 'daily',
      ),
      frequencyValue: _toInt(data['frequencyValue'], fallback: 1),
      allowedWeekdays: _intList(data['allowedWeekdays']),
      periodResetWeekday: _toInt(
        data['periodResetWeekday'],
        fallback: DateTime.monday,
      ),
      receiptRequired: data['receiptRequired'] as bool? ?? false,
      supplierRestrictionEnabled:
          data['supplierRestrictionEnabled'] as bool? ?? false,
      allowedSupplierIds: _stringList(data['allowedSupplierIds']),
      allowedPaymentSources: _stringList(data['allowedPaymentSources']),
      requesterRoleRestrictions: _stringList(data['requesterRoleRestrictions']),
      requesterIds: _stringList(data['requesterIds']),
      allowedStartTime: data['allowedStartTime'] as String? ?? '',
      allowedEndTime: data['allowedEndTime'] as String? ?? '',
      validFrom: _toDate(data['validFrom']),
      validUntil: _toDate(data['validUntil']),
      restoreQuotaOnCancellation:
          data['restoreQuotaOnCancellation'] as bool? ?? false,
      requireReason: data['requireReason'] as bool? ?? true,
      allowAdditionalNotes: data['allowAdditionalNotes'] as bool? ?? true,
      allowFreeConcept: data['allowFreeConcept'] as bool? ?? false,
      policyVersion: _toInt(data['policyVersion'], fallback: 1),
      sortOrder: _toInt(data['sortOrder']),
      createdBy: data['createdBy'] as String? ?? '',
      updatedBy: data['updatedBy'] as String? ?? '',
    );
  }

  Map<String, Object?> toMap() {
    return {
      'restaurantId': restaurantId,
      'branchId': branchId,
      'name': name,
      'code': code,
      'description': description,
      'active': active,
      'autoApproveEnabled': autoApproveEnabled,
      'maxAmountPerTransaction': maxAmountPerTransaction,
      'maxAmountPerPeriod': maxAmountPerPeriod,
      'maxUsesPerPeriod': maxUsesPerPeriod,
      'frequencyType': frequencyType.name,
      'frequencyValue': frequencyValue,
      'allowedWeekdays': allowedWeekdays,
      'periodResetWeekday': periodResetWeekday,
      'receiptRequired': receiptRequired,
      'supplierRestrictionEnabled': supplierRestrictionEnabled,
      'allowedSupplierIds': allowedSupplierIds,
      'allowedPaymentSources': allowedPaymentSources,
      'requesterRoleRestrictions': requesterRoleRestrictions,
      'requesterIds': requesterIds,
      'allowedStartTime': allowedStartTime,
      'allowedEndTime': allowedEndTime,
      'validFrom': validFrom,
      'validUntil': validUntil,
      'restoreQuotaOnCancellation': restoreQuotaOnCancellation,
      'requireReason': requireReason,
      'allowAdditionalNotes': allowAdditionalNotes,
      'allowFreeConcept': allowFreeConcept,
      'policyVersion': policyVersion,
      'sortOrder': sortOrder,
      'createdBy': createdBy,
      'updatedBy': updatedBy,
    };
  }

  Map<String, Object?> snapshotForExpense() {
    return {
      'policyId': id,
      'policyVersion': policyVersion,
      'policyName': name,
      'policyCode': code,
      'maxAmountPerTransactionSnapshot': maxAmountPerTransaction,
      'maxAmountPerPeriodSnapshot': maxAmountPerPeriod,
      'maxUsesSnapshot': maxUsesPerPeriod,
      'frequencySnapshot': frequencyType.name,
      'frequencyValueSnapshot': frequencyValue,
      'receiptRequiredSnapshot': receiptRequired,
      'supplierRestrictionSnapshot': supplierRestrictionEnabled,
      'allowedSupplierIdsSnapshot': allowedSupplierIds,
      'allowedPaymentSourcesSnapshot': allowedPaymentSources,
    };
  }
}

class ExpensePolicyUsage {
  const ExpensePolicyUsage({
    required this.id,
    required this.policyId,
    required this.branchId,
    required this.periodKey,
    this.amountUsed = 0,
    this.usesUsed = 0,
    this.expenseIds = const [],
  });

  final String id;
  final String policyId;
  final String branchId;
  final String periodKey;
  final double amountUsed;
  final int usesUsed;
  final List<String> expenseIds;

  ExpensePolicyUsage consume({
    required double amount,
    required String expenseId,
  }) {
    final cleanExpenseId = expenseId.trim();
    return ExpensePolicyUsage(
      id: id,
      policyId: policyId,
      branchId: branchId,
      periodKey: periodKey,
      amountUsed: _money(amountUsed + amount),
      usesUsed: usesUsed + 1,
      expenseIds: cleanExpenseId.isEmpty
          ? expenseIds
          : [...expenseIds, cleanExpenseId],
    );
  }

  factory ExpensePolicyUsage.fromMap(String id, Map<String, dynamic> data) {
    return ExpensePolicyUsage(
      id: id,
      policyId: data['policyId'] as String? ?? '',
      branchId: data['branchId'] as String? ?? '',
      periodKey: data['periodKey'] as String? ?? '',
      amountUsed: _toDouble(data['amountUsed']),
      usesUsed: _toInt(data['usesUsed']),
      expenseIds: _stringList(data['expenseIds']),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'policyId': policyId,
      'branchId': branchId,
      'periodKey': periodKey,
      'amountUsed': amountUsed,
      'usesUsed': usesUsed,
      'expenseIds': expenseIds,
    };
  }
}

class ExpensePolicyEvaluationInput {
  const ExpensePolicyEvaluationInput({
    required this.settings,
    required this.policy,
    required this.usage,
    required this.amount,
    required this.businessDate,
    required this.requestedAt,
    required this.paymentSource,
    this.supplierId = '',
    this.requesterRole = '',
    this.requesterId = '',
    this.hasReceipt = false,
    this.offline = false,
    this.reason = '',
  });

  final ExpensePolicySettings settings;
  final ExpensePolicy policy;
  final ExpensePolicyUsage usage;
  final double amount;
  final String businessDate;
  final DateTime requestedAt;
  final String paymentSource;
  final String supplierId;
  final String requesterRole;
  final String requesterId;
  final bool hasReceipt;
  final bool offline;
  final String reason;
}

class ExpensePolicyDecision {
  const ExpensePolicyDecision({
    required this.status,
    required this.reasonCode,
    required this.message,
    this.periodKey = '',
  });

  final ExpensePolicyDecisionStatus status;
  final String reasonCode;
  final String message;
  final String periodKey;

  bool get autoApproved => status == ExpensePolicyDecisionStatus.autoApproved;
}

ExpensePolicyDecision evaluateExpensePolicy(
  ExpensePolicyEvaluationInput input,
) {
  final policy = input.policy;
  final periodKey = expensePolicyPeriodKey(
    policy: policy,
    businessDate: input.businessDate,
  );

  ExpensePolicyDecision manual(String code, String message) {
    return ExpensePolicyDecision(
      status: ExpensePolicyDecisionStatus.manualApprovalRequired,
      reasonCode: code,
      message: message,
      periodKey: periodKey,
    );
  }

  if (!input.settings.expensePoliciesEnabled) {
    return manual(
      'kill_switch_off',
      'La autoautorizacion de gastos esta desactivada.',
    );
  }
  if (input.offline) {
    return manual('offline', 'No hay conexion suficiente para autoautorizar.');
  }
  if (!policy.active) {
    return manual('policy_inactive', 'La politica no esta activa.');
  }
  if (!policy.autoApproveEnabled) {
    return manual('policy_manual', 'La politica requiere autorizacion manual.');
  }
  if (policy.isOtherPolicy && policy.autoApproveEnabled == false) {
    return manual(
      'other_manual',
      'Otros gastos requieren autorizacion manual.',
    );
  }
  if (input.amount <= 0) {
    return manual('invalid_amount', 'Captura un monto valido.');
  }
  if (policy.maxAmountPerTransaction > 0 &&
      input.amount > policy.maxAmountPerTransaction) {
    return manual(
      'max_transaction_amount',
      'Supera el monto maximo de \$${policy.maxAmountPerTransaction.toStringAsFixed(2)}.',
    );
  }
  if (policy.maxUsesPerPeriod > 0 &&
      input.usage.usesUsed >= policy.maxUsesPerPeriod) {
    return manual(
      'max_uses',
      'Este gasto ya fue utilizado ${input.usage.usesUsed} de ${policy.maxUsesPerPeriod} veces durante el periodo.',
    );
  }
  if (policy.maxAmountPerPeriod > 0 &&
      _money(input.usage.amountUsed + input.amount) >
          policy.maxAmountPerPeriod) {
    return manual(
      'max_period_amount',
      'El limite acumulado del periodo ya fue alcanzado.',
    );
  }
  if (policy.receiptRequired && !input.hasReceipt) {
    return manual('receipt_required', 'Esta politica requiere comprobante.');
  }
  if (policy.supplierRestrictionEnabled &&
      !policy.allowedSupplierIds.contains(input.supplierId)) {
    return manual(
      'supplier_not_allowed',
      'El proveedor seleccionado no esta permitido.',
    );
  }
  if (policy.allowedPaymentSources.isNotEmpty &&
      !policy.allowedPaymentSources.contains(input.paymentSource)) {
    return manual(
      'payment_source_not_allowed',
      'La fuente de pago no esta permitida para esta politica.',
    );
  }
  if (policy.requesterRoleRestrictions.isNotEmpty &&
      !policy.requesterRoleRestrictions.contains(input.requesterRole)) {
    return manual('role_not_allowed', 'Tu rol no puede usar esta politica.');
  }
  if (policy.requesterIds.isNotEmpty &&
      !policy.requesterIds.contains(input.requesterId)) {
    return manual(
      'requester_not_allowed',
      'Este usuario no puede usar esta politica.',
    );
  }
  if (!_businessDateAllowed(policy, input.businessDate)) {
    return manual(
      'frequency_not_allowed',
      'La politica no esta disponible en esta fecha operativa.',
    );
  }
  if (!_timeAllowed(policy, input.requestedAt)) {
    return manual(
      'time_not_allowed',
      'La solicitud quedo fuera del horario de autorizacion y sera revisada el siguiente dia operativo.',
    );
  }
  if (policy.validFrom != null &&
      _businessDate(input.businessDate).isBefore(policy.validFrom!)) {
    return manual('not_yet_valid', 'La politica aun no esta vigente.');
  }
  if (policy.validUntil != null &&
      _businessDate(input.businessDate).isAfter(policy.validUntil!)) {
    return manual('expired', 'La politica ya no esta vigente.');
  }

  return ExpensePolicyDecision(
    status: ExpensePolicyDecisionStatus.autoApproved,
    reasonCode: 'auto_approved',
    message: 'Gasto autoautorizado.',
    periodKey: periodKey,
  );
}

String expensePolicyPeriodKey({
  required ExpensePolicy policy,
  required String businessDate,
}) {
  final date = _businessDate(businessDate);
  final prefix = '${policy.id}_${policy.branchId}';
  return switch (policy.frequencyType) {
    ExpensePolicyFrequencyType.daily ||
    ExpensePolicyFrequencyType.specificWeekdays => '$prefix:${_dateKey(date)}',
    ExpensePolicyFrequencyType.everyNDays =>
      '$prefix:every_${policy.frequencyValue}_days:${_periodBucket(date, policy.frequencyValue)}',
    ExpensePolicyFrequencyType.weekly =>
      '$prefix:week:${_weekKey(date, policy.periodResetWeekday)}',
    ExpensePolicyFrequencyType.everyNWeeks =>
      '$prefix:every_${policy.frequencyValue}_weeks:${_periodBucket(_weekStart(date, policy.periodResetWeekday), policy.frequencyValue * 7)}',
    ExpensePolicyFrequencyType.monthly =>
      '$prefix:${date.year}-${date.month.toString().padLeft(2, '0')}',
  };
}

DateTime nextEligibleBusinessDate({
  required ExpensePolicy policy,
  required String lastUsedBusinessDate,
}) {
  final date = _businessDate(lastUsedBusinessDate);
  return switch (policy.frequencyType) {
    ExpensePolicyFrequencyType.everyNDays => date.add(
      Duration(days: policy.frequencyValue <= 0 ? 1 : policy.frequencyValue),
    ),
    ExpensePolicyFrequencyType.everyNWeeks => date.add(
      Duration(
        days: (policy.frequencyValue <= 0 ? 1 : policy.frequencyValue) * 7,
      ),
    ),
    ExpensePolicyFrequencyType.weekly => date.add(const Duration(days: 7)),
    ExpensePolicyFrequencyType.monthly => DateTime(
      date.year,
      date.month + 1,
      date.day,
    ),
    _ => date.add(const Duration(days: 1)),
  };
}

ExpensePolicyFrequencyType expensePolicyFrequencyTypeFromName(String value) {
  return ExpensePolicyFrequencyType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => ExpensePolicyFrequencyType.daily,
  );
}

ExpensePolicyMode expensePolicyModeFromName(
  String value, {
  ExpensePolicyMode fallback = ExpensePolicyMode.off,
}) {
  return ExpensePolicyMode.values.firstWhere(
    (mode) => mode.name == value.trim().toLowerCase(),
    orElse: () => fallback,
  );
}

bool _businessDateAllowed(ExpensePolicy policy, String businessDate) {
  final date = _businessDate(businessDate);
  if (policy.frequencyType != ExpensePolicyFrequencyType.specificWeekdays) {
    return true;
  }
  return policy.allowedWeekdays.contains(date.weekday);
}

bool _timeAllowed(ExpensePolicy policy, DateTime requestedAt) {
  final start = _minutes(policy.allowedStartTime);
  final end = _minutes(policy.allowedEndTime);
  if (start == null && end == null) return true;
  final current = requestedAt.hour * 60 + requestedAt.minute;
  if (start != null && current < start) return false;
  if (end != null && current > end) return false;
  return true;
}

int? _minutes(String value) {
  final parts = value.trim().split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

DateTime _businessDate(String value) {
  final parts = value.split('-').map(int.tryParse).toList();
  if (parts.length != 3 || parts.any((part) => part == null)) {
    throw ArgumentError('Fecha operativa invalida: $value');
  }
  return DateTime(parts[0]!, parts[1]!, parts[2]!);
}

String _dateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

int _periodBucket(DateTime date, int days) {
  final safeDays = days <= 0 ? 1 : days;
  return date.difference(DateTime.utc(1970)).inDays ~/ safeDays;
}

String _weekKey(DateTime date, int resetWeekday) {
  final start = _weekStart(date, resetWeekday);
  return _dateKey(start);
}

DateTime _weekStart(DateTime date, int resetWeekday) {
  final safeReset =
      resetWeekday < DateTime.monday || resetWeekday > DateTime.sunday
      ? DateTime.monday
      : resetWeekday;
  final delta = (date.weekday - safeReset) % 7;
  return DateTime(
    date.year,
    date.month,
    date.day,
  ).subtract(Duration(days: delta));
}

double _money(double value) => (value * 100).roundToDouble() / 100;

double _toDouble(Object? value) => value is num ? value.toDouble() : 0;

int _toInt(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : fallback;

List<String> _stringList(Object? value) {
  if (value is Iterable) {
    return value
        .map((item) => '$item')
        .where((item) => item.trim().isNotEmpty)
        .toList();
  }
  return const [];
}

List<int> _intList(Object? value) {
  if (value is Iterable) {
    return value.whereType<num>().map((item) => item.toInt()).toList();
  }
  return const [];
}

DateTime? _toDate(Object? value) {
  return value is DateTime ? value : null;
}
