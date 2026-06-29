import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/constants/app_constants.dart';
import '../models/cash_session.dart';
import '../models/employee.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../models/order_platform.dart';
import '../models/payment.dart';
import '../models/pos_table.dart';
import '../models/product.dart';
import 'app_session.dart';

class KitchenOrderBundle {
  const KitchenOrderBundle({required this.order, required this.items});

  final PosOrder order;
  final List<OrderItem> items;

  int get personCount => items.map((item) => item.personNumber).toSet().length;

  String get personLabel {
    final namesByPerson = <int, String>{};
    for (final item in items) {
      namesByPerson.putIfAbsent(item.personNumber, () => item.personName);
    }
    final names = namesByPerson.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return names.map((entry) => entry.value).join(', ');
  }

  DateTime? get firstSentToKitchenAt {
    return items
        .map((item) => item.sentToKitchenAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (min, date) => min == null || date.isBefore(min) ? date : min,
        );
  }

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

  CollectionReference<Map<String, dynamic>> get _platformsRef =>
      _restaurantRef.collection('orderPlatforms');

  CollectionReference<Map<String, dynamic>> get _ordersRef =>
      _restaurantRef.collection('orders');

  CollectionReference<Map<String, dynamic>> get _cashSessionsRef =>
      _restaurantRef.collection('cashSessions');

  Stream<List<PosTable>> watchTables({bool activeOnly = true}) {
    return _tablesRef.snapshots().map((snapshot) {
      final tables = snapshot.docs.map(PosTable.fromDoc).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return activeOnly
          ? tables.where((table) => table.active).toList()
          : tables;
    });
  }

  Stream<List<OrderPlatform>> watchOrderPlatforms({bool activeOnly = true}) {
    return _platformsRef.snapshots().map((snapshot) {
      final platforms = snapshot.docs.map(OrderPlatform.fromDoc).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return activeOnly
          ? platforms.where((platform) => platform.active).toList()
          : platforms;
    });
  }

  Future<void> ensureDefaultOrderPlatforms() async {
    final snapshot = await _platformsRef.limit(1).get();
    if (snapshot.docs.isNotEmpty) {
      return;
    }

    final batch = _db.batch();
    const defaults = [
      {'id': 'en_persona', 'name': 'En persona', 'sortOrder': 1},
      {'id': 'didi', 'name': 'DiDi', 'sortOrder': 2},
      {'id': 'uber', 'name': 'Uber', 'sortOrder': 3},
      {'id': 'rappi', 'name': 'Rappi', 'sortOrder': 4},
    ];

    for (final platform in defaults) {
      final id = platform['id']! as String;
      batch.set(_platformsRef.doc(id), {
        ...platform,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
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

  Future<void> ensureInitialAdminEmployee() async {
    final adminRef = _employeesRef.doc('admin');
    final doc = await adminRef.get();
    if (doc.exists) {
      if (doc.data()?['canManageCash'] != true) {
        await adminRef.set({
          'canManageCash': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      return;
    }

    await adminRef.set({
      'id': 'admin',
      'name': 'Admin',
      // TODO: Replace plain PIN storage with a salted hash before production.
      'pin': '1234',
      'active': true,
      'canTakeOrders': true,
      'canCharge': true,
      'canViewKitchen': true,
      'canViewAdmin': true,
      'canManageProducts': true,
      'canManageTables': true,
      'canManagePlatforms': true,
      'canManageEmployees': true,
      'canManageCash': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> validateEmployeePin({
    required String employeeId,
    required String pin,
  }) async {
    final doc = await _employeesRef.doc(employeeId).get();
    if (!doc.exists) {
      return false;
    }

    final employee = Employee.fromDoc(doc);
    return employee.active && employee.pin == pin;
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

  Stream<List<PosOrder>> watchOpenTakeoutOrders() {
    return _ordersRef.snapshots().map((snapshot) {
      final orders =
          snapshot.docs
              .map(PosOrder.fromDoc)
              .where(
                (order) =>
                    order.orderType == 'takeout' &&
                    !['paid', 'cancelled'].contains(order.status),
              )
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

  Stream<List<CashSession>> watchCashSessions() {
    return _cashSessionsRef.snapshots().map((snapshot) {
      final sessions = snapshot.docs.map(CashSession.fromDoc).toList()
        ..sort((a, b) {
          final aDate = a.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
      return sessions;
    });
  }

  Stream<CashSession?> watchOpenCashSession() {
    return watchCashSessions().map((sessions) {
      final openSessions = sessions
          .where((session) => session.status == 'open')
          .toList();
      if (openSessions.isEmpty) {
        return null;
      }
      return openSessions.first;
    });
  }

  Stream<CashSessionTotals> watchCashSessionTotals(String cashSessionId) {
    return watchPayments().map(
      (payments) => _totalsForPayments(
        payments
            .where((payment) => payment.cashSessionId == cashSessionId)
            .toList(),
      ),
    );
  }

  Future<CashSession?> getOpenCashSession() async {
    final snapshot = await _cashSessionsRef.get();
    final sessions =
        snapshot.docs
            .map(CashSession.fromDoc)
            .where((session) => session.status == 'open')
            .toList()
          ..sort((a, b) {
            final aDate = a.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });

    return sessions.isEmpty ? null : sessions.first;
  }

  Future<void> openCashSession({
    required String businessDate,
    required double openingCashAmount,
  }) async {
    _requireCashOpenPermission();
    if (businessDate.trim().isEmpty) {
      throw ArgumentError('Selecciona la fecha operativa.');
    }
    if (openingCashAmount < 0) {
      throw ArgumentError('El fondo inicial no puede ser negativo.');
    }

    final openSession = await getOpenCashSession();
    if (openSession != null) {
      if (openSession.businessDate == businessDate) {
        return;
      }
      throw StateError(
        'Ya existe una caja abierta para ${openSession.businessDate}.',
      );
    }

    final existingForDate = await _cashSessionsRef
        .where('businessDate', isEqualTo: businessDate)
        .get();
    final hasClosed = existingForDate.docs
        .map(CashSession.fromDoc)
        .any((session) => session.status == 'closed');
    if (hasClosed) {
      throw StateError('La fecha $businessDate ya tiene corte cerrado.');
    }

    final employee = AppSession.instance.employee;
    final docRef = _cashSessionsRef.doc();
    await docRef.set({
      'id': docRef.id,
      'businessDate': businessDate,
      'status': 'open',
      'openingCashAmount': openingCashAmount,
      'openedAt': FieldValue.serverTimestamp(),
      'openedByEmployeeId': employee?.id ?? '',
      'openedByEmployeeName': employee?.name ?? '',
      'countedCashAmount': 0.0,
      'terminalReportedAmount': 0.0,
      'expectedCashAmount': 0.0,
      'expectedCardChargedAmount': 0.0,
      'expectedCardBaseAmount': 0.0,
      'expectedCardSurchargeAmount': 0.0,
      'expectedPlatformAmount': 0.0,
      'expectedEmployeeConsumptionAmount': 0.0,
      'totalExpectedRealMoney': 0.0,
      'totalCountedRealMoney': 0.0,
      'cashDifference': 0.0,
      'cardDifference': 0.0,
      'netDifference': 0.0,
      'shortageAmount': 0.0,
      'overAmount': 0.0,
      'notes': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<CashSession> closeCashSession({
    required String cashSessionId,
    required double countedCashAmount,
    required double terminalReportedAmount,
    required String notes,
  }) async {
    _requireCashManager();
    if (countedCashAmount < 0 || terminalReportedAmount < 0) {
      throw ArgumentError('Los montos de cierre no pueden ser negativos.');
    }

    final docRef = _cashSessionsRef.doc(cashSessionId);
    final doc = await docRef.get();
    if (!doc.exists) {
      throw StateError('La caja ya no existe.');
    }

    final session = CashSession.fromDoc(doc);
    if (session.status != 'open') {
      throw StateError('Esta caja ya esta cerrada.');
    }

    final totals = await _cashSessionTotalsOnce(cashSessionId);
    final totalCountedRealMoney = totals.totalCountedRealMoney(
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
    );
    final cashDifference = totals.cashDifference(countedCashAmount);
    final cardDifference = totals.cardDifference(terminalReportedAmount);
    final netDifference = totals.netDifference(
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
    );
    final shortageAmount = totals.shortageAmount(
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
    );
    final overAmount = totals.overAmount(
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
    );
    final employee = AppSession.instance.employee;

    await docRef.update({
      'status': 'closed',
      'closedAt': FieldValue.serverTimestamp(),
      'closedByEmployeeId': employee?.id ?? '',
      'closedByEmployeeName': employee?.name ?? '',
      'countedCashAmount': countedCashAmount,
      'terminalReportedAmount': terminalReportedAmount,
      'expectedCashAmount': totals.expectedCashAmount,
      'expectedCardChargedAmount': totals.expectedCardChargedAmount,
      'expectedCardBaseAmount': totals.expectedCardBaseAmount,
      'expectedCardSurchargeAmount': totals.expectedCardSurchargeAmount,
      'expectedPlatformAmount': totals.expectedPlatformAmount,
      'expectedEmployeeConsumptionAmount':
          totals.expectedEmployeeConsumptionAmount,
      'totalExpectedRealMoney': totals.totalExpectedRealMoney,
      'totalCountedRealMoney': totalCountedRealMoney,
      'cashDifference': cashDifference,
      'cardDifference': cardDifference,
      'netDifference': netDifference,
      'shortageAmount': shortageAmount,
      'overAmount': overAmount,
      'notes': notes.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final updatedDoc = await docRef.get();
    return CashSession.fromDoc(updatedDoc);
  }

  Future<CashSessionTotals> _cashSessionTotalsOnce(String cashSessionId) async {
    final snapshot = await _db.collectionGroup('payments').get();
    return _totalsForPayments(
      snapshot.docs
          .map(Payment.fromDoc)
          .where((payment) => payment.cashSessionId == cashSessionId)
          .toList(),
    );
  }

  CashSessionTotals _totalsForPayments(List<Payment> payments) {
    double cash = 0;
    double cardCharged = 0;
    double cardBase = 0;
    double cardSurcharge = 0;
    double platform = 0;
    double employeeConsumption = 0;

    for (final payment in payments) {
      switch (payment.method) {
        case 'cash':
          cash += payment.chargedAmount;
          break;
        case 'card':
          cardCharged += payment.chargedAmount;
          cardBase += payment.baseAmount;
          cardSurcharge += payment.surchargeAmount;
          break;
        case 'platform_paid':
          platform += payment.baseAmount;
          break;
        case 'employee_consumption':
          employeeConsumption += payment.baseAmount;
          break;
      }
    }

    return CashSessionTotals(
      expectedCashAmount: cash,
      expectedCardChargedAmount: cardCharged,
      expectedCardBaseAmount: cardBase,
      expectedCardSurchargeAmount: cardSurcharge,
      expectedPlatformAmount: platform,
      expectedEmployeeConsumptionAmount: employeeConsumption,
    );
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
      _requireAnyPermission(
        takeOrders: true,
        charge: true,
        message: 'No tienes permiso para abrir ordenes.',
      );
      return existing.first;
    }

    _requireTakeOrders();
    final orderRef = _ordersRef.doc();
    final data = {
      'tableId': table.id,
      'tableName': table.name,
      'orderType': 'dine_in',
      'status': 'open',
      'kitchenStatus': 'pending',
      'paymentStatus': 'pending',
      'total': 0.0,
      'paidTotal': 0.0,
      'pendingTotal': 0.0,
      'personNames': {'1': 'Persona 1'},
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      ..._employeeAuditFields(prefix: 'createdBy'),
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

  Future<PosOrder> createTakeoutOrder({
    required OrderPlatform platform,
    String? customerName,
  }) async {
    _requireTakeOrders();
    final orderRef = _ordersRef.doc();
    final takeoutNumber = await _nextTakeoutNumber();
    final cleanCustomer = customerName?.trim();
    final data = {
      'tableId': 'takeout',
      'tableName': 'Para llevar',
      'orderType': 'takeout',
      'platformId': platform.id,
      'platformName': platform.name,
      'takeoutNumber': takeoutNumber,
      if (cleanCustomer != null && cleanCustomer.isNotEmpty)
        'customerName': cleanCustomer,
      'status': 'open',
      'kitchenStatus': 'pending',
      'paymentStatus': 'pending',
      'total': 0.0,
      'paidTotal': 0.0,
      'pendingTotal': 0.0,
      'personNames': {'1': 'Persona 1'},
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      ..._employeeAuditFields(prefix: 'createdBy'),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await orderRef.set(data);
    final doc = await orderRef.get();
    return PosOrder.fromDoc(doc);
  }

  Future<int> _nextTakeoutNumber() async {
    final snapshot = await _ordersRef.get();
    var maxNumber = 0;
    for (final doc in snapshot.docs) {
      final number = (doc.data()['takeoutNumber'] as num?)?.toInt() ?? 0;
      if (number > maxNumber) {
        maxNumber = number;
      }
    }
    return maxNumber + 1;
  }

  Future<void> addProductToOrder({
    required String orderId,
    required Product product,
    required int personNumber,
  }) async {
    _requireTakeOrders();
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = orderDoc.exists ? PosOrder.fromDoc(orderDoc) : null;
    final personName =
        order?.personName(personNumber) ?? 'Persona $personNumber';
    final platformId = order?.orderType == 'takeout' ? order?.platformId : null;
    final platformName = order?.orderType == 'takeout'
        ? order?.platformName
        : null;
    final usePlatformPrice = platformId != null && platformId != 'en_persona';
    final appliedPrice = usePlatformPrice
        ? product.priceForPlatform(platformId)
        : product.price;
    final existingItem = await _findMatchingPendingItem(
      orderId: orderId,
      productId: product.id,
      personNumber: personNumber,
      appliedPlatformId: usePlatformPrice ? platformId : null,
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
      'personName': personName,
      'productId': product.id,
      'productName': product.name,
      'category': product.category,
      'qty': 1,
      'unitPrice': appliedPrice,
      'total': appliedPrice,
      'appliedPlatformId': usePlatformPrice ? platformId : null,
      'appliedPlatformName': usePlatformPrice ? platformName : null,
      'priceSource': usePlatformPrice ? 'platform' : 'store',
      'notes': '',
      ..._employeeAuditFields(prefix: 'createdBy'),
      'sendToKitchen': product.sendToKitchen,
      'kitchenStatus': product.sendToKitchen ? 'pending' : 'not_required',
      'kitchenBatchId': null,
      'paymentStatus': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await recalculateOrderTotal(orderId);
  }

  Future<void> renamePerson({
    required String orderId,
    required int personNumber,
    required String name,
  }) async {
    _requireTakeOrders();
    final cleanName = name.trim().isEmpty
        ? 'Persona $personNumber'
        : name.trim();
    final orderRef = _ordersRef.doc(orderId);
    final itemsSnapshot = await orderRef.collection('items').get();
    final batch = _db.batch();

    batch.update(orderRef, {
      'personNames.$personNumber': cleanName,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.personNumber == personNumber) {
        batch.update(doc.reference, {
          'personName': cleanName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();
  }

  Future<OrderItem?> _findMatchingPendingItem({
    required String orderId,
    required String productId,
    required int personNumber,
    String? appliedPlatformId,
  }) async {
    final snapshot = await _ordersRef.doc(orderId).collection('items').get();

    for (final doc in snapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.productId == productId &&
          item.personNumber == personNumber &&
          item.appliedPlatformId == appliedPlatformId &&
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
    _requireTakeOrders();
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
    _requireTakeOrders();
    await _ordersRef.doc(orderId).collection('items').doc(itemId).delete();
    await recalculateOrderTotal(orderId);
  }

  Future<void> cancelEmptyOrder(String orderId) async {
    final orderDoc = await _ordersRef.doc(orderId).get();
    if (!orderDoc.exists) {
      throw StateError('La orden ya no existe.');
    }
    final order = PosOrder.fromDoc(orderDoc);
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final paymentsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('payments')
        .get();

    if (itemsSnapshot.docs.isNotEmpty) {
      throw StateError('No se puede cerrar: la orden ya tiene articulos.');
    }
    if (paymentsSnapshot.docs.isNotEmpty) {
      throw StateError('No se puede cerrar: la orden ya tiene pagos.');
    }
    if (order.status != 'open' ||
        order.sentToKitchenAt != null ||
        ['sent', 'cooking', 'ready'].contains(order.kitchenStatus)) {
      throw StateError('No se puede cerrar: la orden ya fue enviada a cocina.');
    }

    final batch = _db.batch();
    batch.update(_ordersRef.doc(orderId), {
      'status': 'cancelled',
      'kitchenStatus': 'cancelled',
      'paymentStatus': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      ..._employeeAuditFields(prefix: 'cancelledBy'),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (order.orderType != 'takeout') {
      batch.set(_tablesRef.doc(order.tableId), {
        'status': 'available',
        'currentOrderId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<int> sendOrderToKitchen(String orderId) async {
    _requireTakeOrders();
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
      final shouldAttachToBatch =
          item.kitchenBatchId == null &&
          item.paymentStatus == 'pending' &&
          (item.kitchenStatus == 'pending' ||
              item.kitchenStatus == 'not_required');
      if (item.sendToKitchen && item.kitchenStatus == 'pending') {
        sentCount += 1;
        batch.update(doc.reference, {
          'kitchenStatus': 'sent',
          'kitchenBatchId': kitchenBatchId,
          'sentToKitchenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (shouldAttachToBatch) {
        batch.update(doc.reference, {
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
    final orderData = orderDoc.data();
    final tableId = orderData?['tableId'] as String?;
    final orderType = orderData?['orderType'] as String? ?? 'dine_in';
    batch.update(_ordersRef.doc(orderId), {
      'status': 'sent',
      'kitchenStatus': 'sent',
      'sentToKitchenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (tableId != null && orderType != 'takeout') {
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
          if (normalizedStatus == 'cooking' && item.cookingAt == null)
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
    final orderData = orderDoc.data();
    final tableId = orderData?['tableId'] as String?;
    final orderType = orderData?['orderType'] as String? ?? 'dine_in';
    final orderStatus = normalizedStatus == 'ready' ? 'ready' : 'sent';

    batch.update(_ordersRef.doc(orderId), {
      'status': orderStatus,
      'kitchenStatus': normalizedStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (tableId != null && orderType != 'takeout') {
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
          if (normalizedStatus == 'cooking' && item.cookingAt == null)
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
    final orderData = orderDoc.data();
    final tableId = orderData?['tableId'] as String?;
    final orderType = orderData?['orderType'] as String? ?? 'dine_in';
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

    if (tableId != null && orderType != 'takeout') {
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
    _requireCharge();
    final cashSession = await _requireOpenCashSessionForPayment();
    await _ensureNoPaymentType(orderId, blockedType: 'person');
    await _ensureEmployeeConsumptionAllowed(orderId, method);
    await _ensureKitchenReadyForPayment(orderId);
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
      cashSession: cashSession,
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
    _requireCharge();
    final cashSession = await _requireOpenCashSessionForPayment();
    await _ensureNoPaymentType(orderId, blockedType: 'partial');
    await _ensureEmployeeConsumptionAllowed(orderId, method);
    await _ensureKitchenReadyForPayment(orderId);
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
    final personName = personItems.isEmpty
        ? 'Persona $personNumber'
        : personItems.first.personName;
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
      cashSession: cashSession,
      type: 'person',
      method: method,
      baseAmount: baseAmount,
      personNumber: personNumber,
      personName: personName,
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
    _requireCharge();
    final cashSession = await _requireOpenCashSessionForPayment();
    await _ensureNoPaymentType(orderId, blockedType: 'person');
    await _ensureEmployeeConsumptionAllowed(orderId, method);
    await _ensureKitchenReadyForPayment(orderId);
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
      cashSession: cashSession,
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

  Future<PaymentResult> payPlatformOrder({required String orderId}) async {
    _requireCharge();
    final cashSession = await _requireOpenCashSessionForPayment();
    await _ensureKitchenReadyForPayment(orderId);
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = PosOrder.fromDoc(orderDoc);
    if (order.orderType != 'takeout' || order.platformId == 'en_persona') {
      throw StateError('Este pedido no aplica para pago en plataforma.');
    }

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
      cashSession: cashSession,
      type: 'platform',
      method: 'platform_paid',
      baseAmount: baseAmount,
      platformId: order.platformId,
      platformName: order.platformName,
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
    if (order.orderType != 'takeout') {
      batch.set(_tablesRef.doc(order.tableId), {
        'status': 'available',
        'currentOrderId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  void _setPayment({
    required WriteBatch batch,
    required DocumentReference<Map<String, dynamic>> paymentRef,
    required PosOrder order,
    required CashSession cashSession,
    required String type,
    required String method,
    required double baseAmount,
    int? personNumber,
    String? personName,
    String? employeeId,
    String? employeeName,
    String? platformId,
    String? platformName,
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
      'platformId': platformId,
      'platformName': platformName,
      'cashSessionId': cashSession.id,
      'businessDate': cashSession.businessDate,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      ..._employeeAuditFields(prefix: 'createdBy'),
    });
  }

  Map<String, Object> _employeeAuditFields({required String prefix}) {
    final employee = AppSession.instance.employee;
    if (employee == null) {
      return const {};
    }
    return {
      '${prefix}EmployeeId': employee.id,
      '${prefix}EmployeeName': employee.name,
    };
  }

  void _requireTakeOrders() {
    if (AppSession.instance.employee?.canTakeOrders == true) {
      return;
    }
    throw StateError('No tienes permiso para levantar pedidos');
  }

  void _requireCharge() {
    if (AppSession.instance.employee?.canCharge == true) {
      return;
    }
    throw StateError('No tienes permiso para cobrar');
  }

  void _requireCashManager() {
    if (AppSession.instance.employee?.canManageCash == true) {
      return;
    }
    throw StateError('No tienes permiso para cerrar caja.');
  }

  void _requireCashOpenPermission() {
    final employee = AppSession.instance.employee;
    if (employee?.canManageCash == true || employee?.canCharge == true) {
      return;
    }
    throw StateError('No tienes permiso para abrir caja.');
  }

  Future<CashSession> _requireOpenCashSessionForPayment() async {
    final session = await getOpenCashSession();
    if (session == null) {
      throw StateError('Debes abrir caja antes de cobrar.');
    }
    return session;
  }

  void _requireAnyPermission({
    required bool takeOrders,
    required bool charge,
    required String message,
  }) {
    final employee = AppSession.instance.employee;
    final allowed =
        (takeOrders && employee?.canTakeOrders == true) ||
        (charge && employee?.canCharge == true);
    if (!allowed) {
      throw StateError(message);
    }
  }

  Future<void> _ensureKitchenReadyForPayment(String orderId) async {
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final hasKitchenPending = itemsSnapshot.docs
        .map(OrderItem.fromDoc)
        .any(
          (item) =>
              item.sendToKitchen &&
              ['pending', 'sent', 'cooking'].contains(item.kitchenStatus),
        );

    if (hasKitchenPending) {
      throw StateError(
        'No puedes cobrar hasta que cocina marque todo como listo.',
      );
    }
  }

  Future<void> _ensureNoPaymentType(
    String orderId, {
    required String blockedType,
  }) async {
    final paymentsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('payments')
        .get();
    final hasBlockedType = paymentsSnapshot.docs
        .map(Payment.fromDoc)
        .any((payment) => payment.type == blockedType);

    if (hasBlockedType) {
      final message = blockedType == 'partial'
          ? 'Esta cuenta ya tiene pagos parciales. Termina el cobro por parcialidades.'
          : 'Esta cuenta ya inicio cobro por persona. Termina el cobro por persona.';
      throw StateError(message);
    }
  }

  Future<void> _ensureEmployeeConsumptionAllowed(
    String orderId,
    String method,
  ) async {
    if (method != 'employee_consumption') {
      return;
    }

    final paymentsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('payments')
        .get();
    final hasClientPayment = paymentsSnapshot.docs
        .map(Payment.fromDoc)
        .any((payment) => ['cash', 'card'].contains(payment.method));

    if (hasClientPayment) {
      throw StateError(
        'Consumo empleado no disponible porque ya existe un pago de cliente.',
      );
    }
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
    required Map<String, double> platformPrices,
    required bool active,
    required bool sendToKitchen,
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageProducts == true,
      'No tienes permiso para administrar productos.',
    );
    final docRef = productId == null
        ? _productsRef.doc()
        : _productsRef.doc(productId);
    final current = await _productsRef.get();

    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'category': category.trim(),
      'price': price,
      'platformPrices': platformPrices,
      'active': active,
      'sendToKitchen': sendToKitchen,
      'sortOrder': current.docs.length + 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveTable({
    String? tableId,
    required String name,
    required String type,
    required bool active,
    required int sortOrder,
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageTables == true,
      'No tienes permiso para administrar mesas.',
    );
    final docRef = tableId == null ? _tablesRef.doc() : _tablesRef.doc(tableId);

    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'type': type,
      'active': active,
      'sortOrder': sortOrder,
      if (tableId == null) 'status': 'available',
      if (tableId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleTable(PosTable table) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageTables == true,
      'No tienes permiso para administrar mesas.',
    );
    await _tablesRef.doc(table.id).update({
      'active': !table.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveOrderPlatform({
    String? platformId,
    required String name,
    required bool active,
    required int sortOrder,
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManagePlatforms == true,
      'No tienes permiso para administrar plataformas.',
    );
    final docRef = platformId == null
        ? _platformsRef.doc()
        : _platformsRef.doc(platformId);

    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'active': active,
      'sortOrder': sortOrder,
      if (platformId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleOrderPlatform(OrderPlatform platform) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManagePlatforms == true,
      'No tienes permiso para administrar plataformas.',
    );
    await _platformsRef.doc(platform.id).update({
      'active': !platform.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> toggleProduct(Product product) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageProducts == true,
      'No tienes permiso para administrar productos.',
    );
    await _productsRef.doc(product.id).update({
      'active': !product.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveEmployee({
    String? employeeId,
    required String name,
    required bool active,
    required String pin,
    required bool canTakeOrders,
    required bool canCharge,
    required bool canViewKitchen,
    required bool canViewAdmin,
    required bool canManageProducts,
    required bool canManageTables,
    required bool canManagePlatforms,
    required bool canManageEmployees,
    required bool canManageCash,
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageEmployees == true,
      'No tienes permiso para administrar empleados.',
    );
    final docRef = employeeId == null
        ? _employeesRef.doc()
        : _employeesRef.doc(employeeId);

    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      // TODO: Replace plain PIN storage with a salted hash before production.
      'pin': pin.trim(),
      'active': active,
      'canTakeOrders': canTakeOrders,
      'canCharge': canCharge,
      'canViewKitchen': canViewKitchen,
      'canViewAdmin': canViewAdmin,
      'canManageProducts': canManageProducts,
      'canManageTables': canManageTables,
      'canManagePlatforms': canManagePlatforms,
      'canManageEmployees': canManageEmployees,
      'canManageCash': canManageCash,
      if (employeeId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleEmployee(Employee employee) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageEmployees == true,
      'No tienes permiso para administrar empleados.',
    );
    await _employeesRef.doc(employee.id).update({
      'active': !employee.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  void _requireAdminPermission(bool allowed, String message) {
    if (allowed) {
      return;
    }
    throw StateError(message);
  }
}
