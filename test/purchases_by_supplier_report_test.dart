import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/purchases/purchases_by_supplier_report.dart';
import 'package:tacopos/models/purchase_models.dart';

void main() {
  group('compras por proveedor con rango', () {
    test('el rango inicia con el primer dia del mes actual', () {
      final range = defaultPurchasesBySupplierDateRange(
        DateTime(2026, 8, 6, 18, 30),
      );

      expect(range.startDate, DateTime(2026, 8));
    });

    test('el rango termina con la fecha actual', () {
      final range = defaultPurchasesBySupplierDateRange(
        DateTime(2026, 8, 6, 18, 30),
      );

      expect(range.endDate, DateTime(2026, 8, 6));
    });

    test('fecha inicial posterior a fecha final muestra error', () {
      final error = validatePurchasesBySupplierDateRange(
        PurchasesBySupplierDateRange(
          startDate: DateTime(2026, 8, 7),
          endDate: DateTime(2026, 8, 6),
        ),
      );

      expect(
        error,
        'La fecha inicial no puede ser posterior a la fecha final.',
      );
    });

    test('incluye compras de la fecha inicial', () {
      final range = _range();
      final purchase = _purchase(
        id: 'p1',
        supplierId: 'a',
        date: DateTime(2026, 8, 1),
        total: 100,
      );

      expect(supplierPurchaseMatchesDateRange(purchase, range), isTrue);
    });

    test('incluye compras de la fecha final por la noche', () {
      final range = _range();
      final purchase = _purchase(
        id: 'p1',
        supplierId: 'a',
        date: DateTime(2026, 8, 6, 23, 59, 59, 999),
        total: 100,
      );

      expect(supplierPurchaseMatchesDateRange(purchase, range), isTrue);
    });

    test('no incluye compras anteriores al rango', () {
      final range = _range();
      final purchase = _purchase(
        id: 'p1',
        supplierId: 'a',
        date: DateTime(2026, 7, 31, 23, 59),
        total: 100,
      );

      expect(supplierPurchaseMatchesDateRange(purchase, range), isFalse);
    });

    test('no incluye compras posteriores al rango', () {
      final range = _range();
      final purchase = _purchase(
        id: 'p1',
        supplierId: 'a',
        date: DateTime(2026, 8, 7),
        total: 100,
      );

      expect(supplierPurchaseMatchesDateRange(purchase, range), isFalse);
    });

    test('usa limite final exclusivo para respetar el dia operativo local', () {
      final range = _range();

      expect(range.startInclusive, DateTime(2026, 8));
      expect(range.endExclusive, DateTime(2026, 8, 7));
    });

    test('agrupa correctamente por proveedor', () {
      final report = _report([
        _purchase(id: 'a1', supplierId: 'a', total: 100),
        _purchase(id: 'a2', supplierId: 'a', total: 50),
        _purchase(id: 'b1', supplierId: 'b', total: 80),
      ]);

      expect(report.rows, hasLength(2));
      expect(
        report.rows.firstWhere((row) => row.supplierId == 'a').noteCount,
        2,
      );
      expect(
        report.rows.firstWhere((row) => row.supplierId == 'b').noteCount,
        1,
      );
    });

    test('suma correctamente el total de cada proveedor', () {
      final report = _report([
        _purchase(id: 'a1', supplierId: 'a', total: 1200),
        _purchase(id: 'a2', supplierId: 'a', total: 850),
        _purchase(id: 'a3', supplierId: 'a', total: 400),
      ]);

      expect(report.rows.single.totalPurchased, 2450);
    });

    test('ordena proveedores de mayor a menor importe', () {
      final report = _report([
        _purchase(id: 'a1', supplierId: 'a', total: 1500),
        _purchase(id: 'b1', supplierId: 'b', total: 1000),
      ]);

      expect(report.rows.map((row) => row.supplierId), ['a', 'b']);
    });

    test('ordena alfabeticamente cuando el importe empata', () {
      final report = buildPurchasesBySupplierDateReport(
        suppliers: const [
          Supplier(id: 'b', commercialName: 'Beta', active: true),
          Supplier(id: 'a', commercialName: 'Alpha', active: true),
        ],
        purchases: [
          _purchase(
            id: 'b1',
            supplierId: 'b',
            supplierName: 'Beta',
            total: 100,
          ),
          _purchase(
            id: 'a1',
            supplierId: 'a',
            supplierName: 'Alpha',
            total: 100,
          ),
        ],
        range: _range(),
      );

      expect(report.rows.map((row) => row.supplierName), ['Alpha', 'Beta']);
    });

    test('no muestra proveedores sin compras', () {
      final report = buildPurchasesBySupplierDateReport(
        suppliers: const [
          Supplier(id: 'a', commercialName: 'Proveedor A', active: true),
          Supplier(id: 'b', commercialName: 'Proveedor B', active: true),
        ],
        purchases: [_purchase(id: 'a1', supplierId: 'a', total: 100)],
        range: _range(),
      );

      expect(report.rows.map((row) => row.supplierId), ['a']);
    });

    test('excluye compras canceladas', () {
      final report = _report([
        _purchase(id: 'a1', supplierId: 'a', total: 100),
        _purchase(id: 'a2', supplierId: 'a', total: 999, status: 'cancelled'),
      ]);

      expect(report.rows.single.noteCount, 1);
      expect(report.rows.single.totalPurchased, 100);
    });

    test(
      'excluye compras con fecha de cancelacion aunque status sea previo',
      () {
        final report = _report([
          _purchase(
            id: 'a1',
            supplierId: 'a',
            total: 100,
            cancelledAt: DateTime(2026, 8, 2),
          ),
        ]);

        expect(report.rows, isEmpty);
      },
    );

    test('no duplica compras con el mismo id', () {
      final purchase = _purchase(id: 'a1', supplierId: 'a', total: 100);
      final report = _report([purchase, purchase]);

      expect(report.rows.single.noteCount, 1);
      expect(report.rows.single.totalPurchased, 100);
    });

    test('calcula correctamente el total general', () {
      final report = _report([
        _purchase(id: 'a1', supplierId: 'a', total: 1500),
        _purchase(id: 'b1', supplierId: 'b', total: 1000),
      ]);

      expect(report.totalPurchased, 2500);
    });

    test('el total general coincide con la suma de proveedores', () {
      final report = _report([
        _purchase(id: 'a1', supplierId: 'a', total: 100.10),
        _purchase(id: 'b1', supplierId: 'b', total: 200.20),
      ]);
      final sum = report.rows.fold<double>(
        0,
        (runningTotal, row) => runningTotal + row.totalPurchased,
      );

      expect(report.totalPurchased, closeTo(sum, 0.001));
    });

    test('sin resultados muestra total cero', () {
      final report = _report([]);

      expect(report.rows, isEmpty);
      expect(report.totalPurchased, 0);
    });

    test('detalle conserva solo compras del proveedor seleccionado', () {
      final report = _report([
        _purchase(id: 'a1', supplierId: 'a', total: 100),
        _purchase(id: 'b1', supplierId: 'b', total: 200),
      ]);

      final row = report.rows.firstWhere((row) => row.supplierId == 'a');

      expect(row.purchases.map((purchase) => purchase.supplierId), ['a']);
    });

    test('detalle conserva el rango seleccionado', () {
      final range = _range();
      final report = buildPurchasesBySupplierDateReport(
        suppliers: _suppliers,
        purchases: [_purchase(id: 'a1', supplierId: 'a', total: 100)],
        range: range,
      );

      expect(report.range.startDate, range.startDate);
      expect(report.range.endDate, range.endDate);
    });

    test('total del detalle coincide con el resumen', () {
      final report = _report([
        _purchase(id: 'a1', supplierId: 'a', total: 100),
        _purchase(id: 'a2', supplierId: 'a', total: 50),
      ]);
      final row = report.rows.single;
      final detailTotal = row.purchases.fold<double>(
        0,
        (runningTotal, purchase) => runningTotal + purchase.total,
      );

      expect(row.totalPurchased, detailTotal);
    });

    test('compras del proveedor se ordenan de mas reciente a mas antigua', () {
      final report = _report([
        _purchase(
          id: 'old',
          supplierId: 'a',
          date: DateTime(2026, 8, 1),
          total: 1,
        ),
        _purchase(
          id: 'new',
          supplierId: 'a',
          date: DateTime(2026, 8, 6),
          total: 1,
        ),
      ]);

      expect(report.rows.single.purchases.map((purchase) => purchase.id), [
        'new',
        'old',
      ]);
    });

    test('el total mostrado utiliza el valor historico de la compra', () {
      final report = _report([
        _purchase(id: 'a1', supplierId: 'a', total: 440.40),
      ]);

      expect(report.rows.single.totalPurchased, 440.40);
    });

    test('no genera NaN ni Infinity en totales', () {
      final report = _report([
        _purchase(id: 'nan', supplierId: 'a', total: double.nan),
        _purchase(id: 'inf', supplierId: 'a', total: double.infinity),
        _purchase(id: 'ok', supplierId: 'a', total: 10),
      ]);

      expect(report.totalPurchased.isFinite, isTrue);
      expect(report.totalPurchased, 10);
    });

    test('mantiene importes a dos decimales al redondear centavos', () {
      final report = _report([
        _purchase(id: 'a1', supplierId: 'a', total: 10.005),
      ]);

      expect(report.totalPurchased, 10.01);
    });

    test(
      'partida mantiene cantidad, unitario calculado e importe historico',
      () {
        final item = SupplierPurchaseItem.fromData('i1', {
          'purchaseItemName': 'Carne',
          'quantity': 2.010,
          'unit': 'kg',
          'lineTotalCents': 44040,
        });

        expect(item.quantity, 2.01);
        expect(item.lineTotal, 440.40);
        expect(item.unitCostCalculated, closeTo(219.1044776119, 0.0000001));
      },
    );
  });
}

const _suppliers = [
  Supplier(id: 'a', commercialName: 'Proveedor A', active: true),
  Supplier(id: 'b', commercialName: 'Proveedor B', active: true),
];

PurchasesBySupplierReport _report(List<SupplierPurchase> purchases) {
  return buildPurchasesBySupplierDateReport(
    suppliers: _suppliers,
    purchases: purchases,
    range: _range(),
  );
}

PurchasesBySupplierDateRange _range() {
  return PurchasesBySupplierDateRange(
    startDate: DateTime(2026, 8),
    endDate: DateTime(2026, 8, 6),
  );
}

SupplierPurchase _purchase({
  required String id,
  required String supplierId,
  double total = 0,
  DateTime? date,
  String? supplierName,
  String status = 'pending',
  DateTime? cancelledAt,
}) {
  return SupplierPurchase(
    id: id,
    supplierId: supplierId,
    supplierName: supplierName ?? 'Proveedor $supplierId',
    purchaseDate: date ?? DateTime(2026, 8, 2, 12),
    folio: 'F-$id',
    documentType: 'note',
    status: status,
    subtotal: total,
    total: total,
    paidTotal: 0,
    balance: total,
    cancelledAt: cancelledAt,
    createdByEmployeeName: 'Admin',
  );
}
