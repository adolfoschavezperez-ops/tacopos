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
    this.dueDate,
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
    this.cancelledAt,
    this.cancelledByEmployeeId,
    this.cancelledByEmployeeName,
    this.cancelReason,
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
  final DateTime? dueDate;
  final String paymentWeekdaySnapshot;
  final String paymentWeekdayNameSnapshot;
  final String createdByEmployeeId;
  final String createdByEmployeeName;
  final DateTime? cancelledAt;
  final String? cancelledByEmployeeId;
  final String? cancelledByEmployeeName;
  final String? cancelReason;
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

  bool get isCancelled => status == 'cancelled' || cancelledAt != null;
  bool get hasBalance => balance > 0.01 && !isCancelled;

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
      dueDate: _toDate(data['dueDate']),
      paymentWeekdaySnapshot:
          data['paymentWeekdaySnapshot'] as String? ?? 'none',
      paymentWeekdayNameSnapshot:
          data['paymentWeekdayNameSnapshot'] as String? ?? 'Sin dia fijo',
      createdByEmployeeId: data['createdByEmployeeId'] as String? ?? '',
      createdByEmployeeName: data['createdByEmployeeName'] as String? ?? '',
      cancelledAt: _toDate(data['cancelledAt']),
      cancelledByEmployeeId: data['cancelledByEmployeeId'] as String?,
      cancelledByEmployeeName: data['cancelledByEmployeeName'] as String?,
      cancelReason: data['cancelReason'] as String?,
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
    this.status = 'active',
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
  final String status;
  final String notes;

  bool get isActive => status != 'removed' && status != 'cancelled';

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
      status: data['status'] as String? ?? 'active',
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
    this.fundingSource = 'cash',
    this.fundingSourceName = 'Efectivo',
    this.partnerId,
    this.partnerName,
    this.cancelledAt,
    this.cancelledByEmployeeId,
    this.cancelledByEmployeeName,
    this.cancelReason,
    this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String branchId;
  final String branchName;
  final String createdByEmployeeId;
  final String createdByEmployeeName;
  final String fundingSource;
  final String fundingSourceName;
  final String? partnerId;
  final String? partnerName;
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
  final DateTime? cancelledAt;
  final String? cancelledByEmployeeId;
  final String? cancelledByEmployeeName;
  final String? cancelReason;
  final DateTime? createdAt;

  bool get isActive => status == 'active' && cancelledAt == null;
  bool get isCancelled => status == 'cancelled' || cancelledAt != null;

  factory SupplierPayment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final rawFundingSource = _supplierPaymentMethodFromData(data);
    final method = _normalizeSupplierPaymentMethod(rawFundingSource);
    final fundingSourceName = _supplierPaymentMethodLabel(method);
    final paymentDate =
        _toDate(data['paymentDate']) ?? _toDate(data['createdAt']);
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
      fundingSource: method,
      fundingSourceName: fundingSourceName,
      partnerId: data['partnerId'] as String?,
      partnerName: data['partnerName'] as String?,
      supplierId: data['supplierId'] as String? ?? '',
      supplierName: data['supplierName'] as String? ?? 'Proveedor',
      purchaseId: data['purchaseId'] as String? ?? '',
      purchaseFolio: data['purchaseFolio'] as String? ?? '',
      paymentDate: paymentDate ?? DateTime.now(),
      amount: _toDouble(data['amount']),
      method: method,
      reference: data['reference'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      status: (data['status'] as String? ?? 'active').trim().toLowerCase(),
      cancelledAt: _toDate(data['cancelledAt']),
      cancelledByEmployeeId: data['cancelledByEmployeeId'] as String?,
      cancelledByEmployeeName: data['cancelledByEmployeeName'] as String?,
      cancelReason: data['cancelReason'] as String?,
      createdAt: _toDate(data['createdAt']),
    );
  }
}

String _supplierPaymentMethodFromData(Map<String, dynamic> data) {
  final values = [
    data['method'],
    data['paymentMethod'],
    data['fundingSource'],
    data['methodName'],
    data['paymentMethodName'],
    data['fundingSourceName'],
  ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
  for (final value in values) {
    if (_normalizeSupplierPaymentMethod(value) == 'partner_contribution') {
      return value;
    }
  }
  return values.isEmpty ? 'transfer' : values.first;
}

String _normalizeSupplierPaymentMethod(String value) {
  final normalized = _normalizeToken(value);
  return switch (normalized) {
    'business_cash' || 'business cash' || 'cash' || 'efectivo' => 'cash',
    'business_transfer' ||
    'business transfer' ||
    'transfer' ||
    'transferencia' => 'transfer',
    'partner_cash' ||
    'partner cash' ||
    'partner_transfer' ||
    'partner transfer' ||
    'partner_contribution' ||
    'partner contribution' ||
    'aportacion de socios' => 'partner_contribution',
    _ => normalized,
  };
}

String _normalizeToken(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
}

String _supplierPaymentMethodLabel(String method) {
  return switch (_normalizeSupplierPaymentMethod(method)) {
    'cash' => 'Efectivo',
    'transfer' => 'Transferencia',
    'partner_contribution' => 'Aportacion de socios',
    _ => method,
  };
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
    this.dueDate,
    this.supplierName = '',
    this.purchaseId,
    this.paymentId,
    this.fundingSourceName = '',
    this.partnerName,
    this.reference = '',
    this.status = 'active',
    this.cancelReason,
    this.cancelledByEmployeeName,
    this.cancelledAt,
  });

  final DateTime date;
  final String type;
  final String folio;
  final double charge;
  final double credit;
  final double balance;
  final String method;
  final String notes;
  final DateTime? dueDate;
  final String supplierName;
  final String? purchaseId;
  final String? paymentId;
  final String fundingSourceName;
  final String? partnerName;
  final String reference;
  final String status;
  final String? cancelReason;
  final String? cancelledByEmployeeName;
  final DateTime? cancelledAt;
}

class Partner {
  const Partner({
    required this.id,
    required this.name,
    required this.active,
    this.ownershipPercent = 0,
    this.phone = '',
    this.pin = '',
    this.linkedEmployeeId = '',
    this.linkedEmployeeName = '',
    this.notes = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final bool active;
  final double ownershipPercent;
  final String phone;
  final String pin;
  final String linkedEmployeeId;
  final String linkedEmployeeName;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Partner.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Partner(
      id: doc.id,
      name: data['name'] as String? ?? 'Socio',
      active: data['active'] as bool? ?? true,
      ownershipPercent: _toDouble(data['ownershipPercent']),
      phone: data['phone'] as String? ?? '',
      pin: data['pin'] as String? ?? '',
      linkedEmployeeId: data['linkedEmployeeId'] as String? ?? '',
      linkedEmployeeName: data['linkedEmployeeName'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }
}

class PartnerContribution {
  const PartnerContribution({
    required this.id,
    required this.partnerId,
    required this.partnerName,
    required this.date,
    required this.amount,
    required this.method,
    this.reference = '',
    this.notes = '',
    this.linkedSupplierPaymentId,
    this.supplierId,
    this.supplierName,
    this.purchaseId,
    this.purchaseFolio,
    this.restaurantId = AppConstants.restaurantId,
    this.restaurantName = AppConstants.restaurantName,
    this.branchId = AppConstants.defaultBranchId,
    this.branchName = AppConstants.defaultBranchName,
    this.createdByEmployeeId = '',
    this.createdByEmployeeName = '',
    this.status = 'active',
    this.cancelledAt,
    this.cancelledByEmployeeId,
    this.cancelledByEmployeeName,
    this.cancelReason,
    this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String branchId;
  final String branchName;
  final String partnerId;
  final String partnerName;
  final DateTime date;
  final double amount;
  final String method;
  final String reference;
  final String notes;
  final String? linkedSupplierPaymentId;
  final String? supplierId;
  final String? supplierName;
  final String? purchaseId;
  final String? purchaseFolio;
  final String createdByEmployeeId;
  final String createdByEmployeeName;
  final String status;
  final DateTime? cancelledAt;
  final String? cancelledByEmployeeId;
  final String? cancelledByEmployeeName;
  final String? cancelReason;
  final DateTime? createdAt;

  bool get isActive => status == 'active' && cancelledAt == null;
  bool get isCancelled => status == 'cancelled' || cancelledAt != null;

  factory PartnerContribution.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return PartnerContribution(
      id: doc.id,
      restaurantId:
          data['restaurantId'] as String? ?? AppConstants.restaurantId,
      restaurantName:
          data['restaurantName'] as String? ?? AppConstants.restaurantName,
      branchId: data['branchId'] as String? ?? AppConstants.defaultBranchId,
      branchName:
          data['branchName'] as String? ?? AppConstants.defaultBranchName,
      partnerId: data['partnerId'] as String? ?? '',
      partnerName: data['partnerName'] as String? ?? 'Socio',
      date:
          _toDate(data['date']) ?? _toDate(data['createdAt']) ?? DateTime.now(),
      amount: _toDouble(data['amount']),
      method: data['method'] as String? ?? 'cash',
      reference: data['reference'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      linkedSupplierPaymentId: data['linkedSupplierPaymentId'] as String?,
      supplierId: data['supplierId'] as String?,
      supplierName: data['supplierName'] as String?,
      purchaseId: data['purchaseId'] as String?,
      purchaseFolio: data['purchaseFolio'] as String?,
      createdByEmployeeId: data['createdByEmployeeId'] as String? ?? '',
      createdByEmployeeName: data['createdByEmployeeName'] as String? ?? '',
      status: data['status'] as String? ?? 'active',
      cancelledAt: _toDate(data['cancelledAt']),
      cancelledByEmployeeId: data['cancelledByEmployeeId'] as String?,
      cancelledByEmployeeName: data['cancelledByEmployeeName'] as String?,
      cancelReason: data['cancelReason'] as String?,
      createdAt: _toDate(data['createdAt']),
    );
  }
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
    this.supplierPurchaseItemId,
    this.purchaseItemId,
    this.kitchenStockItemId,
    this.kitchenStockItemName,
    this.affectsKitchenStock = false,
    this.notes = '',
  });

  final String? supplierPurchaseItemId;
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
  if (value is String) {
    final clean = value.trim();
    if (clean.isEmpty) return null;
    return DateTime.tryParse(clean);
  }
  return null;
}

double _toDouble(Object? value) {
  if (value is String) {
    return double.tryParse(value.trim().replaceAll(',', '')) ?? 0;
  }
  return value is num ? value.toDouble() : 0;
}
