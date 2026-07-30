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
  });
}

CashSession _session() {
  return const CashSession(
    id: 'NkTSfERJPJb0hbRhrStH',
    businessDate: '2026-07-27',
    status: 'closed',
    openingCashAmount: 500,
    openedByEmployeeId: 'employee-1',
    openedByEmployeeName: 'Gael Pineda',
    countedCashAmount: 3552,
    terminalReportedAmount: 941.76,
    expectedCashAmount: 3465.4,
    expectedCardChargedAmount: 281,
    expectedCardBaseAmount: 430,
    expectedCardSurchargeAmount: 0,
    expectedCardFeeAbsorbedAmount: 11.4086,
    expectedPlatformAmount: 0,
    expectedEmployeeConsumptionAmount: 0,
    totalExpectedRealMoney: 3746.4,
    totalCountedRealMoney: 4493.76,
    cashDifference: 86.6,
    cardDifference: 660.76,
    netDifference: 747.36,
    shortageAmount: 0,
    overAmount: 747.36,
    approvedWithdrawalsTotal: 0,
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
}) {
  return PosOrder(
    id: id,
    tableId: id,
    tableName: label,
    status: status,
    kitchenStatus: 'served',
    paymentStatus: 'paid',
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
    chargedAmount: amount,
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
