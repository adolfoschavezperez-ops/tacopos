import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/canonical_sales_summary.dart';
import 'package:tacopos/core/reports/finance_dashboard.dart';
import 'package:tacopos/core/theme/app_theme.dart';
import 'package:tacopos/models/cash_session.dart';
import 'package:tacopos/models/cash_withdrawal_request.dart';
import 'package:tacopos/models/purchase_models.dart';
import 'package:tacopos/screens/admin/finance_main_dashboard_screen.dart';

void main() {
  testWidgets('dashboard financiero no desborda en resoluciones objetivo', (
    tester,
  ) async {
    final bundle = buildFinanceDashboard(
      FinanceDashboardInput(
        key: const FinanceDashboardKey(
          restaurantId: 'restaurant',
          branchId: 'branch',
          startBusinessDate: '2026-07-01',
          endBusinessDate: '2026-07-31',
        ),
        salesSummary: buildCanonicalSalesSummary(const []),
        paymentsByOrder: const {},
        cashSessions: const [],
        withdrawals: [
          for (var index = 1; index <= 5; index++) _expense(index, index * 100),
        ],
        purchases: [
          for (var index = 1; index <= 5; index++)
            _purchase(index, index * 1000),
        ],
        supplierPayments: [
          _supplierPayment(1, 1000, 'cash'),
          _supplierPayment(2, 2000, 'transfer'),
          _supplierPayment(3, 3000, 'partner_contribution'),
          _supplierPayment(4, 400, 'card'),
        ],
        suppliers: const [],
      ),
    );

    for (final size in const [
      Size(1920, 1080),
      Size(1600, 900),
      Size(1366, 768),
    ]) {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            backgroundColor: const Color(0xFF090A0B),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: FinanceDashboardContent(
                bundle: bundle,
                repository: null,
                refreshing: false,
                onRefresh: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('VENTA'), findsOneWidget);
      expect(find.text('INGRESO REAL'), findsOneWidget);
      expect(find.text('GASTOS'), findsOneWidget);
      expect(find.text('FACTURAS PROVEEDOR'), findsOneWidget);
      expect(find.text('PAGADO'), findsOneWidget);
      expect(find.text('RESUMEN'), findsOneWidget);
      expect(find.text('Total venta neta'), findsNWidgets(2));
      expect(find.text('Total ingreso real'), findsOneWidget);
      expect(find.text('Total gastos'), findsOneWidget);
      expect(find.text('Total facturado'), findsWidgets);
      expect(find.text('Total pagado'), findsWidgets);
      expect(find.text('Otros gastos'), findsNothing);
      expect(find.text('Otros proveedores'), findsNothing);
      expect(find.text('Gasto 1'), findsWidgets);
      expect(find.text('Gasto 5'), findsWidgets);
      expect(find.text('Proveedor 1'), findsWidgets);
      expect(find.text('Proveedor 5'), findsWidgets);
      expect(find.text('Otros métodos'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Resolucion $size');
    }

    final gasto = find.byKey(const ValueKey('finance-detail-line-Gasto 5'));
    await tester.ensureVisible(gasto);
    await tester.tap(gasto);
    await tester.pumpAndSettle();
    expect(find.text('Detalle de Gasto 5'), findsOneWidget);
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text(r'$500.00'), findsWidgets);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('abre detalle diario de ingreso real desde KPI', (tester) async {
    final bundle = buildFinanceDashboard(
      FinanceDashboardInput(
        key: const FinanceDashboardKey(
          restaurantId: 'restaurant',
          branchId: 'branch',
          startBusinessDate: '2026-08-01',
          endBusinessDate: '2026-08-31',
        ),
        salesSummary: buildCanonicalSalesSummary(const []),
        paymentsByOrder: const {},
        cashSessions: [
          _cashSession(
            id: 'cut-2026-08-05',
            businessDate: '2026-08-05',
            countedCashAmount: 2999,
            terminalReportedAmount: 2500,
            expectedCashAmount: 3049,
            expectedCardChargedAmount: 2500,
            approvedWithdrawalsTotal: 500,
          ),
        ],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          backgroundColor: const Color(0xFF090A0B),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: FinanceDashboardContent(
              bundle: bundle,
              repository: null,
              refreshing: false,
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('INGRESO REAL').first);
    await tester.pumpAndSettle();

    expect(find.text('Ingreso real por dia'), findsOneWidget);
    expect(find.text('05/08/2026'), findsWidgets);
    expect(find.text('Efectivo contado'), findsWidgets);
    expect(find.text('Gastos pagados desde caja'), findsOneWidget);
    expect(find.text('Efectivo antes de gastos'), findsWidgets);
    expect(find.text(r'$2,999.00'), findsWidgets);
    expect(find.text(r'$500.00'), findsWidgets);
    expect(find.text(r'$3,499.00'), findsWidgets);
    expect(find.text(r'$5,999.00'), findsWidgets);
  });

  testWidgets('resumen final colorea importe y recuadro por signo', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1600, 1800)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    expect(financeFinalResultColor(-2412.66), const Color(0xFFE36565));
    expect(financeFinalResultColor(3500), const Color(0xFF55B845));
    expect(financeFinalResultColor(0), const Color(0xFFA2A6AA));

    final formulaBundle = _summaryBundle(
      real: 25360.70,
      expenses: 2015,
      pendingInvoices: 25758.36,
    );
    expect(
      formulaBundle.finalResult,
      closeTo(25360.70 - 2015 - 25758.36, 0.001),
    );

    final negativeBundle = _summaryBundle(real: 100, expenses: 150);
    await _pumpDashboardContent(tester, negativeBundle);
    _expectSummaryFinalStyle(
      tester,
      color: const Color(0xFFE36565),
      value: r'-$50.00',
    );
    await _pumpShareSummary(tester, negativeBundle);
    _expectShareFinalStyle(
      tester,
      color: const Color(0xFFE36565),
      value: r'-$50.00',
    );

    final positiveBundle = _summaryBundle(real: 3500);
    await _pumpDashboardContent(tester, positiveBundle);
    _expectSummaryFinalStyle(
      tester,
      color: const Color(0xFF55B845),
      value: r'$3,500.00',
    );
    await _pumpShareSummary(tester, positiveBundle);
    _expectShareFinalStyle(
      tester,
      color: const Color(0xFF55B845),
      value: r'$3,500.00',
    );

    final zeroBundle = _summaryBundle();
    await _pumpDashboardContent(tester, zeroBundle);
    _expectSummaryFinalStyle(
      tester,
      color: const Color(0xFFA2A6AA),
      value: r'$0.00',
    );
    await _pumpShareSummary(tester, zeroBundle);
    _expectShareFinalStyle(
      tester,
      color: const Color(0xFFA2A6AA),
      value: r'$0.00',
    );
  });
}

Future<void> _pumpDashboardContent(
  WidgetTester tester,
  FinanceDashboardBundle bundle,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        backgroundColor: const Color(0xFF090A0B),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: FinanceDashboardContent(
            bundle: bundle,
            repository: null,
            refreshing: false,
            onRefresh: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpShareSummary(
  WidgetTester tester,
  FinanceDashboardBundle bundle,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        backgroundColor: const Color(0xFF090A0B),
        body: RepaintBoundary(
          child: financeShareSummaryForTest(
            bundle: bundle,
            restaurantName: "Los Padrino's Tacos",
            branchName: 'Aviacion',
            generatedAt: DateTime(2026, 8, 17, 14, 30),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _expectSummaryFinalStyle(
  WidgetTester tester, {
  required Color color,
  required String value,
}) {
  final card = tester.widget<Container>(
    find.byKey(const ValueKey('finance-summary-card-3. RESUMEN FINAL')),
  );
  expect(_containerBorderColor(card), color);

  final resultText = tester.widget<Text>(
    find.byKey(const ValueKey('finance-summary-total-3. RESUMEN FINAL')),
  );
  expect(resultText.data, value);
  expect(resultText.style?.color, color);
}

void _expectShareFinalStyle(
  WidgetTester tester, {
  required Color color,
  required String value,
}) {
  final section = tester.widget<Container>(
    find.byKey(const ValueKey('finance-share-final-section')),
  );
  expect(_containerBorderColor(section), color);

  final resultText = tester.widget<Text>(
    find.byKey(const ValueKey('finance-share-value-SALDO FINAL')),
  );
  expect(resultText.data, value);
  expect(resultText.style?.color, color);
}

Color _containerBorderColor(Container container) {
  final decoration = container.decoration! as BoxDecoration;
  final border = decoration.border! as Border;
  return border.top.color;
}

FinanceDashboardBundle _summaryBundle({
  double real = 0,
  double expenses = 0,
  double supplierPaid = 0,
  double pendingInvoices = 0,
}) {
  return buildFinanceDashboard(
    FinanceDashboardInput(
      key: const FinanceDashboardKey(
        restaurantId: 'restaurant',
        branchId: 'branch',
        startBusinessDate: '2026-08-10',
        endBusinessDate: '2026-08-16',
      ),
      salesSummary: buildCanonicalSalesSummary(const []),
      paymentsByOrder: const {},
      cashSessions: real == 0
          ? const []
          : [
              _cashSession(
                id: 'summary-result-cut',
                businessDate: '2026-08-10',
                countedCashAmount: real,
                expectedCashAmount: real,
              ),
            ],
      withdrawals: expenses == 0
          ? const []
          : [_expense(1, expenses, businessDate: '2026-08-10')],
      purchases: pendingInvoices == 0
          ? const []
          : [
              _purchase(
                1,
                pendingInvoices,
                businessDate: '2026-08-10',
                purchaseDate: DateTime(2026, 8, 10),
              ),
            ],
      supplierPayments: supplierPaid == 0
          ? const []
          : [
              _supplierPayment(
                1,
                supplierPaid,
                'cash',
                businessDate: '2026-08-10',
                paymentDate: DateTime(2026, 8, 10),
              ),
            ],
      suppliers: const [],
    ),
  );
}

CashWithdrawalRequest _expense(
  int index,
  double amount, {
  String businessDate = '2026-07-12',
}) {
  return CashWithdrawalRequest(
    id: 'expense-$index',
    cashSessionId: 'cash',
    businessDate: businessDate,
    amount: amount,
    reason: 'Gasto $index',
    requestedByEmployeeId: 'employee',
    requestedByEmployeeName: 'Empleado',
    status: 'approved',
  );
}

CashSession _cashSession({
  required String id,
  required String businessDate,
  double openingCashAmount = 0,
  double countedCashAmount = 0,
  double terminalReportedAmount = 0,
  double expectedCashAmount = 0,
  double expectedCardChargedAmount = 0,
  double approvedWithdrawalsTotal = 0,
}) {
  final netDifference =
      (countedCashAmount + terminalReportedAmount) -
      (expectedCashAmount + expectedCardChargedAmount);
  return CashSession(
    id: id,
    businessDate: businessDate,
    status: 'closed',
    openingCashAmount: openingCashAmount,
    openedByEmployeeId: 'employee',
    openedByEmployeeName: 'Empleado',
    closedByEmployeeId: 'employee',
    closedByEmployeeName: 'Empleado',
    countedCashAmount: countedCashAmount,
    terminalReportedAmount: terminalReportedAmount,
    expectedCashAmount: expectedCashAmount,
    expectedCardChargedAmount: expectedCardChargedAmount,
    expectedCardBaseAmount: expectedCardChargedAmount,
    expectedCardSurchargeAmount: 0,
    expectedCardFeeAbsorbedAmount: 0,
    expectedPlatformAmount: 0,
    expectedEmployeeConsumptionAmount: 0,
    totalExpectedRealMoney: expectedCashAmount + expectedCardChargedAmount,
    totalCountedRealMoney: countedCashAmount + terminalReportedAmount,
    cashDifference: countedCashAmount - expectedCashAmount,
    cardDifference: terminalReportedAmount - expectedCardChargedAmount,
    netDifference: netDifference,
    shortageAmount: netDifference < 0 ? netDifference.abs() : 0,
    overAmount: netDifference > 0 ? netDifference : 0,
    approvedWithdrawalsTotal: approvedWithdrawalsTotal,
    pendingWithdrawalsTotal: 0,
    withdrawalRequestCount: approvedWithdrawalsTotal > 0 ? 1 : 0,
    notes: '',
  );
}

SupplierPurchase _purchase(
  int index,
  double total, {
  String businessDate = '2026-07-12',
  DateTime? purchaseDate,
}) {
  return SupplierPurchase(
    id: 'purchase-$index',
    supplierId: 'supplier-$index',
    supplierName: 'Proveedor $index',
    purchaseDate: purchaseDate ?? DateTime(2026, 7, 12),
    businessDate: businessDate,
    folio: 'F-$index',
    documentType: 'invoice',
    status: 'pending',
    subtotal: total,
    total: total,
    paidTotal: 0,
    balance: total,
  );
}

SupplierPayment _supplierPayment(
  int index,
  double amount,
  String method, {
  String businessDate = '2026-07-12',
  DateTime? paymentDate,
}) {
  return SupplierPayment(
    id: 'payment-$index',
    supplierId: 'supplier-$index',
    supplierName: 'Proveedor $index',
    purchaseId: 'purchase-$index',
    purchaseFolio: 'F-$index',
    paymentDate: paymentDate ?? DateTime(2026, 7, 12),
    businessDate: businessDate,
    amount: amount,
    method: method,
    status: 'active',
  );
}
