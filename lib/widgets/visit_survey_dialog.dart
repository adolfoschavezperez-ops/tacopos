import 'package:flutter/material.dart';

enum VisitSurveyAnswer {
  firstTime('first_time', true),
  returning('returning', false);

  const VisitSurveyAnswer(this.firestoreValue, this.isFirstVisit);

  final String firestoreValue;
  final bool isFirstVisit;
}

Future<VisitSurveyAnswer?> showVisitSurveyDialog(BuildContext context) {
  return showDialog<VisitSurveyAnswer>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const VisitSurveyDialog(),
  );
}

class VisitSurveyDialog extends StatelessWidget {
  const VisitSurveyDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('¿Es la primera vez que nos visitan?'),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(VisitSurveyAnswer.firstTime),
          child: const Text('Sí'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(VisitSurveyAnswer.returning),
          child: const Text('No'),
        ),
      ],
    );
  }
}
