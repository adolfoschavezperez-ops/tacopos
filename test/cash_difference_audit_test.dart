import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/cash_difference_audit.dart';
import 'package:tacopos/models/cash_session.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/payment.dart';

void main() {
  group('buildCashDifferenceAuditReport', () {
    test('audits a closed cash session without changing close formulas', () {
      final session = _session();
      final orders = [
        _order(
          id: 'card-candidate-order',
          label: '#103',
          netTotal: 660,
          total: 660,
        ),
        _order(id: 'card-pos-order', label: '#100', netTotal: 132, total: 132),
        _order(id: 'net-zero-1', label: 'Mesa 2', netTotal: 0, total: 88),
        _order(id: 'net-zero-2', label: 'Mesa 4-A', netTotal: 0, total: 102),
        _order(
          id: 'cash-change-order',
          label: 'Mesa 1',
          netTotal: 100,
          total: 100,
        ),
      ];
      final report = buildCashDifferenceAuditReport(
        session: session,
        orders: orders,
        payments: [
          _input(
            _payment(
              id: 'cash-as-card-candidate',
              orderId: 'card-candidate-order',
              method: 'cash',
              amount: 660,
            ),
          ),
          _input(
            _payment(
              id: 'card-pos-payment',
              orderId: 'card-pos-order',
              method: 'card',
              amount: 132,
            ),
          ),
          _input(
            _payment(
              id: 'net-zero-payment-1',
              orderId: 'net-zero-1',
              method: 'cash',
              amount: 88,
            ),
          ),
          _input(
            _payment(
              id: 'net-zero-payment-2',
              orderId: 'net-zero-2',
              method: 'cash',
              amount: 102,
            ),
          ),
          _input(
            _payment(
              id: 'received-change',
              orderId: 'cash-change-order',
              method: 'cash',
              amount: 100,
              received: 200,
              change: 100,
            ),
          ),
        ],
      );

      expect(report.cashPos, closeTo(2965.4, 0.001));
      expect(report.countedCashLessOpening, closeTo(3052, 0.001));
      expect(report.cashDifference, closeTo(86.6, 0.001));
      expect(report.cardDifference, closeTo(660.76, 0.001));
      expect(report.activeCardPayments, closeTo(132, 0.001));
      expect(report.activeCashPayments, closeTo(950, 0.001));
      expect(report.cardCandidates.first.paymentId, 'cash-as-card-candidate');
      expect(report.cardCandidates.first.confidence, 'Alto');
      expect(
        report.findings
            .where((row) => row.type == 'Clasificacion')
            .single
            .reducesGlobalDifference,
        'No',
      );
      expect(report.cashCandidates, isNotEmpty);
      expect(report.changeIssues, isEmpty);
    });

    test('separates cancelled, excluded, tips and date/session issues', () {
      final session = _session();
      final report = buildCashDifferenceAuditReport(
        session: session,
        orders: [
          _order(id: 'after-midnight', label: 'Mesa 1'),
          _order(id: 'cancelled-order', label: 'Mesa 3'),
          _order(id: 'wrong-session-order', label: 'Mesa 4'),
          _order(
            id: 'missing-business-date-order',
            label: 'Mesa 5',
            businessDate: '',
          ),
        ],
        payments: [
          _input(
            _payment(
              id: 'after-midnight-payment',
              orderId: 'after-midnight',
              amount: 87,
              createdAt: DateTime(2026, 7, 28, 5),
            ),
          ),
          _input(
            _payment(
              id: 'cancelled-payment',
              orderId: 'cancelled-order',
              amount: 50,
              status: 'cancelled',
              cancelledAt: DateTime(2026, 7, 28, 4),
            ),
          ),
          _input(
            _payment(
              id: 'wrong-session-payment',
              orderId: 'wrong-session-order',
              amount: 40,
              cashSessionId: 'other-session',
            ),
          ),
          _input(
            _payment(
              id: 'tip-payment',
              orderId: 'after-midnight',
              method: 'Tarjeta',
              amount: 25,
            ),
            tipAmount: 12,
          ),
          _input(
            _payment(
              id: 'missing-date-payment',
              orderId: 'missing-business-date-order',
              amount: 30,
              businessDate: '',
            ),
          ),
        ],
      );

      expect(
        report.activePayments.map((row) => row.paymentId),
        containsAll(['after-midnight-payment', 'tip-payment']),
      );
      expect(report.cancelledPayments.single.paymentId, 'cancelled-payment');
      expect(
        report.excludedPayments.map((row) => row.paymentId),
        contains('wrong-session-payment'),
      );
      expect(report.tipCandidates.single.amount, 12);
      expect(
        report.inconsistencies.map((row) => row.paymentId),
        contains('missing-date-payment'),
      );
      expect(report.activeCardPayments, closeTo(25, 0.001));
    });

    test('flags cash received and change mismatches only when captured', () {
      final report = buildCashDifferenceAuditReport(
        session: _session(),
        orders: [_order(id: 'cash-order', label: 'Mesa 7')],
        payments: [
          _input(
            _payment(
              id: 'bad-change',
              orderId: 'cash-order',
              amount: 100,
              received: 150,
              change: 20,
            ),
          ),
          _input(
            _payment(
              id: 'zero-defaults',
              orderId: 'cash-order',
              amount: 90,
              received: 0,
              change: 0,
            ),
          ),
        ],
      );

      expect(report.changeIssues.single.paymentId, 'bad-change');
    });

    test('card fee stays outside sale amount in cash audit payments', () {
      final report = buildCashDifferenceAuditReport(
        session: _session(),
        orders: [_order(id: 'card-fee-order', label: '#104', total: 100)],
        payments: [
          _input(
            _payment(
              id: 'card-fee-payment',
              orderId: 'card-fee-order',
              method: 'card',
              amount: 100,
              chargedAmount: 104,
              cardFee: 4,
            ),
          ),
        ],
      );

      expect(report.activePayments.single.amountForAudit, 100);
      expect(report.activeCardPayments, 100);
      expect(report.orders.single.paymentVsNetDifference, 0);
    });

    test('tip stays outside sale amount in cash audit payments', () {
      final report = buildCashDifferenceAuditReport(
        session: _session(),
        orders: [_order(id: 'tip-order', label: 'Mesa 9', total: 100)],
        payments: [
          _input(
            _payment(
              id: 'tip-payment',
              orderId: 'tip-order',
              amount: 100,
              chargedAmount: 120,
            ),
            tipAmount: 20,
          ),
        ],
      );

      expect(report.activePayments.single.amountForAudit, 100);
      expect(report.tipCandidates.single.amount, 20);
      expect(report.orders.single.paymentVsNetDifference, 0);
    });

    test('cancelled order without payments has no monetary impact', () {
      final report = buildCashDifferenceAuditReport(
        session: _session(),
        orders: [
          _order(
            id: 'cancelled-160',
            label: 'Mesa 3',
            total: 160,
            netTotal: 160,
            status: 'cancelled',
            paymentStatus: 'pending',
          ),
        ],
        payments: const [],
      );

      final row = report.orders.single;
      expect(row.countsForSales, isFalse);
      expect(row.netTotal, 0);
      expect(row.activePaymentTotal, 0);
      expect(row.calculatedPendingTotal, 0);
      expect(row.paymentVsNetDifference, 0);
      expect(row.observation, 'Cancelada - Sin impacto monetario');
      expect(report.netSales, 0);
      expect(report.orderLedgerDifference, 0);
    });

    test(
      'cancelled order with cancelled historical payments has no impact',
      () {
        final report = buildCashDifferenceAuditReport(
          session: _session(),
          orders: [
            _order(
              id: 'cancelled-with-payment',
              label: 'Mesa 3',
              total: 160,
              netTotal: 160,
              status: 'cancelled',
              paymentStatus: 'cancelled',
            ),
          ],
          payments: [
            _input(
              _payment(
                id: 'historical-cancelled',
                orderId: 'cancelled-with-payment',
                amount: 160,
                status: 'cancelled',
                cancelledAt: DateTime(2026, 7, 28, 4),
              ),
            ),
          ],
        );

        final row = report.orders.single;
        expect(row.netTotal, 0);
        expect(row.activePaymentTotal, 0);
        expect(row.calculatedPendingTotal, 0);
        expect(row.paymentVsNetDifference, 0);
        expect(row.observation, 'Cancelada - Sin impacto monetario');
        expect(report.activePaymentTotal, 0);
        expect(
          report.cancelledPayments.single.paymentId,
          'historical-cancelled',
        );
      },
    );

    test('cancelled order with active payment does not contaminate totals', () {
      final report = buildCashDifferenceAuditReport(
        session: _session(),
        orders: [
          _order(
            id: 'cancelled-active-payment',
            label: 'Mesa 3',
            total: 160,
            netTotal: 160,
            status: 'cancelled',
            paymentStatus: 'pending',
          ),
        ],
        payments: [
          _input(
            _payment(
              id: 'active-but-cancelled-order',
              orderId: 'cancelled-active-payment',
              amount: 160,
              status: 'active',
            ),
          ),
        ],
      );

      final row = report.orders.single;
      expect(row.netTotal, 0);
      expect(row.activePaymentTotal, 0);
      expect(row.paymentVsNetDifference, 0);
      expect(report.activePaymentTotal, 0);
      expect(
        report.excludedPayments.single.paymentId,
        'active-but-cancelled-order',
      );
      expect(report.netSales, 0);
      expect(report.paymentNetDifference, 0);
      expect(report.cashCandidates, isEmpty);
      expect(report.cardCandidates, isEmpty);
      expect(report.changeIssues, isEmpty);
    });

    test('global difference subtracts approved withdrawals from valid net', () {
      final report = buildCashDifferenceAuditReport(
        session: _session(
          countedCashAmount: 4790,
          terminalReportedAmount: 2068,
          expectedCashAmount: 5247,
          expectedCardChargedAmount: 1895.4,
          approvedWithdrawalsTotal: 420,
        ),
        orders: [
          _order(
            id: 'sales',
            label: 'Mesa 1',
            total: 6960.40,
            netTotal: 6960.40,
          ),
        ],
        payments: [
          _input(_payment(id: 'cash', orderId: 'sales', amount: 5167)),
          _input(
            _payment(
              id: 'card',
              orderId: 'sales',
              method: 'card',
              amount: 1895.40,
            ),
          ),
        ],
      );

      expect(report.observedMoney, 6358);
      expect(report.expectedPhysicalMoney, 6540.40);
      expect(report.globalDifference, closeTo(-182.40, 0.001));
    });

    test('active payments greater than net creates data finding', () {
      final report = buildCashDifferenceAuditReport(
        session: _session(
          countedCashAmount: 4790,
          terminalReportedAmount: 2068,
          expectedCashAmount: 5247,
          expectedCardChargedAmount: 1895.4,
          approvedWithdrawalsTotal: 420,
        ),
        orders: [
          _order(
            id: 'mesa-4',
            label: 'Mesa 4',
            total: 6960.40,
            netTotal: 6960.40,
          ),
        ],
        payments: [
          _input(_payment(id: 'cash', orderId: 'mesa-4', amount: 5167)),
          _input(
            _payment(
              id: 'card',
              orderId: 'mesa-4',
              method: 'card',
              amount: 1895.40,
            ),
          ),
        ],
      );

      expect(report.activePaymentTotal, 7062.40);
      expect(report.paymentNetDifference, closeTo(102, 0.001));
      final finding = report.findings
          .where(
            (row) => row.finding == 'Los pagos activos exceden la venta neta',
          )
          .single;
      expect(finding.amount, closeTo(102, 0.001));
      expect(finding.type, 'Datos');
      expect(finding.reducesGlobalDifference, 'No');
    });
  });
}

CashSession _session({
  double countedCashAmount = 3552,
  double terminalReportedAmount = 941.76,
  double expectedCashAmount = 3465.4,
  double expectedCardChargedAmount = 281,
  double approvedWithdrawalsTotal = 0,
}) {
  final cashDifference =
      countedCashAmount -
      500 -
      (expectedCashAmount - 500 + approvedWithdrawalsTotal);
  final cardDifference = terminalReportedAmount - expectedCardChargedAmount;
  final netDifference = cashDifference + cardDifference;
  return CashSession(
    id: 'NkTSfERJPJb0hbRhrStH',
    businessDate: '2026-07-27',
    status: 'closed',
    openingCashAmount: 500,
    openedByEmployeeId: 'employee-1',
    openedByEmployeeName: 'Gael Pineda',
    countedCashAmount: countedCashAmount,
    terminalReportedAmount: terminalReportedAmount,
    expectedCashAmount: expectedCashAmount,
    expectedCardChargedAmount: expectedCardChargedAmount,
    expectedCardBaseAmount: 430,
    expectedCardSurchargeAmount: 0,
    expectedCardFeeAbsorbedAmount: 11.4086,
    expectedPlatformAmount: 0,
    expectedEmployeeConsumptionAmount: 0,
    totalExpectedRealMoney: expectedCashAmount + expectedCardChargedAmount,
    totalCountedRealMoney: countedCashAmount + terminalReportedAmount,
    cashDifference: cashDifference,
    cardDifference: cardDifference,
    netDifference: netDifference,
    shortageAmount: netDifference < 0 ? netDifference.abs() : 0,
    overAmount: netDifference > 0 ? netDifference : 0,
    approvedWithdrawalsTotal: approvedWithdrawalsTotal,
    pendingWithdrawalsTotal: 0,
    withdrawalRequestCount: 0,
    notes: '',
    branchId: 'aviacion',
    branchName: 'Aviacion',
  );
}

PosOrder _order({
  required String id,
  required String label,
  double netTotal = 100,
  double total = 100,
  String businessDate = '2026-07-27',
  String cashSessionId = 'NkTSfERJPJb0hbRhrStH',
  String status = 'paid',
  String paymentStatus = 'paid',
}) {
  return PosOrder(
    id: id,
    tableId: id,
    tableName: label,
    status: status,
    kitchenStatus: 'served',
    paymentStatus: paymentStatus,
    total: total,
    paidTotal: total,
    pendingTotal: 0,
    personNames: const {},
    orderType: label.startsWith('#') ? 'takeout' : 'dine_in',
    takeoutNumber: label.startsWith('#')
        ? int.tryParse(label.replaceFirst('#', ''))
        : null,
    createdAt: DateTime(2026, 7, 28, 2),
    grossSubtotal: total,
    netTotal: netTotal,
    businessDate: businessDate,
    cashSessionId: cashSessionId,
    branchId: 'aviacion',
    branchName: 'Aviacion',
  );
}

CashAuditPaymentInput _input(Payment payment, {double tipAmount = 0}) {
  return CashAuditPaymentInput(
    payment: payment,
    orderId: payment.orderId,
    tipAmount: tipAmount,
  );
}

Payment _payment({
  required String id,
  required String orderId,
  String method = 'cash',
  double amount = 100,
  double? chargedAmount,
  double cardFee = 0,
  String status = 'active',
  String cashSessionId = 'NkTSfERJPJb0hbRhrStH',
  String businessDate = '2026-07-27',
  DateTime? createdAt,
  DateTime? cancelledAt,
  double? received,
  double? change,
}) {
  return Payment(
    id: id,
    orderId: orderId,
    tableId: orderId,
    tableName: orderId,
    type: 'full_table',
    method: method,
    baseAmount: amount,
    surchargeRate: 0,
    surchargeAmount: 0,
    chargedAmount: chargedAmount ?? amount,
    cardFeeAbsorbedAmount: cardFee,
    cashSessionId: cashSessionId,
    businessDate: businessDate,
    cashReceivedAmount: received,
    cashChangeAmount: change,
    status: status,
    cancelledAt: cancelledAt,
    createdAt: createdAt ?? DateTime(2026, 7, 28, 3),
    branchId: 'aviacion',
    branchName: 'Aviacion',
  );
}
