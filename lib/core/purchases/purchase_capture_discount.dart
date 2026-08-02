import '../../models/purchase_models.dart';

const double _purchaseUnitCostFactor = 100000000;

bool isValidPurchaseDiscountPercent(double value) {
  return value.isFinite && value >= 0 && value <= 100;
}

double purchaseMoney(num value) {
  return purchaseAmountFromCents(purchaseAmountCents(value));
}

double purchaseLinesTotal(Iterable<PurchaseLineInput> lines) {
  return purchaseAmountFromCents(
    lines.fold<int>(0, (sum, line) => sum + line.lineTotalCents),
  );
}

bool isValidPurchaseLineInput(PurchaseLineInput line) {
  return line.purchaseItemName.trim().isNotEmpty &&
      line.quantity.isFinite &&
      line.quantity > 0 &&
      line.lineTotalCents >= 0 &&
      line.unitCostCalculated.isFinite &&
      line.unitCostCalculated >= 0;
}

double purchaseDiscountAmount(double currentTotal, double percent) {
  _validatePercent(percent);
  return purchaseMoney(
    currentTotal - purchaseDiscountedTotal(currentTotal, percent),
  );
}

double purchaseDiscountedTotal(double currentTotal, double percent) {
  _validatePercent(percent);
  return purchaseMoney(currentTotal * (1 - percent / 100));
}

PurchaseLineInput applyPurchaseLineDiscount(
  PurchaseLineInput line,
  double percent,
) {
  _validatePercent(percent);
  final lineTotal = purchaseDiscountedTotal(line.lineTotal, percent);
  return _copyLine(line, lineTotalCents: purchaseAmountCents(lineTotal));
}

List<PurchaseLineInput> applyPurchaseGeneralDiscount(
  List<PurchaseLineInput> lines,
  double percent,
) {
  _validatePercent(percent);
  if (lines.isEmpty) return const [];

  final targetTotal = purchaseDiscountedTotal(
    purchaseLinesTotal(lines),
    percent,
  );
  final lastValidIndex = lines.lastIndexWhere(
    (line) => line.quantity > 0 && line.total > 0,
  );
  if (lastValidIndex < 0) return List.unmodifiable(lines);

  final result = <PurchaseLineInput>[];
  var allocatedCents = 0;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (line.quantity <= 0) {
      result.add(line);
      continue;
    }
    final lineTotalCents = index == lastValidIndex
        ? (purchaseAmountCents(targetTotal) - allocatedCents).clamp(0, 1 << 62)
        : purchaseAmountCents(line.lineTotal * (1 - percent / 100));
    final discounted = _copyLine(line, lineTotalCents: lineTotalCents.toInt());
    result.add(discounted);
    allocatedCents += discounted.lineTotalCents;
  }
  return List.unmodifiable(result);
}

void _validatePercent(double percent) {
  if (!isValidPurchaseDiscountPercent(percent)) {
    throw RangeError.range(percent, 0, 100, 'percent');
  }
}

double _roundUnitCost(double value) {
  return (value * _purchaseUnitCostFactor).roundToDouble() /
      _purchaseUnitCostFactor;
}

PurchaseLineInput _copyLine(
  PurchaseLineInput line, {
  required int lineTotalCents,
}) {
  final unitCost = _roundUnitCost(
    purchaseUnitCostFromLineTotal(
      quantity: line.quantity,
      lineTotalCents: lineTotalCents,
    ),
  );
  return PurchaseLineInput(
    supplierPurchaseItemId: line.supplierPurchaseItemId,
    purchaseItemId: line.purchaseItemId,
    purchaseItemName: line.purchaseItemName,
    kitchenStockItemId: line.kitchenStockItemId,
    kitchenStockItemName: line.kitchenStockItemName,
    affectsKitchenStock: line.affectsKitchenStock,
    quantity: line.quantity,
    unit: line.unit,
    unitCost: unitCost,
    lineTotalCents: lineTotalCents,
    calculationMode: 'line_total',
    notes: line.notes,
  );
}
