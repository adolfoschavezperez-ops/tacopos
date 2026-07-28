import '../../models/kitchen_stock_item.dart';
import '../../models/product.dart';
import '../../models/product_category.dart';
import '../../models/yield_profit_models.dart';
import 'canonical_sales_summary.dart';
import 'report_data_bundle.dart';

const initialYieldSourceLabel =
    'Referencia inicial USDA / estimación conservadora';

class InitialYieldDefinition {
  const InitialYieldDefinition(this.name, this.aliases, this.percent);

  final String name;
  final List<String> aliases;
  final double percent;
}

const initialYieldDefinitions = <InitialYieldDefinition>[
  InitialYieldDefinition('Bistec', ['bistec'], 69),
  InitialYieldDefinition('Adobada', ['adobada', 'adobado'], 60),
  InitialYieldDefinition('Arrachera', ['arrachera'], 68),
  InitialYieldDefinition('Higado', ['higado'], 70),
  InitialYieldDefinition('Chorizo', ['chorizo'], 55),
  InitialYieldDefinition('Carnaza', ['carnaza'], 77),
  InitialYieldDefinition('Labio', ['labio'], 60),
  InitialYieldDefinition('Lengua', ['lengua'], 58),
  InitialYieldDefinition('Tripa', ['tripa'], 65),
];

String normalizeYieldName(String value) {
  return value
      .toLowerCase()
      .trim()
      .replaceAll(RegExp('[áàäâ]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöô]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'\s+'), ' ');
}

class InitialYieldSeedPlan {
  const InitialYieldSeedPlan({
    required this.toCreate,
    required this.linkedNames,
    required this.pendingNames,
  });

  final List<IngredientYieldProfile> toCreate;
  final List<String> linkedNames;
  final List<String> pendingNames;
}

InitialYieldSeedPlan planInitialYieldSeed({
  required String restaurantId,
  required Iterable<KitchenStockItem> stockItems,
  required Iterable<IngredientYieldProfile> existingProfiles,
}) {
  final stockByName = <String, KitchenStockItem>{};
  for (final item in stockItems) {
    stockByName.putIfAbsent(normalizeYieldName(item.name), () => item);
  }
  final existingIds = existingProfiles
      .map((profile) => profile.stockItemId)
      .toSet();
  final existingNames = existingProfiles
      .map((profile) => normalizeYieldName(profile.stockItemName))
      .toSet();
  final create = <IngredientYieldProfile>[];
  final linked = <String>[];
  final pending = <String>[];
  for (final definition in initialYieldDefinitions) {
    KitchenStockItem? match;
    for (final alias in definition.aliases) {
      match = stockByName[normalizeYieldName(alias)];
      if (match != null) break;
    }
    if (match == null) {
      pending.add(definition.name);
      continue;
    }
    linked.add(match.name);
    if (existingIds.contains(match.id) ||
        existingNames.contains(normalizeYieldName(match.name))) {
      continue;
    }
    create.add(
      IngredientYieldProfile(
        id: match.id,
        restaurantId: restaurantId,
        stockItemId: match.id,
        stockItemName: match.name,
        cookingYieldPercent: definition.percent,
        cookingYieldRate: definition.percent / 100,
        estimatedReductionPercent: 100 - definition.percent,
        isEstimated: true,
        needsInternalValidation: true,
        sourceLabel: initialYieldSourceLabel,
        active: true,
      ),
    );
  }
  return InitialYieldSeedPlan(
    toCreate: create,
    linkedNames: linked,
    pendingNames: pending,
  );
}

double theoreticalUnitsPerRawKg({
  required double cookingYieldRate,
  required double cookedPortionGrams,
}) {
  if (cookingYieldRate <= 0 || cookedPortionGrams <= 0) return 0;
  return 1000 * cookingYieldRate / cookedPortionGrams;
}

double rawEquivalent({
  required double quantity,
  required String inputStage,
  double? cookingYieldRate,
}) {
  if (quantity < 0) return 0;
  if (inputStage == 'cooked') {
    final rate = cookingYieldRate ?? 0;
    return rate > 0 ? quantity / rate : double.nan;
  }
  return quantity;
}

class RecipeSuggestion {
  const RecipeSuggestion({required this.recipe, required this.reason});

  final TheoreticalProductRecipe recipe;
  final String reason;
}

List<RecipeSuggestion> suggestInitialRecipes({
  required Iterable<Product> products,
  required Iterable<KitchenStockItem> stockItems,
  required Iterable<TheoreticalProductRecipe> existingRecipes,
}) {
  final existing = existingRecipes.map((recipe) => recipe.productId).toSet();
  final stock = stockItems.where((item) => item.active).toList();
  KitchenStockItem? exact(Iterable<String> aliases) {
    for (final alias in aliases) {
      final normalizedAlias = normalizeYieldName(alias);
      for (final item in stock) {
        if (normalizeYieldName(item.name) == normalizedAlias) return item;
      }
    }
    return null;
  }

  final tortillaMaiz = exact(['tortilla de maiz', 'tortilla maiz']);
  final tortillaHarina = exact(['tortilla de harina', 'tortilla harina']);
  final queso = exact(['queso', 'queso para gringa']);
  final result = <RecipeSuggestion>[];
  for (final product in products.where((item) => item.active)) {
    if (existing.contains(product.id)) continue;
    final name = normalizeYieldName(product.name);
    final isGringa = name.contains('gringa');
    final isTaco = name.contains('taco');
    if (!isGringa && !isTaco) continue;
    KitchenStockItem? meat;
    for (final definition in initialYieldDefinitions) {
      if (definition.aliases.any((alias) => name.contains(alias))) {
        meat = exact(definition.aliases);
        break;
      }
    }
    if (meat == null) continue;
    final ingredients = <TheoreticalRecipeIngredient>[
      TheoreticalRecipeIngredient(
        stockItemId: meat.id,
        stockItemName: meat.name,
        quantity: isGringa ? 60 : 30,
        quantityType: 'portion',
        inputStage: 'cooked',
        unit: 'g',
        baseQuantity: isGringa ? 60 : 30,
      ),
    ];
    if (isGringa && queso != null) {
      ingredients.add(
        TheoreticalRecipeIngredient(
          stockItemId: queso.id,
          stockItemName: queso.name,
          quantity: 45,
          quantityType: 'portion',
          inputStage: 'ready_to_serve',
          unit: 'g',
          baseQuantity: 45,
        ),
      );
    }
    final tortilla = isGringa ? tortillaHarina : tortillaMaiz;
    if (tortilla != null) {
      ingredients.add(
        TheoreticalRecipeIngredient(
          stockItemId: tortilla.id,
          stockItemName: tortilla.name,
          quantity: isGringa ? 1 : 2,
          quantityType: 'portion',
          inputStage: 'ready_to_serve',
          unit: 'piece',
          baseQuantity: isGringa ? 1 : 2,
        ),
      );
    }
    result.add(
      RecipeSuggestion(
        recipe: TheoreticalProductRecipe(
          productId: product.id,
          productName: product.name,
          ingredients: ingredients,
        ),
        reason: isGringa
            ? 'Gringa y carne identificadas por nombre'
            : 'Taco y carne identificados por nombre',
      ),
    );
  }
  return result;
}

class YieldPurchaseLine {
  const YieldPurchaseLine({
    required this.purchaseId,
    required this.purchaseDate,
    required this.supplierName,
    required this.stockItemId,
    required this.stockItemName,
    required this.quantity,
    required this.unit,
    required this.unitCost,
  });

  final String purchaseId;
  final DateTime purchaseDate;
  final String supplierName;
  final String stockItemId;
  final String stockItemName;
  final double quantity;
  final String unit;
  final double unitCost;

  double get baseQuantity => quantityToBase(quantity, unit);
  double get finalCost => quantity * unitCost;
}

double quantityToBase(double quantity, String unit) {
  final normalized = normalizeYieldName(unit);
  return switch (normalized) {
    'kg' || 'kilogramo' || 'kilogramos' => quantity * 1000,
    'g' || 'gr' || 'gramo' || 'gramos' => quantity,
    'l' || 'litro' || 'litros' => quantity * 1000,
    'ml' || 'mililitro' || 'mililitros' => quantity,
    _ => quantity,
  };
}

class IngredientCost {
  const IngredientCost({
    required this.stockItemId,
    required this.costPerBaseUnit,
    required this.source,
    required this.purchaseLines,
  });

  final String stockItemId;
  final double costPerBaseUnit;
  final String source;
  final List<YieldPurchaseLine> purchaseLines;
}

IngredientCost? resolveIngredientCost({
  required String stockItemId,
  required Iterable<YieldPurchaseLine> lines,
  required DateTime start,
  required DateTime endInclusive,
}) {
  final valid = lines
      .where(
        (line) =>
            line.stockItemId == stockItemId &&
            line.quantity > 0 &&
            line.unitCost > 0 &&
            line.baseQuantity > 0 &&
            !line.purchaseDate.isAfter(endInclusive),
      )
      .toList();
  final inPeriod = valid
      .where((line) => !line.purchaseDate.isBefore(start))
      .toList();
  if (inPeriod.isNotEmpty) {
    final totalBase = inPeriod.fold<double>(
      0,
      (sum, line) => sum + line.baseQuantity,
    );
    final totalCost = inPeriod.fold<double>(
      0,
      (sum, line) => sum + line.finalCost,
    );
    return IngredientCost(
      stockItemId: stockItemId,
      costPerBaseUnit: totalCost / totalBase,
      source: 'Promedio ponderado del periodo',
      purchaseLines: inPeriod,
    );
  }
  if (valid.isEmpty) return null;
  valid.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
  final latest = valid.first;
  return IngredientCost(
    stockItemId: stockItemId,
    costPerBaseUnit: latest.finalCost / latest.baseQuantity,
    source: 'Ultimo costo valido anterior',
    purchaseLines: [latest],
  );
}

class YieldProductRow {
  const YieldProductRow({
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.unitsSold,
    required this.grossSales,
    required this.discountAllocated,
    required this.netSales,
    required this.recipe,
    required this.unitCost,
    required this.totalCost,
    required this.grossProfit,
    required this.grossMarginPercent,
    required this.missingCostIngredients,
  });

  final String productId;
  final String productName;
  final String categoryName;
  final int unitsSold;
  final double grossSales;
  final double discountAllocated;
  final double netSales;
  final TheoreticalProductRecipe? recipe;
  final double? unitCost;
  final double? totalCost;
  final double? grossProfit;
  final double? grossMarginPercent;
  final List<String> missingCostIngredients;

  bool get hasRecipe => recipe != null;
  bool get hasCompleteCost => hasRecipe && missingCostIngredients.isEmpty;
}

class IngredientProductUsage {
  const IngredientProductUsage({
    required this.productId,
    required this.productName,
    required this.unitsSold,
    required this.portion,
    required this.inputStage,
    required this.theoreticalInput,
    required this.rawEquivalent,
  });

  final String productId;
  final String productName;
  final int unitsSold;
  final double portion;
  final String inputStage;
  final double theoreticalInput;
  final double rawEquivalent;
}

class YieldIngredientRow {
  const YieldIngredientRow({
    required this.stockItemId,
    required this.stockItemName,
    required this.purchaseUnit,
    required this.profile,
    required this.cookedQuantity,
    required this.rawEstimatedQuantity,
    required this.cost,
    required this.theoreticalConsumedCost,
    required this.purchasedInPeriod,
    required this.estimatedDifference,
    required this.usages,
  });

  final String stockItemId;
  final String stockItemName;
  final String purchaseUnit;
  final IngredientYieldProfile? profile;
  final double cookedQuantity;
  final double rawEstimatedQuantity;
  final IngredientCost? cost;
  final double? theoreticalConsumedCost;
  final double purchasedInPeriod;
  final double estimatedDifference;
  final List<IngredientProductUsage> usages;
}

class YieldProfitReport {
  const YieldProfitReport({
    required this.products,
    required this.ingredients,
    required this.netSales,
    required this.theoreticalIngredientCost,
    required this.theoreticalGrossProfit,
    required this.theoreticalGrossMarginPercent,
    required this.rawEstimatedKilograms,
    required this.productsWithoutRecipe,
    required this.ingredientsWithoutCost,
    required this.recipesPendingValidation,
  });

  final List<YieldProductRow> products;
  final List<YieldIngredientRow> ingredients;
  final double netSales;
  final double theoreticalIngredientCost;
  final double theoreticalGrossProfit;
  final double theoreticalGrossMarginPercent;
  final double rawEstimatedKilograms;
  final int productsWithoutRecipe;
  final int ingredientsWithoutCost;
  final int recipesPendingValidation;
}

class _IngredientAccumulator {
  _IngredientAccumulator(this.stockItemId, this.stockItemName);

  final String stockItemId;
  final String stockItemName;
  double cooked = 0;
  double raw = 0;
  final usages = <IngredientProductUsage>[];
}

YieldProfitReport buildYieldProfitReport({
  required CanonicalSalesSummary sales,
  required Iterable<TheoreticalProductRecipe> recipes,
  required Iterable<IngredientYieldProfile> profiles,
  required Iterable<KitchenStockItem> stockItems,
  required Iterable<YieldPurchaseLine> purchaseLines,
  required DateTime start,
  required DateTime endInclusive,
}) {
  final recipeByProduct = {
    for (final recipe in recipes.where((item) => item.active))
      recipe.productId: recipe,
  };
  final profileByStock = {
    for (final profile in profiles.where((item) => item.active))
      profile.stockItemId: profile,
  };
  final stockById = {for (final item in stockItems) item.id: item};
  final costs = <String, IngredientCost?>{};
  IngredientCost? costFor(String id) => costs.putIfAbsent(
    id,
    () => resolveIngredientCost(
      stockItemId: id,
      lines: purchaseLines,
      start: start,
      endInclusive: endInclusive,
    ),
  );
  final ingredientAccumulators = <String, _IngredientAccumulator>{};
  final productRows = <YieldProductRow>[];
  for (final sale in sales.productRows) {
    final recipe = recipeByProduct[sale.productId];
    double unitCost = 0;
    final missing = <String>[];
    if (recipe != null) {
      for (final ingredient in recipe.ingredients) {
        final profile = profileByStock[ingredient.stockItemId];
        final rawPerUnit = rawEquivalent(
          quantity: ingredient.baseQuantity,
          inputStage: ingredient.inputStage,
          cookingYieldRate: profile?.cookingYieldRate,
        );
        final cost = costFor(ingredient.stockItemId);
        if (rawPerUnit.isNaN || cost == null) {
          missing.add(ingredient.stockItemName);
        } else {
          unitCost += rawPerUnit * cost.costPerBaseUnit;
        }
        final inputTotal = ingredient.baseQuantity * sale.qty;
        final rawTotal = rawPerUnit.isNaN ? 0.0 : rawPerUnit * sale.qty;
        final accumulator = ingredientAccumulators.putIfAbsent(
          ingredient.stockItemId,
          () => _IngredientAccumulator(
            ingredient.stockItemId,
            ingredient.stockItemName,
          ),
        );
        if (ingredient.inputStage == 'cooked') {
          accumulator.cooked += inputTotal;
        }
        accumulator.raw += rawTotal;
        accumulator.usages.add(
          IngredientProductUsage(
            productId: sale.productId,
            productName: sale.productName,
            unitsSold: sale.qty,
            portion: ingredient.baseQuantity,
            inputStage: ingredient.inputStage,
            theoreticalInput: inputTotal,
            rawEquivalent: rawTotal,
          ),
        );
      }
    }
    final complete = recipe != null && missing.isEmpty;
    final totalCost = complete ? unitCost * sale.qty : null;
    final profit = totalCost == null ? null : sale.netSales - totalCost;
    productRows.add(
      YieldProductRow(
        productId: sale.productId,
        productName: sale.productName,
        categoryName: sale.categoryName,
        unitsSold: sale.qty,
        grossSales: sale.grossSales,
        discountAllocated: sale.discountAllocated,
        netSales: sale.netSales,
        recipe: recipe,
        unitCost: complete ? unitCost : null,
        totalCost: totalCost,
        grossProfit: profit,
        grossMarginPercent: profit == null || sale.netSales == 0
            ? null
            : profit / sale.netSales * 100,
        missingCostIngredients: missing,
      ),
    );
  }
  final ingredientRows =
      ingredientAccumulators.values.map((accumulator) {
        final item = stockById[accumulator.stockItemId];
        final cost = costFor(accumulator.stockItemId);
        final purchased = purchaseLines
            .where(
              (line) =>
                  line.stockItemId == accumulator.stockItemId &&
                  !line.purchaseDate.isBefore(start) &&
                  !line.purchaseDate.isAfter(endInclusive),
            )
            .fold<double>(0, (sum, line) => sum + line.baseQuantity);
        return YieldIngredientRow(
          stockItemId: accumulator.stockItemId,
          stockItemName: accumulator.stockItemName,
          purchaseUnit: item?.unit ?? 'unidad base',
          profile: profileByStock[accumulator.stockItemId],
          cookedQuantity: accumulator.cooked,
          rawEstimatedQuantity: accumulator.raw,
          cost: cost,
          theoreticalConsumedCost: cost == null
              ? null
              : accumulator.raw * cost.costPerBaseUnit,
          purchasedInPeriod: purchased,
          estimatedDifference: purchased - accumulator.raw,
          usages: accumulator.usages,
        );
      }).toList()..sort(
        (a, b) => b.rawEstimatedQuantity.compareTo(a.rawEstimatedQuantity),
      );
  final completeProducts = productRows.where((row) => row.hasCompleteCost);
  final includedSales = completeProducts.fold<double>(
    0,
    (sum, row) => sum + row.netSales,
  );
  final totalCost = completeProducts.fold<double>(
    0,
    (sum, row) => sum + (row.totalCost ?? 0),
  );
  final grossProfit = includedSales - totalCost;
  return YieldProfitReport(
    products: productRows,
    ingredients: ingredientRows,
    netSales: productRows.fold(0, (sum, row) => sum + row.netSales),
    theoreticalIngredientCost: totalCost,
    theoreticalGrossProfit: grossProfit,
    theoreticalGrossMarginPercent: includedSales == 0
        ? 0
        : grossProfit / includedSales * 100,
    rawEstimatedKilograms:
        ingredientRows.fold<double>(
          0,
          (sum, row) => sum + row.rawEstimatedQuantity,
        ) /
        1000,
    productsWithoutRecipe: productRows.where((row) => !row.hasRecipe).length,
    ingredientsWithoutCost: ingredientRows
        .where((row) => row.cost == null)
        .length,
    recipesPendingValidation: recipeByProduct.values
        .where((recipe) => recipe.needsInternalValidation)
        .length,
  );
}

class YieldProfitReportKey {
  const YieldProfitReportKey({
    required this.restaurantId,
    required this.branchId,
    required this.startBusinessDate,
    required this.endBusinessDate,
  });

  final String restaurantId;
  final String branchId;
  final String startBusinessDate;
  final String endBusinessDate;

  String get value =>
      '$restaurantId|$branchId|$startBusinessDate|$endBusinessDate';

  @override
  bool operator ==(Object other) =>
      other is YieldProfitReportKey && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

class YieldProfitReportBundle {
  const YieldProfitReportBundle({
    required this.key,
    required this.reportData,
    required this.products,
    required this.categories,
    required this.recipes,
    required this.profiles,
    required this.stockItems,
    required this.purchaseLines,
    required this.report,
    required this.firestoreQueries,
    required this.fromCache,
    required this.loadMilliseconds,
  });

  final YieldProfitReportKey key;
  final ReportDataBundle reportData;
  final List<Product> products;
  final List<ProductCategory> categories;
  final List<TheoreticalProductRecipe> recipes;
  final List<IngredientYieldProfile> profiles;
  final List<KitchenStockItem> stockItems;
  final List<YieldPurchaseLine> purchaseLines;
  final YieldProfitReport report;
  final int firestoreQueries;
  final bool fromCache;
  final int loadMilliseconds;

  YieldProfitReportBundle withMetadata({
    required bool fromCache,
    required int loadMilliseconds,
  }) {
    return YieldProfitReportBundle(
      key: key,
      reportData: reportData,
      products: products,
      categories: categories,
      recipes: recipes,
      profiles: profiles,
      stockItems: stockItems,
      purchaseLines: purchaseLines,
      report: report,
      firestoreQueries: firestoreQueries,
      fromCache: fromCache,
      loadMilliseconds: loadMilliseconds,
    );
  }
}

class YieldProfitBundleCache {
  YieldProfitBundleCache({this.ttl = const Duration(seconds: 60)});

  final Duration ttl;
  final Map<YieldProfitReportKey, (DateTime, YieldProfitReportBundle)> _cache =
      {};
  final Map<YieldProfitReportKey, Future<YieldProfitReportBundle>> _inFlight =
      {};

  Future<(YieldProfitReportBundle, bool, bool)> load({
    required YieldProfitReportKey key,
    required Future<YieldProfitReportBundle> Function() loader,
    bool forceRefresh = false,
  }) async {
    final cached = _cache[key];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.$1) < ttl) {
      return (cached.$2, true, false);
    }
    final pending = _inFlight[key];
    if (!forceRefresh && pending != null) {
      return (await pending, false, true);
    }
    final future = loader();
    _inFlight[key] = future;
    try {
      final bundle = await future;
      _cache[key] = (DateTime.now(), bundle);
      return (bundle, false, false);
    } finally {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }
  }

  void clear() => _cache.clear();
}
