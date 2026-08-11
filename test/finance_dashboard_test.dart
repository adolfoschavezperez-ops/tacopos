import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/canonical_sales_summary.dart';
import 'package:tacopos/core/reports/finance_dashboard.dart';
import 'package:tacopos/core/reports/finance_dashboard_excel.dart';
import 'package:excel/excel.dart';
import 'package:tacopos/models/cash_session.dart';
import 'package:tacopos/models/cash_withdrawal_request.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/payment.dart';
import 'package:tacopos/models/purchase_models.dart';

void main() {
  const key = FinanceDashboardKey(
    restaurantId: 'restaurant',
    branchId: 'branch',
    startBusinessDate: '2026-07-01',
    endBusinessDate: '2026-07-31',
  );

  test('calcula venta bruta, descuentos y venta neta sin duplicarlos', () {
    final order = _order('sale', businessDate: '2026-07-12');
    final payment = _payment('sale-payment', order.id, amount: 800);
    final summary = buildCanonicalSalesSummary([
      SalesOrderBundleInput(
        order: order.copyForTest(
          explicitDiscountFields: const {'discountAmount': 200},
        ),
        items: [_item(1000)],
        payments: [payment],
      ),
    ]);

    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: summary,
        paymentsByOrder: {
          order.id: [payment],
        },
        cashSessions: const [],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    expect(dashboard.grossSales, 1000);
    expect(dashboard.salesWithDiscount, 800);
    expect(dashboard.salesWithoutDiscount, 0);
    expect(dashboard.discounts, 200);
    expect(dashboard.netSales, 800);
  });

  test('ingreso real usa cortes cerrados y no pagos aplicados', () {
    final order = _order('collections', businessDate: '2026-07-12');
    final cash = _payment(
      'cash',
      order.id,
      amount: 500,
      received: 600,
      change: 100,
    );
    final card = _payment('card', order.id, amount: 300, method: 'card');
    final cancelled = _payment(
      'cancelled',
      order.id,
      amount: 100,
      status: 'cancelled',
      cancelledAt: DateTime(2026, 7, 12),
    );
    final summary = buildCanonicalSalesSummary([
      SalesOrderBundleInput(
        order: order,
        items: [_item(800)],
        payments: [cash, card, cancelled],
      ),
    ]);

    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: summary,
        paymentsByOrder: {
          order.id: [cash, card, cancelled],
        },
        cashSessions: [
          _cashSession(
            id: 'cut-3950',
            openingCashAmount: 1000,
            countedCashAmount: 2950,
            terminalReportedAmount: 2000,
            expectedCashAmount: 3000,
            expectedCardChargedAmount: 2000,
          ),
        ],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    expect(dashboard.cashCollected, 1950);
    expect(dashboard.cardCollected, 2000);
    expect(dashboard.realCollected, 3950);
    expect(dashboard.expectedMonetaryIncome, 4000);
    expect(dashboard.cashShortages, 50);
  });

  test('detalle diario reconstruye efectivo de gastos pagados desde caja', () {
    const augustKey = FinanceDashboardKey(
      restaurantId: 'restaurant',
      branchId: 'branch',
      startBusinessDate: '2026-08-01',
      endBusinessDate: '2026-08-31',
    );
    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: augustKey,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: [
          _cashSession(
            id: 'cut-2026-08-05',
            businessDate: '2026-08-05',
            countedCashAmount: 2999,
            terminalReportedAmount: 2500,
            expectedCashAmount: 3049,
            expectedCardChargedAmount: 2500,
            approvedWithdrawalsTotal: 500,
          ),
        ],
        withdrawals: [
          _expense(
            'approved',
            500,
            businessDate: '2026-08-05',
            cashSessionId: 'cut-2026-08-05',
          ),
        ],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    final day = dashboard.cashCutDailyDetails.single;
    expect(day.businessDate, '2026-08-05');
    expect(day.cashCounted, 2999);
    expect(day.cashExpensesPaid, 500);
    expect(day.cashOperationalBeforeExpenses, 3499);
    expect(day.cardReceived, 2500);
    expect(day.otherReceived, 0);
    expect(day.actualIncome, 5999);
    expect(day.expectedMonetaryIncome, 6049);
    expect(day.shortage, 50);
    expect(day.overage, 0);
    expect(dashboard.cashCollected, 3499);
    expect(dashboard.realCollected, 5999);
    expect(dashboard.generalResult, 5499);
  });

  test('gastos que no salen de caja no reconstruyen efectivo operativo', () {
    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: [
          _cashSession(
            id: 'cut-no-cash-expense',
            countedCashAmount: 3500,
            terminalReportedAmount: 2500,
            expectedCashAmount: 3500,
            expectedCardChargedAmount: 2500,
          ),
        ],
        withdrawals: [
          _expense('approved', 500, source: 'supplier_payment'),
          _expense('approved', 700, source: 'cash_transfer'),
        ],
        purchases: const [],
        supplierPayments: [
          _supplierPayment(amount: 500, method: 'card'),
          _supplierPayment(amount: 700, method: 'transfer'),
        ],
        suppliers: const [],
      ),
    );

    final day = dashboard.cashCutDailyDetails.single;
    expect(day.cashCounted, 3500);
    expect(day.cashExpensesPaid, 0);
    expect(day.cashOperationalBeforeExpenses, 3500);
    expect(day.actualIncome, 6000);
    expect(dashboard.paidExpenses, 0);
  });

  test('fondo inicial no cuenta como ingreso ni se resta dos veces', () {
    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: [
          _cashSession(
            id: 'cut-with-opening',
            openingCashAmount: 1000,
            countedCashAmount: 3999,
            terminalReportedAmount: 2500,
            expectedCashAmount: 4049,
            expectedCardChargedAmount: 2500,
            approvedWithdrawalsTotal: 500,
          ),
        ],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    final day = dashboard.cashCutDailyDetails.single;
    expect(day.cashCounted, 2999);
    expect(day.cashExpensesPaid, 500);
    expect(day.cashOperationalBeforeExpenses, 3499);
    expect(day.actualIncome, 5999);
    expect(day.expectedMonetaryIncome, 6049);
    expect(day.shortage, 50);
  });

  test('detalle diario agrupa varios cortes y ordena fechas ascendente', () {
    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: [
          _cashSession(
            id: 'cut-newer',
            businessDate: '2026-07-13',
            countedCashAmount: 300,
            expectedCashAmount: 300,
          ),
          _cashSession(
            id: 'cut-1',
            countedCashAmount: 1000,
            terminalReportedAmount: 800,
            expectedCashAmount: 900,
            expectedCardChargedAmount: 800,
            approvedWithdrawalsTotal: 100,
            closedByEmployeeName: 'Ana',
          ),
          _cashSession(
            id: 'cut-2',
            countedCashAmount: 1500,
            terminalReportedAmount: 1200,
            expectedCashAmount: 1300,
            expectedCardChargedAmount: 1200,
            approvedWithdrawalsTotal: 200,
            closedByEmployeeName: 'Luis',
          ),
          _cashSession(id: 'cut-open', status: 'open', countedCashAmount: 9999),
          _cashSession(
            id: 'cut-cancelled',
            status: 'cancelled',
            countedCashAmount: 9999,
          ),
        ],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    final days = dashboard.cashCutDailyDetails;
    expect(days.map((row) => row.businessDate), ['2026-07-12', '2026-07-13']);
    final grouped = days.first;
    expect(grouped.cutCount, 2);
    expect(grouped.cashCounted, 2500);
    expect(grouped.cashExpensesPaid, 300);
    expect(grouped.cashOperationalBeforeExpenses, 2800);
    expect(grouped.cardReceived, 2000);
    expect(grouped.actualIncome, 4800);
    expect(grouped.closedByNames, ['Ana', 'Luis']);
  });

  test('total del periodo coincide con suma diaria y dashboard', () {
    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: [
          _cashSession(
            id: 'cut-a',
            businessDate: '2026-07-12',
            countedCashAmount: 100,
            terminalReportedAmount: 200,
            expectedCashAmount: 100,
            expectedCardChargedAmount: 200,
          ),
          _cashSession(
            id: 'cut-b',
            businessDate: '2026-07-13',
            countedCashAmount: 300,
            terminalReportedAmount: 400,
            expectedCashAmount: 300,
            expectedCardChargedAmount: 400,
          ),
        ],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    final total = dashboard.cashCutPeriodTotal;
    expect(total.actualIncome, 1000);
    expect(total.actualIncome, dashboard.realCollected);
    expect(total.cashOperationalBeforeExpenses, dashboard.cashCollected);
    expect(total.cardReceived, dashboard.cardCollected);
  });

  test('resta solo gastos aprobados y separa pendientes y cancelados', () {
    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: const [],
        withdrawals: [
          _expense('approved', 100),
          _expense('pending', 50),
          _expense('cancelled', 30),
          _expense('approved', 400, source: 'supplier_payment'),
        ],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    expect(dashboard.paidExpenses, 100);
    expect(dashboard.pendingExpensesTotal, 50);
    expect(dashboard.approvedExpenses, hasLength(1));
    expect(dashboard.pendingExpenses, hasLength(1));
  });

  test('separa facturado, pagado y saldo pendiente de proveedor', () {
    final purchase = _purchase(total: 1000, paid: 600, balance: 400);
    final payment = _supplierPayment(amount: 600);
    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: const [],
        withdrawals: const [],
        purchases: [purchase],
        supplierPayments: [payment],
        suppliers: const [],
      ),
    );

    expect(dashboard.supplierInvoicesTotal, 1000);
    expect(dashboard.supplierPaidTotal, 600);
    expect(dashboard.pendingSupplierInvoices, 400);
    expect(dashboard.supplierRows.single.balance, 400);
  });

  test('aplica exactamente las tres formulas financieras', () {
    final order = _order('summary', businessDate: '2026-07-12');
    final payment = _payment('summary-payment', order.id, amount: 9000);
    final summary = buildCanonicalSalesSummary([
      SalesOrderBundleInput(
        order: order,
        items: [_item(10000)],
        payments: [payment],
      ),
    ]);
    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: summary,
        paymentsByOrder: {
          order.id: [payment],
        },
        cashSessions: [
          _cashSession(
            id: 'cut-summary',
            countedCashAmount: 0,
            terminalReportedAmount: 9000,
            expectedCardChargedAmount: 9000,
          ),
        ],
        withdrawals: [_expense('approved', 1000)],
        purchases: [_purchase(total: 4000, paid: 3000, balance: 1000)],
        supplierPayments: [_supplierPayment(amount: 3000)],
        suppliers: const [],
      ),
    );

    expect(dashboard.generalResult, 4000);
    expect(dashboard.collectionsResult, 5000);
    expect(dashboard.finalResult, 4000);
  });

  test('concilia gastos visibles, otros y total del KPI', () {
    final entries = <FinanceBreakdownEntry<String>>[
      const FinanceBreakdownEntry(
        label: 'Refresco',
        amount: 315,
        source: 'refresco',
      ),
      const FinanceBreakdownEntry(label: 'Uber', amount: 198, source: 'uber'),
      const FinanceBreakdownEntry(
        label: 'Tortillas para gringas',
        amount: 124,
        source: 'tortillas',
      ),
      const FinanceBreakdownEntry(
        label: 'Propina',
        amount: 123,
        source: 'propina',
      ),
      for (var index = 0; index < 60; index++)
        FinanceBreakdownEntry(
          label: 'Gasto menor $index',
          amount: 100,
          source: 'menor-$index',
        ),
      const FinanceBreakdownEntry(
        label: 'Gasto menor final',
        amount: 27.20,
        source: 'menor-final',
      ),
    ];

    final breakdown = buildReconciledBreakdown(
      entries: entries,
      expectedTotal: 6787.20,
    );

    expect(breakdown.visibleTotal, 760);
    expect(breakdown.otherTotal, 6027.20);
    expect(breakdown.reconciledTotal, 6787.20);
    expect(breakdown.hiddenEntries, hasLength(61));
    expect(breakdown.isValid, isTrue);
  });

  test('concilia proveedores por monto descendente', () {
    final breakdown = buildReconciledBreakdown<String>(
      entries: const [
        FinanceBreakdownEntry(
          label: 'Proveedor A',
          amount: 15283.50,
          source: 'a',
        ),
        FinanceBreakdownEntry(label: 'Proveedor B', amount: 9000, source: 'b'),
        FinanceBreakdownEntry(label: 'Proveedor C', amount: 3996, source: 'c'),
        FinanceBreakdownEntry(label: 'Proveedor D', amount: 3000, source: 'd'),
        FinanceBreakdownEntry(label: 'Proveedor E', amount: 2500, source: 'e'),
        FinanceBreakdownEntry(label: 'Proveedor F', amount: 2000, source: 'f'),
        FinanceBreakdownEntry(
          label: 'Proveedor G',
          amount: 1773.90,
          source: 'g',
        ),
      ],
      expectedTotal: 37553.40,
    );

    expect(breakdown.visibleEntries.map((entry) => entry.source), [
      'a',
      'b',
      'c',
      'd',
    ]);
    expect(breakdown.visibleTotal, 31279.50);
    expect(breakdown.otherTotal, 6273.90);
    expect(breakdown.reconciledTotal, 37553.40);
    expect(breakdown.isValid, isTrue);
  });

  test('pagos a proveedores concilian sin Otros con tres metodos', () {
    final breakdown = buildReconciledBreakdown<String>(
      entries: const [
        FinanceBreakdownEntry(
          label: 'Efectivo',
          amount: 12820.90,
          source: 'cash',
        ),
        FinanceBreakdownEntry(
          label: 'Transferencia',
          amount: 11641.77,
          source: 'transfer',
        ),
        FinanceBreakdownEntry(
          label: 'Aportacion de socios',
          amount: 5483.04,
          source: 'partner_contribution',
        ),
      ],
      expectedTotal: 29945.71,
      visibleLimit: 3,
    );

    expect(breakdown.hasOther, isFalse);
    expect(breakdown.reconciledTotal, 29945.71);
    expect(breakdown.isValid, isTrue);
  });

  test('cobrado concilia metodos sin incluir ajustes de caja', () {
    final breakdown = buildReconciledBreakdown<String>(
      entries: const [
        FinanceBreakdownEntry(
          label: 'Efectivo',
          amount: 32811.80,
          source: 'cash',
        ),
        FinanceBreakdownEntry(
          label: 'Tarjeta',
          amount: 9113.50,
          source: 'card',
        ),
      ],
      expectedTotal: 41925.30,
      sortDescending: false,
    );

    expect(breakdown.reconciledTotal, 41925.30);
    expect(breakdown.isValid, isTrue);
    expect(359.46 + 116.88 + 1007.44, isNot(breakdown.expectedTotal));
  });

  test('diferencia negativa real se marca como error y no como Otros', () {
    final breakdown = buildReconciledBreakdown<String>(
      entries: const [
        FinanceBreakdownEntry(label: 'Duplicado', amount: 101, source: 'a'),
      ],
      expectedTotal: 100,
    );

    expect(breakdown.otherTotal, 0);
    expect(breakdown.difference, -1);
    expect(breakdown.isValid, isFalse);
  });

  test(
    'cancelados no cuentan y pago nocturno hereda businessDate de orden',
    () {
      final activeOrder = _order(
        'late',
        businessDate: '2026-07-26',
        createdAt: DateTime(2026, 7, 26, 23, 50),
      );
      final latePayment = _payment(
        'late-payment',
        activeOrder.id,
        amount: 200,
        createdAt: DateTime(2026, 7, 27, 0, 15),
        businessDate: '2026-07-27',
      );
      final cancelledOrder = _order(
        'cancelled-order',
        businessDate: '2026-07-26',
        status: 'cancelled',
        cancelledAt: DateTime(2026, 7, 26),
      );
      final cancelledPayment = _payment(
        'cancelled-payment',
        cancelledOrder.id,
        amount: 500,
      );
      final summary = buildCanonicalSalesSummary([
        SalesOrderBundleInput(
          order: activeOrder,
          items: [_item(200)],
          payments: [latePayment],
        ),
        SalesOrderBundleInput(
          order: cancelledOrder,
          items: [_item(500)],
          payments: [cancelledPayment],
        ),
      ]);
      final dashboard = buildFinanceDashboard(
        FinanceDashboardInput(
          key: key,
          salesSummary: summary,
          paymentsByOrder: {
            activeOrder.id: [latePayment],
            cancelledOrder.id: [cancelledPayment],
          },
          cashSessions: [
            _cashSession(
              id: 'cut-late',
              businessDate: '2026-07-26',
              countedCashAmount: 200,
              expectedCashAmount: 200,
            ),
          ],
          withdrawals: const [],
          purchases: [
            _purchase(total: 400, paid: 0, balance: 0, status: 'cancelled'),
          ],
          supplierPayments: [
            _supplierPayment(amount: 300, status: 'cancelled'),
          ],
          suppliers: const [],
        ),
      );

      expect(dashboard.netSales, 200);
      expect(dashboard.realCollected, 200);
      expect(dashboard.customerPayments.single.businessDate, '2026-07-26');
      expect(dashboard.collectionsByDay.single.businessDate, '2026-07-26');
      expect(dashboard.supplierInvoicesTotal, 0);
      expect(dashboard.supplierPaidTotal, 0);
    },
  );

  test('corte exacto no genera diferencia', () {
    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: [
          _cashSession(
            id: 'exact',
            openingCashAmount: 1000,
            countedCashAmount: 3000,
            terminalReportedAmount: 2000,
            expectedCashAmount: 3000,
            expectedCardChargedAmount: 2000,
          ),
        ],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    expect(dashboard.realCollected, 4000);
    expect(dashboard.expectedMonetaryIncome, 4000);
    expect(dashboard.cashShortages, 0);
    expect(dashboard.cashOverages, 0);
  });

  test('sobrante de corte aumenta ingreso real sin limitarlo a venta', () {
    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: [
          _cashSession(
            id: 'over',
            openingCashAmount: 1000,
            countedCashAmount: 3020,
            terminalReportedAmount: 2000,
            expectedCashAmount: 3000,
            expectedCardChargedAmount: 2000,
          ),
        ],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    expect(dashboard.realCollected, 4020);
    expect(dashboard.cashOverages, 20);
    expect(dashboard.cashShortages, 0);
  });

  test('fondo no cuenta como ingreso ni se resta dos veces con retiros', () {
    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: [
          _cashSession(
            id: 'float',
            openingCashAmount: 1000,
            approvedWithdrawalsTotal: 100,
            countedCashAmount: 2900,
            terminalReportedAmount: 0,
            expectedCashAmount: 2900,
          ),
        ],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    expect(dashboard.cashCollected, 2000);
    expect(dashboard.expectedMonetaryIncome, 2000);
    expect(dashboard.cashShortages, 0);
  });

  test('dia sin corte conserva venta pero no confirma ingreso financiero', () {
    final order = _order('no-cut', businessDate: '2026-07-12');
    final payment = _payment('no-cut-payment', order.id, amount: 4000);
    final summary = buildCanonicalSalesSummary([
      SalesOrderBundleInput(
        order: order,
        items: [_item(4000)],
        payments: [payment],
      ),
    ]);

    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: summary,
        paymentsByOrder: {
          order.id: [payment],
        },
        cashSessions: const [],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    expect(dashboard.netSales, 4000);
    expect(dashboard.realCollected, 0);
    expect(dashboard.collectionsByDay.single.realCollected, 0);
  });

  test('varios cortes cerrados del dia se suman y abiertos se excluyen', () {
    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: [
          _cashSession(
            id: 'morning',
            openingCashAmount: 500,
            countedCashAmount: 1500,
            terminalReportedAmount: 1000,
            expectedCashAmount: 1500,
            expectedCardChargedAmount: 1000,
          ),
          _cashSession(
            id: 'night',
            openingCashAmount: 500,
            countedCashAmount: 2500,
            terminalReportedAmount: 2000,
            expectedCashAmount: 2500,
            expectedCardChargedAmount: 2000,
          ),
          _cashSession(
            id: 'open',
            status: 'open',
            countedCashAmount: 999,
            terminalReportedAmount: 999,
          ),
          _cashSession(
            id: 'cancelled',
            status: 'cancelled',
            countedCashAmount: 999,
            terminalReportedAmount: 999,
          ),
        ],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    expect(dashboard.cashCutSummaries, hasLength(2));
    expect(dashboard.cashCollected, 3000);
    expect(dashboard.cardCollected, 3000);
    expect(dashboard.realCollected, 6000);
  });

  test('descuentos y comida de empleado no incrementan ingreso monetario', () {
    final order = _order('discounts', businessDate: '2026-07-12');
    final cash = _payment('cash-discount', order.id, amount: 4000);
    final employeeMeal = _payment(
      'meal',
      order.id,
      amount: 100,
      method: 'employee_consumption',
    );
    final summary = buildCanonicalSalesSummary([
      SalesOrderBundleInput(
        order: order,
        items: [_item(4100)],
        payments: [cash, employeeMeal],
      ),
    ]);
    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: summary,
        paymentsByOrder: {
          order.id: [cash, employeeMeal],
        },
        cashSessions: [
          _cashSession(
            id: 'meal-cut',
            countedCashAmount: 4000,
            expectedCashAmount: 4000,
            expectedEmployeeConsumptionAmount: 100,
          ),
        ],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    expect(dashboard.grossSales, 4100);
    expect(dashboard.realCollected, 4000);
    expect(dashboard.expectedMonetaryIncome, 4000);
    expect(dashboard.employeeConsumption, 100);
    expect(dashboard.cashShortages, 0);
  });

  test('cache comparte cargas simultaneas e invalida solo la clave', () async {
    final cache = FinanceDashboardCache();
    final completer = Completer<FinanceDashboardBundle>();
    var loads = 0;

    Future<FinanceDashboardBundle> loader() {
      loads++;
      return completer.future;
    }

    final first = cache.load(key: key, loader: loader);
    final second = cache.load(key: key, loader: loader);
    expect(loads, 1);
    completer.complete(_emptyDashboard(key));
    final results = await Future.wait([first, second]);
    expect(results.last.sharedInFlight, isTrue);

    final cached = await cache.load(key: key, loader: loader);
    expect(cached.fromCache, isTrue);
    cache.invalidate(key);
    await cache.load(
      key: key,
      loader: () async {
        loads++;
        return _emptyDashboard(key);
      },
    );
    expect(loads, 2);
  });

  test('Excel contiene las siete hojas y el periodo operativo', () {
    final dashboard = _emptyDashboard(key);
    final bytes = buildFinanceDashboardWorkbook(
      bundle: dashboard,
      restaurantName: 'Los Padrinos',
      branchName: 'Aviacion',
      generatedAt: DateTime(2026, 7, 27, 12),
    );
    final workbook = Excel.decodeBytes(bytes);

    expect(
      workbook.tables.keys,
      containsAll([
        'Resumen',
        'Ventas',
        'Cobros',
        'Gastos',
        'Facturas proveedor',
        'Pagos proveedores',
        'Acumulado proveedor',
      ]),
    );
    final summaryText = workbook.tables['Resumen']!.rows
        .expand((row) => row)
        .map((cell) => cell?.value?.toString() ?? '')
        .join(' ');
    expect(summaryText, contains('2026-07-01 al 2026-07-31'));
  });

  test('permiso financiero acepta Finanzas y Admin, y rechaza mesero', () {
    expect(canViewFinanceDashboard(_employee(canViewPurchases: true)), isTrue);
    expect(canViewFinanceDashboard(_employee(canViewAdmin: true)), isTrue);
    expect(canViewFinanceDashboard(_employee()), isFalse);
  });
}

final _emptySales = buildCanonicalSalesSummary(const []);

FinanceDashboardBundle _emptyDashboard(FinanceDashboardKey key) {
  return buildFinanceDashboard(
    FinanceDashboardInput(
      key: key,
      salesSummary: _emptySales,
      paymentsByOrder: const {},
      cashSessions: const [],
      withdrawals: const [],
      purchases: const [],
      supplierPayments: const [],
      suppliers: const [],
    ),
  );
}

PosOrder _order(
  String id, {
  String businessDate = '2026-07-12',
  String status = 'paid',
  DateTime? createdAt,
  DateTime? cancelledAt,
}) {
  return PosOrder(
    id: id,
    tableId: 'table',
    tableName: 'Mesa 1',
    status: status,
    kitchenStatus: 'ready',
    paymentStatus: 'paid',
    total: 0,
    paidTotal: 0,
    pendingTotal: 0,
    personNames: const {},
    orderType: 'dine_in',
    businessDate: businessDate,
    createdAt: createdAt,
    cancelledAt: cancelledAt,
  );
}

extension on PosOrder {
  PosOrder copyForTest({
    Map<String, double> explicitDiscountFields = const {},
  }) {
    return PosOrder(
      id: id,
      tableId: tableId,
      tableName: tableName,
      status: status,
      kitchenStatus: kitchenStatus,
      paymentStatus: paymentStatus,
      total: total,
      paidTotal: paidTotal,
      pendingTotal: pendingTotal,
      personNames: personNames,
      orderType: orderType,
      businessDate: businessDate,
      createdAt: createdAt,
      explicitDiscountFields: explicitDiscountFields,
    );
  }
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
    kitchenStatus: 'ready',
    paymentStatus: 'paid',
  );
}

Payment _payment(
  String id,
  String orderId, {
  required double amount,
  String method = 'cash',
  double? received,
  double? change,
  String? businessDate,
  DateTime? createdAt,
  String status = 'active',
  DateTime? cancelledAt,
}) {
  return Payment(
    id: id,
    orderId: orderId,
    tableId: 'table',
    tableName: 'Mesa 1',
    type: 'full_table',
    method: method,
    baseAmount: amount,
    surchargeRate: 0,
    surchargeAmount: 0,
    chargedAmount: amount,
    appliedAmount: amount,
    cashReceivedAmount: received,
    cashChangeAmount: change,
    businessDate: businessDate,
    createdAt: createdAt,
    status: status,
    cancelledAt: cancelledAt,
  );
}

CashWithdrawalRequest _expense(
  String status,
  double amount, {
  String source = '',
  String businessDate = '2026-07-12',
  String cashSessionId = 'cash',
}) {
  return CashWithdrawalRequest(
    id: '$status-$amount',
    cashSessionId: cashSessionId,
    businessDate: businessDate,
    amount: amount,
    reason: status,
    requestedByEmployeeId: 'employee',
    requestedByEmployeeName: 'Empleado',
    status: status,
    source: source,
  );
}

CashSession _cashSession({
  required String id,
  String businessDate = '2026-07-12',
  String status = 'closed',
  double openingCashAmount = 0,
  double countedCashAmount = 0,
  double terminalReportedAmount = 0,
  double expectedCashAmount = 0,
  double expectedCardChargedAmount = 0,
  double expectedPlatformAmount = 0,
  double expectedEmployeeConsumptionAmount = 0,
  double approvedWithdrawalsTotal = 0,
  String? closedByEmployeeName,
}) {
  final netDifference =
      (countedCashAmount + terminalReportedAmount) -
      (expectedCashAmount + expectedCardChargedAmount);
  return CashSession(
    id: id,
    businessDate: businessDate,
    status: status,
    openingCashAmount: openingCashAmount,
    openedByEmployeeId: 'employee',
    openedByEmployeeName: 'Empleado',
    closedByEmployeeId: closedByEmployeeName == null ? null : 'closer',
    closedByEmployeeName: closedByEmployeeName,
    countedCashAmount: countedCashAmount,
    terminalReportedAmount: terminalReportedAmount,
    expectedCashAmount: expectedCashAmount,
    expectedCardChargedAmount: expectedCardChargedAmount,
    expectedCardBaseAmount: expectedCardChargedAmount,
    expectedCardSurchargeAmount: 0,
    expectedCardFeeAbsorbedAmount: 0,
    expectedPlatformAmount: expectedPlatformAmount,
    expectedEmployeeConsumptionAmount: expectedEmployeeConsumptionAmount,
    totalExpectedRealMoney: expectedCashAmount + expectedCardChargedAmount,
    totalCountedRealMoney: countedCashAmount + terminalReportedAmount,
    cashDifference: countedCashAmount - expectedCashAmount,
    cardDifference: terminalReportedAmount - expectedCardChargedAmount,
    netDifference: netDifference,
    shortageAmount: netDifference < 0 ? netDifference.abs() : 0,
    overAmount: netDifference > 0 ? netDifference : 0,
    approvedWithdrawalsTotal: approvedWithdrawalsTotal,
    pendingWithdrawalsTotal: 0,
    withdrawalRequestCount: 0,
    notes: '',
  );
}

SupplierPurchase _purchase({
  required double total,
  required double paid,
  required double balance,
  String status = 'partial',
}) {
  return SupplierPurchase(
    id: 'purchase-$total-$status',
    supplierId: 'supplier',
    supplierName: 'Proveedor',
    purchaseDate: DateTime(2026, 7, 12),
    businessDate: '2026-07-12',
    folio: 'F-1',
    documentType: 'invoice',
    status: status,
    subtotal: total,
    total: total,
    paidTotal: paid,
    balance: balance,
  );
}

SupplierPayment _supplierPayment({
  required double amount,
  String status = 'active',
  String method = 'transfer',
}) {
  return SupplierPayment(
    id: 'supplier-payment-$amount-$status',
    supplierId: 'supplier',
    supplierName: 'Proveedor',
    purchaseId: 'purchase',
    purchaseFolio: 'F-1',
    paymentDate: DateTime(2026, 7, 12),
    businessDate: '2026-07-12',
    amount: amount,
    method: method,
    status: status,
  );
}

Employee _employee({bool canViewAdmin = false, bool canViewPurchases = false}) {
  return Employee(
    id: 'employee',
    name: 'Empleado',
    active: true,
    pin: '',
    canTakeOrders: false,
    canCharge: false,
    canViewKitchen: false,
    canViewAdmin: canViewAdmin,
    canManageProducts: false,
    canManageTables: false,
    canManagePlatforms: false,
    canManageEmployees: false,
    canManageCash: false,
    canAuthorizeCashWithdrawals: false,
    canOpenKitchen: false,
    canCloseKitchen: false,
    canViewKitchenReports: false,
    canViewKitchenHourlySalesComparison: false,
    canManageKitchenStock: false,
    canCancelOrders: false,
    canCancelPayments: false,
    canCancelItems: false,
    canApproveKitchenCancellations: false,
    canViewLiveOperations: false,
    canControlLiveOperations: false,
    canViewPurchases: canViewPurchases,
  );
}
