import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/canonical_sales_summary.dart';
import 'package:tacopos/core/reports/product_sales_cost_report.dart';
import 'package:tacopos/models/product.dart';

void main() {
  test('utilidad descuenta el costo de la venta neta, no de la bruta', () {
    final sales = _sales(qty: 25, gross: 625, discount: 87.50);
    final row = buildProductSalesCostRows(
      salesRows: [sales],
      products: [_product(cost: 10.20)],
    ).single;

    expect(row.sales, same(sales));
    expect(row.unitCost, 10.20);
    expect(row.totalCost, 255);
    expect(row.profit, 282.50);
    expect(row.sales.discountAllocated, 87.50);
    expect(row.sales.netSales, 537.50);
  });

  test('costo ausente, cero o articulo eliminado usa cero y conserva venta', () {
    final rows = buildProductSalesCostRows(
      salesRows: [
        _sales(id: 'sin-costo'),
        _sales(id: 'costo-cero'),
        _sales(id: 'eliminado'),
      ],
      products: [
        _product(id: 'sin-costo'),
        _product(id: 'costo-cero', cost: 0),
      ],
    );

    expect(rows, hasLength(3));
    for (final row in rows) {
      expect(row.unitCost, 0);
      expect(row.totalCost, 0);
      expect(row.profit, 50);
    }
  });

  test('mismo nombre en taco y gringa conserva el costo de cada ID', () {
    final rows = buildProductSalesCostRows(
      salesRows: [
        _sales(id: 'carnaza-taco', qty: 3, gross: 75),
        _sales(id: 'carnaza-gringa', category: 'Gringa Chica', gross: 120),
      ],
      products: [
        _product(id: 'carnaza-gringa', cost: 20),
        _product(id: 'carnaza-taco', cost: 8),
      ],
    );

    expect(rows.map((row) => row.unitCost), [8, 20]);
    expect(rows.map((row) => row.totalCost), [24, 40]);
    expect(rows.map((row) => row.profit), [51, 80]);
  });

  test('producto renombrado e inactivo sigue dando costo a su venta', () {
    final row = buildProductSalesCostRows(
      salesRows: [_sales()],
      products: [_product(name: 'Carnaza nueva', cost: 9, active: false)],
    ).single;

    expect(row.sales.productName, 'Carnaza');
    expect(row.totalCost, 18);
    expect(row.profit, 32);
  });

  test('un nombre coincidente sin el mismo ID no presta su costo', () {
    final row = buildProductSalesCostRows(
      salesRows: [_sales(id: 'historico')],
      products: [_product(id: 'nuevo', cost: 20)],
    ).single;

    expect(row.unitCost, 0);
    expect(row.profit, 50);
  });

  test('actualizar costo recalcula ventas anteriores sin alterar ingresos', () {
    final sales = [_sales()];
    final before = buildProductSalesCostRows(
      salesRows: sales,
      products: [_product(cost: 10)],
    ).single;
    final after = buildProductSalesCostRows(
      salesRows: sales,
      products: [_product(cost: 12)],
    ).single;

    expect(before.profit, 30);
    expect(after.profit, 26);
    expect(before.sales.netSales, after.sales.netSales);
  });

  test('comida gratis conserva costo completo y utilidad negativa', () {
    final row = buildProductSalesCostRows(
      salesRows: [_sales(qty: 4, gross: 100, discount: 100)],
      products: [_product(cost: 8)],
    ).single;

    expect(row.totalCost, 32);
    expect(row.profit, -32);
    expect(row.toReportCells(totalNetSales: 0).last, '\$-32.00');
    expect(row.toReportCells(totalNetSales: 0)[7], '0.0%');
  });

  test('venta por debajo de costo conserva la perdida', () {
    final row = buildProductSalesCostRows(
      salesRows: [_sales(gross: 50, discount: 40)],
      products: [_product(cost: 10)],
    ).single;

    expect(row.totalCost, 20);
    expect(row.profit, -10);
  });

  test('cantidades y costos con centavos producen importes monetarios', () {
    final row = buildProductSalesCostRows(
      salesRows: [_sales(qty: 3, gross: 75)],
      products: [_product(cost: 19.80)],
    ).single;

    expect(row.totalCost, 59.40);
    expect(row.profit, 15.60);
  });

  test('costos legacy negativos y no finitos no inflan la utilidad', () {
    for (final cost in [-1.0, double.nan, double.infinity]) {
      final row = buildProductSalesCostRows(
        salesRows: [_sales()],
        products: [_product(cost: cost)],
      ).single;

      expect(row.unitCost, 0);
      expect(row.profit, 50);
    }
  });

  test('pantalla y CSV conservan columnas y terminan con costos y utilidad', () {
    final row = buildProductSalesCostRows(
      salesRows: [_sales(qty: 25, gross: 625, discount: 87.50)],
      products: [_product(cost: 10.20)],
    ).single;
    final cells = row.toReportCells(totalNetSales: 1000);

    expect(cells, hasLength(productSalesCostReportHeaders.length));
    expect(productSalesCostReportHeaders.sublist(8), [
      'Costo unitario',
      'Costo total vendido',
      'Utilidad',
    ]);
    expect(cells, [
      'Carnaza',
      'Taco',
      '25 vendidos',
      '\$625.00',
      '\$87.50',
      '\$537.50',
      '\$21.50',
      '53.8%',
      '\$10.20',
      '\$255.00',
      '\$282.50',
    ]);
  });
}

CanonicalProductSalesRow _sales({
  String id = 'carnaza',
  String category = 'Taco',
  int qty = 2,
  double gross = 50,
  double discount = 0,
}) {
  return CanonicalProductSalesRow(
    productId: id,
    productName: 'Carnaza',
    categoryName: category,
    qty: qty,
    grossSales: gross,
    discountAllocated: discount,
    netSales: gross - discount,
  );
}

Product _product({
  String id = 'carnaza',
  String name = 'Carnaza',
  double? cost,
  bool active = true,
}) {
  return Product(
    id: id,
    name: name,
    categoryId: 'taco',
    categoryName: 'Taco',
    category: 'Taco',
    price: 25,
    unitCost: cost,
    active: active,
    sendToKitchen: true,
    sortOrder: 0,
    platformPrices: const {},
    affectsKitchenStock: false,
  );
}
