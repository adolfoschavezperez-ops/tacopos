import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/backoffice_v2/auth/backoffice_permissions.dart';
import 'package:tacopos/backoffice_v2/auth/backoffice_session.dart';
import 'package:tacopos/backoffice_v2/core/adapters/sales_adapter.dart';
import 'package:tacopos/backoffice_v2/core/env/backoffice_env.dart';
import 'package:tacopos/backoffice_v2/navigation/backoffice_route.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/payment.dart';

Employee _buildEmployee({
  bool active = true,
  bool canViewAdmin = false,
  bool canManageCash = false,
  bool canViewPurchases = false,
  bool canManageEmployees = false,
}) {
  return Employee(
    id: 'emp_1',
    name: 'Test User',
    active: active,
    pin: '',
    canTakeOrders: false,
    canCharge: false,
    canViewKitchen: false,
    canViewAdmin: canViewAdmin,
    canManageProducts: false,
    canManageTables: false,
    canManagePlatforms: false,
    canManageEmployees: canManageEmployees,
    canManageCash: canManageCash,
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
    canViewPurchases: canViewPurchases,
  );
}

void main() {
  group('BackofficePermissions & Session Recovery', () {
    test('inactive employee has zero section access', () {
      final perms = BackofficePermissions(
        employee: _buildEmployee(active: false, canViewAdmin: true),
        isSuperAdmin: true,
      );
      expect(perms.isAuthenticated, isFalse);
      for (final section in BackofficeSection.values) {
        expect(perms.canViewSection(section), isFalse);
      }
    });

    test('purchase-only manager cannot access dashboard, sales, or employees', () {
      final perms = BackofficePermissions(
        employee: _buildEmployee(canViewPurchases: true),
      );
      expect(perms.canViewSection(BackofficeSection.purchases), isTrue);
      expect(perms.canViewSection(BackofficeSection.dashboard), isFalse);
      expect(perms.canViewSection(BackofficeSection.sales), isFalse);
      expect(perms.canViewSection(BackofficeSection.employees), isFalse);
    });

    test('session expiration preserves and consumes recovery notice', () {
      final config = EnvironmentGuard.resolveAndValidate(rawEnv: 'local');
      final session = BackofficeSession(config: config);
      session.signIn(
        employee: _buildEmployee(canViewAdmin: true),
        isSuperAdmin: true,
        restaurantId: 'rest_alpha',
        restaurantName: 'Alpha',
        branches: const [],
      );
      expect(session.isAuthenticated, isTrue);

      session.signOut(notice: 'Tu sesión expiró. Inicia sesión nuevamente.');
      expect(session.isAuthenticated, isFalse);
      expect(
        session.consumeNotice(),
        'Tu sesión expiró. Inicia sesión nuevamente.',
      );
      expect(session.consumeNotice(), isNull);
    });
  });

  group('Financial separation: monetary vs internal consumption', () {
    test('monetaryCollected excludes employee_consumption while totalCollected includes it', () {
      const cashOrder = PosOrder(
        id: 'o1',
        tableId: 't1',
        tableName: 'Mesa 1',
        status: 'paid',
        kitchenStatus: 'ready',
        paymentStatus: 'paid',
        total: 200,
        paidTotal: 200,
        pendingTotal: 0,
        personNames: {},
        orderType: 'dine_in',
        businessDate: '2026-11-26',
      );
      const internalOrder = PosOrder(
        id: 'o2',
        tableId: 't2',
        tableName: 'Mesa 2',
        status: 'paid',
        kitchenStatus: 'ready',
        paymentStatus: 'paid',
        total: 100,
        paidTotal: 100,
        pendingTotal: 0,
        personNames: {},
        orderType: 'dine_in',
        businessDate: '2026-11-26',
      );

      final summary = BackofficeSalesAdapter.buildCanonicalSummary(
        orders: const [cashOrder, internalOrder],
        itemsByOrder: {
          'o1': const [
            OrderItem(
              id: 'i1',
              personNumber: 1,
              personName: 'Cliente',
              productId: 'p1',
              productName: 'Tacos',
              category: 'Tacos',
              qty: 2,
              unitPrice: 100,
              total: 200,
              notes: '',
              sendToKitchen: true,
              kitchenStatus: 'ready',
              paymentStatus: 'paid',
            ),
          ],
          'o2': const [
            OrderItem(
              id: 'i2',
              personNumber: 1,
              personName: 'Empleado',
              productId: 'p1',
              productName: 'Tacos',
              category: 'Tacos',
              qty: 1,
              unitPrice: 100,
              total: 100,
              notes: '',
              sendToKitchen: true,
              kitchenStatus: 'ready',
              paymentStatus: 'paid',
            ),
          ],
        },
        paymentsByOrder: {
          'o1': const [
            Payment(
              id: 'pay1',
              orderId: 'o1',
              tableId: 't1',
              tableName: 'Mesa 1',
              type: 'cash',
              method: 'cash',
              baseAmount: 200,
              surchargeRate: 0,
              surchargeAmount: 0,
              chargedAmount: 200,
              appliedAmount: 200,
            ),
          ],
          'o2': const [
            Payment(
              id: 'pay2',
              orderId: 'o2',
              tableId: 't2',
              tableName: 'Mesa 2',
              type: 'employee_consumption',
              method: 'employee_consumption',
              baseAmount: 100,
              surchargeRate: 0,
              surchargeAmount: 0,
              chargedAmount: 100,
              appliedAmount: 100,
            ),
          ],
        },
      );

      expect(summary.monetaryCollected, 200.0);
      expect(summary.employeeConsumption, 100.0);
      expect(summary.totalCollected, 300.0);
    });

    test('commercial adapters translate technical enums cleanly', () {
      expect(
        BackofficeSalesAdapter.paymentMethodLabel('platform_paid'),
        'Pago por plataforma',
      );
      expect(BackofficeSalesAdapter.orderTypeLabel('takeout'), 'Para llevar');
      expect(BackofficeSalesAdapter.orderTypeLabel('dine_in'), 'Comedor');
    });
  });
}
