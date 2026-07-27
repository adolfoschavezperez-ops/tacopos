import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/canonical_sales_summary.dart';
import 'package:tacopos/core/reports/finance_dashboard.dart';
import 'package:tacopos/core/theme/app_theme.dart';
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
      expect(find.text('COBRADO'), findsOneWidget);
      expect(find.text('GASTOS'), findsOneWidget);
      expect(find.text('FACTURAS PROVEEDOR'), findsOneWidget);
      expect(find.text('PAGADO'), findsOneWidget);
      expect(find.text('RESUMEN'), findsOneWidget);
      expect(find.text('Total venta neta'), findsNWidgets(2));
      expect(find.text('Total cobrado'), findsOneWidget);
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
