import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../models/cash_session.dart';
import '../../models/cash_withdrawal_request.dart';
import '../../models/employee.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../models/purchase_models.dart';
import 'canonical_sales_summary.dart';

const double financeMoneyTolerance = 0.02;
const double financeRoundingTolerance = 0.01;

class FinanceBreakdownEntry<T> {
  const FinanceBreakdownEntry({
    required this.label,
    required this.amount,
    required this.source,
  });

  final String label;
  final double amount;
  final T source;
}

class FinanceReconciledBreakdown<T> {
  const FinanceReconciledBreakdown({
    required this.entries,
    required this.visibleEntries,
    required this.hiddenEntries,
    required this.expectedTotal,
    required this.sourceTotal,
    required this.visibleTotal,
    required this.otherTotal,
    required this.reconciledTotal,
    required this.difference,
    required this.isValid,
  });

  final List<FinanceBreakdownEntry<T>> entries;
  final List<FinanceBreakdownEntry<T>> visibleEntries;
  final List<FinanceBreakdownEntry<T>> hiddenEntries;
  final double expectedTotal;
  final double sourceTotal;
  final double visibleTotal;
  final double otherTotal;
  final double reconciledTotal;
  final double difference;
  final bool isValid;

  bool get hasOther => hiddenEntries.isNotEmpty && otherTotal > 0.005;
}

List<FinanceBreakdownEntry<CashWithdrawalRequest>>
financeExpenseBreakdownEntries(FinanceDashboardBundle bundle) {
  final entries = bundle.approvedExpenses
      .map(
        (row) => FinanceBreakdownEntry(
          label: row.reason,
          amount: row.amount,
          source: row,
        ),
      )
      .where((entry) => entry.amount.abs() > 0.005)
      .toList();
  entries.sort((a, b) {
    final byAmount = b.amount.compareTo(a.amount);
    if (byAmount != 0) return byAmount;
    final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
    if (byLabel != 0) return byLabel;
    return a.source.id.compareTo(b.source.id);
  });
  return List.unmodifiable(entries);
}

List<FinanceBreakdownEntry<FinanceSupplierRow>>
financeSupplierInvoiceBreakdownEntries(FinanceDashboardBundle bundle) {
  final entries = bundle.supplierRows
      .where((row) => row.invoiced > 0.005)
      .map(
        (row) => FinanceBreakdownEntry(
          label: row.supplierName,
          amount: row.invoiced,
          source: row,
        ),
      )
      .toList();
  entries.sort((a, b) {
    final byAmount = b.amount.compareTo(a.amount);
    if (byAmount != 0) return byAmount;
    final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
    if (byLabel != 0) return byLabel;
    return a.source.supplierId.compareTo(b.source.supplierId);
  });
  return List.unmodifiable(entries);
}

bool financePeriodIsFullWeek(FinanceDashboardKey key) {
  final start = DateTime.tryParse(key.startBusinessDate);
  final end = DateTime.tryParse(key.endBusinessDate);
  if (start == null || end == null) return false;
  return start.weekday == DateTime.monday &&
      end.weekday == DateTime.sunday &&
      end.difference(start).inDays == 6;
}

String financePeriodSummaryTitle(FinanceDashboardKey key) {
  return financePeriodIsFullWeek(key)
      ? 'Resumen semanal'
      : 'Resumen financiero';
}

String financeSummaryImageFileName({
  required FinanceDashboardBundle bundle,
  required String branchName,
}) {
  final branch = _summaryFileToken(
    branchName.isEmpty ? bundle.key.branchId : branchName,
  );
  final start = _summaryFileDate(bundle.key.startBusinessDate);
  final end = _summaryFileDate(bundle.key.endBusinessDate);
  return 'Resumen-Financiero-$branch-$start-al-$end.png';
}

String financeWhatsappSummaryText({
  required FinanceDashboardBundle bundle,
  required String restaurantName,
  required String branchName,
  DateTime? generatedAt,
}) {
  final title = financePeriodSummaryTitle(bundle.key);
  final period =
      '${_summaryDisplayDate(bundle.key.startBusinessDate)} - ${_summaryDisplayDate(bundle.key.endBusinessDate)}';
  final expenses = financeExpenseBreakdownEntries(bundle);
  final suppliers = financeSupplierInvoiceBreakdownEntries(bundle);
  final generated = generatedAt == null
      ? null
      : DateFormat('dd/MM/yyyy HH:mm').format(generatedAt);
  final lines = <String>[
    restaurantName.toUpperCase(),
    branchName.toUpperCase(),
    title,
    period,
    if (generated != null) 'Generado: $generated',
    '',
    'VENTAS',
    'Venta bruta: ${_summaryMoney(bundle.grossSales)}',
    'Descuentos: ${_summaryMoney(bundle.discounts)}',
    'Venta neta: ${_summaryMoney(bundle.netSales)}',
    'Ordenes: ${bundle.salesOrders.length}',
    'Ticket promedio: ${_summaryMoney(_safeAverage(bundle.netSales, bundle.salesOrders.length))}',
    '',
    'INGRESOS REALES',
    'Efectivo: ${_summaryMoney(bundle.cashCollected)}',
    'Tarjeta neta: ${_summaryMoney(bundle.cardCollected)}',
    if ((bundle.platformCollected + bundle.otherCollected).abs() > 0.005)
      'Otros / plataforma: ${_summaryMoney(bundle.platformCollected + bundle.otherCollected)}',
    'Ingreso real: ${_summaryMoney(bundle.realCollected)}',
    'Tarjeta bruta: ${_summaryMoney(bundle.cardGrossCollected)}',
    'Comisiones de tarjeta: ${_summaryMoney(bundle.cardFees)}',
    '',
    'AJUSTES DE CAJA',
    'Monetario esperado bruto: ${_summaryMoney(bundle.expectedMonetaryGrossIncome)}',
    'Comision tarjeta: ${_summaryMoney(bundle.cardFees)}',
    'Monetario esperado neto: ${_summaryMoney(bundle.expectedMonetaryIncome)}',
    'Faltantes: ${_summaryMoney(bundle.cashShortages)}',
    'Sobrantes: ${_summaryMoney(bundle.cashOverages)}',
    '',
    'GASTOS',
    for (final entry in expenses)
      '${entry.label}: ${_summaryMoney(entry.amount)}',
    'Total gastos: ${_summaryMoney(bundle.paidExpenses)}',
    '',
    'FACTURAS DE PROVEEDORES',
    for (final entry in suppliers)
      '${entry.label}: ${_summaryMoney(entry.amount)}',
    'Total facturado: ${_summaryMoney(bundle.supplierInvoicesTotal)}',
    '',
    'PAGOS A PROVEEDORES',
    for (final entry in _supplierPaymentSummaryEntries(bundle))
      '${entry.key}: ${_summaryMoney(entry.value)}',
    'Total pagado: ${_summaryMoney(bundle.supplierPaidTotal)}',
    '',
    'FACTURAS PENDIENTES',
    _summaryMoney(bundle.pendingSupplierInvoices),
    '',
    'RESUMEN FINAL',
    'Ingreso real: ${_summaryMoney(bundle.realCollected)}',
    'Gastos: -${_summaryMoney(bundle.paidExpenses)}',
    'Pagado a proveedores: -${_summaryMoney(bundle.supplierPaidTotal)}',
    'Facturas pendientes: ${_summaryMoney(bundle.pendingSupplierInvoices)}',
    'Resultado: ${_summaryMoney(bundle.finalResult)}',
  ];
  return lines.join('\n');
}

FinanceReconciledBreakdown<T> buildReconciledBreakdown<T>({
  required List<FinanceBreakdownEntry<T>> entries,
  required double expectedTotal,
  int visibleLimit = 4,
  bool sortDescending = true,
}) {
  assert(visibleLimit >= 0);
  final ordered = entries
      .where((entry) => entry.amount.abs() > 0.005)
      .toList(growable: false);
  if (sortDescending) {
    ordered.sort((a, b) => b.amount.compareTo(a.amount));
  }
  final safeLimit = visibleLimit.clamp(0, ordered.length);
  final visible = ordered.take(safeLimit).toList();
  final hidden = ordered.skip(safeLimit).toList(growable: false);
  final normalizedExpected = _money(expectedTotal);
  final sourceTotal = _money(
    ordered.fold<double>(0, (sum, entry) => sum + entry.amount),
  );
  final difference = _money(normalizedExpected - sourceTotal);
  var isValid = difference.abs() <= financeMoneyTolerance;
  if (difference < -financeRoundingTolerance) isValid = false;
  final canAdjustRounding = difference.abs() <= financeRoundingTolerance;
  if (hidden.isEmpty &&
      visible.isNotEmpty &&
      difference.abs() <= financeRoundingTolerance) {
    final last = visible.last;
    visible[visible.length - 1] = FinanceBreakdownEntry<T>(
      label: last.label,
      amount: _money(last.amount + difference),
      source: last.source,
    );
  }
  final visibleTotal = _money(
    visible.fold<double>(0, (sum, entry) => sum + entry.amount),
  );
  final hiddenTotal = _money(
    hidden.fold<double>(0, (sum, entry) => sum + entry.amount),
  );
  final expectedOther = _money(normalizedExpected - visibleTotal);
  final otherTotal = hidden.isEmpty
      ? 0.0
      : canAdjustRounding
      ? expectedOther
      : hiddenTotal;
  final reconciledTotal = _money(visibleTotal + otherTotal);

  return FinanceReconciledBreakdown<T>(
    entries: List.unmodifiable(ordered),
    visibleEntries: List.unmodifiable(visible),
    hiddenEntries: List.unmodifiable(hidden),
    expectedTotal: normalizedExpected,
    sourceTotal: sourceTotal,
    visibleTotal: visibleTotal,
    otherTotal: otherTotal,
    reconciledTotal: reconciledTotal,
    difference: difference,
    isValid:
        isValid &&
        otherTotal >= -financeRoundingTolerance &&
        (normalizedExpected - reconciledTotal).abs() <= financeMoneyTolerance,
  );
}

List<MapEntry<String, double>> _supplierPaymentSummaryEntries(
  FinanceDashboardBundle bundle,
) {
  final entries = bundle.supplierPaymentsByMethod.entries
      .map(
        (entry) =>
            MapEntry(financeSupplierPaymentMethodLabel(entry.key), entry.value),
      )
      .where((entry) => entry.value.abs() > 0.005)
      .toList();
  entries.sort((a, b) {
    final byAmount = b.value.compareTo(a.value);
    if (byAmount != 0) return byAmount;
    return a.key.toLowerCase().compareTo(b.key.toLowerCase());
  });
  return List.unmodifiable(entries);
}

String financePaymentMethodLabel(String method) {
  return switch (method.trim().toLowerCase()) {
    'cash' => 'Efectivo',
    'card' => 'Tarjeta',
    'platform_paid' => 'Pagado en plataforma',
    'employee_consumption' => 'Consumo empleado',
    'transfer' => 'Transferencia',
    _ => method.trim().isEmpty ? 'Otro' : method,
  };
}

String financeSupplierPaymentMethodLabel(String method) {
  return switch (method.trim().toLowerCase()) {
    'cash' => 'Efectivo',
    'transfer' => 'Transferencia',
    'partner_contribution' => 'Aportacion de socios',
    'card' => 'Tarjeta',
    _ => method.trim().isEmpty ? 'Otro' : method,
  };
}

double _safeAverage(double total, int count) {
  if (count <= 0) return 0;
  return _money(total / count);
}

String _summaryDisplayDate(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  return DateFormat('dd/MM/yyyy').format(date);
}

String _summaryFileDate(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value.replaceAll(RegExp(r'[^0-9A-Za-z]+'), '-');
  return DateFormat('dd-MM-yyyy').format(date);
}

String _summaryFileToken(String value) {
  final token = value
      .trim()
      .replaceAll(RegExp(r'[^0-9A-Za-z]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return token.isEmpty ? 'Sucursal' : token;
}

String _summaryMoney(double value) {
  final formatter = NumberFormat.currency(locale: 'es_MX', symbol: r'$');
  return formatter.format(_money(value));
}

void logFinanceDashboardReconciliation<T>(
  String section,
  FinanceReconciledBreakdown<T> breakdown,
) {
  if (!kDebugMode) return;
  debugPrint(
    'FINANCE_DASHBOARD_RECONCILIATION '
    'section=$section '
    'kpiTotal=${breakdown.expectedTotal.toStringAsFixed(2)} '
    'visibleTotal=${breakdown.visibleTotal.toStringAsFixed(2)} '
    'otherTotal=${breakdown.otherTotal.toStringAsFixed(2)} '
    'reconciledTotal=${breakdown.reconciledTotal.toStringAsFixed(2)} '
    'difference=${breakdown.difference.toStringAsFixed(2)} '
    'valid=${breakdown.isValid}',
  );
  if (!breakdown.isValid) {
    debugPrint(
      'FINANCE_DASHBOARD_RECONCILIATION WARNING '
      'section=$section difference=${breakdown.difference.toStringAsFixed(2)}',
    );
  }
}

bool canViewFinanceDashboard(Employee? employee) {
  return employee?.hasAdminAccess == true ||
      employee?.canViewAdmin == true ||
      employee?.canViewPurchases == true ||
      employee?.canPaySuppliers == true ||
      employee?.canViewAccountsPayable == true ||
      employee?.canViewPurchaseReports == true;
}

class FinanceDashboardKey {
  const FinanceDashboardKey({
    required this.restaurantId,
    required this.branchId,
    required this.startBusinessDate,
    required this.endBusinessDate,
  });

  final String restaurantId;
  final String branchId;
  final String startBusinessDate;
  final String endBusinessDate;

  String get value =>
      [restaurantId, branchId, startBusinessDate, endBusinessDate].join('|');

  @override
  bool operator ==(Object other) {
    return other is FinanceDashboardKey &&
        restaurantId == other.restaurantId &&
        branchId == other.branchId &&
        startBusinessDate == other.startBusinessDate &&
        endBusinessDate == other.endBusinessDate;
  }

  @override
  int get hashCode =>
      Object.hash(restaurantId, branchId, startBusinessDate, endBusinessDate);
}

class FinanceDashboardInput {
  const FinanceDashboardInput({
    required this.key,
    required this.salesSummary,
    required this.paymentsByOrder,
    required this.cashSessions,
    required this.withdrawals,
    required this.purchases,
    required this.supplierPayments,
    required this.suppliers,
  });

  final FinanceDashboardKey key;
  final CanonicalSalesSummary salesSummary;
  final Map<String, List<Payment>> paymentsByOrder;
  final List<CashSession> cashSessions;
  final List<CashWithdrawalRequest> withdrawals;
  final List<SupplierPurchase> purchases;
  final List<SupplierPayment> supplierPayments;
  final List<Supplier> suppliers;
}

class FinanceDashboardBundle {
  const FinanceDashboardBundle({
    required this.key,
    required this.salesSummary,
    required this.salesOrders,
    required this.customerPayments,
    required this.cashSessions,
    required this.cashCutSummaries,
    required this.expenses,
    required this.purchases,
    required this.supplierPayments,
    required this.suppliers,
    required this.salesByDay,
    required this.collectionsByDay,
    required this.supplierRows,
    required this.firestoreQueries,
    required this.loadedAt,
    this.fromCache = false,
    this.loadMilliseconds = 0,
  });

  final FinanceDashboardKey key;
  final CanonicalSalesSummary salesSummary;
  final List<CanonicalOrderSalesRow> salesOrders;
  final List<FinanceCustomerPayment> customerPayments;
  final List<CashSession> cashSessions;
  final List<FinanceCashCutSummary> cashCutSummaries;
  final List<CashWithdrawalRequest> expenses;
  final List<SupplierPurchase> purchases;
  final List<SupplierPayment> supplierPayments;
  final List<Supplier> suppliers;
  final List<FinanceSalesDayRow> salesByDay;
  final List<FinanceCollectionsDayRow> collectionsByDay;
  final List<FinanceSupplierRow> supplierRows;
  final int firestoreQueries;
  final DateTime loadedAt;
  final bool fromCache;
  final int loadMilliseconds;

  double get grossSales =>
      _money(salesOrders.fold<double>(0, (sum, row) => sum + row.grossSales));
  double get salesWithoutDiscount => _money(
    salesOrders
        .where((row) => !row.hasExplicitDiscount)
        .fold<double>(0, (sum, row) => sum + row.netSales),
  );
  double get salesWithDiscount => _money(
    salesOrders
        .where((row) => row.hasExplicitDiscount)
        .fold<double>(0, (sum, row) => sum + row.netSales),
  );
  double get discounts => _money(
    salesOrders.fold<double>(0, (sum, row) => sum + row.discountTotal),
  );
  double get netSales => _money(grossSales - discounts);

  double get expectedMonetaryIncome => _money(
    cashCutSummaries.fold<double>(
      0,
      (sum, row) => sum + row.expectedMonetaryIncome,
    ),
  );
  double get expectedMonetaryGrossIncome => _money(
    cashCutSummaries.fold<double>(
      0,
      (sum, row) => sum + row.expectedMonetaryGrossIncome,
    ),
  );
  double get cashCollected => _money(
    cashCutSummaries.fold<double>(0, (sum, row) => sum + row.cashReceived),
  );
  double get cardCollected => _money(
    cashCutSummaries.fold<double>(0, (sum, row) => sum + row.cardReceived),
  );
  double get cardGrossCollected => _money(
    cashCutSummaries.fold<double>(0, (sum, row) => sum + row.cardGrossReceived),
  );
  double get platformCollected => _money(
    cashCutSummaries.fold<double>(0, (sum, row) => sum + row.platformReceived),
  );
  double get otherCollected => _money(
    cashCutSummaries.fold<double>(0, (sum, row) => sum + row.otherReceived),
  );
  double get realCollected => _money(
    cashCollected + cardCollected + platformCollected + otherCollected,
  );
  double get employeeConsumption => _paymentTotal('employee_consumption');
  double get cardFees => _money(
    cashCutSummaries.fold<double>(0, (sum, row) => sum + row.cardFeeAbsorbed),
  );
  double get cashShortages => _money(
    cashCutSummaries.fold<double>(0, (sum, row) => sum + row.shortage),
  );
  double get cashOverages =>
      _money(cashCutSummaries.fold<double>(0, (sum, row) => sum + row.overage));
  List<FinanceCashCutDailyDetail> get cashCutDailyDetails =>
      buildFinanceCashCutDailyDetails(cashCutSummaries);
  FinanceCashCutDailyDetail get cashCutPeriodTotal =>
      buildFinanceCashCutPeriodTotal(cashCutDailyDetails);

  List<CashWithdrawalRequest> get approvedExpenses => expenses
      .where((row) => financeExpenseStatus(row) == FinanceExpenseStatus.paid)
      .toList(growable: false);
  List<CashWithdrawalRequest> get pendingExpenses => expenses
      .where((row) => financeExpenseStatus(row) == FinanceExpenseStatus.pending)
      .toList(growable: false);
  double get paidExpenses =>
      _money(approvedExpenses.fold<double>(0, (sum, row) => sum + row.amount));
  double get pendingExpensesTotal =>
      _money(pendingExpenses.fold<double>(0, (sum, row) => sum + row.amount));

  double get supplierInvoicesTotal =>
      _money(purchases.fold<double>(0, (sum, row) => sum + row.total));
  double get supplierPaidTotal =>
      _money(supplierPayments.fold<double>(0, (sum, row) => sum + row.amount));
  double get pendingSupplierInvoices => _money(
    purchases.fold<double>(0, (sum, row) => sum + financePurchaseBalance(row)),
  );

  double get generalResult =>
      _money(realCollected - paidExpenses - supplierInvoicesTotal);
  double get collectionsResult =>
      _money(realCollected - paidExpenses - supplierPaidTotal);
  double get finalResult => _money(
    realCollected - paidExpenses - supplierPaidTotal - pendingSupplierInvoices,
  );

  Map<String, double> get customerPaymentsByMethod {
    final result = <String, double>{};
    for (final row in customerPayments) {
      final method = row.payment.method.trim().toLowerCase();
      if (method == 'employee_consumption') continue;
      result.update(
        method,
        (value) => _money(value + row.amount),
        ifAbsent: () => row.amount,
      );
    }
    return result;
  }

  Map<String, double> get supplierPaymentsByMethod {
    final result = <String, double>{};
    for (final row in supplierPayments) {
      final method = row.method.trim().toLowerCase();
      result.update(
        method,
        (value) => _money(value + row.amount),
        ifAbsent: () => row.amount,
      );
    }
    return result;
  }

  FinanceDashboardBundle withLoadMetadata({
    required bool fromCache,
    required int loadMilliseconds,
  }) {
    return FinanceDashboardBundle(
      key: key,
      salesSummary: salesSummary,
      salesOrders: salesOrders,
      customerPayments: customerPayments,
      cashSessions: cashSessions,
      cashCutSummaries: cashCutSummaries,
      expenses: expenses,
      purchases: purchases,
      supplierPayments: supplierPayments,
      suppliers: suppliers,
      salesByDay: salesByDay,
      collectionsByDay: collectionsByDay,
      supplierRows: supplierRows,
      firestoreQueries: firestoreQueries,
      loadedAt: loadedAt,
      fromCache: fromCache,
      loadMilliseconds: loadMilliseconds,
    );
  }

  double _paymentTotal(String method) => _money(
    customerPayments
        .where((row) => row.payment.method.trim().toLowerCase() == method)
        .fold<double>(0, (sum, row) => sum + row.amount),
  );
}

class FinanceCashCutSummary {
  const FinanceCashCutSummary({
    required this.session,
    required this.businessDate,
    required this.expectedCashIncome,
    required this.expectedCardIncome,
    required this.expectedPlatformIncome,
    required this.expectedOtherIncome,
    required this.cashReceived,
    required this.cardReceived,
    required this.platformReceived,
    required this.otherReceived,
    required this.cardFeeAbsorbed,
    required this.openingFloat,
    required this.approvedWithdrawals,
  });

  final CashSession session;
  final String businessDate;
  final double expectedCashIncome;
  final double expectedCardIncome;
  final double expectedPlatformIncome;
  final double expectedOtherIncome;
  final double cashReceived;
  final double cardReceived;
  final double platformReceived;
  final double otherReceived;
  final double cardFeeAbsorbed;
  final double openingFloat;
  final double approvedWithdrawals;

  double get expectedMonetaryIncome => _money(
    expectedCashIncome +
        expectedCardIncome +
        expectedPlatformIncome +
        expectedOtherIncome,
  );
  double get expectedCardGrossIncome =>
      _money(session.expectedCardChargedAmount);
  double get expectedCardNetIncome => expectedCardIncome;
  double get expectedMonetaryGrossIncome => _money(
    expectedCashIncome +
        expectedCardGrossIncome +
        expectedPlatformIncome +
        expectedOtherIncome,
  );
  double get cardGrossReceived => _money(session.terminalReportedAmount);
  double get cardNetReceived => cardReceived;
  double get actualReceived =>
      _money(cashReceived + cardReceived + platformReceived + otherReceived);
  double get difference => _money(actualReceived - expectedMonetaryIncome);
  double get shortage => difference < 0 ? _money(difference.abs()) : 0;
  double get overage => difference > 0 ? difference : 0;
  double get cashCountedLessOpening =>
      _money(session.countedCashAmount - openingFloat);
  double get cashOperationalBeforeExpenses => cashReceived;
}

bool financeCashSessionCountsAsClosed(CashSession session) {
  final status = _token(session.status);
  if (_cancelledToken(status)) return false;
  return status == 'closed' || session.closedAt != null;
}

FinanceCashCutSummary buildFinanceCashCutSummary(CashSession session) {
  final expectedCashIncome = _money(
    session.expectedCashAmount -
        session.openingCashAmount +
        session.approvedWithdrawalsTotal,
  );
  final cashReceived = _money(
    session.countedCashAmount -
        session.openingCashAmount +
        session.approvedWithdrawalsTotal,
  );
  final cardFeeAbsorbed = _money(session.expectedCardFeeAbsorbedAmount);
  final expectedCardNet = financeNetCardReceived(
    cardGross: session.expectedCardChargedAmount,
    cardFee: cardFeeAbsorbed,
  );
  final cardNetReceived = financeNetCardReceived(
    cardGross: session.terminalReportedAmount,
    cardFee: cardFeeAbsorbed,
  );
  return FinanceCashCutSummary(
    session: session,
    businessDate: session.businessDate,
    expectedCashIncome: expectedCashIncome,
    expectedCardIncome: expectedCardNet,
    expectedPlatformIncome: _money(session.expectedPlatformAmount),
    expectedOtherIncome: 0,
    cashReceived: cashReceived,
    cardReceived: cardNetReceived,
    platformReceived: _money(session.expectedPlatformAmount),
    otherReceived: 0,
    cardFeeAbsorbed: cardFeeAbsorbed,
    openingFloat: _money(session.openingCashAmount),
    approvedWithdrawals: _money(session.approvedWithdrawalsTotal),
  );
}

double financeNetCardReceived({
  required double cardGross,
  required double cardFee,
}) {
  return _money(cardGross - cardFee);
}

class FinanceCashCutDailyDetail {
  const FinanceCashCutDailyDetail({
    required this.businessDate,
    required this.cashCounted,
    required this.cashExpensesPaid,
    required this.cashOperationalBeforeExpenses,
    required this.cardReceived,
    required this.cardGrossReceived,
    required this.cardFees,
    required this.otherReceived,
    required this.actualIncome,
    required this.expectedMonetaryIncome,
    required this.shortage,
    required this.overage,
    required this.cutCount,
    required this.closedByNames,
    required this.cuts,
  });

  final String businessDate;
  final double cashCounted;
  final double cashExpensesPaid;
  final double cashOperationalBeforeExpenses;
  final double cardReceived;
  final double cardGrossReceived;
  final double cardFees;
  final double otherReceived;
  final double actualIncome;
  final double expectedMonetaryIncome;
  final double shortage;
  final double overage;
  final int cutCount;
  final List<String> closedByNames;
  final List<FinanceCashCutSummary> cuts;
}

List<FinanceCashCutDailyDetail> buildFinanceCashCutDailyDetails(
  Iterable<FinanceCashCutSummary> summaries,
) {
  final groups = <String, List<FinanceCashCutSummary>>{};
  for (final summary in summaries) {
    groups.putIfAbsent(summary.businessDate, () => []).add(summary);
  }
  final result = groups.entries.map((entry) {
    final rows = entry.value;
    rows.sort((a, b) {
      final aDate = a.session.closedAt ?? DateTime(1970);
      final bDate = b.session.closedAt ?? DateTime(1970);
      return aDate.compareTo(bDate);
    });
    final names = <String>{};
    for (final row in rows) {
      final closedBy = row.session.closedByEmployeeName?.trim();
      if (closedBy != null && closedBy.isNotEmpty) {
        names.add(closedBy);
        continue;
      }
      final openedBy = row.session.openedByEmployeeName.trim();
      if (openedBy.isNotEmpty) names.add(openedBy);
    }
    final cashCounted = _money(
      rows.fold<double>(0, (sum, row) => sum + row.cashCountedLessOpening),
    );
    final cashExpensesPaid = _money(
      rows.fold<double>(0, (sum, row) => sum + row.approvedWithdrawals),
    );
    final cashOperational = _money(
      rows.fold<double>(
        0,
        (sum, row) => sum + row.cashOperationalBeforeExpenses,
      ),
    );
    final card = _money(
      rows.fold<double>(0, (sum, row) => sum + row.cardReceived),
    );
    final cardGross = _money(
      rows.fold<double>(0, (sum, row) => sum + row.cardGrossReceived),
    );
    final cardFees = _money(
      rows.fold<double>(0, (sum, row) => sum + row.cardFeeAbsorbed),
    );
    final other = _money(
      rows.fold<double>(
        0,
        (sum, row) => sum + row.platformReceived + row.otherReceived,
      ),
    );
    final actualIncome = _money(cashOperational + card + other);
    return FinanceCashCutDailyDetail(
      businessDate: entry.key,
      cashCounted: cashCounted,
      cashExpensesPaid: cashExpensesPaid,
      cashOperationalBeforeExpenses: cashOperational,
      cardReceived: card,
      cardGrossReceived: cardGross,
      cardFees: cardFees,
      otherReceived: other,
      actualIncome: actualIncome,
      expectedMonetaryIncome: _money(
        rows.fold<double>(0, (sum, row) => sum + row.expectedMonetaryIncome),
      ),
      shortage: _money(rows.fold<double>(0, (sum, row) => sum + row.shortage)),
      overage: _money(rows.fold<double>(0, (sum, row) => sum + row.overage)),
      cutCount: rows.length,
      closedByNames: names.toList(growable: false)..sort(),
      cuts: List.unmodifiable(rows),
    );
  }).toList();
  result.sort((a, b) => a.businessDate.compareTo(b.businessDate));
  return result;
}

FinanceCashCutDailyDetail buildFinanceCashCutPeriodTotal(
  Iterable<FinanceCashCutDailyDetail> days,
) {
  final rows = days.toList(growable: false);
  return FinanceCashCutDailyDetail(
    businessDate: 'TOTAL',
    cashCounted: _money(
      rows.fold<double>(0, (sum, row) => sum + row.cashCounted),
    ),
    cashExpensesPaid: _money(
      rows.fold<double>(0, (sum, row) => sum + row.cashExpensesPaid),
    ),
    cashOperationalBeforeExpenses: _money(
      rows.fold<double>(
        0,
        (sum, row) => sum + row.cashOperationalBeforeExpenses,
      ),
    ),
    cardReceived: _money(
      rows.fold<double>(0, (sum, row) => sum + row.cardReceived),
    ),
    cardGrossReceived: _money(
      rows.fold<double>(0, (sum, row) => sum + row.cardGrossReceived),
    ),
    cardFees: _money(rows.fold<double>(0, (sum, row) => sum + row.cardFees)),
    otherReceived: _money(
      rows.fold<double>(0, (sum, row) => sum + row.otherReceived),
    ),
    actualIncome: _money(
      rows.fold<double>(0, (sum, row) => sum + row.actualIncome),
    ),
    expectedMonetaryIncome: _money(
      rows.fold<double>(0, (sum, row) => sum + row.expectedMonetaryIncome),
    ),
    shortage: _money(rows.fold<double>(0, (sum, row) => sum + row.shortage)),
    overage: _money(rows.fold<double>(0, (sum, row) => sum + row.overage)),
    cutCount: rows.fold<int>(0, (sum, row) => sum + row.cutCount),
    closedByNames: const [],
    cuts: const [],
  );
}

class FinanceCustomerPayment {
  const FinanceCustomerPayment({
    required this.payment,
    required this.order,
    required this.businessDate,
    required this.amount,
  });

  final Payment payment;
  final PosOrder order;
  final String businessDate;
  final double amount;
}

class FinanceSalesDayRow {
  const FinanceSalesDayRow({
    required this.businessDate,
    required this.grossSales,
    required this.salesWithoutDiscount,
    required this.salesWithDiscount,
    required this.discounts,
    required this.netSales,
    required this.documents,
  });

  final String businessDate;
  final double grossSales;
  final double salesWithoutDiscount;
  final double salesWithDiscount;
  final double discounts;
  final double netSales;
  final int documents;
}

class FinanceCollectionsDayRow {
  const FinanceCollectionsDayRow({
    required this.businessDate,
    required this.cash,
    required this.card,
    required this.other,
    required this.cardFees,
    required this.shortage,
    required this.overage,
    required this.realCollected,
  });

  final String businessDate;
  final double cash;
  final double card;
  final double other;
  final double cardFees;
  final double shortage;
  final double overage;
  final double realCollected;
}

class FinanceSupplierRow {
  const FinanceSupplierRow({
    required this.supplierId,
    required this.supplierName,
    required this.invoiced,
    required this.paidOnInvoices,
    required this.paidInPeriod,
    required this.balance,
    required this.documents,
    required this.purchases,
    required this.payments,
  });

  final String supplierId;
  final String supplierName;
  final double invoiced;
  final double paidOnInvoices;
  final double paidInPeriod;
  final double balance;
  final int documents;
  final List<SupplierPurchase> purchases;
  final List<SupplierPayment> payments;
}

enum FinanceExpenseStatus { paid, pending, cancelled }

FinanceExpenseStatus financeExpenseStatus(CashWithdrawalRequest request) {
  return switch (_token(request.status)) {
    'approved' ||
    'aprobado' ||
    'aprobada' ||
    'paid' ||
    'pagado' ||
    'pagada' => FinanceExpenseStatus.paid,
    'pending' || 'pendiente' => FinanceExpenseStatus.pending,
    _ => FinanceExpenseStatus.cancelled,
  };
}

bool isFinanceOperatingExpense(CashWithdrawalRequest request) {
  final source = _token(request.source);
  if (source.isEmpty || source == 'historical_admin') return true;
  return !const {
    'supplier_payment',
    'supplier payment',
    'pago_proveedor',
    'pago proveedor',
    'partner_contribution',
    'partner contribution',
    'aportacion_socio',
    'aportacion socio',
    'cash_transfer',
    'cash transfer',
    'transferencia_interna',
    'transferencia interna',
  }.contains(source);
}

String financePurchaseBusinessDate(SupplierPurchase purchase) {
  return _validBusinessDate(purchase.businessDate) ??
      _dateKey(purchase.purchaseDate);
}

String financeSupplierPaymentBusinessDate(SupplierPayment payment) {
  return _validBusinessDate(payment.businessDate) ??
      _dateKey(payment.paymentDate);
}

double financePurchaseBalance(SupplierPurchase purchase) {
  if (purchase.isCancelled) return 0;
  if (purchase.balance >= 0) return _money(purchase.balance);
  return _money(
    (purchase.total - purchase.paidTotal).clamp(0, double.infinity),
  );
}

FinanceDashboardBundle buildFinanceDashboard(
  FinanceDashboardInput input, {
  int firestoreQueries = 0,
  DateTime? loadedAt,
}) {
  final key = input.key;
  final salesOrders = input.salesSummary.orderRows
      .where(
        (row) =>
            _inRange(row.businessDate, key) &&
            (row.grossSales > financeMoneyTolerance ||
                row.totalCollected > financeMoneyTolerance),
      )
      .toList(growable: false);
  final ordersById = {for (final row in salesOrders) row.order.id: row.order};
  final customerPayments = <FinanceCustomerPayment>[];
  for (final entry in input.paymentsByOrder.entries) {
    final order = ordersById[entry.key];
    if (order == null) continue;
    for (final payment in entry.value) {
      if (!isCanonicalActivePayment(payment)) continue;
      final businessDate = resolveOperationalBusinessDate(
        order: order,
        payment: payment,
        historicalFallback:
            order.createdAt ?? payment.createdAt ?? order.updatedAt,
      );
      if (!_inRange(businessDate, key)) continue;
      customerPayments.add(
        FinanceCustomerPayment(
          payment: payment,
          order: order,
          businessDate: businessDate,
          amount: canonicalPaymentAppliedAmount(payment),
        ),
      );
    }
  }
  customerPayments.sort(
    (a, b) => (b.payment.createdAt ?? DateTime(1970)).compareTo(
      a.payment.createdAt ?? DateTime(1970),
    ),
  );

  final cashSessions = input.cashSessions
      .where(
        (row) =>
            _inRange(row.businessDate, key) &&
            financeCashSessionCountsAsClosed(row),
      )
      .toList(growable: false);
  final cashCutSummaries = cashSessions
      .map(buildFinanceCashCutSummary)
      .toList(growable: false);
  final expenses =
      input.withdrawals
          .where(
            (row) =>
                _inRange(row.businessDate, key) &&
                isFinanceOperatingExpense(row),
          )
          .toList()
        ..sort(
          (a, b) => (b.requestedAt ?? DateTime(1970)).compareTo(
            a.requestedAt ?? DateTime(1970),
          ),
        );
  final purchases =
      input.purchases
          .where(
            (row) =>
                !row.isCancelled &&
                row.total >= 0 &&
                _inRange(financePurchaseBusinessDate(row), key),
          )
          .toList()
        ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
  final supplierPayments =
      input.supplierPayments
          .where(
            (row) =>
                row.isActive &&
                row.amount > 0 &&
                _inRange(financeSupplierPaymentBusinessDate(row), key),
          )
          .toList()
        ..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));

  return FinanceDashboardBundle(
    key: key,
    salesSummary: input.salesSummary,
    salesOrders: salesOrders,
    customerPayments: customerPayments,
    cashSessions: cashSessions,
    cashCutSummaries: cashCutSummaries,
    expenses: expenses,
    purchases: purchases,
    supplierPayments: supplierPayments,
    suppliers: input.suppliers,
    salesByDay: _salesByDay(salesOrders),
    collectionsByDay: _collectionsByDay(customerPayments, cashCutSummaries),
    supplierRows: _supplierRows(purchases, supplierPayments),
    firestoreQueries: firestoreQueries,
    loadedAt: loadedAt ?? DateTime.now(),
  );
}

List<FinanceSalesDayRow> _salesByDay(List<CanonicalOrderSalesRow> orders) {
  final groups = <String, List<CanonicalOrderSalesRow>>{};
  for (final row in orders) {
    groups.putIfAbsent(row.businessDate, () => []).add(row);
  }
  final result = groups.entries.map((entry) {
    final rows = entry.value;
    return FinanceSalesDayRow(
      businessDate: entry.key,
      grossSales: _money(
        rows.fold<double>(0, (sum, row) => sum + row.grossSales),
      ),
      salesWithoutDiscount: _money(
        rows
            .where((row) => !row.hasExplicitDiscount)
            .fold<double>(0, (sum, row) => sum + row.netSales),
      ),
      salesWithDiscount: _money(
        rows
            .where((row) => row.hasExplicitDiscount)
            .fold<double>(0, (sum, row) => sum + row.netSales),
      ),
      discounts: _money(
        rows.fold<double>(0, (sum, row) => sum + row.discountTotal),
      ),
      netSales: _money(rows.fold<double>(0, (sum, row) => sum + row.netSales)),
      documents: rows.length,
    );
  }).toList()..sort((a, b) => b.businessDate.compareTo(a.businessDate));
  return result;
}

List<FinanceCollectionsDayRow> _collectionsByDay(
  List<FinanceCustomerPayment> payments,
  List<FinanceCashCutSummary> cashCuts,
) {
  final dates = {
    ...payments.map((row) => row.businessDate),
    ...cashCuts.map((row) => row.businessDate),
  };
  final result = <FinanceCollectionsDayRow>[];
  for (final date in dates) {
    final dailyCashCuts = cashCuts.where((row) => row.businessDate == date);
    final cash = _money(
      dailyCashCuts.fold<double>(0, (sum, row) => sum + row.cashReceived),
    );
    final card = _money(
      dailyCashCuts.fold<double>(0, (sum, row) => sum + row.cardReceived),
    );
    final other = _money(
      dailyCashCuts.fold<double>(
        0,
        (sum, row) => sum + row.platformReceived + row.otherReceived,
      ),
    );
    result.add(
      FinanceCollectionsDayRow(
        businessDate: date,
        cash: cash,
        card: card,
        other: other,
        cardFees: _money(
          dailyCashCuts.fold<double>(
            0,
            (sum, row) => sum + row.cardFeeAbsorbed,
          ),
        ),
        shortage: _money(
          dailyCashCuts.fold<double>(0, (sum, row) => sum + row.shortage),
        ),
        overage: _money(
          dailyCashCuts.fold<double>(0, (sum, row) => sum + row.overage),
        ),
        realCollected: _money(cash + card + other),
      ),
    );
  }
  result.sort((a, b) => b.businessDate.compareTo(a.businessDate));
  return result;
}

List<FinanceSupplierRow> _supplierRows(
  List<SupplierPurchase> purchases,
  List<SupplierPayment> payments,
) {
  final supplierIds = {
    ...purchases.map((row) => row.supplierId),
    ...payments.map((row) => row.supplierId),
  };
  final rows = supplierIds.map((supplierId) {
    final supplierPurchases = purchases
        .where((row) => row.supplierId == supplierId)
        .toList(growable: false);
    final supplierPayments = payments
        .where((row) => row.supplierId == supplierId)
        .toList(growable: false);
    final fallbackName = supplierPurchases.isNotEmpty
        ? supplierPurchases.first.supplierName
        : supplierPayments.isNotEmpty
        ? supplierPayments.first.supplierName
        : 'Proveedor';
    return FinanceSupplierRow(
      supplierId: supplierId,
      supplierName: fallbackName,
      invoiced: _money(
        supplierPurchases.fold<double>(0, (sum, row) => sum + row.total),
      ),
      paidOnInvoices: _money(
        supplierPurchases.fold<double>(0, (sum, row) => sum + row.paidTotal),
      ),
      paidInPeriod: _money(
        supplierPayments.fold<double>(0, (sum, row) => sum + row.amount),
      ),
      balance: _money(
        supplierPurchases.fold<double>(
          0,
          (sum, row) => sum + financePurchaseBalance(row),
        ),
      ),
      documents: supplierPurchases.length,
      purchases: supplierPurchases,
      payments: supplierPayments,
    );
  }).toList()..sort((a, b) => b.invoiced.compareTo(a.invoiced));
  return rows;
}

class FinanceDashboardCache {
  FinanceDashboardCache({this.ttl = const Duration(seconds: 60)});

  final Duration ttl;
  final Map<FinanceDashboardKey, _FinanceCacheEntry> _cache = {};
  final Map<FinanceDashboardKey, Future<FinanceDashboardBundle>> _inFlight = {};

  Future<FinanceDashboardLoadResult> load({
    required FinanceDashboardKey key,
    required Future<FinanceDashboardBundle> Function() loader,
    bool forceRefresh = false,
  }) async {
    final cached = _cache[key];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.createdAt) < ttl) {
      return FinanceDashboardLoadResult(
        bundle: cached.bundle,
        fromCache: true,
        sharedInFlight: false,
      );
    }
    final pending = _inFlight[key];
    if (!forceRefresh && pending != null) {
      return FinanceDashboardLoadResult(
        bundle: await pending,
        fromCache: false,
        sharedInFlight: true,
      );
    }
    final future = loader();
    _inFlight[key] = future;
    try {
      final bundle = await future;
      _cache[key] = _FinanceCacheEntry(DateTime.now(), bundle);
      return FinanceDashboardLoadResult(
        bundle: bundle,
        fromCache: false,
        sharedInFlight: false,
      );
    } finally {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }
  }

  void invalidate(FinanceDashboardKey key) => _cache.remove(key);
}

class FinanceDashboardLoadResult {
  const FinanceDashboardLoadResult({
    required this.bundle,
    required this.fromCache,
    required this.sharedInFlight,
  });

  final FinanceDashboardBundle bundle;
  final bool fromCache;
  final bool sharedInFlight;
}

class _FinanceCacheEntry {
  const _FinanceCacheEntry(this.createdAt, this.bundle);

  final DateTime createdAt;
  final FinanceDashboardBundle bundle;
}

bool _inRange(String value, FinanceDashboardKey key) {
  return value.compareTo(key.startBusinessDate) >= 0 &&
      value.compareTo(key.endBusinessDate) <= 0;
}

bool _cancelledToken(String value) {
  return const {
    'cancelled',
    'canceled',
    'cancelado',
    'cancelada',
    'replaced',
    'voided',
    'anulado',
    'anulada',
  }.contains(_token(value));
}

String _token(String value) => value.trim().toLowerCase();

String? _validBusinessDate(String? value) {
  final clean = value?.trim();
  if (clean == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(clean)) {
    return null;
  }
  return clean;
}

String _dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

double _money(num value) => (value * 100).roundToDouble() / 100;
