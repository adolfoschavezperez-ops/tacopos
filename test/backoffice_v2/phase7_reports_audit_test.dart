import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/backoffice_v2/auth/backoffice_permissions.dart';
import 'package:tacopos/backoffice_v2/features/finance/finance_analytics.dart';
import 'package:tacopos/backoffice_v2/features/reports/reports_catalog.dart';
import 'package:tacopos/models/cash_withdrawal_request.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/payment.dart';
import 'package:tacopos/models/purchase_models.dart';

Employee _makeEmployee({
  bool canViewAdmin = false,
  bool canViewKitchenReports = false,
  bool canManageCash = false,
}) {
  return Employee(
    id: 'emp-1',
    name: 'Tester',
    active: true,
    pin: '0000',
    canTakeOrders: false,
    canCharge: false,
    canViewKitchen: false,
    canViewAdmin: canViewAdmin,
    canManageProducts: false,
    canManageTables: false,
    canManagePlatforms: false,
    canManageEmployees: false,
    canManageCash: canManageCash,
    canAuthorizeCashWithdrawals: false,
    canOpenKitchen: false,
    canCloseKitchen: false,
    canViewKitchenReports: canViewKitchenReports,
    canViewKitchenHourlySalesComparison: false,
    canManageKitchenStock: false,
    canCancelOrders: false,
    canCancelPayments: false,
    canCancelItems: false,
    canApproveKitchenCancellations: false,
    canViewLiveOperations: false,
    canControlLiveOperations: false,
  );
}

void main() {
  group('Phase 7 — 25 Reports Catalog, Permissions & Large Exports', () {
    test('Catalog contains all 25 unique Backoffice 1.0 report kinds', () {
      expect(backoffice25ReportsCatalog.length, 25);
      final uniqueKinds = backoffice25ReportsCatalog.map((r) => r.kind).toSet();
      expect(uniqueKinds.length, 25);
    });

    test('Report permissions enforce kitchen vs cashSchedule vs adminAudit', () {
      final kitchenOnly = BackofficePermissions(
        employee: _makeEmployee(canViewKitchenReports: true),
      );
      final cashOnly = BackofficePermissions(
        employee: _makeEmployee(canManageCash: true),
      );
      final admin = BackofficePermissions(
        employee: _makeEmployee(canViewAdmin: true),
      );

      final saleFolios = backoffice25ReportsCatalog.firstWhere(
        (r) => r.kind == BackofficeReportKind.saleFolios,
      );
      final kitchenWaste = backoffice25ReportsCatalog.firstWhere(
        (r) => r.kind == BackofficeReportKind.kitchenWaste,
      );
      final cashSchedule = backoffice25ReportsCatalog.firstWhere(
        (r) => r.kind == BackofficeReportKind.cashSchedule,
      );

      expect(kitchenWaste.isAllowed(kitchenOnly), isTrue);
      expect(saleFolios.isAllowed(kitchenOnly), isFalse);
      expect(cashSchedule.isAllowed(cashOnly), isTrue);
      expect(saleFolios.isAllowed(admin), isTrue);
    });

    test('Chunked CSV exports >1,000 and >10,000 rows preserving special chars and totals', () async {
      final rows1500 = List.generate(
        1500,
        (i) => ['2026-11-26', 'Taco "Pastor", Especial #$i', '\$1,250.50'],
      );
      final progressEvents = <double>[];
      final csv1500 = await buildChunkedCsv(
        headers: const ['Fecha', 'Producto', 'Total'],
        rows: rows1500,
        totalsRow: const ['TOTAL', '', '\$1,875,750.00'],
        onProgress: progressEvents.add,
        chunkSize: 500,
      );
      expect(csv1500, isNotNull);
      final lines1500 = csv1500!.trim().split('\n');
      expect(lines1500.length, 1502); // header + 1500 + totals
      expect(csv1500, contains('"Taco ""Pastor"", Especial #0"'));
      expect(progressEvents.last, 1.0);

      final rows10500 = List.generate(
        10500,
        (i) => ['id-$i', 'Sucursal Centro', '${i * 10}'],
      );
      final csv10500 = await buildChunkedCsv(
        headers: const ['ID', 'Sucursal', 'Monto'],
        rows: rows10500,
        chunkSize: 2000,
      );
      expect(csv10500, isNotNull);
      expect(csv10500!.trim().split('\n').length, 10501);
    });

    test('Chunked CSV export supports cooperative cancellation', () async {
      final token = ExportCancellationToken();
      final rows = List.generate(5000, (i) => ['r-$i', 'val']);
      var calls = 0;
      final res = await buildChunkedCsv(
        headers: const ['ID', 'Val'],
        rows: rows,
        chunkSize: 1000,
        cancellationToken: token,
        onProgress: (_) {
          calls++;
          if (calls == 2) token.cancel();
        },
      );
      expect(res, isNull);
    });
  });

  group('Phase 7 Section 7 & 8 — Financial Fixes & Local Scale Benchmark', () {
    test('Partial COGS never inflates profitMarginPercent and recognizes method aliases', () {
      expect(
        isPartnerSupplierPayment(
          SupplierPayment(
            id: 'sp',
            supplierId: 's',
            supplierName: 'Prov',
            purchaseId: 'p',
            purchaseFolio: 'F1',
            paymentDate: DateTime(2026, 11, 26),
            businessDate: '2026-11-26',
            amount: 100,
            method: 'partner_cash',
            fundingSource: 'partner_transfer',
            status: 'active',
          ),
        ),
        isTrue,
      );

      expect(
        isFinanceOperatingExpense(
          const CashWithdrawalRequest(
            id: 'w1',
            cashSessionId: 'c1',
            businessDate: '2026-11-26',
            amount: 100,
            reason: 'Pago prov',
            requestedByEmployeeId: 'e1',
            requestedByEmployeeName: 'Emp',
            status: 'approved',
            source: 'pago_proveedor',
          ),
        ),
        isFalse,
      );

      final summary = FinancePeriodSummary.compute(
        orders: const [
          PosOrder(
            id: 'o1',
            tableId: 't1',
            tableName: 'M1',
            status: 'paid',
            kitchenStatus: 'served',
            paymentStatus: 'paid',
            total: 1000,
            paidTotal: 1000,
            pendingTotal: 0,
            personNames: {1: 'M1'},
            orderType: 'dine_in',
            businessDate: '2026-11-26',
          ),
        ],
        itemsByOrder: const {
          'o1': [
            OrderItem(
              id: 'i1',
              personNumber: 1,
              personName: 'P1',
              productId: 'p1',
              productName: 'Taco',
              category: 'Tacos',
              qty: 10,
              unitPrice: 40,
              total: 400,
              notes: '',
              sendToKitchen: true,
              kitchenStatus: 'served',
              paymentStatus: 'paid',
            ),
            OrderItem(
              id: 'i2',
              personNumber: 1,
              personName: 'P1',
              productId: 'p2',
              productName: 'Agua',
              category: 'Bebidas',
              qty: 10,
              unitPrice: 60,
              total: 600,
              notes: '',
              sendToKitchen: false,
              kitchenStatus: 'served',
              paymentStatus: 'paid',
            ),
          ],
        },
        paymentsByOrder: const {
          'o1': [
            Payment(
              id: 'p1',
              orderId: 'o1',
              tableId: 't1',
              tableName: 'M1',
              type: 'full',
              method: 'cash',
              baseAmount: 1000,
              surchargeRate: 0,
              surchargeAmount: 0,
              chargedAmount: 1000,
              status: 'paid',
            ),
          ],
        },
        cashSessions: const [],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        partnerContributions: const [],
        productProfitability: const [
          ProductProfitabilityRow(
            productId: 'p1',
            productName: 'Taco',
            categoryName: 'Tacos',
            unitsSold: 10,
            avgRealPrice: 40,
            netRevenue: 400,
            hasRecipe: true,
            hasCost: true,
            usesHistoricalCost: false,
            theoreticalUnitCost: 10,
            totalCost: 100,
            estimatedGrossProfit: 300,
            marginPercent: 75,
            salesSharePercent: 40,
            profitSharePercent: 100,
            costNote: 'Teórico',
          ),
          ProductProfitabilityRow(
            productId: 'p2',
            productName: 'Agua',
            categoryName: 'Bebidas',
            unitsSold: 10,
            avgRealPrice: 60,
            netRevenue: 600,
            hasRecipe: false,
            hasCost: false,
            usesHistoricalCost: false,
            theoreticalUnitCost: null,
            totalCost: null,
            estimatedGrossProfit: null,
            marginPercent: null,
            salesSharePercent: 60,
            profitSharePercent: null,
            costNote: 'Costo N/D',
          ),
        ],
      );

      expect(summary.hasPartialCogs, isTrue);
      expect(summary.hasCompleteCogs, isFalse);
      expect(summary.cogsCoveragePercent, closeTo(40.0, 0.1));
      expect(summary.coveredGrossProfit, closeTo(300.0, 0.1));
      expect(summary.profitMarginPercent, isNull);
    });

    test('Local aggregation scales cleanly for 2,000 and 10,000 orders', () {
      List<PosOrder> genOrders(int count) => List.generate(
        count,
        (i) => PosOrder(
          id: 'o-$i',
          tableId: 't1',
          tableName: 'Mesa 1',
          status: 'paid',
          kitchenStatus: 'served',
          paymentStatus: 'paid',
          total: 120.0,
          paidTotal: 120.0,
          pendingTotal: 0.0,
          personNames: const {1: 'Mesa 1'},
          orderType: 'dine_in',
          businessDate: '2026-11-26',
          branchId: 'suc_centro',
        ),
      );

      final sw2k = Stopwatch()..start();
      FinancePeriodSummary.compute(
        orders: genOrders(2000),
        cashSessions: const [],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        partnerContributions: const [],
        productProfitability: const [],
      );
      sw2k.stop();

      final sw10k = Stopwatch()..start();
      FinancePeriodSummary.compute(
        orders: genOrders(10000),
        cashSessions: const [],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        partnerContributions: const [],
        productProfitability: const [],
      );
      sw10k.stop();

      expect(sw2k.elapsedMilliseconds, lessThan(1000));
      expect(sw10k.elapsedMilliseconds, lessThan(2000));
    });
  });
}
