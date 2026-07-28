import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/cash/cash_session_timing.dart';
import 'package:tacopos/core/reports/cash_schedule_report.dart';
import 'package:tacopos/core/reports/cash_schedule_report_excel.dart';
import 'package:tacopos/models/cash_session.dart';

void main() {
  group('timestamps de caja', () {
    test('openedAt se asigna una sola vez al crear la sesión', () {
      final token = Object();
      final fields = cashSessionOpenTimestampFields(
        serverTimestamp: token,
        employeeId: 'employee-1',
        employeeName: 'Gael',
      );

      expect(fields['openedAt'], same(token));
      expect(fields['openedByEmployeeId'], 'employee-1');
      expect(fields['openedByEmployeeName'], 'Gael');
      expect(fields, isNot(contains('closedAt')));
    });

    test('closedAt se asigna únicamente a una sesión abierta', () {
      final token = Object();
      final fields = cashSessionCloseTimestampFields(
        currentStatus: 'open',
        currentClosedAt: null,
        serverTimestamp: token,
        employeeId: 'employee-1',
        employeeName: 'Gael',
      );

      expect(fields['status'], 'closed');
      expect(fields['closedAt'], same(token));
      expect(fields['updatedAt'], same(token));
    });

    test('un cierre fallido o repetido no produce un nuevo closedAt', () {
      expect(
        () => cashSessionCloseTimestampFields(
          currentStatus: 'closed',
          currentClosedAt: DateTime.utc(2026, 7, 27, 7),
          serverTimestamp: Object(),
          employeeId: 'employee-1',
          employeeName: 'Gael',
        ),
        throwsStateError,
      );
    });

    test('el recálculo histórico conserva apertura, cierre y empleados', () {
      final openedAt = DateTime.utc(2026, 7, 27);
      final closedAt = DateTime.utc(2026, 7, 27, 7);
      final session = _session(
        id: 'historical',
        businessDate: '2026-07-26',
        status: 'closed',
        openedAt: openedAt,
        closedAt: closedAt,
      );

      final fields = preservedHistoricalCashTimestampFields(session);

      expect(fields['openedAt'], openedAt);
      expect(fields['closedAt'], closedAt);
      expect(fields['openedByEmployeeName'], 'Gael');
      expect(fields['closedByEmployeeName'], 'Gael');
    });

    test('un histórico sin timestamps no inventa horas actuales', () {
      final fields = preservedHistoricalCashTimestampFields(
        _session(
          id: 'incomplete',
          businessDate: '2026-07-25',
          status: 'closed',
        ),
      );

      expect(fields, isNot(contains('openedAt')));
      expect(fields, isNot(contains('closedAt')));
    });

    test('horas de una corrección heredada no se presentan como reales', () {
      final correctedAt = DateTime.utc(2026, 7, 27, 18);
      final session = _session(
        id: 'legacy-correction',
        businessDate: '2026-07-20',
        status: 'closed',
        openedAt: DateTime.utc(2026, 7, 20, 6),
        closedAt: correctedAt,
        correctedAt: correctedAt,
        correctionMode: true,
        openedByEmployeeName: 'Correccion admin',
      );

      expect(reliableCashSessionOpenedAt(session), isNull);
      expect(reliableCashSessionClosedAt(session), isNull);
      expect(cashScheduleOpeningLabel(session), 'Sin apertura');
      expect(cashScheduleClosingLabel(session), 'No registrada');
    });
  });

  group('reporte semanal de horarios', () {
    test('la semana se construye de lunes a domingo con siete filas', () {
      final report = buildCashScheduleReport(
        weekStart: DateTime(2026, 7, 23),
        sessions: const [],
      );

      expect(report.weekStart, DateTime(2026, 7, 20));
      expect(report.weekEnd, DateTime(2026, 7, 26));
      expect(report.days, hasLength(7));
      expect(report.days.first.weekdayName, 'Lunes');
      expect(report.days.last.weekdayName, 'Domingo');
      expect(report.summary.daysWithoutOperation, 7);
    });

    test('agrupa por businessDate aunque el cierre cruce medianoche', () {
      final session = _session(
        id: 'midnight',
        businessDate: '2026-07-26',
        status: 'closed',
        openedAt: DateTime.utc(2026, 7, 27),
        closedAt: DateTime.utc(2026, 7, 27, 7),
      );
      final report = buildCashScheduleReport(
        weekStart: DateTime(2026, 7, 20),
        sessions: [session],
      );
      final sunday = report.days.last;

      expect(sunday.businessDate, '2026-07-26');
      expect(sunday.sessions.single.id, 'midnight');
      expect(cashScheduleOpeningLabel(session), '6:00 p. m.');
      expect(cashScheduleClosingLabel(session), '1:00 a. m.');
      expect(cashSessionDuration(session), const Duration(hours: 7));
      expect(
        cashScheduleObservation(sunday),
        'Cerró al día calendario siguiente',
      );
    });

    test(
      'una caja abierta aparece pendiente y calcula duración hasta ahora',
      () {
        final session = _session(
          id: 'open',
          businessDate: '2026-07-26',
          status: 'open',
          openedAt: DateTime.utc(2026, 7, 27),
        );
        final report = buildCashScheduleReport(
          weekStart: DateTime(2026, 7, 20),
          sessions: [session],
          now: DateTime.utc(2026, 7, 27, 3, 12),
        );

        expect(cashScheduleClosingLabel(session), 'Pendiente');
        expect(report.summary.pendingSessions, 1);
        expect(
          cashSessionDuration(session, now: DateTime.utc(2026, 7, 27, 3, 12)),
          const Duration(hours: 3, minutes: 12),
        );
        expect(
          cashScheduleObservation(report.days.last),
          'Caja todavía abierta',
        );
      },
    );

    test('el histórico incompleto no inventa una hora de cierre', () {
      final session = _session(
        id: 'legacy',
        businessDate: '2026-07-25',
        status: 'closed',
        createdAt: DateTime.utc(2026, 7, 26),
      );
      final report = buildCashScheduleReport(
        weekStart: DateTime(2026, 7, 20),
        sessions: [session],
      );

      expect(cashScheduleOpeningLabel(session), '6:00 p. m. (estimada)');
      expect(cashScheduleClosingLabel(session), 'No registrada');
      expect(report.summary.incompleteSessions, 1);
      expect(report.summary.averageClosingMinutes, isNull);
    });

    test('los promedios usan minutos relativos e ignoran incompletos', () {
      final sessions = [
        _session(
          id: 'one',
          businessDate: '2026-07-20',
          status: 'closed',
          openedAt: DateTime.utc(2026, 7, 21),
          closedAt: DateTime.utc(2026, 7, 21, 7),
        ),
        _session(
          id: 'two',
          businessDate: '2026-07-21',
          status: 'closed',
          openedAt: DateTime.utc(2026, 7, 22, 0, 16),
          closedAt: DateTime.utc(2026, 7, 22, 7, 6),
        ),
        _session(
          id: 'incomplete',
          businessDate: '2026-07-22',
          status: 'closed',
        ),
      ];
      final report = buildCashScheduleReport(
        weekStart: DateTime(2026, 7, 20),
        sessions: sessions,
      );

      expect(report.summary.averageOpeningLabel, '6:08 p. m.');
      expect(report.summary.averageClosingLabel, '1:03 a. m.');
      expect(report.summary.averageDurationLabel, '6 h 55 min');
      expect(report.summary.incompleteSessions, 1);
    });

    test('detecta varias sesiones sin mezclar sus horarios', () {
      final report = buildCashScheduleReport(
        weekStart: DateTime(2026, 7, 20),
        sessions: [
          _session(
            id: 'first',
            businessDate: '2026-07-24',
            status: 'closed',
            openedAt: DateTime.utc(2026, 7, 25),
            closedAt: DateTime.utc(2026, 7, 25, 2),
          ),
          _session(
            id: 'second',
            businessDate: '2026-07-24',
            status: 'closed',
            openedAt: DateTime.utc(2026, 7, 25, 3),
            closedAt: DateTime.utc(2026, 7, 25, 7),
          ),
        ],
      );
      final friday = report.days[4];

      expect(friday.hasMultipleSessions, isTrue);
      expect(friday.singleSession, isNull);
      expect(
        cashScheduleObservation(friday),
        contains('varias sesiones de caja'),
      );
    });

    test('el Excel contiene siete días, resumen, filtro y fila congelada', () {
      final report = buildCashScheduleReport(
        weekStart: DateTime(2026, 7, 20),
        sessions: [
          _session(
            id: 'sunday',
            businessDate: '2026-07-26',
            status: 'closed',
            openedAt: DateTime.utc(2026, 7, 27),
            closedAt: DateTime.utc(2026, 7, 27, 7),
          ),
        ],
      );
      final bytes = buildCashScheduleWorkbook(
        report: report,
        restaurantName: "Los Padrino's Tacos",
        branchName: 'Aviación',
      );
      final workbook = Excel.decodeBytes(bytes);
      final detail = workbook['Horarios de caja'];

      expect(workbook.tables.keys, contains('Resumen semanal'));
      expect(detail.maxRows, 8);
      expect(
        detail.rows.skip(1).map((row) => row[1]?.value.toString()),
        hasLength(7),
      );

      final archive = ZipDecoder().decodeBytes(bytes);
      final sheetXml = archive.files.firstWhere(
        (file) => file.name == 'xl/worksheets/sheet1.xml',
      );
      final xml = utf8.decode(sheetXml.content as List<int>);
      expect(xml, contains('state="frozen"'));
      expect(xml, contains('<autoFilter ref="A1:M8"/>'));
    });
  });
}

CashSession _session({
  required String id,
  required String businessDate,
  required String status,
  DateTime? openedAt,
  DateTime? closedAt,
  DateTime? createdAt,
  DateTime? correctedAt,
  bool correctionMode = false,
  String openedByEmployeeName = 'Gael',
}) {
  return CashSession(
    id: id,
    businessDate: businessDate,
    status: status,
    openingCashAmount: 1000,
    openedAt: openedAt,
    openedByEmployeeId: 'employee-1',
    openedByEmployeeName: openedByEmployeeName,
    closedAt: closedAt,
    closedByEmployeeId: closedAt == null ? null : 'employee-1',
    closedByEmployeeName: closedAt == null ? null : 'Gael',
    createdAt: createdAt,
    correctedAt: correctedAt,
    correctionMode: correctionMode,
    countedCashAmount: 900,
    terminalReportedAmount: 500,
    expectedCashAmount: 900,
    expectedCardChargedAmount: 500,
    expectedCardBaseAmount: 500,
    expectedCardSurchargeAmount: 0,
    expectedCardFeeAbsorbedAmount: 0,
    expectedPlatformAmount: 0,
    expectedEmployeeConsumptionAmount: 0,
    totalExpectedRealMoney: 1400,
    totalCountedRealMoney: 1400,
    cashDifference: 0,
    cardDifference: 0,
    netDifference: 0,
    shortageAmount: 0,
    overAmount: 0,
    approvedWithdrawalsTotal: 0,
    pendingWithdrawalsTotal: 0,
    withdrawalRequestCount: 0,
    notes: '',
  );
}
