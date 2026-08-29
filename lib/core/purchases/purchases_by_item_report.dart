import '../../models/purchase_models.dart';

List<PurchaseItemReportRow> buildPurchasesByItemReport({
  required Iterable<SupplierPurchaseItem> items,
}) {
  final totals = <String, _PurchaseItemReportAccumulator>{};
  for (final item in items) {
    final itemId =
        item.kitchenStockItemId ??
        item.purchaseItemId ??
        item.purchaseItemName.trim().toLowerCase();
    final itemName = item.kitchenStockItemName ?? item.purchaseItemName;
    final key = itemId.trim().isEmpty
        ? item.purchaseItemName.trim().toLowerCase()
        : itemId.trim();
    final current = totals.putIfAbsent(
      key,
      () => _PurchaseItemReportAccumulator(
        itemId: key,
        itemName: itemName.trim().isEmpty ? 'Insumo' : itemName.trim(),
        unit: item.unit,
        affectsKitchenPerformance: item.affectsKitchenStock,
      ),
    );
    current.quantity += item.quantity;
    current.totalCents += item.lineTotalCents;
    current.noteCount++;
    current.affectsKitchenPerformance =
        current.affectsKitchenPerformance || item.affectsKitchenStock;
  }

  return totals.values
      .map(
        (item) => PurchaseItemReportRow(
          itemId: item.itemId,
          itemName: item.itemName,
          quantity: item.quantity,
          unit: item.unit,
          total: item.total,
          averageUnitCostCalculated: item.averageUnitCostCalculated,
          noteCount: item.noteCount,
          affectsKitchenPerformance: item.affectsKitchenPerformance,
        ),
      )
      .toList()
    ..sort((a, b) => b.total.compareTo(a.total));
}

class _PurchaseItemReportAccumulator {
  _PurchaseItemReportAccumulator({
    required this.itemId,
    required this.itemName,
    required this.unit,
    required this.affectsKitchenPerformance,
  });

  final String itemId;
  final String itemName;
  final String unit;
  bool affectsKitchenPerformance;
  double quantity = 0;
  int totalCents = 0;
  int noteCount = 0;

  double get total => purchaseAmountFromCents(totalCents);
  double get averageUnitCostCalculated => quantity <= 0 ? 0 : total / quantity;
}
