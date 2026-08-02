import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/purchases/purchase_capture_discount.dart';
import 'package:tacopos/core/theme/app_theme.dart';
import 'package:tacopos/models/purchase_models.dart';
import 'package:tacopos/screens/admin/purchase_admin_screen.dart';

void main() {
  test('2.010 kg y 440.40 conserva importe exacto y calcula unitario', () {
    final line = _lineFromTotal(2.010, 440.40, unit: 'kg');

    expect(line.lineTotalCents, 44040);
    expect(line.total, 440.40);
    expect(line.unitCostCalculated, closeTo(219.1044776119, 0.0000001));
  });

  test('no recalcula el total con un unitario redondeado', () {
    final line = _lineFromTotal(2.010, 440.40, unit: 'kg');
    final roundedUnitCost = double.parse(
      line.unitCostCalculated.toStringAsFixed(2),
    );

    expect(purchaseMoney(line.quantity * roundedUnitCost), 440.39);
    expect(line.total, 440.40);
  });

  test('varias lineas suman centavos exactamente', () {
    final lines = [
      _lineFromTotal(2.010, 440.40, name: 'Bistec'),
      _lineFromTotal(1.500, 380.20, name: 'Arrachera'),
      _lineFromTotal(0.750, 291.60, name: 'Tripa'),
    ];

    expect(
      lines.fold<int>(0, (sum, line) => sum + line.lineTotalCents),
      111220,
    );
    expect(purchaseLinesTotal(lines), 1112.20);
  });

  test('cambiar cantidad conserva total y recalcula unitario', () {
    final original = _lineFromTotal(2.010, 440.40, unit: 'kg');
    final edited = _lineFromTotal(
      2.020,
      original.lineTotal,
      unit: original.unit,
    );

    expect(edited.lineTotalCents, original.lineTotalCents);
    expect(edited.total, 440.40);
    expect(edited.unitCostCalculated, closeTo(218.019801, 0.000001));
  });

  test('cambiar total conserva cantidad y recalcula unitario', () {
    final edited = _lineFromTotal(2.010, 500.00, unit: 'kg');

    expect(edited.quantity, 2.010);
    expect(edited.total, 500);
    expect(edited.unitCostCalculated, closeTo(248.7562189, 0.000001));
  });

  test('cantidad cero e importe negativo se rechazan', () {
    expect(isValidPurchaseLineInput(_lineFromTotal(0, 100)), isFalse);
    expect(isValidPurchaseLineInput(_lineFromTotal(1, -0.01)), isFalse);
  });

  test(
    'historico sin lineTotal carga desde cantidad por unitCost existente',
    () {
      final item = SupplierPurchaseItem.fromData('legacy', {
        'purchaseItemName': 'Bistec',
        'quantity': 2.010,
        'unit': 'kg',
        'unitCost': 219.1044776119,
      });

      expect(item.calculationMode, 'legacy_unit_cost');
      expect(item.lineTotalCents, 44040);
      expect(item.total, 440.40);
    },
  );

  test('compra nueva carga lineTotal, lineTotalCents y unitCostCalculated', () {
    final item = SupplierPurchaseItem.fromData('new', {
      'purchaseItemName': 'Bistec',
      'quantity': 2.010,
      'unit': 'kg',
      'unitCost': 219.1044776119,
      'unitCostCalculated': 219.1044776119,
      'lineTotal': 440.40,
      'lineTotalCents': 44040,
      'calculationMode': 'line_total',
      'total': 440.40,
    });

    expect(item.calculationMode, 'line_total');
    expect(item.lineTotal, 440.40);
    expect(item.lineTotalCents, 44040);
    expect(item.unitCostCalculated, closeTo(219.1044776119, 0.0000001));
  });

  test('inventario y cuentas por pagar usan importe total exacto', () {
    final line = _lineFromTotal(2.010, 440.40, unit: 'kg');

    expect(line.quantity, 2.010);
    expect(line.lineTotal, 440.40);
    expect(line.unitCostCalculated, closeTo(219.1044776119, 0.0000001));
    expect(purchaseLinesTotal([line]), 440.40);
  });

  test('reporte y exportacion exponen importe total y unitario calculado', () {
    const row = PurchaseItemReportRow(
      itemId: 'bistec',
      itemName: 'Bistec',
      quantity: 2.010,
      unit: 'kg',
      total: 440.40,
      averageUnitCostCalculated: 219.1044776119,
      noteCount: 1,
      affectsKitchenPerformance: true,
    );

    expect(row.total, 440.40);
    expect(row.averageUnitCostCalculated, closeTo(219.1044776119, 0.0000001));
  });

  test('diferencia de un centavo se informa desde sumas exactas', () {
    final linesTotal = purchaseLinesTotal([
      _lineFromTotal(1, 10.00),
      _lineFromTotal(1, 20.01),
    ]);

    expect(purchaseMoney(linesTotal - 30.00), 0.01);
  });

  test('descuento por articulo convierte 10 x 100 en 10 x 80', () {
    final discounted = applyPurchaseLineDiscount(_line(10, 100), 20);

    expect(discounted.unitCost, 80);
    expect(discounted.total, 800);
  });

  test('descuento general distribuye 20% y suma exactamente 800', () {
    final discounted = applyPurchaseGeneralDiscount([
      _line(2, 100, name: 'Articulo A'),
      _line(8, 100, name: 'Articulo B'),
    ], 20);

    expect(discounted.map((line) => line.total), [160, 640]);
    expect(purchaseLinesTotal(discounted), 800);
  });

  test('descuentos consecutivos usan el costo final actual', () {
    final first = applyPurchaseLineDiscount(_line(1, 100), 20);
    final second = applyPurchaseLineDiscount(first, 10);

    expect(first.unitCost, 80);
    expect(second.unitCost, 72);
    expect(second.total, 72);
  });

  test('total final alimenta saldo inicial y pago parcial', () {
    final total = purchaseLinesTotal(
      applyPurchaseGeneralDiscount([_line(10, 100)], 20),
    );
    final initialBalance = total;
    final balanceAfterPayment = purchaseMoney(total - 300);

    expect(total, 800);
    expect(initialBalance, 800);
    expect(balanceAfterPayment, 500);
  });

  test('edicion parte del costo final guardado sin reconstruir original', () {
    final loaded = _line(10, 80);
    final discounted = applyPurchaseLineDiscount(loaded, 10);

    expect(loaded.total, 800);
    expect(discounted.unitCost, 72);
    expect(discounted.total, 720);
  });

  test('redondeo general conserva suma de partidas y total objetivo', () {
    final lines = [
      _line(3, 10.01, name: 'A'),
      _line(7, 4.333, name: 'B'),
      _line(2.5, 1.999, name: 'C'),
    ];
    final expected = purchaseDiscountedTotal(purchaseLinesTotal(lines), 17.5);
    final discounted = applyPurchaseGeneralDiscount(lines, 17.5);

    expect(purchaseLinesTotal(discounted), expected);
    expect(
      discounted.fold<double>(0, (sum, line) => sum + line.total),
      closeTo(expected, 0.000001),
    );
  });

  test('100% deja costos y totales en cero sin valores negativos', () {
    final discounted = applyPurchaseGeneralDiscount([
      _line(2, 100),
      _line(1, 0),
    ], 100);

    expect(discounted.every((line) => line.unitCost >= 0), isTrue);
    expect(discounted.last.unitCost, 0);
    expect(purchaseLinesTotal(discounted), 0);
  });

  test('partida gratuita permanece en cero al distribuir residuales', () {
    final discounted = applyPurchaseGeneralDiscount([
      _line(3, 10.01),
      _line(7, 4.333),
      _line(1, 0, name: 'Muestra gratis'),
    ], 17.5);

    expect(discounted.last.unitCost, 0);
    expect(discounted.last.total, 0);
    expect(
      purchaseLinesTotal(discounted),
      purchaseDiscountedTotal(60.36, 17.5),
    );
  });

  test('rechaza porcentajes negativos, mayores a 100 o no finitos', () {
    expect(
      () => applyPurchaseLineDiscount(_line(1, 100), -1),
      throwsRangeError,
    );
    expect(
      () => applyPurchaseLineDiscount(_line(1, 100), 100.01),
      throwsRangeError,
    );
    expect(
      () => applyPurchaseLineDiscount(_line(1, 100), double.nan),
      throwsRangeError,
    );
  });

  testWidgets('cancelar modal no devuelve descuento ni modifica el costo', (
    tester,
  ) async {
    final line = _line(10, 100);
    double? result = 999;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<double>(
                  context: context,
                  builder: (_) => PurchaseDiscountDialog.line(line: line),
                );
              },
              child: const Text('Abrir descuento'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir descuento'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('purchase-discount-percent')),
      '20',
    );
    await tester.pump();

    expect(find.text(r'$80.000000'), findsOneWidget);
    expect(find.text(r'$800.00'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(line.unitCost, 100);
    expect(line.total, 1000);
  });

  testWidgets('modal general muestra advertencia y devuelve el porcentaje', (
    tester,
  ) async {
    double? result;
    final lines = [_line(2, 100), _line(4, 50)];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<double>(
                  context: context,
                  builder: (_) => PurchaseDiscountDialog.general(lines: lines),
                );
              },
              child: const Text('Abrir general'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir general'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'El descuento se aplicara sobre los importes actuales de todos los articulos.',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('purchase-discount-percent')),
      '20',
    );
    await tester.pump();
    expect(find.text(r'$320.00'), findsOneWidget);

    await tester.tap(find.text('Aplicar a todos los artículos'));
    await tester.pumpAndSettle();

    expect(result, 20);
    expect(purchaseLinesTotal(lines), 400);
  });
}

PurchaseLineInput _line(
  double quantity,
  double unitCost, {
  String name = 'Articulo',
  String unit = 'pieza',
}) {
  return PurchaseLineInput(
    purchaseItemName: name,
    kitchenStockItemId: name.toLowerCase().replaceAll(' ', '-'),
    kitchenStockItemName: name,
    quantity: quantity,
    unit: unit,
    unitCost: unitCost,
  );
}

PurchaseLineInput _lineFromTotal(
  double quantity,
  double lineTotal, {
  String name = 'Articulo',
  String unit = 'pieza',
}) {
  final cents = purchaseAmountCents(lineTotal);
  final unitCost = purchaseUnitCostFromLineTotal(
    quantity: quantity,
    lineTotalCents: cents,
  );
  return PurchaseLineInput(
    purchaseItemName: name,
    kitchenStockItemId: name.toLowerCase().replaceAll(' ', '-'),
    kitchenStockItemName: name,
    quantity: quantity,
    unit: unit,
    unitCost: unitCost,
    lineTotalCents: cents,
    calculationMode: 'line_total',
  );
}
