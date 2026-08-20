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
        withdrawals: [
          _expense(
            'approved',
            500,
            cashSessionId: 'cut-with-opening',
            source: 'cash_drawer',
          ),
        ],
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
        withdrawals: [
          _expense(
            'approved',
            500,
            cashSessionId: 'cut-with-opening',
            source: 'cash_drawer',
          ),
        ],
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

  test('tarjeta de cortes se muestra neta de comision sin tocar venta', () {
    final order = _order('net-card-fixture', businessDate: '2026-07-12');
    final payment = _payment(
      'net-card-payment',
      order.id,
      amount: 26332.80,
      method: 'card',
    );
    final summary = buildCanonicalSalesSummary([
      SalesOrderBundleInput(
        order: order,
        items: [_item(26332.80)],
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
            id: 'cut-shortage',
            countedCashAmount: 10000,
            terminalReportedAmount: 6021.70,
            expectedCashAmount: 10752.90,
            expectedCardChargedAmount: 6021.70,
            expectedCardFeeAbsorbedAmount: 238,
          ),
          _cashSession(
            id: 'cut-overage',
            countedCashAmount: 9577,
            expectedCashAmount: 9165.20,
          ),
        ],
        withdrawals: [_expense('approved', 100)],
        purchases: [_purchase(total: 500, paid: 100, balance: 400)],
        supplierPayments: [_supplierPayment(amount: 100)],
        suppliers: const [],
      ),
    );

    expect(dashboard.netSales, 26332.80);
    expect(dashboard.cashCollected, 19577);
    expect(dashboard.cardGrossCollected, 6021.70);
    expect(dashboard.cardFees, 238);
    expect(dashboard.cardCollected, 5783.70);
    expect(dashboard.realCollected, 25360.70);
    expect(dashboard.expectedMonetaryGrossIncome, 25939.80);
    expect(dashboard.expectedMonetaryIncome, 25701.80);
    expect(dashboard.cashShortages, 752.90);
    expect(dashboard.cashOverages, 411.80);
    expect(
      dashboard.expectedMonetaryIncome - dashboard.realCollected,
      closeTo(341.10, 0.001),
    );
    expect(dashboard.paidExpenses, 100);
    expect(dashboard.supplierInvoicesTotal, 500);
    expect(dashboard.supplierPaidTotal, 100);
    expect(dashboard.pendingSupplierInvoices, 400);

    final day = dashboard.cashCutDailyDetails.single;
    expect(day.cardGrossReceived, 6021.70);
    expect(day.cardFees, 238);
    expect(day.cardReceived, 5783.70);
    expect(day.actualIncome, 25360.70);

    final bytes = buildFinanceDashboardWorkbook(
      bundle: dashboard,
      restaurantName: 'Los Padrinos',
      branchName: 'Aviacion',
      generatedAt: DateTime(2026, 7, 27, 12),
    );
    final workbook = Excel.decodeBytes(bytes);
    final summaryText = workbook.tables['Resumen']!.rows
        .expand((row) => row)
        .map((cell) => cell?.value?.toString() ?? '')
        .join(' ');
    final collectionsText = workbook.tables['Cobros']!.rows
        .expand((row) => row)
        .map((cell) => cell?.value?.toString() ?? '')
        .join(' ');

    expect(summaryText, contains('Tarjeta neta de cortes'));
    expect(summaryText, contains('Monetario esperado neto'));
    expect(collectionsText, contains('Tarjeta bruta'));
    expect(collectionsText, contains('Comision tarjeta'));
    expect(collectionsText, contains('Tarjeta neta'));
  });

  test(
    'desglose de gastos agrupa conceptos iguales y conserva movimientos',
    () {
      final dashboard = buildFinanceDashboard(
        FinanceDashboardInput(
          key: key,
          salesSummary: _emptySales,
          paymentsByOrder: const {},
          cashSessions: const [],
          withdrawals: [
            _expense('approved', 630, reason: 'Refresco'),
            _expense('approved', 315, reason: ' refresco  '),
            _expense('approved', 40, reason: 'Hielo'),
            _expense('approved', 40, reason: 'hielo'),
            _expense('approved', 38, reason: ' HIELO '),
            _expense('approved', 38, reason: 'hielo  '),
            _expense('approved', 38, reason: 'hielo'),
            _expense('approved', 20, reason: 'Refresco personal'),
            _expense('approved', 10, reason: 'Refresco   personal'),
          ],
          purchases: const [],
          supplierPayments: const [],
          suppliers: const [],
        ),
      );

      final entries = financeExpenseBreakdownEntries(dashboard);
      final breakdown = buildReconciledBreakdown(
        entries: entries,
        expectedTotal: dashboard.paidExpenses,
        visibleLimit: entries.length,
      );
      final byLabel = {for (final entry in entries) entry.label: entry};

      expect(entries.map((entry) => entry.label), [
        'Refresco',
        'Hielo',
        'Refresco Personal',
      ]);
      expect(byLabel['Refresco']!.amount, 945);
      expect(byLabel['Hielo']!.amount, 194);
      expect(byLabel['Refresco Personal']!.amount, 30);
      expect(byLabel['Refresco']!.source.movements, hasLength(2));
      expect(byLabel['Hielo']!.source.movements, hasLength(5));
      expect(byLabel['Refresco Personal']!.source.movements, hasLength(2));
      expect(dashboard.approvedExpenses, hasLength(9));
      expect(dashboard.paidExpenses, 1169);
      expect(breakdown.reconciledTotal, dashboard.paidExpenses);
      expect(breakdown.hasOther, isFalse);
    },
  );

  test(
    'desglose completo de proveedores muestra todos sin otros y ordena monto',
    () {
      for (final count in [1, 5, 20]) {
        final dashboard = buildFinanceDashboard(
          FinanceDashboardInput(
            key: key,
            salesSummary: _emptySales,
            paymentsByOrder: const {},
            cashSessions: const [],
            withdrawals: const [],
            purchases: [
              for (var index = 0; index < count; index++)
                _purchase(
                  total: (count - index) * 100,
                  paid: 0,
                  balance: (count - index) * 100,
                  supplierId: 'supplier-$index',
                  supplierName: 'Proveedor ${index + 1}',
                ),
            ],
            supplierPayments: const [],
            suppliers: const [],
          ),
        );

        final entries = financeSupplierInvoiceBreakdownEntries(dashboard);
        final breakdown = buildReconciledBreakdown(
          entries: entries,
          expectedTotal: dashboard.supplierInvoicesTotal,
          visibleLimit: entries.length,
        );

        expect(entries, hasLength(count));
        expect(breakdown.visibleEntries, hasLength(count));
        expect(breakdown.hasOther, isFalse);
        expect(
          breakdown.visibleEntries.map((entry) => entry.label),
          isNot(contains('Otros proveedores')),
        );
        expect(breakdown.reconciledTotal, dashboard.supplierInvoicesTotal);
        expect(
          entries.map((entry) => entry.amount),
          orderedEquals(
            entries.map((entry) => entry.amount).toList()
              ..sort((a, b) => b.compareTo(a)),
          ),
        );
      }
    },
  );

  test('resumen compartible usa rango, sucursal y valores netos actuales', () {
    const weeklyKey = FinanceDashboardKey(
      restaurantId: 'restaurant',
      branchId: 'aviacion',
      startBusinessDate: '2026-08-10',
      endBusinessDate: '2026-08-16',
    );
    final order = _order('summary-share', businessDate: '2026-08-10');
    final payment = _payment(
      'summary-share-payment',
      order.id,
      amount: 26332.80,
      method: 'card',
    );
    final summary = buildCanonicalSalesSummary([
      SalesOrderBundleInput(
        order: order,
        items: [_item(26332.80)],
        payments: [payment],
      ),
    ]);
    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: weeklyKey,
        salesSummary: summary,
        paymentsByOrder: {
          order.id: [payment],
        },
        cashSessions: [
          _cashSession(
            id: 'cut-share-shortage',
            businessDate: '2026-08-10',
            countedCashAmount: 10000,
            terminalReportedAmount: 6021.70,
            expectedCashAmount: 10752.90,
            expectedCardChargedAmount: 6021.70,
            expectedCardFeeAbsorbedAmount: 238,
          ),
          _cashSession(
            id: 'cut-share-overage',
            businessDate: '2026-08-11',
            countedCashAmount: 9577,
            expectedCashAmount: 9165.20,
          ),
        ],
        withdrawals: [
          _expense(
            'approved',
            630,
            reason: 'Refresco',
            businessDate: '2026-08-10',
          ),
          _expense(
            'approved',
            315,
            reason: 'refresco',
            businessDate: '2026-08-10',
          ),
          _expense(
            'approved',
            300,
            reason: 'Brenda',
            businessDate: '2026-08-11',
          ),
          _expense(
            'approved',
            200,
            reason: 'traslado puesto',
            businessDate: '2026-08-12',
          ),
          _expense(
            'approved',
            150,
            reason: 'hielo',
            businessDate: '2026-08-13',
          ),
          _expense(
            'approved',
            120,
            reason: 'garrafon',
            businessDate: '2026-08-14',
          ),
          _expense(
            'approved',
            300,
            reason: 'cinta aislante',
            businessDate: '2026-08-15',
          ),
        ],
        purchases: [
          _purchase(
            total: 11742.70,
            paid: 11742.70,
            balance: 0,
            supplierId: 'omar',
            supplierName: 'Carniceria Omar',
            businessDate: '2026-08-10',
          ),
          _purchase(
            total: 5100,
            paid: 5100,
            balance: 0,
            supplierId: 'ricardo',
            supplierName: 'Ricardo Bernal',
            businessDate: '2026-08-11',
          ),
          _purchase(
            total: 2421,
            paid: 2421,
            balance: 0,
            supplierId: 'rafa',
            supplierName: 'Rafa Verdura',
            businessDate: '2026-08-12',
          ),
          _purchase(
            total: 6494.66,
            paid: 6494.66,
            balance: 0,
            supplierId: 'varios',
            supplierName: 'Varios',
            businessDate: '2026-08-13',
          ),
        ],
        supplierPayments: [
          _supplierPayment(
            amount: 15758.36,
            method: 'cash',
            businessDate: '2026-08-14',
          ),
          _supplierPayment(
            amount: 10000,
            method: 'transfer',
            businessDate: '2026-08-15',
          ),
        ],
        suppliers: const [],
      ),
    );

    final text = financeWhatsappSummaryText(
      bundle: dashboard,
      restaurantName: "Los Padrino's Tacos",
      branchName: 'Aviacion',
      generatedAt: DateTime(2026, 8, 17, 14, 30),
    );

    expect(financePeriodSummaryTitle(weeklyKey), 'Resumen semanal');
    expect(text, contains("LOS PADRINO'S TACOS"));
    expect(text, contains('AVIACION'));
    expect(text, contains('10/08/2026 - 16/08/2026'));
    expect(text, contains('Venta neta: \$26,332.80'));
    expect(text, contains('Efectivo: \$19,577.00'));
    expect(text, contains('Tarjeta neta: \$5,783.70'));
    expect(text, contains('Ingreso real: \$25,360.70'));
    expect(text, contains('Comisiones de tarjeta: \$238.00'));
    expect(text, contains('Refresco: \$945.00'));
    expect(text, isNot(contains('refresco: \$315.00')));
    expect(text, contains('Total gastos: \$2,015.00'));
    expect(text, contains('Total facturado: \$25,758.36'));
    expect(text, contains('Total pagado: \$25,758.36'));
    expect(text, contains('FACTURAS PENDIENTES\n\$0.00'));
    expect(text, contains('RESUMEN FINANCIERO'));
    expect(text, contains('SUMA'));
    expect(text, contains('Cobrado real: \$25,360.70'));
    expect(text, contains('RESTA'));
    expect(text, contains('Gastos: -\$2,015.00'));
    expect(text, contains('Facturas proveedor: -\$25,758.36'));
    expect(text, contains('Resultado operativo: -\$2,412.66'));
    expect(text, contains('APORTACIONES'));
    expect(text, contains('Aportacion de socios: \$0.00'));
    expect(text, contains('CONCILIACION'));
    expect(text, contains('Diferencia por conciliar: -\$2,412.66'));
    expect(text, isNot(contains('Otros gastos')));
    expect(text, isNot(contains('Otros proveedores')));
    expect(
      financeSummaryImageFileName(bundle: dashboard, branchName: 'Aviacion'),
      'Resumen-Financiero-Aviacion-10-08-2026-al-16-08-2026.png',
    );
  });

  test('rango no semanal usa titulo resumen financiero', () {
    const customKey = FinanceDashboardKey(
      restaurantId: 'restaurant',
      branchId: 'branch',
      startBusinessDate: '2026-08-01',
      endBusinessDate: '2026-08-15',
    );

    expect(financePeriodSummaryTitle(customKey), 'Resumen financiero');
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
            source: 'cash_drawer',
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

  test('gasto historico posterior al corte no aumenta efectivo', () {
    final closedAt = DateTime(2026, 8, 15, 23, 59);
    final createdAfterClose = DateTime(2026, 8, 17, 10);
    const augustKey = FinanceDashboardKey(
      restaurantId: 'restaurant',
      branchId: 'branch',
      startBusinessDate: '2026-08-15',
      endBusinessDate: '2026-08-15',
    );

    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: augustKey,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: [
          _cashSession(
            id: 'cut-2026-08-15',
            businessDate: '2026-08-15',
            countedCashAmount: 3000,
            expectedCashAmount: 3000,
            approvedWithdrawalsTotal: 0,
            closedAt: closedAt,
          ),
        ],
        withdrawals: [
          _expense(
            'approved',
            66,
            businessDate: '2026-08-15',
            cashSessionId: 'cut-2026-08-15',
            source: 'historical_admin',
            reason: 'cuenta mal cobrada',
            createdAt: createdAfterClose,
            requestedAt: createdAfterClose,
            approvedAt: createdAfterClose,
            isHistorical: true,
          ),
        ],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    final day = dashboard.cashCutDailyDetails.single;
    expect(day.cashCounted, 3000);
    expect(day.cashExpensesPaid, 0);
    expect(day.cashOperationalBeforeExpenses, 3000);
    expect(dashboard.cashCollected, 3000);
    expect(dashboard.paidExpenses, 66);
    expect(dashboard.finalResult, 2934);
  });

  test(
    'gasto real de caja antes del cierre reconstruye efectivo una sola vez',
    () {
      final closedAt = DateTime(2026, 8, 15, 23, 59);
      final approvedAt = DateTime(2026, 8, 15, 18);
      const augustKey = FinanceDashboardKey(
        restaurantId: 'restaurant',
        branchId: 'branch',
        startBusinessDate: '2026-08-15',
        endBusinessDate: '2026-08-15',
      );

      final dashboard = buildFinanceDashboard(
        FinanceDashboardInput(
          key: augustKey,
          salesSummary: _emptySales,
          paymentsByOrder: const {},
          cashSessions: [
            _cashSession(
              id: 'cut-real-cash',
              businessDate: '2026-08-15',
              countedCashAmount: 3000,
              expectedCashAmount: 3000,
              approvedWithdrawalsTotal: 500,
              closedAt: closedAt,
            ),
          ],
          withdrawals: [
            _expense(
              'approved',
              500,
              businessDate: '2026-08-15',
              cashSessionId: 'cut-real-cash',
              source: 'cash_drawer',
              createdAt: approvedAt,
              requestedAt: approvedAt,
              approvedAt: approvedAt,
            ),
          ],
          purchases: const [],
          supplierPayments: const [],
          suppliers: const [],
        ),
      );

      final day = dashboard.cashCutDailyDetails.single;
      expect(day.cashExpensesPaid, 500);
      expect(day.cashOperationalBeforeExpenses, 3500);
      expect(dashboard.cashCollected, 3500);
      expect(dashboard.paidExpenses, 500);
      expect(dashboard.finalResult, 3000);
    },
  );

  test('transferencia tarjeta y otra sesion no reconstruyen caja', () {
    final closedAt = DateTime(2026, 8, 15, 23, 59);
    final beforeClose = DateTime(2026, 8, 15, 18);
    final afterClose = DateTime(2026, 8, 16, 1);
    const augustKey = FinanceDashboardKey(
      restaurantId: 'restaurant',
      branchId: 'branch',
      startBusinessDate: '2026-08-15',
      endBusinessDate: '2026-08-15',
    );

    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: augustKey,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: [
          _cashSession(
            id: 'cut-non-cash',
            businessDate: '2026-08-15',
            countedCashAmount: 3500,
            expectedCashAmount: 2600,
            approvedWithdrawalsTotal: 650,
            closedAt: closedAt,
          ),
        ],
        withdrawals: [
          _expense(
            'approved',
            300,
            businessDate: '2026-08-15',
            cashSessionId: 'cut-non-cash',
            source: 'transfer',
            approvedAt: beforeClose,
          ),
          _expense(
            'approved',
            200,
            businessDate: '2026-08-15',
            cashSessionId: 'cut-non-cash',
            source: 'card',
            approvedAt: beforeClose,
          ),
          _expense(
            'approved',
            250,
            businessDate: '2026-08-15',
            cashSessionId: 'other-cut',
            source: 'cash_drawer',
            approvedAt: beforeClose,
          ),
          _expense(
            'approved',
            150,
            businessDate: '2026-08-15',
            cashSessionId: 'cut-non-cash',
            source: 'cash_drawer',
            approvedAt: afterClose,
          ),
        ],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    final day = dashboard.cashCutDailyDetails.single;
    expect(day.cashExpensesPaid, 650);
    expect(day.cashOperationalBeforeExpenses, 4150);
    expect(dashboard.paidExpenses, 900);
    expect(dashboard.finalResult, 3250);
  });

  test('fixture real identifica 102 y conserva solo gasto caja legitimo', () {
    final closedAt = DateTime(2026, 8, 15, 23, 59);
    final afterClose = DateTime(2026, 8, 17, 10);
    const augustKey = FinanceDashboardKey(
      restaurantId: 'restaurant',
      branchId: 'branch',
      startBusinessDate: '2026-08-15',
      endBusinessDate: '2026-08-15',
    );

    final session = _cashSession(
      id: 'cut-real-regression',
      businessDate: '2026-08-15',
      countedCashAmount: 19541,
      terminalReportedAmount: 6021.70,
      expectedCashAmount: 19816.10,
      expectedCardChargedAmount: 6021.70,
      expectedCardFeeAbsorbedAmount: 238.47,
      approvedWithdrawalsTotal: 102,
      shortageAmount: 686.90,
      overAmount: 411.80,
      closedAt: closedAt,
    );
    final withdrawals = [
      _expense(
        'approved',
        66,
        businessDate: '2026-08-15',
        cashSessionId: session.id,
        source: 'historical_admin',
        reason: 'cuenta mal cobrada',
        createdAt: afterClose,
        requestedAt: afterClose,
        approvedAt: afterClose,
        isHistorical: true,
      ),
      _expense(
        'approved',
        36,
        businessDate: '2026-08-15',
        cashSessionId: session.id,
        source: 'cash_drawer',
        reason: 'Errores De Cambio De Gael',
        createdAt: afterClose,
        requestedAt: afterClose,
        approvedAt: afterClose,
      ),
      _expense(
        'approved',
        1979,
        businessDate: '2026-08-15',
        cashSessionId: 'supplier-or-admin',
        source: 'transfer',
        reason: 'Otros gastos',
      ),
    ];

    final trace = financeCashExpenseReconciliationTrace(session, withdrawals);
    expect(
      trace
          .where((row) => row.includedBeforeV103 && !row.includedNow)
          .fold<double>(0, (sum, row) => sum + row.amount),
      66,
    );
    expect(
      trace.singleWhere((row) => row.amount == 66).reason,
      'explicit_non_cash_drawer',
    );
    expect(trace.singleWhere((row) => row.amount == 36).includedNow, isTrue);

    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: augustKey,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: [session],
        withdrawals: withdrawals,
        purchases: [
          _purchase(
            total: 25758.36,
            paid: 25758.36,
            balance: 0,
            businessDate: '2026-08-15',
          ),
        ],
        supplierPayments: [
          _supplierPayment(
            amount: 25758.36,
            method: 'cash',
            businessDate: '2026-08-15',
          ),
        ],
        suppliers: const [],
      ),
    );

    final day = dashboard.cashCutDailyDetails.single;
    expect(day.cashCounted, 19541);
    expect(day.cashExpensesPaid, 102);
    expect(day.cashOperationalBeforeExpenses, 19643);
    expect(dashboard.cashCollected, 19643);
    expect(dashboard.cardGrossCollected, 6021.70);
    expect(dashboard.cardFees, 238.47);
    expect(dashboard.cardCollected, 5783.23);
    expect(dashboard.realCollected, 25426.23);
    expect(dashboard.expectedMonetaryGrossIncome, 25939.80);
    expect(dashboard.expectedMonetaryIncome, 25701.33);
    expect(dashboard.paidExpenses, 2081);
    expect(dashboard.cashShortages, 686.90);
    expect(dashboard.cashOverages, 411.80);
    expect(dashboard.finalResult, -2413.13);
  });

  test('varios cortes no duplican gasto por misma fecha operativa', () {
    final firstClosedAt = DateTime(2026, 8, 15, 18);
    final secondClosedAt = DateTime(2026, 8, 16, 0, 30);
    final approvedAt = DateTime(2026, 8, 15, 20);
    const augustKey = FinanceDashboardKey(
      restaurantId: 'restaurant',
      branchId: 'branch',
      startBusinessDate: '2026-08-15',
      endBusinessDate: '2026-08-15',
    );

    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: augustKey,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: [
          _cashSession(
            id: 'cut-a',
            businessDate: '2026-08-15',
            countedCashAmount: 1000,
            expectedCashAmount: 1000,
            closedAt: firstClosedAt,
          ),
          _cashSession(
            id: 'cut-b',
            businessDate: '2026-08-15',
            countedCashAmount: 1500,
            expectedCashAmount: 1300,
            approvedWithdrawalsTotal: 200,
            closedAt: secondClosedAt,
          ),
        ],
        withdrawals: [
          _expense(
            'approved',
            200,
            businessDate: '2026-08-15',
            cashSessionId: 'cut-b',
            source: 'cash_drawer',
            approvedAt: approvedAt,
          ),
        ],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    final cuts = dashboard.cashCutDailyDetails.single.cuts;
    expect(
      cuts.singleWhere((row) => row.session.id == 'cut-a').approvedWithdrawals,
      0,
    );
    expect(
      cuts.singleWhere((row) => row.session.id == 'cut-b').approvedWithdrawals,
      200,
    );
    expect(dashboard.cashCollected, 2700);
    expect(dashboard.paidExpenses, 200);
    expect(dashboard.finalResult, 2500);
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
        withdrawals: [
          _expense(
            'approved',
            500,
            cashSessionId: 'cut-with-opening',
            source: 'cash_drawer',
          ),
        ],
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

  test('gasto financiero normal de 66 no cambia ingreso real dos veces', () {
    FinanceDashboardBundle buildWithExpenses(List<CashWithdrawalRequest> rows) {
      return buildFinanceDashboard(
        FinanceDashboardInput(
          key: key,
          salesSummary: _emptySales,
          paymentsByOrder: const {},
          cashSessions: [
            _cashSession(
              id: 'cut-real-66',
              countedCashAmount: 19607,
              terminalReportedAmount: 6021.70,
              expectedCashAmount: 19607,
              expectedCardChargedAmount: 6021.70,
              expectedCardFeeAbsorbedAmount: 238.47,
            ),
          ],
          withdrawals: rows,
          purchases: [_purchase(total: 25758.36, paid: 25758.36, balance: 0)],
          supplierPayments: const [],
          suppliers: const [],
        ),
      );
    }

    final baseDashboard = buildWithExpenses([
      _expense('approved', 2015, cashSessionId: 'admin'),
    ]);
    final withExpenseDashboard = buildWithExpenses([
      _expense('approved', 2015, cashSessionId: 'admin'),
      _expense('approved', 66, cashSessionId: 'cut-real-66'),
    ]);
    final cancelledExpenseDashboard = buildWithExpenses([
      _expense('approved', 2015, cashSessionId: 'admin'),
      _expense('cancelled', 66, cashSessionId: 'cut-real-66'),
    ]);

    expect(baseDashboard.realCollected, 25390.23);
    expect(withExpenseDashboard.realCollected, 25390.23);
    expect(cancelledExpenseDashboard.realCollected, 25390.23);
    expect(baseDashboard.paidExpenses, 2015);
    expect(withExpenseDashboard.paidExpenses, 2081);
    expect(cancelledExpenseDashboard.paidExpenses, 2015);
    expect(baseDashboard.operatingResult, -2383.13);
    expect(withExpenseDashboard.operatingResult, -2449.13);
    expect(cancelledExpenseDashboard.operatingResult, -2383.13);
    expect(
      withExpenseDashboard.operatingResult - baseDashboard.operatingResult,
      closeTo(-66, 0.001),
    );
    expect(
      cancelledExpenseDashboard.operatingResult -
          withExpenseDashboard.operatingResult,
      closeTo(66, 0.001),
    );
  });

  test('cortes cerrados usan snapshot de gastos caja y no gastos actuales', () {
    FinanceDashboardBundle buildClosedCuts({
      CashWithdrawalRequest? variableExpense,
    }) {
      final withdrawals = [
        _expense(
          'approved',
          2015,
          businessDate: '2026-08-15',
          cashSessionId: 'admin',
        ),
        ?variableExpense,
      ];
      return buildFinanceDashboard(
        FinanceDashboardInput(
          key: const FinanceDashboardKey(
            restaurantId: 'restaurant',
            branchId: 'branch',
            startBusinessDate: '2026-08-10',
            endBusinessDate: '2026-08-15',
          ),
          salesSummary: _emptySales,
          paymentsByOrder: const {},
          cashSessions: [
            _cashSession(
              id: 'cut-2026-08-15',
              businessDate: '2026-08-15',
              countedCashAmount: 10000,
              terminalReportedAmount: 6021.70,
              expectedCashAmount: 9985.10,
              expectedCardChargedAmount: 6021.70,
              expectedCardFeeAbsorbedAmount: 238.47,
              approvedWithdrawalsTotal: 446,
              shortageAmount: 686.90,
              overAmount: 411.80,
            ),
            _cashSession(
              id: 'cut-2026-08-14',
              businessDate: '2026-08-14',
              countedCashAmount: 3000,
              expectedCashAmount: 3000,
              approvedWithdrawalsTotal: 285,
              shortageAmount: 0,
              overAmount: 0,
            ),
            _cashSession(
              id: 'cut-2026-08-13',
              businessDate: '2026-08-13',
              countedCashAmount: 2000,
              expectedCashAmount: 2000,
              approvedWithdrawalsTotal: 114,
              shortageAmount: 0,
              overAmount: 0,
            ),
            _cashSession(
              id: 'cut-2026-08-12',
              businessDate: '2026-08-12',
              countedCashAmount: 1500,
              expectedCashAmount: 1500,
              approvedWithdrawalsTotal: 968,
              shortageAmount: 0,
              overAmount: 0,
            ),
            _cashSession(
              id: 'cut-2026-08-11',
              businessDate: '2026-08-11',
              countedCashAmount: 700,
              expectedCashAmount: 700,
              approvedWithdrawalsTotal: 38,
              shortageAmount: 0,
              overAmount: 0,
            ),
            _cashSession(
              id: 'cut-2026-08-10',
              businessDate: '2026-08-10',
              countedCashAmount: 362,
              expectedCashAmount: 688,
              approvedWithdrawalsTotal: 194,
              shortageAmount: 0,
              overAmount: 0,
            ),
          ],
          withdrawals: withdrawals,
          purchases: [
            _purchase(
              total: 25758.36,
              paid: 25758.36,
              balance: 0,
              businessDate: '2026-08-15',
            ),
          ],
          supplierPayments: [
            _supplierPayment(
              amount: 2430,
              method: 'partner_contribution',
              businessDate: '2026-08-15',
            ),
          ],
          suppliers: const [],
        ),
      );
    }

    final baseDashboard = buildClosedCuts();
    final activeDashboard = buildClosedCuts(
      variableExpense: _expense(
        'approved',
        66,
        businessDate: '2026-08-15',
        cashSessionId: 'cut-2026-08-15',
        source: 'historical_admin',
        reason: 'Se dieron 3 tacos menos',
        isHistorical: true,
      ),
    );
    final cancelledDashboard = buildClosedCuts(
      variableExpense: _expense(
        'cancelled',
        66,
        businessDate: '2026-08-15',
        cashSessionId: 'cut-2026-08-15',
        source: 'historical_admin',
        reason: 'Se dieron 3 tacos menos',
        isHistorical: true,
      ),
    );

    for (final dashboard in [
      baseDashboard,
      activeDashboard,
      cancelledDashboard,
    ]) {
      expect(dashboard.cashCutDailyDetails.map((row) => row.cashExpensesPaid), [
        194,
        38,
        968,
        114,
        285,
        446,
      ]);
      expect(dashboard.cashCutPeriodTotal.cashExpensesPaid, 2045);
      expect(dashboard.cashCollected, 19607);
      expect(dashboard.cardGrossCollected, 6021.70);
      expect(dashboard.cardFees, 238.47);
      expect(dashboard.cardCollected, 5783.23);
      expect(dashboard.realCollected, 25390.23);
      expect(dashboard.expectedMonetaryGrossIncome, 25939.80);
      expect(dashboard.expectedMonetaryIncome, 25701.33);
      expect(dashboard.cashShortages, 686.90);
      expect(dashboard.cashOverages, 411.80);
    }

    expect(baseDashboard.paidExpenses, 2015);
    expect(activeDashboard.paidExpenses, 2081);
    expect(cancelledDashboard.paidExpenses, 2015);
    expect(baseDashboard.operatingResult, -2383.13);
    expect(activeDashboard.operatingResult, -2449.13);
    expect(cancelledDashboard.operatingResult, -2383.13);
    expect(
      activeDashboard.operatingResult - baseDashboard.operatingResult,
      closeTo(-66, 0.001),
    );
    expect(baseDashboard.reconciliationDifference, 46.87);
    expect(activeDashboard.reconciliationDifference, -19.13);

    final text = financeWhatsappSummaryText(
      bundle: baseDashboard,
      restaurantName: "Los Padrino's Tacos",
      branchName: 'Aviacion',
    );
    expect(text, contains('Cobrado real: \$25,390.23'));
    expect(text, contains('Gastos: -\$2,015.00'));
    expect(text, contains('Resultado operativo: -\$2,383.13'));
    expect(text, contains('Diferencia por conciliar: +\$46.87'));

    final workbook = Excel.decodeBytes(
      buildFinanceDashboardWorkbook(
        bundle: baseDashboard,
        restaurantName: "Los Padrino's Tacos",
        branchName: 'Aviacion',
        generatedAt: DateTime(2026, 8, 18, 10),
      ),
    );
    final summaryText = workbook.tables['Resumen']!.rows
        .expand((row) => row)
        .map((cell) => cell?.value?.toString() ?? '')
        .join(' ');
    expect(summaryText, contains('Diferencia por conciliar'));
    expect(summaryText, contains('46.87'));
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
        withdrawals: [
          _expense(
            'approved',
            100,
            cashSessionId: 'cut-1',
            source: 'cash_drawer',
          ),
          _expense(
            'approved',
            200,
            cashSessionId: 'cut-2',
            source: 'cash_drawer',
          ),
        ],
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
        withdrawals: [
          _expense(
            'approved',
            100,
            cashSessionId: 'float',
            source: 'cash_drawer',
          ),
        ],
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
        withdrawals: [
          _expense(
            'approved',
            100,
            cashSessionId: 'float',
            source: 'cash_drawer',
          ),
        ],
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

  test('aplica formulas de resultado operativo y saldo final', () {
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
        supplierPayments: [
          _supplierPayment(amount: 3000),
          _supplierPayment(amount: 500, method: 'partner_contribution'),
        ],
        suppliers: const [],
      ),
    );

    expect(dashboard.generalResult, 4000);
    expect(dashboard.operatingResult, 4000);
    expect(dashboard.partnerContributions, 500);
    expect(dashboard.finalBalance, 4500);
    expect(dashboard.finalResult, 4500);
    expect(dashboard.collectionsResult, 4500);
  });

  test('fixture real separa aporte de socios del ingreso y saldo final', () {
    const augustKey = FinanceDashboardKey(
      restaurantId: 'restaurant',
      branchId: 'branch',
      startBusinessDate: '2026-08-10',
      endBusinessDate: '2026-08-16',
    );

    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: augustKey,
        salesSummary: _emptySales,
        paymentsByOrder: const {},
        cashSessions: [
          _cashSession(
            id: 'cut-real-final',
            businessDate: '2026-08-15',
            countedCashAmount: 19541,
            terminalReportedAmount: 6021.70,
            expectedCashAmount: 19816.10,
            expectedCardChargedAmount: 6021.70,
            expectedCardFeeAbsorbedAmount: 238.47,
            approvedWithdrawalsTotal: 36,
            shortageAmount: 686.90,
            overAmount: 411.80,
          ),
        ],
        withdrawals: [
          _expense(
            'approved',
            2045,
            businessDate: '2026-08-15',
            cashSessionId: 'expenses',
          ),
          _expense(
            'approved',
            36,
            businessDate: '2026-08-15',
            cashSessionId: 'cut-real-final',
            source: 'cash_drawer',
          ),
        ],
        purchases: [
          _purchase(
            total: 25758.36,
            paid: 25758.36,
            balance: 0,
            businessDate: '2026-08-15',
          ),
        ],
        supplierPayments: [
          _supplierPayment(
            amount: 17952.36,
            method: 'cash',
            businessDate: '2026-08-15',
          ),
          _supplierPayment(
            amount: 5376,
            method: 'transfer',
            businessDate: '2026-08-15',
          ),
          _supplierPayment(
            amount: 2430,
            method: 'partner_contribution',
            businessDate: '2026-08-15',
          ),
        ],
        suppliers: const [],
      ),
    );

    expect(dashboard.cashCollected, 19577);
    expect(dashboard.cardGrossCollected, 6021.70);
    expect(dashboard.cardFees, 238.47);
    expect(dashboard.cardCollected, 5783.23);
    expect(dashboard.realCollected, 25360.23);
    expect(dashboard.paidExpenses, 2081);
    expect(dashboard.supplierInvoicesTotal, 25758.36);
    expect(dashboard.supplierPaidTotal, 25758.36);
    expect(dashboard.partnerContributions, 2430);
    expect(dashboard.operatingResult, -2479.13);
    expect(dashboard.finalBalance, -49.13);
    final requiredCollectedForZeroBalance =
        dashboard.supplierInvoicesTotal +
        dashboard.paidExpenses -
        dashboard.partnerContributions;
    expect(requiredCollectedForZeroBalance, 25409.36);
    expect(requiredCollectedForZeroBalance - 25324.23, closeTo(85.13, 0.001));
    expect(
      (requiredCollectedForZeroBalance - dashboard.realCollected).abs(),
      closeTo(49.13, 0.001),
    );
    expect(
      36 + (requiredCollectedForZeroBalance - dashboard.realCollected).abs(),
      closeTo(85.13, 0.001),
    );
    expect(dashboard.cashShortages, 686.90);
    expect(dashboard.cashOverages, 411.80);
    expect(dashboard.expectedMonetaryGrossIncome, 25873.80);
    expect(dashboard.expectedMonetaryIncome, 25635.33);
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
        withdrawals: [
          _expense(
            'approved',
            100,
            cashSessionId: 'float',
            source: 'cash_drawer',
          ),
        ],
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
        withdrawals: [
          _expense(
            'approved',
            100,
            cashSessionId: 'float',
            source: 'cash_drawer',
          ),
        ],
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
        withdrawals: [
          _expense(
            'approved',
            100,
            cashSessionId: 'float',
            source: 'cash_drawer',
          ),
        ],
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
    expect(dashboard.discounts, 0);
    expect(dashboard.employeeFreeMeals, 100);
    expect(dashboard.netSales, 4000);
    expect(dashboard.realCollected, 4000);
    expect(dashboard.expectedMonetaryIncome, 4000);
    expect(dashboard.employeeConsumption, 100);
    expect(dashboard.cashShortages, 0);
  });

  test('fixture 19/08 excluye consumo empleado de cobrado real', () {
    const augustKey = FinanceDashboardKey(
      restaurantId: 'restaurant',
      branchId: 'branch',
      startBusinessDate: '2026-08-19',
      endBusinessDate: '2026-08-19',
    );
    final order = _order('fixture-1908', businessDate: '2026-08-19');
    final cash = _payment('cash-1908', order.id, amount: 6634);
    final card = _payment('card-1908', order.id, amount: 1191, method: 'card');
    final employeeMeal = _payment(
      'meal-1908',
      order.id,
      amount: 259,
      method: 'employee_consumption',
    );
    final summary = buildCanonicalSalesSummary([
      SalesOrderBundleInput(
        order: order,
        items: [_item(7825), _item(259)],
        payments: [cash, card, employeeMeal],
      ),
    ]);

    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: augustKey,
        salesSummary: summary,
        paymentsByOrder: {
          order.id: [cash, card, employeeMeal],
        },
        cashSessions: [
          _cashSession(
            id: 'cut-1908',
            businessDate: '2026-08-19',
            countedCashAmount: 6634,
            terminalReportedAmount: 1191,
            expectedCashAmount: 6634,
            expectedCardChargedAmount: 1191,
            expectedEmployeeConsumptionAmount: 259,
          ),
        ],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    expect(dashboard.grossSales, 8084);
    expect(dashboard.discounts, 0);
    expect(dashboard.employeeFreeMeals, 259);
    expect(dashboard.netSales, 7825);
    expect(dashboard.realCollected, 7825);
    expect(dashboard.employeeConsumption, 259);
    expect(dashboard.salesByDay.single.employeeFreeMeals, 259);
    expect(dashboard.salesByDay.single.netSales, 7825);
  });

  test('fixture periodo separa descuento parcial y comida gratis', () {
    const augustKey = FinanceDashboardKey(
      restaurantId: 'restaurant',
      branchId: 'branch',
      startBusinessDate: '2026-08-17',
      endBusinessDate: '2026-08-19',
    );
    final day17 = _order('day-17', businessDate: '2026-08-17');
    final day18 = _order('day-18', businessDate: '2026-08-18');
    final day19 = _order('day-19', businessDate: '2026-08-19');
    final payment17 = _payment('cash-17', day17.id, amount: 3982);
    final payment18 = _payment(
      'cash-18',
      day18.id,
      amount: 7263,
      chargedAmount: 7130,
      discountAmount: 133,
    );
    final cash19 = _payment('cash-19', day19.id, amount: 6634);
    final card19 = _payment('card-19', day19.id, amount: 1191, method: 'card');
    final meal19 = _payment(
      'meal-19',
      day19.id,
      amount: 259,
      method: 'employee_consumption',
    );
    final summary = buildCanonicalSalesSummary([
      SalesOrderBundleInput(
        order: day17,
        items: [_item(3982)],
        payments: [payment17],
      ),
      SalesOrderBundleInput(
        order: day18,
        items: [_item(7263)],
        payments: [payment18],
      ),
      SalesOrderBundleInput(
        order: day19,
        items: [_item(7825), _item(259)],
        payments: [cash19, card19, meal19],
      ),
    ]);

    final dashboard = buildFinanceDashboard(
      FinanceDashboardInput(
        key: augustKey,
        salesSummary: summary,
        paymentsByOrder: {
          day17.id: [payment17],
          day18.id: [payment18],
          day19.id: [cash19, card19, meal19],
        },
        cashSessions: const [],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    expect(dashboard.grossSales, 19329);
    expect(dashboard.discounts, 133);
    expect(dashboard.employeeFreeMeals, 259);
    expect(dashboard.netSales, 18937);
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
  double? chargedAmount,
  double discountAmount = 0,
  String? appliedDiscountType,
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
    chargedAmount: chargedAmount ?? amount,
    appliedAmount: chargedAmount ?? amount,
    cashReceivedAmount: received,
    cashChangeAmount: change,
    discountAmount: discountAmount,
    appliedDiscountType: appliedDiscountType,
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
  String? reason,
  DateTime? requestedAt,
  DateTime? createdAt,
  DateTime? authorizedAt,
  DateTime? approvedAt,
  bool isHistorical = false,
}) {
  return CashWithdrawalRequest(
    id: '$status-$amount-${reason ?? status}',
    cashSessionId: cashSessionId,
    businessDate: businessDate,
    amount: amount,
    reason: reason ?? status,
    requestedByEmployeeId: 'employee',
    requestedByEmployeeName: 'Empleado',
    requestedAt: requestedAt,
    createdAt: createdAt,
    status: status,
    authorizedAt: authorizedAt,
    approvedAt: approvedAt,
    source: source,
    isHistorical: isHistorical,
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
  double expectedCardFeeAbsorbedAmount = 0,
  double expectedPlatformAmount = 0,
  double expectedEmployeeConsumptionAmount = 0,
  double approvedWithdrawalsTotal = 0,
  double? shortageAmount,
  double? overAmount,
  DateTime? openedAt,
  DateTime? closedAt,
  String? closedByEmployeeName,
}) {
  final netDifference =
      (countedCashAmount +
          terminalReportedAmount -
          expectedCardFeeAbsorbedAmount) -
      (expectedCashAmount +
          expectedCardChargedAmount -
          expectedCardFeeAbsorbedAmount);
  return CashSession(
    id: id,
    businessDate: businessDate,
    status: status,
    openingCashAmount: openingCashAmount,
    openedAt: openedAt,
    openedByEmployeeId: 'employee',
    openedByEmployeeName: 'Empleado',
    closedAt: closedAt,
    closedByEmployeeId: closedByEmployeeName == null ? null : 'closer',
    closedByEmployeeName: closedByEmployeeName,
    countedCashAmount: countedCashAmount,
    terminalReportedAmount: terminalReportedAmount,
    expectedCashAmount: expectedCashAmount,
    expectedCardChargedAmount: expectedCardChargedAmount,
    expectedCardBaseAmount: expectedCardChargedAmount,
    expectedCardSurchargeAmount: 0,
    expectedCardFeeAbsorbedAmount: expectedCardFeeAbsorbedAmount,
    expectedPlatformAmount: expectedPlatformAmount,
    expectedEmployeeConsumptionAmount: expectedEmployeeConsumptionAmount,
    totalExpectedRealMoney:
        expectedCashAmount +
        expectedCardChargedAmount -
        expectedCardFeeAbsorbedAmount,
    totalCountedRealMoney:
        countedCashAmount +
        terminalReportedAmount -
        expectedCardFeeAbsorbedAmount,
    cashDifference: countedCashAmount - expectedCashAmount,
    cardDifference: terminalReportedAmount - expectedCardChargedAmount,
    netDifference: netDifference,
    shortageAmount:
        shortageAmount ?? (netDifference < 0 ? netDifference.abs() : 0),
    overAmount: overAmount ?? (netDifference > 0 ? netDifference : 0),
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
  String supplierId = 'supplier',
  String supplierName = 'Proveedor',
  String businessDate = '2026-07-12',
}) {
  return SupplierPurchase(
    id: 'purchase-$supplierId-$total-$status',
    supplierId: supplierId,
    supplierName: supplierName,
    purchaseDate: DateTime(2026, 7, 12),
    businessDate: businessDate,
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
  String businessDate = '2026-07-12',
}) {
  return SupplierPayment(
    id: 'supplier-payment-$amount-$status',
    supplierId: 'supplier',
    supplierName: 'Proveedor',
    purchaseId: 'purchase',
    purchaseFolio: 'F-1',
    paymentDate: DateTime(2026, 7, 12),
    businessDate: businessDate,
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
