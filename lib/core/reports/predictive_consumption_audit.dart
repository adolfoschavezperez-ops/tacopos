import 'dart:math' as math;

import 'yield_profit_report.dart';

class PredictivePurchaseLine {
  const PredictivePurchaseLine({
    required this.purchaseId,
    required this.purchaseDate,
    required this.businessDate,
    required this.supplierName,
    required this.itemName,
    required this.quantity,
    required this.unit,
    this.stockItemId = '',
    this.stockItemName = '',
  });

  final String purchaseId;
  final DateTime purchaseDate;
  final String businessDate;
  final String supplierName;
  final String itemName;
  final double quantity;
  final String unit;
  final String stockItemId;
  final String stockItemName;

  double get baseQuantity => quantityToBase(quantity, unit);
  String get unitFamily => predictiveUnitFamily(unit);
}

class PredictiveSaleLine {
  const PredictiveSaleLine({
    required this.businessDate,
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.quantity,
    required this.kind,
    required this.ingredientNames,
    this.orderId = '',
    this.cancelledByEmployeeName = '',
  });

  final String businessDate;
  final String productId;
  final String productName;
  final String categoryName;
  final int quantity;
  final PredictiveSaleKind kind;
  final List<String> ingredientNames;
  final String orderId;
  final String cancelledByEmployeeName;

  bool get isPaidSale => kind == PredictiveSaleKind.paidSale;
  bool get isCancelledKitchen =>
      kind == PredictiveSaleKind.cancelledKitchen;
}

enum PredictiveSaleKind { paidSale, cancelledKitchen }

class PredictiveCashDay {
  const PredictiveCashDay({
    required this.businessDate,
    required this.shortageAmount,
    required this.netDifference,
  });

  final String businessDate;
  final double shortageAmount;
  final double netDifference;
}

class PredictiveYieldInput {
  const PredictiveYieldInput({
    required this.stockItemId,
    required this.stockItemName,
    required this.yieldRate,
  });

  final String stockItemId;
  final String stockItemName;
  final double yieldRate;
}

class PredictiveIngredientDefinition {
  const PredictiveIngredientDefinition({
    required this.key,
    required this.name,
    required this.kind,
    required this.aliases,
  });

  final String key;
  final String name;
  final PredictiveIngredientKind kind;
  final List<String> aliases;
}

enum PredictiveIngredientKind { meat, tortillaCorn, tortillaFlour, tortillaAny }

const predictiveIngredientDefinitions = <PredictiveIngredientDefinition>[
  PredictiveIngredientDefinition(
    key: 'bistec',
    name: 'Bistec',
    kind: PredictiveIngredientKind.meat,
    aliases: ['bistec', 'bistek', 'bisteck'],
  ),
  PredictiveIngredientDefinition(
    key: 'adobada',
    name: 'Adobada',
    kind: PredictiveIngredientKind.meat,
    aliases: ['adobada', 'adobado'],
  ),
  PredictiveIngredientDefinition(
    key: 'arrachera',
    name: 'Arrachera',
    kind: PredictiveIngredientKind.meat,
    aliases: ['arrachera'],
  ),
  PredictiveIngredientDefinition(
    key: 'higado',
    name: 'Higado',
    kind: PredictiveIngredientKind.meat,
    aliases: ['higado'],
  ),
  PredictiveIngredientDefinition(
    key: 'chorizo',
    name: 'Chorizo',
    kind: PredictiveIngredientKind.meat,
    aliases: ['chorizo'],
  ),
  PredictiveIngredientDefinition(
    key: 'carnaza',
    name: 'Carnaza',
    kind: PredictiveIngredientKind.meat,
    aliases: ['carnaza'],
  ),
  PredictiveIngredientDefinition(
    key: 'labio',
    name: 'Labio',
    kind: PredictiveIngredientKind.meat,
    aliases: ['labio'],
  ),
  PredictiveIngredientDefinition(
    key: 'lengua',
    name: 'Lengua',
    kind: PredictiveIngredientKind.meat,
    aliases: ['lengua'],
  ),
  PredictiveIngredientDefinition(
    key: 'tripa',
    name: 'Tripa',
    kind: PredictiveIngredientKind.meat,
    aliases: ['tripa', 'tripa dorada'],
  ),
  PredictiveIngredientDefinition(
    key: 'tortilla_maiz',
    name: 'Tortilla de maiz',
    kind: PredictiveIngredientKind.tortillaCorn,
    aliases: ['tortilla maiz', 'tortilla de maiz'],
  ),
  PredictiveIngredientDefinition(
    key: 'tortilla_harina',
    name: 'Tortilla de harina',
    kind: PredictiveIngredientKind.tortillaFlour,
    aliases: ['tortilla harina', 'tortilla de harina'],
  ),
  PredictiveIngredientDefinition(
    key: 'tortilla',
    name: 'Tortilla',
    kind: PredictiveIngredientKind.tortillaAny,
    aliases: ['tortilla'],
  ),
];

class PredictiveProductCoefficient {
  const PredictiveProductCoefficient({
    required this.productKey,
    required this.productName,
    required this.rawBasePerUnit,
    required this.cookedBasePerUnit,
    required this.unitsInTraining,
    required this.shareOfTrainingUnits,
    required this.plausibility,
  });

  final String productKey;
  final String productName;
  final double rawBasePerUnit;
  final double? cookedBasePerUnit;
  final double unitsInTraining;
  final double shareOfTrainingUnits;
  final String plausibility;
}

class PredictiveConsumptionCycle {
  const PredictiveConsumptionCycle({
    required this.purchaseDate,
    required this.startBusinessDate,
    required this.endBusinessDate,
    required this.days,
    required this.operatingDays,
    required this.purchasedBase,
    required this.knownOperationalBase,
    required this.predictedPaidBase,
    required this.cancelledKitchenExplainedBase,
    required this.predictedOperationalBase,
    required this.residualPaidBase,
    required this.residualOperationalBase,
    required this.residualPercent,
    required this.expectedLowBase,
    required this.expectedHighBase,
    required this.robustZ,
    required this.anomalyScore,
    required this.shortageAmount,
    required this.paidUnits,
    required this.cancelledKitchenUnits,
    required this.evidence,
    required this.isInvestigationPeriod,
    required this.purchaseMagnitudeOutlier,
  });

  final String purchaseDate;
  final String startBusinessDate;
  final String endBusinessDate;
  final int days;
  final int operatingDays;
  final double purchasedBase;
  final double knownOperationalBase;
  final double predictedPaidBase;
  final double cancelledKitchenExplainedBase;
  final double predictedOperationalBase;
  final double residualPaidBase;
  final double residualOperationalBase;
  final double residualPercent;
  final double expectedLowBase;
  final double expectedHighBase;
  final double robustZ;
  final double anomalyScore;
  final double shortageAmount;
  final double paidUnits;
  final double cancelledKitchenUnits;
  final String evidence;
  final bool isInvestigationPeriod;
  final bool purchaseMagnitudeOutlier;

  bool get isHighAnomaly => anomalyScore >= 70;
  bool get isAuditEligible => anomalyScore >= 35 && !purchaseMagnitudeOutlier;
  bool get isMediumAnomaly => anomalyScore >= 45 && anomalyScore < 70;
}

class PredictiveIngredientModel {
  const PredictiveIngredientModel({
    required this.definition,
    required this.unitFamily,
    required this.baseUnitLabel,
    required this.supplierNames,
    required this.purchaseLineCount,
    required this.purchaseDayCount,
    required this.trainingCycleCount,
    required this.alignment,
    required this.baselineMode,
    required this.baselineDailyBase,
    required this.rSquared,
    required this.normalizedMae,
    required this.residualScale,
    required this.confidence,
    required this.coefficients,
    required this.cycles,
    required this.totalPurchasedBase,
    required this.totalPredictedPaidBase,
    required this.totalCancelledKitchenExplainedBase,
    required this.totalResidualOperationalBase,
    required this.recentResidualOperationalBase,
    required this.recentHighAnomalies,
  });

  final PredictiveIngredientDefinition definition;
  final String unitFamily;
  final String baseUnitLabel;
  final List<String> supplierNames;
  final int purchaseLineCount;
  final int purchaseDayCount;
  final int trainingCycleCount;
  final PredictiveAlignment alignment;
  final String baselineMode;
  final double baselineDailyBase;
  final double rSquared;
  final double normalizedMae;
  final double residualScale;
  final String confidence;
  final List<PredictiveProductCoefficient> coefficients;
  final List<PredictiveConsumptionCycle> cycles;
  final double totalPurchasedBase;
  final double totalPredictedPaidBase;
  final double totalCancelledKitchenExplainedBase;
  final double totalResidualOperationalBase;
  final double recentResidualOperationalBase;
  final int recentHighAnomalies;

  bool get isWeight => unitFamily == 'weight';
  bool get isPieces => unitFamily == 'pieces';
  bool get isAuditUsable => confidence == 'Alta' || confidence == 'Media';
  bool get isExploratory => !isAuditUsable;

  List<PredictiveConsumptionCycle> get investigationCycles => cycles
      .where((cycle) => cycle.isInvestigationPeriod)
      .toList(growable: false);

  PredictiveConsumptionCycle? get highestRecentAnomaly {
    final recent = investigationCycles;
    if (recent.isEmpty) return null;
    return recent.reduce(
      (a, b) => a.anomalyScore >= b.anomalyScore ? a : b,
    );
  }

  double get learnedRawPerSaleWeighted {
    final totalUnits = coefficients.fold<double>(
      0,
      (sum, row) => sum + row.unitsInTraining,
    );
    if (totalUnits <= 0) return 0;
    return coefficients.fold<double>(
          0,
          (sum, row) => sum + row.rawBasePerUnit * row.unitsInTraining,
        ) /
        totalUnits;
  }

  double? get learnedCookedPerSaleWeighted {
    final valid = coefficients
        .where((row) => row.cookedBasePerUnit != null)
        .toList(growable: false);
    final totalUnits = valid.fold<double>(
      0,
      (sum, row) => sum + row.unitsInTraining,
    );
    if (totalUnits <= 0) return null;
    return valid.fold<double>(
          0,
          (sum, row) => sum + row.cookedBasePerUnit! * row.unitsInTraining,
        ) /
        totalUnits;
  }
}

enum PredictiveAlignment { forwardSupply, replenishment }

class PredictiveConsumptionAudit {
  const PredictiveConsumptionAudit({
    required this.historyStart,
    required this.historyEnd,
    required this.investigationStart,
    required this.models,
    required this.detectedSupplierNames,
    required this.purchaseLinesLoaded,
    required this.paidSaleLinesLoaded,
    required this.cancelledKitchenLinesLoaded,
    required this.cashDaysLoaded,
    required this.notes,
  });

  final String historyStart;
  final String historyEnd;
  final String investigationStart;
  final List<PredictiveIngredientModel> models;
  final List<String> detectedSupplierNames;
  final int purchaseLinesLoaded;
  final int paidSaleLinesLoaded;
  final int cancelledKitchenLinesLoaded;
  final int cashDaysLoaded;
  final List<String> notes;

  int get highAnomalyCycles =>
      models.where((model) => model.isAuditUsable)
          .fold(0, (sum, model) => sum + model.recentHighAnomalies);

  double _positiveResidualForConfidence(String confidence) => models
      .where((model) => model.isWeight && model.confidence == confidence)
      .fold<double>(
        0,
        (sum, model) =>
            sum + math.max(0.0, model.recentResidualOperationalBase).toDouble(),
      );

  double get recentPositiveResidualHighWeightGrams =>
      _positiveResidualForConfidence('Alta');
  double get recentPositiveResidualMediumWeightGrams =>
      _positiveResidualForConfidence('Media');
  double get recentPositiveResidualLowWeightGrams =>
      _positiveResidualForConfidence('Baja');
  double get recentPositiveResidualAuditableWeightGrams =>
      recentPositiveResidualHighWeightGrams +
      recentPositiveResidualMediumWeightGrams;
  double get recentPositiveResidualWeightGrams =>
      recentPositiveResidualAuditableWeightGrams +
      recentPositiveResidualLowWeightGrams;

  List<PredictiveConsumptionCycleFinding> get rankedFindings {
    final findings = <PredictiveConsumptionCycleFinding>[];
    for (final model in models.where((item) => item.isAuditUsable)) {
      for (final cycle in model.investigationCycles) {
        if (!cycle.isAuditEligible) continue;
        findings.add(
          PredictiveConsumptionCycleFinding(
            ingredientName: model.definition.name,
            baseUnitLabel: model.baseUnitLabel,
            confidence: model.confidence,
            cycle: cycle,
          ),
        );
      }
    }
    findings.sort(
      (a, b) => b.cycle.anomalyScore.compareTo(a.cycle.anomalyScore),
    );
    return findings;
  }
}

class PredictiveConsumptionCycleFinding {
  const PredictiveConsumptionCycleFinding({
    required this.ingredientName,
    required this.baseUnitLabel,
    required this.confidence,
    required this.cycle,
  });

  final String ingredientName;
  final String baseUnitLabel;
  final String confidence;
  final PredictiveConsumptionCycle cycle;
}

class _DailyIngredientSales {
  _DailyIngredientSales();

  final Map<String, double> paidByProduct = {};
  final Map<String, double> cancelledByProduct = {};
}

class _PurchaseDay {
  _PurchaseDay(this.date);

  final String date;
  double quantity = 0;
}

class _CycleInput {
  const _CycleInput({
    required this.purchaseDate,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.operatingDays,
    required this.target,
    required this.knownOperationalBase,
    required this.paid,
    required this.cancelled,
    required this.shortage,
  });

  final String purchaseDate;
  final String startDate;
  final String endDate;
  final int days;
  final int operatingDays;
  final double target;
  final double knownOperationalBase;
  final Map<String, double> paid;
  final Map<String, double> cancelled;
  final double shortage;

  double get paidUnits => paid.values.fold(0, (sum, value) => sum + value);
  double get cancelledUnits =>
      cancelled.values.fold(0, (sum, value) => sum + value);
}

class _FitResult {
  const _FitResult({
    required this.coefficients,
    required this.baselineDaily,
    required this.predictions,
    required this.residuals,
    required this.rSquared,
    required this.normalizedMae,
    required this.residualScale,
  });

  final Map<String, double> coefficients;
  final double baselineDaily;
  final List<double> predictions;
  final List<double> residuals;
  final double rSquared;
  final double normalizedMae;
  final double residualScale;
}

PredictiveConsumptionAudit buildPredictiveConsumptionAudit({
  required Iterable<PredictivePurchaseLine> purchaseLines,
  required Iterable<PredictiveSaleLine> saleLines,
  required Iterable<PredictiveCashDay> cashDays,
  required Iterable<PredictiveYieldInput> yieldInputs,
  required String historyStart,
  required String historyEnd,
  String investigationStart = '2026-09-28',
}) {
  final purchases = purchaseLines.where((line) {
    final supplier = normalizeYieldName(line.supplierName);
    return supplier.contains('noe') || supplier.contains('omar');
  }).toList(growable: false);

  final paidSales = saleLines
      .where((line) => line.isPaidSale)
      .toList(growable: false);
  final cancelledSales = saleLines
      .where((line) => line.isCancelledKitchen)
      .toList(growable: false);
  final cashByDate = <String, PredictiveCashDay>{
    for (final day in cashDays) day.businessDate: day,
  };
  final yields = yieldInputs.toList(growable: false);

  final groups = <String, List<PredictivePurchaseLine>>{};
  final definitions = <String, PredictiveIngredientDefinition>{};
  for (final line in purchases) {
    final definition = detectPredictiveIngredient(
      itemName: line.stockItemName.trim().isNotEmpty
          ? line.stockItemName
          : line.itemName,
      supplierName: line.supplierName,
    );
    if (definition == null) continue;
    final family = line.unitFamily;
    final key = '${definition.key}|$family';
    groups.putIfAbsent(key, () => []).add(line);
    definitions[key] = definition;
  }

  final models = <PredictiveIngredientModel>[];
  for (final entry in groups.entries) {
    final lines = entry.value;
    final definition = definitions[entry.key]!;
    if (lines.length < 2) continue;

    final dailySales = <String, _DailyIngredientSales>{};
    final productNames = <String, String>{};

    void addSale(PredictiveSaleLine line) {
      if (!_saleMatchesIngredient(line, definition)) return;
      final productKey = _productKey(line.productId, line.productName);
      productNames[productKey] = line.productName;
      final daily = dailySales.putIfAbsent(
        line.businessDate,
        _DailyIngredientSales.new,
      );
      final map = line.isPaidSale
          ? daily.paidByProduct
          : daily.cancelledByProduct;
      map[productKey] = (map[productKey] ?? 0) + line.quantity;
    }

    for (final sale in paidSales) {
      addSale(sale);
    }
    for (final sale in cancelledSales) {
      addSale(sale);
    }

    if (productNames.isEmpty) continue;

    final purchaseByDate = <String, _PurchaseDay>{};
    for (final line in lines) {
      final date = line.businessDate.trim().isNotEmpty
          ? line.businessDate
          : _dateKey(line.purchaseDate);
      final day = purchaseByDate.putIfAbsent(date, () => _PurchaseDay(date));
      day.quantity += line.baseQuantity;
    }
    final purchaseDays = purchaseByDate.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (purchaseDays.length < 2) continue;

    final forward = _buildCycles(
      purchaseDays: purchaseDays,
      dailySales: dailySales,
      cashByDate: cashByDate,
      historyStart: historyStart,
      historyEnd: historyEnd,
      alignment: PredictiveAlignment.forwardSupply,
      definition: definition,
      unitFamily: lines.first.unitFamily,
    );
    final replenishment = _buildCycles(
      purchaseDays: purchaseDays,
      dailySales: dailySales,
      cashByDate: cashByDate,
      historyStart: historyStart,
      historyEnd: historyEnd,
      alignment: PredictiveAlignment.replenishment,
      definition: definition,
      unitFamily: lines.first.unitFamily,
    );

    final forwardTraining = _trainingCycles(forward, investigationStart);
    final replenishmentTraining = _trainingCycles(
      replenishment,
      investigationStart,
    );
    final forwardKeys = _selectFeatureKeys(
      cycles: forwardTraining,
      productNames: productNames,
    );
    final replenishmentKeys = _selectFeatureKeys(
      cycles: replenishmentTraining,
      productNames: productNames,
    );
    final forwardFit = _fitCycles(forwardTraining, forwardKeys);
    final replenishFit = _fitCycles(replenishmentTraining, replenishmentKeys);

    PredictiveAlignment alignment;
    List<_CycleInput> allCycles;
    List<_CycleInput> training;
    List<String> candidateKeys;
    _FitResult fit;
    if (replenishFit != null &&
        (forwardFit == null ||
            _modelScore(replenishFit, replenishmentTraining.length) <
                _modelScore(forwardFit, forwardTraining.length))) {
      alignment = PredictiveAlignment.replenishment;
      allCycles = replenishment;
      training = replenishmentTraining;
      candidateKeys = replenishmentKeys;
      fit = replenishFit;
    } else if (forwardFit != null) {
      alignment = PredictiveAlignment.forwardSupply;
      allCycles = forward;
      training = forwardTraining;
      candidateKeys = forwardKeys;
      fit = forwardFit;
    } else {
      continue;
    }

    final cleanTraining =
        training.isNotEmpty && training.every(_isCleanTrainingCycle);
    final baselineMode = cleanTraining
        ? 'Historico previo limpio: faltante <= 20 y cancelaciones controladas'
        : 'Historico previo al periodo de investigacion (sin usar septiembre)';

    final yieldRate = _resolveYieldRate(definition, lines, yields);
    final totalTrainingUnits = candidateKeys.fold<double>(
      0,
      (sum, key) =>
          sum +
          training.fold<double>(
            0,
            (subtotal, cycle) => subtotal + (cycle.paid[key] ?? 0),
          ),
    );

    final coefficients = <PredictiveProductCoefficient>[];
    for (final key in candidateKeys) {
      final raw = fit.coefficients[key] ?? 0;
      final units = training.fold<double>(
        0,
        (sum, cycle) => sum + (cycle.paid[key] ?? 0),
      );
      if (raw <= 0.000001 || units <= 0) continue;
      final cooked = definition.kind == PredictiveIngredientKind.meat &&
              yieldRate != null &&
              yieldRate > 0
          ? raw * yieldRate
          : null;
      coefficients.add(
        PredictiveProductCoefficient(
          productKey: key,
          productName: productNames[key] ?? key,
          rawBasePerUnit: raw,
          cookedBasePerUnit: cooked,
          unitsInTraining: units,
          shareOfTrainingUnits:
              totalTrainingUnits <= 0 ? 0.0 : units / totalTrainingUnits,
          plausibility: _coefficientPlausibility(
            definition: definition,
            family: lines.first.unitFamily,
            raw: raw,
            cooked: cooked,
          ),
        ),
      );
    }
    coefficients.sort(
      (a, b) => b.unitsInTraining.compareTo(a.unitsInTraining),
    );

    final confidence = _modelConfidence(
      trainingCount: training.length,
      rSquared: fit.rSquared,
      normalizedMae: fit.normalizedMae,
      coefficientCount: coefficients.length,
    );
    final trainingTargets = training.map((cycle) => cycle.target).toList();

    final outputCycles = allCycles.map((cycle) {
      final predictedPaid = _predictCycle(cycle, fit);
      final cancelledExplained = fit.coefficients.entries.fold<double>(
        0,
        (sum, coefficient) =>
            sum +
            coefficient.value * (cycle.cancelled[coefficient.key] ?? 0),
      );
      final knownOperational = cycle.knownOperationalBase;
      final predictedOperational =
          predictedPaid + knownOperational + cancelledExplained;
      final residualPaid =
          cycle.target - predictedPaid - knownOperational;
      final residualOperational = cycle.target - predictedOperational;
      final residualPercent = predictedOperational.abs() < 0.001
          ? 0.0
          : residualOperational / predictedOperational;
      final robustZ = fit.residualScale <= 0
          ? 0.0
          : residualOperational / fit.residualScale;
      final intervalHalfWidth = fit.residualScale * 1.96;
      final expectedLow = math
          .max(0.0, predictedOperational - intervalHalfWidth)
          .toDouble();
      final expectedHigh = predictedOperational + intervalHalfWidth;
      final rawScore = _anomalyScore(
        robustZ: robustZ,
        residualPercent: residualPercent,
        cancelledExplained: cancelledExplained,
        predictedPaid: predictedPaid,
      );
      final purchaseMagnitudeOutlier = _isPurchaseMagnitudeOutlier(
        cycle.target,
        trainingTargets,
      );
      final score = _qualityAdjustedAnomalyScore(
        rawScore: rawScore,
        confidence: confidence,
        rSquared: fit.rSquared,
        purchaseMagnitudeOutlier: purchaseMagnitudeOutlier,
      );
      return PredictiveConsumptionCycle(
        purchaseDate: cycle.purchaseDate,
        startBusinessDate: cycle.startDate,
        endBusinessDate: cycle.endDate,
        days: cycle.days,
        operatingDays: cycle.operatingDays,
        purchasedBase: cycle.target,
        knownOperationalBase: knownOperational,
        predictedPaidBase: predictedPaid,
        cancelledKitchenExplainedBase: cancelledExplained,
        predictedOperationalBase: predictedOperational,
        residualPaidBase: residualPaid,
        residualOperationalBase: residualOperational,
        residualPercent: residualPercent,
        expectedLowBase: expectedLow,
        expectedHighBase: expectedHigh,
        robustZ: robustZ,
        anomalyScore: score,
        shortageAmount: cycle.shortage,
        paidUnits: cycle.paidUnits,
        cancelledKitchenUnits: cycle.cancelledUnits,
        evidence: _cycleEvidence(
          residualPaid: residualPaid,
          residualOperational: residualOperational,
          cancelledExplained: cancelledExplained,
          knownOperational: knownOperational,
          purchaseMagnitudeOutlier: purchaseMagnitudeOutlier,
          shortage: cycle.shortage,
          family: lines.first.unitFamily,
        ),
        isInvestigationPeriod:
            cycle.endDate.compareTo(investigationStart) >= 0,
        purchaseMagnitudeOutlier: purchaseMagnitudeOutlier,
      );
    }).toList()
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));

    final recent = outputCycles.where((cycle) => cycle.isInvestigationPeriod);

    models.add(
      PredictiveIngredientModel(
        definition: definition,
        unitFamily: lines.first.unitFamily,
        baseUnitLabel: predictiveBaseUnitLabel(lines.first.unitFamily),
        supplierNames:
            lines.map((line) => line.supplierName).toSet().toList()..sort(),
        purchaseLineCount: lines.length,
        purchaseDayCount: purchaseDays.length,
        trainingCycleCount: training.length,
        alignment: alignment,
        baselineMode: baselineMode,
        baselineDailyBase: fit.baselineDaily,
        rSquared: fit.rSquared,
        normalizedMae: fit.normalizedMae,
        residualScale: fit.residualScale,
        confidence: confidence,
        coefficients: coefficients,
        cycles: outputCycles,
        totalPurchasedBase: outputCycles.fold(
          0,
          (sum, cycle) => sum + cycle.purchasedBase,
        ),
        totalPredictedPaidBase: outputCycles.fold(
          0,
          (sum, cycle) => sum + cycle.predictedPaidBase,
        ),
        totalCancelledKitchenExplainedBase: outputCycles.fold(
          0,
          (sum, cycle) => sum + cycle.cancelledKitchenExplainedBase,
        ),
        totalResidualOperationalBase: outputCycles.fold(
          0,
          (sum, cycle) => sum + cycle.residualOperationalBase,
        ),
        recentResidualOperationalBase: recent.fold(
          0,
          (sum, cycle) => sum + cycle.residualOperationalBase,
        ),
        recentHighAnomalies:
            recent.where((cycle) => cycle.isHighAnomaly).length,
      ),
    );
  }

  models.sort((a, b) {
    final anomaly = b.recentHighAnomalies.compareTo(a.recentHighAnomalies);
    if (anomaly != 0) return anomaly;
    return a.definition.name.compareTo(b.definition.name);
  });

  final suppliers = purchases.map((line) => line.supplierName).toSet().toList()
    ..sort();

  final notes = <String>[
    'El modelo aprende de ciclos de reposicion, no iguala compra del dia con venta del dia.',
    'Prueba automaticamente si la compra abastece ventas futuras o repone consumo previo y conserva la alineacion con menor error robusto.',
    'Los coeficientes se ajustan con regresion no negativa regularizada y reponderacion robusta para que dias atipicos no definan el consumo normal.',
    'Cuando hay al menos 3 a 5 ciclos suficientes, el entrenamiento prefiere periodos con faltante de caja <= 20 y cancelaciones de cocina controladas para construir una linea base mas limpia.',
    'Sin inventario fisico no puede demostrarse una fuga: una discrepancia tambien puede ser merma, cambio de stock inicial/final, porcion distinta o captura incompleta.',
    'Las cancelaciones que tocaron cocina se muestran por separado para medir cuanto consumo podrian explicar sin contarlas como venta.',
    'El periodo de investigacion se aplica a las fechas de consumo cubiertas por cada ciclo, no solo a la fecha de compra, para no contaminar el entrenamiento con ventas posteriores al corte.',
    'Si el patron aprendido es abastecimiento hacia adelante, la compra mas reciente queda abierta y no se califica hasta que exista la siguiente reposicion.',
    'El rango esperado usa la dispersion robusta del historico (aprox. 95%). Estar fuera del rango es una señal de investigacion, no una prueba de robo.',
  ];

  return PredictiveConsumptionAudit(
    historyStart: historyStart,
    historyEnd: historyEnd,
    investigationStart: investigationStart,
    models: models,
    detectedSupplierNames: suppliers,
    purchaseLinesLoaded: purchases.length,
    paidSaleLinesLoaded: paidSales.length,
    cancelledKitchenLinesLoaded: cancelledSales.length,
    cashDaysLoaded: cashByDate.length,
    notes: notes,
  );
}

PredictiveIngredientDefinition? detectPredictiveIngredient({
  required String itemName,
  required String supplierName,
}) {
  final item = normalizeYieldName(itemName);
  final supplier = normalizeYieldName(supplierName);

  if (supplier.contains('noe') || item.contains('tortilla')) {
    if (item.contains('harina')) {
      return predictiveIngredientDefinitions.firstWhere(
        (definition) => definition.key == 'tortilla_harina',
      );
    }
    if (item.contains('maiz')) {
      return predictiveIngredientDefinitions.firstWhere(
        (definition) => definition.key == 'tortilla_maiz',
      );
    }
    if (item.contains('tortilla')) {
      return predictiveIngredientDefinitions.firstWhere(
        (definition) => definition.key == 'tortilla',
      );
    }
  }

  if (supplier.contains('omar') || supplier.contains('carne')) {
    for (final definition in predictiveIngredientDefinitions.where(
      (item) => item.kind == PredictiveIngredientKind.meat,
    )) {
      if (definition.aliases.any(
        (alias) => item.contains(normalizeYieldName(alias)),
      )) {
        return definition;
      }
    }
  }

  for (final definition in predictiveIngredientDefinitions.where(
    (item) => item.kind == PredictiveIngredientKind.meat,
  )) {
    if (definition.aliases.any(
      (alias) => item.contains(normalizeYieldName(alias)),
    )) {
      return definition;
    }
  }
  return null;
}

String predictiveUnitFamily(String unit) {
  final normalized = normalizeYieldName(unit);
  if (const {
    'kg',
    'kilogramo',
    'kilogramos',
    'g',
    'gr',
    'gramo',
    'gramos',
  }.contains(normalized)) {
    return 'weight';
  }
  if (const {
    'pieza',
    'piezas',
    'piece',
    'pieces',
    'unidad',
    'unidades',
  }.contains(normalized)) {
    return 'pieces';
  }
  if (const {
    'l',
    'litro',
    'litros',
    'ml',
    'mililitro',
    'mililitros',
  }.contains(normalized)) {
    return 'volume';
  }
  return 'units';
}

String predictiveBaseUnitLabel(String family) {
  return switch (family) {
    'weight' => 'g',
    'pieces' => 'pzas',
    'volume' => 'ml',
    _ => 'unid.',
  };
}

bool _saleMatchesIngredient(
  PredictiveSaleLine sale,
  PredictiveIngredientDefinition definition,
) {
  final product = normalizeYieldName(sale.productName);
  final category = normalizeYieldName(sale.categoryName);
  final ingredients = sale.ingredientNames.map(normalizeYieldName).toList();

  bool ingredientHas(String token) =>
      ingredients.any((name) => name.contains(token));

  switch (definition.kind) {
    case PredictiveIngredientKind.meat:
      for (final alias in definition.aliases.map(normalizeYieldName)) {
        if (product.contains(alias) || ingredientHas(alias)) return true;
      }
      return false;
    case PredictiveIngredientKind.tortillaFlour:
      return ingredientHas('tortilla de harina') ||
          ingredientHas('tortilla harina') ||
          product.contains('gringa') ||
          category.contains('gringa');
    case PredictiveIngredientKind.tortillaCorn:
      if (ingredientHas('tortilla de maiz') ||
          ingredientHas('tortilla maiz')) {
        return true;
      }
      final isGringa = product.contains('gringa') || category.contains('gringa');
      final isTaco =
          product.contains('taco') ||
          category == 'taco' ||
          category == 'tacos' ||
          category.contains('tacos');
      return isTaco && !isGringa;
    case PredictiveIngredientKind.tortillaAny:
      if (ingredients.any((name) => name.contains('tortilla'))) return true;
      return product.contains('taco') ||
          category.contains('taco') ||
          product.contains('gringa') ||
          category.contains('gringa');
  }
}

String _productKey(String productId, String productName) {
  final id = productId.trim();
  if (id.isNotEmpty) return id;
  return normalizeYieldName(productName);
}

List<String> _selectFeatureKeys({
  required List<_CycleInput> cycles,
  required Map<String, String> productNames,
}) {
  if (cycles.length < 3) return const [];
  final totals = <String, double>{};
  for (final cycle in cycles) {
    for (final entry in cycle.paid.entries) {
      totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
    }
  }
  final keys = totals.entries
      .where((entry) => entry.value >= 3 && productNames.containsKey(entry.key))
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final maxFeatures = math.max(1, math.min(8, cycles.length - 2));
  return keys
      .take(maxFeatures)
      .map((entry) => entry.key)
      .toList(growable: false);
}

List<_CycleInput> _trainingCycles(
  List<_CycleInput> cycles,
  String investigationStart,
) {
  final previous = cycles
      .where(
        (cycle) =>
            cycle.endDate.compareTo(investigationStart) < 0 &&
            cycle.paidUnits > 0,
      )
      .toList();

  // The primary baseline is strictly pre-investigation. Never use cycles from
  // the investigated period to manufacture enough observations: insufficient
  // history must remain insufficient rather than teaching the anomaly as normal.
  final cleanPrevious = previous
      .where(_isCleanTrainingCycle)
      .toList(growable: false);
  if (cleanPrevious.length >= 5) return cleanPrevious;
  if (previous.length >= 5) return previous;
  if (cleanPrevious.length >= 3) return cleanPrevious;
  return previous;
}

bool _isCleanTrainingCycle(_CycleInput cycle) {
  final cancellationLimit = math.max(2.0, cycle.paidUnits * 0.10).toDouble();
  return cycle.shortage <= 20.0 &&
      cycle.cancelledUnits <= cancellationLimit;
}

List<_CycleInput> _buildCycles({
  required List<_PurchaseDay> purchaseDays,
  required Map<String, _DailyIngredientSales> dailySales,
  required Map<String, PredictiveCashDay> cashByDate,
  required String historyStart,
  required String historyEnd,
  required PredictiveAlignment alignment,
  required PredictiveIngredientDefinition definition,
  required String unitFamily,
}) {
  final result = <_CycleInput>[];

  if (alignment == PredictiveAlignment.forwardSupply) {
    for (var i = 0; i < purchaseDays.length; i++) {
      final purchase = purchaseDays[i];
      final start = purchase.date;
      final next = i + 1 < purchaseDays.length ? purchaseDays[i + 1].date : null;
      // Forward supply cannot be closed until the next purchase defines where
      // the current batch stopped covering consumption. Scoring the last open
      // batch would create a false anomaly simply because stock remains.
      if (next == null) continue;
      final end = _shiftDate(next, -1);
      if (end.compareTo(start) < 0) continue;
      final days = _daysInclusive(start, end);
      if (days <= 0 || days > 21) continue;
      result.add(
        _cycleFromRange(
          purchase: purchase,
          start: start,
          end: end,
          days: days,
          dailySales: dailySales,
          cashByDate: cashByDate,
          definition: definition,
          unitFamily: unitFamily,
        ),
      );
    }
    return result;
  }

  for (var i = 1; i < purchaseDays.length; i++) {
    final purchase = purchaseDays[i];
    final previous = purchaseDays[i - 1];
    final start = previous.date;
    final end = _shiftDate(purchase.date, -1);
    if (end.compareTo(start) < 0) continue;
    final days = _daysInclusive(start, end);
    if (days <= 0 || days > 21) continue;
    result.add(
      _cycleFromRange(
        purchase: purchase,
        start: start,
        end: end,
        days: days,
        dailySales: dailySales,
        cashByDate: cashByDate,
      ),
    );
  }
  return result;
}

_CycleInput _cycleFromRange({
  required _PurchaseDay purchase,
  required String start,
  required String end,
  required int days,
  required Map<String, _DailyIngredientSales> dailySales,
  required Map<String, PredictiveCashDay> cashByDate,
  required PredictiveIngredientDefinition definition,
  required String unitFamily,
}) {
  final paid = <String, double>{};
  final cancelled = <String, double>{};
  var shortage = 0.0;

  for (final date in _dateKeys(start, end)) {
    final sales = dailySales[date];
    if (sales != null) {
      for (final entry in sales.paidByProduct.entries) {
        paid[entry.key] = (paid[entry.key] ?? 0) + entry.value;
      }
      for (final entry in sales.cancelledByProduct.entries) {
        cancelled[entry.key] = (cancelled[entry.key] ?? 0) + entry.value;
      }
    }
    shortage += cashByDate[date]?.shortageAmount ?? 0;
  }

  final operatingDays = _operatingDaysInclusive(start, end);
  return _CycleInput(
    purchaseDate: purchase.date,
    startDate: start,
    endDate: end,
    days: days,
    operatingDays: operatingDays,
    target: purchase.quantity,
    knownOperationalBase: _knownOperationalBase(
      definition: definition,
      unitFamily: unitFamily,
      operatingDays: operatingDays,
    ),
    paid: paid,
    cancelled: cancelled,
    shortage: shortage,
  );
}

double _knownOperationalBase({
  required PredictiveIngredientDefinition definition,
  required String unitFamily,
  required int operatingDays,
}) {
  if (unitFamily != 'weight') return 0;
  if (definition.kind == PredictiveIngredientKind.tortillaCorn ||
      definition.kind == PredictiveIngredientKind.tortillaAny) {
    // Operational rule confirmed by the business: about 1 kg of corn tortilla
    // is used for doraditas on each open day. Sunday is closed.
    return operatingDays * 1000.0;
  }
  return 0;
}

int _operatingDaysInclusive(String start, String end) {
  var count = 0;
  for (final key in _dateKeys(start, end)) {
    final parts = key.split('-').map(int.parse).toList(growable: false);
    final date = DateTime(parts[0], parts[1], parts[2]);
    if (date.weekday != DateTime.sunday) count++;
  }
  return count;
}

_FitResult? _fitCycles(List<_CycleInput> cycles, List<String> keys) {
  if (cycles.length < 3 || keys.isEmpty) return null;
  final rows = cycles.where((cycle) => cycle.target > 0).toList();
  if (rows.length < 3) return null;

  final featureCount = keys.length + 1;
  final x = <List<double>>[];
  final y = <double>[];
  final knownOffsets = <double>[];
  for (final cycle in rows) {
    x.add([
      for (final key in keys) cycle.paid[key] ?? 0,
      cycle.operatingDays.toDouble(),
    ]);
    y.add(cycle.target);
    knownOffsets.add(cycle.knownOperationalBase);
  }
  final adjustedY = List<double>.generate(
    y.length,
    (i) => y[i] - knownOffsets[i],
  );

  final scales = List<double>.filled(featureCount, 1);
  for (var j = 0; j < featureCount; j++) {
    final sumSquares = x.fold<double>(
      0,
      (sum, row) => sum + row[j] * row[j],
    );
    final rms = math.sqrt(sumSquares / x.length);
    scales[j] = rms > 0.000001 ? rms : 1;
    for (final row in x) {
      row[j] /= scales[j];
    }
  }

  var weights = List<double>.filled(x.length, 1);
  var beta = List<double>.filled(featureCount, 0);
  for (var robustIteration = 0; robustIteration < 5; robustIteration++) {
    beta = _nonNegativeRidge(
      x: x,
      y: adjustedY,
      weights: weights,
      lambda: 0.01,
      iterations: 180,
    );
    final predictions = List<double>.generate(
      x.length,
      (i) => knownOffsets[i] + _dot(x[i], beta),
    );
    final residuals = List<double>.generate(
      x.length,
      (i) => y[i] - predictions[i],
    );
    final scale = _robustScale(residuals);
    if (scale <= 0.000001) break;
    const huberK = 1.5;
    weights = residuals.map((residual) {
      final a = residual.abs();
      final threshold = huberK * scale;
      return a <= threshold || a == 0 ? 1.0 : threshold / a;
    }).toList(growable: false);
  }

  final unscaled = <double>[
    for (var j = 0; j < featureCount; j++) beta[j] / scales[j],
  ];
  final predictions = <double>[
    for (final cycle in rows)
      keys.indexed.fold<double>(
            cycle.knownOperationalBase +
                unscaled.last * cycle.operatingDays,
            (sum, entry) =>
                sum + unscaled[entry.$1] * (cycle.paid[entry.$2] ?? 0),
          ),
  ];
  final residuals = List<double>.generate(
    rows.length,
    (i) => y[i] - predictions[i],
  );
  final meanY = y.fold<double>(0, (sum, value) => sum + value) / y.length;
  final sse = residuals.fold<double>(
    0,
    (sum, residual) => sum + residual * residual,
  );
  final sst = y.fold<double>(
    0,
    (sum, value) => sum + math.pow(value - meanY, 2).toDouble(),
  );
  final r2 = sst <= 0.000001
      ? 0.0
      : (1 - sse / sst).clamp(-1.0, 1.0).toDouble();
  final mae = residuals.fold<double>(
        0,
        (sum, residual) => sum + residual.abs(),
      ) /
      residuals.length;
  final normalizedMae = meanY.abs() <= 0.000001 ? 1.0 : mae / meanY.abs();

  return _FitResult(
    coefficients: {
      for (var i = 0; i < keys.length; i++) keys[i]: unscaled[i],
    },
    baselineDaily: unscaled.last,
    predictions: predictions,
    residuals: residuals,
    rSquared: r2,
    normalizedMae: normalizedMae,
    residualScale: _robustScale(residuals),
  );
}

List<double> _nonNegativeRidge({
  required List<List<double>> x,
  required List<double> y,
  required List<double> weights,
  required double lambda,
  required int iterations,
}) {
  final p = x.first.length;
  final beta = List<double>.filled(p, 0);
  final prediction = List<double>.filled(x.length, 0);

  for (var iteration = 0; iteration < iterations; iteration++) {
    var maxChange = 0.0;
    for (var j = 0; j < p; j++) {
      var numerator = 0.0;
      var denominator = 0.0;
      for (var i = 0; i < x.length; i++) {
        final value = x[i][j];
        if (value == 0) continue;
        final partial = y[i] - (prediction[i] - beta[j] * value);
        numerator += weights[i] * value * partial;
        denominator += weights[i] * value * value;
      }
      // The final feature is the per-day baseline. Penalize it much
      // harder than product coefficients so it absorbs true fixed waste/buffer
      // without stealing explanatory power from units sold when the two are
      // correlated (common on one-purchase-per-day histories).
      final featurePenalty = j == p - 1 ? lambda * 25 : lambda;
      denominator += featurePenalty;
      final next = denominator <= 0
          ? 0.0
          : math.max(0.0, numerator / denominator).toDouble();
      final delta = next - beta[j];
      if (delta != 0) {
        for (var i = 0; i < x.length; i++) {
          prediction[i] += delta * x[i][j];
        }
      }
      maxChange = math.max(maxChange, delta.abs()).toDouble();
      beta[j] = next;
    }
    if (maxChange < 1e-7) break;
  }
  return beta;
}

double _modelScore(_FitResult fit, int observations) {
  final samplePenalty = observations < 6 ? (6 - observations) * 0.08 : 0.0;
  final r2Penalty = fit.rSquared < 0 ? fit.rSquared.abs() * 0.15 : 0.0;
  return fit.normalizedMae + samplePenalty + r2Penalty;
}

double _predictCycle(_CycleInput cycle, _FitResult fit) {
  var prediction = fit.baselineDaily * cycle.operatingDays;
  for (final entry in fit.coefficients.entries) {
    prediction += entry.value * (cycle.paid[entry.key] ?? 0);
  }
  return prediction;
}

double? _resolveYieldRate(
  PredictiveIngredientDefinition definition,
  List<PredictivePurchaseLine> purchaseLines,
  List<PredictiveYieldInput> yields,
) {
  if (definition.kind != PredictiveIngredientKind.meat) return null;
  final stockIds = purchaseLines
      .map((line) => line.stockItemId.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  for (final yield in yields) {
    if (stockIds.contains(yield.stockItemId) &&
        yield.yieldRate > 0 &&
        yield.yieldRate <= 1.2) {
      return yield.yieldRate;
    }
  }
  for (final yield in yields) {
    final name = normalizeYieldName(yield.stockItemName);
    if (definition.aliases.any(
      (alias) => name.contains(normalizeYieldName(alias)),
    )) {
      if (yield.yieldRate > 0 && yield.yieldRate <= 1.2) {
        return yield.yieldRate;
      }
    }
  }
  for (final seed in initialYieldDefinitions) {
    if (normalizeYieldName(seed.name) == normalizeYieldName(definition.name)) {
      return seed.percent / 100;
    }
  }
  return null;
}

String _coefficientPlausibility({
  required PredictiveIngredientDefinition definition,
  required String family,
  required double raw,
  required double? cooked,
}) {
  if (family != 'weight') return 'Dato empirico';
  if (definition.kind == PredictiveIngredientKind.meat) {
    final cookedValue = cooked;
    if (cookedValue == null || cookedValue.isNaN) return 'Sin rendimiento';
    if (cookedValue >= 20 && cookedValue <= 120) return 'Plausible';
    if (cookedValue > 0 && cookedValue <= 180) return 'Revisar porcion';
    return 'Atipico';
  }
  if (definition.kind == PredictiveIngredientKind.tortillaCorn ||
      definition.kind == PredictiveIngredientKind.tortillaFlour ||
      definition.kind == PredictiveIngredientKind.tortillaAny) {
    if (raw > 0 && raw <= 150) return 'Plausible como peso efectivo';
    return 'Revisar conversion kg/pieza';
  }
  return 'Dato empirico';
}

String _modelConfidence({
  required int trainingCount,
  required double rSquared,
  required double normalizedMae,
  required int coefficientCount,
}) {
  if (coefficientCount <= 0) return 'Baja';
  final highMinCycles = math.max(10, coefficientCount + 6);
  final mediumMinCycles = math.max(6, coefficientCount + 3);
  if (trainingCount >= highMinCycles &&
      rSquared >= 0.55 &&
      normalizedMae <= 0.30) {
    return 'Alta';
  }
  if (trainingCount >= mediumMinCycles &&
      rSquared >= 0.25 &&
      normalizedMae <= 0.50) {
    return 'Media';
  }
  return 'Baja';
}

double _anomalyScore({
  required double robustZ,
  required double residualPercent,
  required double cancelledExplained,
  required double predictedPaid,
}) {
  var score = math.min(55.0, robustZ.abs() * 18).toDouble();
  score += math.min(25.0, residualPercent.abs() * 35).toDouble();
  if (cancelledExplained >
      math.max(50.0, predictedPaid * 0.10).toDouble()) {
    score += 10;
  }
  return score.clamp(0.0, 100.0).toDouble();
}

double _qualityAdjustedAnomalyScore({
  required double rawScore,
  required String confidence,
  required double rSquared,
  required bool purchaseMagnitudeOutlier,
}) {
  if (purchaseMagnitudeOutlier || confidence == 'Baja' || rSquared < 0) {
    // Exploratory/data-quality signals stay visible in ingredient detail but
    // cannot enter the main audit radar as a strong finding.
    return math.min(rawScore, 34.0).toDouble();
  }
  return rawScore;
}

bool _isPurchaseMagnitudeOutlier(
  double target,
  List<double> trainingTargets,
) {
  final values = trainingTargets.where((value) => value > 0).toList();
  if (values.length < 3) return false;
  final median = _median(values);
  if (median <= 0) return false;
  final deviations =
      values.map((value) => (value - median).abs()).toList(growable: false);
  final robustScale = _median(deviations) * 1.4826;
  final byScale = median + 6 * math.max(robustScale, median * 0.05);
  final byRatio = median * 3.0;
  return target > math.max(byScale, byRatio);
}

String _cycleEvidence({
  required double residualPaid,
  required double residualOperational,
  required double cancelledExplained,
  required double knownOperational,
  required bool purchaseMagnitudeOutlier,
  required double shortage,
  required String family,
}) {
  final unit = predictiveBaseUnitLabel(family);
  final parts = <String>[];
  if (purchaseMagnitudeOutlier) {
    parts.add(
      'Volumen de compra extremo frente al baseline; revisar captura, unidad '
      'o compra para varios dias antes de interpretar el residual',
    );
  }
  if (knownOperational > 0.01) {
    parts.add(
      'consumo operativo conocido incluido '
      '${knownOperational.toStringAsFixed(1)} $unit',
    );
  }
  if (residualPaid > 0) {
    parts.add(
      'Compra excede lo esperado por ventas en '
      '${residualPaid.toStringAsFixed(1)} $unit',
    );
  } else if (residualPaid < 0) {
    parts.add(
      'Compra queda por debajo del consumo modelado en '
      '${residualPaid.abs().toStringAsFixed(1)} $unit',
    );
  }
  if (cancelledExplained > 0.01) {
    parts.add(
      'cancelaciones que tocaron cocina explicarian '
      '${cancelledExplained.toStringAsFixed(1)} $unit',
    );
  }
  if ((residualPaid.abs() - residualOperational.abs()) > 0.01) {
    parts.add(
      'residual tras considerar cancelaciones '
      '${residualOperational.toStringAsFixed(1)} $unit',
    );
  }
  if (shortage > 0.01) {
    parts.add(
      'faltante de caja del ciclo \$${shortage.toStringAsFixed(2)}',
    );
  }
  return parts.isEmpty ? 'Sin discrepancia material' : parts.join(' · ');
}

double _robustScale(List<double> values) {
  if (values.isEmpty) return 0;
  final median = _median(values);
  final deviations = values.map((value) => (value - median).abs()).toList();
  final mad = _median(deviations);
  if (mad > 0.000001) return mad * 1.4826;
  final rms = math.sqrt(
    values.fold<double>(0, (sum, value) => sum + value * value) /
        values.length,
  );
  return rms;
}

double _median(List<double> source) {
  if (source.isEmpty) return 0;
  final values = [...source]..sort();
  final middle = values.length ~/ 2;
  if (values.length.isOdd) return values[middle];
  return (values[middle - 1] + values[middle]) / 2;
}

double _dot(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _shiftDate(String date, int days) =>
    _dateKey(DateTime.parse(date).add(Duration(days: days)));

int _daysInclusive(String start, String end) =>
    DateTime.parse(end).difference(DateTime.parse(start)).inDays + 1;

Iterable<String> _dateKeys(String start, String end) sync* {
  var cursor = DateTime.parse(start);
  final finish = DateTime.parse(end);
  while (!cursor.isAfter(finish)) {
    yield _dateKey(cursor);
    cursor = cursor.add(const Duration(days: 1));
  }
}
