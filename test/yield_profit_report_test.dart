import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/canonical_sales_summary.dart';
import 'package:tacopos/core/reports/report_data_bundle.dart';
import 'package:tacopos/core/reports/yield_profit_report.dart';
import 'package:tacopos/core/reports/yield_profit_report_excel.dart';
import 'package:tacopos/models/kitchen_stock_item.dart';
import 'package:tacopos/models/yield_profit_models.dart';

void main() {
  group('formulas de rendimiento', () {
    test('bistec taco convierte 30 g cocidos a crudo y costo final', () {
      final raw = rawEquivalent(
        quantity: 30,
        inputStage: 'cooked',
        cookingYieldRate: 0.69,
      );
      expect(raw, closeTo(43.47826087, 0.00000001));
      expect(raw * 120 / 1000, closeTo(5.217391, 0.000001));
      expect(
        theoreticalUnitsPerRawKg(
          cookingYieldRate: 0.69,
          cookedPortionGrams: 30,
        ),
        closeTo(23, 0.000001),
      );
    });

    test('gringa de 60 g rinde 11.50 unidades por kg', () {
      expect(
        rawEquivalent(
          quantity: 60,
          inputStage: 'cooked',
          cookingYieldRate: 0.69,
        ),
        closeTo(86.95652174, 0.00000001),
      );
      expect(
        theoreticalUnitsPerRawKg(
          cookingYieldRate: 0.69,
          cookedPortionGrams: 60,
        ),
        closeTo(11.5, 0.000001),
      );
    });

    test('consumo combinado de tacos y gringas da 6086.96 g crudos', () {
      final cooked = 100 * 30 + 20 * 60;
      expect(cooked, 4200);
      expect(cooked / 0.69, closeTo(6086.95652174, 0.000001));
    });

    test('utilidad bruta de 5000 menos 2000 tiene margen de 60%', () {
      const netSales = 5000.0;
      const cost = 2000.0;
      final profit = netSales - cost;
      expect(profit, 3000);
      expect(profit / netSales * 100, 60);
    });
  });

  group('costos de compra', () {
    test('calcula promedio ponderado usando unitCost final guardado', () {
      final cost = resolveIngredientCost(
        stockItemId: 'bistec',
        lines: [
          _purchase('bistec', DateTime(2026, 7, 2), 2, 'kg', 100),
          _purchase('bistec', DateTime(2026, 7, 3), 1, 'kg', 130),
        ],
        start: DateTime(2026, 7),
        endInclusive: DateTime(2026, 7, 31, 23, 59),
      );
      expect(cost, isNotNull);
      expect(cost!.costPerBaseUnit * 1000, closeTo(110, 0.000001));
      expect(cost.source, 'Promedio ponderado del periodo');
    });

    test(
      'usa ultimo costo valido anterior cuando no hay compra en periodo',
      () {
        final cost = resolveIngredientCost(
          stockItemId: 'bistec',
          lines: [
            _purchase('bistec', DateTime(2026, 6, 20), 1, 'kg', 115),
            _purchase('bistec', DateTime(2026, 6, 28), 1, 'kg', 120),
          ],
          start: DateTime(2026, 7),
          endInclusive: DateTime(2026, 7, 31, 23, 59),
        );
        expect(cost!.costPerBaseUnit * 1000, closeTo(120, 0.000001));
        expect(cost.source, 'Ultimo costo valido anterior');
      },
    );

    test('sin costo valido retorna null y no simula costo cero', () {
      final cost = resolveIngredientCost(
        stockItemId: 'bistec',
        lines: const [],
        start: DateTime(2026, 7),
        endInclusive: DateTime(2026, 7, 31),
      );
      expect(cost, isNull);
    });
  });

  group('reporte por producto', () {
    test('producto sin receta conserva venta y costo no disponible', () {
      final report = buildYieldProfitReport(
        sales: _sales([
          const CanonicalProductSalesRow(
            productId: 'taco',
            productName: 'Taco de bistec',
            categoryName: 'Tacos',
            qty: 10,
            grossSales: 300,
            discountAllocated: 20,
            netSales: 280,
          ),
        ]),
        recipes: const [],
        profiles: const [],
        stockItems: const [],
        purchaseLines: const [],
        start: DateTime(2026, 7),
        endInclusive: DateTime(2026, 7, 31),
      );
      expect(report.products.single.netSales, 280);
      expect(report.products.single.unitCost, isNull);
      expect(report.products.single.grossMarginPercent, isNull);
      expect(report.productsWithoutRecipe, 1);
    });

    test('ingrediente sin costo marca costo y margen incompletos', () {
      final report = _singleProductReport(purchaseLines: const []);
      expect(report.products.single.hasRecipe, isTrue);
      expect(report.products.single.unitCost, isNull);
      expect(report.products.single.grossMarginPercent, isNull);
      expect(report.products.single.missingCostIngredients, ['Bistec']);
      expect(report.ingredientsWithoutCost, 1);
    });

    test('calcula costo teorico, utilidad y consumo crudo', () {
      final report = _singleProductReport(
        purchaseLines: [
          _purchase('bistec', DateTime(2026, 7, 2), 1, 'kg', 120),
        ],
      );
      final product = report.products.single;
      expect(product.unitCost, closeTo(5.217391, 0.000001));
      expect(product.totalCost, closeTo(52.173913, 0.000001));
      expect(product.grossProfit, closeTo(227.826087, 0.000001));
      expect(
        report.ingredients.single.rawEstimatedQuantity,
        closeTo(434.782608, 0.000001),
      );
    });

    test('descuento canónico recibido no se duplica', () {
      final report = _singleProductReport(
        purchaseLines: [
          _purchase('bistec', DateTime(2026, 7, 2), 1, 'kg', 120),
        ],
      );
      expect(report.products.single.grossSales, 300);
      expect(report.products.single.discountAllocated, 20);
      expect(report.products.single.netSales, 280);
    });
  });

  group('carga inicial segura', () {
    test('detecta Bistec aunque tenga mayusculas', () {
      final plan = _plan([_stock('bistec', '  BISTEC  ')]);
      expect(plan.toCreate.single.cookingYieldPercent, 69);
    });

    test('detecta Higado con o sin acento', () {
      final accented = _plan([_stock('h1', 'Hígado')]);
      final plain = _plan([_stock('h2', 'Higado')]);
      expect(accented.toCreate.single.cookingYieldPercent, 70);
      expect(plain.toCreate.single.cookingYieldPercent, 70);
    });

    test('detecta Adobado como equivalente de Adobada', () {
      final plan = _plan([_stock('adobado', 'Adobado')]);
      expect(plan.toCreate.single.cookingYieldPercent, 60);
    });

    test('no duplica ni sobrescribe rendimiento manual', () {
      final existing = IngredientYieldProfile(
        id: 'bistec',
        restaurantId: 'r',
        stockItemId: 'bistec',
        stockItemName: 'Bistec',
        cookingYieldPercent: 73,
        cookingYieldRate: 0.73,
        estimatedReductionPercent: 27,
        isEstimated: false,
        needsInternalValidation: false,
        sourceLabel: 'Prueba interna',
        active: true,
      );
      final plan = _plan(
        [_stock('bistec', 'Bistec')],
        existingProfiles: [existing],
      );
      expect(plan.toCreate, isEmpty);
      expect(existing.cookingYieldPercent, 73);
    });

    test('ingrediente inexistente queda pendiente de vincular', () {
      final plan = _plan(const []);
      expect(plan.pendingNames, contains('Bistec'));
      expect(plan.pendingNames, hasLength(9));
    });

    test('segunda ejecucion produce el mismo estado sin nuevas altas', () {
      final first = _plan([_stock('bistec', 'Bistec')]);
      final second = _plan([
        _stock('bistec', 'Bistec'),
      ], existingProfiles: first.toCreate);
      expect(first.toCreate, hasLength(1));
      expect(second.toCreate, isEmpty);
      expect(second.linkedNames, first.linkedNames);
      expect(second.pendingNames, first.pendingNames);
    });
  });

  test('Excel contiene ocho hojas con filtros y encabezados congelados', () {
    final report = _singleProductReport(
      purchaseLines: [_purchase('bistec', DateTime(2026, 7, 2), 1, 'kg', 120)],
    );
    final reportData = ReportDataBundle(
      key: const ReportDataKey(
        restaurantId: 'r',
        branchId: 'aviacion',
        startBusinessDate: '2026-07-01',
        endBusinessDate: '2026-07-31',
        includeItems: true,
      ),
      orders: const [],
      payments: const [],
      paymentsByOrder: const {},
      itemsByOrder: const {},
      canonicalSummary: _sales(const []),
      firestoreQueries: 0,
      orderDocuments: 0,
      paymentDocuments: 0,
      itemDocuments: 0,
    );
    final bundle = YieldProfitReportBundle(
      key: const YieldProfitReportKey(
        restaurantId: 'r',
        branchId: 'aviacion',
        startBusinessDate: '2026-07-01',
        endBusinessDate: '2026-07-31',
      ),
      reportData: reportData,
      products: const [],
      categories: const [],
      recipes: const [],
      profiles: const [],
      stockItems: const [],
      purchaseLines: const [],
      report: report,
      firestoreQueries: 0,
      fromCache: false,
      loadMilliseconds: 1,
    );
    final bytes = buildYieldProfitWorkbook(
      bundle: bundle,
      restaurantName: 'Los Padrinos Tacos',
      branchName: 'Aviacion',
      generatedAt: DateTime(2026, 7, 31, 12),
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final worksheets = archive.files
        .where(
          (file) =>
              file.isFile &&
              RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(file.name),
        )
        .toList();
    expect(worksheets, hasLength(8));
    for (final sheet in worksheets) {
      final xml = utf8.decode(sheet.content as List<int>);
      expect(xml, contains('state="frozen"'));
      expect(xml, contains('<autoFilter'));
    }
  });
}

YieldPurchaseLine _purchase(
  String stockItemId,
  DateTime date,
  double quantity,
  String unit,
  double unitCost,
) {
  return YieldPurchaseLine(
    purchaseId: '${stockItemId}_${date.millisecondsSinceEpoch}',
    purchaseDate: date,
    supplierName: 'Proveedor',
    stockItemId: stockItemId,
    stockItemName: 'Bistec',
    quantity: quantity,
    unit: unit,
    unitCost: unitCost,
  );
}

KitchenStockItem _stock(String id, String name) {
  return KitchenStockItem(
    id: id,
    name: name,
    category: 'carne',
    unit: 'kg',
    active: true,
    sortOrder: 0,
    optimalConsumptionPerSaleQty: 0,
    optimalConsumptionUnit: 'g_per_item',
  );
}

InitialYieldSeedPlan _plan(
  List<KitchenStockItem> stockItems, {
  List<IngredientYieldProfile> existingProfiles = const [],
}) {
  return planInitialYieldSeed(
    restaurantId: 'r',
    stockItems: stockItems,
    existingProfiles: existingProfiles,
  );
}

CanonicalSalesSummary _sales(List<CanonicalProductSalesRow> rows) {
  return CanonicalSalesSummary(
    grossSales: rows.fold(0, (sum, row) => sum + row.grossSales),
    discountTotal: rows.fold(0, (sum, row) => sum + row.discountAllocated),
    netSales: rows.fold(0, (sum, row) => sum + row.netSales),
    cashCollected: 0,
    cardCollected: 0,
    platformCollected: 0,
    employeeConsumption: 0,
    otherCollected: 0,
    totalCollected: 0,
    reconciliationDifference: 0,
    paidOrdersCount: 1,
    takeoutOrdersCount: 0,
    dineInOrdersCount: 1,
    standingOrdersCount: 0,
    productRows: rows,
    orderRows: const [],
    integrityIssues: const [],
  );
}

YieldProfitReport _singleProductReport({
  required List<YieldPurchaseLine> purchaseLines,
}) {
  return buildYieldProfitReport(
    sales: _sales([
      const CanonicalProductSalesRow(
        productId: 'taco',
        productName: 'Taco de bistec',
        categoryName: 'Tacos',
        qty: 10,
        grossSales: 300,
        discountAllocated: 20,
        netSales: 280,
      ),
    ]),
    recipes: const [
      TheoreticalProductRecipe(
        productId: 'taco',
        productName: 'Taco de bistec',
        ingredients: [
          TheoreticalRecipeIngredient(
            stockItemId: 'bistec',
            stockItemName: 'Bistec',
            quantity: 30,
            quantityType: 'portion',
            inputStage: 'cooked',
            unit: 'g',
            baseQuantity: 30,
          ),
        ],
      ),
    ],
    profiles: const [
      IngredientYieldProfile(
        id: 'bistec',
        restaurantId: 'r',
        stockItemId: 'bistec',
        stockItemName: 'Bistec',
        cookingYieldPercent: 69,
        cookingYieldRate: 0.69,
        estimatedReductionPercent: 31,
        isEstimated: true,
        needsInternalValidation: true,
        sourceLabel: initialYieldSourceLabel,
        active: true,
      ),
    ],
    stockItems: [_stock('bistec', 'Bistec')],
    purchaseLines: purchaseLines,
    start: DateTime(2026, 7),
    endInclusive: DateTime(2026, 7, 31, 23, 59),
  );
}
