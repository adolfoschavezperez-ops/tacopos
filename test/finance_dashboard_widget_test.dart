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
  testWidgets('dashboard principal inicia bajo demanda sin cargar finanzas', (
    tester,
  ) async {
    final loader = _FinanceDashboardLoaderSpy();

    await tester.pumpWidget(_dashboardShell(loader: loader));
    await tester.pump();

    expect(loader.calls, isEmpty);
    expect(find.text('Fecha desde'), findsOneWidget);
    expect(find.text('Fecha hasta'), findsOneWidget);
    expect(
      find.text(
        'Selecciona un rango de fechas para consultar el Dashboard financiero.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cargando dashboard financiero...'), findsNothing);
  });

  testWidgets('dashboard no consulta con fecha inicial incompleta', (
    tester,
  ) async {
    final loader = _FinanceDashboardLoaderSpy();

    await tester.pumpWidget(
      _dashboardShell(loader: loader, initialStartDate: DateTime(2026, 8, 17)),
    );
    await tester.tap(find.byKey(const ValueKey('finance-dashboard-search')));
    await tester.pump();

    expect(loader.calls, isEmpty);
    expect(
      find.text('Selecciona una fecha inicial y una fecha final.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'dashboard no consulta al seleccionar rango hasta pulsar buscar',
    (tester) async {
      final loader = _FinanceDashboardLoaderSpy();

      await tester.pumpWidget(
        _dashboardShell(
          loader: loader,
          initialStartDate: DateTime(2026, 8, 17),
          initialEndDate: DateTime(2026, 8, 23),
        ),
      );
      await tester.pump();

      expect(loader.calls, isEmpty);
      expect(find.text('Desde 17/08/2026'), findsOneWidget);
      expect(find.text('Hasta 23/08/2026'), findsOneWidget);
    },
  );

  testWidgets('dashboard busca solo al pulsar buscar y limpiar no consulta', (
    tester,
  ) async {
    final loader = _FinanceDashboardLoaderSpy();

    await tester.pumpWidget(
      _dashboardShell(
        loader: loader,
        initialStartDate: DateTime(2026, 8, 17),
        initialEndDate: DateTime(2026, 8, 23),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('finance-dashboard-search')));
    await tester.pumpAndSettle();

    expect(loader.calls, ['2026-08-17..2026-08-23']);
    expect(find.text('VENTA'), findsOneWidget);

    await tester.tap(find.text('Hoy'));
    await tester.pump();
    expect(loader.calls, ['2026-08-17..2026-08-23']);
    expect(find.text('VENTA'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('finance-dashboard-search')));
    await tester.pumpAndSettle();
    expect(loader.calls, hasLength(2));

    await tester.tap(find.byKey(const ValueKey('finance-dashboard-clear')));
    await tester.pump();
    expect(loader.calls, hasLength(2));
    expect(find.text('VENTA'), findsNothing);
    expect(find.text('Fecha desde'), findsOneWidget);
    expect(find.text('Fecha hasta'), findsOneWidget);
    expect(
      find.text(
        'Selecciona un rango de fechas para consultar el Dashboard financiero.',
      ),
      findsOneWidget,
    );
  });

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
        withdrawals: [
          _expense(
            1,
            500,
            businessDate: '2026-08-05',
            cashSessionId: 'cut-2026-08-05',
            source: 'cash_drawer',
          ),
        ],
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

  testWidgets('resumen financiero colorea resultado y conciliacion', (
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
    expect(
      financeReconciliationDifferenceColor(-2412.66),
      const Color(0xFFE9A91A),
    );
    expect(
      financeReconciliationDifferenceColor(46.87),
      const Color(0xFFE9A91A),
    );
    expect(financeReconciliationDifferenceColor(0), const Color(0xFF55B845));

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
    _expectSummaryFinancialStyle(
      tester,
      operatingColor: const Color(0xFFE36565),
      operatingValue: r'-$50.00',
      reconciliationColor: const Color(0xFFE9A91A),
      reconciliationValue: r'-$50.00',
    );
    await _pumpShareSummary(tester, negativeBundle);
    _expectShareFinancialStyle(
      tester,
      color: const Color(0xFFE9A91A),
      value: r'-$50.00',
    );

    final positiveBundle = _summaryBundle(real: 3500);
    await _pumpDashboardContent(tester, positiveBundle);
    _expectSummaryFinancialStyle(
      tester,
      operatingColor: const Color(0xFF55B845),
      operatingValue: r'$3,500.00',
      reconciliationColor: const Color(0xFFE9A91A),
      reconciliationValue: r'+$3,500.00',
    );
    await _pumpShareSummary(tester, positiveBundle);
    _expectShareFinancialStyle(
      tester,
      color: const Color(0xFFE9A91A),
      value: r'+$3,500.00',
    );

    final zeroBundle = _summaryBundle();
    await _pumpDashboardContent(tester, zeroBundle);
    _expectSummaryFinancialStyle(
      tester,
      operatingColor: const Color(0xFFA2A6AA),
      operatingValue: r'$0.00',
      reconciliationColor: const Color(0xFF55B845),
      reconciliationValue: r'$0.00',
      reconciled: true,
    );
    await _pumpShareSummary(tester, zeroBundle);
    _expectShareFinancialStyle(
      tester,
      color: const Color(0xFF55B845),
      value: r'$0.00',
      reconciled: true,
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

void _expectSummaryFinancialStyle(
  WidgetTester tester, {
  required Color operatingColor,
  required String operatingValue,
  required Color reconciliationColor,
  required String reconciliationValue,
  bool reconciled = false,
}) {
  final card = tester.widget<Container>(
    find.byKey(const ValueKey('finance-summary-card-RESUMEN FINANCIERO')),
  );
  expect(_containerBorderColor(card), reconciliationColor);

  final operatingText = tester.widget<Text>(
    find.byKey(const ValueKey('finance-summary-total-Resultado operativo')),
  );
  expect(operatingText.data, operatingValue);
  expect(operatingText.style?.color, operatingColor);

  final reconciliationText = tester.widget<Text>(
    find.byKey(
      ValueKey(
        'finance-summary-total-${reconciled ? 'Conciliado' : 'Diferencia por conciliar'}',
      ),
    ),
  );
  expect(reconciliationText.data, reconciliationValue);
  expect(reconciliationText.style?.color, reconciliationColor);
}

void _expectShareFinancialStyle(
  WidgetTester tester, {
  required Color color,
  required String value,
  bool reconciled = false,
}) {
  final section = tester.widget<Container>(
    find.byKey(const ValueKey('finance-share-final-section')),
  );
  expect(_containerBorderColor(section), color);

  final resultText = tester.widget<Text>(
    find.byKey(
      ValueKey(
        'finance-share-value-${reconciled ? 'CONCILIADO' : 'DIFERENCIA POR CONCILIAR'}',
      ),
    ),
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
  String cashSessionId = 'cash',
  String source = '',
}) {
  return CashWithdrawalRequest(
    id: 'expense-$index',
    cashSessionId: cashSessionId,
    businessDate: businessDate,
    amount: amount,
    reason: 'Gasto $index',
    requestedByEmployeeId: 'employee',
    requestedByEmployeeName: 'Empleado',
    status: 'approved',
    source: source,
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

Widget _dashboardShell({
  required _FinanceDashboardLoaderSpy loader,
  DateTime? initialStartDate,
  DateTime? initialEndDate,
}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: FinanceMainDashboardScreen(
      hasAccessOverride: true,
      dashboardLoader: loader.call,
      initialStartDate: initialStartDate,
      initialEndDate: initialEndDate,
    ),
  );
}

class _FinanceDashboardLoaderSpy {
  final calls = <String>[];

  Future<FinanceDashboardBundle> call({
    required String startBusinessDate,
    required String endBusinessDate,
    bool forceRefresh = false,
  }) async {
    calls.add('$startBusinessDate..$endBusinessDate');
    return buildFinanceDashboard(
      FinanceDashboardInput(
        key: FinanceDashboardKey(
          restaurantId: 'restaurant',
          branchId: 'branch',
          startBusinessDate: startBusinessDate,
          endBusinessDate: endBusinessDate,
        ),
        salesSummary: buildCanonicalSalesSummary(const []),
        paymentsByOrder: const {},
        cashSessions: const [],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );
  }
}
