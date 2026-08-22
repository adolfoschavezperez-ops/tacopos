import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String purchaseScreen;
  late String repository;

  setUpAll(() {
    purchaseScreen = File(
      'lib/screens/admin/purchase_admin_screen.dart',
    ).readAsStringSync();
    repository = File(
      'lib/services/taco_pos_repository.dart',
    ).readAsStringSync();
  });

  test('cuentas por pagar abre sin watch global y busca bajo demanda', () {
    final dataScope = purchaseScreen.substring(
      purchaseScreen.indexOf('class _PurchaseDataScope'),
      purchaseScreen.indexOf('class _SuppliersTab'),
    );
    expect(dataScope, isNot(contains('repository.watchSupplierPurchases()')));
    expect(dataScope, isNot(contains('repository.watchSupplierPayments()')));
    expect(purchaseScreen, contains('Consulta bajo demanda'));
    expect(purchaseScreen, contains('Buscar en todos los proveedores'));
    expect(purchaseScreen, contains('searchSupplierPurchasesByDueDate'));
  });

  test('estado de cuenta no ofrece todos y consulta un proveedor', () {
    expect(purchaseScreen, contains('Selecciona un proveedor para consultar'));
    expect(purchaseScreen, isNot(contains("value: '', child: Text('Todos')")));
    expect(purchaseScreen, contains('getSupplierPurchasesForSupplier'));
    expect(purchaseScreen, contains('getSupplierPaymentsForSupplier'));
  });

  test('pagos consulta por paymentDate y proveedor', () {
    expect(purchaseScreen, contains('Todos los proveedores'));
    expect(purchaseScreen, contains('searchSupplierPayments'));
    expect(repository, contains("orderBy('paymentDate', descending: true)"));
    expect(
      repository,
      contains("where('supplierId', isEqualTo: cleanSupplierId)"),
    );
  });

  test('folio de compra usa counter transaccional global', () {
    expect(repository, contains("doc('purchaseFolioCounter')"));
    expect(repository, contains('runTransaction<int>'));
    expect(repository, contains("'folioNumber': nextFolio"));
    expect(repository, contains("'folio': nextFolio.toString()"));
  });
}
