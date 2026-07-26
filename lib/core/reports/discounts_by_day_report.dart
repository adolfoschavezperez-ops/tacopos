import '../../models/order.dart';
import '../../models/payment.dart';
import 'canonical_sales_summary.dart';

enum DiscountReportCategory {
  employeeDiscount,
  employeeFreeMeal,
  partnerDiscount,
  friendsFamily,
  courtesy,
  promotion,
  other,
  historicalUnknown,
}

class DiscountReportRow {
  const DiscountReportRow({
    required this.businessDate,
    required this.order,
    required this.grossSales,
    required this.discountAmount,
    required this.netTotal,
    required this.category,
    required this.catalogId,
    required this.discountName,
    required this.discountType,
    required this.discountSource,
    required this.discountPercent,
    required this.beneficiary,
    required this.beneficiaryEmployeeId,
    required this.beneficiaryPartnerId,
    required this.appliedBy,
    required this.authorizedBy,
    required this.reason,
    required this.appliedAt,
  });

  final String businessDate;
  final PosOrder order;
  final double grossSales;
  final double discountAmount;
  final double netTotal;
  final DiscountReportCategory category;
  final String catalogId;
  final String discountName;
  final String discountType;
  final String discountSource;
  final double? discountPercent;
  final String beneficiary;
  final String beneficiaryEmployeeId;
  final String beneficiaryPartnerId;
  final String appliedBy;
  final String authorizedBy;
  final String reason;
  final DateTime? appliedAt;

  bool get isEmployeeFreeMeal =>
      category == DiscountReportCategory.employeeFreeMeal;
  bool get hasIdentifiedBeneficiary =>
      beneficiary.trim().isNotEmpty &&
      beneficiary != 'Beneficiario no identificado';
}

class DiscountDailySummary {
  DiscountDailySummary(this.businessDate);

  final String businessDate;
  final rows = <DiscountReportRow>[];
  double grossSales = 0;
  double employeeDiscount = 0;
  double employeeFreeMeals = 0;
  double partnerDiscount = 0;
  double friendsFamily = 0;
  double courtesy = 0;
  double promotion = 0;
  double other = 0;
  double historicalUnknown = 0;
  double netSales = 0;

  int get documents => rows.length;
  double get totalDiscount =>
      employeeDiscount +
      employeeFreeMeals +
      partnerDiscount +
      friendsFamily +
      courtesy +
      promotion +
      other +
      historicalUnknown;
  double get normalDiscounts => totalDiscount - employeeFreeMeals;

  void add(DiscountReportRow row) {
    rows.add(row);
    grossSales += row.grossSales;
    netSales += row.netTotal;
    switch (row.category) {
      case DiscountReportCategory.employeeDiscount:
        employeeDiscount += row.discountAmount;
        break;
      case DiscountReportCategory.employeeFreeMeal:
        employeeFreeMeals += row.discountAmount;
        break;
      case DiscountReportCategory.partnerDiscount:
        partnerDiscount += row.discountAmount;
        break;
      case DiscountReportCategory.friendsFamily:
        friendsFamily += row.discountAmount;
        break;
      case DiscountReportCategory.courtesy:
        courtesy += row.discountAmount;
        break;
      case DiscountReportCategory.promotion:
        promotion += row.discountAmount;
        break;
      case DiscountReportCategory.other:
        other += row.discountAmount;
        break;
      case DiscountReportCategory.historicalUnknown:
        historicalUnknown += row.discountAmount;
        break;
    }
  }
}

class DiscountsByDayReport {
  const DiscountsByDayReport({required this.rows, required this.daily});

  final List<DiscountReportRow> rows;
  final List<DiscountDailySummary> daily;

  int get documents => rows.length;
  double get grossSalesAffected =>
      rows.fold(0, (sum, row) => sum + row.grossSales);
  double get discountTotal =>
      rows.fold(0, (sum, row) => sum + row.discountAmount);
  double get employeeFreeMeals => rows
      .where((row) => row.isEmployeeFreeMeal)
      .fold(0, (sum, row) => sum + row.discountAmount);
  double get normalDiscounts => discountTotal - employeeFreeMeals;
  double get employeeDiscount => rows
      .where((row) => row.category == DiscountReportCategory.employeeDiscount)
      .fold(0, (sum, row) => sum + row.discountAmount);
  double get partnerDiscount => rows
      .where((row) => row.category == DiscountReportCategory.partnerDiscount)
      .fold(0, (sum, row) => sum + row.discountAmount);
  double get friendsFamily => rows
      .where((row) => row.category == DiscountReportCategory.friendsFamily)
      .fold(0, (sum, row) => sum + row.discountAmount);
  double get netSalesResult => rows.fold(0, (sum, row) => sum + row.netTotal);
}

DiscountsByDayReport buildDiscountsByDayReport({
  required Iterable<CanonicalOrderSalesRow> orderRows,
  required Map<String, List<Payment>> paymentsByOrder,
}) {
  final rows = <DiscountReportRow>[];
  for (final orderRow in orderRows) {
    if (orderRow.discountTotal <= salesReconciliationTolerance) continue;
    final order = orderRow.order;
    if (isCanonicalCancelledOrder(order)) continue;
    final payments = paymentsByOrder[order.id] ?? const <Payment>[];
    rows.add(_discountRow(orderRow, payments));
  }
  rows.sort((a, b) {
    final dateCompare = b.businessDate.compareTo(a.businessDate);
    if (dateCompare != 0) return dateCompare;
    final aTime = a.order.createdAt ?? DateTime(1970);
    final bTime = b.order.createdAt ?? DateTime(1970);
    return bTime.compareTo(aTime);
  });

  final dailyByDate = <String, DiscountDailySummary>{};
  for (final row in rows) {
    dailyByDate
        .putIfAbsent(row.businessDate, () {
          return DiscountDailySummary(row.businessDate);
        })
        .add(row);
  }
  final daily = dailyByDate.values.toList()
    ..sort((a, b) => b.businessDate.compareTo(a.businessDate));
  return DiscountsByDayReport(rows: rows, daily: daily);
}

DiscountsByDayReport discountsByDayReportFromRows(
  Iterable<DiscountReportRow> rows,
) {
  final sortedRows = rows.toList()
    ..sort((a, b) {
      final dateCompare = b.businessDate.compareTo(a.businessDate);
      if (dateCompare != 0) return dateCompare;
      final aTime = a.order.createdAt ?? DateTime(1970);
      final bTime = b.order.createdAt ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });
  final dailyByDate = <String, DiscountDailySummary>{};
  for (final row in sortedRows) {
    dailyByDate
        .putIfAbsent(row.businessDate, () {
          return DiscountDailySummary(row.businessDate);
        })
        .add(row);
  }
  final daily = dailyByDate.values.toList()
    ..sort((a, b) => b.businessDate.compareTo(a.businessDate));
  return DiscountsByDayReport(rows: sortedRows, daily: daily);
}

String discountCategoryLabel(DiscountReportCategory category) {
  return switch (category) {
    DiscountReportCategory.employeeDiscount => 'Descuento empleado',
    DiscountReportCategory.employeeFreeMeal => 'Comida gratis empleado',
    DiscountReportCategory.partnerDiscount => 'Descuento socio',
    DiscountReportCategory.friendsFamily => 'Amigos / familia',
    DiscountReportCategory.courtesy => 'Cortesia',
    DiscountReportCategory.promotion => 'Promocion',
    DiscountReportCategory.other => 'Otro',
    DiscountReportCategory.historicalUnknown =>
      'Historico sin tipo identificado',
  };
}

DiscountReportRow _discountRow(
  CanonicalOrderSalesRow orderRow,
  List<Payment> payments,
) {
  final order = orderRow.order;
  final primaryPayment = payments
      .where(_paymentHasDiscountMetadata)
      .firstOrNull;
  final rawType = _firstText([
    order.discountType,
    primaryPayment?.appliedDiscountType,
    primaryPayment?.method == 'employee_consumption'
        ? primaryPayment?.method
        : null,
    order.discountName,
    primaryPayment?.appliedDiscountName,
  ]);
  final rawName = _firstText([
    order.discountName,
    primaryPayment?.appliedDiscountName,
  ]);
  final rawSource = _firstText([
    order.discountSource,
    primaryPayment?.discountSource,
  ]);
  final category = classifyDiscountType(type: rawType, name: rawName);
  final beneficiary = _beneficiaryFor(category, order, primaryPayment);
  return DiscountReportRow(
    businessDate: orderRow.businessDate,
    order: order,
    grossSales: orderRow.grossSales,
    discountAmount: orderRow.discountTotal,
    netTotal: orderRow.netSales,
    category: category,
    catalogId: _firstText([
      order.discountCatalogId,
      primaryPayment?.discountAuthorizationRequestId,
      rawType,
    ]),
    discountName: rawName.isEmpty
        ? rawType.isEmpty && rawSource.isEmpty
              ? 'Descuento histórico sin concepto identificado'
              : discountCategoryLabel(category)
        : rawName,
    discountType: rawType.isEmpty ? discountCategoryLabel(category) : rawType,
    discountSource: rawSource.isEmpty ? 'Histórico' : rawSource,
    discountPercent: _discountPercent(order, primaryPayment),
    beneficiary: beneficiary,
    beneficiaryEmployeeId: _firstText([
      order.discountBeneficiaryEmployeeId,
      primaryPayment?.discountEmployeeBeneficiaryId,
    ]),
    beneficiaryPartnerId: _firstText([
      order.discountBeneficiaryPartnerId,
      primaryPayment?.discountAuthorizedByPartnerId,
    ]),
    appliedBy: _firstText([
      order.discountAppliedByEmployeeName,
      primaryPayment?.employeeName,
      primaryPayment?.createdBy,
    ]),
    authorizedBy: _firstText([
      order.discountAuthorizedByEmployeeName,
      order.discountBeneficiaryPartnerName,
      primaryPayment?.discountAuthorizedByPartnerLinkedEmployeeName,
      primaryPayment?.discountAuthorizedByPartnerName,
    ]),
    reason: _firstText([order.discountReason, primaryPayment?.discountReason]),
    appliedAt: order.discountAppliedAt ?? primaryPayment?.createdAt,
  );
}

DiscountReportCategory classifyDiscountType({String? type, String? name}) {
  final normalizedType = _normalize(type);
  final normalizedName = _normalize(name);
  bool matches(Iterable<String> values) {
    return values.any((value) {
      final clean = _normalize(value);
      return normalizedType == clean ||
          normalizedType.contains(clean) ||
          normalizedName.contains(clean);
    });
  }

  if (matches(const [
    'employee_free_meal',
    'free_employee_meal',
    'employee_consumption',
    'consumo_empleado',
    'comida_gratis_empleado',
    'comida empleado',
  ])) {
    return DiscountReportCategory.employeeFreeMeal;
  }
  if (matches(const [
    'employee',
    'employee_discount',
    'empleado',
    'employee_30',
  ])) {
    return DiscountReportCategory.employeeDiscount;
  }
  if (matches(const ['partner', 'partner_discount', 'socio'])) {
    return DiscountReportCategory.partnerDiscount;
  }
  if (matches(const [
    'family',
    'family_discount',
    'friends_family',
    'amigos_familia',
    'familia',
  ])) {
    return DiscountReportCategory.friendsFamily;
  }
  if (matches(const ['courtesy', 'cortesia', 'complimentary'])) {
    return DiscountReportCategory.courtesy;
  }
  if (matches(const ['promotion', 'promocion', 'promo', 'general'])) {
    return DiscountReportCategory.promotion;
  }
  if (normalizedType.isEmpty && normalizedName.isEmpty) {
    return DiscountReportCategory.historicalUnknown;
  }
  return DiscountReportCategory.other;
}

String _beneficiaryFor(
  DiscountReportCategory category,
  PosOrder order,
  Payment? payment,
) {
  final value = switch (category) {
    DiscountReportCategory.employeeDiscount ||
    DiscountReportCategory.employeeFreeMeal => _firstText([
      order.discountBeneficiaryEmployeeName,
      order.employeeConsumptionName,
      order.beneficiaryEmployeeName,
      payment?.discountEmployeeBeneficiaryName,
      payment?.employeeName,
    ]),
    DiscountReportCategory.partnerDiscount => _firstText([
      order.discountBeneficiaryPartnerName,
      order.partnerName,
      order.discountBeneficiaryName,
      payment?.discountAuthorizedByPartnerName,
    ]),
    DiscountReportCategory.friendsFamily => _firstText([
      order.discountBeneficiaryName,
      order.familyBeneficiaryName,
      order.customerName,
    ]),
    DiscountReportCategory.courtesy ||
    DiscountReportCategory.promotion ||
    DiscountReportCategory.other => _firstText([
      order.discountBeneficiaryName,
      order.customerName,
      payment?.personName,
    ]),
    DiscountReportCategory.historicalUnknown => '',
  };
  return value.isEmpty ? 'Beneficiario no identificado' : value;
}

double? _discountPercent(PosOrder order, Payment? payment) {
  final percent = order.discountPercent;
  if (percent != null && percent > 0) {
    return percent > 1 ? percent : percent * 100;
  }
  final rate = order.discountRate;
  if (rate != null && rate > 0) return rate > 1 ? rate : rate * 100;
  final paymentPercent = payment?.appliedDiscountPercent ?? 0;
  if (paymentPercent > 0) {
    return paymentPercent > 1 ? paymentPercent : paymentPercent * 100;
  }
  return null;
}

bool _paymentHasDiscountMetadata(Payment payment) {
  return _firstText([
        payment.appliedDiscountType,
        payment.appliedDiscountName,
        payment.discountEmployeeBeneficiaryName,
        payment.discountAuthorizedByPartnerName,
        payment.discountReason,
      ]).isNotEmpty ||
      payment.discountAmount > salesReconciliationTolerance;
}

String _firstText(Iterable<Object?> values) {
  for (final value in values) {
    final clean = value?.toString().trim();
    if (clean != null && clean.isNotEmpty && clean.toLowerCase() != 'none') {
      return clean;
    }
  }
  return '';
}

String _normalize(Object? value) {
  return value
      .toString()
      .toLowerCase()
      .trim()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll('Ã¡', 'a')
      .replaceAll('Ã©', 'e')
      .replaceAll('Ã­', 'i')
      .replaceAll('Ã³', 'o')
      .replaceAll('Ãº', 'u')
      .replaceAll('Ã±', 'n');
}
