import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/backoffice_v2/auth/backoffice_permissions.dart';
import 'package:tacopos/backoffice_v2/auth/backoffice_session.dart';
import 'package:tacopos/backoffice_v2/core/env/backoffice_env.dart';
import 'package:tacopos/backoffice_v2/core/env/firebase_options_dev.dart';
import 'package:tacopos/backoffice_v2/features/settings/settings_repository.dart';
import 'package:tacopos/models/branch.dart';
import 'package:tacopos/models/employee.dart';

Employee _emp({
  String id = 'e1',
  bool active = true,
  bool isSuperAdmin = false,
  bool canManageEmployees = false,
  bool canManageProducts = false,
  bool canManageTables = false,
  bool canManagePlatforms = false,
  bool canViewAdmin = false,
}) {
  return Employee(
    id: id,
    name: 'Test $id',
    active: active,
    pin: '',
    isSuperAdmin: isSuperAdmin,
    canTakeOrders: false,
    canCharge: false,
    canViewKitchen: false,
    canViewAdmin: canViewAdmin,
    canManageProducts: canManageProducts,
    canManageTables: canManageTables,
    canManagePlatforms: canManagePlatforms,
    canManageEmployees: canManageEmployees,
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
  );
}

void main() {
  group('Phase 8 — Security, Session Isolation & Document Compatibility', () {
    test('BackofficeSession clears branch/employee/restaurant on signOut and isolates permissions', () {
      final cfg = BackofficeConfig(
        env: BackofficeEnv.dev,
        firebaseOptions: BackofficeDevFirebaseOptions.web,
        useEmulators: false,
        emulatorHost: 'localhost',
        authEmulatorPort: 9099,
        firestoreEmulatorPort: 8080,
        functionsEmulatorPort: 5001,
        functionsRegion: 'us-central1',
        defaultRestaurantId: 'rest_alpha',
      );
      final session = BackofficeSession(config: cfg);
      session.signIn(
        employee: _emp(id: 'emp-mgr', canManageProducts: true),
        isSuperAdmin: false,
        restaurantId: 'rest_alpha',
        restaurantName: 'Alpha',
        branches: const [
          Branch(
            id: 'suc_centro',
            name: 'Centro',
            normalizedName: 'centro',
            active: true,
            sortOrder: 1,
            restaurantId: 'rest_alpha',
          ),
        ],
      );
      expect(session.isAuthenticated, isTrue);
      expect(session.permissions.canManageSettings, isTrue);
      expect(session.permissions.canManageEmployees, isFalse);

      session.signOut();
      expect(session.isAuthenticated, isFalse);
      expect(session.employee, isNull);
      expect(session.branches, isEmpty);
      expect(session.permissions.canViewDashboard, isFalse);
    });

    test('Deactivated employee immediately loses all BackofficePermissions', () {
      final inactive = BackofficePermissions(
        employee: _emp(
          active: false,
          isSuperAdmin: true,
          canManageEmployees: true,
          canViewAdmin: true,
        ),
        isSuperAdmin: true,
      );
      expect(inactive.isAuthenticated, isFalse);
      expect(inactive.canViewDashboard, isFalse);
      expect(inactive.canManageEmployees, isFalse);
      expect(inactive.canManageSettings, isFalse);
    });

    test('Settings models parse Android settings/discounts & settings/appUpdates cleanly', () {
      final disc = GeneralDiscountConfig.fromMap(const {
        'active': true,
        'name': 'Promo Jueves',
        'percent': 15.0,
        'description': 'Descuento nocturno',
        'branchId': 'suc_centro',
      });
      expect(disc.active, isTrue);
      expect(disc.percent, 15.0);
      expect(disc.branchId, 'suc_centro');

      final app = AppUpdateConfig.fromMap(const {
        'active': true,
        'minimumSupportedVersionCode': 42,
        'recommendedVersionCode': 45,
        'forceUpdate': true,
        'updateMessage': 'Actualiza TacoPOS',
      });
      expect(app.active, isTrue);
      expect(app.minimumSupportedVersionCode, 42);
      expect(app.forceUpdate, isTrue);
    });
  });
}
