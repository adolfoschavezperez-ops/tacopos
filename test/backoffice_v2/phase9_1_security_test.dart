import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/backoffice_v2/auth/backoffice_permissions.dart';
import 'package:tacopos/backoffice_v2/core/cache/backoffice_cache_scope.dart';
import 'package:tacopos/models/employee.dart';

Employee _makeEmp({
  required String id,
  bool active = true,
  bool isSuperAdmin = false,
  bool canViewAdmin = false,
  bool canManageEmployees = false,
  bool canCancelOrders = false,
}) {
  return Employee(
    id: id,
    name: 'Test $id',
    pin: '',
    active: active,
    isSuperAdmin: isSuperAdmin,
    canTakeOrders: false,
    canCharge: false,
    canViewKitchen: false,
    canViewAdmin: canViewAdmin,
    canManageProducts: false,
    canManageTables: false,
    canManagePlatforms: false,
    canManageEmployees: canManageEmployees,
    canManageCash: false,
    canAuthorizeCashWithdrawals: false,
    canOpenKitchen: false,
    canCloseKitchen: false,
    canViewKitchenReports: false,
    canViewKitchenHourlySalesComparison: false,
    canManageKitchenStock: false,
    canCancelOrders: canCancelOrders,
    canCancelPayments: false,
    canCancelItems: false,
    canApproveKitchenCancellations: false,
    canViewLiveOperations: false,
    canControlLiveOperations: false,
  );
}

void main() {
  group('Phase 9.1 Security — P0-3 Cache Isolation & Stale Async Race', () {
    test('Cache keys isolate by user, restaurant, branch, permissions, and epoch within 60s', () {
      final scope = BackofficeCacheScope();
      var invalidations = 0;
      scope.registerInvalidator(() => invalidations++);

      scope.updateContext(
        userId: 'emp_a',
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        permissionsFingerprint: 'false|canViewAdmin',
      );
      final keyA = scope.buildScopedKey('finance', ['2026-11-01', '2026-11-27']);
      expect(invalidations, 1);

      // Consecutive user within 60s TTL gets a completely isolated key & triggers invalidation
      scope.updateContext(
        userId: 'emp_b',
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        permissionsFingerprint: 'false|canViewPurchases',
      );
      final keyB = scope.buildScopedKey('finance', ['2026-11-01', '2026-11-27']);
      expect(invalidations, 2);
      expect(keyA, isNot(equals(keyB)));

      // Branch change invalidates & isolates key
      scope.updateContext(
        userId: 'emp_b',
        restaurantId: 'rest_alpha',
        branchId: 'suc_norte',
        permissionsFingerprint: 'false|canViewPurchases',
      );
      final keyB2 = scope.buildScopedKey('finance', ['2026-11-01', '2026-11-27']);
      expect(invalidations, 3);
      expect(keyB2, isNot(equals(keyB)));

      // Permission change invalidates & isolates key
      scope.updateContext(
        userId: 'emp_b',
        restaurantId: 'rest_alpha',
        branchId: 'suc_norte',
        permissionsFingerprint: 'false|canViewAdmin,canViewPurchases',
      );
      final keyB3 = scope.buildScopedKey('finance', ['2026-11-01', '2026-11-27']);
      expect(invalidations, 4);
      expect(keyB3, isNot(equals(keyB2)));
    });

    test('In-flight async response from prior session cannot populate cache after resetSession()', () async {
      final scope = BackofficeCacheScope();
      final cache = <String, String>{};
      scope.registerInvalidator(cache.clear);

      scope.updateContext(
        userId: 'emp_old',
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        permissionsFingerprint: 'false|canViewAdmin',
      );
      final reqEpoch = scope.epoch;
      final reqKey = scope.buildScopedKey('dashboard', ['2026-11-27']);

      // Simulate async fetch in flight while session is revoked/signed out
      final pendingFuture = Future<String>.delayed(
        const Duration(milliseconds: 25),
        () => 'sensitive_old_session_data',
      );

      scope.resetSession();
      scope.updateContext(
        userId: 'emp_new',
        restaurantId: 'rest_alpha',
        branchId: 'suc_centro',
        permissionsFingerprint: 'false|canViewPurchases',
      );

      final result = await pendingFuture;
      if (reqEpoch == scope.epoch) {
        cache[reqKey] = result;
      }

      expect(cache, isEmpty);
      expect(scope.epoch, isNot(equals(reqEpoch)));
    });
  });

  group('Phase 9.1 Security — P0-2 28 Permissions & P1-8 Revocation', () {
    test('Employee model exposes all 28 individual permission keys', () {
      final emp = _makeEmp(id: 'emp_1', canViewAdmin: true);
      final map = emp.currentPermissionsMap;
      expect(map.length, 28);
      expect(map.keys, containsAll([
        'canTakeOrders',
        'canCharge',
        'canViewKitchen',
        'canViewAdmin',
        'canManageProducts',
        'canManageTables',
        'canManagePlatforms',
        'canManageEmployees',
        'canManageCash',
        'canAuthorizeCashWithdrawals',
        'canOpenKitchen',
        'canCloseKitchen',
        'canViewKitchenReports',
        'canViewKitchenHourlySalesComparison',
        'canManageKitchenStock',
        'canCancelOrders',
        'canCancelPayments',
        'canCancelItems',
        'canApproveKitchenCancellations',
        'canViewLiveOperations',
        'canControlLiveOperations',
        'canViewPurchases',
        'canManageSuppliers',
        'canRegisterPurchases',
        'canPaySuppliers',
        'canCancelSupplierPayments',
        'canViewAccountsPayable',
        'canViewPurchaseReports',
      ]));
    });

    test('Deactivated employee loses all BackofficePermissions even if isSuperAdmin was true', () {
      final inactiveAdmin = _makeEmp(
        id: 'emp_revoked',
        active: false,
        isSuperAdmin: true,
        canViewAdmin: true,
        canManageEmployees: true,
        canCancelOrders: true,
      );
      final perms = BackofficePermissions(
        employee: inactiveAdmin,
        isSuperAdmin: true,
      );
      expect(perms.isAuthenticated, isFalse);
      expect(perms.canViewDashboard, isFalse);
      expect(perms.canManageEmployees, isFalse);
      expect(perms.canCancelOrders, isFalse);
    });
  });
}
