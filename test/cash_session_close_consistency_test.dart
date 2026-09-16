import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/cash/cash_close_execution.dart';
import 'package:tacopos/models/cash_session.dart';

void main() {
  test('recalculo definitivo conserva ventas reales, no ventas cero', () {
    const totals = CashSessionTotals(
      expectedCashAmount: 1110,
      expectedCardChargedAmount: 1035,
      approvedWithdrawalsTotal: 955,
    );

    expect(totals.expectedCashAmount, 110 + 1955 - 955);
    expect(totals.cashDifference(1825), 715);
    expect(totals.cardDifference(1035), 0);
    expect(
      totals.netDifference(
        countedCashAmount: 1825,
        terminalReportedAmount: 1035,
      ),
      715,
    );
  });

  test('sesion closing no es una sesion abierta ni finalizable', () {
    const session = CashSession(
      id: 'closing-session',
      businessDate: '2026-09-07',
      status: 'closing',
      openingCashAmount: 110,
      openedByEmployeeId: 'cashier',
      openedByEmployeeName: 'Cashier',
      countedCashAmount: 0,
      terminalReportedAmount: 0,
      expectedCashAmount: 0,
      expectedCardChargedAmount: 0,
      expectedCardBaseAmount: 0,
      expectedCardSurchargeAmount: 0,
      expectedCardFeeAbsorbedAmount: 0,
      expectedPlatformAmount: 0,
      expectedEmployeeConsumptionAmount: 0,
      totalExpectedRealMoney: 0,
      totalCountedRealMoney: 0,
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

    expect(session.isOpen, isFalse);
    expect(session.isClosing, isTrue);
    expect(
      canFinalizeCashSessionClose(status: session.status, hasClosedAt: false),
      isFalse,
    );
  });

  test('Caja Admin usa lectura puntual server-first y no first del stream', () {
    final source = File(
      'lib/screens/admin/cash_admin_screen.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/services/taco_pos_repository.dart',
    ).readAsStringSync();
    final rules = File('firestore.rules').readAsStringSync();

    expect(source, contains('getCashSessionTotalsForCloseOrAudit(session.id)'));
    expect(source, isNot(contains('watchCashSessionTotals(session.id).first')));
    expect(
      repository,
      contains(".where('cashSessionId', isEqualTo: cashSessionId)"),
    );
    expect(repository, contains('GetOptions(source: Source.server)'));
    expect(rules, contains('cashSessionAcceptsMonetaryWrite'));
    expect(rules, contains(".data.status == 'open'"));
  });
}
