import '../../models/purchase_models.dart';

class PurchasesBySupplierDateRange {
  const PurchasesBySupplierDateRange({
    required this.startDate,
    required this.endDate,
  });

  final DateTime startDate;
  final DateTime endDate;

  DateTime get startInclusive =>
      DateTime(startDate.year, startDate.month, startDate.day);

  DateTime get endExclusive => DateTime(
    endDate.year,
    endDate.month,
    endDate.day,
  ).add(const Duration(days: 1));

  bool get isValid => !startInclusive.isAfter(_startOfDay(endDate));
}

class PurchasesBySupplierReport {
  const PurchasesBySupplierReport({
    required this.range,
    required this.rows,
    required this.totalPurchased,
  });

  final PurchasesBySupplierDateRange range;
  final List<PurchaseSupplierReportRow> rows;
  final double totalPurchased;

  int get purchaseCount =>
      rows.fold(0, (runningTotal, row) => runningTotal + row.noteCount);
}

PurchasesBySupplierDateRange defaultPurchasesBySupplierDateRange(DateTime now) {
  final today = _startOfDay(now);
  return PurchasesBySupplierDateRange(
    startDate: DateTime(today.year, today.month),
    endDate: today,
  );
}

String? validatePurchasesBySupplierDateRange(
  PurchasesBySupplierDateRange range,
) {
  if (!range.isValid) {
    return 'La fecha inicial no puede ser posterior a la fecha final.';
  }
  return null;
}

bool isSupplierPurchaseIncludedInSupplierReport(SupplierPurchase purchase) {
  return !purchase.isCancelled;
}

bool supplierPurchaseMatchesDateRange(
  SupplierPurchase purchase,
  PurchasesBySupplierDateRange range,
) {
  final purchaseDate = purchase.purchaseDate;
  return !purchaseDate.isBefore(range.startInclusive) &&
      purchaseDate.isBefore(range.endExclusive);
}

PurchasesBySupplierReport buildPurchasesBySupplierDateReport({
  required Iterable<Supplier> suppliers,
  required Iterable<SupplierPurchase> purchases,
  required PurchasesBySupplierDateRange range,
}) {
  final supplierById = {
    for (final supplier in suppliers) supplier.id: supplier,
  };
  final grouped = <String, List<SupplierPurchase>>{};
  final seenPurchaseIds = <String>{};
  for (final purchase in purchases) {
    final purchaseKey = purchase.id.trim();
    if (purchaseKey.isNotEmpty && !seenPurchaseIds.add(purchaseKey)) {
      continue;
    }
    if (!isSupplierPurchaseIncludedInSupplierReport(purchase)) {
      continue;
    }
    if (!supplierPurchaseMatchesDateRange(purchase, range)) {
      continue;
    }
    grouped.putIfAbsent(purchase.supplierId, () => []).add(purchase);
  }

  final rows = grouped.entries.map((entry) {
    final supplier = supplierById[entry.key];
    final purchaseList = entry.value.toList()
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    final totalPurchased = _roundMoney(
      purchaseList.fold<double>(
        0,
        (runningTotal, purchase) => runningTotal + _safeMoney(purchase.total),
      ),
    );
    return PurchaseSupplierReportRow(
      supplierId: entry.key,
      supplierName:
          supplier?.commercialName ??
          (purchaseList.isEmpty ? null : purchaseList.first.supplierName) ??
          'Proveedor',
      totalPurchased: totalPurchased,
      totalPaid: 0,
      balance: totalPurchased,
      noteCount: purchaseList.length,
      paymentWeekdayName: supplier?.paymentWeekdayName ?? 'Sin dia fijo',
      purchases: purchaseList,
    );
  }).toList();

  rows.sort((a, b) {
    final byTotal = b.totalPurchased.compareTo(a.totalPurchased);
    if (byTotal != 0) return byTotal;
    return a.supplierName.toLowerCase().compareTo(b.supplierName.toLowerCase());
  });

  final totalPurchased = _roundMoney(
    rows.fold<double>(
      0,
      (runningTotal, row) => runningTotal + _safeMoney(row.totalPurchased),
    ),
  );

  return PurchasesBySupplierReport(
    range: range,
    rows: rows,
    totalPurchased: totalPurchased,
  );
}

DateTime _startOfDay(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

double _safeMoney(num value) {
  final amount = value.toDouble();
  if (!amount.isFinite) return 0;
  return amount;
}

double _roundMoney(num value) {
  return purchaseAmountFromCents(purchaseAmountCents(_safeMoney(value)));
}
