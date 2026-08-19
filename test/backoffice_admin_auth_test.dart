import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/screens/login_screen.dart';
import 'package:tacopos/services/backoffice_admin_auth_service.dart';

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
          'employeeId': 'admin',
          'permissions': {'canViewAdmin': true},
        },
      );

      final employee = record.toEmployee(
        restaurantId: 'main_restaurant',
        defaultBranchId: 'aviacion',
      );

      expect(employee.id, 'admin');
      expect(employee.name, 'Admin');
      expect(employee.hasAdminAccess, isTrue);
      expect(employee.canManageCash, isTrue);
      expect(employee.defaultRestaurantId, 'main_restaurant');
      expect(employee.restaurantAccess, ['main_restaurant']);
    });

    test('pin incorrecto tiene mensaje limpio', () {
      final message = backofficeLoginErrorMessage(Exception('bad login'));

      expect(message, 'PIN incorrecto.');
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

    test('pantalla web usa combo Usuario y PIN sin correo password', () {
      final source = File('lib/screens/login_screen.dart').readAsStringSync();
      final service = File(
        'lib/services/backoffice_admin_auth_service.dart',
      ).readAsStringSync();

      expect(source, contains("labelText: 'Usuario'"));
      expect(source, contains('DropdownButtonFormField<BackofficeLoginUser>'));
      expect(source, contains("labelText: 'Empleado'"));
      expect(source, contains("labelText: 'PIN'"));
      expect(source, isNot(contains("labelText: 'Correo'")));
      expect(source, isNot(contains("labelText: 'Contrasena'")));
      expect(source, isNot(contains('final _userController')));
      expect(source, contains('signInWithPin'));
      expect(service, contains('listBackofficeUsers'));
      expect(service, contains("httpsCallable('listBackofficeUsers')"));
      expect(service, contains('signInWithCustomToken'));
    });

    test('login web no lista empleados antes del custom token', () {
      final source = File('lib/screens/login_screen.dart').readAsStringSync();

      expect(source, contains('if (_isBackofficeWebLogin)'));
      expect(
        source,
        contains('_employeesStream = _repository.watchEmployees();'),
      );
      expect(
        source,
        contains('_backofficeUsersFuture = _loadBackofficeUsers();'),
      );
      expect(source, contains('employeeId: selectedUser.id'));
    });
  });
}
