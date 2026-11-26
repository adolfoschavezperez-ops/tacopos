import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tacopos/models/branch.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/services/app_session.dart';
import 'package:tacopos/services/device_registry_service.dart';
import 'package:tacopos/services/operational_employee_session_service.dart';
import 'package:tacopos/services/operational_employee_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemorySessionStore store;
  late Employee employee;

  setUp(() {
    store = _MemorySessionStore();
    employee = _employee();
    AppSession.employeeSessionStoreForTesting = store;
    AppSession.disablePresenceForTesting = true;
  });

  tearDown(() async {
    await AppSession.instance.signOut(reason: 'test_cleanup');
    AppSession.disablePresenceForTesting = false;
  });

  test('restore validates and restores current employee and branch', () async {
    await store.write(_identity());
    final service = OperationalEmployeeSessionService(
      store: store,
      isAuthenticated: () => true,
      resolver: (_) async => ResolvedOperationalEmployeeSession(
        employee: employee,
        branches: const [Branch.defaultBranch],
        selectedBranch: Branch.defaultBranch,
      ),
      deviceValidator: (_) async {},
    );

    final result = await service.restore();

    expect(result.status, OperationalSessionRestoreStatus.restored);
    expect(AppSession.instance.employee?.id, 'waiter_a');
    expect(AppSession.instance.currentBranchId, 'aviacion');
    expect(store.identity?.employeeId, 'waiter_a');
    expect(store.identity?.branchId, 'aviacion');
  });

  test('revoked employee or branch clears persisted identity', () async {
    await store.write(_identity());
    final service = OperationalEmployeeSessionService(
      store: store,
      isAuthenticated: () => true,
      resolver: (_) async =>
          throw const OperationalEmployeeSessionRevoked('access revoked'),
    );

    final result = await service.restore();

    expect(result.status, OperationalSessionRestoreStatus.revoked);
    expect(result.message, 'access revoked');
    expect(store.identity, isNull);
    expect(AppSession.instance.isLoggedIn, isFalse);
  });

  test(
    'transient Firestore failure retains identity for automatic recovery',
    () async {
      await store.write(_identity());
      final service = OperationalEmployeeSessionService(
        store: store,
        isAuthenticated: () => true,
        resolver: (_) async => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        ),
      );

      final result = await service.restore();

      expect(
        result.status,
        OperationalSessionRestoreStatus.waitingForValidation,
      );
      expect(store.identity?.employeeId, 'waiter_a');
      expect(AppSession.instance.isLoggedIn, isFalse);
    },
  );

  test('Firebase authentication not ready retains identity', () async {
    await store.write(_identity());
    var resolverCalled = false;
    final service = OperationalEmployeeSessionService(
      store: store,
      isAuthenticated: () => false,
      resolver: (_) async {
        resolverCalled = true;
        return null;
      },
    );

    final result = await service.restore();

    expect(result.status, OperationalSessionRestoreStatus.waitingForValidation);
    expect(resolverCalled, isFalse);
    expect(store.identity?.employeeId, 'waiter_a');
  });

  test(
    'explicit logout clears employee and branch identity without PIN',
    () async {
      await store.write(_identity());
      await AppSession.instance.signOut(reason: 'user_requested');

      expect(store.identity, isNull);
      expect(AppSession.instance.isLoggedIn, isFalse);
    },
  );

  test(
    'resume revalidation revokes employee after server access revocation',
    () async {
      await store.write(_identity());
      AppSession.instance.signIn(
        employee,
        branches: const [Branch.defaultBranch],
      );
      final service = OperationalEmployeeSessionService(
        store: store,
        isAuthenticated: () => true,
        resolver: (_) async =>
            throw const OperationalEmployeeSessionRevoked('access revoked'),
        deviceValidator: (_) async {},
      );

      final result = await service.revalidateCurrentSession();

      expect(result.status, OperationalSessionRestoreStatus.revoked);
      expect(AppSession.instance.isLoggedIn, isFalse);
      expect(store.identity, isNull);
    },
  );

  test(
    'resume revalidation keeps session on transient server failure',
    () async {
      await store.write(_identity());
      AppSession.instance.signIn(
        employee,
        branches: const [Branch.defaultBranch],
      );
      final service = OperationalEmployeeSessionService(
        store: store,
        isAuthenticated: () => true,
        resolver: (_) async => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        ),
        deviceValidator: (_) async {},
      );

      final result = await service.revalidateCurrentSession();

      expect(
        result.status,
        OperationalSessionRestoreStatus.waitingForValidation,
      );
      expect(AppSession.instance.isLoggedIn, isTrue);
      expect(store.identity?.employeeId, 'waiter_a');
    },
  );
  test(
    'unauthenticated Firestore response does not clear operator session',
    () async {
      await store.write(_identity());
      AppSession.instance.signIn(
        employee,
        branches: const [Branch.defaultBranch],
      );
      final service = OperationalEmployeeSessionService(
        store: store,
        isAuthenticated: () => true,
        resolver: (_) async => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unauthenticated',
        ),
        authRevocationCheck: () async => false,
        deviceValidator: (_) async {},
      );

      final result = await service.revalidateCurrentSession();

      expect(
        result.status,
        OperationalSessionRestoreStatus.waitingForValidation,
      );
      expect(AppSession.instance.employee?.id, 'waiter_a');
      expect(store.identity?.employeeId, 'waiter_a');
    },
  );

  test(
    'confirmed Firebase Auth revocation clears the active session',
    () async {
      await store.write(_identity());
      AppSession.instance.signIn(
        employee,
        branches: const [Branch.defaultBranch],
      );
      final service = OperationalEmployeeSessionService(
        store: store,
        isAuthenticated: () => true,
        resolver: (_) async => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unauthenticated',
        ),
        authRevocationCheck: () async => true,
        deviceValidator: (_) async {},
      );

      final result = await service.revalidateCurrentSession();

      expect(result.status, OperationalSessionRestoreStatus.revoked);
      expect(AppSession.instance.isLoggedIn, isFalse);
      expect(store.identity, isNull);
    },
  );

  test(
    'late validation cannot restore the old branch after branch change',
    () async {
      const branchB = Branch(
        id: 'sucursal_b',
        name: 'Sucursal B',
        normalizedName: 'sucursal_b',
        active: true,
        sortOrder: 2,
      );
      await store.write(_identity());
      AppSession.instance.signIn(
        employee,
        branches: const [Branch.defaultBranch, branchB],
        initialBranch: Branch.defaultBranch,
      );
      final validation = Completer<ResolvedOperationalEmployeeSession?>();
      final service = OperationalEmployeeSessionService(
        store: store,
        isAuthenticated: () => true,
        resolver: (_) => validation.future,
        deviceValidator: (_) async {},
      );

      final pending = service.revalidateCurrentSession();
      await store.write(
        const OperationalEmployeeSessionIdentity(
          employeeId: 'waiter_a',
          restaurantId: 'main_restaurant',
          branchId: 'sucursal_b',
        ),
      );
      AppSession.instance.selectBranch(branchB);
      validation.complete(
        ResolvedOperationalEmployeeSession(
          employee: employee,
          branches: const [Branch.defaultBranch, branchB],
          selectedBranch: Branch.defaultBranch,
        ),
      );

      final result = await pending;

      expect(result.status, OperationalSessionRestoreStatus.restored);
      expect(AppSession.instance.currentBranchId, 'sucursal_b');
      expect(AppSession.instance.isLoggedIn, isTrue);
      expect(store.identity?.branchId, 'sucursal_b');
    },
  );

  test('inactive device revokes and clears the operational session', () async {
    await store.write(_identity());
    AppSession.instance.signIn(
      employee,
      branches: const [Branch.defaultBranch],
    );
    final service = OperationalEmployeeSessionService(
      store: store,
      isAuthenticated: () => true,
      resolver: (_) async => ResolvedOperationalEmployeeSession(
        employee: employee,
        branches: const [Branch.defaultBranch],
        selectedBranch: Branch.defaultBranch,
      ),
      deviceValidator: (_) async => throw const DeviceRegistryException(
        'device-inactive',
        'Dispositivo inactivo',
      ),
    );

    final result = await service.revalidateCurrentSession();

    expect(result.status, OperationalSessionRestoreStatus.revoked);
    expect(AppSession.instance.isLoggedIn, isFalse);
    expect(store.identity, isNull);
  });
  test(
    'server permission revocation refreshes permissions without stale grants',
    () async {
      await store.write(_identity());
      AppSession.instance.signIn(
        employee,
        branches: const [Branch.defaultBranch],
      );
      final revisedEmployee = Employee(
        id: employee.id,
        name: employee.name,
        active: true,
        pin: employee.pin,
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
        defaultRestaurantId: employee.defaultRestaurantId,
        defaultBranchId: employee.defaultBranchId,
      );
      final service = OperationalEmployeeSessionService(
        store: store,
        isAuthenticated: () => true,
        resolver: (_) async => ResolvedOperationalEmployeeSession(
          employee: revisedEmployee,
          branches: const [Branch.defaultBranch],
          selectedBranch: Branch.defaultBranch,
        ),
        deviceValidator: (_) async {},
      );

      final result = await service.revalidateCurrentSession();

      expect(result.status, OperationalSessionRestoreStatus.restored);
      expect(AppSession.instance.isLoggedIn, isTrue);
      expect(AppSession.instance.employee?.canTakeOrders, isFalse);
      expect(AppSession.instance.employee?.canCharge, isFalse);
    },
  );
}

OperationalEmployeeSessionIdentity _identity() =>
    const OperationalEmployeeSessionIdentity(
      employeeId: 'waiter_a',
      restaurantId: 'main_restaurant',
      branchId: 'aviacion',
    );

Employee _employee() => const Employee(
  id: 'waiter_a',
  name: 'Mesero A',
  active: true,
  pin: 'test-only-not-persisted',
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
  defaultRestaurantId: 'main_restaurant',
  defaultBranchId: 'aviacion',
);

class _MemorySessionStore implements OperationalEmployeeSessionStore {
  OperationalEmployeeSessionIdentity? identity;

  @override
  Future<OperationalEmployeeSessionIdentity?> read() async => identity;

  @override
  Future<void> write(OperationalEmployeeSessionIdentity value) async {
    identity = value;
  }

  @override
  Future<void> clear() async {
    identity = null;
  }
}
