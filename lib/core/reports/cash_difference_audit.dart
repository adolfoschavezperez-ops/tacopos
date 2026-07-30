import 'package:flutter/foundation.dart';

import '../../models/cash_session.dart';
import '../../models/order.dart';
import '../../models/payment.dart';

class CashDifferenceAuditReport {
  const CashDifferenceAuditReport({
    required this.session,
    required this.orders,
    required this.activePayments,
    required this.excludedPayments,
    required this.cancelledPayments,
    required this.inconsistencies,
    required this.cashCandidates,
    required this.cardCandidates,
    required this.tipCandidates,
    required this.changeIssues,
    required this.findings,
    required this.nonSaleMovements,
    required this.previousWithdrawals,
    required this.explainedCashAmount,
    required this.explainedCardAmount,
    this.previousSession,
  });

  final CashSession session;
  final List<CashAuditOrderRow> orders;
  final List<CashAuditPaymentRow> activePayments;
  final List<CashAuditPaymentRow> excludedPayments;
  final List<CashAuditPaymentRow> cancelledPayments;
  final List<CashAuditIssueRow> inconsistencies;
  final List<CashAuditIssueRow> cashCandidates;
  final List<CashAuditIssueRow> cardCandidates;
  final List<CashAuditIssueRow> tipCandidates;
  final List<CashAuditIssueRow> changeIssues;
  final List<CashAuditFindingRow> findings;
  final List<CashAuditMovementRow> nonSaleMovements;
  final List<CashAuditMovementRow> previousWithdrawals;
  final double explainedCashAmount;
  final double explainedCardAmount;
  final CashSession? previousSession;

  double get grossSales => orders
      .where((row) => row.countsForSales)
      .fold(0, (sum, row) => sum + row.grossSubtotal);
  double get discountTotal => orders
      .where((row) => row.countsForSales)
      .fold(0, (sum, row) => sum + row.discountAmount);
  double get netSales => orders
      .where((row) => row.countsForSales)
      .fold(0, (sum, row) => sum + row.netTotal);

  double get cashPos =>
      session.expectedCashAmount -
      session.openingCashAmount +
      session.approvedWithdrawalsTotal;
  double get countedCashLessOpening =>
      session.countedCashAmount - session.openingCashAmount;
  double get cashDifference => countedCashLessOpening - cashPos;
  double get cardPos => session.expectedCardChargedAmount;
  double get cardDifference => session.terminalReportedAmount - cardPos;
  double get totalDifference => cashDifference + cardDifference;
  double get observedMoney =>
      countedCashLessOpening + session.terminalReportedAmount;
  double get globalDifference => observedMoney - netSales;
  double get openingCashNeededToBalance =>
      session.countedCashAmount + session.terminalReportedAmount - netSales;
  double get openingCashGap =>
      openingCashNeededToBalance - session.openingCashAmount;
  double get activePaymentTotal =>
      activePayments.fold(0, (sum, row) => sum + row.amountForAudit);
  double get activeCashPayments => activePayments
      .where((row) => row.normalizedMethod == 'cash')
      .fold(0, (sum, row) => sum + row.amountForAudit);
  double get activeCardPayments => activePayments
      .where((row) => row.normalizedMethod == 'card')
      .fold(0, (sum, row) => sum + row.amountForAudit);
  double get unexplainedCashAmount =>
      (cashDifference.abs() - explainedCashAmount).clamp(0, double.infinity);
  double get unexplainedCardAmount =>
      (cardDifference.abs() - explainedCardAmount).clamp(0, double.infinity);
  double get orderLedgerDifference =>
      orders.fold(0, (sum, row) => sum + row.paymentVsNetDifference);
  double get cancelledCashTotal => cancelledPayments
      .where((row) => row.normalizedMethod == 'cash')
      .fold(0, (sum, row) => sum + row.amountForAudit);
  double get cancelledCardTotal => cancelledPayments
      .where((row) => row.normalizedMethod == 'card')
      .fold(0, (sum, row) => sum + row.amountForAudit);
  double get tipCashTotal => tipCandidates
      .where((row) => normalizeCashAuditPaymentMethod(row.method) == 'cash')
      .fold(0, (sum, row) => sum + row.amount);
  double get tipCardTotal => tipCandidates
      .where((row) => normalizeCashAuditPaymentMethod(row.method) == 'card')
      .fold(0, (sum, row) => sum + row.amount);
  double get tipTotal => tipCandidates.fold(0, (sum, row) => sum + row.amount);
  double get cashReceivedChangeDifferenceTotal {
    var total = 0.0;
    for (final row in activePayments) {
      if (row.normalizedMethod != 'cash') continue;
      final received = row.receivedAmount;
      final change = row.changeAmount;
      if (received == null || change == null) continue;
      if (received == 0 && change == 0) continue;
      total += (received - change) - row.amountForAudit;
    }
    return total;
  }

  double get confirmedGlobalExplanationTotal => findings
      .where((row) => row.reducesGlobalDifference == 'Si')
      .fold(0, (sum, row) => sum + row.amount.abs());
  double get unexplainedGlobalAmount =>
      (globalDifference.abs() - confirmedGlobalExplanationTotal).clamp(
        0,
        double.infinity,
      );
}

class CashAuditOrderRow {
  const CashAuditOrderRow({
    required this.orderId,
    required this.label,
    required this.orderType,
    required this.businessDate,
    required this.cashSessionId,
    required this.branchId,
    required this.createdAt,
    required this.status,
    required this.paymentStatus,
    required this.grossSubtotal,
    required this.discountAmount,
    required this.netTotal,
    required this.total,
    required this.paidTotal,
    required this.pendingTotal,
    required this.activePaymentTotal,
    required this.cancelledPaymentTotal,
    required this.calculatedPendingTotal,
    required this.observation,
    required this.inclusionReason,
  });

  final String orderId;
  final String label;
  final String orderType;
  final String businessDate;
  final String cashSessionId;
  final String branchId;
  final DateTime? createdAt;
  final String status;
  final String paymentStatus;
  final double grossSubtotal;
  final double discountAmount;
  final double netTotal;
  final double total;
  final double paidTotal;
  final double pendingTotal;
  final double activePaymentTotal;
  final double cancelledPaymentTotal;
  final double calculatedPendingTotal;
  final String observation;
  final String inclusionReason;

  bool get countsForSales =>
      !{'cancelled', 'voided'}.contains(status.trim().toLowerCase());
  double get paymentVsNetDifference => activePaymentTotal - netTotal;
}

class CashAuditPaymentRow {
  const CashAuditPaymentRow({
    required this.paymentId,
    required this.orderId,
    required this.label,
    required this.originalMethod,
    required this.normalizedMethod,
    required this.amount,
    required this.baseAmount,
    required this.chargedAmount,
    required this.appliedAmount,
    required this.receivedAmount,
    required this.changeAmount,
    required this.status,
    required this.cancelledAt,
    required this.createdAt,
    required this.businessDate,
    required this.orderBusinessDate,
    required this.cashSessionId,
    required this.orderCashSessionId,
    required this.employeeName,
    required this.included,
    required this.inclusionReason,
    required this.orderNetTotal,
    required this.orderStatus,
    required this.tipAmount,
  });

  final String paymentId;
  final String orderId;
  final String label;
  final String originalMethod;
  final String normalizedMethod;
  final double amount;
  final double baseAmount;
  final double chargedAmount;
  final double? appliedAmount;
  final double? receivedAmount;
  final double? changeAmount;
  final String status;
  final DateTime? cancelledAt;
  final DateTime? createdAt;
  final String businessDate;
  final String orderBusinessDate;
  final String cashSessionId;
  final String orderCashSessionId;
  final String employeeName;
  final bool included;
  final String inclusionReason;
  final double orderNetTotal;
  final String orderStatus;
  final double tipAmount;

  double get amountForAudit => appliedAmount ?? chargedAmount;
  bool get isActive => status == 'active' && cancelledAt == null;
}

class CashAuditIssueRow {
  const CashAuditIssueRow({
    required this.kind,
    required this.confidence,
    required this.amount,
    required this.paymentId,
    required this.orderId,
    required this.label,
    required this.method,
    required this.createdAt,
    required this.explanation,
  });

  final String kind;
  final String confidence;
  final double amount;
  final String paymentId;
  final String orderId;
  final String label;
  final String method;
  final DateTime? createdAt;
  final String explanation;
}

class CashAuditFindingRow {
  const CashAuditFindingRow({
    required this.finding,
    required this.type,
    required this.amount,
    required this.cashEffect,
    required this.cardEffect,
    required this.reducesGlobalDifference,
    required this.confidence,
    required this.evidence,
  });

  final String finding;
  final String type;
  final double amount;
  final double cashEffect;
  final double cardEffect;
  final String reducesGlobalDifference;
  final String confidence;
  final String evidence;
}

class CashAuditMovementRow {
  const CashAuditMovementRow({
    required this.type,
    required this.id,
    required this.amount,
    required this.method,
    required this.date,
    required this.user,
    required this.status,
    required this.includedInSession,
    required this.notes,
  });

  final String type;
  final String id;
  final double amount;
  final String method;
  final String date;
  final String user;
  final String status;
  final bool includedInSession;
  final String notes;
}

class CashAuditPaymentInput {
  const CashAuditPaymentInput({
    required this.payment,
    required this.orderId,
    this.tipAmount = 0,
  });

  final Payment payment;
  final String orderId;
  final double tipAmount;
}

CashDifferenceAuditReport buildCashDifferenceAuditReport({
  required CashSession session,
  required Iterable<PosOrder> orders,
  required Iterable<CashAuditPaymentInput> payments,
  CashSession? previousSession,
  Iterable<CashAuditMovementRow> nonSaleMovements = const [],
  Iterable<CashAuditMovementRow> previousWithdrawals = const [],
}) {
  final orderById = {for (final order in orders) order.id: order};
  final paymentRows = payments
      .map((input) => _paymentRow(session, input, orderById[input.orderId]))
      .toList();
  final rowsByOrder = <String, List<CashAuditPaymentRow>>{};
  for (final row in paymentRows) {
    rowsByOrder.putIfAbsent(row.orderId, () => []).add(row);
  }

  final orderRows =
      orders
          .where(
            (order) =>
                order.cashSessionId == session.id ||
                ((order.cashSessionId ?? '').trim().isEmpty &&
                    (order.businessDate ?? order.operationalDate ?? '') ==
                        session.businessDate &&
                    _branchMatches(order.branchId, session.branchId)),
          )
          .map((order) {
            final activePaymentTotal = (rowsByOrder[order.id] ?? const [])
                .where((payment) => payment.isActive && payment.included)
                .fold(0.0, (sum, payment) => sum + payment.amountForAudit);
            final cancelledPaymentTotal = (rowsByOrder[order.id] ?? const [])
                .where((payment) => !payment.isActive)
                .fold(0.0, (sum, payment) => sum + payment.amountForAudit);
            final netTotal = order.netTotal ?? order.total;
            final observation = _orderObservation(
              order: order,
              netTotal: netTotal,
              activePaymentTotal: activePaymentTotal,
            );
            return CashAuditOrderRow(
              orderId: order.id,
              label: _orderLabel(order),
              orderType: order.orderType,
              businessDate: order.businessDate ?? order.operationalDate ?? '',
              cashSessionId: order.cashSessionId ?? '',
              branchId: order.branchId,
              createdAt: order.createdAt,
              status: order.status,
              paymentStatus: order.paymentStatus,
              grossSubtotal: order.grossSubtotal ?? order.total,
              discountAmount: order.explicitDiscount,
              netTotal: netTotal,
              total: order.total,
              paidTotal: order.paidTotal,
              pendingTotal: order.pendingTotal,
              activePaymentTotal: activePaymentTotal,
              cancelledPaymentTotal: cancelledPaymentTotal,
              calculatedPendingTotal: netTotal - activePaymentTotal,
              observation: observation,
              inclusionReason: order.cashSessionId == session.id
                  ? 'cashSessionId del corte'
                  : 'fallback historico por businessDate y sucursal',
            );
          })
          .toList()
        ..sort((a, b) => _compareNullableDate(a.createdAt, b.createdAt));

  final activePayments = paymentRows.where((row) => row.included).toList()
    ..sort((a, b) => _compareNullableDate(a.createdAt, b.createdAt));
  final cancelledPayments =
      paymentRows
          .where((row) => row.status != 'active' || row.cancelledAt != null)
          .toList()
        ..sort((a, b) => _compareNullableDate(a.createdAt, b.createdAt));
  final excludedPayments = paymentRows.where((row) => !row.included).toList()
    ..sort((a, b) => _compareNullableDate(a.createdAt, b.createdAt));

  final inconsistencies = _businessInconsistencies(paymentRows);
  final cardCandidates = _cardCandidates(session, paymentRows);
  final cashCandidates = _cashCandidates(session, paymentRows);
  final tipCandidates = _tipCandidates(paymentRows);
  final changeIssues = _changeIssues(paymentRows);
  final findings = _findings(
    session: session,
    orders: orderRows,
    paymentRows: paymentRows,
    cardCandidates: cardCandidates,
    tipCandidates: tipCandidates,
    changeIssues: changeIssues,
    previousSession: previousSession,
    nonSaleMovements: nonSaleMovements.toList(),
    previousWithdrawals: previousWithdrawals.toList(),
  );
  final explainedCard = cardCandidates.isEmpty
      ? 0.0
      : cardCandidates.first.amount;
  final explainedCash = cashCandidates.isEmpty
      ? 0.0
      : cashCandidates.first.amount;

  final report = CashDifferenceAuditReport(
    session: session,
    orders: orderRows,
    activePayments: activePayments,
    excludedPayments: excludedPayments,
    cancelledPayments: cancelledPayments,
    inconsistencies: inconsistencies,
    cashCandidates: cashCandidates,
    cardCandidates: cardCandidates,
    tipCandidates: tipCandidates,
    changeIssues: changeIssues,
    findings: findings,
    nonSaleMovements: nonSaleMovements.toList(),
    previousWithdrawals: previousWithdrawals.toList(),
    explainedCashAmount: explainedCash,
    explainedCardAmount: explainedCard,
    previousSession: previousSession,
  );
  debugPrint(
    'CASH_AUDIT_SUMMARY\n'
    'cashSessionId=${session.id}\n'
    'businessDate=${session.businessDate}\n'
    'netSales=${report.netSales.toStringAsFixed(2)}\n'
    'cashPayments=${report.cashPos.toStringAsFixed(2)}\n'
    'cardPayments=${report.cardPos.toStringAsFixed(2)}\n'
    'countedCashLessOpening=${report.countedCashLessOpening.toStringAsFixed(2)}\n'
    'cashDifference=${report.cashDifference.toStringAsFixed(2)}\n'
    'terminalReported=${session.terminalReportedAmount.toStringAsFixed(2)}\n'
    'cardDifference=${report.cardDifference.toStringAsFixed(2)}\n'
    'observedMoney=${report.observedMoney.toStringAsFixed(2)}\n'
    'posNetSales=${report.netSales.toStringAsFixed(2)}\n'
    'globalDifference=${report.globalDifference.toStringAsFixed(2)}\n'
    'explainedCash=${report.explainedCashAmount.toStringAsFixed(2)}\n'
    'unexplainedCash=${report.unexplainedCashAmount.toStringAsFixed(2)}\n'
    'explainedCard=${report.explainedCardAmount.toStringAsFixed(2)}\n'
    'unexplainedCard=${report.unexplainedCardAmount.toStringAsFixed(2)}',
  );
  return report;
}

CashAuditPaymentRow _paymentRow(
  CashSession session,
  CashAuditPaymentInput input,
  PosOrder? order,
) {
  final payment = input.payment;
  final orderBusinessDate = order?.businessDate ?? order?.operationalDate ?? '';
  final paymentBusinessDate = payment.businessDate ?? '';
  final paymentCashSessionId = payment.cashSessionId ?? '';
  final method = payment.method.trim();
  final normalized = normalizeCashAuditPaymentMethod(method);
  final active = payment.status == 'active' && payment.cancelledAt == null;
  final included = active && paymentCashSessionId == session.id;
  return CashAuditPaymentRow(
    paymentId: payment.id,
    orderId: input.orderId,
    label: order == null ? input.orderId : _orderLabel(order),
    originalMethod: method,
    normalizedMethod: normalized,
    amount: payment.amount,
    baseAmount: payment.baseAmount,
    chargedAmount: payment.chargedAmount,
    appliedAmount: payment.appliedAmount,
    receivedAmount: payment.cashReceivedAmount,
    changeAmount: payment.cashChangeAmount,
    status: payment.status,
    cancelledAt: payment.cancelledAt,
    createdAt: payment.createdAt,
    businessDate: paymentBusinessDate,
    orderBusinessDate: orderBusinessDate,
    cashSessionId: paymentCashSessionId,
    orderCashSessionId: order?.cashSessionId ?? '',
    employeeName: payment.employeeName ?? '',
    included: included,
    inclusionReason: included
        ? 'payment.cashSessionId activo coincide con el corte'
        : _exclusionReason(session, payment, order),
    orderNetTotal: order?.netTotal ?? order?.total ?? 0,
    orderStatus: order?.status ?? '',
    tipAmount: input.tipAmount,
  );
}

String normalizeCashAuditPaymentMethod(String method) {
  final value = method
      .trim()
      .toLowerCase()
      .replaceAll(' ', '_')
      .replaceAll('-', '_');
  if (value == 'cash' || value == 'efectivo') return 'cash';
  if ({
    'card',
    'tarjeta',
    'credit_card',
    'debit_card',
    'terminal',
    'mercado_pago',
    'mp',
    'bancaria',
  }.contains(value)) {
    return 'card';
  }
  if (value == 'platform_paid' || value == 'plataforma') {
    return 'platform_paid';
  }
  if (value == 'employee_consumption' || value == 'consumo_empleado') {
    return 'employee_consumption';
  }
  return value;
}

String _exclusionReason(CashSession session, Payment payment, PosOrder? order) {
  if (payment.status != 'active' || payment.cancelledAt != null) {
    return 'payment cancelado o inactivo';
  }
  if ((payment.cashSessionId ?? '') != session.id) {
    return 'cashSessionId distinto o faltante';
  }
  if (!_branchMatches(payment.branchId, session.branchId) &&
      order != null &&
      !_branchMatches(order.branchId, session.branchId)) {
    return 'sucursal distinta';
  }
  return 'metodo no considerado por el corte';
}

List<CashAuditIssueRow> _cardCandidates(
  CashSession session,
  List<CashAuditPaymentRow> rows,
) {
  final target =
      session.terminalReportedAmount - session.expectedCardChargedAmount;
  final candidates =
      rows
          .where(
            (row) =>
                row.isActive &&
                row.cashSessionId == session.id &&
                row.normalizedMethod == 'cash',
          )
          .map((row) {
            final gap = (target.abs() - row.amountForAudit.abs()).abs();
            final confidence = gap <= 1
                ? 'Alto'
                : gap <= 10
                ? 'Medio'
                : 'Bajo';
            return CashAuditIssueRow(
              kind: 'Tarjeta',
              confidence: confidence,
              amount: row.amountForAudit,
              paymentId: row.paymentId,
              orderId: row.orderId,
              label: row.label,
              method: row.originalMethod,
              createdAt: row.createdAt,
              explanation:
                  'Pago activo registrado como efectivo; su importe esta cerca de la diferencia de terminal.',
            );
          })
          .toList()
        ..sort(
          (a, b) => (target.abs() - a.amount.abs()).abs().compareTo(
            (target.abs() - b.amount.abs()).abs(),
          ),
        );
  return candidates.take(12).toList();
}

List<CashAuditIssueRow> _cashCandidates(
  CashSession session,
  List<CashAuditPaymentRow> rows,
) {
  final target =
      (session.countedCashAmount - session.openingCashAmount) -
      (session.expectedCashAmount -
          session.openingCashAmount +
          session.approvedWithdrawalsTotal);
  final netZeroRows = rows
      .where(
        (row) =>
            row.isActive &&
            row.cashSessionId == session.id &&
            row.normalizedMethod == 'cash' &&
            row.orderNetTotal == 0 &&
            row.amountForAudit > 0,
      )
      .toList();
  final candidates = <CashAuditIssueRow>[];
  if (netZeroRows.isNotEmpty) {
    final amount = netZeroRows.fold(
      0.0,
      (sum, row) => sum + row.amountForAudit,
    );
    candidates.add(
      CashAuditIssueRow(
        kind: 'Efectivo',
        confidence: 'Medio',
        amount: amount,
        paymentId: netZeroRows.map((row) => row.paymentId).join(', '),
        orderId: netZeroRows.map((row) => row.orderId).join(', '),
        label: netZeroRows.map((row) => row.label).join(', '),
        method: 'cash',
        createdAt: netZeroRows.first.createdAt,
        explanation:
            'Pagos activos en efectivo ligados a ordenes con netTotal 0; revisar si fueron descuentos/cancelaciones con dinero fisico.',
      ),
    );
  }
  candidates.addAll(
    rows
        .where(
          (row) =>
              row.isActive &&
              row.cashSessionId == session.id &&
              row.normalizedMethod == 'cash',
        )
        .map((row) {
          final gap = (target.abs() - row.amountForAudit.abs()).abs();
          return CashAuditIssueRow(
            kind: 'Efectivo',
            confidence: gap <= 1
                ? 'Alto'
                : gap <= 10
                ? 'Medio'
                : 'Bajo',
            amount: row.amountForAudit,
            paymentId: row.paymentId,
            orderId: row.orderId,
            label: row.label,
            method: row.originalMethod,
            createdAt: row.createdAt,
            explanation: 'Pago en efectivo cercano a la diferencia de arqueo.',
          );
        }),
  );
  candidates.sort(
    (a, b) => (target.abs() - a.amount.abs()).abs().compareTo(
      (target.abs() - b.amount.abs()).abs(),
    ),
  );
  return candidates.take(12).toList();
}

List<CashAuditIssueRow> _businessInconsistencies(
  List<CashAuditPaymentRow> rows,
) {
  return rows
      .where(
        (row) =>
            (row.businessDate.isNotEmpty &&
                row.orderBusinessDate.isNotEmpty &&
                row.businessDate != row.orderBusinessDate) ||
            (row.cashSessionId.isNotEmpty &&
                row.orderCashSessionId.isNotEmpty &&
                row.cashSessionId != row.orderCashSessionId) ||
            row.businessDate.isEmpty ||
            row.cashSessionId.isEmpty,
      )
      .map(
        (row) => CashAuditIssueRow(
          kind: 'Inconsistencia',
          confidence: 'Medio',
          amount: row.amountForAudit,
          paymentId: row.paymentId,
          orderId: row.orderId,
          label: row.label,
          method: row.originalMethod,
          createdAt: row.createdAt,
          explanation:
              'Diferencia o ausencia de businessDate/cashSessionId entre pago y orden.',
        ),
      )
      .toList()
    ..sort((a, b) => _compareNullableDate(a.createdAt, b.createdAt));
}

List<CashAuditIssueRow> _tipCandidates(List<CashAuditPaymentRow> rows) {
  return rows
      .where((row) => row.tipAmount > 0)
      .map(
        (row) => CashAuditIssueRow(
          kind: 'Propina',
          confidence: 'Medio',
          amount: row.tipAmount,
          paymentId: row.paymentId,
          orderId: row.orderId,
          label: row.label,
          method: row.originalMethod,
          createdAt: row.createdAt,
          explanation: 'Campo de propina detectado en el pago.',
        ),
      )
      .toList();
}

List<CashAuditIssueRow> _changeIssues(List<CashAuditPaymentRow> rows) {
  return rows
      .where((row) {
        if (row.normalizedMethod != 'cash') return false;
        final received = row.receivedAmount;
        final change = row.changeAmount;
        if (received == null || change == null) return false;
        if (received == 0 && change == 0) return false;
        return ((received - change) - row.amountForAudit).abs() > 0.02 ||
            received < row.amountForAudit ||
            change < 0;
      })
      .map(
        (row) => CashAuditIssueRow(
          kind: 'Recibido/cambio',
          confidence: 'Alto',
          amount: row.amountForAudit,
          paymentId: row.paymentId,
          orderId: row.orderId,
          label: row.label,
          method: row.originalMethod,
          createdAt: row.createdAt,
          explanation:
              'receivedAmount - changeAmount no coincide con el importe aplicado.',
        ),
      )
      .toList();
}

String _orderObservation({
  required PosOrder order,
  required double netTotal,
  required double activePaymentTotal,
}) {
  final diff = activePaymentTotal - netTotal;
  final observations = <String>[];
  if (diff.abs() <= 0.02) {
    observations.add('Cuadra exactamente');
  } else if (diff > 0) {
    observations.add('Pagada de mas');
  } else {
    observations.add('Pagada de menos');
  }
  if (netTotal == 0 && activePaymentTotal > 0) {
    observations.add('Pago activo con netTotal cero');
  }
  if (netTotal > 0 && activePaymentTotal == 0) {
    observations.add('Total sin pago');
  }
  if ({'cancelled', 'voided'}.contains(order.status.trim().toLowerCase()) &&
      activePaymentTotal > 0) {
    observations.add('Orden cancelada con pago activo');
  }
  if (order.paymentStatus == 'paid' && diff.abs() > 0.02) {
    observations.add('Orden pagada con saldo');
  }
  if ((order.businessDate ?? order.operationalDate ?? '').trim().isEmpty ||
      (order.cashSessionId ?? '').trim().isEmpty) {
    observations.add('Metadata inconsistente');
  }
  return observations.join('; ');
}

List<CashAuditFindingRow> _findings({
  required CashSession session,
  required List<CashAuditOrderRow> orders,
  required List<CashAuditPaymentRow> paymentRows,
  required List<CashAuditIssueRow> cardCandidates,
  required List<CashAuditIssueRow> tipCandidates,
  required List<CashAuditIssueRow> changeIssues,
  required CashSession? previousSession,
  required List<CashAuditMovementRow> nonSaleMovements,
  required List<CashAuditMovementRow> previousWithdrawals,
}) {
  final findings = <CashAuditFindingRow>[];
  if (cardCandidates.isNotEmpty) {
    final candidate = cardCandidates.first;
    findings.add(
      CashAuditFindingRow(
        finding:
            'Pago ${candidate.label} registrado cash, probable cobro con terminal',
        type: 'Clasificacion',
        amount: candidate.amount,
        cashEffect: -candidate.amount,
        cardEffect: candidate.amount,
        reducesGlobalDifference: 'No',
        confidence: candidate.confidence,
        evidence:
            '${candidate.paymentId} / ${candidate.orderId}. Corrige columnas cash/card, no el sobrante global.',
      ),
    );
  }
  for (final row in orders.where(
    (row) =>
        row.grossSubtotal > 0 &&
        row.netTotal == 0 &&
        row.activePaymentTotal == 0,
  )) {
    findings.add(
      CashAuditFindingRow(
        finding: '${row.label} con venta bruta y descuento total',
        type: 'Registro',
        amount: row.grossSubtotal,
        cashEffect: 0,
        cardEffect: 0,
        reducesGlobalDifference: 'No confirmado',
        confidence: 'Media',
        evidence:
            '${row.orderId}: gross=${_money(row.grossSubtotal)}, descuento=${_money(row.discountAmount)}, netTotal=0, pagos activos=${_money(row.activePaymentTotal)}.',
      ),
    );
  }
  for (final movement in nonSaleMovements.where(
    (row) => row.amount > 0 && !row.type.toLowerCase().contains('retiro'),
  )) {
    findings.add(
      CashAuditFindingRow(
        finding: movement.type,
        type: 'Ingreso no venta',
        amount: movement.amount,
        cashEffect: movement.method == 'card' ? 0 : movement.amount,
        cardEffect: movement.method == 'card' ? movement.amount : 0,
        reducesGlobalDifference: movement.includedInSession
            ? 'Si'
            : 'Pendiente',
        confidence: movement.includedInSession ? 'Alta' : 'Media',
        evidence: '${movement.id} ${movement.date} ${movement.user}',
      ),
    );
  }
  final tipTotal = tipCandidates.fold(0.0, (sum, row) => sum + row.amount);
  if (tipTotal > 0) {
    findings.add(
      CashAuditFindingRow(
        finding: 'Propinas detectadas en pagos',
        type: 'Conteo/alcance',
        amount: tipTotal,
        cashEffect: 0,
        cardEffect: 0,
        reducesGlobalDifference: 'Pendiente',
        confidence: 'Media',
        evidence:
            '${tipCandidates.length} pagos con campos de propina; comparar contra caja/terminal.',
      ),
    );
  }
  if (changeIssues.isNotEmpty) {
    findings.add(
      CashAuditFindingRow(
        finding: 'Diferencias en recibido menos cambio',
        type: 'Conteo/alcance',
        amount: changeIssues.fold(0.0, (sum, row) => sum + row.amount),
        cashEffect: 0,
        cardEffect: 0,
        reducesGlobalDifference: 'Pendiente',
        confidence: 'Alta',
        evidence:
            '${changeIssues.length} pagos efectivos con cambio irregular.',
      ),
    );
  }
  if (previousSession != null) {
    final previousNet = previousSession.netDifference;
    findings.add(
      CashAuditFindingRow(
        finding: 'Corte anterior con diferencia neta',
        type: 'Conteo/alcance',
        amount: previousNet.abs(),
        cashEffect: previousSession.cashDifference,
        cardEffect: previousSession.cardDifference,
        reducesGlobalDifference: 'Pendiente',
        confidence: 'Media',
        evidence:
            '${previousSession.businessDate}: net=${_money(previousNet)}, retiros=${_money(previousWithdrawals.fold(0.0, (sum, row) => sum + row.amount))}. Requiere confirmar arrastre fisico.',
      ),
    );
  }
  final globalObserved =
      session.countedCashAmount -
      session.openingCashAmount +
      session.terminalReportedAmount;
  final globalNet = orders
      .where((row) => row.countsForSales)
      .fold(0.0, (sum, row) => sum + row.netTotal);
  final globalDifference = globalObserved - globalNet;
  findings.add(
    CashAuditFindingRow(
      finding: 'Diferencia global pendiente de explicar',
      type: 'Registro / conteo',
      amount: globalDifference.abs(),
      cashEffect: 0,
      cardEffect: 0,
      reducesGlobalDifference: 'Pendiente',
      confidence: 'Alta',
      evidence:
          'Dinero observado ${_money(globalObserved)} - venta neta POS ${_money(globalNet)}.',
    ),
  );
  return findings;
}

String _orderLabel(PosOrder order) {
  if (order.takeoutNumber != null) return '#${order.takeoutNumber}';
  final customer = order.customerName?.trim();
  if (customer != null && customer.isNotEmpty) return customer;
  return order.tableName;
}

bool _branchMatches(String? branchId, String selectedBranchId) {
  final clean = branchId?.trim();
  if (clean == null || clean.isEmpty) return true;
  return clean == selectedBranchId;
}

int _compareNullableDate(DateTime? a, DateTime? b) {
  final left = a ?? DateTime.fromMillisecondsSinceEpoch(0);
  final right = b ?? DateTime.fromMillisecondsSinceEpoch(0);
  return left.compareTo(right);
}

List<List<String>> cashDifferenceAuditCsvRows(
  CashDifferenceAuditReport report,
) {
  final rows = <List<String>>[];
  void section(String name) {
    rows
      ..add(const [])
      ..add([name]);
  }

  rows.addAll([
    ['Resumen'],
    ['cashSessionId', report.session.id],
    ['businessDate', report.session.businessDate],
    ['dinero observado', _money(report.observedMoney)],
    ['venta bruta POS', _money(report.grossSales)],
    ['descuentos POS', _money(report.discountTotal)],
    ['venta neta', _money(report.netSales)],
    ['diferencia global', _money(report.globalDifference)],
    ['fondo requerido para cuadrar', _money(report.openingCashNeededToBalance)],
    ['pagos activos', _money(report.activePaymentTotal)],
    ['efectivo POS', _money(report.cashPos)],
    ['conteo sin fondo', _money(report.countedCashLessOpening)],
    ['diferencia efectivo', _money(report.cashDifference)],
    ['tarjeta POS', _money(report.cardPos)],
    ['terminal reportada', _money(report.session.terminalReportedAmount)],
    ['diferencia tarjeta', _money(report.cardDifference)],
    ['diferencia total', _money(report.totalDifference)],
    ['monto explicado efectivo', _money(report.explainedCashAmount)],
    ['monto explicado tarjeta', _money(report.explainedCardAmount)],
    ['monto sin explicar efectivo', _money(report.unexplainedCashAmount)],
    ['monto sin explicar tarjeta', _money(report.unexplainedCardAmount)],
    ['monto sin explicar global', _money(report.unexplainedGlobalAmount)],
  ]);
  section('Hallazgos');
  rows.add([
    'hallazgo',
    'tipo',
    'importe',
    'afecta efectivo',
    'afecta tarjeta',
    'reduce diferencia global',
    'confianza',
    'evidencia',
  ]);
  for (final row in report.findings) {
    rows.add([
      row.finding,
      row.type,
      _money(row.amount),
      _money(row.cashEffect),
      _money(row.cardEffect),
      row.reducesGlobalDifference,
      row.confidence,
      row.evidence,
    ]);
  }
  section('Ordenes');
  rows.add([
    'orderId',
    'folio',
    'tipo',
    'businessDate',
    'cashSessionId',
    'status',
    'netTotal',
    'pagos activos',
    'pagos cancelados',
    'pendiente calculado',
    'diferencia',
    'observacion',
  ]);
  for (final row in report.orders) {
    rows.add([
      row.orderId,
      row.label,
      row.orderType,
      row.businessDate,
      row.cashSessionId,
      row.status,
      _money(row.netTotal),
      _money(row.activePaymentTotal),
      _money(row.cancelledPaymentTotal),
      _money(row.calculatedPendingTotal),
      _money(row.paymentVsNetDifference),
      row.observation,
    ]);
  }
  section('Pagos activos');
  _addPaymentRows(rows, report.activePayments);
  section('Pagos cancelados');
  _addPaymentRows(rows, report.cancelledPayments);
  section('Pagos excluidos');
  _addPaymentRows(rows, report.excludedPayments.take(200));
  section('Inconsistencias');
  _addIssueRows(rows, report.inconsistencies);
  section('Candidatos efectivo');
  _addIssueRows(rows, report.cashCandidates);
  section('Candidatos tarjeta');
  _addIssueRows(rows, report.cardCandidates);
  section('Ingresos no venta');
  _addMovementRows(rows, report.nonSaleMovements);
  section('Retiros corte anterior');
  _addMovementRows(rows, report.previousWithdrawals);
  return rows;
}

void _addMovementRows(
  List<List<String>> rows,
  Iterable<CashAuditMovementRow> movements,
) {
  rows.add([
    'tipo',
    'id',
    'importe',
    'metodo',
    'fecha',
    'usuario',
    'status',
    'incluido en corte',
    'notas',
  ]);
  for (final row in movements) {
    rows.add([
      row.type,
      row.id,
      _money(row.amount),
      row.method,
      row.date,
      row.user,
      row.status,
      row.includedInSession ? 'si' : 'no',
      row.notes,
    ]);
  }
}

void _addPaymentRows(
  List<List<String>> rowsSink,
  Iterable<CashAuditPaymentRow> rows,
) {
  rowsSink.add([
    'paymentId',
    'orderId',
    'folio',
    'metodo',
    'normalizado',
    'importe',
    'status',
    'createdAt',
    'businessDate',
    'cashSessionId',
    'incluido',
    'motivo',
  ]);
  for (final row in rows) {
    rowsSink.add([
      row.paymentId,
      row.orderId,
      row.label,
      row.originalMethod,
      row.normalizedMethod,
      _money(row.amountForAudit),
      row.status,
      row.createdAt?.toIso8601String() ?? '',
      row.businessDate,
      row.cashSessionId,
      row.included ? 'si' : 'no',
      row.inclusionReason,
    ]);
  }
}

void _addIssueRows(
  List<List<String>> rows,
  Iterable<CashAuditIssueRow> issues,
) {
  rows.add([
    'tipo',
    'confianza',
    'importe',
    'paymentId',
    'orderId',
    'folio',
    'metodo',
    'createdAt',
    'explicacion',
  ]);
  for (final row in issues) {
    rows.add([
      row.kind,
      row.confidence,
      _money(row.amount),
      row.paymentId,
      row.orderId,
      row.label,
      row.method,
      row.createdAt?.toIso8601String() ?? '',
      row.explanation,
    ]);
  }
}

String _money(double value) => value.toStringAsFixed(2);
