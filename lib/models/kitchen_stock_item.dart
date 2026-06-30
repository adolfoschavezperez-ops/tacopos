import 'package:cloud_firestore/cloud_firestore.dart';

class KitchenStockItem {
  const KitchenStockItem({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.active,
    required this.sortOrder,
    required this.optimalConsumptionPerSaleQty,
    required this.optimalConsumptionUnit,
  });

  final String id;
  final String name;
  final String category;
  final String unit;
  final bool active;
  final int sortOrder;
  final double optimalConsumptionPerSaleQty;
  final String optimalConsumptionUnit;

  factory KitchenStockItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return KitchenStockItem(
      id: doc.id,
      name: data['name'] as String? ?? doc.id,
      category: data['category'] as String? ?? 'other',
      unit: data['unit'] as String? ?? 'kg',
      active: data['active'] as bool? ?? true,
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
      optimalConsumptionPerSaleQty:
          (data['optimalConsumptionPerSaleQty'] as num?)?.toDouble() ?? 0,
      optimalConsumptionUnit:
          data['optimalConsumptionUnit'] as String? ??
          _defaultOptimalUnit(data['unit'] as String? ?? 'kg'),
    );
  }

  static String _defaultOptimalUnit(String unit) {
    return switch (unit) {
      'piece' => 'piece_per_item',
      'kg' => 'g_per_item',
      _ => '',
    };
  }
}
