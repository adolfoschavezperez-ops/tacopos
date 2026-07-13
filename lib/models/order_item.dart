import 'package:cloud_firestore/cloud_firestore.dart';

import 'product_recipe_item.dart';

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
    this.appliedPlatformId,
    this.appliedPlatformName,
    this.priceSource,
    this.kitchenStockItemId,
    this.kitchenStockItemName,
    this.affectsKitchenStock = false,
    this.kitchenStockUnit,
    this.recipeItems = const [],
    this.status = 'active',
    this.cancelStatus = 'none',
    this.cancelRequestedAt,
    this.cancelRequestedByEmployeeId,
    this.cancelRequestedByEmployeeName,
    this.cancelledAt,
    this.cancelledByEmployeeId,
    this.cancelledByEmployeeName,
    this.cancelReason,
    this.cancelAcceptedAt,
    this.cancelAcceptedByEmployeeId,
    this.cancelAcceptedByEmployeeName,
    this.cancelRejectedAt,
    this.cancelRejectedByEmployeeId,
    this.cancelRejectedByEmployeeName,
    this.cancelRejectReason,
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
  final String? appliedPlatformId;
  final String? appliedPlatformName;
  final String? priceSource;
  final String? kitchenStockItemId;
  final String? kitchenStockItemName;
  final bool affectsKitchenStock;
  final String? kitchenStockUnit;
  final List<ProductRecipeItem> recipeItems;
  final String status;
  final String cancelStatus;
  final DateTime? cancelRequestedAt;
  final String? cancelRequestedByEmployeeId;
  final String? cancelRequestedByEmployeeName;
  final DateTime? cancelledAt;
  final String? cancelledByEmployeeId;
  final String? cancelledByEmployeeName;
  final String? cancelReason;
  final DateTime? cancelAcceptedAt;
  final String? cancelAcceptedByEmployeeId;
  final String? cancelAcceptedByEmployeeName;
  final DateTime? cancelRejectedAt;
  final String? cancelRejectedByEmployeeId;
  final String? cancelRejectedByEmployeeName;
  final String? cancelRejectReason;

  bool get isServed => kitchenStatus == 'ready';
  bool get isCancelled =>
      status == 'cancelled' ||
      kitchenStatus == 'cancelled' ||
      paymentStatus == 'cancelled' ||
      cancelStatus == 'accepted';
  bool get hasCancellationRequested =>
      cancelStatus == 'requested' || kitchenStatus == 'cancel_requested';
  bool get wasCancellationRejected => cancelStatus == 'rejected';

  factory OrderItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    final kitchenStockItemId = data['kitchenStockItemId'] as String?;
    final kitchenStockItemName = data['kitchenStockItemName'] as String?;
    final kitchenStockUnit = data['kitchenStockUnit'] as String?;
    final recipeItems = ProductRecipeItem.readList(
      data['recipeItems'],
      legacyStockItemId: kitchenStockItemId,
      legacyStockItemName: kitchenStockItemName,
      legacyStockUnit: kitchenStockUnit,
      legacyConsumptionFactor: data['stockConsumptionQty'] is num
          ? (data['stockConsumptionQty'] as num).toDouble()
          : data['kitchenConsumptionFactor'] is num
          ? (data['kitchenConsumptionFactor'] as num).toDouble()
          : null,
    );
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
      appliedPlatformId: data['appliedPlatformId'] as String?,
      appliedPlatformName: data['appliedPlatformName'] as String?,
      priceSource: data['priceSource'] as String?,
      kitchenStockItemId: kitchenStockItemId,
      kitchenStockItemName: kitchenStockItemName,
      affectsKitchenStock:
          data['affectsKitchenStock'] as bool? ?? recipeItems.isNotEmpty,
      kitchenStockUnit: kitchenStockUnit,
      recipeItems: recipeItems,
      status: data['status'] as String? ?? 'active',
      cancelStatus: data['cancelStatus'] as String? ?? 'none',
      cancelRequestedAt: _toDate(data['cancelRequestedAt']),
      cancelRequestedByEmployeeId:
          data['cancelRequestedByEmployeeId'] as String?,
      cancelRequestedByEmployeeName:
          data['cancelRequestedByEmployeeName'] as String?,
      cancelledAt: _toDate(data['cancelledAt']),
      cancelledByEmployeeId: data['cancelledByEmployeeId'] as String?,
      cancelledByEmployeeName: data['cancelledByEmployeeName'] as String?,
      cancelReason: data['cancelReason'] as String?,
      cancelAcceptedAt: _toDate(data['cancelAcceptedAt']),
      cancelAcceptedByEmployeeId: data['cancelAcceptedByEmployeeId'] as String?,
      cancelAcceptedByEmployeeName:
          data['cancelAcceptedByEmployeeName'] as String?,
      cancelRejectedAt: _toDate(data['cancelRejectedAt']),
      cancelRejectedByEmployeeId: data['cancelRejectedByEmployeeId'] as String?,
      cancelRejectedByEmployeeName:
          data['cancelRejectedByEmployeeName'] as String?,
      cancelRejectReason: data['cancelRejectReason'] as String?,
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
