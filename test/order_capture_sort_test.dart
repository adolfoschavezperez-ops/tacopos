import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/order_capture_sort.dart';
import 'package:tacopos/models/product.dart';

void main() {
  test('sortProductsForOrderCapture orders products A-Z inside a category', () {
    final sorted = sortProductsForOrderCapture([
      _product(id: 'c', name: 'Volcan', sortOrder: 1),
      _product(id: 'b', name: 'Agua', sortOrder: 99),
      _product(id: 'a', name: 'alambre', sortOrder: 1),
      _product(id: 'd', name: 'Agua', sortOrder: 2),
      _product(id: 'e', name: 'Agua', sortOrder: 1),
    ]);

    expect(sorted.map((product) => product.id), ['e', 'd', 'b', 'a', 'c']);
  });
}

Product _product({
  required String id,
  required String name,
  required int sortOrder,
}) {
  return Product(
    id: id,
    name: name,
    categoryId: 'tacos',
    categoryName: 'Tacos',
    category: 'Tacos',
    price: 10,
    active: true,
    sendToKitchen: true,
    sortOrder: sortOrder,
    platformPrices: const {},
    affectsKitchenStock: false,
  );
}
