import '../../models/cash_session.dart';

const Duration mexicoCityUtcOffset = Duration(hours: -6);

DateTime mexicoCityDateTime(DateTime instant) {
  return instant.toUtc().add(mexicoCityUtcOffset);
}

String formatCashLocalTime(DateTime? instant) {
  if (instant == null) return 'No registrada';
  final local = mexicoCityDateTime(instant);
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'a. m.' : 'p. m.';
  return '$hour:$minute $period';
}

String formatCashLocalDate(DateTime? instant) {
  if (instant == null) return 'No registrada';
  final local = mexicoCityDateTime(instant);
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year}';
}

String formatBusinessDate(String businessDate) {
  final parsed = parseBusinessDate(businessDate);
  if (parsed == null) return businessDate;
  return '${parsed.day.toString().padLeft(2, '0')}/'
      '${parsed.month.toString().padLeft(2, '0')}/'
      '${parsed.year}';
}

DateTime? parseBusinessDate(String businessDate) {
  final parts = businessDate.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  final result = DateTime(year, month, day);
  if (result.year != year || result.month != month || result.day != day) {
    return null;
  }
  return result;
}

String businessDateKey(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

Duration? cashSessionDuration(CashSession session, {DateTime? now}) {
  final openedAt = reliableCashSessionOpenedAt(session);
  if (openedAt == null) return null;
  final end =
      reliableCashSessionClosedAt(session) ??
      (session.isOpen ? now ?? DateTime.now() : null);
  if (end == null || end.isBefore(openedAt)) return null;
  return end.difference(openedAt);
}

DateTime? reliableCashSessionOpenedAt(CashSession session) {
  final openedAt = session.openedAt;
  if (openedAt == null) return null;
  final generatedByLegacyCorrection =
      session.correctionMode &&
      session.openedByEmployeeName.trim().toLowerCase() == 'correccion admin';
  return generatedByLegacyCorrection ? null : openedAt;
}

DateTime? estimatedHistoricalCashSessionOpenedAt(CashSession session) {
  if (reliableCashSessionOpenedAt(session) != null ||
      session.correctionMode ||
      session.createdAt == null) {
    return null;
  }
  return session.createdAt;
}

DateTime? reliableCashSessionClosedAt(CashSession session) {
  final closedAt = session.closedAt;
  if (closedAt == null) return null;
  final correctedAt = session.correctedAt;
  final overwrittenByLegacyCorrection =
      session.correctionMode &&
      correctedAt != null &&
      closedAt.difference(correctedAt).abs() < const Duration(seconds: 2);
  return overwrittenByLegacyCorrection ? null : closedAt;
}

String formatCashDuration(Duration? duration) {
  if (duration == null || duration.isNegative) return 'No disponible';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '$minutes min';
  if (minutes == 0) return '$hours h';
  return '$hours h $minutes min';
}

Map<String, Object?> cashSessionOpenTimestampFields({
  required Object serverTimestamp,
  required String employeeId,
  required String employeeName,
}) {
  return {
    'openedAt': serverTimestamp,
    'openedByEmployeeId': employeeId,
    'openedByEmployeeName': employeeName,
  };
}

Map<String, Object?> cashSessionCloseTimestampFields({
  required String currentStatus,
  required DateTime? currentClosedAt,
  required Object serverTimestamp,
  required String employeeId,
  required String employeeName,
}) {
  if (currentStatus.trim().toLowerCase() != 'open' || currentClosedAt != null) {
    throw StateError('Esta caja ya fue cerrada.');
  }
  return {
    'status': 'closed',
    'closedAt': serverTimestamp,
    'closedByEmployeeId': employeeId,
    'closedByEmployeeName': employeeName,
    'updatedAt': serverTimestamp,
  };
}

Map<String, Object?> preservedHistoricalCashTimestampFields(
  CashSession? existing,
) {
  if (existing == null) return const {};
  return {
    if (existing.openedAt != null) 'openedAt': existing.openedAt!,
    if (existing.openedByEmployeeId.isNotEmpty)
      'openedByEmployeeId': existing.openedByEmployeeId,
    if (existing.openedByEmployeeName.isNotEmpty)
      'openedByEmployeeName': existing.openedByEmployeeName,
    if (existing.closedAt != null) 'closedAt': existing.closedAt!,
    if (existing.closedByEmployeeId?.trim().isNotEmpty == true)
      'closedByEmployeeId': existing.closedByEmployeeId!,
    if (existing.closedByEmployeeName?.trim().isNotEmpty == true)
      'closedByEmployeeName': existing.closedByEmployeeName!,
  };
}
