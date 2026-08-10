import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/visits/visit_classification.dart';
import 'package:tacopos/widgets/visit_survey_dialog.dart';

void main() {
  group('visit classification prompt rule', () {
    test(
      'new table order shows question and existing table order does not',
      () {
        expect(
          orderNeedsVisitSurvey(
            isNewOrder: true,
            visitClassification: null,
            isFirstVisit: null,
          ),
          isTrue,
        );
        expect(
          orderNeedsVisitSurvey(
            isNewOrder: false,
            visitClassification: null,
            isFirstVisit: null,
          ),
          isFalse,
        );
      },
    );

    test('new takeout order shows question and existing takeout does not', () {
      expect(
        orderNeedsVisitSurvey(
          isNewOrder: true,
          visitClassification: '',
          isFirstVisit: null,
        ),
        isTrue,
      );
      expect(
        orderNeedsVisitSurvey(
          isNewOrder: false,
          visitClassification: visitClassificationFirstTime,
          isFirstVisit: true,
        ),
        isFalse,
      );
    });

    test(
      'new standing order shows question and existing standing does not',
      () {
        expect(
          orderNeedsVisitSurvey(
            isNewOrder: true,
            visitClassification: null,
            isFirstVisit: null,
          ),
          isTrue,
        );
        expect(
          orderNeedsVisitSurvey(
            isNewOrder: false,
            visitClassification: visitClassificationReturning,
            isFirstVisit: false,
          ),
          isFalse,
        );
      },
    );

    test('saved classification prevents asking on reopen or rebuild', () {
      for (final answer in VisitSurveyAnswer.values) {
        expect(
          orderNeedsVisitSurvey(
            isNewOrder: true,
            visitClassification: answer.firestoreValue,
            isFirstVisit: answer.isFirstVisit,
          ),
          isFalse,
        );
      }
    });

    test('same classification fields are used for every order type', () {
      expect(VisitSurveyAnswer.firstTime.firestoreValue, 'first_time');
      expect(VisitSurveyAnswer.returning.firestoreValue, 'returning');
      expect(visitSurveyVersion, 1);
    });
  });
}
