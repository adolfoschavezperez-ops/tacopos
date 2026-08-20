import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/expenses/expense_policy.dart';
import 'package:tacopos/screens/admin/expense_policy_admin_screen.dart';

void main() {
  testWidgets('OFF muestra sin limite de horario', (tester) async {
    await tester.pumpWidget(
      _host(settings: const ExpensePolicySettings(), onChanged: (_) async {}),
    );

    expect(find.text('Horario limite para aprobacion manual'), findsOneWidget);
    expect(find.text('Sin limite de horario'), findsOneWidget);
    expect(find.text('Hora limite'), findsNothing);
  });

  testWidgets('ON sin hora obliga seleccionar hora antes de guardar', (
    tester,
  ) async {
    ExpensePolicySettings? saved;

    await tester.pumpWidget(
      _host(
        settings: const ExpensePolicySettings(),
        onChanged: (value) async => saved = value,
        timePicker: (_, _) async => const TimeOfDay(hour: 22, minute: 0),
      ),
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(saved?.manualApprovalCutoffEnabled, isTrue);
    expect(saved?.manualApprovalCutoffTime, '22:00');
  });

  testWidgets('cancelar primera seleccion mantiene configuracion sin guardar', (
    tester,
  ) async {
    var saves = 0;

    await tester.pumpWidget(
      _host(
        settings: const ExpensePolicySettings(),
        onChanged: (_) async => saves++,
        timePicker: (_, _) async => null,
      ),
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(saves, 0);
  });

  testWidgets('editar cambia 22:00 a 21:30 y reload conserva', (tester) async {
    ExpensePolicySettings saved = const ExpensePolicySettings(
      manualApprovalCutoffEnabled: true,
      manualApprovalCutoffTime: '22:00',
    );

    Future<void> pumpCurrent() {
      return tester.pumpWidget(
        _host(
          settings: saved,
          onChanged: (value) async => saved = value,
          timePicker: (_, _) async => const TimeOfDay(hour: 21, minute: 30),
        ),
      );
    }

    await pumpCurrent();
    expect(find.text('10:00 PM'), findsWidgets);

    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    await pumpCurrent();

    expect(saved.manualApprovalCutoffEnabled, isTrue);
    expect(saved.manualApprovalCutoffTime, '21:30');
    expect(find.text('9:30 PM'), findsWidgets);
  });

  testWidgets('desactivar conserva hora internamente', (tester) async {
    ExpensePolicySettings? saved;

    await tester.pumpWidget(
      _host(
        settings: const ExpensePolicySettings(
          manualApprovalCutoffEnabled: true,
          manualApprovalCutoffTime: '21:30',
        ),
        onChanged: (value) async => saved = value,
      ),
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(saved?.manualApprovalCutoffEnabled, isFalse);
    expect(saved?.manualApprovalCutoffTime, '21:30');
  });

  testWidgets('reactivar reutiliza la hora conservada', (tester) async {
    ExpensePolicySettings? saved;

    await tester.pumpWidget(
      _host(
        settings: const ExpensePolicySettings(
          manualApprovalCutoffEnabled: false,
          manualApprovalCutoffTime: '21:30',
        ),
        onChanged: (value) async => saved = value,
        timePicker: (_, _) async {
          fail('No debe abrir selector cuando ya existe hora valida.');
        },
      ),
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(saved?.manualApprovalCutoffEnabled, isTrue);
    expect(saved?.manualApprovalCutoffTime, '21:30');
  });
}

Widget _host({
  required ExpensePolicySettings settings,
  required Future<void> Function(ExpensePolicySettings) onChanged,
  ExpensePolicyTimePicker? timePicker,
}) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      body: ExpensePolicySettingsPanel(
        settings: settings,
        onChanged: onChanged,
        timePicker: timePicker,
      ),
    ),
  );
}
