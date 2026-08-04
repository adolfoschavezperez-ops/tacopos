import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/visit_classification_report.dart';
import 'package:tacopos/models/order.dart';

void main() {
  group('visit classification weekly report', () {
    test('groups paid table orders by operational Monday-Sunday weeks', () {
      final report = buildVisitClassificationWeeklyReport(
        startBusinessDate: '2026-07-01',
        endBusinessDate: '2026-07-20',
        orders: [
          _order(
            id: 'first-1',
            businessDate: '2026-07-01',
            visitClassification: 'first_time',
          ),
          _order(
            id: 'returning-1',
            businessDate: '2026-07-05',
            visitClassification: 'returning',
          ),
          _order(id: 'first-2', businessDate: '2026-07-06', isFirstVisit: true),
          _order(id: 'unknown-1', businessDate: '2026-07-20'),
          _order(
            id: 'outside',
            businessDate: '2026-07-21',
            visitClassification: 'first_time',
          ),
        ],
      );

      expect(report.rows, hasLength(4));
      expect(report.rows.first.weekLabel, '29/06/2026 al 05/07/2026');
      expect(report.rows.first.isPartial, isTrue);
      expect(report.rows.first.firstTime, 1);
      expect(report.rows.first.returning, 1);
      expect(report.rows.first.classified, 2);
      expect(report.rows.first.unknown, 0);
      expect(report.rows[1].weekLabel, '06/07/2026 al 12/07/2026');
      expect(report.rows[1].isPartial, isFalse);
      expect(report.rows[1].firstTime, 1);
      expect(report.rows.last.weekLabel, '20/07/2026 al 26/07/2026');
      expect(report.rows.last.isPartial, isTrue);
      expect(report.rows.last.unknown, 1);
    });

    test('excludes takeout, open and cancelled orders', () {
      final report = buildVisitClassificationWeeklyReport(
        startBusinessDate: '2026-07-06',
        endBusinessDate: '2026-07-12',
        orders: [
          _order(id: 'table', visitClassification: 'first_time'),
          _order(
            id: 'takeout',
            orderType: 'takeout',
            visitClassification: 'first_time',
          ),
          _order(
            id: 'open',
            status: 'open',
            paymentStatus: 'pending',
            visitClassification: 'first_time',
          ),
          _order(
            id: 'cancelled',
            status: 'cancelled',
            visitClassification: 'first_time',
          ),
        ],
      );

      expect(report.firstTimeTotal, 1);
      expect(report.classifiedTotal, 1);
    });

    test('calculates changes, percentages, averages and csv rows', () {
      final report = buildVisitClassificationWeeklyReport(
        startBusinessDate: '2026-07-06',
        endBusinessDate: '2026-07-19',
        orders: [
          _order(id: 'a', businessDate: '2026-07-06', isFirstVisit: true),
          _order(id: 'b', businessDate: '2026-07-07', isFirstVisit: false),
          _order(id: 'c', businessDate: '2026-07-13', isFirstVisit: false),
          _order(id: 'd', businessDate: '2026-07-14', isFirstVisit: false),
        ],
      );

      expect(report.rows, hasLength(2));
      expect(report.firstTimeTotal, 1);
      expect(report.returningTotal, 3);
      expect(report.classifiedTotal, 4);
      expect(report.unknownTotal, 0);
      expect(report.firstTimeWeeklyAverage, 0.5);
      expect(report.returningWeeklyAverage, 1.5);
      expect(report.classifiedWeeklyAverage, 2);
      expect(report.rows[1].firstTimeChange, -1);
      expect(report.rows[1].returningChange, 1);
      expect(report.rows[1].classifiedChange, 0);
      expect(report.rows.first.csvRow, [
        '06/07/2026 al 12/07/2026',
        'Semana completa',
        '1',
        '1',
        '2',
        '0',
        '-',
        '-',
        '-',
        '50.0%',
        '50.0%',
      ]);
      expect(report.rows[1].csvRow[6], '-1');
      expect(report.rows[1].csvRow[7], '+1');
    });

    test('keeps historical orders without visit fields as unknown', () {
      final report = buildVisitClassificationWeeklyReport(
        startBusinessDate: '2026-07-06',
        endBusinessDate: '2026-07-12',
        orders: [_order(id: 'historical')],
      );

      expect(report.unknownTotal, 1);
      expect(report.classifiedTotal, 0);
      expect(report.rows.single.csvRow[9], '0.0%');
      expect(report.rows.single.csvRow[10], '0.0%');
    });
  });
}

PosOrder _order({
  required String id,
  String businessDate = '2026-07-06',
  String orderType = 'dine_in',
  String status = 'paid',
  String paymentStatus = 'paid',
  String? visitClassification,
  bool? isFirstVisit,
}) {
  return PosOrder(
    id: id,
    tableId: 'table-1',
    tableName: 'Mesa 1',
    status: status,
    kitchenStatus: 'ready',
    paymentStatus: paymentStatus,
    total: 100,
    paidTotal: 100,
    pendingTotal: 0,
    personNames: const {},
    orderType: orderType,
    businessDate: businessDate,
    visitClassification: visitClassification,
    isFirstVisit: isFirstVisit,
  );
}
