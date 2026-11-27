import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/order.dart';
import '../../../models/purchase_models.dart';
import '../../core/adapters/sales_adapter.dart';
import 'purchases_analytics.dart';

class PurchasesCursorPage {
  const PurchasesCursorPage({
    required this.purchases,
    required this.lastDocument,
    required this.hasNext,
  });

  final List<SupplierPurchase> purchases;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasNext;
}

class PurchaseDetailData {
  const PurchaseDetailData({
    required this.purchase,
    required this.items,
    required this.payments,
  });

  final SupplierPurchase purchase;
  final List<SupplierPurchaseItem> items;
  final List<SupplierPayment> payments;
}

class PurchasesDashboardData {
  const PurchasesDashboardData({
    required this.suppliers,
    required this.catalogItems,
    required this.currentPurchases,
    required this.previousPurchases,
    required this.currentItemsByPurchase,
    required this.previousItemsByPurchase,
    required this.payments,
    required this.openPayables,
    required this.metrics,
    required this.accountsPayable,
    required this.currentNetSales,
    required this.previousNetSales,
    required this.readCount,
  });

  final List<Supplier> suppliers;
  final List<PurchaseItem> catalogItems;
  final List<SupplierPurchase> currentPurchases;
  final List<SupplierPurchase> previousPurchases;
  final Map<String, List<SupplierPurchaseItem>> currentItemsByPurchase;
  final Map<String, List<SupplierPurchaseItem>> previousItemsByPurchase;
  final List<SupplierPayment> payments;
  final List<SupplierPurchase> openPayables;
  final PurchasesDashboardMetrics metrics;
  final AccountsPayableSummary accountsPayable;
  final double currentNetSales;
  final double previousNetSales;
  final int readCount;
}

/// Multi-tenant & multi-branch safe Purchases, Suppliers & CXP Repository.
///
/// Strictly scoped to `restaurants/{restaurantId}` with bounded queries,
/// cursor pagination, and Android-compatible document writes (DEV-safe).
class PurchasesRepository {
  PurchasesRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<PurchasesDashboardData> loadDashboard({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    required String prevStartBusinessDate,
    required String prevEndBusinessDate,
    String? branchId,
    required Map<String, String> branchNames,
  }) async {
    final suppliersQuery = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('suppliers')
        .orderBy('commercialName')
        .limit(200);

    final catalogQuery = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('purchaseItems')
        .orderBy('name')
        .limit(300);

    final currentPurchasesQuery = _buildPurchasesQuery(
      restaurantId: restaurantId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      branchId: branchId,
    ).limit(300);

    final prevPurchasesQuery = _buildPurchasesQuery(
      restaurantId: restaurantId,
      startBusinessDate: prevStartBusinessDate,
      endBusinessDate: prevEndBusinessDate,
      branchId: branchId,
    ).limit(300);

    Query<Map<String, dynamic>> paymentsQuery = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('supplierPayments')
        .where('businessDate', isGreaterThanOrEqualTo: startBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: endBusinessDate)
        .orderBy('businessDate', descending: true);
    if (branchId != null && branchId.isNotEmpty) {
      paymentsQuery = paymentsQuery.where('branchId', isEqualTo: branchId);
    }

    Query<Map<String, dynamic>> pendingQuery = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('supplierPurchases')
        .where('status', whereIn: const ['pending', 'partial']);
    if (branchId != null && branchId.isNotEmpty) {
      pendingQuery = pendingQuery.where('branchId', isEqualTo: branchId);
    }

    final currentOrdersQuery = _buildOrdersQuery(
      restaurantId: restaurantId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      branchId: branchId,
    ).limit(600);

    final prevOrdersQuery = _buildOrdersQuery(
      restaurantId: restaurantId,
      startBusinessDate: prevStartBusinessDate,
      endBusinessDate: prevEndBusinessDate,
      branchId: branchId,
    ).limit(600);

    final results = await Future.wait([
      suppliersQuery.get(),
      catalogQuery.get(),
      currentPurchasesQuery.get(),
      prevPurchasesQuery.get(),
      paymentsQuery.limit(250).get(),
      pendingQuery.limit(200).get(),
      currentOrdersQuery.get(),
      prevOrdersQuery.get(),
    ]);

    final suppliers = results[0].docs
        .map(Supplier.fromDoc)
        .toList(growable: false);
    final catalogItems = results[1].docs
        .map(PurchaseItem.fromDoc)
        .toList(growable: false);
    final currentPurchases = results[2].docs
        .map(SupplierPurchase.fromDoc)
        .toList(growable: false);
    final previousPurchases = results[3].docs
        .map(SupplierPurchase.fromDoc)
        .toList(growable: false);
    final payments = results[4].docs
        .map(SupplierPayment.fromDoc)
        .toList(growable: false);
    final openPayables = results[5].docs
        .map(SupplierPurchase.fromDoc)
        .toList(growable: false);

    final currentOrders = results[6].docs
        .map(PosOrder.fromDoc)
        .where((o) => o.status != 'cancelled')
        .toList(growable: false);
    final prevOrders = results[7].docs
        .map(PosOrder.fromDoc)
        .where((o) => o.status != 'cancelled')
        .toList(growable: false);

    final currentNetSales = currentOrders.fold<double>(
      0.0,
      (acc, o) => acc + o.total,
    );
    final previousNetSales = prevOrders.fold<double>(
      0.0,
      (acc, o) => acc + o.total,
    );

    final itemLoads = await Future.wait([
      _fetchPurchaseItemsBatch(results[2].docs),
      _fetchPurchaseItemsBatch(results[3].docs),
    ]);

    final currentItemsByPurchase = itemLoads[0].items;
    final previousItemsByPurchase = itemLoads[1].items;

    final metrics = PurchasesAnalytics.computeDashboard(
      currentPurchases: currentPurchases,
      previousPurchases: previousPurchases,
      currentItemsByPurchase: currentItemsByPurchase,
      previousItemsByPurchase: previousItemsByPurchase,
      catalogItems: catalogItems,
      branchNames: branchNames,
    );

    final accountsPayable = PurchasesAnalytics.computeAccountsPayable(
      purchases: openPayables,
    );

    final baseReads = results.fold<int>(0, (acc, s) => acc + s.docs.length);

    return PurchasesDashboardData(
      suppliers: suppliers,
      catalogItems: catalogItems,
      currentPurchases: currentPurchases,
      previousPurchases: previousPurchases,
      currentItemsByPurchase: currentItemsByPurchase,
      previousItemsByPurchase: previousItemsByPurchase,
      payments: payments,
      openPayables: openPayables,
      metrics: metrics,
      accountsPayable: accountsPayable,
      currentNetSales: currentNetSales,
      previousNetSales: previousNetSales,
      readCount: baseReads + itemLoads[0].reads + itemLoads[1].reads,
    );
  }

  Future<PurchasesCursorPage> fetchPurchasesPage({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
    String? statusFilter,
    String? supplierId,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int pageSize = 20,
  }) async {
    var query = _buildPurchasesQuery(
      restaurantId: restaurantId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      branchId: branchId,
      statusFilter: statusFilter,
      supplierId: supplierId,
    );
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    final snapshot = await query.limit(pageSize + 1).get();
    final hasNext = snapshot.docs.length > pageSize;
    final docs = hasNext
        ? snapshot.docs.take(pageSize).toList(growable: false)
        : snapshot.docs;
    return PurchasesCursorPage(
      purchases: docs.map(SupplierPurchase.fromDoc).toList(growable: false),
      lastDocument: docs.isEmpty ? null : docs.last,
      hasNext: hasNext,
    );
  }

  Future<List<SupplierPurchase>> exportAllPurchasesInRange({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
    String? statusFilter,
    String? supplierId,
    int pageSize = 200,
    void Function(int loadedCount)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final baseQuery = _buildPurchasesQuery(
      restaurantId: restaurantId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      branchId: branchId,
      statusFilter: statusFilter,
      supplierId: supplierId,
    );
    final all = <SupplierPurchase>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      if (isCancelled?.call() == true) break;
      final q = cursor != null
          ? baseQuery.startAfterDocument(cursor)
          : baseQuery;
      final snap = await q.limit(pageSize + 1).get();
      final hasMore = snap.docs.length > pageSize;
      final docs = hasMore
          ? snap.docs.take(pageSize).toList(growable: false)
          : snap.docs;
      all.addAll(docs.map(SupplierPurchase.fromDoc));
      onProgress?.call(all.length);
      if (!hasMore || docs.isEmpty) break;
      cursor = docs.last;
    }
    return all;
  }

  Future<PurchaseDetailData?> loadPurchaseDetail({
    required String restaurantId,
    required String purchaseId,
  }) async {
    final docRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('supplierPurchases')
        .doc(purchaseId);
    final docSnap = await docRef.get();
    if (!docSnap.exists) return null;

    final purchase = SupplierPurchase.fromDoc(docSnap);
    final results = await Future.wait([
      docRef.collection('items').get(),
      _db
          .collection('restaurants')
          .doc(restaurantId)
          .collection('supplierPayments')
          .where('purchaseId', isEqualTo: purchaseId)
          .limit(50)
          .get(),
    ]);

    return PurchaseDetailData(
      purchase: purchase,
      items: results[0].docs
          .map(SupplierPurchaseItem.fromDoc)
          .toList(growable: false),
      payments: results[1].docs
          .map(SupplierPayment.fromDoc)
          .toList(growable: false),
    );
  }

  Future<void> saveSupplier({
    required String restaurantId,
    String? supplierId,
    required String commercialName,
    String legalName = '',
    String rfc = '',
    String phone = '',
    String contactName = '',
    String address = '',
    String notes = '',
    required bool active,
    required String preferredPaymentMethod,
    required int creditDays,
    required String paymentWeekday,
    required String paymentWeekdayName,
    required String employeeId,
    required String employeeName,
  }) async {
    final ref = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('suppliers');
    final isNew = supplierId == null || supplierId.trim().isEmpty;
    final docRef = isNew ? ref.doc() : ref.doc(supplierId.trim());
    await docRef.set({
      'id': docRef.id,
      'commercialName': commercialName.trim(),
      'legalName': legalName.trim(),
      'rfc': rfc.trim(),
      'phone': phone.trim(),
      'contactName': contactName.trim(),
      'address': address.trim(),
      'notes': notes.trim(),
      'active': active,
      'preferredPaymentMethod': preferredPaymentMethod,
      'creditDays': creditDays < 0 ? 0 : creditDays,
      'paymentWeekday': paymentWeekday,
      'paymentWeekdayName': paymentWeekdayName,
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      if (isNew) 'createdByEmployeeId': employeeId,
      if (isNew) 'createdByEmployeeName': employeeName,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmployeeId': employeeId,
      'updatedByEmployeeName': employeeName,
    }, SetOptions(merge: true));
  }

  Future<void> createPurchase({
    required String restaurantId,
    required String restaurantName,
    required String branchId,
    required String branchName,
    required Supplier supplier,
    required String folio,
    required String documentType,
    required DateTime purchaseDate,
    DateTime? dueDate,
    required PurchaseItem item,
    required double quantity,
    required double lineTotal,
    required bool markPaidImmediately,
    required String paymentMethod,
    required String notes,
    required String employeeId,
    required String employeeName,
  }) async {
    final purchasesRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('supplierPurchases');
    final docRef = purchasesRef.doc();
    final businessDate = BackofficeSalesAdapter.formatBusinessDate(purchaseDate);
    final cleanTotal = double.parse(lineTotal.toStringAsFixed(2));
    final paidTotal = markPaidImmediately ? cleanTotal : 0.0;
    final balance = markPaidImmediately ? 0.0 : cleanTotal;
    final status = markPaidImmediately ? 'paid' : 'pending';
    final lineTotalCents = (cleanTotal * 100).round();
    final unitCost = quantity > 0 ? cleanTotal / quantity : 0.0;

    final batch = _db.batch();
    batch.set(docRef, {
      'id': docRef.id,
      'restaurantId': restaurantId,
      'restaurantName': restaurantName,
      'branchId': branchId,
      'branchName': branchName,
      'supplierId': supplier.id,
      'supplierName': supplier.commercialName,
      'purchaseDate': Timestamp.fromDate(purchaseDate),
      'businessDate': businessDate,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate) : null,
      'paymentWeekdaySnapshot': supplier.paymentWeekday,
      'paymentWeekdayNameSnapshot': supplier.paymentWeekdayName,
      'folio': folio.trim(),
      'documentType': documentType,
      'status': status,
      'subtotal': cleanTotal,
      'total': cleanTotal,
      'paidTotal': paidTotal,
      'balance': balance,
      'notes': notes.trim(),
      'createdByEmployeeId': employeeId,
      'createdByEmployeeName': employeeName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final itemRef = docRef.collection('items').doc('line_1');
    batch.set(itemRef, {
      'id': 'line_1',
      'purchaseItemId': item.id,
      'purchaseItemName': item.name,
      'kitchenStockItemId': item.kitchenStockItemId,
      'kitchenStockItemName': item.kitchenStockItemName,
      'affectsKitchenStock': item.affectsKitchenStock,
      'quantity': quantity,
      'unit': item.unit,
      'unitCost': unitCost,
      'unitCostCalculated': unitCost,
      'total': cleanTotal,
      'lineTotal': cleanTotal,
      'lineTotalCents': lineTotalCents,
      'calculationMode': 'line_total',
      'status': 'active',
      'notes': notes.trim(),
    });

    if (markPaidImmediately && cleanTotal > 0) {
      final paymentRef = _db
          .collection('restaurants')
          .doc(restaurantId)
          .collection('supplierPayments')
          .doc();
      batch.set(paymentRef, {
        'id': paymentRef.id,
        'restaurantId': restaurantId,
        'restaurantName': restaurantName,
        'branchId': branchId,
        'branchName': branchName,
        'supplierId': supplier.id,
        'supplierName': supplier.commercialName,
        'purchaseId': docRef.id,
        'purchaseFolio': folio.trim(),
        'paymentDate': Timestamp.fromDate(purchaseDate),
        'businessDate': businessDate,
        'amount': cleanTotal,
        'method': paymentMethod,
        'fundingSource': paymentMethod,
        'fundingSourceName': paymentMethod == 'cash'
            ? 'Efectivo'
            : 'Transferencia',
        'reference': '',
        'notes': 'Pago al registrar compra',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'createdByEmployeeId': employeeId,
        'createdByEmployeeName': employeeName,
      });
    }

    await batch.commit();
  }

  Future<void> registerPayment({
    required String restaurantId,
    required String restaurantName,
    required SupplierPurchase purchase,
    required double amount,
    required String method,
    required String reference,
    required String notes,
    required String employeeId,
    required String employeeName,
  }) async {
    if (purchase.isCancelled) {
      throw StateError('No puedes pagar una compra cancelada.');
    }
    if (amount <= 0 || amount > purchase.balance + 0.01) {
      throw ArgumentError('El monto debe ser mayor a cero y menor o igual al saldo pendiente.');
    }

    final purchaseRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('supplierPurchases')
        .doc(purchase.id);
    final paymentRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('supplierPayments')
        .doc();

    final now = DateTime.now();
    final businessDate = BackofficeSalesAdapter.formatBusinessDate(now);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(purchaseRef);
      if (!snap.exists) {
        throw StateError('No se encontró el documento de compra.');
      }
      final latest = SupplierPurchase.fromDoc(snap);
      if (latest.isCancelled || !latest.hasBalance) {
        throw StateError('Esta compra ya fue liquidada o cancelada.');
      }
      if (amount > latest.balance + 0.01) {
        throw StateError('El saldo actual es menor al monto ingresado.');
      }

      final nextPaid = latest.paidTotal + amount;
      final nextBalance = (latest.total - nextPaid).clamp(0.0, double.infinity);
      final nextStatus = nextBalance <= 0.01 ? 'paid' : 'partial';

      tx.set(paymentRef, {
        'id': paymentRef.id,
        'restaurantId': restaurantId,
        'restaurantName': restaurantName,
        'branchId': latest.branchId,
        'branchName': latest.branchName,
        'supplierId': latest.supplierId,
        'supplierName': latest.supplierName,
        'purchaseId': latest.id,
        'purchaseFolio': latest.folio,
        'paymentDate': Timestamp.fromDate(now),
        'businessDate': businessDate,
        'amount': amount,
        'method': method,
        'fundingSource': method,
        'fundingSourceName': method == 'cash' ? 'Efectivo' : 'Transferencia',
        'reference': reference.trim(),
        'notes': notes.trim(),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'createdByEmployeeId': employeeId,
        'createdByEmployeeName': employeeName,
      });

      tx.update(purchaseRef, {
        'paidTotal': nextPaid,
        'balance': nextBalance <= 0.01 ? 0.0 : nextBalance,
        'status': nextStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Query<Map<String, dynamic>> _buildPurchasesQuery({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
    String? statusFilter,
    String? supplierId,
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('supplierPurchases')
        .where('businessDate', isGreaterThanOrEqualTo: startBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: endBusinessDate)
        .orderBy('businessDate', descending: true);

    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }
    if (statusFilter != null && statusFilter.isNotEmpty) {
      query = query.where('status', isEqualTo: statusFilter);
    }
    if (supplierId != null && supplierId.isNotEmpty) {
      query = query.where('supplierId', isEqualTo: supplierId);
    }
    return query;
  }

  Query<Map<String, dynamic>> _buildOrdersQuery({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('orders')
        .where('businessDate', isGreaterThanOrEqualTo: startBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: endBusinessDate)
        .orderBy('businessDate', descending: true);

    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }
    return query;
  }

  Future<({Map<String, List<SupplierPurchaseItem>> items, int reads})>
  _fetchPurchaseItemsBatch(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final map = <String, List<SupplierPurchaseItem>>{};
    var reads = 0;
    const batchSize = 15;
    for (var i = 0; i < docs.length; i += batchSize) {
      final chunk = docs.sublist(i, (i + batchSize).clamp(0, docs.length));
      final snaps = await Future.wait(
        chunk.map((d) => d.reference.collection('items').get()),
      );
      for (var j = 0; j < chunk.length; j++) {
        reads += snaps[j].docs.length;
        map[chunk[j].id] = snaps[j].docs
            .map(SupplierPurchaseItem.fromDoc)
            .toList(growable: false);
      }
    }
    return (items: map, reads: reads);
  }
}
