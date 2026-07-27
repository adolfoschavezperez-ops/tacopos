import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/cash/operational_business_date.dart';
import 'package:tacopos/models/cash_session.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/payment.dart';

void main() {
  group('dia operativo canonico', () {
    test('orden antes de medianoche y pago posterior pertenecen al 26', () {
      final order = orderFixture(
        businessDate: '2026-07-26',
        cashSessionId: 'session-26',
        createdAt: DateTime(2026, 7, 26, 23, 50),
      );
      final payment = paymentFixture(createdAt: DateTime(2026, 7, 27, 0, 10));

      expect(
        resolveOperationalBusinessDate(order: order, payment: payment),
        '2026-07-26',
      );
    });

    test(
      'orden posterior a medianoche conserva la fecha de la caja abierta',
      () {
        final session = cashSessionFixture(
          id: 'session-26',
          businessDate: '2026-07-26',
        );

        expect(businessDateForOpenCashSession(session), '2026-07-26');
        expect(
          resolveOperationalBusinessDate(
            cashSession: session,
            historicalFallback: DateTime(2026, 7, 27, 0, 20),
          ),
          '2026-07-26',
        );
      },
    );

    test('venta de la sesion 25 no entra en el corte de la sesion 26', () {
      final membership = belongsToOperationalSession(
        order: orderFixture(
          businessDate: '2026-07-25',
          cashSessionId: 'session-25',
        ),
        selectedCashSessionId: 'session-26',
        selectedBusinessDate: '2026-07-26',
        branchId: 'aviacion',
      );

      expect(membership.included, isFalse);
      expect(membership.reason, 'cash_session_mismatch');
    });

    test('sesiones cercanas quedan separadas por cashSessionId', () {
      final session25Order = orderFixture(
        businessDate: '2026-07-25',
        cashSessionId: 'session-25',
        createdAt: DateTime(2026, 7, 26, 0, 1),
      );
      final session26Order = orderFixture(
        businessDate: '2026-07-26',
        cashSessionId: 'session-26',
        createdAt: DateTime(2026, 7, 26, 0, 2),
      );

      expect(
        belongsToOperationalSession(
          order: session25Order,
          selectedCashSessionId: 'session-26',
          selectedBusinessDate: '2026-07-26',
          branchId: 'aviacion',
        ).included,
        isFalse,
      );
      expect(
        belongsToOperationalSession(
          order: session26Order,
          selectedCashSessionId: 'session-26',
          selectedBusinessDate: '2026-07-26',
          branchId: 'aviacion',
        ).included,
        isTrue,
      );
    });

    test('orden historica sin cashSessionId usa businessDate exacto', () {
      final membership = belongsToOperationalSession(
        order: orderFixture(businessDate: '2026-07-26'),
        selectedCashSessionId: 'session-26',
        selectedBusinessDate: '2026-07-26',
        branchId: 'aviacion',
      );

      expect(membership.included, isTrue);
      expect(membership.reason, 'legacy_exact_business_date');
    });

    test('payment sin businessDate hereda la clasificacion de la orden', () {
      final order = orderFixture(
        businessDate: '2026-07-26',
        cashSessionId: 'session-26',
      );

      expect(
        resolveOperationalBusinessDate(
          order: order,
          payment: paymentFixture(createdAt: DateTime(2026, 7, 27, 0, 10)),
        ),
        '2026-07-26',
      );
    });

    test('orden legada sin campos requiere evidencia de pago de la sesion', () {
      final legacyOrder = orderFixture(
        createdAt: DateTime(2026, 7, 26, 22, 58),
      );

      final withoutEvidence = belongsToOperationalSession(
        order: legacyOrder,
        selectedCashSessionId: 'session-26',
        selectedBusinessDate: '2026-07-26',
        branchId: 'aviacion',
      );
      final withEvidence = belongsToOperationalSession(
        order: legacyOrder,
        selectedCashSessionId: 'session-26',
        selectedBusinessDate: '2026-07-26',
        branchId: 'aviacion',
        paymentCashSessionIds: const ['session-26'],
      );

      expect(withoutEvidence.included, isFalse);
      expect(withEvidence.included, isTrue);
      expect(withEvidence.reason, 'legacy_payment_cash_session_match');
    });

    test('un timestamp UTC no mueve la clave operativa al dia anterior', () {
      final order = orderFixture(
        businessDate: '2026-07-26',
        cashSessionId: 'session-26',
        createdAt: DateTime.parse('2026-07-27T05:10:00Z'),
      );

      expect(
        resolveOperationalBusinessDate(
          order: order,
          historicalFallback: order.createdAt,
        ),
        '2026-07-26',
      );
    });

    test('una caja nueva cambia el dia solo despues de cerrar la anterior', () {
      final closed26 = cashSessionFixture(
        id: 'session-26',
        businessDate: '2026-07-26',
        status: 'closed',
        closedAt: DateTime(2026, 7, 27, 1),
      );
      final open27 = cashSessionFixture(
        id: 'session-27',
        businessDate: '2026-07-27',
      );

      expect(() => businessDateForOpenCashSession(closed26), throwsStateError);
      expect(businessDateForOpenCashSession(open27), '2026-07-27');
    });

    test(
      'sesion coincidente prevalece y diagnostica una fecha inconsistente',
      () {
        final membership = belongsToOperationalSession(
          order: orderFixture(
            businessDate: '2026-07-25',
            cashSessionId: 'session-26',
          ),
          selectedCashSessionId: 'session-26',
          selectedBusinessDate: '2026-07-26',
          branchId: 'aviacion',
        );

        expect(membership.included, isTrue);
        expect(membership.reason, 'cash_session_match');
        expect(membership.inconsistency, contains('2026-07-25'));
      },
    );
  });
}

PosOrder orderFixture({
  String? businessDate,
  String? cashSessionId,
  DateTime? createdAt,
}) {
  return PosOrder(
    id: 'order-${cashSessionId ?? 'legacy'}',
    tableId: 'table-1',
    tableName: 'Mesa 1',
    status: 'paid',
    kitchenStatus: 'ready',
    paymentStatus: 'paid',
    total: 100,
    paidTotal: 100,
    pendingTotal: 0,
    personNames: const {1: 'Persona 1'},
    orderType: 'dine_in',
    businessDate: businessDate,
    cashSessionId: cashSessionId,
    createdAt: createdAt,
    branchId: 'aviacion',
    branchName: 'Aviacion',
  );
}

Payment paymentFixture({DateTime? createdAt}) {
  return Payment(
    id: 'payment-1',
    orderId: 'order-1',
    tableId: 'table-1',
    tableName: 'Mesa 1',
    type: 'full_table',
    method: 'cash',
    baseAmount: 100,
    surchargeRate: 0,
    surchargeAmount: 0,
    chargedAmount: 100,
    createdAt: createdAt,
    branchId: 'aviacion',
    branchName: 'Aviacion',
  );
}

CashSession cashSessionFixture({
  required String id,
  required String businessDate,
  String status = 'open',
  DateTime? closedAt,
}) {
  return CashSession(
    id: id,
    businessDate: businessDate,
    status: status,
    openingCashAmount: 0,
    openedByEmployeeId: 'employee-1',
    openedByEmployeeName: 'Empleado',
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
    closedAt: closedAt,
    branchId: 'aviacion',
    branchName: 'Aviacion',
  );
}
