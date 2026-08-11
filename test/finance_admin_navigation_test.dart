import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/theme/app_theme.dart';
import 'package:tacopos/screens/admin/finance_admin_screen.dart';

void main() {
  testWidgets(
    'Dashboard principal es la primera opcion y conserva la pestaña activa',
    (tester) async {
      var dashboardOpens = 0;
      TabController? controller;

      for (final size in const [
        Size(1920, 1080),
        Size(1600, 900),
        Size(1366, 768),
      ]) {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: DefaultTabController(
                length: 6,
                initialIndex: 1,
                child: Builder(
                  builder: (context) {
                    controller = DefaultTabController.of(context);
                    return Column(
                      children: [
                        FinanceNavigationTabs(
                          canOpenDashboard: true,
                          onOpenDashboard: () => dashboardOpens++,
                        ),
                        const Expanded(
                          child: TabBarView(
                            physics: NeverScrollableScrollPhysics(),
                            children: [
                              SizedBox.shrink(),
                              SizedBox.shrink(),
                              SizedBox.shrink(),
                              SizedBox.shrink(),
                              SizedBox.shrink(),
                              SizedBox.shrink(),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Dashboard principal'), findsOneWidget);
        expect(find.text('Comparativo semanal'), findsNothing);
        expect(find.byIcon(Icons.dashboard_outlined), findsOneWidget);
        expect(
          tester.getCenter(find.text('Dashboard principal')).dx,
          lessThan(tester.getCenter(find.text('Estado financiero')).dx),
        );
        expect(
          tester.getCenter(find.text('Flujo de efectivo')).dx,
          lessThan(tester.getCenter(find.text('Aportaciones de socios')).dx),
        );
        expect(tester.takeException(), isNull, reason: 'Resolucion $size');
      }

      await tester.tap(find.text('Dashboard principal'));
      await tester.pump();

      expect(dashboardOpens, 1);
      expect(controller?.index, 1);
      expect(find.text('Estado financiero'), findsOneWidget);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('oculta Dashboard principal cuando no existe permiso', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: DefaultTabController(
            length: 5,
            child: FinanceNavigationTabs(
              canOpenDashboard: false,
              onOpenDashboard: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Dashboard principal'), findsNothing);
    expect(find.text('Estado financiero'), findsOneWidget);
    expect(find.text('Reportes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
