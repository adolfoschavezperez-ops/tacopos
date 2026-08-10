const visitClassificationFirstTime = 'first_time';
const visitClassificationReturning = 'returning';
const visitSurveyVersion = 1;

bool hasVisitClassificationAnswer({
  required String? visitClassification,
  required bool? isFirstVisit,
}) {
  final clean = visitClassification?.trim().toLowerCase();
  return clean == visitClassificationFirstTime ||
      clean == visitClassificationReturning ||
      isFirstVisit != null;
}

bool orderNeedsVisitSurvey({
  required bool isNewOrder,
  required String? visitClassification,
  required bool? isFirstVisit,
}) {
  return isNewOrder &&
      !hasVisitClassificationAnswer(
        visitClassification: visitClassification,
        isFirstVisit: isFirstVisit,
      );
}
