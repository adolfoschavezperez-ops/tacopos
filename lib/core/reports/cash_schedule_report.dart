import '../../models/cash_session.dart';
import '../cash/cash_session_timing.dart';

const _weekdayNames = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

const _monthNames = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

DateTime startOfCashScheduleWeek(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

String cashScheduleWeekLabel(DateTime weekStart) {
  final start = startOfCashScheduleWeek(weekStart);
  final end = start.add(const Duration(days: 6));
  if (start.year == end.year && start.month == end.month) {
    return 'Semana del ${start.day} al ${end.day} de '
        '${_monthNames[start.month - 1]} de ${start.year}';
  }
  if (start.year == end.year) {
    return 'Semana del ${start.day} de ${_monthNames[start.month - 1]} '
        'al ${end.day} de ${_monthNames[end.month - 1]} de ${end.year}';
  }
  return 'Semana del ${start.day} de ${_monthNames[start.month - 1]} '
      'de ${start.year} al ${end.day} de ${_monthNames[end.month - 1]} '
      'de ${end.year}';
}

class CashScheduleDay {
  const CashScheduleDay({
    required this.date,
    required this.weekdayName,
    required this.businessDate,
    required this.sessions,
  });

  final DateTime date;
  final String weekdayName;
  final String businessDate;
  final List<CashSession> sessions;

  bool get hasOperation => sessions.isNotEmpty;
  bool get hasMultipleSessions => sessions.length > 1;
  CashSession? get singleSession =>
      sessions.length == 1 ? sessions.first : null;
}

class CashScheduleSummary {
  const CashScheduleSummary({
    required this.daysWithOpening,
    required this.daysWithoutOperation,
    required this.averageOpeningMinutes,
    required this.averageClosingMinutes,
    required this.averageDuration,
    required this.pendingSessions,
    required this.incompleteSessions,
  });

  final int daysWithOpening;
  final int daysWithoutOperation;
  final int? averageOpeningMinutes;
  final int? averageClosingMinutes;
  final Duration? averageDuration;
  final int pendingSessions;
  final int incompleteSessions;

  String get averageOpeningLabel =>
      _formatAverageClockMinutes(averageOpeningMinutes);
  String get averageClosingLabel =>
      _formatAverageClockMinutes(averageClosingMinutes);
  String get averageDurationLabel => formatCashDuration(averageDuration);
}

class CashScheduleReport {
  const CashScheduleReport({
    required this.weekStart,
    required this.weekEnd,
    required this.days,
    required this.summary,
  });

  final DateTime weekStart;
  final DateTime weekEnd;
  final List<CashScheduleDay> days;
  final CashScheduleSummary summary;
}

class CashScheduleLoadResult {
  const CashScheduleLoadResult({
    required this.sessions,
    required this.fromCache,
    required this.queries,
    required this.totalMilliseconds,
  });

  final List<CashSession> sessions;
  final bool fromCache;
  final int queries;
  final int totalMilliseconds;
}

CashScheduleReport buildCashScheduleReport({
  required DateTime weekStart,
  required Iterable<CashSession> sessions,
  DateTime? now,
}) {
  final start = startOfCashScheduleWeek(weekStart);
  final end = start.add(const Duration(days: 6));
  final grouped = <String, List<CashSession>>{};
  for (final session in sessions) {
    final parsed = parseBusinessDate(session.businessDate);
    if (parsed == null || parsed.isBefore(start) || parsed.isAfter(end)) {
      continue;
    }
    grouped.putIfAbsent(session.businessDate, () => []).add(session);
  }

  final days = List<CashScheduleDay>.generate(7, (index) {
    final date = start.add(Duration(days: index));
    final key = businessDateKey(date);
    final daySessions = [...grouped[key] ?? const <CashSession>[]]
      ..sort((a, b) {
        final aDate = a.openedAt ?? a.createdAt ?? DateTime(0);
        final bDate = b.openedAt ?? b.createdAt ?? DateTime(0);
        return aDate.compareTo(bDate);
      });
    return CashScheduleDay(
      date: date,
      weekdayName: _weekdayNames[index],
      businessDate: key,
      sessions: daySessions,
    );
  });

  final inRange = days.expand((day) => day.sessions).toList();
  final openingMinutes = <int>[];
  final closingMinutes = <int>[];
  final durations = <Duration>[];
  var pending = 0;
  var incomplete = 0;
  final current = now ?? DateTime.now();

  for (final session in inRange) {
    final openedAt = reliableCashSessionOpenedAt(session);
    final closedAt = reliableCashSessionClosedAt(session);
    if (openedAt != null) {
      openingMinutes.add(_relativeMinutes(session.businessDate, openedAt));
    }
    if (closedAt != null) {
      closingMinutes.add(_relativeMinutes(session.businessDate, closedAt));
    }
    final duration = cashSessionDuration(session, now: current);
    if (openedAt != null && closedAt != null && duration != null) {
      durations.add(duration);
    }
    if (session.isOpen) pending++;
    if (openedAt == null || (!session.isOpen && closedAt == null)) {
      incomplete++;
    }
  }

  return CashScheduleReport(
    weekStart: start,
    weekEnd: end,
    days: days,
    summary: CashScheduleSummary(
      daysWithOpening: days.where((day) => day.hasOperation).length,
      daysWithoutOperation: days.where((day) => !day.hasOperation).length,
      averageOpeningMinutes: _averageInt(openingMinutes),
      averageClosingMinutes: _averageInt(closingMinutes),
      averageDuration: _averageDuration(durations),
      pendingSessions: pending,
      incompleteSessions: incomplete,
    ),
  );
}

String cashScheduleOpeningLabel(CashSession session) {
  final openedAt = reliableCashSessionOpenedAt(session);
  if (openedAt != null) return formatCashLocalTime(openedAt);
  final estimated = estimatedHistoricalCashSessionOpenedAt(session);
  if (estimated != null) {
    return '${formatCashLocalTime(estimated)} (estimada)';
  }
  return 'Sin apertura';
}

String cashScheduleClosingLabel(CashSession session) {
  if (session.isOpen) return 'Pendiente';
  final closedAt = reliableCashSessionClosedAt(session);
  return closedAt == null ? 'No registrada' : formatCashLocalTime(closedAt);
}

String cashScheduleStatusLabel(CashSession session) {
  if (session.isOpen) return 'Abierta';
  if (session.status == 'closed' || session.closedAt != null) return 'Cerrada';
  return session.status.isEmpty ? 'Sin estado' : session.status;
}

String cashScheduleObservation(CashScheduleDay day, {DateTime? now}) {
  if (!day.hasOperation) return 'Sin operación';
  if (day.hasMultipleSessions) {
    return 'Se encontraron varias sesiones de caja para el mismo día operativo.';
  }
  final session = day.sessions.first;
  if (session.isOpen) return 'Caja todavía abierta';
  final openedAt = reliableCashSessionOpenedAt(session);
  final estimatedOpening = estimatedHistoricalCashSessionOpenedAt(session);
  final closedAt = reliableCashSessionClosedAt(session);
  if (openedAt == null && estimatedOpening == null) {
    return 'Información histórica incompleta';
  }
  if (closedAt == null) return 'Cierre no registrado';
  if (openedAt == null) return 'Apertura histórica estimada';
  final openedLocal = mexicoCityDateTime(openedAt);
  final closedLocal = mexicoCityDateTime(closedAt);
  final openedDate = DateTime(
    openedLocal.year,
    openedLocal.month,
    openedLocal.day,
  );
  final closedDate = DateTime(
    closedLocal.year,
    closedLocal.month,
    closedLocal.day,
  );
  if (closedDate.isAfter(openedDate)) {
    return 'Cerró al día calendario siguiente';
  }
  return 'Sin observaciones';
}

int _relativeMinutes(String businessDate, DateTime instant) {
  final businessDay = parseBusinessDate(businessDate);
  if (businessDay == null) return 0;
  final local = mexicoCityDateTime(instant);
  final localDate = DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
  );
  final start = DateTime.utc(
    businessDay.year,
    businessDay.month,
    businessDay.day,
  );
  return localDate.difference(start).inMinutes;
}

int? _averageInt(List<int> values) {
  if (values.isEmpty) return null;
  return (values.reduce((a, b) => a + b) / values.length).round();
}

Duration? _averageDuration(List<Duration> values) {
  if (values.isEmpty) return null;
  final totalMinutes = values.fold<int>(
    0,
    (sum, duration) => sum + duration.inMinutes,
  );
  return Duration(minutes: (totalMinutes / values.length).round());
}

String _formatAverageClockMinutes(int? minutes) {
  if (minutes == null) return 'No disponible';
  final normalized = minutes.remainder(24 * 60);
  final hour24 = normalized ~/ 60;
  final minute = normalized.remainder(60);
  final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final period = hour24 < 12 ? 'a. m.' : 'p. m.';
  return '$hour:${minute.toString().padLeft(2, '0')} $period';
}
