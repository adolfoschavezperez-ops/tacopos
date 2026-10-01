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

      final withoutCash = buildPredictiveConsumptionAudit(
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
      final physicalCycle = withoutCash.models.single.cycles.firstWhere(
        (row) => row.purchaseDate == cycle.purchaseDate,
      );
      expect(cycle.residualOperationalBase,
          closeTo(physicalCycle.residualOperationalBase, 0.000001));
      expect(cycle.anomalyScore,
          closeTo(physicalCycle.anomalyScore, 0.000001));
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
      expect(
        detectPredictiveIngredient(
          itemName: 'Bisteck laminado',
          supplierName: 'Omar',
        )?.key,
        'bistec_laminado',
      );
    });

    test('never trains on a cycle after investigation begins', () {
      final purchases = <PredictivePurchaseLine>[];
      final sales = <PredictiveSaleLine>[];
      for (var i = 0; i < 9; i++) {
        final date = DateTime(2026, 9, 24 + i);
        final key = _dateKey(date);
        purchases.add(PredictivePurchaseLine(
          purchaseId: 'p-$i',
          purchaseDate: date,
          businessDate: key,
          supplierName: 'Omar',
          itemName: 'Bistec',
          quantity: i >= 4 ? 10 : 1,
          unit: 'kg',
        ));
        sales.add(PredictiveSaleLine(
          businessDate: key,
          productId: 'bistec',
          productName: 'Taco Bistec',
          categoryName: 'Tacos',
          quantity: 20 + i,
          kind: PredictiveSaleKind.paidSale,
          ingredientNames: const ['Bistec'],
        ));
      }
      final audit = buildPredictiveConsumptionAudit(
        purchaseLines: purchases,
        saleLines: sales,
        cashDays: const [],
        yieldInputs: const [],
        historyStart: '2026-09-24',
        historyEnd: '2026-10-02',
        investigationStart: '2026-09-28',
      );
      expect(audit.models, hasLength(1));
      expect(audit.models.single.trainingCycleCount, 4);
      expect(audit.models.single.confidence, 'No identificable');
      expect(
        audit.models.single.investigationCycles.every(
          (cycle) => cycle.anomalyScore == 0,
        ),
        isTrue,
      );
    });

    test('perfectly correlated product and day cannot earn an alert', () {
      final purchases = <PredictivePurchaseLine>[];
      final sales = <PredictiveSaleLine>[];
      for (var i = 0; i < 10; i++) {
        final date = DateTime(2026, 9, 20 + i);
        final key = _dateKey(date);
        purchases.add(PredictivePurchaseLine(
          purchaseId: 'p-$i',
          purchaseDate: date,
          businessDate: key,
          supplierName: 'Omar',
          itemName: 'Bistec',
          quantity: i == 8 ? 10 : 1,
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
        historyStart: '2026-09-20',
        historyEnd: '2026-09-29',
        investigationStart: '2026-09-28',
      );
      final model = audit.models.single;
      expect(model.confidence, 'No identificable');
      expect(model.investigationCycles.every((cycle) => cycle.anomalyScore == 0),
          isTrue);
    });

    test('physically absurd grams per taco are not scored', () {
      final purchases = <PredictivePurchaseLine>[];
      final sales = <PredictiveSaleLine>[];
      const quantities = [20, 24, 18, 22, 26, 16, 28, 14, 20, 24];
      for (var i = 0; i < quantities.length; i++) {
        final date = DateTime(2026, 9, 20 + i);
        final key = _dateKey(date);
        purchases.add(PredictivePurchaseLine(
          purchaseId: 'p-$i',
          purchaseDate: date,
          businessDate: key,
          supplierName: 'Omar',
          itemName: 'Bistec',
          quantity: i == 8 ? 10 : quantities[i] * 0.30,
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
        yieldInputs: const [
          PredictiveYieldInput(
            stockItemId: '',
            stockItemName: 'Bistec',
            yieldRate: 0.69,
          ),
        ],
        historyStart: '2026-09-20',
        historyEnd: '2026-09-29',
        investigationStart: '2026-09-28',
      );
      final model = audit.models.single;
      expect(model.coefficients.single.rawBasePerUnit, greaterThan(250));
      expect(model.confidence, 'No identificable');
      expect(model.investigationCycles.every((cycle) => cycle.anomalyScore == 0),
          isTrue);
    });

    test('separates taco and gringa coefficients for the same meat', () {
      const tacos = [20, 15, 27, 18, 31, 13, 26, 16, 22, 29];
      const gringas = [5, 12, 4, 10, 7, 15, 3, 13, 8, 6];
      final purchases = <PredictivePurchaseLine>[];
      final sales = <PredictiveSaleLine>[];
      for (var i = 0; i < tacos.length; i++) {
        final date = DateTime(2026, 9, 20 + i);
        final key = _dateKey(date);
        purchases.add(PredictivePurchaseLine(
          purchaseId: 'p-$i',
          purchaseDate: date,
          businessDate: key,
          supplierName: 'Omar',
          itemName: 'Bistec',
          quantity: tacos[i] * 0.05 + gringas[i] * 0.09,
          unit: 'kg',
        ));
        sales.addAll([
          PredictiveSaleLine(
            businessDate: key,
            productId: 'taco',
            productName: 'Taco Bistec',
            categoryName: 'Tacos',
            quantity: tacos[i],
            kind: PredictiveSaleKind.paidSale,
            ingredientNames: const ['Bistec'],
          ),
          PredictiveSaleLine(
            businessDate: key,
            productId: 'gringa',
            productName: 'Gringa Bistec',
            categoryName: 'Gringas',
            quantity: gringas[i],
            kind: PredictiveSaleKind.paidSale,
            ingredientNames: const ['Bistec'],
          ),
        ]);
      }
      final model = buildPredictiveConsumptionAudit(
        purchaseLines: purchases,
        saleLines: sales,
        cashDays: const [],
        yieldInputs: const [],
        historyStart: '2026-09-20',
        historyEnd: '2026-09-29',
        investigationStart: '2026-09-28',
      ).models.single;
      final byKey = {for (final row in model.coefficients) row.productKey: row};
      expect(byKey['taco']!.rawBasePerUnit, inInclusiveRange(35, 65));
      expect(byKey['gringa']!.rawBasePerUnit, inInclusiveRange(70, 110));
      expect(model.confidence, isNot('No identificable'));
    });

    test('combines purchases on the same day without duplicating sales', () {
      final purchases = <PredictivePurchaseLine>[];
      final sales = <PredictiveSaleLine>[];
      for (var i = 0; i < 10; i++) {
        final date = DateTime(2026, 9, 20 + i);
        final key = _dateKey(date);
        final qty = 15 + (i * 7) % 16;
        for (var part = 0; part < 2; part++) {
          purchases.add(PredictivePurchaseLine(
            purchaseId: 'p-$i-$part',
            purchaseDate: date,
            businessDate: key,
            supplierName: 'Omar',
            itemName: 'Bistec',
            quantity: qty * 0.025,
            unit: 'kg',
          ));
        }
        sales.add(PredictiveSaleLine(
          businessDate: key,
          productId: 'taco',
          productName: 'Taco Bistec',
          categoryName: 'Tacos',
          quantity: qty,
          kind: PredictiveSaleKind.paidSale,
          ingredientNames: const ['Bistec'],
        ));
      }
      final model = buildPredictiveConsumptionAudit(
        purchaseLines: purchases,
        saleLines: sales,
        cashDays: const [],
        yieldInputs: const [],
        historyStart: '2026-09-20',
        historyEnd: '2026-09-29',
        investigationStart: '2026-09-28',
      ).models.single;
      expect(model.purchaseLineCount, 20);
      expect(model.purchaseDayCount, 10);
      expect(model.coefficients.single.rawBasePerUnit, inInclusiveRange(40, 60));
    });

    test('keeps corn taco and flour gringa purchases separate', () {
      final purchases = <PredictivePurchaseLine>[];
      final sales = <PredictiveSaleLine>[];
      for (var i = 0; i < 10; i++) {
        final date = DateTime(2026, 9, 20 + i);
        final key = _dateKey(date);
        final tacoQty = 20 + (i * 7) % 13;
        final gringaQty = 5 + (i * 3) % 9;
        purchases.addAll([
          PredictivePurchaseLine(
            purchaseId: 'corn-$i',
            purchaseDate: date,
            businessDate: key,
            supplierName: 'Noé Tortillas',
            itemName: 'Tortilla de maíz',
            quantity: tacoQty * 0.025,
            unit: 'kg',
          ),
          PredictivePurchaseLine(
            purchaseId: 'flour-$i',
            purchaseDate: date,
            businessDate: key,
            supplierName: 'Noe',
            itemName: 'Tortilla de harina',
            quantity: gringaQty * 0.05,
            unit: 'kg',
          ),
        ]);
        sales.addAll([
          PredictiveSaleLine(
            businessDate: key,
            productId: 'taco',
            productName: 'Taco Bistec',
            categoryName: 'Tacos',
            quantity: tacoQty,
            kind: PredictiveSaleKind.paidSale,
            ingredientNames: const ['Tortilla de maíz'],
          ),
          PredictiveSaleLine(
            businessDate: key,
            productId: 'gringa',
            productName: 'Gringa Bistec',
            categoryName: 'Gringas',
            quantity: gringaQty,
            kind: PredictiveSaleKind.paidSale,
            ingredientNames: const ['Tortilla de harina'],
          ),
        ]);
      }
      final models = buildPredictiveConsumptionAudit(
        purchaseLines: purchases,
        saleLines: sales,
        cashDays: const [],
        yieldInputs: const [],
        historyStart: '2026-09-20',
        historyEnd: '2026-09-29',
        investigationStart: '2026-09-28',
      ).models;
      expect(models, hasLength(2));
      final byKey = {for (final model in models) model.definition.key: model};
      expect(byKey['tortilla_maiz']!.coefficients.single.productKey, 'taco');
      expect(byKey['tortilla_harina']!.coefficients.single.productKey, 'gringa');
      expect(byKey['tortilla_maiz']!.baseUnitLabel, 'g');
    });
  });
}

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
