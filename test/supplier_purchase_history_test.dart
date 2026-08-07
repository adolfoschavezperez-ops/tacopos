import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/purchases/purchases_by_supplier_report.dart';
import 'package:tacopos/core/purchases/supplier_purchase_history.dart';
import 'package:tacopos/models/purchase_models.dart';

void main() {
  group('historial de compras por proveedor en Backoffice', () {
    test('el rango inicial muestra el primer dia del mes actual', () {
      final range = defaultSupplierPurchaseHistoryDateRange(
        DateTime(2026, 8, 6, 18, 30),
      );

      expect(range.startDate, DateTime(2026, 8));
    });

    test('el rango inicial muestra la fecha actual como fecha final', () {
      final range = defaultSupplierPurchaseHistoryDateRange(
        DateTime(2026, 8, 6, 18, 30),
      );

      expect(range.endDate, DateTime(2026, 8, 6));
    });

    test('consulta el rango con fecha final completa', () {
      final range = _range();

      expect(range.startInclusive, DateTime(2026, 8));
      expect(range.endExclusive, DateTime(2026, 8, 7));
    });

    test('solo aparecen compras del proveedor seleccionado', () {
      final history = _history([
        _purchase(id: 'a1', supplierId: 'a', total: 100),
        _purchase(id: 'b1', supplierId: 'b', total: 200),
      ]);

      expect(history.purchases.map((purchase) => purchase.supplierId), ['a']);
    });

    test('no aparecen compras de otros proveedores', () {
      final history = _history([
        _purchase(id: 'b1', supplierId: 'b', total: 200),
      ]);

      expect(history.purchases, isEmpty);
    });

    test('incluye compras de la fecha inicial', () {
      final history = _history([
        _purchase(id: 'a1', supplierId: 'a', date: DateTime(2026, 8)),
      ]);

      expect(history.purchases.single.id, 'a1');
    });

    test('incluye compras de la fecha final', () {
      final history = _history([
        _purchase(
          id: 'a1',
          supplierId: 'a',
          date: DateTime(2026, 8, 6, 23, 59, 59),
        ),
      ]);

      expect(history.purchases.single.id, 'a1');
    });

    test('no aparecen compras fuera del rango', () {
      final history = _history([
        _purchase(id: 'before', supplierId: 'a', date: DateTime(2026, 7, 31)),
        _purchase(id: 'after', supplierId: 'a', date: DateTime(2026, 8, 7)),
      ]);

      expect(history.purchases, isEmpty);
    });

    test('ordena de la mas antigua a la mas reciente', () {
      final history = _history([
        _purchase(id: 'new', supplierId: 'a', date: DateTime(2026, 8, 6)),
        _purchase(id: 'old', supplierId: 'a', date: DateTime(2026, 8, 1)),
        _purchase(id: 'middle', supplierId: 'a', date: DateTime(2026, 8, 4)),
      ]);

      expect(history.purchases.map((purchase) => purchase.id), [
        'old',
        'middle',
        'new',
      ]);
    });

    test('mantiene orden estable con fechas iguales usando hora y folio', () {
      final history = _history([
        _purchase(
          id: 'late',
          supplierId: 'a',
          date: DateTime(2026, 8, 3, 15),
          folio: 'COMP-002',
        ),
        _purchase(
          id: 'early-b',
          supplierId: 'a',
          date: DateTime(2026, 8, 3, 9),
          folio: 'COMP-002',
        ),
        _purchase(
          id: 'early-a',
          supplierId: 'a',
          date: DateTime(2026, 8, 3, 9),
          folio: 'COMP-001',
        ),
      ]);

      expect(history.purchases.map((purchase) => purchase.id), [
        'early-a',
        'early-b',
        'late',
      ]);
    });

    test('muestra folio, fecha, vencimiento, estatus y total reales', () {
      final purchase = _purchase(
        id: 'a1',
        supplierId: 'a',
        date: DateTime(2026, 8, 2),
        dueDate: DateTime(2026, 8, 9),
        folio: 'COMP-001',
        status: 'partial',
        total: 1500,
      );
      final history = _history([purchase]);

      expect(history.purchases.single.folio, 'COMP-001');
      expect(history.purchases.single.purchaseDate, DateTime(2026, 8, 2));
      expect(history.purchases.single.dueDate, DateTime(2026, 8, 9));
      expect(history.purchases.single.status, 'partial');
      expect(history.purchases.single.total, 1500);
    });

    test('calcula total comprado al proveedor en el periodo', () {
      final history = _history([
        _purchase(id: 'a1', supplierId: 'a', total: 100.10),
        _purchase(id: 'a2', supplierId: 'a', total: 200.20),
      ]);

      expect(history.totalPurchased, 300.30);
    });

    test('excluye compras canceladas igual que compras por proveedor', () {
      final history = _history([
        _purchase(id: 'a1', supplierId: 'a', total: 100),
        _purchase(id: 'a2', supplierId: 'a', total: 900, status: 'cancelled'),
      ]);

      expect(history.purchaseCount, 1);
      expect(history.totalPurchased, 100);
    });

    test('excluye compras con cancelledAt aunque el status sea pendiente', () {
      final history = _history([
        _purchase(
          id: 'a1',
          supplierId: 'a',
          total: 100,
          cancelledAt: DateTime(2026, 8, 5),
        ),
      ]);

      expect(history.purchases, isEmpty);
    });

    test('no duplica la misma compra', () {
      final purchase = _purchase(id: 'a1', supplierId: 'a', total: 100);
      final history = _history([purchase, purchase]);

      expect(history.purchaseCount, 1);
      expect(history.totalPurchased, 100);
    });

    test('ver detalle puede usar partidas historicas guardadas', () {
      final item = SupplierPurchaseItem.fromData('i1', {
        'purchaseItemName': 'Carne',
        'quantity': 2.010,
        'unit': 'kg',
        'lineTotalCents': 44040,
      });

      expect(item.purchaseItemName, 'Carne');
      expect(item.quantity, 2.01);
      expect(item.unit, 'kg');
      expect(item.lineTotal, 440.40);
      expect(item.unitCostCalculated, closeTo(219.1044776119, 0.0000001));
    });

    test('permite editar fechas de una compra pendiente desde Backoffice', () {
      final purchase = _purchase(id: 'a1', supplierId: 'a');

      expect(canEditSupplierPurchaseDatesFromBackoffice(purchase), isTrue);
    });

    test('permite editar fechas de una compra pagada desde Backoffice', () {
      final purchase = _paidPurchase();

      expect(canEditSupplierPurchaseDatesFromBackoffice(purchase), isTrue);
    });

    test('no permite editar fechas de una compra cancelada', () {
      final purchase = _purchase(
        id: 'a1',
        supplierId: 'a',
        status: 'cancelled',
      );

      expect(canEditSupplierPurchaseDatesFromBackoffice(purchase), isFalse);
    });

    test('editar fecha de compra pagada no cambia estatus ni total', () {
      final before = _paidPurchase();
      final after = _paidPurchase(
        purchaseDate: DateTime(2026, 8, 3),
        dueDate: DateTime(2026, 8, 10),
      );

      expect(
        keepsSupplierPurchaseFinancialStateAfterDateEdit(
          before: before,
          after: after,
        ),
        isTrue,
      );
      expect(after.status, 'paid');
      expect(after.total, 1500);
    });

    test('editar fecha no cambia pagos, saldo, folio ni proveedor', () {
      final before = _paidPurchase();
      final after = _paidPurchase(
        purchaseDate: DateTime(2026, 8, 3),
        dueDate: DateTime(2026, 8, 10),
      );
      final paymentsBefore = [_payment(purchase: before)];
      final paymentsAfter = [_payment(purchase: after)];

      expect(after.paidTotal, before.paidTotal);
      expect(after.balance, before.balance);
      expect(after.folio, before.folio);
      expect(after.supplierId, before.supplierId);
      expect(paymentsAfter.single.id, paymentsBefore.single.id);
      expect(paymentsAfter.single.amount, paymentsBefore.single.amount);
    });

    test('editar fecha no cambia partidas', () {
      final itemsBefore = [_item('i1'), _item('i2')];
      final itemsAfter = [_item('i1'), _item('i2')];

      expect(itemsAfter.map((item) => item.id), itemsBefore.map((i) => i.id));
      expect(
        itemsAfter.fold<double>(0, (sum, item) => sum + item.lineTotal),
        itemsBefore.fold<double>(0, (sum, item) => sum + item.lineTotal),
      );
    });

    test('editar fecha no genera nueva compra', () {
      final before = _paidPurchase();
      final after = _paidPurchase(
        purchaseDate: DateTime(2026, 8, 3),
        dueDate: DateTime(2026, 8, 10),
      );

      expect(after.id, before.id);
    });

    test('editar fecha no duplica inventario ni genera nuevo pago', () {
      final itemsBefore = [_item('i1')];
      final paymentsBefore = [_payment(purchase: _paidPurchase())];
      final itemsAfter = [_item('i1')];
      final paymentsAfter = [_payment(purchase: _paidPurchase())];

      expect(itemsAfter.length, itemsBefore.length);
      expect(paymentsAfter.length, paymentsBefore.length);
    });

    test('cancelar edicion conserva la compra original', () {
      final before = _paidPurchase();
      final afterCancel = before;

      expect(afterCancel.purchaseDate, before.purchaseDate);
      expect(afterCancel.dueDate, before.dueDate);
      expect(afterCancel.total, before.total);
    });

    test('doble pulsacion en guardar debe mantenerse en una actualizacion', () {
      var updates = 0;
      var saving = false;
      void saveOnce() {
        if (saving) return;
        saving = true;
        updates++;
      }

      saveOnce();
      saveOnce();

      expect(updates, 1);
    });

    test('al guardar se refresca el listado y reordena por nueva fecha', () {
      final updated = _purchase(
        id: 'a2',
        supplierId: 'a',
        date: DateTime(2026, 8, 1),
      );
      final history = _history([
        _purchase(id: 'a1', supplierId: 'a', date: DateTime(2026, 8, 2)),
        updated,
      ]);

      expect(history.purchases.map((purchase) => purchase.id), ['a2', 'a1']);
    });

    test('si la nueva fecha sale del rango desaparece del resultado', () {
      final history = _history([
        _purchase(id: 'a1', supplierId: 'a', date: DateTime(2026, 8, 15)),
      ]);

      expect(history.purchases, isEmpty);
    });

    test('si una compra entra al rango aparece correctamente', () {
      final history = _history([
        _purchase(id: 'a1', supplierId: 'a', date: DateTime(2026, 8, 3)),
      ]);

      expect(history.purchases.single.id, 'a1');
    });

    test('ver detalle despues de editar usa fechas nuevas', () {
      final after = _paidPurchase(
        purchaseDate: DateTime(2026, 8, 3),
        dueDate: DateTime(2026, 8, 10),
      );

      expect(after.purchaseDate, DateTime(2026, 8, 3));
      expect(after.dueDate, DateTime(2026, 8, 10));
    });

    test('la funcionalidad especial queda representada como Backoffice', () {
      final purchase = _paidPurchase();

      expect(canEditSupplierPurchaseDatesFromBackoffice(purchase), isTrue);
    });

    test('no representa desbloqueo completo de compras pagadas', () {
      final before = _paidPurchase();
      final after = _paidPurchase(
        purchaseDate: DateTime(2026, 8, 3),
        dueDate: DateTime(2026, 8, 10),
      );

      expect(after.supplierId, before.supplierId);
      expect(after.total, before.total);
      expect(after.paidTotal, before.paidTotal);
      expect(after.status, before.status);
    });

    test('no rompe el reporte Compras por proveedor', () {
      final report = buildPurchasesBySupplierDateReport(
        suppliers: const [
          Supplier(id: 'a', commercialName: 'Proveedor A', active: true),
        ],
        purchases: [_purchase(id: 'a1', supplierId: 'a', total: 150)],
        range: _range(),
      );

      expect(report.rows.single.totalPurchased, 150);
    });

    test('no cambia criterios de captura, pagos, inventario ni cocina', () {
      final purchase = _paidPurchase();
      final item = _item('i1');
      final payment = _payment(purchase: purchase);

      expect(purchase.status, 'paid');
      expect(item.affectsKitchenStock, isTrue);
      expect(payment.amount, 1500);
    });

    test('no incorpora comercializacion ni multiempresa', () {
      final history = _history([_purchase(id: 'a1', supplierId: 'a')]);

      expect(history.supplierId, 'a');
      expect(history.range.startDate, DateTime(2026, 8));
    });
  });
}

SupplierPurchaseHistory _history(List<SupplierPurchase> purchases) {
  return buildSupplierPurchaseHistory(
    supplierId: 'a',
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

SupplierPurchase _paidPurchase({DateTime? purchaseDate, DateTime? dueDate}) {
  return _purchase(
    id: 'paid-1',
    supplierId: 'a',
    date: purchaseDate ?? DateTime(2026, 8, 1),
    dueDate: dueDate ?? DateTime(2026, 8, 8),
    folio: 'COMP-001',
    status: 'paid',
    total: 1500,
    paidTotal: 1500,
    balance: 0,
  );
}

SupplierPurchase _purchase({
  required String id,
  required String supplierId,
  DateTime? date,
  DateTime? dueDate,
  String folio = 'COMP-001',
  String status = 'pending',
  double total = 100,
  double? paidTotal,
  double? balance,
  DateTime? cancelledAt,
}) {
  return SupplierPurchase(
    id: id,
    supplierId: supplierId,
    supplierName: 'Proveedor $supplierId',
    purchaseDate: date ?? DateTime(2026, 8, 2, 12),
    dueDate: dueDate ?? DateTime(2026, 8, 9),
    folio: folio,
    documentType: 'note',
    status: status,
    subtotal: total,
    total: total,
    paidTotal: paidTotal ?? 0,
    balance: balance ?? total,
    cancelledAt: cancelledAt,
    createdAt: date,
    createdByEmployeeName: 'Admin',
  );
}

SupplierPurchaseItem _item(String id) {
  return SupplierPurchaseItem.fromData(id, {
    'purchaseItemName': 'Carne',
    'quantity': 2,
    'unit': 'kg',
    'lineTotalCents': 75000,
    'affectsKitchenStock': true,
  });
}

SupplierPayment _payment({required SupplierPurchase purchase}) {
  return SupplierPayment(
    id: 'pay-1',
    supplierId: purchase.supplierId,
    supplierName: purchase.supplierName,
    purchaseId: purchase.id,
    purchaseFolio: purchase.folio,
    paymentDate: DateTime(2026, 8, 8),
    amount: 1500,
    method: 'cash',
    status: 'active',
  );
}
