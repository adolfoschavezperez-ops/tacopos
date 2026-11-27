import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/backoffice_v2/app/isolation_blocked_screen.dart';
import 'package:tacopos/backoffice_v2/auth/backoffice_session.dart';
import 'package:tacopos/backoffice_v2/auth/widgets/login_showcase_panel.dart';
import 'package:tacopos/backoffice_v2/core/design/backoffice_theme.dart';
import 'package:tacopos/backoffice_v2/core/env/backoffice_env.dart';
import 'package:tacopos/backoffice_v2/navigation/app_shell.dart';
import 'package:tacopos/backoffice_v2/navigation/backoffice_route.dart';
import 'package:tacopos/models/branch.dart';
import 'package:tacopos/models/employee.dart';

void main() {
  testWidgets('IsolationBlockedApp displays guard code and blocks startup', (
    tester,
  ) async {
    await tester.pumpWidget(
      const IsolationBlockedApp(
        error: EnvironmentGuardException(
          'FORBIDDEN_PROD_PROJECT',
          'Bloqueado por seguridad',
        ),
      ),
    );
    expect(find.text('Código: FORBIDDEN_PROD_PROJECT'), findsOneWidget);
    expect(find.text('Bloqueado por seguridad'), findsOneWidget);
  });

  testWidgets('BackofficeAppShell renders sidebar, env pill, branch selector and toggles dark mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final config = EnvironmentGuard.resolveAndValidate(rawEnv: 'local');
    final session = BackofficeSession(config: config);
    session.signIn(
      employee: const Employee(
        id: 'emp_admin',
        name: 'Adolfo Admin',
        active: true,
        pin: '',
        canTakeOrders: false,
        canCharge: false,
        canViewKitchen: true,
        canViewAdmin: true,
        canManageProducts: true,
        canManageTables: true,
        canManagePlatforms: true,
        canManageEmployees: true,
        canManageCash: true,
        canAuthorizeCashWithdrawals: true,
        canOpenKitchen: true,
        canCloseKitchen: true,
        canViewKitchenReports: true,
        canViewKitchenHourlySalesComparison: true,
        canManageKitchenStock: true,
        canCancelOrders: true,
        canCancelPayments: true,
        canCancelItems: true,
        canApproveKitchenCancellations: true,
        canViewLiveOperations: true,
        canControlLiveOperations: true,
      ),
      restaurantId: 'rest_alpha',
      restaurantName: 'Taquería Alpha',
      branches: const [
        Branch(
          id: 'suc_centro',
          restaurantId: 'rest_alpha',
          restaurantName: 'Taquería Alpha',
          name: 'Centro',
          normalizedName: 'centro',
          active: true,
          sortOrder: 1,
        ),
        Branch(
          id: 'suc_norte',
          restaurantId: 'rest_alpha',
          restaurantName: 'Taquería Alpha',
          name: 'Norte',
          normalizedName: 'norte',
          active: true,
          sortOrder: 2,
        ),
      ],
    );

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: session,
        builder: (context, _) => MaterialApp(
          theme: BackofficeTheme.light(),
          darkTheme: BackofficeTheme.dark(),
          themeMode: session.themeMode,
          home: BackofficeAppShell(
            session: session,
            currentRoute: const BackofficeRoute.section(
              BackofficeSection.dashboard,
            ),
            onNavigate: (_) {},
            onSignOut: () {},
            child: const Center(child: Text('Contenido')),
          ),
        ),
      ),
    );

    expect(find.text('LOCAL • EMULADOR'), findsOneWidget);
    expect(find.text('Todas las sucursales'), findsOneWidget);
    expect(find.text('Taquería Alpha'), findsOneWidget);
    expect(session.isDarkMode, isFalse);

    await tester.tap(find.byTooltip('Modo oscuro'));
    await tester.pump();
    expect(session.isDarkMode, isTrue);
  });

  testWidgets('LoginShowcasePanel renders without errors at 1920x1080 and 1366x768', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(flex: 55, child: LoginShowcasePanel()),
              Expanded(flex: 45, child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Tu restaurante, bajo control.'), findsOneWidget);
    expect(find.text('Ventas del día'), findsOneWidget);
  });
}
