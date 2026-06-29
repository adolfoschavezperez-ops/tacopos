import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/constants/app_constants.dart';
import '../models/employee.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../models/payment.dart';
import '../models/pos_table.dart';
import '../models/product.dart';

class KitchenOrderBundle {
  const KitchenOrderBundle({required this.order, required this.items});

  final PosOrder order;
  final List<OrderItem> items;

  int get personCount => items.map((item) => item.personNumber).toSet().length;

  String get shortSummary {
    final counts = <String, int>{};
    for (final item in items) {
      counts[item.productName] = (counts[item.productName] ?? 0) + item.qty;
    }

    return counts.entries
        .take(3)
        .map((entry) => '${entry.value} ${entry.key}')
        .join(' · ');
  }
}

class PaymentResult {
  const PaymentResult({required this.allPaid});

  final bool allPaid;
}

class TacoPosRepository {
  TacoPosRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  static const cardSurchargeRate = 0.04;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> get _restaurantRef =>
      _db.collection('restaurants').doc(AppConstants.restaurantId);

  CollectionReference<Map<String, dynamic>> get _tablesRef =>
      _restaurantRef.collection('tables');

  CollectionReference<Map<String, dynamic>> get _productsRef =>
      _restaurantRef.collection('products');

  CollectionReference<Map<String, dynamic>> get _employeesRef =>
      _restaurantRef.collection('employees');

  CollectionReference<Map<String, dynamic>> get _ordersRef =>
      _restaurantRef.collection('orders');

  Stream<List<PosTable>> watchTables({bool activeOnly = true}) {
    return _tablesRef.snapshots().map((snapshot) {
      final tables = snapshot.docs.map(PosTable.fromDoc).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return activeOnly
          ? tables.where((table) => table.active).toList()
          : tables;
    });
  }

  Stream<List<Product>> watchProducts({bool activeOnly = false}) {
    return _productsRef.snapshots().map((snapshot) {
      final products = snapshot.docs.map(Product.fromDoc).toList()
        ..sort((a, b) {
          final categoryCompare = a.category.compareTo(b.category);
          return categoryCompare != 0
              ? categoryCompare
              : a.sortOrder.compareTo(b.sortOrder);
        });
      return activeOnly
          ? products.where((product) => product.active).toList()
          : products;
    });
  }

  Stream<List<Employee>> watchEmployees({bool activeOnly = true}) {
    return _employeesRef.snapshots().map((snapshot) {
      final employees = snapshot.docs.map(Employee.fromDoc).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return activeOnly
          ? employees.where((employee) => employee.active).toList()
          : employees;
    });
  }

  Stream<List<PosOrder>> watchOpenOrders() {
    return _ordersRef.snapshots().map((snapshot) {
      final orders =
          snapshot.docs
              .map(PosOrder.fromDoc)
              .where((order) => order.status != 'paid')
              .toList()
            ..sort((a, b) {
              final aDate =
                  a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bDate =
                  b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });
      return orders;
    });
  }

  Stream<List<PosOrder>> watchAllOrders() {
    return _ordersRef.snapshots().map((snapshot) {
      final orders = snapshot.docs.map(PosOrder.fromDoc).toList()
        ..sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
      return orders;
    });
  }

  Stream<List<KitchenOrderBundle>> watchKitchenOrderBundles() {
    return _ordersRef.snapshots().asyncMap((snapshot) async {
      final orders = snapshot.docs
          .map(PosOrder.fromDoc)
          .where((order) => !['paid', 'cancelled'].contains(order.status))
          .toList();

      final bundles = <KitchenOrderBundle>[];
      for (final order in orders) {
        final items = await getActiveKitchenItems(order.id);
        if (items.isNotEmpty) {
          bundles.add(KitchenOrderBundle(order: order, items: items));
        }
      }

      bundles.sort((a, b) {
        final aDate =
            a.items
                .map((item) => item.sentToKitchenAt)
                .whereType<DateTime>()
                .fold<DateTime?>(
                  null,
                  (min, date) => min == null || date.isBefore(min) ? date : min,
                ) ??
            a.order.updatedAt ??
            a.order.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            b.items
                .map((item) => item.sentToKitchenAt)
                .whereType<DateTime>()
                .fold<DateTime?>(
                  null,
                  (min, date) => min == null || date.isBefore(min) ? date : min,
                ) ??
            b.order.updatedAt ??
            b.order.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return aDate.compareTo(bDate);
      });

      return bundles;
    });
  }

  Stream<PosOrder?> watchOrder(String orderId) {
    return _ordersRef.doc(orderId).snapshots().map((doc) {
      if (!doc.exists) {
        return null;
      }
      return PosOrder.fromDoc(doc);
    });
  }

  Stream<List<OrderItem>> watchOrderItems(String orderId) {
    return _ordersRef.doc(orderId).collection('items').snapshots().map((
      snapshot,
    ) {
      final items = snapshot.docs.map(OrderItem.fromDoc).toList()
        ..sort((a, b) {
          final personCompare = a.personNumber.compareTo(b.personNumber);
          return personCompare != 0
              ? personCompare
              : a.productName.compareTo(b.productName);
        });
      return items;
    });
  }

  Stream<List<OrderItem>> watchKitchenItems(String orderId) {
    return watchOrderItems(orderId).map(_activeKitchenItems);
  }

  Future<List<OrderItem>> getActiveKitchenItems(String orderId) async {
    final snapshot = await _ordersRef.doc(orderId).collection('items').get();
    return _activeKitchenItems(snapshot.docs.map(OrderItem.fromDoc).toList());
  }

  List<OrderItem> _activeKitchenItems(List<OrderItem> items) {
    return items
        .where(
          (item) =>
              item.sendToKitchen &&
              ['sent', 'cooking'].contains(item.kitchenStatus),
        )
        .toList()
      ..sort((a, b) {
        final personCompare = a.personNumber.compareTo(b.personNumber);
        return personCompare != 0
            ? personCompare
            : a.productName.compareTo(b.productName);
      });
  }

  Stream<List<Payment>> watchPayments() {
    return _db.collectionGroup('payments').snapshots().map((snapshot) {
      final payments = snapshot.docs.map(Payment.fromDoc).toList()
        ..sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
      return payments;
    });
  }

  Stream<List<Payment>> watchOrderPayments(String orderId) {
    return _ordersRef.doc(orderId).collection('payments').snapshots().map((
      snapshot,
    ) {
      final payments = snapshot.docs.map(Payment.fromDoc).toList()
        ..sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
      return payments;
    });
  }

  Future<PosOrder> createOrGetOpenOrder(PosTable table) async {
    final snapshot = await _ordersRef.get();
    final existing =
        snapshot.docs
            .map(PosOrder.fromDoc)
            .where(
              (order) =>
                  order.tableId == table.id &&
                  ['open', 'sent', 'ready'].contains(order.status),
            )
            .toList()
          ..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });

    if (existing.isNotEmpty) {
      return existing.first;
    }

    final orderRef = _ordersRef.doc();
    final data = {
      'tableId': table.id,
      'tableName': table.name,
      'status': 'open',
      'kitchenStatus': 'pending',
      'paymentStatus': 'pending',
      'total': 0.0,
      'paidTotal': 0.0,
      'pendingTotal': 0.0,
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = _db.batch();
    batch.set(orderRef, data);
    batch.set(_tablesRef.doc(table.id), {
      'status': 'occupied',
      'currentOrderId': orderRef.id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();

    final doc = await orderRef.get();
    return PosOrder.fromDoc(doc);
  }

  Future<void> addProductToOrder({
    required String orderId,
    required Product product,
    required int personNumber,
  }) async {
    final existingItem = await _findMatchingPendingItem(
      orderId: orderId,
      productId: product.id,
      personNumber: personNumber,
    );

    if (existingItem != null) {
      await updateItemQty(
        orderId: orderId,
        item: existingItem,
        qty: existingItem.qty + 1,
      );
      return;
    }

    final itemRef = _ordersRef.doc(orderId).collection('items').doc();
    await itemRef.set({
      'personNumber': personNumber,
      'personName': 'Persona $personNumber',
      'productId': product.id,
      'productName': product.name,
      'category': product.category,
      'qty': 1,
      'unitPrice': product.price,
      'total': product.price,
      'notes': '',
      'sendToKitchen': product.sendToKitchen,
      'kitchenStatus': product.sendToKitchen ? 'pending' : 'not_required',
      'kitchenBatchId': null,
      'paymentStatus': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await recalculateOrderTotal(orderId);
  }

  Future<OrderItem?> _findMatchingPendingItem({
    required String orderId,
    required String productId,
    required int personNumber,
  }) async {
    final snapshot = await _ordersRef.doc(orderId).collection('items').get();

    for (final doc in snapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.productId == productId &&
          item.personNumber == personNumber &&
          item.kitchenStatus == 'pending' &&
          item.paymentStatus == 'pending') {
        return item;
      }
    }
    return null;
  }

  Future<void> updateItemQty({
    required String orderId,
    required OrderItem item,
    required int qty,
  }) async {
    if (qty <= 0) {
      await deleteItem(orderId: orderId, itemId: item.id);
      return;
    }

    await _ordersRef.doc(orderId).collection('items').doc(item.id).update({
      'qty': qty,
      'total': qty * item.unitPrice,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await recalculateOrderTotal(orderId);
  }

  Future<void> deleteItem({
    required String orderId,
    required String itemId,
  }) async {
    await _ordersRef.doc(orderId).collection('items').doc(itemId).delete();
    await recalculateOrderTotal(orderId);
  }

  Future<int> sendOrderToKitchen(String orderId) async {
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final batch = _db.batch();
    final kitchenBatchId = _ordersRef
        .doc(orderId)
        .collection('kitchenBatches')
        .doc()
        .id;
    var sentCount = 0;

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.sendToKitchen && item.kitchenStatus == 'pending') {
        sentCount += 1;
        batch.update(doc.reference, {
          'kitchenStatus': 'sent',
          'kitchenBatchId': kitchenBatchId,
          'sentToKitchenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    if (sentCount == 0) {
      return 0;
    }

    final orderDoc = await _ordersRef.doc(orderId).get();
    final tableId = orderDoc.data()?['tableId'] as String?;
    batch.update(_ordersRef.doc(orderId), {
      'status': 'sent',
      'kitchenStatus': 'sent',
      'sentToKitchenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (tableId != null) {
      batch.set(_tablesRef.doc(tableId), {
        'status': 'sent',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
    return sentCount;
  }

  Future<void> updateKitchenStatus({
    required String orderId,
    required String status,
  }) async {
    final normalizedStatus = status == 'preparing' ? 'cooking' : status;
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final batch = _db.batch();
    var changed = 0;

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.sendToKitchen &&
          ['sent', 'cooking'].contains(item.kitchenStatus)) {
        changed += 1;
        batch.update(doc.reference, {
          'kitchenStatus': normalizedStatus,
          if (normalizedStatus == 'cooking')
            'cookingAt': FieldValue.serverTimestamp(),
          if (normalizedStatus == 'ready')
            'readyAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    if (changed == 0) {
      return;
    }

    final orderDoc = await _ordersRef.doc(orderId).get();
    final tableId = orderDoc.data()?['tableId'] as String?;
    final orderStatus = normalizedStatus == 'ready' ? 'ready' : 'sent';

    batch.update(_ordersRef.doc(orderId), {
      'status': orderStatus,
      'kitchenStatus': normalizedStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (tableId != null) {
      batch.set(_tablesRef.doc(tableId), {
        'status': orderStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<void> updateKitchenItemsStatus({
    required String orderId,
    required Iterable<String> itemIds,
    required String status,
  }) async {
    final normalizedStatus = status == 'preparing' ? 'cooking' : status;
    final targetIds = itemIds.toSet();
    if (targetIds.isEmpty) {
      return;
    }

    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final allItems = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
    final batch = _db.batch();
    final changedIds = <String>{};

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (targetIds.contains(item.id) &&
          item.sendToKitchen &&
          ['sent', 'cooking'].contains(item.kitchenStatus)) {
        changedIds.add(item.id);
        batch.update(doc.reference, {
          'kitchenStatus': normalizedStatus,
          if (normalizedStatus == 'cooking')
            'cookingAt': FieldValue.serverTimestamp(),
          if (normalizedStatus == 'ready')
            'readyAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    if (changedIds.isEmpty) {
      return;
    }

    final orderDoc = await _ordersRef.doc(orderId).get();
    final tableId = orderDoc.data()?['tableId'] as String?;
    final kitchenStatus = _aggregateKitchenStatus(
      allItems: allItems,
      changedIds: changedIds,
      changedStatus: normalizedStatus,
    );
    final orderStatus = ['ready', 'not_required'].contains(kitchenStatus)
        ? 'ready'
        : 'sent';

    batch.update(_ordersRef.doc(orderId), {
      'status': orderStatus,
      'kitchenStatus': kitchenStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (tableId != null) {
      batch.set(_tablesRef.doc(tableId), {
        'status': orderStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  String _aggregateKitchenStatus({
    required List<OrderItem> allItems,
    required Set<String> changedIds,
    required String changedStatus,
  }) {
    var hasPending = false;
    var hasSent = false;
    var hasCooking = false;
    var hasReady = false;

    for (final item in allItems.where((item) => item.sendToKitchen)) {
      final status = changedIds.contains(item.id)
          ? changedStatus
          : item.kitchenStatus;

      switch (status) {
        case 'cooking':
          hasCooking = true;
        case 'sent':
          hasSent = true;
        case 'pending':
          hasPending = true;
        case 'ready':
          hasReady = true;
      }
    }

    if (hasCooking) {
      return 'cooking';
    }
    if (hasSent) {
      return 'sent';
    }
    if (hasPending) {
      return 'pending';
    }
    if (hasReady) {
      return 'ready';
    }
    return 'not_required';
  }

  Future<void> markActiveKitchenItemsCooking(String orderId) {
    return updateKitchenStatus(orderId: orderId, status: 'cooking');
  }

  Future<PaymentResult> payFullTable({
    required String orderId,
    required String method,
    String? employeeId,
    String? employeeName,
  }) async {
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = PosOrder.fromDoc(orderDoc);
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final pendingItems = itemsSnapshot.docs
        .map(OrderItem.fromDoc)
        .where((item) => item.paymentStatus != 'paid')
        .toList();
    final baseAmount = pendingItems.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.total,
    );

    if (baseAmount <= 0) {
      return const PaymentResult(allPaid: true);
    }

    final paymentRef = _ordersRef.doc(orderId).collection('payments').doc();
    final batch = _db.batch();
    _setPayment(
      batch: batch,
      paymentRef: paymentRef,
      order: order,
      type: 'full_table',
      method: method,
      baseAmount: baseAmount,
      employeeId: employeeId,
      employeeName: employeeName,
    );

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.paymentStatus != 'paid') {
        batch.update(doc.reference, {
          'paymentStatus': 'paid',
          'paidAt': FieldValue.serverTimestamp(),
          'paymentId': paymentRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    _closeOrderInBatch(batch, order, paidTotal: order.total);
    await batch.commit();
    return const PaymentResult(allPaid: true);
  }

  Future<PaymentResult> payPerson({
    required String orderId,
    required int personNumber,
    required String method,
    String? employeeId,
    String? employeeName,
  }) async {
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = PosOrder.fromDoc(orderDoc);
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final items = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
    final personItems = items
        .where(
          (item) =>
              item.personNumber == personNumber && item.paymentStatus != 'paid',
        )
        .toList();
    final baseAmount = personItems.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.total,
    );

    if (baseAmount <= 0) {
      return PaymentResult(allPaid: order.pendingTotal <= 0.01);
    }

    final paymentRef = _ordersRef.doc(orderId).collection('payments').doc();
    final batch = _db.batch();
    _setPayment(
      batch: batch,
      paymentRef: paymentRef,
      order: order,
      type: 'person',
      method: method,
      baseAmount: baseAmount,
      personNumber: personNumber,
      personName: 'Persona $personNumber',
      employeeId: employeeId,
      employeeName: employeeName,
    );

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.personNumber == personNumber && item.paymentStatus != 'paid') {
        batch.update(doc.reference, {
          'paymentStatus': 'paid',
          'paidAt': FieldValue.serverTimestamp(),
          'paymentId': paymentRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    final allPaid = _updateOrderPaymentTotalsInBatch(
      batch,
      order,
      baseAmount: baseAmount,
      closeItemsSnapshot: itemsSnapshot,
    );
    await batch.commit();
    return PaymentResult(allPaid: allPaid);
  }

  Future<PaymentResult> payPartialAmount({
    required String orderId,
    required double baseAmount,
    required String method,
    String? employeeId,
    String? employeeName,
  }) async {
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = PosOrder.fromDoc(orderDoc);

    if (baseAmount <= 0 || baseAmount > order.pendingTotal + 0.01) {
      throw ArgumentError('Monto parcial invalido.');
    }

    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final paymentRef = _ordersRef.doc(orderId).collection('payments').doc();
    final batch = _db.batch();
    _setPayment(
      batch: batch,
      paymentRef: paymentRef,
      order: order,
      type: 'partial',
      method: method,
      baseAmount: baseAmount,
      employeeId: employeeId,
      employeeName: employeeName,
    );

    final allPaid = _updateOrderPaymentTotalsInBatch(
      batch,
      order,
      baseAmount: baseAmount,
      closeItemsSnapshot: itemsSnapshot,
      markItemsOnlyIfClosed: true,
    );
    await batch.commit();
    return PaymentResult(allPaid: allPaid);
  }

  bool _updateOrderPaymentTotalsInBatch(
    WriteBatch batch,
    PosOrder order, {
    required double baseAmount,
    required QuerySnapshot<Map<String, dynamic>> closeItemsSnapshot,
    bool markItemsOnlyIfClosed = false,
  }) {
    final paidTotal = (order.paidTotal + baseAmount).clamp(0, order.total);
    final pendingTotal = (order.total - paidTotal).clamp(0, double.infinity);
    final allPaid = pendingTotal <= 0.01;

    if (allPaid) {
      for (final doc in closeItemsSnapshot.docs) {
        batch.update(doc.reference, {
          'paymentStatus': 'paid',
          'paidAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      _closeOrderInBatch(batch, order, paidTotal: order.total);
    } else {
      batch.update(_ordersRef.doc(order.id), {
        'paymentStatus': 'partial',
        'paidTotal': paidTotal,
        'pendingTotal': pendingTotal,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!markItemsOnlyIfClosed) {
        // Person payments already updated their own items before this method.
      }
    }

    return allPaid;
  }

  void _closeOrderInBatch(
    WriteBatch batch,
    PosOrder order, {
    required double paidTotal,
  }) {
    batch.update(_ordersRef.doc(order.id), {
      'status': 'paid',
      'paymentStatus': 'paid',
      'paidTotal': paidTotal,
      'pendingTotal': 0.0,
      'paidAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_tablesRef.doc(order.tableId), {
      'status': 'available',
      'currentOrderId': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _setPayment({
    required WriteBatch batch,
    required DocumentReference<Map<String, dynamic>> paymentRef,
    required PosOrder order,
    required String type,
    required String method,
    required double baseAmount,
    int? personNumber,
    String? personName,
    String? employeeId,
    String? employeeName,
  }) {
    if (method == 'employee_consumption' &&
        (employeeId == null || employeeName == null)) {
      throw ArgumentError('Selecciona un empleado.');
    }

    final surchargeRate = method == 'card' ? cardSurchargeRate : 0.0;
    final surchargeAmount = baseAmount * surchargeRate;
    final chargedAmount = baseAmount + surchargeAmount;

    batch.set(paymentRef, {
      'orderId': order.id,
      'tableId': order.tableId,
      'tableName': order.tableName,
      'type': type,
      'personNumber': personNumber,
      'personName': personName,
      'method': method,
      'baseAmount': baseAmount,
      'amount': baseAmount,
      'surchargeRate': surchargeRate,
      'surchargeAmount': surchargeAmount,
      'chargedAmount': chargedAmount,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
    });
  }

  Future<void> recalculateOrderTotal(String orderId) async {
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final items = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
    final total = items.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.total,
    );
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = orderDoc.exists ? PosOrder.fromDoc(orderDoc) : null;
    final paidTotal = order?.paidTotal ?? 0;
    final adjustedPending = (total - paidTotal).clamp(0, double.infinity);

    await _ordersRef.doc(orderId).update({
      'total': total,
      'pendingTotal': adjustedPending,
      'paymentStatus': paidTotal <= 0
          ? 'pending'
          : adjustedPending <= 0.01
          ? 'paid'
          : 'partial',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveProduct({
    String? productId,
    required String name,
    required String category,
    required double price,
    required bool active,
    required bool sendToKitchen,
  }) async {
    final docRef = productId == null
        ? _productsRef.doc()
        : _productsRef.doc(productId);
    final current = await _productsRef.get();

    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'category': category.trim(),
      'price': price,
      'active': active,
      'sendToKitchen': sendToKitchen,
      'sortOrder': current.docs.length + 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleProduct(Product product) async {
    await _productsRef.doc(product.id).update({
      'active': !product.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveEmployee({
    String? employeeId,
    required String name,
    required bool active,
  }) async {
    final docRef = employeeId == null
        ? _employeesRef.doc()
        : _employeesRef.doc(employeeId);

    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'active': active,
      if (employeeId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleEmployee(Employee employee) async {
    await _employeesRef.doc(employee.id).update({
      'active': !employee.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
