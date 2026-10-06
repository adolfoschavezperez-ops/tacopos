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

double _roundMoney(double value) => (value * 100).roundToDouble() / 100;

String _money(double value) => '\$${value.toStringAsFixed(2)}';
