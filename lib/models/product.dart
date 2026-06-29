import 'package:cloud_firestore/cloud_firestore.dart';

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.active,
    required this.sendToKitchen,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String category;
  final double price;
  final bool active;
  final bool sendToKitchen;
  final int sortOrder;

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return Product(
      id: doc.id,
      name: data['name'] as String? ?? doc.id,
      category: data['category'] as String? ?? 'General',
      price: (data['price'] as num?)?.toDouble() ?? 0,
      active: data['active'] as bool? ?? true,
      sendToKitchen:
          data['sendToKitchen'] as bool? ?? _defaultSendToKitchen(data),
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  static bool _defaultSendToKitchen(Map<String, dynamic> data) {
    final category = (data['category'] as String? ?? '').toLowerCase().trim();
    return category != 'bebidas';
  }
}
