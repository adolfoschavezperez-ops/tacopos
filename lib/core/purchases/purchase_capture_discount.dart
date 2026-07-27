import '../../models/purchase_models.dart';

const double _purchaseUnitCostFactor = 100000000;

bool isValidPurchaseDiscountPercent(double value) {
  return value.isFinite && value >= 0 && value <= 100;
}

double purchaseMoney(num value) {
  return (value * 100).roundToDouble() / 100;
}

double purchaseLinesTotal(Iterable<PurchaseLineInput> lines) {
  return purchaseMoney(lines.fold<double>(0, (sum, line) => sum + line.total));
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
  final unitCost = _roundUnitCost(line.unitCost * (1 - percent / 100));
  return _copyLine(line, unitCost: unitCost);
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
  var allocated = 0.0;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (line.quantity <= 0) {
      result.add(line);
      continue;
    }
    final discountedUnitCost = index == lastValidIndex
        ? purchaseMoney(
                targetTotal - allocated,
              ).clamp(0, double.infinity).toDouble() /
              line.quantity
        : line.unitCost * (1 - percent / 100);
    final discounted = _copyLine(
      line,
      unitCost: _roundUnitCost(discountedUnitCost),
    );
    result.add(discounted);
    allocated = purchaseMoney(allocated + discounted.total);
  }

  final residual = purchaseMoney(targetTotal - purchaseLinesTotal(result));
  if (residual.abs() >= 0.01) {
    final line = result[lastValidIndex];
    final adjustedLineTotal = purchaseMoney(line.total + residual);
    result[lastValidIndex] = _copyLine(
      line,
      unitCost: _roundUnitCost(adjustedLineTotal / line.quantity),
    );
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
  required double unitCost,
}) {
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
    notes: line.notes,
  );
}
