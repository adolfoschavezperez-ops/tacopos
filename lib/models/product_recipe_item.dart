class ProductRecipeItem {
  const ProductRecipeItem({
    required this.kitchenStockItemId,
    required this.kitchenStockItemName,
    required this.kitchenStockUnit,
    required this.consumptionFactor,
  });

  final String kitchenStockItemId;
  final String kitchenStockItemName;
  final String kitchenStockUnit;
  final double consumptionFactor;

  Map<String, dynamic> toMap() {
    return {
      'kitchenStockItemId': kitchenStockItemId,
      'kitchenStockItemName': kitchenStockItemName,
      'kitchenStockUnit': kitchenStockUnit,
      'consumptionFactor': consumptionFactor,
    };
  }

  factory ProductRecipeItem.fromMap(Map<dynamic, dynamic> data) {
    return ProductRecipeItem(
      kitchenStockItemId: _readString(data['kitchenStockItemId']),
      kitchenStockItemName: _readString(data['kitchenStockItemName']),
      kitchenStockUnit: _readString(data['kitchenStockUnit']),
      consumptionFactor: _readDouble(data['consumptionFactor']),
    );
  }

  bool get isValid =>
      kitchenStockItemId.trim().isNotEmpty && consumptionFactor > 0;

  static List<ProductRecipeItem> readList(
    Object? value, {
    String? legacyStockItemId,
    String? legacyStockItemName,
    String? legacyStockUnit,
    double? legacyConsumptionFactor,
  }) {
    final items = <ProductRecipeItem>[];
    if (value is Iterable) {
      for (final entry in value) {
        if (entry is Map) {
          final item = ProductRecipeItem.fromMap(entry);
          if (item.isValid) {
            items.add(item);
          }
        }
      }
    }

    if (items.isNotEmpty) {
      return items;
    }

    final legacyId = legacyStockItemId?.trim() ?? '';
    if (legacyId.isEmpty) {
      return const [];
    }

    return [
      ProductRecipeItem(
        kitchenStockItemId: legacyId,
        kitchenStockItemName: (legacyStockItemName?.trim().isNotEmpty == true)
            ? legacyStockItemName!.trim()
            : legacyId,
        kitchenStockUnit: (legacyStockUnit?.trim().isNotEmpty == true)
            ? legacyStockUnit!.trim()
            : 'kg',
        consumptionFactor:
            legacyConsumptionFactor != null && legacyConsumptionFactor > 0
            ? legacyConsumptionFactor
            : 1,
      ),
    ];
  }

  static List<Map<String, dynamic>> toMapList(
    Iterable<ProductRecipeItem> items,
  ) {
    return items
        .where((item) => item.isValid)
        .map((item) => item.toMap())
        .toList();
  }

  static String _readString(Object? value) {
    if (value is String) {
      return value.trim();
    }
    return '';
  }

  static double _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.')) ?? 0;
    }
    return 0;
  }
}
