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
    required this.sendToKitchen,
    required this.kitchenStatus,
    required this.paymentStatus,
    this.kitchenBatchId,
    this.createdAt,
    this.updatedAt,
    this.sentToKitchenAt,
    this.cookingAt,
    this.readyAt,
    this.paidAt,
    this.paymentId,
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
  final bool sendToKitchen;
  final String kitchenStatus;
  final String paymentStatus;
  final String? kitchenBatchId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? sentToKitchenAt;
  final DateTime? cookingAt;
  final DateTime? readyAt;
  final DateTime? paidAt;
  final String? paymentId;

  factory OrderItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return OrderItem(
      id: doc.id,
      personNumber: (data['personNumber'] as num?)?.toInt() ?? 1,
      personName: _readPersonName(data),
      productId: data['productId'] as String? ?? '',
      productName: data['productName'] as String? ?? 'Producto',
      category: data['category'] as String? ?? 'General',
      qty: (data['qty'] as num?)?.toInt() ?? 1,
      unitPrice: (data['unitPrice'] as num?)?.toDouble() ?? 0,
      total: (data['total'] as num?)?.toDouble() ?? 0,
      notes: data['notes'] as String? ?? '',
      sendToKitchen:
          data['sendToKitchen'] as bool? ?? _defaultSendToKitchen(data),
      kitchenStatus: data['kitchenStatus'] as String? ?? 'pending',
      paymentStatus: data['paymentStatus'] as String? ?? 'pending',
      kitchenBatchId: data['kitchenBatchId'] as String?,
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
      sentToKitchenAt: _toDate(data['sentToKitchenAt']),
      cookingAt: _toDate(data['cookingAt']),
      readyAt: _toDate(data['readyAt']),
      paidAt: _toDate(data['paidAt']),
      paymentId: data['paymentId'] as String?,
    );
  }

  static bool _defaultSendToKitchen(Map<String, dynamic> data) {
    final category = (data['category'] as String? ?? '').toLowerCase().trim();
    return category != 'bebidas';
  }

  static String _readPersonName(Map<String, dynamic> data) {
    final personNumber = (data['personNumber'] as num?)?.toInt() ?? 1;
    final name = (data['personName'] as String?)?.trim();
    return name == null || name.isEmpty ? 'Persona $personNumber' : name;
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    return null;
  }
}
