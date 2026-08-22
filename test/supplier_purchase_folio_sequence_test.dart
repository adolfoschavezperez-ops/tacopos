import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/models/purchase_models.dart';

void main() {
  test('supplier A 1,2,3 returns 4', () {
    expect(nextSupplierPurchaseFolioFromNumbers([1, 2, 3]), 4);
  });

  test('supplier B 1,2,3,4,5 returns 6', () {
    expect(nextSupplierPurchaseFolioFromNumbers([1, 2, 3, 4, 5]), 6);
  });

  test('supplier change A to B previews independent values', () {
    final supplierA = nextSupplierPurchaseFolioFromNumbers([1, 2, 3]);
    final supplierB = nextSupplierPurchaseFolioFromNumbers([1, 2, 3, 4, 5]);

    expect(supplierA, 4);
    expect(supplierB, 6);
  });

  test('new supplier starts at 1', () {
    expect(nextSupplierPurchaseFolioFromNumbers([]), 1);
  });

  test('supplier A with gap 1,2,5 returns max plus one', () {
    expect(nextSupplierPurchaseFolioFromNumbers([1, 2, 5]), 6);
  });

  test('supplier A and B can both have next 11', () {
    final supplierA = nextSupplierPurchaseFolioFromNumbers([8, 9, 10]);
    final supplierB = nextSupplierPurchaseFolioFromNumbers([1, 10]);

    expect(supplierA, 11);
    expect(supplierB, 11);
  });

  test('numeric max avoids lexicographic folio order', () {
    expect(nextSupplierPurchaseFolioFromNumbers([1, 2, 9, 10, 100]), 101);
  });
}
