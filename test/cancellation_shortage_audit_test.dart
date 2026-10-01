import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/cancellation_shortage_audit.dart';
import 'package:tacopos/models/cash_session.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';

void main() {
  group('cancellation shortage audit', () {
    test('reconstructs a 215 cancellation initiated by Andres', () {
      final cancelledAt = DateTime(2026, 9, 28, 22, 5);
      final order = _order(cancelledAt: cancelledAt);
      final items = [
        _item(
          id: 'tacos',
          productName: 'Taco bistec',
          qty: 7,
          unitPrice: 25,
          cancelledAt: cancelledAt,
          requestedBy: 'Andres Ramirez',
          acceptedBy: 'Ricardo',
          sentToKitchenAt: DateTime(2026, 9, 28, 21, 55),
          cookingAt: DateTime(2026, 9, 28, 21, 57),
        ),
        _item(
          id: 'aguas',
          productName: 'Agua',
          qty: 2,
          unitPrice: 20,
          cancelledAt: cancelledAt,
          requestedBy: 'Andres Ramirez',
          acceptedBy: 'Ricardo',
          sendToKitchen: false,
        ),
      ];

      final rows = buildCancellationCashAuditRows(
        orders: [order],
        itemsByOrder: {order.id: items},
        paymentsByOrder: const {},
      );

      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.cancelledAmount, 215);
      expect(row.cancelledAmountInitiatedBy('Andres'), 215);
      expect(row.cancelledQtyInitiatedBy('Andres'), 9);
      expect(row.hasNoPaymentRecord, isTrue);
      expect(row.fullOrderCancelled, isTrue);
      expect(row.passedThroughKitchen, isTrue);
      expect(row.strongCashCancellationCandidate, isTrue);
      expect(row.initiatedByLabel, contains('Andres Ramirez'));
      expect(row.acceptedByLabel, contains('Ricardo'));
    });

    test('285 shortage plus 215 no-payment cancellation implies 500 outflow', () {
      final cancelledAt = DateTime(2026, 9, 28, 22, 5);
      final order = _order(cancelledAt: cancelledAt);
      final rows = buildCancellationCashAuditRows(
        orders: [order],
        itemsByOrder: {
          order.id: [
            _item(
              id: 'order-total',
              productName: 'Productos',
              qty: 1,
              unitPrice: 215,
              cancelledAt: cancelledAt,
              requestedBy: 'Andres Ramirez',
              sentToKitchenAt: DateTime(2026, 9, 28, 21, 55),
            ),
          ],
        },
        paymentsByOrder: const {},
      );

      final days = buildCancellationCashAuditDays(
        rows: rows,
        cashSessions: [_session(shortage: 285)],
      );

      expect(days, hasLength(1));
      expect(days.single.shortage, 285);
      expect(days.single.noPaymentAmountBy('Andres'), 215);
      expect(days.single.impliedUnrecordedOutflowBy('Andres'), 500);
    });

    test('finds exact combination matching required compensation', () {
      final first = _rowForAmount('order-1', 140);
      final second = _rowForAmount('order-2', 75);
      final third = _rowForAmount('order-3', 90);

      final matches = findCancellationAmountMatches(
        rows: [first, second, third],
        target: 215,
        employeeName: 'Andres',
        maxItems: 3,
      );

      expect(matches, isNotEmpty);
      expect(matches.first.total, 215);
      expect(matches.first.absoluteDifference, 0);
      expect(
        matches.first.rows.map((row) => row.order.id).toSet(),
        {'order-1', 'order-2'},
      );
    });

    test('attributes only the items initiated by the selected employee', () {
      final cancelledAt = DateTime(2026, 9, 28, 22, 5);
      final order = _order(cancelledAt: cancelledAt);
      final rows = buildCancellationCashAuditRows(
        orders: [order],
        itemsByOrder: {
          order.id: [
            _item(
              id: 'andres',
              productName: 'Tacos',
              qty: 7,
              unitPrice: 25,
              cancelledAt: cancelledAt,
              requestedBy: 'Andres Ramirez',
            ),
            _item(
              id: 'otro',
              productName: 'Aguas',
              qty: 2,
              unitPrice: 20,
              cancelledAt: cancelledAt,
              requestedBy: 'Yamilet Ayali',
            ),
          ],
        },
        paymentsByOrder: const {},
      );

      expect(rows.single.cancelledAmount, 215);
      expect(rows.single.cancelledAmountInitiatedBy('Andres'), 175);
      expect(rows.single.cancelledAmountInitiatedBy('Yamilet'), 40);
    });
  });
}

CancellationCashAuditRow _rowForAmount(String id, double amount) {
  final cancelledAt = DateTime(2026, 9, 28, 22, 5);
  final order = _order(id: id, cancelledAt: cancelledAt);
  return buildCancellationCashAuditRows(
    orders: [order],
    itemsByOrder: {
      order.id: [
        _item(
          id: '$id-item',
          productName: 'Producto',
          qty: 1,
          unitPrice: amount,
          cancelledAt: cancelledAt,
          requestedBy: 'Andres Ramirez',
          sentToKitchenAt: DateTime(2026, 9, 28, 21, 55),
        ),
      ],
    },
    paymentsByOrder: const {},
  ).single;
}

PosOrder _order({
  String id = 'order-1',
  DateTime? cancelledAt,
}) {
  return PosOrder(
    id: id,
    tableId: 'mesa-1',
    tableName: 'Mesa 1',
    status: 'cancelled',
    kitchenStatus: 'cancelled',
    paymentStatus: 'cancelled',
    total: 0,
    paidTotal: 0,
    pendingTotal: 0,
    personNames: const {1: 'Persona 1'},
    orderType: 'dine_in',
    createdAt: DateTime(2026, 9, 28, 21, 50),
    sentToKitchenAt: DateTime(2026, 9, 28, 21, 55),
    cancelledAt: cancelledAt,
    cancelledByEmployeeName: 'Andres Ramirez',
    cancelReason: 'Cliente cancelo',
    businessDate: '2026-09-28',
    saleFolioDisplay: '0012',
    saleFolioFull: 'AVI-2026-09-28-0012',
  );
}

OrderItem _item({
  required String id,
  required String productName,
  required int qty,
  required double unitPrice,
  required DateTime cancelledAt,
  String? requestedBy,
  String? acceptedBy,
  DateTime? sentToKitchenAt,
  DateTime? cookingAt,
  bool sendToKitchen = true,
}) {
  return OrderItem(
    id: id,
    personNumber: 1,
    personName: 'Persona 1',
    productId: id,
    productName: productName,
    category: sendToKitchen ? 'Tacos' : 'Bebidas',
    qty: qty,
    unitPrice: unitPrice,
    total: qty * unitPrice,
    notes: '',
    sendToKitchen: sendToKitchen,
    kitchenStatus: 'cancelled',
    paymentStatus: 'cancelled',
    status: 'cancelled',
    cancelStatus: 'accepted',
    createdAt: DateTime(2026, 9, 28, 21, 50),
    sentToKitchenAt: sentToKitchenAt,
    cookingAt: cookingAt,
    cancelledAt: cancelledAt,
    cancelRequestedAt: requestedBy == null
        ? null
        : cancelledAt.subtract(const Duration(minutes: 1)),
    cancelRequestedByEmployeeName: requestedBy,
    cancelAcceptedAt: acceptedBy == null ? null : cancelledAt,
    cancelAcceptedByEmployeeName: acceptedBy,
    cancelledByEmployeeName: acceptedBy ?? requestedBy,
    cancelReason: 'Cliente cancelo',
  );
}

CashSession _session({required double shortage}) {
  return CashSession(
    id: 'cash-2026-09-28',
    businessDate: '2026-09-28',
    status: 'closed',
    openingCashAmount: 500,
    openedByEmployeeId: 'andres',
    openedByEmployeeName: 'Andres Ramirez',
    countedCashAmount: 5000,
    terminalReportedAmount: 1000,
    expectedCashAmount: 5285,
    expectedCardChargedAmount: 1000,
    expectedCardBaseAmount: 1000,
    expectedCardSurchargeAmount: 0,
    expectedCardFeeAbsorbedAmount: 0,
    expectedPlatformAmount: 0,
    expectedEmployeeConsumptionAmount: 0,
    totalExpectedRealMoney: 6285,
    totalCountedRealMoney: 6000,
    cashDifference: -285,
    cardDifference: 0,
    netDifference: -285,
    shortageAmount: shortage,
    overAmount: 0,
    approvedWithdrawalsTotal: 0,
    pendingWithdrawalsTotal: 0,
    withdrawalRequestCount: 0,
    notes: '',
    openedAt: DateTime(2026, 9, 28, 19, 30),
    closedAt: DateTime(2026, 9, 28, 23, 59),
  );
}
