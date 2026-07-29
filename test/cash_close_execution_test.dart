import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
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
      expect(guard.stage, CashCloseProgressStage.validatingOrders);

      guard.markSaving();
      expect(guard.stage, CashCloseProgressStage.updatingCashSession);

      guard.markStage(CashCloseProgressStage.registeringActivityLog);
      expect(guard.stage, CashCloseProgressStage.registeringActivityLog);

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

  group('cash close error messages', () {
    test('maps permission denied without calling it a connection issue', () {
      final message = cashCloseErrorMessage(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Missing or insufficient permissions.',
        ),
      );

      expect(message, contains('No tienes permiso para grabar el corte'));
      expect(message, isNot(contains('conexion')));
    });

    test('maps unavailable to the connection message', () {
      final message = cashCloseErrorMessage(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
          message: 'Service unavailable.',
        ),
      );

      expect(message, contains('No hay conexion con Firebase'));
    });

    test('maps not-found to the session-specific message', () {
      final message = cashCloseErrorMessage(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'not-found',
          message: 'Document not found.',
        ),
      );

      expect(
        message,
        'No se encontro la sesion de caja que se intento cerrar.',
      );
    });

    test('unwraps cash close diagnostics before presenting the message', () {
      final message = cashCloseErrorMessage(
        CashCloseException(
          stage: CashCloseProgressStage.updatingCashSession,
          operation: 'update_cash_session',
          documentPath: 'restaurants/tacopos/cashSessions/cash-1',
          cause: FirebaseException(
            plugin: 'cloud_firestore',
            code: 'failed-precondition',
            message: 'Index missing.',
          ),
          stackTrace: StackTrace.empty,
        ),
      );

      expect(message, contains('configuracion o indice requerido'));
    });
  });

  group('cash close amount serialization guard', () {
    test('accepts real case finite amounts', () {
      expect(isValidCashCloseAmount(4136), isTrue);
      expect(isValidCashCloseAmount(557), isTrue);
    });

    test('rejects non serializable monetary values', () {
      expect(isValidCashCloseAmount(double.nan), isFalse);
      expect(isValidCashCloseAmount(double.infinity), isFalse);
      expect(isValidCashCloseAmount(double.negativeInfinity), isFalse);
      expect(isValidCashCloseAmount(-1), isFalse);
    });
  });

  testWidgets('progress modal updates stage and blocks dismiss actions', (
    tester,
  ) async {
    final stage = ValueNotifier(CashCloseProgressStage.validatingOrders);
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
    expect(find.text('Validando ordenes abiertas'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(find.text('Validando ordenes abiertas'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Validando ordenes abiertas'), findsOneWidget);

    stage.value = CashCloseProgressStage.updatingCashSession;
    await tester.pump();
    expect(find.text('Grabando sesion de caja'), findsOneWidget);
    expect(find.text('Grabando sesion de caja...'), findsOneWidget);

    Navigator.of(hostContext, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    stage.dispose();
  });
}
