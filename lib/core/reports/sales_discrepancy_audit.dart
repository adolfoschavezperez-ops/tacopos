import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';

const salesAuditMoneyTolerance = 0.02;

class SalesAuditResult {
  const SalesAuditResult({
    required this.activeItems,
    required this.cancelledItems,
    required this.activePayments,
    required this.itemsSubtotal,
    required this.explicitDiscountTotal,
    required this.expectedOrderTotal,
    required this.paymentsAppliedTotal,
    required this.receivedTotal,
    required this.changeTotal,
    required this.diffItemsOrder,
    required this.diffPaymentsOrder,
    required this.diffPaidTotal,
    required this.diffPendingTotal,
    required this.discountFields,
    required this.paymentDiscountTotal,
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
  final double itemsSubtotal;
  final double explicitDiscountTotal;
  final double expectedOrderTotal;
  final double paymentsAppliedTotal;
  final double receivedTotal;
  final double changeTotal;
  final double diffItemsOrder;
  final double diffPaymentsOrder;
  final double diffPaidTotal;
  final double diffPendingTotal;
  final Map<String, double> discountFields;
  final double paymentDiscountTotal;
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
  final itemsSubtotal = activeItems.fold<double>(
    0,
    (sum, item) => sum + (item.qty * item.unitPrice),
  );
  final paymentDiscountTotal = _paymentDiscountTotal(activePayments);
  final discountFields = _discountFieldsFor(order, activePayments);
  final explicitDiscountTotal = _explicitDiscountTotal(
    orderDiscount: order.explicitDiscount,
    paymentDiscountTotal: paymentDiscountTotal,
  );
  final expectedOrderTotal = (itemsSubtotal - explicitDiscountTotal)
      .clamp(0, double.infinity)
      .toDouble();
  final paymentsAppliedTotal = activePayments.fold<double>(
    0,
    (sum, payment) => sum + salesAuditPaymentAppliedAmount(payment),
  );
  final receivedTotal = activePayments.fold<double>(
    0,
    (sum, payment) => sum + (payment.cashReceivedAmount ?? 0),
  );
  final changeTotal = activePayments.fold<double>(
    0,
    (sum, payment) => sum + (payment.cashChangeAmount ?? 0),
  );
  final expectedPending = (order.total - paymentsAppliedTotal)
      .clamp(0, double.infinity)
      .toDouble();
  final diffItemsOrder = order.total - expectedOrderTotal;
  final diffPaymentsOrder = paymentsAppliedTotal - order.total;
  final diffPaidTotal = order.paidTotal - paymentsAppliedTotal;
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
      _pendingOrderLooksConsistent(order, activeItems, paymentsAppliedTotal),
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
      order: order,
      activeItems: activeItems,
      cancelledItems: cancelledItems,
      activePayments: activePayments,
      itemsSubtotal: itemsSubtotal,
      explicitDiscountTotal: explicitDiscountTotal,
      expectedOrderTotal: expectedOrderTotal,
      paymentsAppliedTotal: paymentsAppliedTotal,
      receivedTotal: receivedTotal,
      changeTotal: changeTotal,
      diffItemsOrder: diffItemsOrder,
      diffPaymentsOrder: diffPaymentsOrder,
      diffPaidTotal: diffPaidTotal,
      diffPendingTotal: diffPendingTotal,
      discountFields: discountFields,
      paymentDiscountTotal: paymentDiscountTotal,
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
      order: order,
      activeItems: activeItems,
      cancelledItems: cancelledItems,
      activePayments: activePayments,
      itemsSubtotal: itemsSubtotal,
      explicitDiscountTotal: explicitDiscountTotal,
      expectedOrderTotal: expectedOrderTotal,
      paymentsAppliedTotal: paymentsAppliedTotal,
      receivedTotal: receivedTotal,
      changeTotal: changeTotal,
      diffItemsOrder: diffItemsOrder,
      diffPaymentsOrder: diffPaymentsOrder,
      diffPaidTotal: diffPaidTotal,
      diffPendingTotal: diffPendingTotal,
      discountFields: discountFields,
      paymentDiscountTotal: paymentDiscountTotal,
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
      'paidTotal = pagos activos',
      !_outsideTolerance(diffPaidTotal),
      code: 'paid_total',
      failMessage:
          'paidTotal vs suma de pagos activos: diferencia ${diffPaidTotal.toStringAsFixed(2)}.',
    );
    validation(
      'pendingTotal = total - paidTotal',
      !_outsideTolerance(order.pendingTotal - (order.total - order.paidTotal)),
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
      order: order,
      activeItems: activeItems,
      cancelledItems: cancelledItems,
      activePayments: activePayments,
      itemsSubtotal: itemsSubtotal,
      explicitDiscountTotal: explicitDiscountTotal,
      expectedOrderTotal: expectedOrderTotal,
      paymentsAppliedTotal: paymentsAppliedTotal,
      receivedTotal: receivedTotal,
      changeTotal: changeTotal,
      diffItemsOrder: diffItemsOrder,
      diffPaymentsOrder: diffPaymentsOrder,
      diffPaidTotal: diffPaidTotal,
      diffPendingTotal: diffPendingTotal,
      discountFields: discountFields,
      paymentDiscountTotal: paymentDiscountTotal,
      failedCodes: codes,
      diagnostics: diagnostics,
      validations: validations,
      cashPaymentMismatchCount: cashIssues,
      duplicatePaymentCount: duplicateCount,
      auditMode: mode,
    );
  }

  final itemsTotalMatches = !_outsideTolerance(
    expectedOrderTotal - order.total,
  );
  final missingDiscountLike =
      explicitDiscountTotal <= salesAuditMoneyTolerance &&
      itemsSubtotal > order.total + salesAuditMoneyTolerance;
  validation(
    'Subtotal - descuento = total orden',
    itemsTotalMatches,
    code: 'items_order',
    failMessage:
        'Items/descuento vs total orden: diferencia ${(order.total - expectedOrderTotal).toStringAsFixed(2)}.',
  );
  if (!itemsTotalMatches && missingDiscountLike) {
    fail(
      'discount_inconsistent',
      'Posible descuento no registrado o total incorrecto.',
    );
  }
  validation(
    'Total pagos activos = total orden',
    !_outsideTolerance(diffPaymentsOrder),
    code: 'payments_order',
    failMessage:
        'Pagos vs total orden: diferencia ${diffPaymentsOrder.toStringAsFixed(2)}.',
  );
  validation(
    'paidTotal = pagos activos',
    !_outsideTolerance(diffPaidTotal),
    code: 'paid_total',
    failMessage:
        'paidTotal vs suma de pagos activos: diferencia ${diffPaidTotal.toStringAsFixed(2)}.',
  );
  validation(
    'pendingTotal pagado = 0',
    order.pendingTotal.abs() <= salesAuditMoneyTolerance,
    code: 'pending_total',
    failMessage: 'Orden pagada con saldo pendiente.',
  );
  validation(
    'Orden pagada completa',
    paymentsAppliedTotal + salesAuditMoneyTolerance >= order.total &&
        order.paidTotal + salesAuditMoneyTolerance >= order.total,
    code: 'paid_incomplete',
    failMessage: 'Orden marcada pagada sin importe completo.',
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
    order: order,
    activeItems: activeItems,
    cancelledItems: cancelledItems,
    activePayments: activePayments,
    itemsSubtotal: itemsSubtotal,
    explicitDiscountTotal: explicitDiscountTotal,
    expectedOrderTotal: expectedOrderTotal,
    paymentsAppliedTotal: paymentsAppliedTotal,
    receivedTotal: receivedTotal,
    changeTotal: changeTotal,
    diffItemsOrder: diffItemsOrder,
    diffPaymentsOrder: diffPaymentsOrder,
    diffPaidTotal: diffPaidTotal,
    diffPendingTotal: diffPendingTotal,
    discountFields: discountFields,
    paymentDiscountTotal: paymentDiscountTotal,
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
      salesAuditPaymentAppliedAmount(payment) > 0;
}

double salesAuditPaymentAppliedAmount(Payment payment) {
  if (payment.discountAmount > salesAuditMoneyTolerance &&
      payment.totalAfterDiscount > 0) {
    return payment.totalAfterDiscount;
  }
  if (payment.baseAmount > 0) return payment.baseAmount;
  if (payment.amount > 0) return payment.amount;
  if (payment.totalAfterDiscount > 0) return payment.totalAfterDiscount;
  if (payment.chargedAmount > 0) return payment.chargedAmount;
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
  double paymentsAppliedTotal,
) {
  if (paymentsAppliedTotal > salesAuditMoneyTolerance) return false;
  if (activeItems.isEmpty && order.total.abs() <= salesAuditMoneyTolerance) {
    return true;
  }
  return (order.total - order.pendingTotal).abs() <= salesAuditMoneyTolerance &&
      order.paidTotal.abs() <= salesAuditMoneyTolerance;
}

Map<String, double> _discountFieldsFor(
  PosOrder order,
  List<Payment> activePayments,
) {
  final fields = <String, double>{};
  for (final entry in order.explicitDiscountFields.entries) {
    if (entry.value > salesAuditMoneyTolerance) {
      fields['order.${entry.key}'] = entry.value;
    }
  }
  for (final payment in activePayments) {
    if (payment.discountAmount > salesAuditMoneyTolerance) {
      fields['payment.${payment.id}.discountAmount'] = payment.discountAmount;
    }
    if (payment.appliedDiscountPercent > salesAuditMoneyTolerance) {
      fields['payment.${payment.id}.appliedDiscountPercent'] =
          payment.appliedDiscountPercent;
    }
  }
  return fields;
}

double _explicitDiscountTotal({
  required double orderDiscount,
  required double paymentDiscountTotal,
}) {
  if (orderDiscount > salesAuditMoneyTolerance) return orderDiscount;
  if (paymentDiscountTotal > salesAuditMoneyTolerance) {
    return paymentDiscountTotal;
  }
  return 0;
}

double _paymentDiscountTotal(List<Payment> activePayments) {
  final discounts = activePayments
      .where((payment) => payment.discountAmount > salesAuditMoneyTolerance)
      .map((payment) => payment.discountAmount)
      .toList();
  if (discounts.isEmpty) return 0;
  return discounts.fold<double>(0, (sum, value) => sum + value);
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
    final applied = salesAuditPaymentAppliedAmount(payment);
    final received = payment.cashReceivedAmount;
    final change = payment.cashChangeAmount;
    if (received != null && change != null) {
      final net = received - change;
      final passed = !_outsideTolerance(net - applied);
      validations.add(
        SalesAuditValidation(
          label: 'Recibido - cambio = pago aplicado',
          passed: passed,
          detail: payment.id,
        ),
      );
      if (!passed) {
        issues++;
        fail(
          'cash_net',
          'Efectivo ${payment.id}: recibido - cambio no coincide con pago aplicado.',
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
    if (received != null && received + salesAuditMoneyTolerance < applied) {
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
        salesAuditPaymentAppliedAmount(a) - salesAuditPaymentAppliedAmount(b),
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
  required PosOrder order,
  required List<OrderItem> activeItems,
  required List<OrderItem> cancelledItems,
  required List<Payment> activePayments,
  required double itemsSubtotal,
  required double explicitDiscountTotal,
  required double expectedOrderTotal,
  required double paymentsAppliedTotal,
  required double receivedTotal,
  required double changeTotal,
  required double diffItemsOrder,
  required double diffPaymentsOrder,
  required double diffPaidTotal,
  required double diffPendingTotal,
  required Map<String, double> discountFields,
  required double paymentDiscountTotal,
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
    itemsSubtotal: itemsSubtotal,
    explicitDiscountTotal: explicitDiscountTotal,
    expectedOrderTotal: expectedOrderTotal,
    paymentsAppliedTotal: paymentsAppliedTotal,
    receivedTotal: receivedTotal,
    changeTotal: changeTotal,
    diffItemsOrder: diffItemsOrder,
    diffPaymentsOrder: diffPaymentsOrder,
    diffPaidTotal: diffPaidTotal,
    diffPendingTotal: diffPendingTotal,
    discountFields: discountFields,
    paymentDiscountTotal: paymentDiscountTotal,
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

bool _outsideTolerance(double value) => value.abs() > salesAuditMoneyTolerance;

String _normalize(String value) => value.trim().toLowerCase();
