import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/canonical_sales_summary.dart';
import 'package:tacopos/core/reports/finance_dashboard.dart';
import 'package:tacopos/core/theme/app_theme.dart';
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
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
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
      expect(tester.takeException(), isNull, reason: 'Resolucion $size');
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
