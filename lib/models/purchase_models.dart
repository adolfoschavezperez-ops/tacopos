import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';

class Supplier {
  const Supplier({
    required this.id,
    required this.commercialName,
    required this.active,
    this.legalName = '',
    this.rfc = '',
    this.phone = '',
    this.contactName = '',
    this.address = '',
    this.notes = '',
    this.preferredPaymentMethod = 'both',
    this.creditDays = 0,
    this.paymentWeekday = 'none',
    this.paymentWeekdayName = 'Sin dia fijo',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String commercialName;
  final String legalName;
  final String rfc;
  final String phone;
  final String contactName;
  final String address;
  final String notes;
  final bool active;
  final String preferredPaymentMethod;
  final int creditDays;
  final String paymentWeekday;
  final String paymentWeekdayName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Supplier.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Supplier(
      id: doc.id,
      commercialName: data['commercialName'] as String? ?? 'Proveedor',
      legalName: data['legalName'] as String? ?? '',
      rfc: data['rfc'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      contactName: data['contactName'] as String? ?? '',
      address: data['address'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      active: data['active'] as bool? ?? true,
      preferredPaymentMethod:
          data['preferredPaymentMethod'] as String? ?? 'both',
      creditDays: (data['creditDays'] as num?)?.toInt() ?? 0,
      paymentWeekday: data['paymentWeekday'] as String? ?? 'none',
      paymentWeekdayName:
          data['paymentWeekdayName'] as String? ?? 'Sin dia fijo',
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }
}

class PurchaseItem {
  const PurchaseItem({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.active,
    this.defaultSupplierId,
    this.defaultSupplierName,
    this.affectsKitchenStock = false,
    this.kitchenStockItemId,
    this.kitchenStockItemName,
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String category;
  final String unit;
  final bool active;
  final String? defaultSupplierId;
  final String? defaultSupplierName;
  final bool affectsKitchenStock;
  final String? kitchenStockItemId;
  final String? kitchenStockItemName;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PurchaseItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return PurchaseItem(
      id: doc.id,
      name: data['name'] as String? ?? 'Insumo',
      category: data['category'] as String? ?? 'General',
      unit: data['unit'] as String? ?? 'pieza',
      active: data['active'] as bool? ?? true,
      defaultSupplierId: data['defaultSupplierId'] as String?,
      defaultSupplierName: data['defaultSupplierName'] as String?,
      affectsKitchenStock: data['affectsKitchenStock'] as bool? ?? false,
      kitchenStockItemId: data['kitchenStockItemId'] as String?,
      kitchenStockItemName: data['kitchenStockItemName'] as String?,
      notes: data['notes'] as String? ?? '',
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }
}

class SupplierPurchase {
  const SupplierPurchase({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.purchaseDate,
    required this.dueDate,
    required this.folio,
    required this.documentType,
    required this.status,
    required this.subtotal,
    required this.total,
    required this.paidTotal,
    required this.balance,
    this.notes = '',
    this.restaurantId = AppConstants.restaurantId,
    this.restaurantName = AppConstants.restaurantName,
    this.branchId = AppConstants.defaultBranchId,
    this.branchName = AppConstants.defaultBranchName,
    this.paymentWeekdaySnapshot = 'none',
    this.paymentWeekdayNameSnapshot = 'Sin dia fijo',
    this.createdByEmployeeId = '',
    this.createdByEmployeeName = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String branchId;
  final String branchName;
  final String supplierId;
  final String supplierName;
  final DateTime purchaseDate;
  final DateTime dueDate;
  final String paymentWeekdaySnapshot;
  final String paymentWeekdayNameSnapshot;
  final String createdByEmployeeId;
  final String createdByEmployeeName;
  final String folio;
  final String documentType;
  final String status;
  final double subtotal;
  final double total;
  final double paidTotal;
  final double balance;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasBalance => balance > 0.01 && status != 'cancelled';

  factory SupplierPurchase.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final now = DateTime.now();
    return SupplierPurchase(
      id: doc.id,
      restaurantId:
          data['restaurantId'] as String? ?? AppConstants.restaurantId,
      restaurantName:
          data['restaurantName'] as String? ?? AppConstants.restaurantName,
      branchId: data['branchId'] as String? ?? AppConstants.defaultBranchId,
      branchName:
          data['branchName'] as String? ?? AppConstants.defaultBranchName,
      supplierId: data['supplierId'] as String? ?? '',
      supplierName: data['supplierName'] as String? ?? 'Proveedor',
      purchaseDate: _toDate(data['purchaseDate']) ?? now,
      dueDate: _toDate(data['dueDate']) ?? now,
      paymentWeekdaySnapshot:
          data['paymentWeekdaySnapshot'] as String? ?? 'none',
      paymentWeekdayNameSnapshot:
          data['paymentWeekdayNameSnapshot'] as String? ?? 'Sin dia fijo',
      createdByEmployeeId: data['createdByEmployeeId'] as String? ?? '',
      createdByEmployeeName: data['createdByEmployeeName'] as String? ?? '',
      folio: data['folio'] as String? ?? '',
      documentType: data['documentType'] as String? ?? 'note',
      status: data['status'] as String? ?? 'pending',
      subtotal: _toDouble(data['subtotal']),
      total: _toDouble(data['total']),
      paidTotal: _toDouble(data['paidTotal']),
      balance: _toDouble(data['balance']),
      notes: data['notes'] as String? ?? '',
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }
}

class SupplierPurchaseItem {
  const SupplierPurchaseItem({
    required this.id,
    required this.purchaseItemName,
    required this.quantity,
    required this.unit,
    required this.unitCost,
    required this.total,
    this.purchaseItemId,
    this.kitchenStockItemId,
    this.kitchenStockItemName,
    this.affectsKitchenStock = false,
    this.notes = '',
  });

  final String id;
  final String? purchaseItemId;
  final String purchaseItemName;
  final String? kitchenStockItemId;
  final String? kitchenStockItemName;
  final bool affectsKitchenStock;
  final double quantity;
  final String unit;
  final double unitCost;
  final double total;
  final String notes;

  factory SupplierPurchaseItem.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return SupplierPurchaseItem(
      id: doc.id,
      purchaseItemId: data['purchaseItemId'] as String?,
      purchaseItemName:
          data['purchaseItemName'] as String? ??
          data['itemName'] as String? ??
          data['kitchenStockItemName'] as String? ??
          'Insumo',
      kitchenStockItemId:
          data['kitchenStockItemId'] as String? ?? data['itemId'] as String?,
      kitchenStockItemName:
          data['kitchenStockItemName'] as String? ??
          data['itemName'] as String?,
      affectsKitchenStock:
          data['affectsKitchenStock'] as bool? ??
          data['affectsKitchenPerformance'] as bool? ??
          false,
      quantity: _toDouble(data['quantity']),
      unit: data['unit'] as String? ?? '',
      unitCost: _toDouble(data['unitCost']),
      total: _toDouble(data['total']),
      notes: data['notes'] as String? ?? '',
    );
  }
}

class SupplierPayment {
  const SupplierPayment({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.purchaseId,
    required this.purchaseFolio,
    required this.paymentDate,
    required this.amount,
    required this.method,
    required this.status,
    this.reference = '',
    this.notes = '',
    this.restaurantId = AppConstants.restaurantId,
    this.restaurantName = AppConstants.restaurantName,
    this.branchId = AppConstants.defaultBranchId,
    this.branchName = AppConstants.defaultBranchName,
    this.createdByEmployeeId = '',
    this.createdByEmployeeName = '',
    this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String branchId;
  final String branchName;
  final String createdByEmployeeId;
  final String createdByEmployeeName;
  final String supplierId;
  final String supplierName;
  final String purchaseId;
  final String purchaseFolio;
  final DateTime paymentDate;
  final double amount;
  final String method;
  final String reference;
  final String notes;
  final String status;
  final DateTime? createdAt;

  factory SupplierPayment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return SupplierPayment(
      id: doc.id,
      restaurantId:
          data['restaurantId'] as String? ?? AppConstants.restaurantId,
      restaurantName:
          data['restaurantName'] as String? ?? AppConstants.restaurantName,
      branchId: data['branchId'] as String? ?? AppConstants.defaultBranchId,
      branchName:
          data['branchName'] as String? ?? AppConstants.defaultBranchName,
      createdByEmployeeId: data['createdByEmployeeId'] as String? ?? '',
      createdByEmployeeName: data['createdByEmployeeName'] as String? ?? '',
      supplierId: data['supplierId'] as String? ?? '',
      supplierName: data['supplierName'] as String? ?? 'Proveedor',
      purchaseId: data['purchaseId'] as String? ?? '',
      purchaseFolio: data['purchaseFolio'] as String? ?? '',
      paymentDate: _toDate(data['paymentDate']) ?? DateTime.now(),
      amount: _toDouble(data['amount']),
      method: data['method'] as String? ?? 'transfer',
      reference: data['reference'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      status: data['status'] as String? ?? 'active',
      createdAt: _toDate(data['createdAt']),
    );
  }
}

class SupplierStatementRow {
  const SupplierStatementRow({
    required this.date,
    required this.type,
    required this.folio,
    required this.charge,
    required this.credit,
    required this.balance,
    required this.method,
    required this.notes,
    this.purchaseId,
    this.paymentId,
  });

  final DateTime date;
  final String type;
  final String folio;
  final double charge;
  final double credit;
  final double balance;
  final String method;
  final String notes;
  final String? purchaseId;
  final String? paymentId;
}

class PurchaseSupplierReportRow {
  const PurchaseSupplierReportRow({
    required this.supplierId,
    required this.supplierName,
    required this.totalPurchased,
    required this.totalPaid,
    required this.balance,
    required this.noteCount,
    required this.paymentWeekdayName,
  });

  final String supplierId;
  final String supplierName;
  final double totalPurchased;
  final double totalPaid;
  final double balance;
  final int noteCount;
  final String paymentWeekdayName;
}

class PurchaseItemReportRow {
  const PurchaseItemReportRow({
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.total,
    required this.noteCount,
    required this.affectsKitchenPerformance,
  });

  final String itemId;
  final String itemName;
  final double quantity;
  final String unit;
  final double total;
  final int noteCount;
  final bool affectsKitchenPerformance;
}

class PurchaseLineInput {
  const PurchaseLineInput({
    required this.purchaseItemName,
    required this.quantity,
    required this.unit,
    required this.unitCost,
    this.purchaseItemId,
    this.kitchenStockItemId,
    this.kitchenStockItemName,
    this.affectsKitchenStock = false,
    this.notes = '',
  });

  final String? purchaseItemId;
  final String purchaseItemName;
  final String? kitchenStockItemId;
  final String? kitchenStockItemName;
  final bool affectsKitchenStock;
  final double quantity;
  final String unit;
  final double unitCost;
  final String notes;

  double get total => quantity * unitCost;
}

DateTime? _toDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

double _toDouble(Object? value) {
  return value is num ? value.toDouble() : 0;
}
