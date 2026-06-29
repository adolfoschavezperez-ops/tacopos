import 'package:cloud_firestore/cloud_firestore.dart';

class OrderItem {
  const OrderItem({
    required this.id,
    required this.personNumber,
    required this.personName,
    required this.productId,
    required this.productName,
    required this.category,
    required this.qty,
    required this.unitPrice,
    required this.total,
    required this.notes,
    required this.kitchenStatus,
    required this.paymentStatus,
  });

  final String id;
  final int personNumber;
  final String personName;
  final String productId;
  final String productName;
  final String category;
  final int qty;
  final double unitPrice;
  final double total;
  final String notes;
  final String kitchenStatus;
  final String paymentStatus;

  factory OrderItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return OrderItem(
      id: doc.id,
      personNumber: (data['personNumber'] as num?)?.toInt() ?? 1,
      personName: data['personName'] as String? ?? 'Persona 1',
      productId: data['productId'] as String? ?? '',
      productName: data['productName'] as String? ?? 'Producto',
      category: data['category'] as String? ?? 'General',
      qty: (data['qty'] as num?)?.toInt() ?? 1,
      unitPrice: (data['unitPrice'] as num?)?.toDouble() ?? 0,
      total: (data['total'] as num?)?.toDouble() ?? 0,
      notes: data['notes'] as String? ?? '',
      kitchenStatus: data['kitchenStatus'] as String? ?? 'pending',
      paymentStatus: data['paymentStatus'] as String? ?? 'pending',
    );
  }
}
