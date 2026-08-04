import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/widgets/visit_survey_dialog.dart';

void main() {
  testWidgets('visit survey shows only yes and no actions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: VisitSurveyDialog())),
    );

    expect(find.text('¿Es la primera vez que nos visitan?'), findsOneWidget);
    expect(find.text('Sí'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('visit survey does not close by tapping outside', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () => showVisitSurveyDialog(context),
                child: const Text('Abrir'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    expect(find.text('¿Es la primera vez que nos visitan?'), findsOneWidget);
  });

  testWidgets('visit survey returns selected answer', (tester) async {
    VisitSurveyAnswer? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () async {
                  answer = await showVisitSurveyDialog(context);
                },
                child: const Text('Abrir'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();

    expect(answer, VisitSurveyAnswer.returning);
  });
}
