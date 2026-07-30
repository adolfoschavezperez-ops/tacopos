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
    required this.explainedCashAmount,
    required this.explainedCardAmount,
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
  final double explainedCashAmount;
  final double explainedCardAmount;

  double get netSales =>
      orders.where((row) => row.countsForSales).fold(0, (sum, row) {
        final net = row.netTotal > 0 ? row.netTotal : row.total;
        return sum + net;
      });

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
  final String inclusionReason;

  bool get countsForSales =>
      !{'cancelled', 'voided'}.contains(status.trim().toLowerCase());
  double get paymentVsNetDifference =>
      activePaymentTotal - (netTotal > 0 ? netTotal : total);
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
                .where((payment) => payment.isActive)
                .fold(0.0, (sum, payment) => sum + payment.amountForAudit);
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
              netTotal: order.netTotal ?? order.total,
              total: order.total,
              paidTotal: order.paidTotal,
              pendingTotal: order.pendingTotal,
              activePaymentTotal: activePaymentTotal,
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
    explainedCashAmount: explainedCash,
    explainedCardAmount: explainedCard,
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
    ['venta neta', _money(report.netSales)],
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
  ]);
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
    'diferencia',
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
      _money(row.paymentVsNetDifference),
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
  return rows;
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
