import '../orders/order_payment_reconciliation.dart';
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
    required this.cashPaid,
    required this.cardPaid,
    required this.employeeConsumptionMonetary,
    required this.otherMonetaryPaid,
    required this.cardFeeTotal,
    required this.tipTotal,
    required this.settledTotal,
    required this.expectedPendingTotal,
    required this.overLiquidatedTotal,
    required this.receivedTotal,
    required this.changeTotal,
    required this.diffItemsOrder,
    required this.diffSettlement,
    required this.diffPaidTotal,
    required this.diffPendingTotal,
    required this.discountFields,
    required this.discountSources,
    required this.discountPercentNormalized,
    required this.discountTypeLabel,
    required this.discountName,
    required this.discountReason,
    required this.discountBeneficiary,
    required this.discountAuthorizedBy,
    required this.discountSourceFields,
    required this.failedCodes,
    required this.discrepancies,
    required this.diagnostics,
    required this.validations,
    required this.cashPaymentMismatchCount,
    required this.duplicatePaymentCount,
    required this.auditMode,
    this.storedOrderDiscount = 0,
    this.reconstructedPaymentDiscount = 0,
    this.historicalDiscountDifference = 0,
  });

  final List<OrderItem> activeItems;
  final List<OrderItem> cancelledItems;
  final List<Payment> activePayments;
  final double grossItemsTotal;
  final double monetaryDiscountApplied;
  final double netCustomerDue;
  final double moneyPaymentsApplied;
  final double cashPaid;
  final double cardPaid;
  final double employeeConsumptionMonetary;
  final double otherMonetaryPaid;
  final double cardFeeTotal;
  final double tipTotal;
  final double settledTotal;
  final double expectedPendingTotal;
  final double overLiquidatedTotal;
  final double receivedTotal;
  final double changeTotal;
  final double diffItemsOrder;
  final double diffSettlement;
  final double diffPaidTotal;
  final double diffPendingTotal;
  final Map<String, double> discountFields;
  final List<SalesAuditDiscountSource> discountSources;
  final double storedOrderDiscount;
  final double reconstructedPaymentDiscount;
  final double historicalDiscountDifference;
  bool get hasHistoricalDiscountAggregateMismatch =>
      storedOrderDiscount > salesAuditMoneyTolerance &&
      reconstructedPaymentDiscount > salesAuditMoneyTolerance &&
      historicalDiscountDifference.abs() > salesAuditMoneyTolerance;
  final double? discountPercentNormalized;
  final String discountTypeLabel;
  final String discountName;
  final String discountReason;
  final String discountBeneficiary;
  final String discountAuthorizedBy;
  final String discountSourceFields;
  final List<String> failedCodes;
  final List<SalesAuditDiscrepancy> discrepancies;
  final List<String> diagnostics;
  final List<SalesAuditValidation> validations;
  final int cashPaymentMismatchCount;
  final int duplicatePaymentCount;
  final SalesAuditMode auditMode;

  bool get hasDiscrepancy => failedCodes.isNotEmpty;
}

class SalesAuditDiscrepancy {
  const SalesAuditDiscrepancy({
    required this.code,
    required this.label,
    required this.expected,
    required this.found,
    required this.difference,
    required this.probableOrigin,
  });

  final String code;
  final String label;
  final double expected;
  final double found;
  final double difference;
  final String probableOrigin;
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
    this.discountTypeLabel = 'Sin descuento',
    this.discountName = '',
    this.discountReason = '',
    this.discountBeneficiary = '',
    this.discountAuthorizedBy = '',
    this.appliedAt,
    this.normalizedPercent,
    this.interpretation = '',
    this.metadata = '',
  });

  final String field;
  final double originalValue;
  final String kind;
  final double monetaryAmount;
  final bool used;
  final String discountTypeLabel;
  final String discountName;
  final String discountReason;
  final String discountBeneficiary;
  final String discountAuthorizedBy;
  final DateTime? appliedAt;
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
  final storedOrderDiscount = discountResolution.storedOrderDiscount;
  final reconstructedPaymentDiscount =
      discountResolution.reconstructedPaymentDiscount;
  final historicalDiscountDifference =
      discountResolution.historicalDiscountDifference;
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
  final overLiquidatedTotal = (settledTotal - grossItemsTotal)
      .clamp(0, double.infinity)
      .toDouble();
  final diffItemsOrder = order.total - grossItemsTotal;
  final diffSettlement = settledTotal - grossItemsTotal;
  final diffPaidTotal = order.paidTotal - settledTotal;
  final diffPendingTotal = order.pendingTotal - expectedPending;
  final codes = <String>[];
  final discrepancies = <SalesAuditDiscrepancy>[];
  final diagnostics = <String>[];
  final validations = <SalesAuditValidation>[];

  void fail(
    String code,
    String message, {
    double expected = 0,
    double found = 0,
    String probableOrigin = '',
  }) {
    if (!codes.contains(code)) codes.add(code);
    final difference = found - expected;
    if (!discrepancies.any(
      (entry) =>
          entry.code == code &&
          (entry.expected - expected).abs() <= salesAuditMoneyTolerance &&
          (entry.found - found).abs() <= salesAuditMoneyTolerance,
    )) {
      discrepancies.add(
        SalesAuditDiscrepancy(
          code: code,
          label: _discrepancyLabel(code),
          expected: expected,
          found: found,
          difference: difference,
          probableOrigin: probableOrigin.isEmpty
              ? _probableOriginFor(code)
              : probableOrigin,
        ),
      );
    }
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
    if (!passed && failMessage.isNotEmpty) {
      final (expected, found) = _expectedFoundForCode(
        code,
        order: order,
        grossItemsTotal: grossItemsTotal,
        settledTotal: settledTotal,
        expectedPending: expectedPending,
      );
      fail(code, failMessage, expected: expected, found: found);
    }
  }

  final hasStoredAndReconstructedDiscount =
      storedOrderDiscount > salesAuditMoneyTolerance &&
      reconstructedPaymentDiscount > salesAuditMoneyTolerance;
  if (hasStoredAndReconstructedDiscount &&
      _outsideTolerance(historicalDiscountDifference)) {
    validations.add(
      const SalesAuditValidation(
        label: 'Inconsistencia de agregado historico',
        passed: false,
      ),
    );
    fail(
      'historical_discount_aggregate',
      'Descuento guardado en orden ${storedOrderDiscount.toStringAsFixed(2)}; '
          'reconstruido desde pagos ${reconstructedPaymentDiscount.toStringAsFixed(2)}; '
          'diferencia ${historicalDiscountDifference.toStringAsFixed(2)}.',
      expected: reconstructedPaymentDiscount,
      found: storedOrderDiscount,
      probableOrigin:
          'Cabecera historica de descuento quedo stale; los pagos conservan el descuento correcto.',
    );
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
      discountPercentNormalized: discountResolution.percentNormalized,
      discountTypeLabel: discountResolution.typeLabel,
      discountName: discountResolution.name,
      discountReason: discountResolution.reason,
      discountBeneficiary: discountResolution.beneficiary,
      discountAuthorizedBy: discountResolution.authorizedBy,
      discountSourceFields: discountResolution.sourceFields,
      failedCodes: codes,
      discrepancies: discrepancies,
      diagnostics: diagnostics,
      validations: validations,
      cashPaymentMismatchCount: 0,
      duplicatePaymentCount: 0,
      auditMode: mode,
      storedOrderDiscount: storedOrderDiscount,
      reconstructedPaymentDiscount: reconstructedPaymentDiscount,
      historicalDiscountDifference: historicalDiscountDifference,
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
      discountPercentNormalized: discountResolution.percentNormalized,
      discountTypeLabel: discountResolution.typeLabel,
      discountName: discountResolution.name,
      discountReason: discountResolution.reason,
      discountBeneficiary: discountResolution.beneficiary,
      discountAuthorizedBy: discountResolution.authorizedBy,
      discountSourceFields: discountResolution.sourceFields,
      failedCodes: codes,
      discrepancies: discrepancies,
      diagnostics: diagnostics,
      validations: validations,
      cashPaymentMismatchCount: 0,
      duplicatePaymentCount: 0,
      auditMode: mode,
      storedOrderDiscount: storedOrderDiscount,
      reconstructedPaymentDiscount: reconstructedPaymentDiscount,
      historicalDiscountDifference: historicalDiscountDifference,
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
      discountPercentNormalized: discountResolution.percentNormalized,
      discountTypeLabel: discountResolution.typeLabel,
      discountName: discountResolution.name,
      discountReason: discountResolution.reason,
      discountBeneficiary: discountResolution.beneficiary,
      discountAuthorizedBy: discountResolution.authorizedBy,
      discountSourceFields: discountResolution.sourceFields,
      failedCodes: codes,
      discrepancies: discrepancies,
      diagnostics: diagnostics,
      validations: validations,
      cashPaymentMismatchCount: cashIssues,
      duplicatePaymentCount: duplicateCount,
      auditMode: mode,
      storedOrderDiscount: storedOrderDiscount,
      reconstructedPaymentDiscount: reconstructedPaymentDiscount,
      historicalDiscountDifference: historicalDiscountDifference,
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
  if (overLiquidatedTotal > salesAuditMoneyTolerance) {
    final activePaymentGross = activePayments.fold<double>(
      0,
      (sum, payment) => sum + payment.baseAmount,
    );
    fail(
      activePaymentGross > grossItemsTotal + salesAuditMoneyTolerance
          ? 'cancellation_after_payment'
          : 'over_liquidated',
      'Sobreliquidacion detectada por ${overLiquidatedTotal.toStringAsFixed(2)}.',
      expected: grossItemsTotal,
      found: settledTotal,
      probableOrigin: activePaymentGross > grossItemsTotal
          ? 'Pago previo mayor al total activo; posible cancelacion posterior sin reversa equivalente.'
          : 'Pagos monetarios y descuentos superan el total activo.',
    );
  }

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
    discountPercentNormalized: discountResolution.percentNormalized,
    discountTypeLabel: discountResolution.typeLabel,
    discountName: discountResolution.name,
    discountReason: discountResolution.reason,
    discountBeneficiary: discountResolution.beneficiary,
    discountAuthorizedBy: discountResolution.authorizedBy,
    discountSourceFields: discountResolution.sourceFields,
    failedCodes: codes,
    discrepancies: discrepancies,
    diagnostics: diagnostics,
    validations: validations,
    cashPaymentMismatchCount: cashIssues,
    duplicatePaymentCount: duplicateCount,
    auditMode: mode,
    storedOrderDiscount: storedOrderDiscount,
    reconstructedPaymentDiscount: reconstructedPaymentDiscount,
    historicalDiscountDifference: historicalDiscountDifference,
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
  return paymentMonetaryAppliedToSale(payment);
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
          discountTypeLabel: _discountTypeLabel(
            rawType: order.discountType,
            rawName: order.discountName,
            sourceField: entry.key,
            hasDiscount: true,
          ),
          discountName: order.discountName ?? '',
          discountReason: order.discountReason ?? '',
          discountBeneficiary: order.discountBeneficiaryEmployeeName ?? '',
          discountAuthorizedBy: order.discountAuthorizedByEmployeeName ?? '',
          appliedAt: order.discountAppliedAt,
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
          discountTypeLabel: _discountTypeLabel(
            rawType: order.discountType,
            rawName: order.discountName,
            sourceField: entry.key,
            hasDiscount: true,
          ),
          discountName: order.discountName ?? '',
          discountReason: order.discountReason ?? '',
          discountBeneficiary: order.discountBeneficiaryEmployeeName ?? '',
          discountAuthorizedBy: order.discountAuthorizedByEmployeeName ?? '',
          appliedAt: order.discountAppliedAt,
          interpretation: 'Importe monetario guardado en la orden.',
        ),
      );
    }
  }

  for (final payment in activePayments) {
    final paymentDiscount = paymentDiscountAppliedToSale(payment);
    if (paymentDiscount > salesAuditMoneyTolerance) {
      final field = 'payment.${payment.id}.discountAmount';
      fields[field] = paymentDiscount;
      paymentMoney.add(
        SalesAuditDiscountSource(
          field: field,
          originalValue: payment.discountAmount,
          kind: 'importe',
          monetaryAmount: paymentDiscount,
          used: false,
          discountTypeLabel: _discountTypeLabel(
            rawType: payment.appliedDiscountType,
            rawName: payment.appliedDiscountName,
            sourceField: 'discountAmount',
            hasDiscount: true,
          ),
          discountName: payment.appliedDiscountName ?? '',
          discountReason: payment.discountReason ?? '',
          discountBeneficiary: payment.discountEmployeeBeneficiaryName ?? '',
          discountAuthorizedBy:
              payment.discountAuthorizedByPartnerName ??
              payment.discountAuthorizedByPartnerLinkedEmployeeName ??
              '',
          interpretation:
              (paymentDiscount - payment.discountAmount).abs() >
                  salesAuditMoneyTolerance
              ? 'Importe de descuento reconstruido desde la politica del pago.'
              : 'Importe monetario de descuento del pago.',
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
          discountTypeLabel: _discountTypeLabel(
            rawType: payment.appliedDiscountType,
            rawName: payment.appliedDiscountName,
            sourceField: 'appliedDiscountPercent',
            hasDiscount: true,
          ),
          discountName: payment.appliedDiscountName ?? '',
          discountReason: payment.discountReason ?? '',
          discountBeneficiary: payment.discountEmployeeBeneficiaryName ?? '',
          discountAuthorizedBy:
              payment.discountAuthorizedByPartnerName ??
              payment.discountAuthorizedByPartnerLinkedEmployeeName ??
              '',
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
  final storedOrderDiscount = _storedOrderDiscountAmount(orderMoney);
  final reconstructedPaymentDiscount = paymentMoney.fold<double>(
    0,
    (sum, source) => sum + source.monetaryAmount,
  );
  final historicalDiscountDifference =
      reconstructedPaymentDiscount - storedOrderDiscount;
  final amount = selected.fold<double>(
    0,
    (sum, source) => sum + source.monetaryAmount,
  );
  final normalizedPercent = _selectedDiscountPercent(
    selected,
    amount,
    grossItemsTotal,
  );
  final selectedType = _selectedText(
    selected,
    (source) => source.discountTypeLabel,
    fallback: amount > salesAuditMoneyTolerance
        ? 'Tipo no identificado'
        : 'Sin descuento',
  );
  final selectedName = _selectedText(selected, (source) => source.discountName);
  final selectedReason = _selectedText(
    selected,
    (source) => source.discountReason,
  );
  final selectedBeneficiary = _selectedText(
    selected,
    (source) => source.discountBeneficiary,
  );
  final selectedAuthorizedBy = _selectedText(
    selected,
    (source) => source.discountAuthorizedBy,
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
        discountTypeLabel: source.discountTypeLabel,
        discountName: source.discountName,
        discountReason: source.discountReason,
        discountBeneficiary: source.discountBeneficiary,
        discountAuthorizedBy: source.discountAuthorizedBy,
        appliedAt: source.appliedAt,
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
    percentNormalized: normalizedPercent,
    typeLabel: selectedType,
    name: selectedName,
    reason: selectedReason,
    beneficiary: selectedBeneficiary,
    authorizedBy: selectedAuthorizedBy,
    sourceFields: selected.map((source) => source.field).join(' | '),
    storedOrderDiscount: storedOrderDiscount,
    reconstructedPaymentDiscount: reconstructedPaymentDiscount,
    historicalDiscountDifference: historicalDiscountDifference,
  );
}

List<SalesAuditDiscountSource> _selectDiscountSource({
  required List<SalesAuditDiscountSource> orderMoney,
  required List<SalesAuditDiscountSource> paymentMoney,
  required List<SalesAuditDiscountSource> orderPercent,
  required List<SalesAuditDiscountSource> paymentPercent,
}) {
  if (paymentMoney.isNotEmpty) return paymentMoney;
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
  if (orderPercent.isNotEmpty) return [orderPercent.first];
  if (paymentPercent.isNotEmpty) return paymentPercent;
  return const [];
}

double _storedOrderDiscountAmount(List<SalesAuditDiscountSource> orderMoney) {
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
    if (match.isNotEmpty) return match.first.monetaryAmount;
  }
  return orderMoney.fold<double>(
    0,
    (sum, source) => sum + source.monetaryAmount,
  );
}

bool _isPercentField(String field) {
  final clean = field.toLowerCase();
  return clean.contains('percent') || clean.contains('percentage');
}

double _normalizePercent(double value) {
  if (value > 1) return value / 100;
  return value;
}

double? _selectedDiscountPercent(
  List<SalesAuditDiscountSource> selected,
  double amount,
  double grossItemsTotal,
) {
  for (final source in selected) {
    final percent = source.normalizedPercent;
    if (percent != null && percent > 0) return percent;
  }
  if (amount > salesAuditMoneyTolerance &&
      grossItemsTotal > salesAuditMoneyTolerance) {
    return amount / grossItemsTotal;
  }
  return null;
}

String _selectedText(
  List<SalesAuditDiscountSource> selected,
  String Function(SalesAuditDiscountSource source) read, {
  String fallback = '',
}) {
  for (final source in selected) {
    final value = read(source).trim();
    if (value.isNotEmpty &&
        value != 'Sin descuento' &&
        value != 'Tipo no identificado') {
      return value;
    }
  }
  return fallback;
}

String _discountTypeLabel({
  required String? rawType,
  required String? rawName,
  required String sourceField,
  required bool hasDiscount,
}) {
  if (!hasDiscount) return 'Sin descuento';
  final clean = [
    rawType,
    rawName,
    sourceField,
  ].whereType<String>().join(' ').toLowerCase();
  if (clean.contains('employee_free_meal') ||
      clean.contains('free_meal') ||
      clean.contains('free meal') ||
      clean.contains('comida empleado') ||
      clean.contains('comida de empleado')) {
    return 'Comida empleado';
  }
  if (clean.contains('employee_30')) return 'Empleado 30%';
  if (clean.contains('employee')) return 'Empleado';
  if (clean.contains('partner') || clean.contains('socio')) return 'Socio';
  if (clean.contains('family') ||
      clean.contains('familia') ||
      clean.contains('friends')) {
    return 'Amigos/Familia';
  }
  if (clean.contains('courtesy') ||
      clean.contains('cortesia') ||
      clean.contains('complimentary')) {
    return 'Cortesia';
  }
  if (clean.contains('promotion') || clean.contains('promo')) {
    return 'Promocion';
  }
  if (clean.contains('manual')) return 'Manual';
  if ((rawType ?? '').trim().isEmpty && (rawName ?? '').trim().isEmpty) {
    return 'Tipo no identificado';
  }
  return (rawName ?? rawType ?? '').trim();
}

String _paymentDiscountMetadata(Payment payment) {
  return [
    if ((payment.discountSource ?? '').trim().isNotEmpty)
      'origen=${payment.discountSource}',
    if ((payment.discountCatalogId ?? '').trim().isNotEmpty)
      'catalogo=${payment.discountCatalogId}',
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
    if (payment.orderGrossSubtotal > 0)
      'subtotalOrden=${payment.orderGrossSubtotal.toStringAsFixed(2)}',
    if (payment.orderDiscountAmount > 0)
      'descuentoOrden=${payment.orderDiscountAmount.toStringAsFixed(2)}',
    if (payment.orderNetTotal > 0)
      'netoOrden=${payment.orderNetTotal.toStringAsFixed(2)}',
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
  required double? discountPercentNormalized,
  required String discountTypeLabel,
  required String discountName,
  required String discountReason,
  required String discountBeneficiary,
  required String discountAuthorizedBy,
  required String discountSourceFields,
  required List<String> failedCodes,
  required List<SalesAuditDiscrepancy> discrepancies,
  required List<String> diagnostics,
  required List<SalesAuditValidation> validations,
  required int cashPaymentMismatchCount,
  required int duplicatePaymentCount,
  required SalesAuditMode auditMode,
  double storedOrderDiscount = 0,
  double reconstructedPaymentDiscount = 0,
  double historicalDiscountDifference = 0,
}) {
  final reconciliation = reconcileOrderPayments(
    orderGrossTotal: grossItemsTotal,
    activePayments: activePayments.map(PaymentSettlementInput.fromPayment),
  );
  final expectedPendingTotal = (grossItemsTotal - settledTotal)
      .clamp(0, double.infinity)
      .toDouble();
  final overLiquidatedTotal = (settledTotal - grossItemsTotal)
      .clamp(0, double.infinity)
      .toDouble();
  return SalesAuditResult(
    activeItems: activeItems,
    cancelledItems: cancelledItems,
    activePayments: activePayments,
    grossItemsTotal: grossItemsTotal,
    monetaryDiscountApplied: monetaryDiscountApplied,
    netCustomerDue: netCustomerDue,
    moneyPaymentsApplied: moneyPaymentsApplied,
    cashPaid: reconciliation.cashPaid,
    cardPaid: reconciliation.cardPaid,
    employeeConsumptionMonetary: reconciliation.employeeConsumptionMonetary,
    otherMonetaryPaid: reconciliation.otherMonetaryPaid,
    cardFeeTotal: reconciliation.cardFeeTotal,
    tipTotal: reconciliation.tipTotal,
    settledTotal: settledTotal,
    expectedPendingTotal: expectedPendingTotal,
    overLiquidatedTotal: overLiquidatedTotal,
    receivedTotal: receivedTotal,
    changeTotal: changeTotal,
    diffItemsOrder: diffItemsOrder,
    diffSettlement: diffSettlement,
    diffPaidTotal: diffPaidTotal,
    diffPendingTotal: diffPendingTotal,
    discountFields: discountFields,
    discountSources: discountSources,
    discountPercentNormalized: discountPercentNormalized,
    discountTypeLabel: discountTypeLabel,
    discountName: discountName,
    discountReason: discountReason,
    discountBeneficiary: discountBeneficiary,
    discountAuthorizedBy: discountAuthorizedBy,
    discountSourceFields: discountSourceFields,
    failedCodes: failedCodes,
    discrepancies: discrepancies,
    diagnostics: diagnostics.isEmpty
        ? const ['Sin discrepancias.']
        : diagnostics,
    validations: validations,
    cashPaymentMismatchCount: cashPaymentMismatchCount,
    duplicatePaymentCount: duplicatePaymentCount,
    auditMode: auditMode,
    storedOrderDiscount: storedOrderDiscount,
    reconstructedPaymentDiscount: reconstructedPaymentDiscount,
    historicalDiscountDifference: historicalDiscountDifference,
  );
}

class _DiscountResolution {
  const _DiscountResolution({
    required this.amount,
    required this.fields,
    required this.sources,
    required this.percentNormalized,
    required this.typeLabel,
    required this.name,
    required this.reason,
    required this.beneficiary,
    required this.authorizedBy,
    required this.sourceFields,
    required this.storedOrderDiscount,
    required this.reconstructedPaymentDiscount,
    required this.historicalDiscountDifference,
  });

  final double amount;
  final Map<String, double> fields;
  final List<SalesAuditDiscountSource> sources;
  final double? percentNormalized;
  final String typeLabel;
  final String name;
  final String reason;
  final String beneficiary;
  final String authorizedBy;
  final String sourceFields;
  final double storedOrderDiscount;
  final double reconstructedPaymentDiscount;
  final double historicalDiscountDifference;
}

bool _outsideTolerance(double value) => value.abs() > salesAuditMoneyTolerance;

String _normalize(String value) => value.trim().toLowerCase();

(double, double) _expectedFoundForCode(
  String code, {
  required PosOrder order,
  required double grossItemsTotal,
  required double settledTotal,
  required double expectedPending,
}) {
  return switch (code) {
    'items_order' => (grossItemsTotal, order.total),
    'payments_order' => (grossItemsTotal, settledTotal),
    'paid_total' => (settledTotal, order.paidTotal),
    'pending_total' => (expectedPending, order.pendingTotal),
    'paid_incomplete' => (grossItemsTotal, settledTotal),
    'negative_total' => (0, order.total),
    _ => (0, 0),
  };
}

String _discrepancyLabel(String code) {
  return switch (code) {
    'historical_discount_aggregate' => 'HEADER_STALE',
    'items_order' => 'ACTIVE_ITEMS_VS_GROSS',
    'discount_inconsistent' => 'DISCOUNT_MISSING_OR_STALE',
    'payments_order' => 'LIQUIDATED_VS_GROSS',
    'cash_net' => 'CASH_RECEIVED_CHANGE_MISMATCH',
    'paid_total' => 'PAID_TOTAL_VS_LIQUIDATED',
    'pending_total' => 'PENDING_TOTAL_MISMATCH',
    'duplicate_payment' => 'DUPLICATE_PAYMENT',
    'paid_incomplete' => 'PAID_ORDER_INCOMPLETE',
    'cancelled_active_payments' => 'CANCELLED_ORDER_ACTIVE_PAYMENTS',
    'state_inconsistent' => 'STATE_INCONSISTENT',
    'negative_total' => 'NEGATIVE_TOTAL',
    'over_liquidated' => 'OVER_LIQUIDATED',
    'cancellation_after_payment' => 'CANCELLATION_AFTER_PAYMENT',
    _ => 'OTHER',
  };
}

String _probableOriginFor(String code) {
  return switch (code) {
    'historical_discount_aggregate' =>
      'Agregado historico de descuento en orden no coincide con pagos.',
    'items_order' =>
      'El total guardado de la orden no coincide con items activos.',
    'discount_inconsistent' =>
      'Descuento no registrado o agregado de cabecera obsoleto.',
    'payments_order' =>
      'Pago monetario mas descuento no liquida el total activo.',
    'cash_net' =>
      'Efectivo recibido menos cambio no coincide con monto aplicado.',
    'paid_total' =>
      'paidTotal debe representar importe liquidado aplicado a la orden.',
    'pending_total' =>
      'pendingTotal no coincide con total activo menos liquidado.',
    'duplicate_payment' => 'Pagos activos similares en una ventana corta.',
    'paid_incomplete' =>
      'La orden esta marcada pagada sin liquidacion completa.',
    'cancelled_active_payments' =>
      'La orden fue cancelada pero conserva pagos activos.',
    'state_inconsistent' => 'Estado operativo y saldos no coinciden.',
    'negative_total' => 'Total guardado negativo.',
    'over_liquidated' =>
      'Pagos y descuentos superan el total activo de articulos.',
    'cancellation_after_payment' =>
      'Cancelacion posterior al cobro sin reversa equivalente.',
    _ => 'Requiere revision manual.',
  };
}
