import '../../models/product.dart';

List<Product> sortProductsForOrderCapture(Iterable<Product> products) {
  final sorted = products.toList();
  sorted.sort(compareProductsForOrderCapture);
  return sorted;
}

int compareProductsForOrderCapture(Product a, Product b) {
  final nameCompare = a.name.trim().toLowerCase().compareTo(
    b.name.trim().toLowerCase(),
  );
  if (nameCompare != 0) return nameCompare;

  final sortCompare = a.sortOrder.compareTo(b.sortOrder);
  if (sortCompare != 0) return sortCompare;

  return a.id.compareTo(b.id);
}
