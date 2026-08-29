import '../cash/operational_business_date.dart';
import '../orders/employee_benefit_checkout.dart';
import '../orders/order_payment_reconciliation.dart';
import '../../models/order.dart';
import '../../models/order_item.dart';
import '../../models/payment.dart';

export '../cash/operational_business_date.dart'
    show resolveOperationalBusinessDate;

const double salesReconciliationTolerance = 0.02;

class CanonicalSalesSummary {
  const CanonicalSalesSummary({
    required this.grossSales,
    required this.discountTotal,
    required this.partialDiscountTotal,
    required this.employeeFreeMealTotal,
    required this.netSales,
    required this.cashCollected,
    required this.cardCollected,
    required this.platformCollected,
    required this.employeeConsumption,
    required this.otherCollected,
    required this.monetaryCollected,
    required this.totalCollected,
    required this.reconciliationDifference,
    required this.paidOrdersCount,
    required this.takeoutOrdersCount,
    required this.dineInOrdersCount,
    required this.standingOrdersCount,
    required this.productRows,
    required this.orderRows,
    required this.integrityIssues,
  });

  final double grossSales;
  final double discountTotal;
  final double partialDiscountTotal;
  final double employeeFreeMealTotal;
  final double netSales;
  final double cashCollected;
  final double cardCollected;
  final double platformCollected;
  final double employeeConsumption;
  final double otherCollected;
  final double monetaryCollected;
  final double totalCollected;
  final double reconciliationDifference;
  final int paidOrdersCount;
  final int takeoutOrdersCount;
  final int dineInOrdersCount;
  final int standingOrdersCount;
  final List<CanonicalProductSalesRow> productRows;
  final List<CanonicalOrderSalesRow> orderRows;
  final List<SalesIntegrityIssue> integrityIssues;

  bool get hasReconciliationDifference =>
      reconciliationDifference.abs() > salesReconciliationTolerance;
  double get averageTicket =>
      paidOrdersCount == 0 ? 0 : netSales / paidOrdersCount;
}

class CanonicalOrderSalesRow {
  const CanonicalOrderSalesRow({
    required this.order,
    required this.grossSales,
    required this.discountTotal,
    required this.partialDiscountTotal,
    required this.employeeFreeMealTotal,
    required this.netSales,
    required this.totalCollected,
    required this.reconciliationDifference,
    required this.businessDate,
  });

  final PosOrder order;
  final double grossSales;
  final double discountTotal;
  final double partialDiscountTotal;
  final double employeeFreeMealTotal;
  final double netSales;
  final double totalCollected;
  final double reconciliationDifference;
  final String businessDate;

  bool get hasExplicitDiscount => discountTotal > salesReconciliationTolerance;
  bool get hasReconciliationDifference =>
      reconciliationDifference.abs() > salesReconciliationTolerance;
}

class CanonicalProductSalesRow {
  const CanonicalProductSalesRow({
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.qty,
    required this.grossSales,
    required this.discountAllocated,
    required this.netSales,
  });

  final String productId;
  final String productName;
  final String categoryName;
  final int qty;
  final double grossSales;
  final double discountAllocated;
  final double netSales;

  double get averageNetPrice => qty == 0 ? 0 : netSales / qty;
}

class SalesIntegrityIssue {
  const SalesIntegrityIssue({
    required this.orderId,
    required this.message,
    required this.amount,
  });

  final String orderId;
  final String message;
  final double amount;
}

class SalesOrderBundleInput {
  const SalesOrderBundleInput({
    required this.order,
    required this.items,
    required this.payments,
  });

  final PosOrder order;
  final List<OrderItem> items;
  final List<Payment> payments;
}

class _ProductAccumulator {
  _ProductAccumulator({
    required this.productId,
    required this.productName,
    required this.categoryName,
  });

  final String productId;
  final String productName;
  final String categoryName;
  int qty = 0;
  double grossSales = 0;
  double discountAllocated = 0;

  void add({
    required int qty,
    required double gross,
    required double discount,
  }) {
    this.qty += qty;
    grossSales += gross;
    discountAllocated += discount;
  }

  CanonicalProductSalesRow toRow() {
    return CanonicalProductSalesRow(
      productId: productId,
      productName: productName,
      categoryName: categoryName,
      qty: qty,
      grossSales: _roundMoney(grossSales),
      discountAllocated: _roundMoney(discountAllocated),
      netSales: _roundMoney(grossSales - discountAllocated),
    );
  }
}

CanonicalSalesSummary buildCanonicalSalesSummary(
  Iterable<SalesOrderBundleInput> bundles,
) {
  var grossSales = 0.0;
  var discountTotal = 0.0;
  var partialDiscountTotal = 0.0;
  var employeeFreeMealTotal = 0.0;
  var cashCollected = 0.0;
  var cardCollected = 0.0;
  var platformCollected = 0.0;
  var employeeConsumption = 0.0;
  var otherCollected = 0.0;
  var reconciliationCollected = 0.0;
  var paidOrdersCount = 0;
  var takeoutOrdersCount = 0;
  var dineInOrdersCount = 0;
  var standingOrdersCount = 0;
  final products = <String, _ProductAccumulator>{};
  final orderRows = <CanonicalOrderSalesRow>[];
  final issues = <SalesIntegrityIssue>[];

  for (final bundle in bundles) {
    final order = bundle.order;
    if (isCanonicalCancelledOrder(order)) continue;
    final activeItems = bundle.items.where(isCanonicalActiveItem).toList();
    final gross = _roundMoney(
      activeItems.fold<double>(
        0,
        (sum, item) => sum + item.qty * item.unitPrice,
      ),
    );
    final activePayments = bundle.payments
        .where(isCanonicalActivePayment)
        .toList();
    final businessDate = resolveOperationalBusinessDate(
      order: order,
      payment: activePayments.isEmpty ? null : activePayments.first,
      historicalFallback: order.createdAt ?? order.paidAt ?? order.updatedAt,
    );
    final paymentDiscount = _explicitPaymentsDiscount(activePayments, gross);
    final orderDiscount = _explicitOrderDiscount(order, gross);
    final reconciliation = reconcileOrderPayments(
      orderGrossTotal: gross,
      activePayments: activePayments.map(PaymentSettlementInput.fromPayment),
    );
    final baseDiscount = _roundMoney(
      paymentDiscount ?? orderDiscount ?? reconciliation.discountAmount,
    ).clamp(0, gross).toDouble();
    final metadataFreeMealDiscount = _roundMoney(
      _employeeFreeMealMetadataDiscount(activePayments),
    ).clamp(0, gross).toDouble();
    final detectedFreeMealDiscount = _roundMoney(
      _employeeFreeMealDiscount(
        activePayments,
        metadataFreeMealDiscount: metadataFreeMealDiscount,
      ),
    ).clamp(0, gross).toDouble();
    final discount = _roundMoney(
      paymentDiscount == null
          ? baseDiscount < detectedFreeMealDiscount
                ? detectedFreeMealDiscount
                : baseDiscount
          : baseDiscount +
                (detectedFreeMealDiscount - metadataFreeMealDiscount)
                    .clamp(0, double.infinity)
                    .toDouble(),
    ).clamp(0, gross).toDouble();
    final freeMealDiscount = _roundMoney(
      detectedFreeMealDiscount.clamp(0, discount).toDouble(),
    );
    final partialDiscount = _roundMoney(
      (discount - freeMealDiscount).clamp(0, double.infinity).toDouble(),
    );
    final net = _roundMoney(gross - discount);
    final collected = _roundMoney(
      activePayments.fold<double>(
        0,
        (sum, payment) => sum + canonicalPaymentAppliedAmount(payment),
      ),
    );
    final collectedForReconciliation = _roundMoney(
      activePayments.fold<double>(
        0,
        (sum, payment) => sum + _paymentReconciliationAppliedAmount(payment),
      ),
    );
    final difference = _roundMoney(collectedForReconciliation - net);

    grossSales += gross;
    discountTotal += discount;
    partialDiscountTotal += partialDiscount;
    employeeFreeMealTotal += freeMealDiscount;
    reconciliationCollected += collectedForReconciliation;
    for (final payment in activePayments) {
      final amount = canonicalPaymentAppliedAmount(payment);
      switch (payment.method.trim().toLowerCase()) {
        case 'cash':
          cashCollected += amount;
          break;
        case 'card':
          cardCollected += amount;
          break;
        case 'platform_paid':
          platformCollected += amount;
          break;
        case 'employee_consumption':
          employeeConsumption += amount;
          break;
        default:
          otherCollected += amount;
      }
    }
    if (order.status.trim().toLowerCase() == 'paid' ||
        order.paymentStatus.trim().toLowerCase() == 'paid') {
      paidOrdersCount++;
    }
    switch (order.orderType) {
      case 'takeout':
        takeoutOrdersCount++;
      case 'standing':
        standingOrdersCount++;
      default:
        dineInOrdersCount++;
    }

    if (difference.abs() > salesReconciliationTolerance) {
      issues.add(
        SalesIntegrityIssue(
          orderId: order.id,
          amount: difference,
          message: discount <= salesReconciliationTolerance
              ? 'Total inconsistente; revisar auditoria'
              : 'Existe diferencia entre venta neta y pagos registrados',
        ),
      );
    }
    _allocateProductDiscounts(
      products: products,
      activeItems: activeItems,
      grossTotal: gross,
      discountTotal: discount,
    );
    orderRows.add(
      CanonicalOrderSalesRow(
        order: order,
        grossSales: gross,
        discountTotal: discount,
        partialDiscountTotal: partialDiscount,
        employeeFreeMealTotal: freeMealDiscount,
        netSales: net,
        totalCollected: collected,
        reconciliationDifference: difference,
        businessDate: businessDate,
      ),
    );
  }

  final monetaryCollected =
      cashCollected + cardCollected + platformCollected + otherCollected;
  final totalCollected = monetaryCollected + employeeConsumption;
  final netSales = _roundMoney(grossSales - discountTotal);
  final productRows = products.values.map((entry) => entry.toRow()).toList()
    ..sort((a, b) => b.netSales.compareTo(a.netSales));
  return CanonicalSalesSummary(
    grossSales: _roundMoney(grossSales),
    discountTotal: _roundMoney(discountTotal),
    partialDiscountTotal: _roundMoney(partialDiscountTotal),
    employeeFreeMealTotal: _roundMoney(employeeFreeMealTotal),
    netSales: netSales,
    cashCollected: _roundMoney(cashCollected),
    cardCollected: _roundMoney(cardCollected),
    platformCollected: _roundMoney(platformCollected),
    employeeConsumption: _roundMoney(employeeConsumption),
    otherCollected: _roundMoney(otherCollected),
    monetaryCollected: _roundMoney(monetaryCollected),
    totalCollected: _roundMoney(totalCollected),
    reconciliationDifference: _roundMoney(reconciliationCollected - netSales),
    paidOrdersCount: paidOrdersCount,
    takeoutOrdersCount: takeoutOrdersCount,
    dineInOrdersCount: dineInOrdersCount,
    standingOrdersCount: standingOrdersCount,
    productRows: productRows,
    orderRows: orderRows,
    integrityIssues: issues,
  );
}

bool isCanonicalCancelledOrder(PosOrder order) {
  final status = order.status.trim().toLowerCase();
  final kitchenStatus = order.kitchenStatus.trim().toLowerCase();
  return const {
        'cancelled',
        'canceled',
        'cancelado',
        'cancelada',
        'voided',
        'anulado',
        'anulada',
      }.contains(status) ||
      const {
        'cancelled',
        'canceled',
        'cancelado',
        'cancelada',
      }.contains(kitchenStatus) ||
      order.cancelledAt != null ||
      order.canceledAt != null;
}

bool isCanonicalActiveItem(OrderItem item) {
  return !item.isCancelled && item.qty > 0 && item.unitPrice >= 0;
}

bool isCanonicalActivePayment(Payment payment) {
  final status = payment.status.trim().toLowerCase();
  return !const {
        'cancelled',
        'canceled',
        'cancelado',
        'cancelada',
        'voided',
        'anulado',
        'anulada',
      }.contains(status) &&
      payment.cancelledAt == null &&
      (canonicalPaymentAppliedAmount(payment) > 0 ||
          payment.discountAmount > 0 ||
          payment.baseAmount > 0);
}

double canonicalPaymentAppliedAmount(Payment payment, {double? tipAmount}) {
  return paymentMonetaryAppliedToSale(payment, tipOverride: tipAmount);
}

double _paymentReconciliationAppliedAmount(Payment payment) {
  if (_isEmployeeFreeMealPaymentFallback(payment)) return 0;
  return canonicalPaymentAppliedAmount(payment);
}

double? _explicitOrderDiscount(PosOrder order, double gross) {
  final fields = order.explicitDiscountFields;
  for (final key in const [
    'totalDiscountAmount',
    'discountAmount',
    'discountTotal',
    'totalDiscount',
    'appliedDiscount',
  ]) {
    final value = fields[key];
    if (value != null && value > 0) return value;
  }
  if (order.explicitDiscount > 0) return order.explicitDiscount;
  return _discountFromPercent(fields, gross);
}

double? _explicitPaymentsDiscount(List<Payment> payments, double gross) {
  var total = 0.0;
  var hasMoney = false;
  for (final payment in payments) {
    if (payment.discountAmount > 0) {
      total += payment.discountAmount;
      hasMoney = true;
    }
  }
  if (hasMoney) return total;

  var highestPercent = 0.0;
  for (final payment in payments) {
    if (payment.appliedDiscountPercent > 0) {
      highestPercent =
          highestPercent > _normalizePercent(payment.appliedDiscountPercent)
          ? highestPercent
          : _normalizePercent(payment.appliedDiscountPercent);
    }
  }
  if (highestPercent > 0) return gross * highestPercent.clamp(0, 1);
  return null;
}

double _employeeFreeMealMetadataDiscount(List<Payment> payments) {
  var total = 0.0;
  for (final payment in payments) {
    if (!isEmployeeFreeMealPayment(payment)) continue;
    total += paymentDiscountAppliedToSale(
      payment,
    ).clamp(0, double.infinity).toDouble();
  }
  return _roundMoney(total);
}

double _employeeFreeMealDiscount(
  List<Payment> payments, {
  required double metadataFreeMealDiscount,
}) {
  var legacyPaymentTotal = 0.0;
  for (final payment in payments) {
    if (!_isEmployeeFreeMealPaymentFallback(payment)) continue;
    legacyPaymentTotal += payment.baseAmount
        .clamp(0, double.infinity)
        .toDouble();
  }
  return _roundMoney(
    metadataFreeMealDiscount > legacyPaymentTotal
        ? metadataFreeMealDiscount
        : legacyPaymentTotal,
  );
}

bool isEmployeeFreeMealPayment(Payment payment) {
  return payment.method.trim().toLowerCase() == 'employee_consumption' &&
      payment.appliedDiscountType?.trim().toLowerCase() ==
          employeeDailyMealDiscountType;
}

bool _isEmployeeFreeMealPaymentFallback(Payment payment) {
  if (isEmployeeFreeMealPayment(payment)) return true;
  if (payment.method.trim().toLowerCase() != 'employee_consumption') {
    return false;
  }
  if (payment.baseAmount <= 0) return false;
  final discountType = payment.appliedDiscountType?.trim().toLowerCase() ?? '';
  if (discountType.isNotEmpty) return false;
  if (payment.discountAmount > salesReconciliationTolerance) return false;
  if (payment.appliedDiscountPercent > salesReconciliationTolerance) {
    return false;
  }
  if (payment.discountPercent > salesReconciliationTolerance) return false;
  return true;
}

double? _discountFromPercent(Map<String, double> fields, double gross) {
  for (final key in const [
    'appliedDiscountPercent',
    'discountPercent',
    'discountPercentage',
    'discountRate',
    'percentageDiscount',
  ]) {
    final percent = fields[key];
    if (percent != null && percent > 0) {
      return gross * _normalizePercent(percent);
    }
  }
  return null;
}

double _normalizePercent(double value) {
  if (value > 1) return value / 100;
  return value;
}

void _allocateProductDiscounts({
  required Map<String, _ProductAccumulator> products,
  required List<OrderItem> activeItems,
  required double grossTotal,
  required double discountTotal,
}) {
  var allocated = 0.0;
  for (var index = 0; index < activeItems.length; index++) {
    final item = activeItems[index];
    final gross = _roundMoney(item.qty * item.unitPrice);
    final discount = index == activeItems.length - 1
        ? _roundMoney(discountTotal - allocated)
        : _roundMoney(
            grossTotal <= 0 ? 0 : discountTotal * (gross / grossTotal),
          );
    allocated += discount;
    final productName = item.productName.trim().isEmpty
        ? 'Producto'
        : item.productName.trim();
    final categoryName = item.category.trim().isEmpty
        ? 'General'
        : item.category.trim();
    final key = item.productId.trim().isNotEmpty
        ? item.productId.trim()
        : 'legacy:${productName.toLowerCase()}|${categoryName.toLowerCase()}';
    final accumulator = products.putIfAbsent(
      key,
      () => _ProductAccumulator(
        productId: item.productId,
        productName: productName,
        categoryName: categoryName,
      ),
    );
    accumulator.add(qty: item.qty, gross: gross, discount: discount);
  }
}

double _roundMoney(num value) {
  return (value * 100).roundToDouble() / 100;
}

String businessDateFor(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
