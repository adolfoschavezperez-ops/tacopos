import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/predictive_consumption_audit.dart';

void main() {
  group('predictive consumption audit', () {
    test('learns empirical meat consumption from historical replenishment cycles', () {
      final quantities = <int>[20, 24, 18, 22, 26, 16, 28, 20, 20, 14];
      final purchases = <PredictivePurchaseLine>[];
      final sales = <PredictiveSaleLine>[];

      for (var i = 0; i < quantities.length; i++) {
        final date = DateTime(2026, 9, 20 + i);
        final businessDate = _dateKey(date);
        final qty = quantities[i];
        purchases.add(
          PredictivePurchaseLine(
            purchaseId: 'p-$i',
            purchaseDate: date,
            businessDate: businessDate,
            supplierName: 'Carne Omar',
            itemName: 'Bistec',
            stockItemId: 'bistec',
            stockItemName: 'Bistec',
            quantity: i == 8 ? 1.6 : qty * 0.05,
            unit: 'kg',
          ),
        );
        sales.add(
          PredictiveSaleLine(
            businessDate: businessDate,
            productId: 'taco-bistec',
            productName: 'Taco Bistec',
            categoryName: 'Tacos',
            quantity: qty,
            kind: PredictiveSaleKind.paidSale,
            ingredientNames: const ['Bistec'],
          ),
        );
      }

      final audit = buildPredictiveConsumptionAudit(
        purchaseLines: purchases,
        saleLines: sales,
        cashDays: const [],
        yieldInputs: const [
          PredictiveYieldInput(
            stockItemId: 'bistec',
            stockItemName: 'Bistec',
            yieldRate: 0.69,
          ),
        ],
        historyStart: '2026-09-20',
        historyEnd: '2026-09-29',
        investigationStart: '2026-09-28',
      );

      expect(audit.models, hasLength(1));
      final model = audit.models.single;
      expect(model.definition.key, 'bistec');
      expect(model.trainingCycleCount, greaterThanOrEqualTo(5));
      expect(model.coefficients, isNotEmpty);

      final taco = model.coefficients.firstWhere(
        (row) => row.productName == 'Taco Bistec',
      );
      expect(taco.rawBasePerUnit, inInclusiveRange(40, 60));
      expect(taco.cookedBasePerUnit, inInclusiveRange(27, 42));

      expect(model.alignment, PredictiveAlignment.forwardSupply);
      final investigation = model.cycles.firstWhere(
        (cycle) => cycle.purchaseDate == '2026-09-28',
      );
      expect(investigation.isInvestigationPeriod, isTrue);
      expect(investigation.purchasedBase, closeTo(1600, 0.1));
      expect(investigation.residualOperationalBase, greaterThan(300));
      expect(investigation.expectedHighBase, lessThan(1600));
      expect(investigation.anomalyScore, greaterThanOrEqualTo(45));
    });

    test('separates kitchen cancellations from registered paid sales', () {
      final purchases = <PredictivePurchaseLine>[];
      final sales = <PredictiveSaleLine>[];

      final quantities = <int>[20, 24, 18, 22, 26, 16, 28, 20, 20, 24];
      for (var i = 0; i < quantities.length; i++) {
        final date = DateTime(2026, 9, 20 + i);
        final businessDate = _dateKey(date);
        final qty = quantities[i];
        purchases.add(
          PredictivePurchaseLine(
            purchaseId: 'p-$i',
            purchaseDate: date,
            businessDate: businessDate,
            supplierName: 'Omar',
            itemName: 'Bistec',
            stockItemId: 'bistec',
            stockItemName: 'Bistec',
            quantity: i == 8 ? 1.4 : qty * 0.05,
            unit: 'kg',
          ),
        );
        sales.add(
          PredictiveSaleLine(
            businessDate: businessDate,
            productId: 'taco-bistec',
            productName: 'Taco Bistec',
            categoryName: 'Tacos',
            quantity: qty,
            kind: PredictiveSaleKind.paidSale,
            ingredientNames: const ['Bistec'],
          ),
        );
      }
      sales.add(
        const PredictiveSaleLine(
          businessDate: '2026-09-28',
          productId: 'taco-bistec',
          productName: 'Taco Bistec',
          categoryName: 'Tacos',
          quantity: 4,
          kind: PredictiveSaleKind.cancelledKitchen,
          ingredientNames: ['Bistec'],
          orderId: 'cancelled-order',
          cancelledByEmployeeName: 'Andres',
        ),
      );

      final audit = buildPredictiveConsumptionAudit(
        purchaseLines: purchases,
        saleLines: sales,
        cashDays: const [
          PredictiveCashDay(
            businessDate: '2026-09-28',
            shortageAmount: 304.90,
            netDifference: -304.90,
          ),
        ],
        yieldInputs: const [
          PredictiveYieldInput(
            stockItemId: 'bistec',
            stockItemName: 'Bistec',
            yieldRate: 0.69,
          ),
        ],
        historyStart: '2026-09-20',
        historyEnd: '2026-09-29',
        investigationStart: '2026-09-28',
      );

      final model = audit.models.single;
      final cycle = model.cycles.firstWhere(
        (row) =>
            row.startBusinessDate.compareTo('2026-09-28') <= 0 &&
            row.endBusinessDate.compareTo('2026-09-28') >= 0 &&
            row.cancelledKitchenUnits > 0,
      );

      expect(cycle.isInvestigationPeriod, isTrue);
      expect(cycle.cancelledKitchenUnits, 4);
      expect(cycle.cancelledKitchenExplainedBase, greaterThan(100));
      expect(cycle.predictedOperationalBase, greaterThan(cycle.predictedPaidBase));
      expect(
        cycle.residualOperationalBase.abs(),
        lessThan(cycle.residualPaidBase.abs()),
      );
      expect(cycle.shortageAmount, closeTo(304.90, 0.001));
      expect(cycle.evidence, contains('cancelaciones'));
      expect(cycle.evidence, contains('faltante de caja'));
    });

    test('does not score an open last forward-supply batch', () {
      final purchases = <PredictivePurchaseLine>[];
      final sales = <PredictiveSaleLine>[];
      for (var i = 0; i < 8; i++) {
        final date = DateTime(2026, 9, 20 + i);
        final key = _dateKey(date);
        final qty = 15 + i;
        purchases.add(
          PredictivePurchaseLine(
            purchaseId: 'p-$i',
            purchaseDate: date,
            businessDate: key,
            supplierName: 'Carne Omar',
            itemName: 'Bistec',
            stockItemId: 'bistec',
            stockItemName: 'Bistec',
            quantity: qty * 0.05,
            unit: 'kg',
          ),
        );
        sales.add(
          PredictiveSaleLine(
            businessDate: key,
            productId: 'taco-bistec',
            productName: 'Taco Bistec',
            categoryName: 'Tacos',
            quantity: qty,
            kind: PredictiveSaleKind.paidSale,
            ingredientNames: const ['Bistec'],
          ),
        );
      }

      final audit = buildPredictiveConsumptionAudit(
        purchaseLines: purchases,
        saleLines: sales,
        cashDays: const [],
        yieldInputs: const [],
        historyStart: '2026-09-20',
        historyEnd: '2026-09-30',
        investigationStart: '2026-09-28',
      );

      final model = audit.models.single;
      if (model.alignment == PredictiveAlignment.forwardSupply) {
        expect(
          model.cycles.any((cycle) => cycle.purchaseDate == '2026-09-27'),
          isFalse,
        );
      }
    });

    test('never uses investigation-period cycles to manufacture a baseline', () {
      final purchases = <PredictivePurchaseLine>[];
      final sales = <PredictiveSaleLine>[];
      final dates = <DateTime>[
        DateTime(2026, 8, 30),
        DateTime(2026, 8, 31),
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 2),
        DateTime(2026, 9, 3),
        DateTime(2026, 9, 4),
      ];
      for (var i = 0; i < dates.length; i++) {
        final key = _dateKey(dates[i]);
        purchases.add(PredictivePurchaseLine(
          purchaseId: 'strict-$i',
          purchaseDate: dates[i],
          businessDate: key,
          supplierName: 'Omar',
          itemName: 'Bistec',
          stockItemId: 'bistec',
          stockItemName: 'Bistec',
          quantity: 1,
          unit: 'kg',
        ));
        sales.add(PredictiveSaleLine(
          businessDate: key,
          productId: 'taco-bistec',
          productName: 'Taco Bistec',
          categoryName: 'Tacos',
          quantity: 20,
          kind: PredictiveSaleKind.paidSale,
          ingredientNames: const ['Bistec'],
        ));
      }

      final audit = buildPredictiveConsumptionAudit(
        purchaseLines: purchases,
        saleLines: sales,
        cashDays: const [],
        yieldInputs: const [],
        historyStart: '2026-08-30',
        historyEnd: '2026-09-04',
        investigationStart: '2026-09-01',
      );

      expect(audit.models, isEmpty,
          reason: 'Two pre-investigation purchase days are not enough; '
              'September must not be reused to train normality.');
    });

    test('tortilla known consumption counts open days and excludes Sunday', () {
      final purchases = <PredictivePurchaseLine>[];
      final sales = <PredictiveSaleLine>[];
      for (var day = 24; day <= 31; day++) {
        final date = DateTime(2026, 8, day);
        final key = _dateKey(date);
        purchases.add(PredictivePurchaseLine(
          purchaseId: 'tortilla-$day',
          purchaseDate: date,
          businessDate: key,
          supplierName: 'NOE tortillas',
          itemName: 'Tortilla de maiz',
          stockItemId: 'tortilla-maiz',
          stockItemName: 'Tortilla de maiz',
          quantity: 2,
          unit: 'kg',
        ));
        if (date.weekday != DateTime.sunday) {
          sales.add(PredictiveSaleLine(
            businessDate: key,
            productId: 'taco-bistec',
            productName: 'Taco Bistec',
            categoryName: 'Tacos',
            quantity: 20,
            kind: PredictiveSaleKind.paidSale,
            ingredientNames: const ['Tortilla de maiz'],
          ));
        }
      }
      purchases.add(PredictivePurchaseLine(
        purchaseId: 'tortilla-sep1',
        purchaseDate: DateTime(2026, 9, 1),
        businessDate: '2026-09-01',
        supplierName: 'NOE tortillas',
        itemName: 'Tortilla de maiz',
        stockItemId: 'tortilla-maiz',
        stockItemName: 'Tortilla de maiz',
        quantity: 2,
        unit: 'kg',
      ));
      sales.add(const PredictiveSaleLine(
        businessDate: '2026-09-01',
        productId: 'taco-bistec',
        productName: 'Taco Bistec',
        categoryName: 'Tacos',
        quantity: 20,
        kind: PredictiveSaleKind.paidSale,
        ingredientNames: ['Tortilla de maiz'],
      ));

      final audit = buildPredictiveConsumptionAudit(
        purchaseLines: purchases,
        saleLines: sales,
        cashDays: const [],
        yieldInputs: const [],
        historyStart: '2026-08-24',
        historyEnd: '2026-09-01',
        investigationStart: '2026-09-01',
      );

      expect(audit.models, hasLength(1));
      final model = audit.models.single;
      final sunday = model.cycles.firstWhere(
        (cycle) =>
            cycle.startBusinessDate == '2026-08-30' &&
            cycle.endBusinessDate == '2026-08-30',
      );
      final monday = model.cycles.firstWhere(
        (cycle) =>
            cycle.startBusinessDate == '2026-08-31' &&
            cycle.endBusinessDate == '2026-08-31',
      );
      expect(sunday.operatingDays, 0);
      expect(sunday.knownOperationalBase, 0);
      expect(monday.operatingDays, 1);
      expect(monday.knownOperationalBase, closeTo(1000, 0.001));
    });

    test('low-confidence models cannot create strong audit findings', () {
      final purchases = <PredictivePurchaseLine>[];
      final sales = <PredictiveSaleLine>[];
      final quantities = <int>[18, 20, 22, 50, 50];
      for (var i = 0; i < quantities.length; i++) {
        final date = DateTime(2026, 8, 24 + i);
        final key = _dateKey(date);
        purchases.add(PredictivePurchaseLine(
          purchaseId: 'low-$i',
          purchaseDate: date,
          businessDate: key,
          supplierName: 'Omar',
          itemName: 'Bistec',
          stockItemId: 'bistec',
          stockItemName: 'Bistec',
          quantity: i >= 3 ? 2.5 : quantities[i] * 0.05,
          unit: 'kg',
        ));
        sales.add(PredictiveSaleLine(
          businessDate: key,
          productId: 'taco-bistec',
          productName: 'Taco Bistec',
          categoryName: 'Tacos',
          quantity: quantities[i],
          kind: PredictiveSaleKind.paidSale,
          ingredientNames: const ['Bistec'],
        ));
      }

      final audit = buildPredictiveConsumptionAudit(
        purchaseLines: purchases,
        saleLines: sales,
        cashDays: const [],
        yieldInputs: const [],
        historyStart: '2026-08-24',
        historyEnd: '2026-08-28',
        investigationStart: '2026-08-27',
      );

      expect(audit.models, hasLength(1));
      final model = audit.models.single;
      expect(model.confidence, 'Baja');
      expect(model.investigationCycles, isNotEmpty);
      expect(
        model.investigationCycles.map((cycle) => cycle.anomalyScore).reduce(
              (a, b) => a > b ? a : b,
            ),
        lessThan(35),
      );
      expect(audit.highAnomalyCycles, 0);
      expect(audit.recentPositiveResidualAuditableWeightGrams, 0);
    });

    test('extreme bulk purchase is separated from auditable residual', () {
      final purchases = <PredictivePurchaseLine>[];
      final sales = <PredictiveSaleLine>[];
      final quantities = <int>[16, 20, 18, 24, 22, 26, 19, 23, 21, 25, 20, 20];
      for (var i = 0; i < quantities.length; i++) {
        final date = i < 10
            ? DateTime(2026, 8, 15 + i)
            : DateTime(2026, 9, 1 + (i - 10));
        final key = _dateKey(date);
        purchases.add(PredictivePurchaseLine(
          purchaseId: 'bulk-$i',
          purchaseDate: date,
          businessDate: key,
          supplierName: 'Omar',
          itemName: 'Bistec',
          stockItemId: 'bistec',
          stockItemName: 'Bistec',
          quantity: i >= 10 ? 75 : quantities[i] * 0.05,
          unit: 'kg',
        ));
        sales.add(PredictiveSaleLine(
          businessDate: key,
          productId: 'taco-bistec',
          productName: 'Taco Bistec',
          categoryName: 'Tacos',
          quantity: quantities[i],
          kind: PredictiveSaleKind.paidSale,
          ingredientNames: const ['Bistec'],
        ));
      }

      final audit = buildPredictiveConsumptionAudit(
        purchaseLines: purchases,
        saleLines: sales,
        cashDays: const [],
        yieldInputs: const [],
        historyStart: '2026-08-15',
        historyEnd: '2026-09-02',
        investigationStart: '2026-09-01',
      );

      expect(audit.models, hasLength(1));
      final model = audit.models.single;
      final bulk = model.investigationCycles.firstWhere(
        (cycle) => cycle.purchasedBase > 70000,
      );
      expect(bulk.purchaseMagnitudeOutlier, isTrue);
      expect(bulk.anomalyScore, lessThan(35));
      expect(audit.recentPurchaseMagnitudeOutliers, greaterThanOrEqualTo(1));
      expect(
        audit.recentPositiveResidualBulkOutlierWeightGrams,
        greaterThan(50000),
      );
    });

    test('recognizes tortilla and target suppliers', () {
      final tortilla = detectPredictiveIngredient(
        itemName: 'Tortilla de maíz',
        supplierName: 'Noe Tortillas',
      );
      final meat = detectPredictiveIngredient(
        itemName: 'Bisteck',
        supplierName: 'Carne Omar',
      );

      expect(tortilla?.key, 'tortilla_maiz');
      expect(meat?.key, 'bistec');
      expect(predictiveUnitFamily('kg'), 'weight');
      expect(predictiveBaseUnitLabel('weight'), 'g');
    });
  });
}

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
