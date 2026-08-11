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
      expect(find.text('Otros gastos'), findsOneWidget);
      expect(find.text('Otros proveedores'), findsOneWidget);
      expect(find.text('Otros métodos'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Resolucion $size');
    }

    await tester.ensureVisible(find.text('Otros gastos'));
    await tester.tap(find.text('Otros gastos'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Periodo 01/07/2026 al 31/07/2026'),
      findsOneWidget,
    );
    expect(find.textContaining('Sucursal'), findsWidgets);
    expect(find.text('Subtotal'), findsOneWidget);
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
}

CashWithdrawalRequest _expense(int index, double amount) {
  return CashWithdrawalRequest(
    id: 'expense-$index',
    cashSessionId: 'cash',
    businessDate: '2026-07-12',
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

SupplierPurchase _purchase(int index, double total) {
  return SupplierPurchase(
    id: 'purchase-$index',
    supplierId: 'supplier-$index',
    supplierName: 'Proveedor $index',
    purchaseDate: DateTime(2026, 7, 12),
    businessDate: '2026-07-12',
    folio: 'F-$index',
    documentType: 'invoice',
    status: 'pending',
    subtotal: total,
    total: total,
    paidTotal: 0,
    balance: total,
  );
}

SupplierPayment _supplierPayment(int index, double amount, String method) {
  return SupplierPayment(
    id: 'payment-$index',
    supplierId: 'supplier-$index',
    supplierName: 'Proveedor $index',
    purchaseId: 'purchase-$index',
    purchaseFolio: 'F-$index',
    paymentDate: DateTime(2026, 7, 12),
    businessDate: '2026-07-12',
    amount: amount,
    method: method,
    status: 'active',
  );
}
