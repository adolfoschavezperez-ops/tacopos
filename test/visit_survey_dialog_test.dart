import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/widgets/visit_survey_dialog.dart';

void main() {
  testWidgets('visit survey uses a full screen layout with large actions', (
    tester,
  ) async {
    await _setSurfaceSize(tester, const Size(1024, 768));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: VisitSurveyDialog())),
    );

    expect(find.text('¿ES CLIENTE NUEVO?'), findsOneWidget);
    expect(find.text('Sí'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);

    final yesSize = tester.getSize(find.widgetWithText(FilledButton, 'Sí'));
    final noSize = tester.getSize(find.widgetWithText(FilledButton, 'No'));

    expect(yesSize.height, greaterThanOrEqualTo(100));
    expect(noSize.height, greaterThanOrEqualTo(100));
    expect(yesSize.width, greaterThanOrEqualTo(700));
    expect(noSize.width, greaterThanOrEqualTo(700));
  });

  testWidgets('visit survey returns first time when selecting yes', (
    tester,
  ) async {
    VisitSurveyAnswer? answer;
    await tester.pumpWidget(
      _host((context) async {
        answer = await showVisitSurveyDialog(context);
      }),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí'));
    await tester.pumpAndSettle();

    expect(answer, VisitSurveyAnswer.firstTime);
  });

  testWidgets('visit survey returns returning when selecting no', (
    tester,
  ) async {
    VisitSurveyAnswer? answer;
    await tester.pumpWidget(
      _host((context) async {
        answer = await showVisitSurveyDialog(context);
      }),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();

    expect(answer, VisitSurveyAnswer.returning);
  });

  testWidgets('visit survey ignores rapid double taps while closing', (
    tester,
  ) async {
    VisitSurveyAnswer? answer;
    var completedCount = 0;
    await tester.pumpWidget(
      _host((context) async {
        answer = await showVisitSurveyDialog(context);
        completedCount++;
      }),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí'));
    await tester.tap(find.text('Sí'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(answer, VisitSurveyAnswer.firstTime);
    expect(completedCount, 1);
    expect(find.text('¿ES CLIENTE NUEVO?'), findsNothing);
  });

  testWidgets('visit survey closes cleanly with Android back', (tester) async {
    VisitSurveyAnswer? answer = VisitSurveyAnswer.firstTime;
    await tester.pumpWidget(
      _host((context) async {
        answer = await showVisitSurveyDialog(context);
      }),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('¿ES CLIENTE NUEVO?'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(answer, isNull);
    expect(find.text('¿ES CLIENTE NUEVO?'), findsNothing);

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('¿ES CLIENTE NUEVO?'), findsOneWidget);
  });

  testWidgets('visit survey fits tablet portrait', (tester) async {
    await _setSurfaceSize(tester, const Size(768, 1024));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: VisitSurveyDialog())),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('¿ES CLIENTE NUEVO?'), findsOneWidget);
    expect(tester.getSize(find.widgetWithText(FilledButton, 'Sí')).height, 112);
    expect(tester.getSize(find.widgetWithText(FilledButton, 'No')).height, 112);
  });

  testWidgets('visit survey fits tablet landscape', (tester) async {
    await _setSurfaceSize(tester, const Size(1024, 768));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: VisitSurveyDialog())),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('¿ES CLIENTE NUEVO?'), findsOneWidget);
    expect(tester.getSize(find.widgetWithText(FilledButton, 'Sí')).height, 112);
    expect(tester.getSize(find.widgetWithText(FilledButton, 'No')).height, 112);
  });
}

Widget _host(Future<void> Function(BuildContext context) onOpen) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        return Scaffold(
          body: FilledButton(
            onPressed: () => onOpen(context),
            child: const Text('Abrir'),
          ),
        );
      },
    ),
  );
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
