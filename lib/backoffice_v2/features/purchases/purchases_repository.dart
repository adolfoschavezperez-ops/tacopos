import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/order.dart';
import '../../../models/purchase_models.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/preview/preview_api_client.dart';
import '../../core/read_only_guard.dart';
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
  PurchasesRepository({
    FirebaseFirestore? firestore,
    PreviewApiClient? previewClient,
    this.isReadOnly = false,
  }) : _dbOverride = firestore,
       _previewClient = previewClient;

  final FirebaseFirestore? _dbOverride;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  final PreviewApiClient? _previewClient;
  final bool isReadOnly;

  Future<PurchasesDashboardData> loadDashboard({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    required String prevStartBusinessDate,
    required String prevEndBusinessDate,
    String? branchId,
    required Map<String, String> branchNames,
  }) async {
    final preview = _previewClient;
    if (preview != null) {
      final results = await Future.wait([
        preview.queryAllPages(
          restaurantId: restaurantId,
          collection: 'suppliers',
          maxDocs: 200,
        ),
        preview.queryAllPages(
          restaurantId: restaurantId,
          collection: 'purchaseItems',
          maxDocs: 500,
        ),
        preview.queryAllPages(
          restaurantId: restaurantId,
          collection: 'supplierPurchases',
          branchId: branchId,
          startBusinessDate: startBusinessDate,
          endBusinessDate: endBusinessDate,
          maxDocs: 500,
        ),
        preview.queryAllPages(
          restaurantId: restaurantId,
          collection: 'supplierPurchases',
          branchId: branchId,
          startBusinessDate: prevStartBusinessDate,
          endBusinessDate: prevEndBusinessDate,
          maxDocs: 500,
        ),
        preview.queryAllPages(
          restaurantId: restaurantId,
          collection: 'supplierPayments',
          branchId: branchId,
          startBusinessDate: startBusinessDate,
          endBusinessDate: endBusinessDate,
          maxDocs: 500,
        ),
        preview.queryAllPages(
          restaurantId: restaurantId,
          collection: 'supplierPurchases',
          branchId: branchId,
          statusFilter: 'pending',
          maxDocs: 250,
        ),
        preview.queryAllPages(
          restaurantId: restaurantId,
          collection: 'supplierPurchases',
          branchId: branchId,
          statusFilter: 'partial',
          maxDocs: 250,
        ),
        preview.queryAllPages(
          restaurantId: restaurantId,
          collection: 'orders',
          branchId: branchId,
          startBusinessDate: startBusinessDate,
          endBusinessDate: endBusinessDate,
          maxDocs: 600,
        ),
        preview.queryAllPages(
          restaurantId: restaurantId,
          collection: 'orders',
          branchId: branchId,
          startBusinessDate: prevStartBusinessDate,
          endBusinessDate: prevEndBusinessDate,
          maxDocs: 600,
        ),
      ]);

      final suppliers = results[0].docs.map(Supplier.fromDoc).toList(growable: false)
        ..sort((a, b) => a.commercialName.compareTo(b.commercialName));
      final catalogItems = results[1].docs.map(PurchaseItem.fromDoc).toList(growable: false)
        ..sort((a, b) => a.name.compareTo(b.name));
      final currentPurchases = results[2].docs.map(SupplierPurchase.fromDoc).toList(growable: false);
      final previousPurchases = results[3].docs.map(SupplierPurchase.fromDoc).toList(growable: false);
      final payments = results[4].docs.map(SupplierPayment.fromDoc).toList(growable: false);
      final openPayables = [
        ...results[5].docs.map(SupplierPurchase.fromDoc),
        ...results[6].docs.map(SupplierPurchase.fromDoc),
      ];
      final currentOrders = results[7].docs.map(PosOrder.fromDoc).toList(growable: false);
      final prevOrders = results[8].docs.map(PosOrder.fromDoc).toList(growable: false);
      final currentNetSales = currentOrders
          .where((o) => o.status.trim().toLowerCase() != 'cancelled')
          .fold<double>(0.0, (a, o) => a + o.total);
      final previousNetSales = prevOrders
          .where((o) => o.status.trim().toLowerCase() != 'cancelled')
          .fold<double>(0.0, (a, o) => a + o.total);

      final currentItemsByPurchase = <String, List<SupplierPurchaseItem>>{};
      final previousItemsByPurchase = <String, List<SupplierPurchaseItem>>{};
      var itemReads = 0;
      for (final p in currentPurchases) {
        final itemRes = await preview.queryAllPages(
          restaurantId: restaurantId,
          collection: 'supplierPurchases',
          parentDocId: p.id,
          subcollection: 'items',
          maxDocs: 100,
        );
        itemReads += itemRes.dataReads;
        currentItemsByPurchase[p.id] = itemRes.docs
            .map(SupplierPurchaseItem.fromDoc)
            .toList(growable: false);
      }
      for (final p in previousPurchases) {
        final itemRes = await preview.queryAllPages(
          restaurantId: restaurantId,
          collection: 'supplierPurchases',
          parentDocId: p.id,
          subcollection: 'items',
          maxDocs: 100,
        );
        itemReads += itemRes.dataReads;
        previousItemsByPurchase[p.id] = itemRes.docs
            .map(SupplierPurchaseItem.fromDoc)
            .toList(growable: false);
      }

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

      final readCount =
          results.fold<int>(0, (a, r) => a + r.dataReads) + itemReads;
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
        readCount: readCount,
      );
    }
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
    final preview = _previewClient;
    if (preview != null) {
      final docSnap = await preview.fetchDoc(
        restaurantId: restaurantId,
        collection: 'supplierPurchases',
        docId: purchaseId,
      );
      if (docSnap == null || !docSnap.exists) return null;
      final itemsRes = await preview.queryAllPages(
        restaurantId: restaurantId,
        collection: 'supplierPurchases',
        parentDocId: purchaseId,
        subcollection: 'items',
        maxDocs: 200,
      );
      return PurchaseDetailData(
        purchase: SupplierPurchase.fromDoc(docSnap),
        items: itemsRes.docs
            .map(SupplierPurchaseItem.fromDoc)
            .toList(growable: false),
        payments: const [],
      );
    }

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
    BackofficeReadOnlyGuard.assertWritable(
      isReadOnly: isReadOnly,
      action: 'Operación de compras/proveedores',
    );
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
        'fundingSourceName': _paymentMethodLabel(method),
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

  static String _paymentMethodLabel(String method) {
    return switch (method.trim().toLowerCase()) {
      'cash' => 'Efectivo',
      'partner_contribution' => 'Aportación de socios',
      _ => 'Transferencia',
    };
  }

  Future<void> savePurchaseItem({
    required String restaurantId,
    String? itemId,
    required String name,
    required String category,
    required String unit,
    required bool active,
    String? defaultSupplierId,
    String? defaultSupplierName,
    String notes = '',
  }) async {
    final ref = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('purchaseItems');
    final isNew = itemId == null || itemId.trim().isEmpty;
    final docRef = isNew ? ref.doc() : ref.doc(itemId.trim());
    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'category': category.trim().isEmpty ? 'General' : category.trim(),
      'unit': unit.trim().isEmpty ? 'kg' : unit.trim(),
      'active': active,
      'defaultSupplierId': defaultSupplierId,
      'defaultSupplierName': defaultSupplierName,
      'notes': notes.trim(),
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> createMultiLinePurchase({
    required String restaurantId,
    required String restaurantName,
    required String branchId,
    required String branchName,
    required Supplier supplier,
    required String folio,
    required String documentType,
    required DateTime purchaseDate,
    DateTime? dueDate,
    required List<({PurchaseItem item, double quantity, double lineTotal})> lines,
    required bool markPaidImmediately,
    required String paymentMethod,
    required String notes,
    required String employeeId,
    required String employeeName,
  }) async {
    BackofficeReadOnlyGuard.assertWritable(
      isReadOnly: isReadOnly,
      action: 'Operación de compras/proveedores',
    );
    if (lines.isEmpty) {
      throw ArgumentError('Agrega al menos una partida.');
    }
    final purchasesRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('supplierPurchases');
    final docRef = purchasesRef.doc();
    final businessDate = BackofficeSalesAdapter.formatBusinessDate(purchaseDate);

    final cleanTotal = double.parse(
      lines.fold<double>(0.0, (acc, l) => acc + l.lineTotal).toStringAsFixed(2),
    );
    final paidTotal = markPaidImmediately ? cleanTotal : 0.0;
    final balance = markPaidImmediately ? 0.0 : cleanTotal;
    final status = markPaidImmediately ? 'paid' : 'pending';

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

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineTotal = double.parse(line.lineTotal.toStringAsFixed(2));
      final lineTotalCents = (lineTotal * 100).round();
      final unitCost = line.quantity > 0 ? lineTotal / line.quantity : 0.0;
      final lineId = 'line_${i + 1}';
      batch.set(docRef.collection('items').doc(lineId), {
        'id': lineId,
        'purchaseItemId': line.item.id,
        'purchaseItemName': line.item.name,
        'kitchenStockItemId': line.item.kitchenStockItemId,
        'kitchenStockItemName': line.item.kitchenStockItemName,
        'affectsKitchenStock': line.item.affectsKitchenStock,
        'quantity': line.quantity,
        'unit': line.item.unit,
        'unitCost': unitCost,
        'unitCostCalculated': unitCost,
        'total': lineTotal,
        'lineTotal': lineTotal,
        'lineTotalCents': lineTotalCents,
        'calculationMode': 'line_total',
        'status': 'active',
        'notes': notes.trim(),
      });
    }

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
        'fundingSourceName': _paymentMethodLabel(paymentMethod),
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

  /// Cancels a supplier purchase only if it has no active payments,
  /// preserving TacoPosRepository.cancelSupplierPurchase parity + audit log.
  Future<void> cancelSupplierPurchase({
    required String restaurantId,
    required SupplierPurchase purchase,
    required String reason,
    required String employeeId,
    required String employeeName,
  }) async {
    BackofficeReadOnlyGuard.assertWritable(
      isReadOnly: isReadOnly,
      action: 'Cancelación de compra/pago',
    );
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Captura el motivo de cancelación.');
    }

    final purchaseRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('supplierPurchases')
        .doc(purchase.id);
    final paymentsSnap = await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('supplierPayments')
        .where('purchaseId', isEqualTo: purchase.id)
        .get();
    final hasActivePayments = paymentsSnap.docs
        .map(SupplierPayment.fromDoc)
        .any((p) => p.isActive);
    if (hasActivePayments) {
      throw StateError(
        'No puedes cancelar esta compra porque tiene pagos activos. Cancela primero los pagos.',
      );
    }

    final logRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('activityLog')
        .doc();
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.update(purchaseRef, {
      'status': 'cancelled',
      'balance': 0.0,
      'cancelledAt': now,
      'cancelledByEmployeeId': employeeId,
      'cancelledByEmployeeName': employeeName,
      'cancelReason': cleanReason,
      'updatedAt': now,
    });
    batch.set(logRef, {
      'id': logRef.id,
      'restaurantId': restaurantId,
      'branchId': purchase.branchId,
      'branchName': purchase.branchName,
      'type': 'supplier_purchase_cancelled',
      'actionType': 'supplier_purchase_cancelled',
      'purchaseId': purchase.id,
      'purchaseFolio': purchase.folio,
      'amount': purchase.total,
      'cancelReason': cleanReason,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'message':
          'Canceló compra ${purchase.folio} de ${purchase.supplierName} (\$${purchase.total.toStringAsFixed(2)})',
      'timestamp': now,
      'createdAt': now,
    });
    await batch.commit();
  }

  /// Atomically cancels a supplier payment and recalculates purchase paidTotal/balance/status.
  Future<void> cancelSupplierPayment({
    required String restaurantId,
    required SupplierPayment payment,
    required String reason,
    required String employeeId,
    required String employeeName,
  }) async {
    BackofficeReadOnlyGuard.assertWritable(
      isReadOnly: isReadOnly,
      action: 'Cancelación de compra/pago',
    );
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Captura el motivo de cancelación.');
    }

    final paymentRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('supplierPayments')
        .doc(payment.id);
    final purchaseRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('supplierPurchases')
        .doc(payment.purchaseId);
    final relatedPaymentsSnap = await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('supplierPayments')
        .where('purchaseId', isEqualTo: payment.purchaseId)
        .get();
    final logRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('activityLog')
        .doc();

    await _db.runTransaction((tx) async {
      final paySnap = await tx.get(paymentRef);
      final purSnap = await tx.get(purchaseRef);
      if (!paySnap.exists) throw StateError('El pago ya no existe.');
      if (!purSnap.exists) throw StateError('La compra ya no existe.');

      final currentPay = SupplierPayment.fromDoc(paySnap);
      if (currentPay.isCancelled) {
        throw StateError('Este pago ya fue cancelado.');
      }

      var activePaidTotal = 0.0;
      for (final pDoc in relatedPaymentsSnap.docs) {
        if (pDoc.id == payment.id) continue;
        final fresh = await tx.get(pDoc.reference);
        if (fresh.exists) {
          final p = SupplierPayment.fromDoc(fresh);
          if (p.isActive) activePaidTotal += p.amount;
        }
      }

      final purchase = SupplierPurchase.fromDoc(purSnap);
      final nextBalance = (purchase.total - activePaidTotal).clamp(
        0.0,
        double.infinity,
      );
      final nextStatus = purchase.isCancelled
          ? 'cancelled'
          : activePaidTotal <= 0.01
          ? 'pending'
          : nextBalance <= 0.01
          ? 'paid'
          : 'partial';

      final now = FieldValue.serverTimestamp();
      tx.update(paymentRef, {
        'status': 'cancelled',
        'cancelledAt': now,
        'cancelledByEmployeeId': employeeId,
        'cancelledByEmployeeName': employeeName,
        'cancelReason': cleanReason,
        'updatedAt': now,
      });
      tx.update(purchaseRef, {
        'paidTotal': activePaidTotal,
        'balance': nextBalance <= 0.01 ? 0.0 : nextBalance,
        'status': nextStatus,
        'updatedAt': now,
      });
      tx.set(logRef, {
        'id': logRef.id,
        'restaurantId': restaurantId,
        'branchId': purchase.branchId,
        'branchName': purchase.branchName,
        'type': 'supplier_payment_cancelled',
        'actionType': 'supplier_payment_cancelled',
        'paymentId': payment.id,
        'purchaseId': purchase.id,
        'purchaseFolio': purchase.folio,
        'amount': payment.amount,
        'cancelReason': cleanReason,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'message':
            'Canceló pago de \$${payment.amount.toStringAsFixed(2)} en compra ${purchase.folio}',
        'timestamp': now,
        'createdAt': now,
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
