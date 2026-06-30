import 'package:cloud_firestore/cloud_firestore.dart';

class KitchenStockItem {
  const KitchenStockItem({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.active,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String category;
  final String unit;
  final bool active;
  final int sortOrder;

  factory KitchenStockItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return KitchenStockItem(
      id: doc.id,
      name: data['name'] as String? ?? doc.id,
      category: data['category'] as String? ?? 'other',
      unit: data['unit'] as String? ?? 'kg',
      active: data['active'] as bool? ?? true,
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}
