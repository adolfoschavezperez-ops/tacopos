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
  });
}

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
