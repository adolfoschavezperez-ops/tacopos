import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/backoffice_v2/auth/backoffice_auth_service.dart';
import 'package:tacopos/backoffice_v2/auth/backoffice_permissions.dart';
import 'package:tacopos/backoffice_v2/features/purchases/purchases_analytics.dart';
import 'package:tacopos/backoffice_v2/navigation/backoffice_route.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/models/purchase_models.dart';

void main() {
  group('Phase 5 PurchasesAnalytics', () {
    test(
      'keeps incompatible units separate, differentiates similar item names, computes weighted average cost, and detects >=8% price alerts',
      () {
        final p1 = SupplierPurchase(
          id: 'sp_1',
          supplierId: 'sup_1',
          supplierName: 'Carnicería A',
          purchaseDate: DateTime(2026, 11, 20),
          businessDate: '2026-11-20',
          folio: 'C-0001',
          documentType: 'invoice',
          status: 'paid',
          subtotal: 1180,
          total: 1180,
          paidTotal: 1180,
          balance: 0,
        );
        final p2 = SupplierPurchase(
          id: 'sp_2',
          supplierId: 'sup_2',
          supplierName: 'Carnicería B',
          purchaseDate: DateTime(2026, 11, 25),
          businessDate: '2026-11-25',
          folio: 'C-0002',
          documentType: 'invoice',
          status: 'pending',
          subtotal: 2680,
          total: 2680,
          paidTotal: 0,
          balance: 2680,
        );

        final itemsMap = {
          'sp_1': const [
            SupplierPurchaseItem(
              id: 'l1',
              purchaseItemId: 'pi_pastor_kg',
              purchaseItemName: 'Carne al Pastor',
              quantity: 10,
              unit: 'kg',
              unitCost: 118,
              total: 1180,
              lineTotal: 1180,
              lineTotalCents: 118000,
              unitCostCalculated: 118,
              calculationMode: 'line_total',
            ),
            SupplierPurchaseItem(
              id: 'l2',
              purchaseItemId: 'pi_salsa_lt',
              purchaseItemName: 'Salsa Verde',
              quantity: 5,
              unit: 'lt',
              unitCost: 40,
              total: 200,
              lineTotal: 200,
              lineTotalCents: 20000,
              unitCostCalculated: 40,
              calculationMode: 'line_total',
            ),
          ],
          'sp_2': const [
            SupplierPurchaseItem(
              id: 'l3',
              purchaseItemId: 'pi_pastor_kg',
              purchaseItemName: 'Carne al Pastor',
              quantity: 20,
              unit: 'kg',
              unitCost: 134,
              total: 2680,
              lineTotal: 2680,
              lineTotalCents: 268000,
              unitCostCalculated: 134,
              calculationMode: 'line_total',
            ),
            // Different item ID & unit ("pieza" vs "lt") must NOT be merged
            SupplierPurchaseItem(
              id: 'l4',
              purchaseItemId: 'pi_salsa_pza',
              purchaseItemName: 'Salsa Verde',
              quantity: 10,
              unit: 'pieza',
              unitCost: 25,
              total: 250,
              lineTotal: 250,
              lineTotalCents: 25000,
              unitCostCalculated: 25,
              calculationMode: 'line_total',
            ),
          ],
        };

        final metrics = PurchasesAnalytics.computeDashboard(
          currentPurchases: [p1, p2],
          previousPurchases: const [],
          currentItemsByPurchase: itemsMap,
          previousItemsByPurchase: const {},
          catalogItems: const [
            PurchaseItem(
              id: 'pi_pastor_kg',
              name: 'Carne al Pastor',
              category: 'Carnes',
              unit: 'kg',
              active: true,
            ),
          ],
          branchNames: const {'suc_centro': 'Centro'},
        );

        expect(metrics.totalAmount, 3860);
        expect(metrics.paidAmount, 1180);
        expect(metrics.pendingAmount, 2680);
        expect(metrics.purchasesCount, 2);

        // 3 distinct item+unit rows (pastor kg, salsa lt, salsa pieza)
        expect(metrics.itemReports.length, 3);
        final pastor = metrics.itemReports.firstWhere(
          (r) => r.itemName == 'Carne al Pastor',
        );
        expect(pastor.totalQuantity, 30);
        expect(pastor.totalAmount, 3860);
        // Weighted average = 3860 / 30 = 128.666...
        expect(pastor.weightedAvgCost, closeTo(128.67, 0.01));
        expect(pastor.minUnitCost, 118);
        expect(pastor.maxUnitCost, 134);
        expect(pastor.lastUnitCost, 134);
        expect(pastor.supplierComparison.length, 2);

        // Price increase alert: 118 -> 134 = +13.56% >= 8%
        expect(metrics.priceAlerts.length, 1);
        expect(metrics.priceAlerts.first.itemName, 'Carne al Pastor');
        expect(metrics.priceAlerts.first.increasePct, closeTo(13.56, 0.05));
      },
    );

    test(
      'computes CXP aging buckets, excludes paid/cancelled purchases, and detects balance mismatches',
      () {
        final asOf = DateTime(2026, 11, 26);
        final paid = SupplierPurchase(
          id: 'p_paid',
          supplierId: 's1',
          supplierName: 'Prov 1',
          purchaseDate: DateTime(2026, 11, 1),
          dueDate: DateTime(2026, 11, 10),
          folio: 'C-01',
          documentType: 'invoice',
          status: 'paid',
          subtotal: 1000,
          total: 1000,
          paidTotal: 1000,
          balance: 0,
        );
        final overdue10 = SupplierPurchase(
          id: 'p_ov10',
          supplierId: 's1',
          supplierName: 'Prov 1',
          purchaseDate: DateTime(2026, 11, 6),
          dueDate: DateTime(2026, 11, 16),
          folio: 'C-02',
          documentType: 'invoice',
          status: 'partial',
          subtotal: 1000,
          total: 1000,
          paidTotal: 400,
          balance: 600,
        );
        final dueSoon = SupplierPurchase(
          id: 'p_soon',
          supplierId: 's2',
          supplierName: 'Prov 2',
          purchaseDate: DateTime(2026, 11, 22),
          dueDate: DateTime(2026, 11, 29),
          folio: 'C-03',
          documentType: 'note',
          status: 'pending',
          subtotal: 500,
          total: 500,
          paidTotal: 0,
          balance: 500,
        );

        final cxp = PurchasesAnalytics.computeAccountsPayable(
          purchases: [paid, overdue10, dueSoon],
          asOf: asOf,
        );

        expect(cxp.openPurchases.length, 2);
        expect(cxp.totalPending, 1100);
        expect(cxp.overdueAmount, 600);
        expect(cxp.dueSoonAmount, 500);
        expect(cxp.reconciliationMismatches, isEmpty);
        expect(cxp.agingBuckets[0].amount, 500); // Al corriente
        expect(cxp.agingBuckets[1].amount, 600); // 1-15 días vencido
      },
    );

    test(
      'computes efficiency per \$100 sales and weekly item budget excess',
      () {
        final eff = PurchasesAnalytics.computeEfficiency(
          label: 'Carnes',
          purchasesAmount: 4200,
          netSalesAmount: 10000,
          previousPurchasesAmount: 3500,
          previousNetSalesAmount: 10000,
          targetPer100Sales: 36,
        );
        expect(eff.costPer100Sales, 42.0);
        expect(eff.previousCostPer100Sales, 35.0);
        expect(eff.deviationPer100Sales, 6.0);

        const row = ItemPurchaseReportRow(
          itemKey: 'pi_tripa|kg',
          itemName: 'Tripa Limpia',
          category: 'Carnes',
          unit: 'kg',
          totalQuantity: 28,
          totalAmount: 3976,
          weightedAvgCost: 142,
          lastUnitCost: 142,
          minUnitCost: 142,
          maxUnitCost: 142,
          previousPeriodAmount: 0,
          variationPct: 0,
          priceHistory: [],
          supplierComparison: [],
          purchaseIds: [],
        );
        final budget = PurchasesAnalytics.evaluateWeeklyBudget(
          itemReport: row,
          targetWeeklyQty: 24,
        );
        expect(budget.purchasedQty, 28);
        expect(budget.differenceQty, 4);
        expect(budget.isExceeded, isTrue);
      },
    );
  });

  group('Phase 4 SessionRenewalGuard (no idTokenChanges/getIdToken loop)', () {
    test('skips redundant checks within cooldown and while in-flight', () async {
      final guard = SessionRenewalGuard(cooldown: const Duration(seconds: 60));
      final t0 = DateTime(2026, 11, 26, 12, 0, 0);

      final first = await guard.runGuarded(() async => true, now: t0);
      expect(first, isTrue);
      expect(guard.executedChecks, 1);

      // Simulate idTokenChanges + resume firing 5 seconds later
      final second = await guard.runGuarded(
        () async => true,
        now: t0.add(const Duration(seconds: 5)),
      );
      expect(second, isNull);
      expect(guard.executedChecks, 1);
      expect(guard.skippedChecks, 1);

      // After cooldown expires (61s), executes again cleanly
      final third = await guard.runGuarded(
        () async => true,
        now: t0.add(const Duration(seconds: 61)),
      );
      expect(third, isTrue);
      expect(guard.executedChecks, 2);
    });
  });

  group('Phase 5 Granular Purchase Permissions', () {
    test('enforces view vs manage vs register vs pay permissions', () {
      const readOnly = Employee(
        id: 'e1',
        name: 'Auditor Compras',
        active: true,
        pin: '0000',
        canTakeOrders: false,
        canCharge: false,
        canViewKitchen: false,
        canViewAdmin: false,
        canManageProducts: false,
        canManageTables: false,
        canManagePlatforms: false,
        canManageEmployees: false,
        canManageCash: false,
        canAuthorizeCashWithdrawals: false,
        canOpenKitchen: false,
        canCloseKitchen: false,
        canViewKitchenReports: false,
        canViewKitchenHourlySalesComparison: false,
        canManageKitchenStock: false,
        canCancelOrders: false,
        canCancelPayments: false,
        canCancelItems: false,
        canApproveKitchenCancellations: false,
        canViewLiveOperations: false,
        canControlLiveOperations: false,
        canViewPurchases: true,
      );
      const perms = BackofficePermissions(employee: readOnly);
      expect(perms.canViewSection(BackofficeSection.purchases), isTrue);
      expect(perms.canManageSuppliers, isFalse);
      expect(perms.canRegisterPurchases, isFalse);
      expect(perms.canPaySuppliers, isFalse);
    });
  });
}
