import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tacopos/core/reports/canonical_sales_summary.dart';
import 'package:tacopos/core/reports/finance_dashboard.dart';
import 'package:tacopos/core/reports/weekly_finance_comparison.dart';
import 'package:tacopos/models/cash_session.dart';
import 'package:tacopos/models/cash_withdrawal_request.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/payment.dart';

void main() {
  test('calcula cuatro semanas lunes-domingo desde la semana actual', () {
    final now = DateTime(2026, 8, 11, 15);
    final report = buildWeeklyFinanceComparisonReport(
      bundle: _dashboard(now: now),
      now: now,
    );

    expect(mondayForDate(now), DateTime(2026, 8, 10));
    expect(report.weeks, hasLength(4));
    expect(report.weeks[0].label, 'Hace 3 semanas');
    expect(report.weeks[0].startBusinessDate, '2026-07-20');
    expect(report.weeks[0].endBusinessDate, '2026-07-26');
    expect(report.weeks[1].startBusinessDate, '2026-07-27');
    expect(report.weeks[1].endBusinessDate, '2026-08-02');
    expect(report.weeks[2].startBusinessDate, '2026-08-03');
    expect(report.weeks[2].endBusinessDate, '2026-08-09');
    expect(report.weeks[3].startBusinessDate, '2026-08-10');
    expect(report.weeks[3].endBusinessDate, '2026-08-16');
    expect(report.weeks[3].isInProgress, isTrue);
    expect(report.elapsedDayCount, 2);
  });

  test('maneja cruces de mes y anio sin usar semanas domingo-sabado', () {
    final monthCross = buildWeeklyFinanceComparisonReport(
      bundle: _dashboard(now: DateTime(2026, 3, 1, 10)),
      now: DateTime(2026, 3, 1, 10),
    );
    expect(monthCross.weeks.last.startBusinessDate, '2026-02-23');
    expect(monthCross.weeks.last.endBusinessDate, '2026-03-01');

    final yearCross = buildWeeklyFinanceComparisonReport(
      bundle: _dashboard(now: DateTime(2027, 1, 1, 10)),
      now: DateTime(2027, 1, 1, 10),
    );
    expect(yearCross.weeks.last.startBusinessDate, '2026-12-28');
    expect(yearCross.weeks.last.endBusinessDate, '2027-01-03');
  });

  test(
    'calcula venta, ingresos reales, gastos, utilidad, ordenes y ticket',
    () {
      final now = DateTime(2026, 8, 11, 12);
      final report = buildWeeklyFinanceComparisonReport(
        bundle: _dashboard(
          now: now,
          sales: [
            _sale('sale-current-1', '2026-08-10', 2000),
            _sale('sale-current-2', '2026-08-11', 2000),
            _sale('sale-previous', '2026-08-03', 3000),
          ],
          cashSessions: [
            _cashSession(
              id: 'current-cut',
              businessDate: '2026-08-10',
              openingCashAmount: 1000,
              countedCashAmount: 2950,
              terminalReportedAmount: 2000,
              expectedCashAmount: 3000,
              expectedCardChargedAmount: 2000,
            ),
            _cashSession(
              id: 'previous-cut',
              businessDate: '2026-08-03',
              countedCashAmount: 1500,
              terminalReportedAmount: 1500,
              expectedCashAmount: 1500,
              expectedCardChargedAmount: 1500,
            ),
          ],
          withdrawals: [_expense('2026-08-10', 700)],
        ),
        now: now,
      );

      final current = report.weeks.last.metrics;
      expect(current.grossSales, 4000);
      expect(current.netSales, 4000);
      expect(current.realIncome, 3950);
      expect(current.cashIncome, 1950);
      expect(current.cardIncome, 2000);
      expect(current.expenses, 700);
      expect(current.financialProfit, 3250);
      expect(current.orders, 2);
      expect(current.averageTicket, 2000);
      expect(current.shortages, 50);
      expect(current.overages, 0);
    },
  );

  test('fondo, descuentos y comida empleado no inflan ingreso real', () {
    final now = DateTime(2026, 8, 11, 12);
    final report = buildWeeklyFinanceComparisonReport(
      bundle: _dashboard(
        now: now,
        sales: [
          _sale('discount', '2026-08-10', 4070, gross: 4100, discount: 30),
          _sale(
            'employee-meal',
            '2026-08-10',
            0,
            gross: 100,
            employeeMeal: 100,
          ),
        ],
        cashSessions: [
          _cashSession(
            id: 'discount-cut',
            businessDate: '2026-08-10',
            openingCashAmount: 1000,
            countedCashAmount: 5070,
            expectedCashAmount: 5070,
            expectedEmployeeConsumptionAmount: 100,
          ),
        ],
      ),
      now: now,
    );

    final current = report.weeks.last.metrics;
    expect(current.grossSales, 4200);
    expect(current.discounts, 30);
    expect(current.netSales, 4070);
    expect(current.realIncome, 4070);
    expect(current.shortages, 0);
  });

  test('cortes abiertos o cancelados no cuentan y varios cortes se suman', () {
    final now = DateTime(2026, 8, 11, 12);
    final report = buildWeeklyFinanceComparisonReport(
      bundle: _dashboard(
        now: now,
        cashSessions: [
          _cashSession(
            id: 'closed-1',
            businessDate: '2026-08-10',
            countedCashAmount: 1000,
            terminalReportedAmount: 500,
            expectedCashAmount: 1000,
            expectedCardChargedAmount: 500,
          ),
          _cashSession(
            id: 'closed-2',
            businessDate: '2026-08-10',
            countedCashAmount: 1020,
            terminalReportedAmount: 500,
            expectedCashAmount: 1000,
            expectedCardChargedAmount: 500,
          ),
          _cashSession(
            id: 'open',
            businessDate: '2026-08-10',
            status: 'open',
            countedCashAmount: 999,
          ),
          _cashSession(
            id: 'cancelled',
            businessDate: '2026-08-10',
            status: 'cancelled',
            countedCashAmount: 999,
          ),
        ],
      ),
      now: now,
    );

    final current = report.weeks.last.metrics;
    expect(current.realIncome, 3020);
    expect(current.overages, 20);
    expect(current.shortages, 0);
  });

  test('semana sin datos, division entre cero y variaciones se manejan', () {
    final now = DateTime(2026, 8, 11, 12);
    final report = buildWeeklyFinanceComparisonReport(
      bundle: _dashboard(
        now: now,
        sales: [
          _sale('previous', '2026-08-03', 2000),
          _sale('current', '2026-08-10', 2200),
        ],
        cashSessions: [
          _cashSession(
            id: 'previous',
            businessDate: '2026-08-03',
            countedCashAmount: 2000,
            expectedCashAmount: 2000,
          ),
          _cashSession(
            id: 'current',
            businessDate: '2026-08-10',
            countedCashAmount: 2200,
            expectedCashAmount: 2200,
          ),
        ],
      ),
      now: now,
    );

    expect(report.weeks.first.metrics.averageTicket, 0);
    expect(weeklyFinanceChange(current: 10, previous: 0).percent, isNull);
    expect(weeklyFinanceChange(current: 0, previous: 0).percent, 0);
    expect(weeklyFinanceChange(current: 2200, previous: 2000).percent, 10);
    expect(weeklyFinanceChange(current: 1800, previous: 2000).percent, -10);
  });

  test('comparacion mismo periodo usa los mismos dias transcurridos', () {
    final now = DateTime(2026, 8, 11, 12);
    final report = buildWeeklyFinanceComparisonReport(
      bundle: _dashboard(
        now: now,
        sales: [
          _sale('mon-current', '2026-08-10', 1000),
          _sale('tue-current', '2026-08-11', 1100),
          _sale('mon-prev', '2026-08-03', 900),
          _sale('tue-prev', '2026-08-04', 1000),
          _sale('wed-prev', '2026-08-05', 5000),
        ],
      ),
      now: now,
    );

    expect(report.samePeriodWeeks.last.metrics.netSales, 2100);
    expect(report.samePeriodWeeks[2].metrics.netSales, 1900);
    expect(report.weeks[2].metrics.netSales, 6900);
    expect(report.weeks.last.dailyRows[0].metrics.netSales, 1000);
    expect(report.weeks.last.dailyRows[1].metrics.netSales, 1100);
    expect(report.weeks.last.dailyRows[2].isFutureForCurrentWeek, isTrue);
  });

  test('coincide con Dashboard financiero para el mismo rango semanal', () {
    final now = DateTime(2026, 8, 11, 12);
    final sales = [
      _sale('sale', '2026-08-03', 3000),
      _sale('sale-2', '2026-08-04', 1000),
    ];
    final cashSessions = [
      _cashSession(
        id: 'cut',
        businessDate: '2026-08-03',
        countedCashAmount: 1900,
        terminalReportedAmount: 2000,
        expectedCashAmount: 2000,
        expectedCardChargedAmount: 2000,
      ),
    ];
    final withdrawals = [_expense('2026-08-03', 500)];
    final rangeBundle = _dashboard(
      now: now,
      sales: sales,
      cashSessions: cashSessions,
      withdrawals: withdrawals,
    );
    final weekBundle = _dashboard(
      now: now,
      startBusinessDate: '2026-08-03',
      endBusinessDate: '2026-08-09',
      sales: sales,
      cashSessions: cashSessions,
      withdrawals: withdrawals,
    );
    final report = buildWeeklyFinanceComparisonReport(
      bundle: rangeBundle,
      now: now,
    );
    final previousWeek = report.weeks[2].metrics;

    expect(previousWeek.netSales, weekBundle.netSales);
    expect(previousWeek.realIncome, weekBundle.realCollected);
    expect(previousWeek.expenses, weekBundle.paidExpenses);
    expect(previousWeek.financialProfit, weekBundle.collectionsResult);
  });
}

FinanceDashboardBundle _dashboard({
  required DateTime now,
  String? startBusinessDate,
  String? endBusinessDate,
  List<_SaleFixture> sales = const [],
  List<CashSession> cashSessions = const [],
  List<CashWithdrawalRequest> withdrawals = const [],
}) {
  final formatter = DateFormat('yyyy-MM-dd');
  final start = weeklyComparisonRangeStart(now);
  final endExclusive = weeklyComparisonRangeEndExclusive(now);
  final bundles = [
    for (final sale in sales)
      SalesOrderBundleInput(
        order: sale.order,
        items: [_item(sale.gross)],
        payments: sale.payments,
      ),
  ];
  final paymentsByOrder = {
    for (final sale in sales) sale.order.id: sale.payments,
  };
  return buildFinanceDashboard(
    FinanceDashboardInput(
      key: FinanceDashboardKey(
        restaurantId: 'restaurant',
        branchId: 'branch',
        startBusinessDate: startBusinessDate ?? formatter.format(start),
        endBusinessDate:
            endBusinessDate ??
            formatter.format(endExclusive.subtract(const Duration(days: 1))),
      ),
      salesSummary: buildCanonicalSalesSummary(bundles),
      paymentsByOrder: paymentsByOrder,
      cashSessions: cashSessions,
      withdrawals: withdrawals,
      purchases: const [],
      supplierPayments: const [],
      suppliers: const [],
    ),
  );
}

_SaleFixture _sale(
  String id,
  String businessDate,
  double net, {
  double? gross,
  double discount = 0,
  double employeeMeal = 0,
}) {
  final resolvedGross = gross ?? net + discount + employeeMeal;
  final order = PosOrder(
    id: id,
    tableId: 'table-$id',
    tableName: 'Mesa',
    status: 'paid',
    kitchenStatus: 'served',
    paymentStatus: 'paid',
    total: resolvedGross,
    paidTotal: net + employeeMeal,
    pendingTotal: 0,
    personNames: const {},
    orderType: 'dine_in',
    businessDate: businessDate,
    explicitDiscountFields: discount + employeeMeal > 0
        ? {'discountAmount': discount + employeeMeal}
        : const {},
  );
  return _SaleFixture(
    order: order,
    gross: resolvedGross,
    payments: [
      if (net > 0) _payment('$id-cash', id, amount: net),
      if (employeeMeal > 0)
        _payment(
          '$id-meal',
          id,
          amount: employeeMeal,
          method: 'employee_consumption',
        ),
    ],
  );
}

OrderItem _item(double total) {
  return OrderItem(
    id: 'item-$total',
    personNumber: 1,
    personName: 'Persona 1',
    productId: 'product',
    productName: 'Producto',
    category: 'General',
    qty: 1,
    unitPrice: total,
    total: total,
    notes: '',
    sendToKitchen: true,
    kitchenStatus: 'served',
    paymentStatus: 'paid',
  );
}

Payment _payment(
  String id,
  String orderId, {
  required double amount,
  String method = 'cash',
}) {
  return Payment(
    id: id,
    orderId: orderId,
    tableId: 'table',
    tableName: 'Mesa',
    type: 'full_table',
    method: method,
    baseAmount: amount,
    surchargeRate: 0,
    surchargeAmount: 0,
    chargedAmount: amount,
    appliedAmount: amount,
    status: 'active',
  );
}

CashSession _cashSession({
  required String id,
  required String businessDate,
  String status = 'closed',
  double openingCashAmount = 0,
  double countedCashAmount = 0,
  double terminalReportedAmount = 0,
  double expectedCashAmount = 0,
  double expectedCardChargedAmount = 0,
  double expectedEmployeeConsumptionAmount = 0,
}) {
  final netDifference =
      countedCashAmount +
      terminalReportedAmount -
      expectedCashAmount -
      expectedCardChargedAmount;
  return CashSession(
    id: id,
    businessDate: businessDate,
    status: status,
    openingCashAmount: openingCashAmount,
    openedByEmployeeId: 'employee',
    openedByEmployeeName: 'Empleado',
    countedCashAmount: countedCashAmount,
    terminalReportedAmount: terminalReportedAmount,
    expectedCashAmount: expectedCashAmount,
    expectedCardChargedAmount: expectedCardChargedAmount,
    expectedCardBaseAmount: expectedCardChargedAmount,
    expectedCardSurchargeAmount: 0,
    expectedCardFeeAbsorbedAmount: 0,
    expectedPlatformAmount: 0,
    expectedEmployeeConsumptionAmount: expectedEmployeeConsumptionAmount,
    totalExpectedRealMoney: expectedCashAmount + expectedCardChargedAmount,
    totalCountedRealMoney: countedCashAmount + terminalReportedAmount,
    cashDifference: countedCashAmount - expectedCashAmount,
    cardDifference: terminalReportedAmount - expectedCardChargedAmount,
    netDifference: netDifference,
    shortageAmount: netDifference < 0 ? netDifference.abs() : 0,
    overAmount: netDifference > 0 ? netDifference : 0,
    approvedWithdrawalsTotal: 0,
    pendingWithdrawalsTotal: 0,
    withdrawalRequestCount: 0,
    notes: '',
  );
}

CashWithdrawalRequest _expense(String businessDate, double amount) {
  return CashWithdrawalRequest(
    id: 'expense-$businessDate-$amount',
    cashSessionId: 'cash',
    businessDate: businessDate,
    amount: amount,
    reason: 'Gasto',
    requestedByEmployeeId: 'employee',
    requestedByEmployeeName: 'Empleado',
    status: 'approved',
  );
}

class _SaleFixture {
  const _SaleFixture({
    required this.order,
    required this.gross,
    required this.payments,
  });

  final PosOrder order;
  final double gross;
  final List<Payment> payments;
}
