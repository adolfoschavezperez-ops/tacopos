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
    final category = _readString(data['category'], 'General');

    return Product(
      id: doc.id,
      name: _readString(data['name'], doc.id),
      category: category,
      price: _readDouble(data['price']),
      active: _readBool(data['active'], fallback: true),
      sendToKitchen: _readBool(
        data['sendToKitchen'],
        fallback: _defaultSendToKitchen(category),
      ),
      sortOrder: _readInt(data['sortOrder']),
    );
  }

  static String _readString(Object? value, String fallback) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return fallback;
  }

  static double _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.')) ?? 0;
    }

    return 0;
  }

  static int _readInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    return 0;
  }

  static bool _readBool(Object? value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      final normalized = value.toLowerCase().trim();
      if (['true', '1', 'yes', 'si'].contains(normalized)) {
        return true;
      }
      if (['false', '0', 'no'].contains(normalized)) {
        return false;
      }
    }

    return fallback;
  }

  static bool _defaultSendToKitchen(String category) {
    category = category.toLowerCase().trim();
    return category != 'bebidas';
  }
}
