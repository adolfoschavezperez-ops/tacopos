import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:tacopos/models/employee.dart';
import 'package:tacopos/models/product.dart';
import 'package:tacopos/services/app_session.dart';
import 'package:tacopos/services/taco_pos_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    await Firebase.initializeApp();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceSet',
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
  });

  test(
    'concurrent increments preserve the latest quantity for each person',
    () async {
      final db = _MemoryFirestore();
      AppSession.instance.signIn(_waiter());
      final repository = TacoPosRepository(firestore: db, auth: _Auth());
      for (final personNumber in [1, 2]) {
        final orderId = 'race-person-$personNumber';
        _seedOrder(db, orderId);
        final itemPath =
            'restaurants/main_restaurant/orders/$orderId/items/taco-pastor-p$personNumber';
        db.documents[itemPath] = {
          'personNumber': personNumber,
          'productId': 'taco-pastor',
          'productName': 'Taco pastor',
          'category': 'Tacos',
          'qty': 1,
          'unitPrice': 20,
          'total': 20,
          'sendToKitchen': true,
          'kitchenStatus': 'pending',
          'paymentStatus': 'pending',
          'status': 'active',
          'cancelStatus': 'none',
        };
        // Another tablet commits after discovery (qty=1) but before this
        // transaction reads the item, so the transactional snapshot is qty=2.
        db.beforeNextTransaction = () {
          db.documents[itemPath]!['qty'] = 2;
          db.documents[itemPath]!['total'] = 40;
        };

        await repository.addProductToOrder(
          orderId: orderId,
          product: _product('taco-pastor', 'Taco pastor'),
          personNumber: personNumber,
          knownStockedOut: false,
          itemId: 'new-local-id',
          operationId: 'capture-p$personNumber',
        );
        await repository.flushPendingMutations(orderId);

        final persistedItem = db.documents[itemPath]!;
        expect(persistedItem['personNumber'], personNumber);
        expect(persistedItem['qty'], 3);
        expect(persistedItem['total'], 60);
        expect(
          db.documents['restaurants/main_restaurant/orders/$orderId']!['total'],
          60,
        );
      }
      AppSession.instance.signOut();
    },
  );

  test(
    'captures 1, 2, 3, 5 and 10 tacos per person without losing flavor rows',
    () async {
      final db = _MemoryFirestore();
      AppSession.instance.signIn(_waiter());
      final repository = TacoPosRepository(firestore: db, auth: _Auth());
      final pastor = _product('taco-pastor', 'Pastor');
      final asada = _product('taco-asada', 'Asada');

      for (final qty in [1, 2, 3, 5, 10]) {
        final orderId = 'qty-$qty';
        _seedOrder(db, orderId);

        await Future.wait([
          for (var i = 0; i < qty; i++)
            repository.addProductToOrder(
              orderId: orderId,
              product: pastor,
              personNumber: 1,
              knownStockedOut: false,
              itemId: 'pastor-person-1',
              operationId: 'fast-p1-$qty-$i',
            ),
          for (var i = 0; i < 2; i++)
            repository.addProductToOrder(
              orderId: orderId,
              product: pastor,
              personNumber: 2,
              knownStockedOut: false,
              itemId: 'pastor-person-2',
              operationId: 'fast-p2-$qty-$i',
            ),
          repository.addProductToOrder(
            orderId: orderId,
            product: asada,
            personNumber: 1,
            knownStockedOut: false,
            itemId: 'asada-person-1',
            operationId: 'asada-p1-$qty',
          ),
        ]);
        await repository.flushPendingMutations(orderId);

        final orderItemsPath =
            'restaurants/main_restaurant/orders/$orderId/items/';
        final pastorP1 = db.documents['${orderItemsPath}pastor-person-1']!;
        final pastorP2 = db.documents['${orderItemsPath}pastor-person-2']!;
        final asadaP1 = db.documents['${orderItemsPath}asada-person-1']!;
        expect((pastorP1['personNumber'], pastorP1['qty']), (1, qty));
        expect((pastorP2['personNumber'], pastorP2['qty']), (2, 2));
        expect((asadaP1['personNumber'], asadaP1['qty']), (1, 1));
        expect(
          db.documents['restaurants/main_restaurant/orders/$orderId']!['total'],
          (qty + 3) * 20,
        );

        for (final entry in db.documents.entries.where(
          (entry) => entry.key.startsWith(orderItemsPath),
        )) {
          entry.value['kitchenStatus'] = 'sent';
          entry.value['kitchenBatchId'] = 'batch-$qty';
        }
        final kitchenItems = await repository.getActiveKitchenItems(orderId);
        expect(
          kitchenItems.fold<int>(0, (runningTotal, item) => runningTotal + item.qty),
          qty + 3,
        );
      }
      AppSession.instance.signOut();
    },
  );
}

Employee _waiter() => const Employee(
  id: 'waiter-1',
  name: 'Mesero',
  active: true,
  pin: '',
  canTakeOrders: true,
  canCharge: false,
  canViewKitchen: false,
  canViewAdmin: false,
  canManageProducts: false,
  canManageTables: false,
  canManagePlatforms: false,
  canManageEmployees: false,
  canManageCash: false,
  canAuthorizeCashWithdrawals: false,
  canOpenKitchen: false,
  canCloseKitchen: false,
  canViewKitchenReports: false,
  canViewKitchenHourlySalesComparison: false,
  canManageKitchenStock: false,
  canCancelOrders: false,
  canCancelPayments: false,
  canCancelItems: false,
  canApproveKitchenCancellations: false,
  canViewLiveOperations: false,
  canControlLiveOperations: false,
);

Product _product(String id, String name) => Product(
  id: id,
  name: name,
  categoryId: 'tacos',
  categoryName: 'Tacos',
  category: 'Tacos',
  price: 20,
  active: true,
  sendToKitchen: true,
  sortOrder: 1,
  platformPrices: const {},
  affectsKitchenStock: false,
);

void _seedOrder(_MemoryFirestore db, String orderId) {
  db.documents['restaurants/main_restaurant/orders/$orderId'] = {
    'status': 'open',
    'paymentStatus': 'pending',
    'kitchenStatus': 'pending',
    'orderType': 'table',
    'total': 0,
    'grossSubtotal': 0,
    'netTotal': 0,
    'paidTotal': 0,
    'pendingTotal': 0,
    'captureRevision': 0,
  };
}

class _Auth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryFirestore implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  void Function()? beforeNextTransaction;
  int transactionCount = 0;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _MemoryCollection(this, path);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    transactionCount++;
    beforeNextTransaction?.call();
    beforeNextTransaction = null;
    return handler(_MemoryTransaction(this));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _MemoryCollection implements CollectionReference<Map<String, dynamic>> {
  _MemoryCollection(this.db, this.path);
  final _MemoryFirestore db;

  @override
  final String path;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      _MemoryDocument(db, '$path/${id ?? 'auto-id'}');

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final prefix = '$path/';
    final docs = db.documents.entries
        .where((entry) {
          final remainder = entry.key.startsWith(prefix)
              ? entry.key.substring(prefix.length)
              : '';
          return remainder.isNotEmpty && !remainder.contains('/');
        })
        .map(
          (entry) => _MemorySnapshot(
            entry.key.split('/').last,
            Map<String, dynamic>.of(entry.value),
          ),
        )
        .toList();
    return _MemoryQuery(docs);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _MemoryDocument implements DocumentReference<Map<String, dynamic>> {
  _MemoryDocument(this.db, this.path);
  final _MemoryFirestore db;

  @override
  final String path;

  @override
  String get id => path.split('/').last;

  @override
  CollectionReference<Map<String, dynamic>> collection(String name) =>
      _MemoryCollection(db, '$path/$name');

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async =>
      _MemorySnapshot(id, db.documents[path] == null
          ? null
          : Map<String, dynamic>.of(db.documents[path]!));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryTransaction implements Transaction {
  _MemoryTransaction(this.db);
  final _MemoryFirestore db;

  @override
  Future<DocumentSnapshot<T>> get<T>(DocumentReference<T> ref) async =>
      _MemorySnapshot(
            ref.id,
            db.documents[ref.path] == null
                ? null
                : Map<String, dynamic>.of(db.documents[ref.path]!),
          )
          as DocumentSnapshot<T>;

  @override
  Transaction update(DocumentReference ref, Map<Object, Object?> data) {
    final target = db.documents[ref.path];
    if (target == null) throw StateError('Missing document ${ref.path}');
    _apply(target, data);
    return this;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> ref,
    T data, [
    SetOptions? options,
  ]) {
    final target = db.documents.putIfAbsent(ref.path, () => {});
    if (data is Map<Object, Object?>) _apply(target, data);
    return this;
  }

  void _apply(Map<String, dynamic> target, Map<Object, Object?> data) {
    for (final entry in data.entries) {
      final key = entry.key as String;
      final value = entry.value;
      if (value is FieldValue) {
        if (key == 'captureRevision') {
          target[key] = ((target[key] as num?) ?? 0) + 1;
        }
      } else {
        target[key] = value;
      }
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _MemorySnapshot implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _MemorySnapshot(this.id, Map<String, dynamic>? value)
    : _value = value ?? {},
      _exists = value != null;
  @override
  final String id;
  final Map<String, dynamic> _value;
  final bool _exists;
  @override
  bool get exists => _exists;
  @override
  Map<String, dynamic> data() => _value;
  @override
  SnapshotMetadata get metadata => const _MemoryMetadata();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryQuery implements QuerySnapshot<Map<String, dynamic>> {
  _MemoryQuery(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  SnapshotMetadata get metadata => const _MemoryMetadata();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryMetadata implements SnapshotMetadata {
  const _MemoryMetadata();
  @override
  bool get isFromCache => false;
  @override
  bool get hasPendingWrites => false;
}
