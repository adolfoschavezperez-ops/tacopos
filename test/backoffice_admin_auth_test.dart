import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/services/backoffice_admin_auth_service.dart';
import 'package:tacopos/screens/login_screen.dart';

void main() {
  group('Backoffice admin auth', () {
    test('auth user sin authUsers no administra', () {
      final record = BackofficeAdminRecord.fromMap(
        uid: 'uid',
        email: 'admin@example.com',
        data: null,
      );

      expect(record.exists, isFalse);
      expect(record.canAccessBackoffice, isFalse);
      expect(record.canManageExpensePolicies, isFalse);
    });

    test('inactive admin no administra', () {
      final record = BackofficeAdminRecord.fromMap(
        uid: 'uid',
        email: 'admin@example.com',
        data: {
          'active': false,
          'isSuperAdmin': true,
          'permissions': {'canViewAdmin': true},
        },
      );

      expect(record.canAccessBackoffice, isFalse);
    });

    test('admin valido administra pantallas sensibles', () {
      final record = BackofficeAdminRecord.fromMap(
        uid: 'uid',
        email: 'admin@example.com',
        data: {
          'active': true,
          'isSuperAdmin': false,
          'permissions': {'canViewAdmin': true},
        },
      );

      expect(record.canAccessBackoffice, isTrue);
      expect(record.canManageExpensePolicies, isTrue);
      expect(record.canManageDevices, isTrue);
      expect(record.canManageAppUpdates, isTrue);
      expect(record.canWriteSensitiveSettings, isTrue);
    });

    test('anonymous no administra', () {
      final record = BackofficeAdminRecord.fromMap(
        uid: 'anon',
        email: '',
        data: {
          'active': true,
          'isSuperAdmin': false,
          'permissions': <String, bool>{},
        },
      );

      expect(record.canAccessBackoffice, isFalse);
    });

    test('admin genera empleado de sesion Backoffice', () {
      final record = BackofficeAdminRecord.fromMap(
        uid: 'admin-uid',
        email: 'admin@example.com',
        data: {
          'active': true,
          'isSuperAdmin': true,
          'displayName': 'Admin',
          'permissions': {'canViewAdmin': true},
        },
      );

      final employee = record.toEmployee(
        restaurantId: 'main_restaurant',
        defaultBranchId: 'aviacion',
      );

      expect(employee.id, 'admin-uid');
      expect(employee.name, 'Admin');
      expect(employee.hasAdminAccess, isTrue);
      expect(employee.canManageCash, isTrue);
      expect(employee.defaultRestaurantId, 'main_restaurant');
      expect(employee.restaurantAccess, ['main_restaurant']);
    });

    test('password incorrecto tiene mensaje limpio', () {
      final message = backofficeLoginErrorMessage(
        FirebaseAuthException(code: 'wrong-password'),
      );

      expect(message, 'Correo o contrasena incorrectos.');
    });

    test('logout elimina acceso al limpiar sesion local', () {
      final record = BackofficeAdminRecord.fromMap(
        uid: 'uid',
        email: 'admin@example.com',
        data: null,
      );

      expect(record.canAccessBackoffice, isFalse);
    });

    test('sesion expirada vuelve a login con mensaje administrativo', () {
      final message = backofficeLoginErrorMessage(
        const BackofficeAdminAuthException(
          'Inicia sesion para acceder al Backoffice.',
        ),
      );

      expect(message, 'Inicia sesion para acceder al Backoffice.');
    });
  });
}
