import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/screens/admin/purchase_admin_screen.dart',
  ).readAsStringSync();
  final repositorySource = File(
    'lib/services/taco_pos_repository.dart',
  ).readAsStringSync();

  test('CXP no consulta al abrir y conserva dueDate en Firestore', () {
    expect(source, contains("_searched = false;"));
    expect(source, contains('searchSupplierPurchasesByDueDate'));
    expect(repositorySource, contains("'dueDate'"));
    expect(source, contains("kind: 'payables'"));
    expect(source, contains("allSuppliers: allSuppliers"));
  });

  test('Pagos no consulta automaticamente al abrir', () {
    expect(source, contains('bool _searched = false;'));
    expect(source, contains('bool _loading = false;'));
    expect(source, contains('Consulta bajo demanda'));
    expect(source, contains("kind: 'supplier-payments'"));
    expect(source, contains('searchSupplierPayments'));
  });

  test(
    'filtros draft no disparan consultas y Buscar usa una clave estable',
    () {
      expect(source, contains('class _PurchaseListQueryKey'));
      expect(source, contains('_queryKey == key'));
      expect(source, contains('(_searched || _loading)'));
      expect(source, contains('Object();'));
      expect(source, contains('_searchGeneration != generation'));
    },
  );

  test('Limpiar cancela contexto aplicado sin hacer una nueva consulta', () {
    expect(source, contains('void _clear()'));
    expect(source, contains('_queryKey = null;'));
    expect(source, contains('_searchGeneration = Object();'));
    expect(source, contains('_payments = const [];'));
  });

  test('consultas server-side conservan los filtros de proveedor y fecha', () {
    expect(
      repositorySource,
      contains(
        "query = query.where('supplierId', isEqualTo: cleanSupplierId);",
      ),
    );
    expect(repositorySource, contains("'paymentDate'"));
    expect(repositorySource, contains("'purchaseDate'"));
    expect(source, isNot(contains('purchaseFolioCounter')));
  });

  test('reporte por insumo carga items al recibir compras ya consultadas', () {
    expect(source, contains('_itemsFuture = widget.hasConsulted'));
    expect(source, contains('? _loadItems()'));
    expect(
      source,
      contains("(!oldWidget.hasConsulted && widget.hasConsulted)"),
    );
    expect(source, contains('allItems: itemRows'));
    expect(source, contains('_exportItems(context, itemRows)'));
  });
}
