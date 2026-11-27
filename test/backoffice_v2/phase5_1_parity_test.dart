import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/backoffice_v2/auth/backoffice_permissions.dart';
import 'package:tacopos/backoffice_v2/features/purchases/purchases_analytics.dart';
import 'package:tacopos/core/orders/backoffice_sales_cancellation.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/models/purchase_models.dart';

void main() {
  group('Phase 5.1 Parity 1.0 vs 2.0: Sales Cancellation & Concurrency', () {
    test(
      'BackofficeCancellationGuard prevents simultaneous duplicate cancellations and enforces payment totals',
      () {
        final guard = BackofficeCancellationGuard();
        expect(guard.tryStart(), isTrue);
        expect(guard.tryStart(), isFalse); // Concurrent attempt blocked
        guard.release();
        expect(guard.tryStart(), isTrue);

        // Order with active payments cannot be cancelled directly
        expect(canCancelBackofficeSale(150.0), isFalse);
        expect(canCancelBackofficeSale(0.0), isTrue);

        // Recalculation after partial payment cancellation matches 1.0
        final partial = deriveCustomerPaymentCancellationTotals(
          orderNetTotal: 500,
          activePaymentAmounts: const [200],
        );
        expect(partial.paidTotal, 200);
        expect(partial.pendingTotal, 300);
        expect(partial.paymentStatus, 'partial');

        final noneLeft = deriveCustomerPaymentCancellationTotals(
          orderNetTotal: 500,
          activePaymentAmounts: const [],
        );
        expect(noneLeft.paidTotal, 0);
        expect(noneLeft.pendingTotal, 500);
        expect(noneLeft.paymentStatus, 'pending');
      },
    );
  });

  group('Phase 5.1 Parity 1.0 vs 2.0: Statement & Kardex', () {
    test(
      'buildSupplierStatement computes running balance accurately and excludes cancelled docs',
      () {
        final purchases = [
          SupplierPurchase(
            id: 'sp_1',
            supplierId: 'sup_1',
            supplierName: 'Prov 1',
            purchaseDate: DateTime(2026, 11, 10),
            folio: 'C-0001',
            documentType: 'invoice',
            status: 'partial',
            subtotal: 1000,
            total: 1000,
            paidTotal: 400,
            balance: 600,
          ),
          SupplierPurchase(
            id: 'sp_cancel',
            supplierId: 'sup_1',
            supplierName: 'Prov 1',
            purchaseDate: DateTime(2026, 11, 12),
            folio: 'C-0002',
            documentType: 'note',
            status: 'cancelled',
            subtotal: 500,
            total: 500,
            paidTotal: 0,
            balance: 0,
          ),
        ];

        final payments = [
          SupplierPayment(
            id: 'pay_1',
            supplierId: 'sup_1',
            supplierName: 'Prov 1',
            purchaseId: 'sp_1',
            purchaseFolio: 'C-0001',
            paymentDate: DateTime(2026, 11, 15),
            amount: 400,
            method: 'partner_contribution',
            fundingSource: 'partner_contribution',
            fundingSourceName: 'Aportación de socios',
            status: 'active',
          ),
          SupplierPayment(
            id: 'pay_cancel',
            supplierId: 'sup_1',
            supplierName: 'Prov 1',
            purchaseId: 'sp_1',
            purchaseFolio: 'C-0001',
            paymentDate: DateTime(2026, 11, 16),
            amount: 200,
            method: 'cash',
            status: 'cancelled',
          ),
        ];

        final statement = PurchasesAnalytics.buildSupplierStatement(
          supplierId: 'sup_1',
          purchases: purchases,
          payments: payments,
          openingBalance: 100,
        );

        expect(statement.totalCharges, 1000);
        expect(statement.totalPayments, 400);
        expect(statement.closingBalance, 700); // 100 + 1000 - 400
        expect(statement.rows.length, 2);
        expect(statement.rows[0].balance, 1100);
        expect(statement.rows[1].balance, 700);
      },
    );

    test('buildKardex excludes cancelled purchases and preserves unit costs', () {
      final purchases = [
        SupplierPurchase(
          id: 'sp_1',
          supplierId: 'sup_1',
          supplierName: 'Carnicería',
          purchaseDate: DateTime(2026, 11, 20),
          businessDate: '2026-11-20',
          folio: 'C-0001',
          documentType: 'invoice',
          status: 'paid',
          subtotal: 1180,
          total: 1180,
          paidTotal: 1180,
          balance: 0,
        ),
        SupplierPurchase(
          id: 'sp_cancel',
          supplierId: 'sup_1',
          supplierName: 'Carnicería',
          purchaseDate: DateTime(2026, 11, 21),
          businessDate: '2026-11-21',
          folio: 'C-0002',
          documentType: 'invoice',
          status: 'cancelled',
          subtotal: 500,
          total: 500,
          paidTotal: 0,
          balance: 0,
        ),
      ];
      final entries = PurchasesAnalytics.buildKardex(
        purchases: purchases,
        itemsByPurchase: const {
          'sp_1': [
            SupplierPurchaseItem(
              id: 'l1',
              purchaseItemId: 'pi_1',
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
          ],
          'sp_cancel': [
            SupplierPurchaseItem(
              id: 'l2',
              purchaseItemId: 'pi_1',
              purchaseItemName: 'Carne al Pastor',
              quantity: 5,
              unit: 'kg',
              unitCost: 100,
              total: 500,
              lineTotal: 500,
              lineTotalCents: 50000,
              unitCostCalculated: 100,
              calculationMode: 'line_total',
            ),
          ],
        },
      );
      expect(entries.length, 1);
      expect(entries.first.quantity, 10);
      expect(entries.first.unitCost, 118);
    });
  });

  group('Phase 5.1 Granular Cancellation Permissions', () {
    test('checks independent cancellation permissions', () {
      const restricted = Employee(
        id: 'e1',
        name: 'Operador',
        active: true,
        pin: '0000',
        canTakeOrders: true,
        canCharge: true,
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
        canCancelSupplierPayments: true,
      );
      const perms = BackofficePermissions(employee: restricted);
      expect(perms.canCancelOrders, isFalse);
      expect(perms.canCancelPayments, isFalse);
      expect(perms.canCancelSupplierPayments, isTrue);
    });
  });
}
