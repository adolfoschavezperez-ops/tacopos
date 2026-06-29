import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/constants/app_constants.dart';
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

class TacoPosRepository {
  TacoPosRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> get _restaurantRef =>
      _db.collection('restaurants').doc(AppConstants.restaurantId);

  CollectionReference<Map<String, dynamic>> get _tablesRef =>
      _restaurantRef.collection('tables');

  CollectionReference<Map<String, dynamic>> get _productsRef =>
      _restaurantRef.collection('products');

  CollectionReference<Map<String, dynamic>> get _ordersRef =>
      _restaurantRef.collection('orders');

  Stream<List<PosTable>> watchTables({bool activeOnly = true}) {
    return _tablesRef.snapshots().map((snapshot) {
      final tables = snapshot.docs.map(PosTable.fromDoc).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      if (!activeOnly) {
        return tables;
      }

      return tables.where((table) => table.active).toList();
    });
  }

  Stream<List<Product>> watchProducts({bool activeOnly = false}) {
    return _productsRef.snapshots().map((snapshot) {
      final products = snapshot.docs.map(Product.fromDoc).toList()
        ..sort((a, b) {
          final categoryCompare = a.category.compareTo(b.category);
          if (categoryCompare != 0) {
            return categoryCompare;
          }
          return a.sortOrder.compareTo(b.sortOrder);
        });

      if (!activeOnly) {
        return products;
      }

      return products.where((product) => product.active).toList();
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
      final activeOrders = snapshot.docs
          .map(PosOrder.fromDoc)
          .where(
            (order) =>
                order.status != 'paid' &&
                ['sent', 'cooking'].contains(order.kitchenStatus),
          )
          .toList();

      final bundles = <KitchenOrderBundle>[];
      for (final order in activeOrders) {
        final items = await getKitchenItems(order.id);
        if (items.isNotEmpty) {
          bundles.add(KitchenOrderBundle(order: order, items: items));
        }
      }

      bundles.sort((a, b) {
        final aDate =
            a.order.sentToKitchenAt ??
            a.order.updatedAt ??
            a.order.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            b.order.sentToKitchenAt ??
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
          if (personCompare != 0) {
            return personCompare;
          }
          return a.productName.compareTo(b.productName);
        });
      return items;
    });
  }

  Stream<List<OrderItem>> watchKitchenItems(String orderId) {
    return watchOrderItems(
      orderId,
    ).map((items) => items.where((item) => item.sendToKitchen).toList());
  }

  Future<List<OrderItem>> getKitchenItems(String orderId) async {
    final snapshot = await _ordersRef.doc(orderId).collection('items').get();
    final items =
        snapshot.docs
            .map(OrderItem.fromDoc)
            .where((item) => item.sendToKitchen)
            .toList()
          ..sort((a, b) {
            final personCompare = a.personNumber.compareTo(b.personNumber);
            if (personCompare != 0) {
              return personCompare;
            }
            return a.productName.compareTo(b.productName);
          });
    return items;
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
    var sentCount = 0;

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.sendToKitchen && item.kitchenStatus == 'pending') {
        sentCount += 1;
        batch.update(doc.reference, {
          'kitchenStatus': 'sent',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    final orderDoc = await _ordersRef.doc(orderId).get();
    final tableId = orderDoc.data()?['tableId'] as String?;

    if (sentCount > 0) {
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
    } else {
      batch.update(_ordersRef.doc(orderId), {
        'kitchenStatus': 'not_required',
        'updatedAt': FieldValue.serverTimestamp(),
      });
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

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.sendToKitchen && item.paymentStatus != 'paid') {
        batch.update(doc.reference, {
          'kitchenStatus': normalizedStatus,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
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

  Future<void> markOrderPaid(String orderId, {String method = 'cash'}) {
    return payFullTable(orderId: orderId, method: method);
  }

  Future<void> payFullTable({
    required String orderId,
    required String method,
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
    final amount = pendingItems.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.total,
    );

    if (amount <= 0) {
      return;
    }

    final paymentRef = _ordersRef.doc(orderId).collection('payments').doc();
    final batch = _db.batch();
    _setPayment(
      batch: batch,
      paymentRef: paymentRef,
      order: order,
      type: 'full_table',
      method: method,
      amount: amount,
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

    batch.update(_ordersRef.doc(orderId), {
      'status': 'paid',
      'paymentStatus': 'paid',
      'paidTotal': order.paidTotal + amount,
      'pendingTotal': 0.0,
      'paidAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_tablesRef.doc(order.tableId), {
      'status': 'available',
      'currentOrderId': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> payPerson({
    required String orderId,
    required int personNumber,
    required String method,
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
    final amount = personItems.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.total,
    );

    if (amount <= 0) {
      return;
    }

    final paymentRef = _ordersRef.doc(orderId).collection('payments').doc();
    final batch = _db.batch();
    _setPayment(
      batch: batch,
      paymentRef: paymentRef,
      order: order,
      type: 'person',
      method: method,
      amount: amount,
      personNumber: personNumber,
      personName: 'Persona $personNumber',
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

    final paidTotal = order.paidTotal + amount;
    final pendingTotal = (order.total - paidTotal).clamp(0, double.infinity);
    final allPaid = pendingTotal <= 0.01;

    batch.update(_ordersRef.doc(orderId), {
      'status': allPaid ? 'paid' : order.status,
      'paymentStatus': allPaid ? 'paid' : 'partial',
      'paidTotal': paidTotal,
      'pendingTotal': allPaid ? 0.0 : pendingTotal,
      if (allPaid) 'paidAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (allPaid) {
      batch.set(_tablesRef.doc(order.tableId), {
        'status': 'available',
        'currentOrderId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  void _setPayment({
    required WriteBatch batch,
    required DocumentReference<Map<String, dynamic>> paymentRef,
    required PosOrder order,
    required String type,
    required String method,
    required double amount,
    int? personNumber,
    String? personName,
  }) {
    batch.set(paymentRef, {
      'orderId': order.id,
      'tableId': order.tableId,
      'tableName': order.tableName,
      'type': type,
      'personNumber': personNumber,
      'personName': personName,
      'method': method,
      'amount': amount,
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
    final total = items.fold<double>(0, (runningTotal, item) {
      return runningTotal + item.total;
    });
    final paidTotal = items
        .where((item) => item.paymentStatus == 'paid')
        .fold<double>(0, (runningTotal, item) => runningTotal + item.total);
    final pendingTotal = (total - paidTotal).clamp(0, double.infinity);

    await _ordersRef.doc(orderId).update({
      'total': total,
      'paidTotal': paidTotal,
      'pendingTotal': pendingTotal,
      'paymentStatus': paidTotal <= 0
          ? 'pending'
          : pendingTotal <= 0.01
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
}
