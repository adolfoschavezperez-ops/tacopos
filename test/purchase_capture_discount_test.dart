import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/purchases/purchase_capture_discount.dart';
import 'package:tacopos/core/theme/app_theme.dart';
import 'package:tacopos/models/purchase_models.dart';
import 'package:tacopos/screens/admin/purchase_admin_screen.dart';

void main() {
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

    expect(find.text(r'$80.00'), findsOneWidget);
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
        'El descuento se aplicará sobre los costos actuales de todos los artículos.',
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
}) {
  return PurchaseLineInput(
    purchaseItemName: name,
    kitchenStockItemId: name.toLowerCase().replaceAll(' ', '-'),
    kitchenStockItemName: name,
    quantity: quantity,
    unit: 'pieza',
    unitCost: unitCost,
  );
}
