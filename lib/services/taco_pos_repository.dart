import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/constants/app_constants.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../models/pos_table.dart';
import '../models/product.dart';

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

  Stream<List<PosOrder>> watchKitchenOrders() {
    return _ordersRef.snapshots().map((snapshot) {
      final orders =
          snapshot.docs
              .map(PosOrder.fromDoc)
              .where(
                (order) =>
                    order.status != 'paid' &&
                    [
                      'sent',
                      'preparing',
                      'ready',
                    ].contains(order.kitchenStatus),
              )
              .toList()
            ..sort((a, b) {
              final aDate =
                  a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bDate =
                  b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return aDate.compareTo(bDate);
            });
      return orders;
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
      'kitchenStatus': 'pending',
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

  Future<void> sendOrderToKitchen(String orderId) async {
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final batch = _db.batch();

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.kitchenStatus == 'pending') {
        batch.update(doc.reference, {
          'kitchenStatus': 'sent',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    batch.update(_ordersRef.doc(orderId), {
      'status': 'sent',
      'kitchenStatus': 'sent',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final orderDoc = await _ordersRef.doc(orderId).get();
    final tableId = orderDoc.data()?['tableId'] as String?;
    if (tableId != null) {
      batch.set(_tablesRef.doc(tableId), {
        'status': 'sent',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<void> updateKitchenStatus({
    required String orderId,
    required String status,
  }) async {
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final batch = _db.batch();

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.paymentStatus != 'paid') {
        batch.update(doc.reference, {
          'kitchenStatus': status,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    final orderDoc = await _ordersRef.doc(orderId).get();
    final tableId = orderDoc.data()?['tableId'] as String?;
    final orderStatus = status == 'ready' ? 'ready' : 'sent';

    batch.update(_ordersRef.doc(orderId), {
      'status': orderStatus,
      'kitchenStatus': status,
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

  Future<void> markOrderPaid(String orderId) async {
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = PosOrder.fromDoc(orderDoc);
    final batch = _db.batch();

    for (final doc in itemsSnapshot.docs) {
      batch.update(doc.reference, {
        'paymentStatus': 'paid',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    batch.update(_ordersRef.doc(orderId), {
      'status': 'paid',
      'paymentStatus': 'paid',
      'paidTotal': order.total,
      'pendingTotal': 0.0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_tablesRef.doc(order.tableId), {
      'status': 'available',
      'currentOrderId': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> recalculateOrderTotal(String orderId) async {
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final total = itemsSnapshot.docs.fold<double>(0, (runningTotal, doc) {
      final item = OrderItem.fromDoc(doc);
      return runningTotal + item.total;
    });

    await _ordersRef.doc(orderId).update({
      'total': total,
      'pendingTotal': total,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveProduct({
    String? productId,
    required String name,
    required String category,
    required double price,
    required bool active,
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
