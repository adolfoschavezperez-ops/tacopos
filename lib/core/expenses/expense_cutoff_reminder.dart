class ExpenseCutoffReminderDecision {
  const ExpenseCutoffReminderDecision({
    required this.thresholdMinutes,
    required this.cutoffAt,
    required this.storageKey,
  });

  final int thresholdMinutes;
  final DateTime cutoffAt;
  final String storageKey;
}

class ExpenseCutoffReminderInput {
  const ExpenseCutoffReminderInput({
    required this.restaurantId,
    required this.branchId,
    required this.employeeId,
    required this.businessDate,
    required this.cutoffTime,
    required this.now,
    this.cutoffEnabled = true,
    this.hasCashPermission = true,
    this.shownKeys = const {},
    this.suppressedKeys = const {},
  });

  final String restaurantId;
  final String branchId;
  final String employeeId;
  final String businessDate;
  final String cutoffTime;
  final DateTime now;
  final bool cutoffEnabled;
  final bool hasCashPermission;
  final Set<String> shownKeys;
  final Set<String> suppressedKeys;
}

const expenseCutoffReminderThresholds = [5, 10, 15];

ExpenseCutoffReminderDecision? nextExpenseCutoffReminder(
  ExpenseCutoffReminderInput input,
) {
  if (!input.cutoffEnabled || !input.hasCashPermission) return null;
  if (input.employeeId.trim().isEmpty) return null;
  final cutoffAt = expenseCutoffDateTime(
    businessDate: input.businessDate,
    cutoffTime: input.cutoffTime,
  );
  if (cutoffAt == null || !input.now.isBefore(cutoffAt)) return null;

  final remainingSeconds = cutoffAt.difference(input.now).inSeconds;
  final remainingMinutes = remainingSeconds / 60.0;
  int? threshold;
  for (final candidate in expenseCutoffReminderThresholds) {
    if (remainingMinutes <= candidate) {
      threshold = candidate;
      break;
    }
  }
  if (threshold == null) return null;

  final baseKey = expenseCutoffReminderBaseKey(
    restaurantId: input.restaurantId,
    branchId: input.branchId,
    employeeId: input.employeeId,
    businessDate: input.businessDate,
    cutoffTime: input.cutoffTime,
  );
  if (input.suppressedKeys.contains(baseKey)) return null;
  final storageKey = '$baseKey|$threshold';
  if (input.shownKeys.contains(storageKey)) return null;
  return ExpenseCutoffReminderDecision(
    thresholdMinutes: threshold,
    cutoffAt: cutoffAt,
    storageKey: storageKey,
  );
}

String expenseCutoffReminderBaseKey({
  required String restaurantId,
  required String branchId,
  required String employeeId,
  required String businessDate,
  required String cutoffTime,
}) {
  return [
    'expense_cutoff_reminder',
    restaurantId.trim(),
    branchId.trim(),
    employeeId.trim(),
    businessDate.trim(),
    cutoffTime.trim(),
  ].join('|');
}

DateTime? expenseCutoffDateTime({
  required String businessDate,
  required String cutoffTime,
}) {
  final dateParts = businessDate.trim().split('-');
  final timeParts = cutoffTime.trim().split(':');
  if (dateParts.length != 3 || timeParts.length < 2) return null;
  final year = int.tryParse(dateParts[0]);
  final month = int.tryParse(dateParts[1]);
  final day = int.tryParse(dateParts[2]);
  final hour = int.tryParse(timeParts[0]);
  final minute = int.tryParse(timeParts[1]);
  if (year == null ||
      month == null ||
      day == null ||
      hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }
  var cutoff = DateTime(year, month, day, hour, minute);
  if (hour < 6) {
    cutoff = cutoff.add(const Duration(days: 1));
  }
  return cutoff;
}
