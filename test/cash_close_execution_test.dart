import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/cash/cash_close_execution.dart';
import 'package:tacopos/widgets/cash_close_progress_dialog.dart';

void main() {
  group('CashCloseExecutionGuard', () {
    test('ignores repeated attempts while a close is active', () async {
      final guard = CashCloseExecutionGuard();
      final operation = Completer<void>();
      var executions = 0;

      Future<void> closeCash() async {
        if (!guard.tryStart()) {
          return;
        }
        try {
          executions++;
          await operation.future;
        } finally {
          guard.release();
        }
      }

      final firstAttempt = closeCash();
      final repeatedAttempts = [
        closeCash(),
        closeCash(),
        closeCash(),
        closeCash(),
      ];

      expect(executions, 1);
      expect(guard.isActive, isTrue);
      operation.complete();
      await Future.wait([firstAttempt, ...repeatedAttempts]);
      expect(executions, 1);
      expect(guard.isActive, isFalse);
    });

    test('releases state after validation is rejected', () {
      final guard = CashCloseExecutionGuard();

      expect(guard.tryStart(), isTrue);
      guard.release();

      expect(guard.isActive, isFalse);
      expect(guard.tryStart(), isTrue);
    });

    test('releases state after an exception and permits retry', () async {
      final guard = CashCloseExecutionGuard();

      Future<void> failingClose() async {
        if (!guard.tryStart()) {
          return;
        }
        try {
          throw Exception('network unavailable');
        } finally {
          guard.release();
        }
      }

      await expectLater(failingClose(), throwsException);
      expect(guard.isActive, isFalse);
      expect(guard.tryStart(), isTrue);
    });

    test('changes from validating to saving only while active', () {
      final guard = CashCloseExecutionGuard();

      expect(guard.tryStart(), isTrue);
      expect(guard.stage, CashCloseProgressStage.validating);

      guard.markSaving();
      expect(guard.stage, CashCloseProgressStage.saving);

      guard.release();
      expect(guard.stage, isNull);
    });
  });

  group('cash session close idempotency condition', () {
    test('allows only an open session without a close timestamp', () {
      expect(
        canFinalizeCashSessionClose(status: 'open', hasClosedAt: false),
        isTrue,
      );
      expect(
        canFinalizeCashSessionClose(status: 'closed', hasClosedAt: true),
        isFalse,
      );
      expect(
        canFinalizeCashSessionClose(status: 'open', hasClosedAt: true),
        isFalse,
      );
      expect(
        canFinalizeCashSessionClose(status: 'closed', hasClosedAt: false),
        isFalse,
      );
    });
  });

  testWidgets('progress modal updates stage and blocks dismiss actions', (
    tester,
  ) async {
    final stage = ValueNotifier(CashCloseProgressStage.validating);
    late BuildContext hostContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) =>
                        CashCloseProgressDialog(stageListenable: stage),
                  );
                },
                child: const Text('Close cash'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Close cash'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Validando cierre de caja'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(find.text('Validando cierre de caja'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Validando cierre de caja'), findsOneWidget);

    stage.value = CashCloseProgressStage.saving;
    await tester.pump();
    expect(find.text('Grabando corte'), findsOneWidget);
    expect(
      find.text('Espera un momento. Estamos guardando el cierre de caja.'),
      findsOneWidget,
    );

    Navigator.of(hostContext, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    stage.dispose();
  });
}
