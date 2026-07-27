import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/canonical_sales_summary.dart';
import 'package:tacopos/core/reports/finance_dashboard.dart';
import 'package:tacopos/core/reports/finance_dashboard_excel.dart';
import 'package:excel/excel.dart';
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

  test('cobrado usa aplicado, descarta cancelado y no suma cambio', () {
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
        cashSessions: const [],
        withdrawals: const [],
        purchases: const [],
        supplierPayments: const [],
        suppliers: const [],
      ),
    );

    expect(dashboard.cashCollected, 500);
    expect(dashboard.cardCollected, 300);
    expect(dashboard.realCollected, 800);
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
        cashSessions: const [],
        withdrawals: [_expense('approved', 1000)],
        purchases: [_purchase(total: 4000, paid: 3000, balance: 1000)],
        supplierPayments: [_supplierPayment(amount: 3000)],
        suppliers: const [],
      ),
    );

    expect(dashboard.generalResult, 5000);
    expect(dashboard.collectionsResult, 5000);
    expect(dashboard.finalResult, 4000);
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
          cashSessions: const [],
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
}) {
  return CashWithdrawalRequest(
    id: '$status-$amount',
    cashSessionId: 'cash',
    businessDate: '2026-07-12',
    amount: amount,
    reason: status,
    requestedByEmployeeId: 'employee',
    requestedByEmployeeName: 'Empleado',
    status: status,
    source: source,
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
    method: 'transfer',
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
