import '../../models/product.dart';
import 'canonical_sales_summary.dart';

const productSalesCostReportHeaders = [
  'Producto',
  'Categoria',
  'Cantidad',
  'Venta bruta',
  'Descuento asignado',
  'Venta neta',
  'Precio promedio neto',
  'Participacion %',
  'Costo unitario',
  'Costo total vendido',
  'Utilidad',
];

class ProductSalesCostRow {
  const ProductSalesCostRow({required this.sales, required this.unitCost});

  final CanonicalProductSalesRow sales;
  final double unitCost;

  double get totalCost => _roundMoney(sales.qty * unitCost);
  double get profit => _roundMoney(sales.netSales - totalCost);

  List<String> toReportCells({required double totalNetSales}) {
    final percent = totalNetSales <= 0
        ? 0.0
        : (sales.netSales / totalNetSales) * 100;
    return [
      sales.productName,
      sales.categoryName,
      '${sales.qty} vendidos',
      _money(sales.grossSales),
      _money(sales.discountAllocated),
      _money(sales.netSales),
      _money(sales.averageNetPrice),
      '${percent.toStringAsFixed(1)}%',
      _money(unitCost),
      _money(totalCost),
      _money(profit),
    ];
  }
}

/// Uses the current catalog cost, including inactive products. Missing costs
/// are zero; names are never used to match historical sales to the catalog.
List<ProductSalesCostRow> buildProductSalesCostRows({
  required Iterable<CanonicalProductSalesRow> salesRows,
  required Iterable<Product> products,
}) {
  final costsById = <String, double>{};
  for (final product in products) {
    final cost = product.unitCost;
    costsById[product.id] = cost != null && cost.isFinite && cost >= 0
        ? cost
        : 0;
  }
  return salesRows
      .map(
        (sales) => ProductSalesCostRow(
          sales: sales,
          unitCost: costsById[sales.productId] ?? 0,
        ),
      )
      .toList(growable: false);
}

List<List<String>> buildProductSalesCostReportCells({
  required Iterable<ProductSalesCostRow> rows,
  required double totalNetSales,
}) {
  final products = rows.toList(growable: false);
  if (products.isEmpty) return const [];
  return [
    ...products.map((row) => row.toReportCells(totalNetSales: totalNetSales)),
    buildProductSalesCostTotalsCells(products),
  ];
}

/// Adds the amounts displayed on each product row, using integer cents.
/// Unit prices and averages are not additive and remain blank in the footer.
List<String> buildProductSalesCostTotalsCells(
  Iterable<ProductSalesCostRow> rows,
) {
  var qty = 0;
  var grossCents = 0;
  var discountCents = 0;
  var netCents = 0;
  var costCents = 0;
  var profitCents = 0;
  for (final row in rows) {
    qty += row.sales.qty;
    grossCents += (row.sales.grossSales * 100).round();
    discountCents += (row.sales.discountAllocated * 100).round();
    netCents += (row.sales.netSales * 100).round();
    costCents += (row.totalCost * 100).round();
    profitCents += (row.profit * 100).round();
  }
  return [
    'TOTAL',
    '',
    '$qty vendidos',
    _money(grossCents / 100),
    _money(discountCents / 100),
    _money(netCents / 100),
    '',
    '',
    '',
    _money(costCents / 100),
    _money(profitCents / 100),
  ];
}

double _roundMoney(double value) => (value * 100).roundToDouble() / 100;

String _money(double value) => '\$${value.toStringAsFixed(2)}';
