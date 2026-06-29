import 'package:cloud_firestore/cloud_firestore.dart';

class OrderPlatform {
  const OrderPlatform({
    required this.id,
    required this.name,
    required this.active,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final bool active;
  final int sortOrder;

  factory OrderPlatform.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return OrderPlatform(
      id: doc.id,
      name: data['name'] as String? ?? doc.id,
      active: data['active'] as bool? ?? true,
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}
