import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/backoffice_v2/auth/backoffice_permissions.dart';
import 'package:tacopos/backoffice_v2/features/cash/cash_repository.dart';
import 'package:tacopos/backoffice_v2/navigation/backoffice_route.dart';
import 'package:tacopos/core/orders/employee_benefit_checkout.dart';
import 'package:tacopos/models/cash_session.dart';
import 'package:tacopos/models/cash_withdrawal_request.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/payment.dart';

void main() {
  group('Phase 4 CashReconciliationSummary', () {
    test(
      'reconciles opening float, cash, card, platforms, withdrawals, tips, discounts, employee meal, independent employee consumption, cancellations, and shortage without mixing non-monetary concepts',
      () {
        final session = CashSession(
          id: 'cs_1',
          businessDate: '2026-11-26',
          status: 'closed',
          openingCashAmount: 1500,
          openedByEmployeeId: 'emp_1',
          openedByEmployeeName: 'Laura',
          countedCashAmount: 2055,
          terminalReportedAmount: 450,
          expectedCashAmount: 2100,
          expectedCardChargedAmount: 450,
          expectedCardBaseAmount: 450,
          expectedCardSurchargeAmount: 0,
          expectedCardFeeAbsorbedAmount: 16.2,
          expectedPlatformAmount: 320,
          expectedEmployeeConsumptionAmount: 180,
          totalExpectedRealMoney: 2870,
          totalCountedRealMoney: 2825,
          cashDifference: -45,
          cardDifference: 0,
          netDifference: -45,
          shortageAmount: 45,
          overAmount: 0,
          approvedWithdrawalsTotal: 200,
          pendingWithdrawalsTotal: 100,
          withdrawalRequestCount: 2,
          notes: '',
          branchId: 'suc_centro',
          branchName: 'Centro',
        );

        final orders = [
          PosOrder(
            id: 'ord_cash',
            tableId: 'mesa_1',
            tableName: 'Mesa 1',
            status: 'paid',
            kitchenStatus: 'ready',
            paymentStatus: 'paid',
            total: 800,
            paidTotal: 800,
            pendingTotal: 0,
            personNames: const {1: 'Cliente 1'},
            orderType: 'dine_in',
            grossSubtotal: 860,
            netTotal: 800,
            explicitDiscount: 60,
            discountApplied: true,
            businessDate: '2026-11-26',
            cashSessionId: 'cs_1',
          ),
          PosOrder(
            id: 'ord_card',
            tableId: 'mesa_2',
            tableName: 'Mesa 2',
            status: 'paid',
            kitchenStatus: 'ready',
            paymentStatus: 'paid',
            total: 450,
            paidTotal: 450,
            pendingTotal: 0,
            personNames: const {1: 'Cliente 2'},
            orderType: 'dine_in',
            grossSubtotal: 450,
            netTotal: 450,
            businessDate: '2026-11-26',
            cashSessionId: 'cs_1',
          ),
          PosOrder(
            id: 'ord_plat',
            tableId: 'takeout',
            tableName: '',
            status: 'paid',
            kitchenStatus: 'ready',
            paymentStatus: 'paid',
            total: 320,
            paidTotal: 320,
            pendingTotal: 0,
            personNames: const {1: 'Uber'},
            orderType: 'takeout',
            platformName: 'Uber Eats',
            grossSubtotal: 320,
            netTotal: 320,
            businessDate: '2026-11-26',
            cashSessionId: 'cs_1',
          ),
          PosOrder(
            id: 'ord_emp_meal',
            tableId: 'mesa_3',
            tableName: 'Mesa 3',
            status: 'paid',
            kitchenStatus: 'ready',
            paymentStatus: 'paid',
            total: 0,
            paidTotal: 0,
            pendingTotal: 0,
            personNames: const {1: 'Comida Empleado'},
            orderType: 'dine_in',
            grossSubtotal: 120,
            netTotal: 0,
            explicitDiscount: 120,
            discountApplied: true,
            discountType: 'employee_free_meal',
            businessDate: '2026-11-26',
            cashSessionId: 'cs_1',
          ),
          PosOrder(
            id: 'ord_emp_cons',
            tableId: 'mesa_4',
            tableName: 'Mesa 4',
            status: 'paid',
            kitchenStatus: 'ready',
            paymentStatus: 'paid',
            total: 180,
            paidTotal: 180,
            pendingTotal: 0,
            personNames: const {1: 'Consumo Independiente'},
            orderType: 'dine_in',
            grossSubtotal: 180,
            netTotal: 180,
            businessDate: '2026-11-26',
            cashSessionId: 'cs_1',
          ),
          PosOrder(
            id: 'ord_cancel',
            tableId: 'mesa_5',
            tableName: 'Mesa 5',
            status: 'cancelled',
            kitchenStatus: 'cancelled',
            paymentStatus: 'cancelled',
            total: 250,
            paidTotal: 0,
            pendingTotal: 0,
            personNames: const {1: 'Cancelado'},
            orderType: 'dine_in',
            businessDate: '2026-11-26',
            cashSessionId: 'cs_1',
          ),
        ];

        final payments = [
          Payment(
            id: 'p_cash',
            orderId: 'ord_cash',
            tableId: 'mesa_1',
            tableName: 'Mesa 1',
            type: 'cash',
            method: 'cash',
            baseAmount: 800,
            surchargeRate: 0,
            surchargeAmount: 0,
            chargedAmount: 800,
            appliedAmount: 800,
            cashSessionId: 'cs_1',
            businessDate: '2026-11-26',
          ),
          Payment(
            id: 'p_card',
            orderId: 'ord_card',
            tableId: 'mesa_2',
            tableName: 'Mesa 2',
            type: 'card',
            method: 'card',
            baseAmount: 450,
            surchargeRate: 0,
            surchargeAmount: 0,
            chargedAmount: 450,
            appliedAmount: 450,
            tipAmount: 45,
            cashSessionId: 'cs_1',
            businessDate: '2026-11-26',
          ),
          Payment(
            id: 'p_plat',
            orderId: 'ord_plat',
            tableId: 'takeout',
            tableName: '',
            type: 'platform_paid',
            method: 'platform_paid',
            baseAmount: 320,
            surchargeRate: 0,
            surchargeAmount: 0,
            chargedAmount: 320,
            appliedAmount: 320,
            cashSessionId: 'cs_1',
            businessDate: '2026-11-26',
          ),
          Payment(
            id: 'p_emp_cons',
            orderId: 'ord_emp_cons',
            tableId: 'mesa_4',
            tableName: 'Mesa 4',
            type: 'employee_consumption',
            method: 'employee_consumption',
            baseAmount: 180,
            surchargeRate: 0,
            surchargeAmount: 0,
            chargedAmount: 180,
            appliedAmount: 180,
            appliedDiscountType: 'employee_independent',
            cashSessionId: 'cs_1',
            businessDate: '2026-11-26',
          ),
          Payment(
            id: 'p_emp_meal',
            orderId: 'ord_emp_meal',
            tableId: 'mesa_3',
            tableName: 'Mesa 3',
            type: 'employee_consumption',
            method: 'employee_consumption',
            baseAmount: 120,
            surchargeRate: 0,
            surchargeAmount: 0,
            chargedAmount: 0,
            appliedAmount: 0,
            discountApplied: true,
            discountSource: 'employee_free_meal',
            appliedDiscountType: employeeDailyMealDiscountType,
            discountAmount: 120,
            cashSessionId: 'cs_1',
            businessDate: '2026-11-26',
          ),
          Payment(
            id: 'p_cancelled_ignored',
            orderId: 'ord_cancel',
            tableId: 'mesa_5',
            tableName: 'Mesa 5',
            type: 'cash',
            method: 'cash',
            baseAmount: 250,
            surchargeRate: 0,
            surchargeAmount: 0,
            chargedAmount: 250,
            status: 'cancelled',
            cashSessionId: 'cs_1',
            businessDate: '2026-11-26',
          ),
        ];

        final withdrawals = [
          const CashWithdrawalRequest(
            id: 'w_1',
            cashSessionId: 'cs_1',
            businessDate: '2026-11-26',
            amount: 200,
            reason: 'Compra hielo',
            requestedByEmployeeId: 'emp_2',
            requestedByEmployeeName: 'Carlos',
            status: 'approved',
            branchId: 'suc_centro',
            branchName: 'Centro',
          ),
          const CashWithdrawalRequest(
            id: 'w_2',
            cashSessionId: 'cs_1',
            businessDate: '2026-11-26',
            amount: 100,
            reason: 'Pendiente',
            requestedByEmployeeId: 'emp_2',
            requestedByEmployeeName: 'Carlos',
            status: 'pending',
            branchId: 'suc_centro',
            branchName: 'Centro',
          ),
        ];

        final summary = CashReconciliationSummary.compute(
          session: session,
          orders: orders,
          payments: payments,
          withdrawals: withdrawals,
        );

        expect(summary.openingCashAmount, 1500);
        expect(summary.cashCollected, 800);
        expect(summary.cardCollected, 450);
        expect(summary.platformCollected, 320);
        expect(summary.tipsTotal, 45);
        expect(summary.approvedWithdrawalsTotal, 200);
        expect(summary.pendingWithdrawalsTotal, 100);
        // 1500 + 800 - 200 = 2100 (employee consumption & cancelled NOT mixed in)
        expect(summary.expectedCashInDrawer, 2100);
        expect(summary.countedCashAmount, 2055);
        expect(summary.cashDifference, -45);
        expect(summary.shortageAmount, 45);
        expect(summary.overAmount, 0);
        expect(summary.employeeConsumptionTotal, 180);
        expect(summary.employeeFreeMealTotal, 120);
        expect(summary.cancelledOrdersCount, 1);
        expect(summary.cancelledAmount, 250);
      },
    );

    test('computes overage correctly for open/closing session', () {
      const session = CashSession(
        id: 'cs_2',
        businessDate: '2026-11-26',
        status: 'open',
        openingCashAmount: 1000,
        openedByEmployeeId: 'emp_1',
        openedByEmployeeName: 'Laura',
        countedCashAmount: 2530,
        terminalReportedAmount: 0,
        expectedCashAmount: 1500,
        expectedCardChargedAmount: 0,
        expectedCardBaseAmount: 0,
        expectedCardSurchargeAmount: 0,
        expectedCardFeeAbsorbedAmount: 0,
        expectedPlatformAmount: 0,
        expectedEmployeeConsumptionAmount: 0,
        totalExpectedRealMoney: 2500,
        totalCountedRealMoney: 2530,
        cashDifference: 30,
        cardDifference: 0,
        netDifference: 30,
        shortageAmount: 0,
        overAmount: 30,
        approvedWithdrawalsTotal: 0,
        pendingWithdrawalsTotal: 0,
        withdrawalRequestCount: 0,
        notes: '',
        branchId: 'suc_norte',
        branchName: 'Norte',
      );
      final summary = CashReconciliationSummary.compute(
        session: session,
        orders: const [],
        payments: const [],
        withdrawals: const [],
      );
      expect(summary.expectedCashInDrawer, 2500);
      expect(summary.cashDifference, 30);
      expect(summary.overAmount, 30);
      expect(summary.shortageAmount, 0);
    });
  });

  group('Phase 4 Permissions', () {
    Employee makeEmployee({
      required String id,
      required String name,
      bool canManageCash = false,
      bool canManageKitchenStock = false,
    }) {
      return Employee(
        id: id,
        name: name,
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
        canManageCash: canManageCash,
        canAuthorizeCashWithdrawals: false,
        canOpenKitchen: false,
        canCloseKitchen: false,
        canViewKitchenReports: false,
        canViewKitchenHourlySalesComparison: false,
        canManageKitchenStock: canManageKitchenStock,
        canCancelOrders: false,
        canCancelPayments: false,
        canCancelItems: false,
        canApproveKitchenCancellations: false,
        canViewLiveOperations: false,
        canControlLiveOperations: false,
      );
    }

    test('enforces cash, authorizations, and inventory permissions', () {
      final cashOnlyEmployee = makeEmployee(
        id: 'e1',
        name: 'Cajero',
        canManageCash: true,
      );
      final perms = BackofficePermissions(employee: cashOnlyEmployee);
      expect(perms.canViewSection(BackofficeSection.cash), isTrue);
      expect(perms.canViewSection(BackofficeSection.authorizations), isFalse);
      expect(perms.canViewSection(BackofficeSection.inventory), isFalse);

      final kitchenEmployee = makeEmployee(
        id: 'e2',
        name: 'Cocina',
        canManageKitchenStock: true,
      );
      final kitchenPerms = BackofficePermissions(employee: kitchenEmployee);
      expect(kitchenPerms.canViewSection(BackofficeSection.inventory), isTrue);
      expect(kitchenPerms.canViewSection(BackofficeSection.cash), isFalse);
    });
  });
}
