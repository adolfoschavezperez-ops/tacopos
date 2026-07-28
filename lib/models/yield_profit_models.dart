import 'package:cloud_firestore/cloud_firestore.dart';

class IngredientYieldProfile {
  const IngredientYieldProfile({
    required this.id,
    required this.restaurantId,
    required this.stockItemId,
    required this.stockItemName,
    required this.cookingYieldPercent,
    required this.cookingYieldRate,
    required this.estimatedReductionPercent,
    required this.isEstimated,
    required this.needsInternalValidation,
    required this.sourceLabel,
    required this.active,
    this.rawBaseUnit = 'g',
    this.cookedBaseUnit = 'g',
    this.notes = '',
    this.createdAt,
    this.createdByEmployeeId = '',
    this.createdByEmployeeName = '',
    this.updatedAt,
    this.updatedByEmployeeId = '',
    this.updatedByEmployeeName = '',
    this.validatedAt,
    this.validatedByEmployeeId,
    this.validatedByEmployeeName,
  });

  final String id;
  final String restaurantId;
  final String stockItemId;
  final String stockItemName;
  final String rawBaseUnit;
  final String cookedBaseUnit;
  final double cookingYieldPercent;
  final double cookingYieldRate;
  final double estimatedReductionPercent;
  final bool isEstimated;
  final bool needsInternalValidation;
  final String sourceLabel;
  final String notes;
  final bool active;
  final DateTime? createdAt;
  final String createdByEmployeeId;
  final String createdByEmployeeName;
  final DateTime? updatedAt;
  final String updatedByEmployeeId;
  final String updatedByEmployeeName;
  final DateTime? validatedAt;
  final String? validatedByEmployeeId;
  final String? validatedByEmployeeName;

  factory IngredientYieldProfile.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final percent = _double(data['cookingYieldPercent']);
    final rate = _double(data['cookingYieldRate']);
    final effectivePercent = percent > 0 ? percent : rate * 100;
    return IngredientYieldProfile(
      id: doc.id,
      restaurantId: _string(data['restaurantId']),
      stockItemId: _string(data['stockItemId'], doc.id),
      stockItemName: _string(data['stockItemName'], doc.id),
      rawBaseUnit: _string(data['rawBaseUnit'], 'g'),
      cookedBaseUnit: _string(data['cookedBaseUnit'], 'g'),
      cookingYieldPercent: effectivePercent,
      cookingYieldRate: effectivePercent / 100,
      estimatedReductionPercent: 100 - effectivePercent,
      isEstimated: data['isEstimated'] as bool? ?? true,
      needsInternalValidation: data['needsInternalValidation'] as bool? ?? true,
      sourceLabel: _string(data['sourceLabel']),
      notes: _string(data['notes']),
      active: data['active'] as bool? ?? true,
      createdAt: _date(data['createdAt']),
      createdByEmployeeId: _string(data['createdByEmployeeId']),
      createdByEmployeeName: _string(data['createdByEmployeeName']),
      updatedAt: _date(data['updatedAt']),
      updatedByEmployeeId: _string(data['updatedByEmployeeId']),
      updatedByEmployeeName: _string(data['updatedByEmployeeName']),
      validatedAt: _date(data['validatedAt']),
      validatedByEmployeeId: data['validatedByEmployeeId'] as String?,
      validatedByEmployeeName: data['validatedByEmployeeName'] as String?,
    );
  }

  IngredientYieldProfile copyWith({
    double? cookingYieldPercent,
    bool? isEstimated,
    bool? needsInternalValidation,
    String? notes,
    bool? active,
  }) {
    final percent = cookingYieldPercent ?? this.cookingYieldPercent;
    return IngredientYieldProfile(
      id: id,
      restaurantId: restaurantId,
      stockItemId: stockItemId,
      stockItemName: stockItemName,
      rawBaseUnit: rawBaseUnit,
      cookedBaseUnit: cookedBaseUnit,
      cookingYieldPercent: percent,
      cookingYieldRate: percent / 100,
      estimatedReductionPercent: 100 - percent,
      isEstimated: isEstimated ?? this.isEstimated,
      needsInternalValidation:
          needsInternalValidation ?? this.needsInternalValidation,
      sourceLabel: sourceLabel,
      notes: notes ?? this.notes,
      active: active ?? this.active,
      createdAt: createdAt,
      createdByEmployeeId: createdByEmployeeId,
      createdByEmployeeName: createdByEmployeeName,
      updatedAt: updatedAt,
      updatedByEmployeeId: updatedByEmployeeId,
      updatedByEmployeeName: updatedByEmployeeName,
      validatedAt: validatedAt,
      validatedByEmployeeId: validatedByEmployeeId,
      validatedByEmployeeName: validatedByEmployeeName,
    );
  }
}

class TheoreticalRecipeIngredient {
  const TheoreticalRecipeIngredient({
    required this.stockItemId,
    required this.stockItemName,
    required this.quantity,
    required this.quantityType,
    required this.inputStage,
    required this.unit,
    required this.baseQuantity,
    this.isEstimated = true,
    this.needsInternalValidation = true,
  });

  final String stockItemId;
  final String stockItemName;
  final double quantity;
  final String quantityType;
  final String inputStage;
  final String unit;
  final double baseQuantity;
  final bool isEstimated;
  final bool needsInternalValidation;

  factory TheoreticalRecipeIngredient.fromMap(Map<String, dynamic> data) {
    return TheoreticalRecipeIngredient(
      stockItemId: _string(data['stockItemId']),
      stockItemName: _string(data['stockItemName']),
      quantity: _double(data['quantity']),
      quantityType: _string(data['quantityType'], 'portion'),
      inputStage: _string(data['inputStage'], 'ready_to_serve'),
      unit: _string(data['unit'], 'g'),
      baseQuantity: _double(data['baseQuantity'] ?? data['quantity']),
      isEstimated: data['isEstimated'] as bool? ?? true,
      needsInternalValidation: data['needsInternalValidation'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'stockItemId': stockItemId,
    'stockItemName': stockItemName,
    'quantity': quantity,
    'quantityType': quantityType,
    'inputStage': inputStage,
    'unit': unit,
    'baseQuantity': baseQuantity,
    'isEstimated': isEstimated,
    'needsInternalValidation': needsInternalValidation,
  };
}

class TheoreticalProductRecipe {
  const TheoreticalProductRecipe({
    required this.productId,
    required this.productName,
    required this.ingredients,
    this.active = true,
    this.isEstimated = true,
    this.needsInternalValidation = true,
    this.notes = '',
    this.version = 1,
    this.effectiveFrom,
    this.effectiveTo,
    this.createdAt,
    this.createdByEmployeeId = '',
    this.createdByEmployeeName = '',
    this.updatedAt,
    this.updatedByEmployeeId = '',
    this.updatedByEmployeeName = '',
    this.validatedAt,
    this.validatedByEmployeeId,
    this.validatedByEmployeeName,
  });

  final String productId;
  final String productName;
  final List<TheoreticalRecipeIngredient> ingredients;
  final bool active;
  final bool isEstimated;
  final bool needsInternalValidation;
  final String notes;
  final int version;
  final DateTime? effectiveFrom;
  final DateTime? effectiveTo;
  final DateTime? createdAt;
  final String createdByEmployeeId;
  final String createdByEmployeeName;
  final DateTime? updatedAt;
  final String updatedByEmployeeId;
  final String updatedByEmployeeName;
  final DateTime? validatedAt;
  final String? validatedByEmployeeId;
  final String? validatedByEmployeeName;

  factory TheoreticalProductRecipe.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawIngredients = data['ingredients'];
    return TheoreticalProductRecipe(
      productId: _string(data['productId'], doc.id),
      productName: _string(data['productName'], doc.id),
      ingredients: rawIngredients is List
          ? rawIngredients
                .whereType<Map>()
                .map(
                  (item) => TheoreticalRecipeIngredient.fromMap(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      active: data['active'] as bool? ?? true,
      isEstimated: data['isEstimated'] as bool? ?? true,
      needsInternalValidation: data['needsInternalValidation'] as bool? ?? true,
      notes: _string(data['notes']),
      version: (data['version'] as num?)?.toInt() ?? 1,
      effectiveFrom: _date(data['effectiveFrom']),
      effectiveTo: _date(data['effectiveTo']),
      createdAt: _date(data['createdAt']),
      createdByEmployeeId: _string(data['createdByEmployeeId']),
      createdByEmployeeName: _string(data['createdByEmployeeName']),
      updatedAt: _date(data['updatedAt']),
      updatedByEmployeeId: _string(data['updatedByEmployeeId']),
      updatedByEmployeeName: _string(data['updatedByEmployeeName']),
      validatedAt: _date(data['validatedAt']),
      validatedByEmployeeId: data['validatedByEmployeeId'] as String?,
      validatedByEmployeeName: data['validatedByEmployeeName'] as String?,
    );
  }

  TheoreticalProductRecipe copyWith({
    List<TheoreticalRecipeIngredient>? ingredients,
    bool? active,
    bool? isEstimated,
    bool? needsInternalValidation,
    String? notes,
  }) {
    return TheoreticalProductRecipe(
      productId: productId,
      productName: productName,
      ingredients: ingredients ?? this.ingredients,
      active: active ?? this.active,
      isEstimated: isEstimated ?? this.isEstimated,
      needsInternalValidation:
          needsInternalValidation ?? this.needsInternalValidation,
      notes: notes ?? this.notes,
      version: version,
      effectiveFrom: effectiveFrom,
      effectiveTo: effectiveTo,
      createdAt: createdAt,
      createdByEmployeeId: createdByEmployeeId,
      createdByEmployeeName: createdByEmployeeName,
      updatedAt: updatedAt,
      updatedByEmployeeId: updatedByEmployeeId,
      updatedByEmployeeName: updatedByEmployeeName,
      validatedAt: validatedAt,
      validatedByEmployeeId: validatedByEmployeeId,
      validatedByEmployeeName: validatedByEmployeeName,
    );
  }
}

String _string(Object? value, [String fallback = '']) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.tryParse(value?.toString() ?? '');
}
