import '../../models/purchase_models.dart';
import 'purchases_by_supplier_report.dart';

class SupplierPurchaseHistory {
  const SupplierPurchaseHistory({
    required this.supplierId,
    required this.range,
    required this.purchases,
    required this.totalPurchased,
  });

  final String supplierId;
  final PurchasesBySupplierDateRange range;
  final List<SupplierPurchase> purchases;
  final double totalPurchased;

  int get purchaseCount => purchases.length;
}

PurchasesBySupplierDateRange defaultSupplierPurchaseHistoryDateRange(
  DateTime now,
) {
  return defaultPurchasesBySupplierDateRange(now);
}

SupplierPurchaseHistory buildSupplierPurchaseHistory({
  required String supplierId,
  required Iterable<SupplierPurchase> purchases,
  required PurchasesBySupplierDateRange range,
}) {
  final cleanSupplierId = supplierId.trim();
  final seenPurchaseIds = <String>{};
  final filtered = <SupplierPurchase>[];
  for (final purchase in purchases) {
    final purchaseKey = purchase.id.trim();
    if (purchaseKey.isNotEmpty && !seenPurchaseIds.add(purchaseKey)) {
      continue;
    }
    if (purchase.supplierId != cleanSupplierId) {
      continue;
    }
    if (!isSupplierPurchaseIncludedInSupplierReport(purchase)) {
      continue;
    }
    if (!supplierPurchaseMatchesDateRange(purchase, range)) {
      continue;
    }
    filtered.add(purchase);
  }
  filtered.sort(compareSupplierPurchasesChronologically);
  final totalPurchased = purchaseAmountFromCents(
    purchaseAmountCents(
      filtered.fold<double>(
        0,
        (runningTotal, purchase) => runningTotal + _safeMoney(purchase.total),
      ),
    ),
  );
  return SupplierPurchaseHistory(
    supplierId: cleanSupplierId,
    range: range,
    purchases: List.unmodifiable(filtered),
    totalPurchased: totalPurchased,
  );
}

int compareSupplierPurchasesChronologically(
  SupplierPurchase a,
  SupplierPurchase b,
) {
  final byPurchaseDate = a.purchaseDate.compareTo(b.purchaseDate);
  if (byPurchaseDate != 0) return byPurchaseDate;
  final byCreatedAt = _compareNullableDate(a.createdAt, b.createdAt);
  if (byCreatedAt != 0) return byCreatedAt;
  final byFolio = a.folio.toLowerCase().compareTo(b.folio.toLowerCase());
  if (byFolio != 0) return byFolio;
  return a.id.compareTo(b.id);
}

bool canEditSupplierPurchaseDatesFromBackoffice(SupplierPurchase purchase) {
  return !purchase.isCancelled;
}

bool keepsSupplierPurchaseFinancialStateAfterDateEdit({
  required SupplierPurchase before,
  required SupplierPurchase after,
}) {
  return before.id == after.id &&
      before.supplierId == after.supplierId &&
      before.supplierName == after.supplierName &&
      before.folio == after.folio &&
      before.documentType == after.documentType &&
      before.status == after.status &&
      before.subtotal == after.subtotal &&
      before.total == after.total &&
      before.paidTotal == after.paidTotal &&
      before.balance == after.balance &&
      before.cancelledAt == after.cancelledAt;
}

int _compareNullableDate(DateTime? a, DateTime? b) {
  if (a != null && b != null) return a.compareTo(b);
  if (a != null) return -1;
  if (b != null) return 1;
  return 0;
}

double _safeMoney(num value) {
  final amount = value.toDouble();
  return amount.isFinite ? amount : 0;
}
