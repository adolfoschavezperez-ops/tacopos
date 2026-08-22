import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/expenses/expense_cutoff_reminder.dart';

void main() {
  group('expense cutoff reminder', () {
    test('cutoff 22:30 dispara 15/10/5 una vez y nada en cutoff', () {
      final shown = <String>{};

      expect(_decision('2026-08-22 22:14', shown: shown), isNull);

      final at15 = _decision('2026-08-22 22:15', shown: shown);
      expect(at15?.thresholdMinutes, 15);
      shown.add(at15!.storageKey);

      expect(_decision('2026-08-22 22:16', shown: shown), isNull);

      final at10 = _decision('2026-08-22 22:20', shown: shown);
      expect(at10?.thresholdMinutes, 10);
      shown.add(at10!.storageKey);

      final at5 = _decision('2026-08-22 22:25', shown: shown);
      expect(at5?.thresholdMinutes, 5);
      shown.add(at5!.storageKey);

      expect(_decision('2026-08-22 22:30', shown: shown), isNull);
    });

    test('OK en 15 permite mostrar 10 y 5', () {
      final shown = <String>{};
      final at15 = _decision('2026-08-22 22:15', shown: shown)!;
      shown.add(at15.storageKey);

      final at10 = _decision('2026-08-22 22:20', shown: shown)!;
      expect(at10.thresholdMinutes, 10);
      shown.add(at10.storageKey);

      final at5 = _decision('2026-08-22 22:25', shown: shown)!;
      expect(at5.thresholdMinutes, 5);
    });

    test(
      'No volver suprime restantes, persiste y vuelve siguiente businessDate',
      () {
        final at15 = _decision('2026-08-22 22:15')!;
        final suppressed = {_baseKey(at15.storageKey)};

        expect(_decision('2026-08-22 22:20', suppressed: suppressed), isNull);
        expect(_decision('2026-08-22 22:25', suppressed: suppressed), isNull);
        expect(_decision('2026-08-22 22:20', suppressed: suppressed), isNull);

        final nextDay = _decision(
          '2026-08-23 22:15',
          businessDate: '2026-08-23',
          suppressed: suppressed,
        );
        expect(nextDay?.thresholdMinutes, 15);
      },
    );

    test('supresion es independiente por empleado y permiso caja', () {
      final employeeA = _decision('2026-08-22 22:15', employeeId: 'A')!;
      final suppressed = {_baseKey(employeeA.storageKey)};

      expect(
        _decision('2026-08-22 22:20', employeeId: 'A', suppressed: suppressed),
        isNull,
      );
      expect(
        _decision(
          '2026-08-22 22:20',
          employeeId: 'B',
          suppressed: suppressed,
        )?.thresholdMinutes,
        10,
      );
      expect(
        _decision('2026-08-22 22:20', employeeId: 'C', cashPermission: false),
        isNull,
      );
    });

    test('resume 22:23 muestra solo el recordatorio relevante de 10', () {
      final decision = _decision('2026-08-22 22:23');
      expect(decision?.thresholdMinutes, 10);
    });

    test('cutoff cambiado recalcula thresholds con la nueva hora', () {
      final oldDecision = _decision('2026-08-22 22:15', cutoffTime: '22:30')!;
      final shown = {oldDecision.storageKey};

      expect(
        _decision('2026-08-22 22:15', cutoffTime: '23:00', shown: shown),
        isNull,
      );
      expect(
        _decision(
          '2026-08-22 22:45',
          cutoffTime: '23:00',
          shown: shown,
        )?.thresholdMinutes,
        15,
      );
    });

    test('cutoff 00:10 usa el dia operativo y cruza medianoche', () {
      expect(
        _decision(
          '2026-08-22 23:55',
          businessDate: '2026-08-22',
          cutoffTime: '00:10',
        )?.thresholdMinutes,
        15,
      );
      expect(
        _decision(
          '2026-08-23 00:00',
          businessDate: '2026-08-22',
          cutoffTime: '00:10',
        )?.thresholdMinutes,
        10,
      );
      expect(
        _decision(
          '2026-08-23 00:05',
          businessDate: '2026-08-22',
          cutoffTime: '00:10',
        )?.thresholdMinutes,
        5,
      );
    });
  });
}

String _baseKey(String storageKey) {
  final splitAt = storageKey.lastIndexOf('|');
  return splitAt < 0 ? storageKey : storageKey.substring(0, splitAt);
}

ExpenseCutoffReminderDecision? _decision(
  String now, {
  String businessDate = '2026-08-22',
  String cutoffTime = '22:30',
  String employeeId = 'employee-a',
  bool cashPermission = true,
  Set<String> shown = const {},
  Set<String> suppressed = const {},
}) {
  return nextExpenseCutoffReminder(
    ExpenseCutoffReminderInput(
      restaurantId: 'main_restaurant',
      branchId: 'aviacion',
      employeeId: employeeId,
      businessDate: businessDate,
      cutoffTime: cutoffTime,
      now: DateTime.parse(now.replaceFirst(' ', 'T')),
      hasCashPermission: cashPermission,
      shownKeys: shown,
      suppressedKeys: suppressed,
    ),
  );
}
