import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';

const salesAuditMoneyTolerance = 0.02;

class SalesAuditResult {
  const SalesAuditResult({
    required this.activeItems,
    required this.cancelledItems,
    required this.activePayments,
    required this.grossItemsTotal,
    required this.monetaryDiscountApplied,
    required this.netCustomerDue,
    required this.moneyPaymentsApplied,
    required this.settledTotal,
    required this.receivedTotal,
    required this.changeTotal,
    required this.diffItemsOrder,
    required this.diffSettlement,
    required this.diffPaidTotal,
    required this.diffPendingTotal,
    required this.discountFields,
    required this.discountSources,
    required this.failedCodes,
    required this.diagnostics,
    required this.validations,
    required this.cashPaymentMismatchCount,
    required this.duplicatePaymentCount,
    required this.auditMode,
  });

  final List<OrderItem> activeItems;
  final List<OrderItem> cancelledItems;
  final List<Payment> activePayments;
  final double grossItemsTotal;
  final double monetaryDiscountApplied;
  final double netCustomerDue;
  final double moneyPaymentsApplied;
  final double settledTotal;
  final double receivedTotal;
  final double changeTotal;
  final double diffItemsOrder;
  final double diffSettlement;
  final double diffPaidTotal;
  final double diffPendingTotal;
  final Map<String, double> discountFields;
  final List<SalesAuditDiscountSource> discountSources;
  final List<String> failedCodes;
  final List<String> diagnostics;
  final List<SalesAuditValidation> validations;
  final int cashPaymentMismatchCount;
  final int duplicatePaymentCount;
  final SalesAuditMode auditMode;

  bool get hasDiscrepancy => failedCodes.isNotEmpty;
}

class SalesAuditValidation {
  const SalesAuditValidation({
    required this.label,
    required this.passed,
    this.detail = '',
  });

  final String label;
  final bool passed;
  final String detail;
}

class SalesAuditDiscountSource {
  const SalesAuditDiscountSource({
    required this.field,
    required this.originalValue,
    required this.kind,
    required this.monetaryAmount,
    required this.used,
    this.normalizedPercent,
    this.interpretation = '',
    this.metadata = '',
  });

  final String field;
  final double originalValue;
  final String kind;
  final double monetaryAmount;
  final bool used;
  final double? normalizedPercent;
  final String interpretation;
  final String metadata;
}

enum SalesAuditMode { paid, partial, cancelled, pending }

SalesAuditResult auditSalesIntegrity(
  PosOrder order,
  List<OrderItem> items,
  List<Payment> payments,
) {
  final activeItems = items.where((item) => !item.isCancelled).toList();
  final cancelledItems = items.where((item) => item.isCancelled).toList();
  final activePayments = payments.where(isSalesAuditActivePayment).toList();
  final mode = _auditModeFor(order);
  final grossItemsTotal = activeItems.fold<double>(
    0,
    (sum, item) => sum + (item.qty * item.unitPrice),
  );
  final discountResolution = _resolveDiscount(
    order,
    activePayments,
    grossItemsTotal,
  );
  final monetaryDiscountApplied = discountResolution.amount;
  final netCustomerDue = (grossItemsTotal - monetaryDiscountApplied)
      .clamp(0, double.infinity)
      .toDouble();
  final moneyPaymentsApplied = activePayments.fold<double>(
    0,
    (sum, payment) => sum + salesAuditMoneyPaymentAmount(payment),
  );
  final settledTotal = moneyPaymentsApplied + monetaryDiscountApplied;
  final receivedTotal = activePayments.fold<double>(
    0,
    (sum, payment) => sum + (payment.cashReceivedAmount ?? 0),
  );
  final changeTotal = activePayments.fold<double>(
    0,
    (sum, payment) => sum + (payment.cashChangeAmount ?? 0),
  );
  final expectedPending = (grossItemsTotal - settledTotal)
      .clamp(0, double.infinity)
      .toDouble();
  final diffItemsOrder = order.total - grossItemsTotal;
  final diffSettlement = settledTotal - grossItemsTotal;
  final diffPaidTotal = order.paidTotal - settledTotal;
  final diffPendingTotal = order.pendingTotal - expectedPending;
  final codes = <String>[];
  final diagnostics = <String>[];
  final validations = <SalesAuditValidation>[];

  void fail(String code, String message) {
    if (!codes.contains(code)) codes.add(code);
    diagnostics.add(message);
  }

  void validation(
    String label,
    bool passed, {
    String code = 'other',
    String failMessage = '',
    String detail = '',
  }) {
    validations.add(
      SalesAuditValidation(label: label, passed: passed, detail: detail),
    );
    if (!passed && failMessage.isNotEmpty) fail(code, failMessage);
  }

  if (mode == SalesAuditMode.pending) {
    validation(
      'Orden pendiente sin cobro completo',
      _pendingOrderLooksConsistent(order, activeItems, moneyPaymentsApplied),
      code: 'state_inconsistent',
      failMessage: 'Estado pendiente con totales inconsistentes.',
      detail: 'Las ordenes abiertas correctas no se tratan como error.',
    );
    validation(
      'Total no negativo',
      order.total >= -salesAuditMoneyTolerance,
      code: 'negative_total',
      failMessage: 'Total de orden negativo.',
    );
    return _result(
      activeItems: activeItems,
      cancelledItems: cancelledItems,
      activePayments: activePayments,
      grossItemsTotal: grossItemsTotal,
      monetaryDiscountApplied: monetaryDiscountApplied,
      netCustomerDue: netCustomerDue,
      moneyPaymentsApplied: moneyPaymentsApplied,
      settledTotal: settledTotal,
      receivedTotal: receivedTotal,
      changeTotal: changeTotal,
      diffItemsOrder: diffItemsOrder,
      diffSettlement: diffSettlement,
      diffPaidTotal: diffPaidTotal,
      diffPendingTotal: diffPendingTotal,
      discountFields: discountResolution.fields,
      discountSources: discountResolution.sources,
      failedCodes: codes,
      diagnostics: diagnostics,
      validations: validations,
      cashPaymentMismatchCount: 0,
      duplicatePaymentCount: 0,
      auditMode: mode,
    );
  }

  if (mode == SalesAuditMode.cancelled) {
    validation(
      'Orden cancelada sin pagos activos',
      activePayments.isEmpty,
      code: 'cancelled_active_payments',
      failMessage: 'Orden cancelada con pagos activos.',
    );
    validation(
      'paidTotal cancelado',
      !_outsideTolerance(order.paidTotal),
      code: 'paid_total',
      failMessage: 'Orden cancelada conserva paidTotal mayor a cero.',
    );
    validation(
      'pendingTotal cancelado',
      order.pendingTotal >= -salesAuditMoneyTolerance,
      code: 'pending_total',
      failMessage: 'Orden cancelada con pendingTotal negativo.',
    );
    return _result(
      activeItems: activeItems,
      cancelledItems: cancelledItems,
      activePayments: activePayments,
      grossItemsTotal: grossItemsTotal,
      monetaryDiscountApplied: monetaryDiscountApplied,
      netCustomerDue: netCustomerDue,
      moneyPaymentsApplied: moneyPaymentsApplied,
      settledTotal: settledTotal,
      receivedTotal: receivedTotal,
      changeTotal: changeTotal,
      diffItemsOrder: diffItemsOrder,
      diffSettlement: diffSettlement,
      diffPaidTotal: diffPaidTotal,
      diffPendingTotal: diffPendingTotal,
      discountFields: discountResolution.fields,
      discountSources: discountResolution.sources,
      failedCodes: codes,
      diagnostics: diagnostics,
      validations: validations,
      cashPaymentMismatchCount: 0,
      duplicatePaymentCount: 0,
      auditMode: mode,
    );
  }

  if (mode == SalesAuditMode.partial) {
    validation(
      'paidTotal = total liquidado',
      !_outsideTolerance(diffPaidTotal),
      code: 'paid_total',
      failMessage:
          'paidTotal vs total liquidado: diferencia ${diffPaidTotal.toStringAsFixed(2)}.',
    );
    validation(
      'pendingTotal = total bruto - liquidado',
      !_outsideTolerance(diffPendingTotal),
      code: 'pending_total',
      failMessage: 'pendingTotal incorrecto para orden parcial.',
    );
    validation(
      'Estado parcial consistente',
      _normalize(order.paymentStatus) == 'partial',
      code: 'state_inconsistent',
      failMessage: 'Orden parcial con estado de pago inconsistente.',
    );
    final cashIssues = _validateCashPayments(activePayments, fail, validations);
    final duplicateCount = _detectDuplicatePayments(activePayments, fail);
    return _result(
      activeItems: activeItems,
      cancelledItems: cancelledItems,
      activePayments: activePayments,
      grossItemsTotal: grossItemsTotal,
      monetaryDiscountApplied: monetaryDiscountApplied,
      netCustomerDue: netCustomerDue,
      moneyPaymentsApplied: moneyPaymentsApplied,
      settledTotal: settledTotal,
      receivedTotal: receivedTotal,
      changeTotal: changeTotal,
      diffItemsOrder: diffItemsOrder,
      diffSettlement: diffSettlement,
      diffPaidTotal: diffPaidTotal,
      diffPendingTotal: diffPendingTotal,
      discountFields: discountResolution.fields,
      discountSources: discountResolution.sources,
      failedCodes: codes,
      diagnostics: diagnostics,
      validations: validations,
      cashPaymentMismatchCount: cashIssues,
      duplicatePaymentCount: duplicateCount,
      auditMode: mode,
    );
  }

  final orderTotalMatchesGross = !_outsideTolerance(diffItemsOrder);
  validation(
    'Items activos = total bruto orden',
    orderTotalMatchesGross,
    code: 'items_order',
    failMessage:
        'Items vs total orden: diferencia ${diffItemsOrder.toStringAsFixed(2)}.',
  );
  if (!orderTotalMatchesGross &&
      monetaryDiscountApplied <= salesAuditMoneyTolerance &&
      grossItemsTotal > order.total + salesAuditMoneyTolerance) {
    fail(
      'discount_inconsistent',
      'Posible total incorrecto o beneficio no registrado.',
    );
  }
  validation(
    'Pago monetario + descuento = total bruto',
    !_outsideTolerance(diffSettlement),
    code: 'payments_order',
    failMessage:
        'Liquidacion vs total bruto: diferencia ${diffSettlement.toStringAsFixed(2)}.',
  );
  validation(
    'paidTotal = total liquidado',
    !_outsideTolerance(diffPaidTotal),
    code: 'paid_total',
    failMessage:
        'paidTotal vs total liquidado: diferencia ${diffPaidTotal.toStringAsFixed(2)}.',
  );
  validation(
    'pendingTotal pagado = 0',
    order.pendingTotal.abs() <= salesAuditMoneyTolerance,
    code: 'pending_total',
    failMessage: 'Orden pagada con saldo pendiente.',
  );
  validation(
    'Orden pagada completa',
    settledTotal + salesAuditMoneyTolerance >= grossItemsTotal &&
        order.paidTotal + salesAuditMoneyTolerance >= grossItemsTotal,
    code: 'paid_incomplete',
    failMessage: 'Orden marcada pagada sin importe liquidado completo.',
  );
  validation(
    'Total no negativo',
    order.total >= -salesAuditMoneyTolerance,
    code: 'negative_total',
    failMessage: 'Total de orden negativo.',
  );
  final cashIssues = _validateCashPayments(activePayments, fail, validations);
  final duplicateCount = _detectDuplicatePayments(activePayments, fail);

  return _result(
    activeItems: activeItems,
    cancelledItems: cancelledItems,
    activePayments: activePayments,
    grossItemsTotal: grossItemsTotal,
    monetaryDiscountApplied: monetaryDiscountApplied,
    netCustomerDue: netCustomerDue,
    moneyPaymentsApplied: moneyPaymentsApplied,
    settledTotal: settledTotal,
    receivedTotal: receivedTotal,
    changeTotal: changeTotal,
    diffItemsOrder: diffItemsOrder,
    diffSettlement: diffSettlement,
    diffPaidTotal: diffPaidTotal,
    diffPendingTotal: diffPendingTotal,
    discountFields: discountResolution.fields,
    discountSources: discountResolution.sources,
    failedCodes: codes,
    diagnostics: diagnostics,
    validations: validations,
    cashPaymentMismatchCount: cashIssues,
    duplicatePaymentCount: duplicateCount,
    auditMode: mode,
  );
}

bool isSalesAuditActivePayment(Payment payment) {
  final status = _normalize(payment.status);
  return status != 'cancelled' &&
      status != 'canceled' &&
      payment.cancelledAt == null &&
      (payment.baseAmount > salesAuditMoneyTolerance ||
          payment.chargedAmount > salesAuditMoneyTolerance ||
          payment.totalAfterDiscount > salesAuditMoneyTolerance ||
          payment.discountAmount > salesAuditMoneyTolerance);
}

double salesAuditMoneyPaymentAmount(Payment payment) {
  if (payment.totalAfterDiscount > salesAuditMoneyTolerance) {
    return payment.totalAfterDiscount;
  }
  if (payment.chargedAmount > salesAuditMoneyTolerance) {
    return payment.chargedAmount;
  }
  if (payment.discountAmount > salesAuditMoneyTolerance &&
      payment.baseAmount > salesAuditMoneyTolerance) {
    return (payment.baseAmount - payment.discountAmount)
        .clamp(0, double.infinity)
        .toDouble();
  }
  if (payment.baseAmount > salesAuditMoneyTolerance) return payment.baseAmount;
  return 0;
}

SalesAuditMode _auditModeFor(PosOrder order) {
  final status = _normalize(order.status);
  final paymentStatus = _normalize(order.paymentStatus);
  if (status == 'cancelled' ||
      status == 'canceled' ||
      order.cancelledAt != null ||
      order.canceledAt != null) {
    return SalesAuditMode.cancelled;
  }
  if (paymentStatus == 'partial') return SalesAuditMode.partial;
  if (status == 'paid' ||
      status == 'closed' ||
      paymentStatus == 'paid' ||
      order.paidAt != null) {
    return SalesAuditMode.paid;
  }
  return SalesAuditMode.pending;
}

bool _pendingOrderLooksConsistent(
  PosOrder order,
  List<OrderItem> activeItems,
  double moneyPaymentsApplied,
) {
  if (moneyPaymentsApplied > salesAuditMoneyTolerance) return false;
  if (activeItems.isEmpty && order.total.abs() <= salesAuditMoneyTolerance) {
    return true;
  }
  return (order.total - order.pendingTotal).abs() <= salesAuditMoneyTolerance &&
      order.paidTotal.abs() <= salesAuditMoneyTolerance;
}

_DiscountResolution _resolveDiscount(
  PosOrder order,
  List<Payment> activePayments,
  double grossItemsTotal,
) {
  final fields = <String, double>{};
  final sources = <SalesAuditDiscountSource>[];
  final orderMoney = <SalesAuditDiscountSource>[];
  final orderPercent = <SalesAuditDiscountSource>[];
  final paymentMoney = <SalesAuditDiscountSource>[];
  final paymentPercent = <SalesAuditDiscountSource>[];

  for (final entry in order.explicitDiscountFields.entries) {
    final field = 'order.${entry.key}';
    final value = entry.value;
    if (value <= salesAuditMoneyTolerance) continue;
    fields[field] = value;
    if (_isPercentField(entry.key)) {
      final normalized = _normalizePercent(value);
      orderPercent.add(
        SalesAuditDiscountSource(
          field: field,
          originalValue: value,
          kind: 'porcentaje',
          normalizedPercent: normalized,
          monetaryAmount: grossItemsTotal * normalized,
          used: false,
          interpretation: 'Porcentaje aplicado al total bruto de items.',
        ),
      );
    } else {
      orderMoney.add(
        SalesAuditDiscountSource(
          field: field,
          originalValue: value,
          kind: 'importe',
          monetaryAmount: value,
          used: false,
          interpretation: 'Importe monetario guardado en la orden.',
        ),
      );
    }
  }

  for (final payment in activePayments) {
    if (payment.discountAmount > salesAuditMoneyTolerance) {
      final field = 'payment.${payment.id}.discountAmount';
      fields[field] = payment.discountAmount;
      paymentMoney.add(
        SalesAuditDiscountSource(
          field: field,
          originalValue: payment.discountAmount,
          kind: 'importe',
          monetaryAmount: payment.discountAmount,
          used: false,
          interpretation: 'Importe monetario de descuento del pago.',
          metadata: _paymentDiscountMetadata(payment),
        ),
      );
    }
    if (payment.appliedDiscountPercent > salesAuditMoneyTolerance) {
      final normalized = _normalizePercent(payment.appliedDiscountPercent);
      final base = payment.subtotalBeforeDiscount > salesAuditMoneyTolerance
          ? payment.subtotalBeforeDiscount
          : payment.baseAmount;
      final field = 'payment.${payment.id}.appliedDiscountPercent';
      fields[field] = payment.appliedDiscountPercent;
      paymentPercent.add(
        SalesAuditDiscountSource(
          field: field,
          originalValue: payment.appliedDiscountPercent,
          kind: 'porcentaje',
          normalizedPercent: normalized,
          monetaryAmount: base * normalized,
          used: false,
          interpretation: 'Porcentaje aplicado al subtotal del pago.',
          metadata: _paymentDiscountMetadata(payment),
        ),
      );
    }
  }

  final selected = _selectDiscountSource(
    orderMoney: orderMoney,
    paymentMoney: paymentMoney,
    orderPercent: orderPercent,
    paymentPercent: paymentPercent,
  );
  final amount = selected.fold<double>(
    0,
    (sum, source) => sum + source.monetaryAmount,
  );
  final selectedKeys = selected.map((source) => source.field).toSet();
  sources.addAll(
    [...orderMoney, ...paymentMoney, ...orderPercent, ...paymentPercent].map((
      source,
    ) {
      return SalesAuditDiscountSource(
        field: source.field,
        originalValue: source.originalValue,
        kind: source.kind,
        monetaryAmount: source.monetaryAmount,
        used: selectedKeys.contains(source.field),
        normalizedPercent: source.normalizedPercent,
        interpretation: source.interpretation,
        metadata: source.metadata,
      );
    }),
  );

  return _DiscountResolution(
    amount: amount.clamp(0, double.infinity).toDouble(),
    fields: fields,
    sources: sources,
  );
}

List<SalesAuditDiscountSource> _selectDiscountSource({
  required List<SalesAuditDiscountSource> orderMoney,
  required List<SalesAuditDiscountSource> paymentMoney,
  required List<SalesAuditDiscountSource> orderPercent,
  required List<SalesAuditDiscountSource> paymentPercent,
}) {
  const orderPriority = [
    'order.totalDiscountAmount',
    'order.totalDiscount',
    'order.discountTotal',
    'order.discountAmount',
    'order.appliedDiscount',
    'order.employeeDiscount',
    'order.partnerDiscount',
    'order.familyDiscount',
    'order.courtesyAmount',
    'order.complimentaryAmount',
    'order.promotionDiscount',
    'order.promoDiscount',
    'order.employeeConsumptionDiscount',
    'order.benefitAmount',
  ];
  for (final key in orderPriority) {
    final match = orderMoney.where((source) => source.field == key).toList();
    if (match.isNotEmpty) return match;
  }
  if (paymentMoney.isNotEmpty) return paymentMoney;
  if (orderPercent.isNotEmpty) return [orderPercent.first];
  if (paymentPercent.isNotEmpty) return paymentPercent;
  return const [];
}

bool _isPercentField(String field) {
  final clean = field.toLowerCase();
  return clean.contains('percent') || clean.contains('percentage');
}

double _normalizePercent(double value) {
  if (value > 1) return value / 100;
  return value;
}

String _paymentDiscountMetadata(Payment payment) {
  return [
    if ((payment.appliedDiscountType ?? '').trim().isNotEmpty)
      'tipo=${payment.appliedDiscountType}',
    if ((payment.appliedDiscountName ?? '').trim().isNotEmpty)
      'nombre=${payment.appliedDiscountName}',
    if ((payment.discountReason ?? '').trim().isNotEmpty)
      'motivo=${payment.discountReason}',
    if ((payment.discountAuthorizationStatus ?? '').trim().isNotEmpty)
      'autorizacion=${payment.discountAuthorizationStatus}',
    if ((payment.employeeName ?? '').trim().isNotEmpty)
      'empleado=${payment.employeeName}',
  ].join(' | ');
}

int _validateCashPayments(
  List<Payment> activePayments,
  void Function(String code, String message) fail,
  List<SalesAuditValidation> validations,
) {
  var issues = 0;
  for (final payment in activePayments.where(
    (payment) => _normalize(payment.method) == 'cash',
  )) {
    final moneyApplied = salesAuditMoneyPaymentAmount(payment);
    final received = payment.cashReceivedAmount;
    final change = payment.cashChangeAmount;
    if (received != null && change != null) {
      final net = received - change;
      final passed = !_outsideTolerance(net - moneyApplied);
      validations.add(
        SalesAuditValidation(
          label: 'Recibido - cambio = pago monetario',
          passed: passed,
          detail: payment.id,
        ),
      );
      if (!passed) {
        issues++;
        fail(
          'cash_net',
          'Efectivo ${payment.id}: recibido - cambio no coincide con pago monetario.',
        );
      }
    }
    if (change != null && change < -salesAuditMoneyTolerance) {
      issues++;
      validations.add(
        SalesAuditValidation(
          label: 'Cambio no negativo',
          passed: false,
          detail: payment.id,
        ),
      );
      fail('cash_net', 'Cambio negativo en pago ${payment.id}.');
    }
    if (received != null &&
        received + salesAuditMoneyTolerance < moneyApplied) {
      issues++;
      validations.add(
        SalesAuditValidation(
          label: 'Recibido suficiente',
          passed: false,
          detail: payment.id,
        ),
      );
      fail('cash_net', 'Pago efectivo mayor a recibido en ${payment.id}.');
    }
  }
  return issues;
}

int _detectDuplicatePayments(
  List<Payment> activePayments,
  void Function(String code, String message) fail,
) {
  var duplicates = 0;
  for (var i = 0; i < activePayments.length; i++) {
    for (var j = i + 1; j < activePayments.length; j++) {
      final a = activePayments[i];
      final b = activePayments[j];
      if (a.id == b.id) continue;
      final sameMethod = _normalize(a.method) == _normalize(b.method);
      final sameAmount = !_outsideTolerance(
        salesAuditMoneyPaymentAmount(a) - salesAuditMoneyPaymentAmount(b),
      );
      final nearTime = _nearCreatedAt(a.createdAt, b.createdAt);
      if (sameMethod && sameAmount && nearTime) {
        duplicates++;
        fail('duplicate_payment', 'Posible pago duplicado: ${a.id} y ${b.id}.');
      }
    }
  }
  return duplicates;
}

bool _nearCreatedAt(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.difference(b).abs() <= const Duration(minutes: 2);
}

SalesAuditResult _result({
  required List<OrderItem> activeItems,
  required List<OrderItem> cancelledItems,
  required List<Payment> activePayments,
  required double grossItemsTotal,
  required double monetaryDiscountApplied,
  required double netCustomerDue,
  required double moneyPaymentsApplied,
  required double settledTotal,
  required double receivedTotal,
  required double changeTotal,
  required double diffItemsOrder,
  required double diffSettlement,
  required double diffPaidTotal,
  required double diffPendingTotal,
  required Map<String, double> discountFields,
  required List<SalesAuditDiscountSource> discountSources,
  required List<String> failedCodes,
  required List<String> diagnostics,
  required List<SalesAuditValidation> validations,
  required int cashPaymentMismatchCount,
  required int duplicatePaymentCount,
  required SalesAuditMode auditMode,
}) {
  return SalesAuditResult(
    activeItems: activeItems,
    cancelledItems: cancelledItems,
    activePayments: activePayments,
    grossItemsTotal: grossItemsTotal,
    monetaryDiscountApplied: monetaryDiscountApplied,
    netCustomerDue: netCustomerDue,
    moneyPaymentsApplied: moneyPaymentsApplied,
    settledTotal: settledTotal,
    receivedTotal: receivedTotal,
    changeTotal: changeTotal,
    diffItemsOrder: diffItemsOrder,
    diffSettlement: diffSettlement,
    diffPaidTotal: diffPaidTotal,
    diffPendingTotal: diffPendingTotal,
    discountFields: discountFields,
    discountSources: discountSources,
    failedCodes: failedCodes,
    diagnostics: diagnostics.isEmpty
        ? const ['Sin discrepancias.']
        : diagnostics,
    validations: validations,
    cashPaymentMismatchCount: cashPaymentMismatchCount,
    duplicatePaymentCount: duplicatePaymentCount,
    auditMode: auditMode,
  );
}

class _DiscountResolution {
  const _DiscountResolution({
    required this.amount,
    required this.fields,
    required this.sources,
  });

  final double amount;
  final Map<String, double> fields;
  final List<SalesAuditDiscountSource> sources;
}

bool _outsideTolerance(double value) => value.abs() > salesAuditMoneyTolerance;

String _normalize(String value) => value.trim().toLowerCase();
