import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/backoffice_v2/auth/backoffice_permissions.dart';
import 'package:tacopos/backoffice_v2/features/finance/finance_analytics.dart';
import 'package:tacopos/models/cash_session.dart';
import 'package:tacopos/models/cash_withdrawal_request.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/models/kitchen_session.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/payment.dart';
import 'package:tacopos/models/purchase_models.dart';
import 'package:tacopos/models/yield_profit_models.dart';

void main() {
  group('Phase 6 — Financial Engine & Parity Scenarios', () {
    test(
      'Separates tips, discounts, employee meals, card fees, purchases vs COGS, and deduplicates partner contributions',
      () {
        final orders = [
          const PosOrder(
            id: 'ord-1',
            tableId: 't1',
            tableName: 'Mesa 1',
            status: 'paid',
            kitchenStatus: 'served',
            paymentStatus: 'paid',
            total: 200.0,
            paidTotal: 200.0,
            pendingTotal: 0.0,
            personNames: {1: 'Mesa 1'},
            orderType: 'dine_in',
            explicitDiscount: 20.0,
            grossSubtotal: 220.0,
            netTotal: 200.0,
            businessDate: '2026-11-26',
            branchId: 'b1',
          ),
          const PosOrder(
            id: 'ord-2',
            tableId: 't2',
            tableName: 'Mesa 2',
            status: 'paid',
            kitchenStatus: 'served',
            paymentStatus: 'paid',
            total: 0.0,
            paidTotal: 0.0,
            pendingTotal: 0.0,
            personNames: {1: 'Empleado'},
            orderType: 'dine_in',
            grossSubtotal: 50.0,
            netTotal: 0.0,
            discountSource: 'employee_free_meal',
            businessDate: '2026-11-26',
            branchId: 'b1',
          ),
        ];

        final itemsByOrder = {
          'ord-1': const [
            OrderItem(
              id: 'i1',
              personNumber: 1,
              personName: 'P1',
              productId: 'prod-taco',
              productName: 'Taco Pastor',
              category: 'Tacos',
              qty: 4,
              unitPrice: 55.0,
              total: 200.0,
              notes: '',
              sendToKitchen: true,
              kitchenStatus: 'served',
              paymentStatus: 'paid',
            ),
          ],
          'ord-2': const [
            OrderItem(
              id: 'i2',
              personNumber: 1,
              personName: 'Empleado',
              productId: 'prod-taco',
              productName: 'Taco Pastor',
              category: 'Tacos',
              qty: 1,
              unitPrice: 50.0,
              total: 50.0,
              notes: '',
              sendToKitchen: true,
              kitchenStatus: 'served',
              paymentStatus: 'paid',
            ),
          ],
        };

        final paymentsByOrder = {
          'ord-1': const [
            Payment(
              id: 'pay-1',
              orderId: 'ord-1',
              tableId: 't1',
              tableName: 'Mesa 1',
              type: 'full',
              method: 'card',
              baseAmount: 200.0,
              surchargeRate: 0.0,
              surchargeAmount: 0.0,
              chargedAmount: 200.0,
              tipAmount: 30.0,
              status: 'paid',
            ),
          ],
          'ord-2': const [
            Payment(
              id: 'pay-2',
              orderId: 'ord-2',
              tableId: 't2',
              tableName: 'Mesa 2',
              type: 'full',
              method: 'employee_consumption',
              baseAmount: 50.0,
              surchargeRate: 0.0,
              surchargeAmount: 0.0,
              chargedAmount: 50.0,
              tipAmount: 0.0,
              status: 'paid',
              discountAmount: 50.0,
            ),
          ],
        };

        final cashSessions = [
          const CashSession(
            id: 'cs-1',
            businessDate: '2026-11-26',
            status: 'closed',
            openingCashAmount: 1000.0,
            openedByEmployeeId: 'e1',
            openedByEmployeeName: 'Cajero',
            countedCashAmount: 950.0,
            terminalReportedAmount: 200.0,
            expectedCashAmount: 950.0,
            expectedCardChargedAmount: 200.0,
            expectedCardBaseAmount: 200.0,
            expectedCardSurchargeAmount: 0.0,
            expectedCardFeeAbsorbedAmount: 6.0,
            expectedPlatformAmount: 0.0,
            expectedEmployeeConsumptionAmount: 50.0,
            totalExpectedRealMoney: 1144.0,
            totalCountedRealMoney: 1144.0,
            cashDifference: 0.0,
            cardDifference: 0.0,
            netDifference: 0.0,
            shortageAmount: 0.0,
            overAmount: 0.0,
            approvedWithdrawalsTotal: 50.0,
            pendingWithdrawalsTotal: 0.0,
            withdrawalRequestCount: 2,
            notes: '',
            branchId: 'b1',
          ),
        ];

        final withdrawals = [
          const CashWithdrawalRequest(
            id: 'w-op',
            cashSessionId: 'cs-1',
            businessDate: '2026-11-26',
            amount: 50.0,
            reason: 'Hielo y cilindros',
            requestedByEmployeeId: 'e1',
            requestedByEmployeeName: 'Cajero',
            status: 'approved',
            branchId: 'b1',
          ),
          // Must NOT be double-counted as an operating expense
          const CashWithdrawalRequest(
            id: 'w-sup',
            cashSessionId: 'cs-1',
            businessDate: '2026-11-26',
            amount: 300.0,
            reason: 'Pago proveedor carne',
            requestedByEmployeeId: 'e1',
            requestedByEmployeeName: 'Cajero',
            status: 'approved',
            source: 'supplier_payment',
            branchId: 'b1',
          ),
        ];

        final purchases = [
          SupplierPurchase(
            id: 'pur-1',
            supplierId: 'sup-1',
            supplierName: 'Carnicería',
            purchaseDate: DateTime(2026, 11, 26),
            businessDate: '2026-11-26',
            folio: 'F-001',
            folioNumber: 1,
            documentType: 'factura',
            status: 'partial',
            subtotal: 500.0,
            total: 500.0,
            paidTotal: 300.0,
            balance: 200.0,
            branchId: 'b1',
          ),
          // Cancelled purchase must be ignored
          SupplierPurchase(
            id: 'pur-cancelled',
            supplierId: 'sup-1',
            supplierName: 'Carnicería',
            purchaseDate: DateTime(2026, 11, 26),
            businessDate: '2026-11-26',
            folio: 'F-002',
            folioNumber: 2,
            documentType: 'factura',
            status: 'cancelled',
            subtotal: 999.0,
            total: 999.0,
            paidTotal: 0.0,
            balance: 0.0,
            branchId: 'b1',
          ),
        ];

        final supplierPayments = [
          SupplierPayment(
            id: 'sp-1',
            supplierId: 'sup-1',
            supplierName: 'Carnicería',
            purchaseId: 'pur-1',
            purchaseFolio: 'F-001',
            paymentDate: DateTime(2026, 11, 26),
            businessDate: '2026-11-26',
            amount: 300.0,
            method: 'partner_contribution',
            fundingSource: 'partner_contribution',
            fundingSourceName: 'Aportación de socios',
            partnerId: 'part-1',
            partnerName: 'Socio A',
            status: 'active',
            branchId: 'b1',
          ),
        ];

        final contributions = [
          // Linked to sp-1 -> MUST BE DEDUPLICATED
          PartnerContribution(
            id: 'pc-linked',
            restaurantId: 'r1',
            branchId: 'b1',
            partnerId: 'part-1',
            partnerName: 'Socio A',
            date: DateTime(2026, 11, 26),
            amount: 300.0,
            method: 'transfer',
            linkedSupplierPaymentId: 'sp-1',
            status: 'active',
          ),
          // Standalone contribution -> MUST BE ADDED
          PartnerContribution(
            id: 'pc-standalone',
            restaurantId: 'r1',
            branchId: 'b1',
            partnerId: 'part-2',
            partnerName: 'Socio B',
            date: DateTime(2026, 11, 26),
            amount: 100.0,
            method: 'transfer',
            status: 'active',
          ),
        ];

        final summary = FinancePeriodSummary.compute(
          orders: orders,
          itemsByOrder: itemsByOrder,
          paymentsByOrder: paymentsByOrder,
          cashSessions: cashSessions,
          withdrawals: withdrawals,
          purchases: purchases,
          supplierPayments: supplierPayments,
          partnerContributions: contributions,
          productProfitability: const [],
        );

        expect(summary.tipsTotal, 30.0);
        expect(summary.cardFeeAbsorbed, 6.0);
        expect(summary.cardCollected, 194.0); // 200 - 6
        expect(summary.realCollected, 194.0); // tips NOT included
        expect(summary.operatingExpensesPaid, 50.0); // sp-300 NOT double counted
        expect(summary.purchasesTotal, 500.0); // cancelled 999 ignored
        expect(summary.accountsPayableTotal, 200.0);
        // Partner contributions: 300 (sp-1) + 100 (pc-standalone), pc-linked deduplicated
        expect(summary.partnerContributionsTotal, 400.0);
        expect(summary.operatingCashFlow, 194.0 - 50.0 - 0.0);
        expect(summary.cashFlowWithPartners, 144.0 + 400.0 - 300.0);
      },
    );

    test(
      'Product profitability handles kg->g conversion, cooking yield, historical fallback, and missing recipe as null (never 0)',
      () {
        final costs = resolveIngredientCosts(
          periodPurchaseItems: const [
            SupplierPurchaseItem(
              id: 'pi-1',
              purchaseItemId: 'item-carne',
              purchaseItemName: 'Carne cruda',
              kitchenStockItemId: 'stock-carne',
              kitchenStockItemName: 'Carne Pastor',
              affectsKitchenStock: true,
              quantity: 2.0,
              unit: 'kg',
              unitCost: 150.0,
              total: 300.0,
              lineTotal: 300.0,
              lineTotalCents: 30000,
              unitCostCalculated: 150.0,
              calculationMode: 'exact',
            ),
          ],
          historicalPurchaseItems: const [
            SupplierPurchaseItem(
              id: 'pi-2',
              purchaseItemId: 'item-tortilla',
              purchaseItemName: 'Tortilla',
              kitchenStockItemId: 'stock-tortilla',
              kitchenStockItemName: 'Tortilla',
              affectsKitchenStock: true,
              quantity: 1.0,
              unit: 'kg',
              unitCost: 20.0,
              total: 20.0,
              lineTotal: 20.0,
              lineTotalCents: 2000,
              unitCostCalculated: 20.0,
              calculationMode: 'exact',
            ),
          ],
        );

        // 300 / 2000g = 0.15 / g
        expect(costs['stock-carne']!.costPerBaseUnit, closeTo(0.15, 0.0001));
        expect(costs['stock-carne']!.isHistoricalFallback, isFalse);
        // 20 / 1000g = 0.02 / g (historical fallback)
        expect(
          costs['stock-tortilla']!.costPerBaseUnit,
          closeTo(0.02, 0.0001),
        );
        expect(costs['stock-tortilla']!.isHistoricalFallback, isTrue);

        final recipes = [
          const TheoreticalProductRecipe(
            productId: 'prod-taco',
            productName: 'Taco Pastor',
            recipeStatus: 'complete',
            ingredients: [
              TheoreticalRecipeIngredient(
                stockItemId: 'stock-carne',
                stockItemName: 'Carne Pastor',
                quantity: 30.0,
                quantityType: 'grams',
                inputStage: 'cooked',
                unit: 'g',
                baseQuantity: 30.0,
              ),
              TheoreticalRecipeIngredient(
                stockItemId: 'stock-tortilla',
                stockItemName: 'Tortilla',
                quantity: 25.0,
                quantityType: 'grams',
                inputStage: 'ready_to_serve',
                unit: 'g',
                baseQuantity: 25.0,
              ),
            ],
          ),
        ];

        final yieldProfiles = [
          const IngredientYieldProfile(
            id: 'stock-carne',
            restaurantId: 'r1',
            stockItemId: 'stock-carne',
            stockItemName: 'Carne Pastor',
            cookingYieldPercent: 60.0,
            cookingYieldRate: 0.60,
            estimatedReductionPercent: 40.0,
            isEstimated: false,
            needsInternalValidation: false,
            sourceLabel: 'Test',
            active: true,
          ),
        ];

        final rows = buildProductProfitabilityReport(
          sales: const [
            ProductSaleAggregate(
              productId: 'prod-taco',
              productName: 'Taco Pastor',
              categoryName: 'Tacos',
              unitsSold: 10,
              netRevenue: 250.0,
            ),
            ProductSaleAggregate(
              productId: 'prod-agua',
              productName: 'Agua de Horchata',
              categoryName: 'Bebidas',
              unitsSold: 5,
              netRevenue: 150.0,
            ),
          ],
          recipes: recipes,
          yieldProfiles: yieldProfiles,
          ingredientCosts: costs,
        );

        final taco = rows.firstWhere((r) => r.productId == 'prod-taco');
        final agua = rows.firstWhere((r) => r.productId == 'prod-agua');

        // Carne raw needed: 30 / 0.60 = 50g * 0.15 = 7.50
        // Tortilla: 25g * 0.02 = 0.50 -> Unit cost = 8.00
        expect(taco.hasCost, isTrue);
        expect(taco.usesHistoricalCost, isTrue);
        expect(taco.theoreticalUnitCost, closeTo(8.0, 0.001));
        expect(taco.totalCost, closeTo(80.0, 0.01));
        expect(taco.estimatedGrossProfit, closeTo(170.0, 0.01));
        expect(taco.marginPercent, closeTo(68.0, 0.1));

        // Product without recipe MUST NOT have 0 cost!
        expect(agua.hasCost, isFalse);
        expect(agua.theoreticalUnitCost, isNull);
        expect(agua.totalCost, isNull);
      },
    );

    test('Break-even, efficiency ratios, and partner share proposal', () {
      final be = BreakEvenAnalysis.compute(
        horizon: BreakEvenHorizon.monthly,
        fixedCosts: 30000.0,
        variableCostRatio: 0.40,
        accumulatedSales: 25000.0,
        elapsedDays: 15,
        totalDaysInPeriod: 30,
      );
      expect(be.contributionMarginRatio, closeTo(0.60, 0.001));
      expect(be.breakEvenSales, closeTo(50000.0, 0.01));
      expect(be.gapToBreakEven, closeTo(25000.0, 0.01));
      expect(be.projectedEndSales, closeTo(50000.0, 0.01));
      expect(be.requiredDailySalesRemaining, closeTo(25000.0 / 15, 0.01));

      final partnerSummary = buildPartnerFinanceSummary(
        partners: const [
          Partner(id: 'p1', name: 'A', active: true, ownershipPercent: 60.0),
          Partner(id: 'p2', name: 'B', active: true, ownershipPercent: 40.0),
        ],
        supplierPayments: const [],
        contributions: const [],
        distributableBase: 10000.0,
      );
      expect(partnerSummary.proposals[0].proposedShareAmount, 6000.0);
      expect(partnerSummary.proposals[1].proposedShareAmount, 4000.0);

      final eff = buildEfficiencyComparisons(
        summary: const FinancePeriodSummary(
          grossSales: 1000,
          discounts: 0,
          employeeFreeMeals: 0,
          netSales: 1000,
          ordersCount: 10,
          cashCollected: 1000,
          cardCollected: 0,
          cardFeeAbsorbed: 0,
          platformCollected: 0,
          otherCollected: 0,
          realCollected: 1000,
          tipsTotal: 0,
          purchasesTotal: 400,
          estimatedCogs: 300,
          cogsCoveredRevenue: 1000,
          cogsMissingRevenue: 0,
          operatingExpensesPaid: 200,
          cashDrawerExpenses: 200,
          historicalExpenses: 0,
          payrollExpenses: 100,
          grossProfit: 700,
          operatingResultFlow: 400,
          operatingProfitAccounting: 500,
          profitMarginPercent: 50,
          accountsPayableTotal: 0,
          supplierPaidFromSales: 400,
          supplierPaidByPartners: 0,
          partnerContributionsTotal: 0,
          operatingCashFlow: 400,
          cashFlowWithPartners: 400,
          expensesByConcept: [],
          expensesByBranch: {},
        ),
        kitchenItems: const [
          KitchenSessionItem(
            id: 'k1',
            kitchenStockItemId: 's1',
            name: 'Carne',
            category: 'Carnes',
            unit: 'kg',
            previousRemainingQty: 0,
            todayInputQty: 10,
            additionalEntriesQty: 0,
            availableQty: 10,
            finalRemainingQty: 0,
            wasteQty: 1.0,
            usedQty: 10.0,
            usefulConsumedQty: 9.0,
            soldQty: 9.0,
            yieldQtyPerUnit: 1.0,
            notes: '',
          ),
        ],
        targetsByKey: const {'purchases_vs_sales': 35.0},
      );
      final purchasesRow = eff.firstWhere((e) => e.key == 'purchases_vs_sales');
      final mermaRow = eff.firstWhere((e) => e.key == 'merma_vs_consumption');
      expect(purchasesRow.actualPercent, closeTo(40.0, 0.01));
      expect(purchasesRow.isOverTarget, isTrue);
      expect(mermaRow.actualPercent, closeTo(10.0, 0.01));
    });

    test('BackofficePermissions grants Finance access to purchase/finance roles matching 1.0', () {
      const buyer = Employee(
        id: 'e-buy',
        name: 'Comprador',
        pin: '1111',
        active: true,
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
      final perms = BackofficePermissions(employee: buyer);
      expect(perms.canViewFinance, isTrue);
      expect(perms.canManagePartners, isTrue);
      expect(perms.canManageExpensePolicies, isFalse);
    });
  });
}
