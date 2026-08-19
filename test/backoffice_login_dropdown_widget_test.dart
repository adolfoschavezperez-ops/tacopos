import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/theme/app_theme.dart';
import 'package:tacopos/screens/login_screen.dart';
import 'package:tacopos/services/backoffice_admin_auth_service.dart';

void main() {
  testWidgets('login muestra dropdown usuario y no TextField usuario', (
    tester,
  ) async {
    await pumpLogin(tester);

    expect(
      find.byKey(const ValueKey('backoffice-user-dropdown')),
      findsOneWidget,
    );
    expect(_textFieldWithLabel(tester, 'Usuario'), isEmpty);
    expect(_textFieldWithLabel(tester, 'PIN'), hasLength(1));
  });

  testWidgets('dropdown carga lista y muestra nombres', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.byKey(const ValueKey('backoffice-user-dropdown')));
    await tester.pumpAndSettle();

    expect(find.text('Adolfo Chavez'), findsWidgets);
    expect(find.text('Gabriel'), findsWidgets);
  });

  testWidgets('dropdown conserva employeeId interno al iniciar login', (
    tester,
  ) async {
    String? employeeId;
    String? pin;
    await pumpLogin(
      tester,
      captureLogin: (capturedEmployeeId, capturedPin) {
        employeeId = capturedEmployeeId;
        pin = capturedPin;
      },
    );

    await selectUser(tester, 'Adolfo Chavez');
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(employeeId, 'employee123');
    expect(pin, '1234');
  });

  testWidgets('sin seleccion no llama login', (tester) async {
    var called = false;
    await pumpLogin(
      tester,
      captureLogin: (_, _) {
        called = true;
      },
    );

    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('Selecciona un usuario.'), findsOneWidget);
  });

  testWidgets('PIN vacio no llama login', (tester) async {
    var called = false;
    await pumpLogin(
      tester,
      captureLogin: (_, _) {
        called = true;
      },
    );

    await selectUser(tester, 'Gabriel');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('Ingresa tu PIN.'), findsOneWidget);
  });

  testWidgets('PIN incorrecto muestra mensaje limpio', (tester) async {
    await pumpLogin(tester, loginError: Exception('bad pin'));

    await selectUser(tester, 'Gabriel');
    await tester.enterText(find.byType(TextField), '0000');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('PIN incorrecto.'), findsOneWidget);
    expect(find.textContaining('permission-denied'), findsNothing);
  });

  testWidgets('usuario sin permiso muestra mensaje limpio', (tester) async {
    await pumpLogin(
      tester,
      loginError: const BackofficeAdminAuthException(
        'No tienes permisos para acceder al Backoffice.',
      ),
    );

    await selectUser(tester, 'Gabriel');
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(
      find.text('No tienes permisos para acceder al Backoffice.'),
      findsOneWidget,
    );
  });

  testWidgets('error listando usuarios permite reintentar sin error crudo', (
    tester,
  ) async {
    var attempts = 0;
    await pumpLogin(
      tester,
      loader: () async {
        attempts += 1;
        if (attempts == 1) {
          throw Exception('[cloud_firestore/permission-denied]');
        }
        return users;
      },
    );

    expect(
      find.text('No fue posible cargar los usuarios. Reintentar.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('[cloud_firestore/permission-denied]'),
      findsNothing,
    );

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('backoffice-user-dropdown')));
    await tester.pumpAndSettle();

    expect(find.text('Adolfo Chavez'), findsWidgets);
  });
}

const users = [
  BackofficeLoginUser(id: 'employee123', displayName: 'Adolfo Chavez'),
  BackofficeLoginUser(id: 'employee456', displayName: 'Gabriel'),
];

Future<void> pumpLogin(
  WidgetTester tester, {
  Future<List<BackofficeLoginUser>> Function()? loader,
  Future<void> Function({required String employeeId, required String pin})?
  login,
  void Function(String employeeId, String pin)? captureLogin,
  Object? loginError,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: LoginScreen(
        forceBackofficeWebLogin: true,
        backofficeUsersLoader: loader ?? () async => users,
        backofficePinLogin:
            login ??
            ({required employeeId, required pin}) async {
              captureLogin?.call(employeeId, pin);
              if (loginError != null) {
                throw loginError;
              }
            },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> selectUser(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const ValueKey('backoffice-user-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

List<TextField> _textFieldWithLabel(WidgetTester tester, String label) {
  return tester
      .widgetList<TextField>(find.byType(TextField))
      .where((field) => field.decoration?.labelText == label)
      .toList();
}
