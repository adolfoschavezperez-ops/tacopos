import 'package:cloud_firestore/cloud_firestore.dart';

import 'product_recipe_item.dart';

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.active,
    required this.sendToKitchen,
    required this.sortOrder,
    required this.platformPrices,
    required this.affectsKitchenStock,
    this.kitchenStockItemId,
    this.kitchenStockItemName,
    this.kitchenStockUnit,
    this.stockConsumptionQty,
    this.recipeItems = const [],
  });

  final String id;
  final String name;
  final String category;
  final double price;
  final bool active;
  final bool sendToKitchen;
  final int sortOrder;
  final Map<String, double> platformPrices;
  final bool affectsKitchenStock;
  final String? kitchenStockItemId;
  final String? kitchenStockItemName;
  final String? kitchenStockUnit;
  final double? stockConsumptionQty;
  final List<ProductRecipeItem> recipeItems;

  List<Map<String, dynamic>> get recipeItemsMap =>
      ProductRecipeItem.toMapList(recipeItems);

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final category = _readString(data['category'], 'General');
    final stockConsumptionQty = data['stockConsumptionQty'] is num
        ? (data['stockConsumptionQty'] as num).toDouble()
        : data['kitchenConsumptionFactor'] is num
        ? (data['kitchenConsumptionFactor'] as num).toDouble()
        : null;
    final kitchenStockItemId = data['kitchenStockItemId'] as String?;
    final kitchenStockItemName = data['kitchenStockItemName'] as String?;
    final kitchenStockUnit = data['kitchenStockUnit'] as String?;
    final recipeItems = ProductRecipeItem.readList(
      data['recipeItems'],
      legacyStockItemId: kitchenStockItemId,
      legacyStockItemName: kitchenStockItemName,
      legacyStockUnit: kitchenStockUnit,
      legacyConsumptionFactor: stockConsumptionQty,
    );
    final primaryRecipe = recipeItems.isNotEmpty ? recipeItems.first : null;
    final affectsKitchenStock =
        _readBool(
          data['affectsKitchenStock'],
          fallback: _defaultAffectsKitchenStock(
            category,
            data['name'] as String?,
          ),
        ) ||
        recipeItems.isNotEmpty;

    return Product(
      id: doc.id,
      name: _readString(data['name'], doc.id),
      category: category,
      price: _readDouble(data['price']),
      active: _readBool(data['active'], fallback: true),
      sendToKitchen: _readBool(
        data['sendToKitchen'],
        fallback: _defaultSendToKitchen(category),
      ),
      sortOrder: _readInt(data['sortOrder']),
      platformPrices: _readPlatformPrices(data['platformPrices']),
      affectsKitchenStock: affectsKitchenStock,
      kitchenStockItemId:
          kitchenStockItemId ?? primaryRecipe?.kitchenStockItemId,
      kitchenStockItemName:
          kitchenStockItemName ?? primaryRecipe?.kitchenStockItemName,
      kitchenStockUnit: kitchenStockUnit ?? primaryRecipe?.kitchenStockUnit,
      stockConsumptionQty:
          stockConsumptionQty ?? primaryRecipe?.consumptionFactor,
      recipeItems: recipeItems,
    );
  }

  double priceForPlatform(String? platformId) {
    if (platformId == null || platformId == 'en_persona') {
      return price;
    }
    return platformPrices[platformId] ?? price;
  }

  static String _readString(Object? value, String fallback) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return fallback;
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

  static Map<String, double> _readPlatformPrices(Object? value) {
    if (value is! Map) {
      return const {};
    }

    final prices = <String, double>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty) {
        continue;
      }
      prices[key] = _readDouble(entry.value);
    }
    return prices;
  }

  static int _readInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    return 0;
  }

  static bool _readBool(Object? value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      final normalized = value.toLowerCase().trim();
      if (['true', '1', 'yes', 'si'].contains(normalized)) {
        return true;
      }
      if (['false', '0', 'no'].contains(normalized)) {
        return false;
      }
    }

    return fallback;
  }

  static bool _defaultSendToKitchen(String category) {
    category = category.toLowerCase().trim();
    return category != 'bebidas';
  }

  static bool _defaultAffectsKitchenStock(String category, String? name) {
    final normalizedCategory = category.toLowerCase().trim();
    final normalizedName = (name ?? '').toLowerCase().trim();
    if (normalizedCategory == 'tacos' ||
        normalizedName.contains('taco') ||
        normalizedName.contains('gringa')) {
      return true;
    }
    if (normalizedCategory == 'bebidas' ||
        normalizedName.contains('refresco')) {
      return true;
    }
    return false;
  }
}
