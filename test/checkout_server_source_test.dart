import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/constants/app_constants.dart';
import 'package:tacopos/services/taco_pos_repository.dart';

const _orderPath = 'restaurants/${AppConstants.restaurantId}/orders/order';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());
  test(
    'canonical repository recalculation reads server items, order and payments',
    () async {
      final db = _Firestore();
      final repository = TacoPosRepository(firestore: db, auth: _Auth());
      await repository.recalculateOrderTotal('order', source: Source.server);
      final order = await repository.getOrderOnce(
        'order',
        source: Source.server,
      );
      expect(db.reads.map((read) => read.$1), [
        '$_orderPath/items',
        _orderPath,
        '$_orderPath/payments',
        _orderPath,
      ]);
      expect(db.reads.every((read) => read.$2 == Source.server), isTrue);
      expect(order.total, 190);
      expect(order.paidTotal, 30);
      expect(order.pendingTotal, 160);
      expect(order.netTotal, 190);
    },
  );

  test(
    'server failure propagates without falling back to cached total',
    () async {
      final db = _Firestore()..serverUnavailable = true;
      final repository = TacoPosRepository(firestore: db, auth: _Auth());
      await expectLater(
        repository.recalculateOrderTotal('order', source: Source.server),
        throwsStateError,
      );
      await expectLater(
        repository.getOrderOnce('order', source: Source.server),
        throwsStateError,
      );
      expect(db.orderData['total'], 100);
    },
  );

  test(
    'checkout order listener drops cache and unacknowledged writes',
    () async {
      final repository = TacoPosRepository(
        firestore: _Firestore(),
        auth: _Auth(),
      );
      final orders = await repository
          .watchOrder('order', requireServer: true)
          .toList();
      expect(orders, hasLength(1));
      expect(orders.single!.total, 190);
    },
  );

  test(
    'checkout items and payments also require server confirmation',
    () async {
      final repository = TacoPosRepository(
        firestore: _Firestore(),
        auth: _Auth(),
      );
      final items = await repository
          .watchOrderItems('order', requireServer: true)
          .toList();
      final payments = await repository
          .watchOrderPayments('order', requireServer: true)
          .toList();
      expect(items, hasLength(1));
      expect(items.single.map((item) => item.total), [100, 30, 40, 20]);
      expect(payments, hasLength(1));
      expect(payments.single.single.baseAmount, 30);
    },
  );

  test(
    'capture listeners preserve their existing optimistic snapshots',
    () async {
      final repository = TacoPosRepository(
        firestore: _Firestore(),
        auth: _Auth(),
      );
      final orders = await repository.watchOrder('order').toList();
      expect(orders.map((order) => order!.total), [100, 170, 190]);
    },
  );
}

class _Auth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Firestore implements FirebaseFirestore {
  final reads = <(String, Source)>[];
  bool serverUnavailable = false;
  final orderData = <String, dynamic>{
    'total': 100,
    'paidTotal': 0,
    'pendingTotal': 100,
  };

  void read(String path, GetOptions? options) {
    final source = options?.source ?? Source.serverAndCache;
    reads.add((path, source));
    if (source == Source.server && serverUnavailable) {
      throw StateError('offline');
    }
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection(this, collectionPath);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// In-memory FlutterFire boundary for exercising the production repository.
// ignore: subtype_of_sealed_class
class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.db, this.path);
  final _Firestore db;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(db, '${this.path}/$path');
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    db.read(path, options);
    return _query(const _Metadata(false, false));
  }

  _Query _query(_Metadata metadata) => _Query([
    if (path.endsWith('/items'))
      for (final amount in [100, 30, 40, 20])
        _Snapshot('item-$amount', {
          'total': amount,
          'unitPrice': amount,
          'qty': 1,
          'sendToKitchen': false,
          'kitchenStatus': 'not_required',
          'paymentStatus': 'pending',
        }, metadata),
    if (path.endsWith('/payments'))
      _Snapshot('partial', {
        'type': 'partial',
        'method': 'cash',
        'baseAmount': 30,
        'appliedAmount': 30,
        'chargedAmount': 30,
        'status': 'active',
      }, metadata),
  ], metadata);
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => Stream.fromIterable([
    _query(const _Metadata(true, false)),
    _query(const _Metadata(false, true)),
    _query(const _Metadata(false, false)),
  ]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Document implements DocumentReference<Map<String, dynamic>> {
  _Document(this.db, this.path);
  final _Firestore db;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _Collection(db, '$path/$collectionPath');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    db.read(path, options);
    return _Snapshot(id, Map.of(db.orderData), const _Metadata(false, false));
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    for (final entry in data.entries) {
      if (entry.value is! FieldValue) {
        db.orderData[entry.key as String] = entry.value;
      }
    }
  }

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => Stream.fromIterable([
    _Snapshot(id, {'total': 100}, const _Metadata(true, false)),
    _Snapshot(id, {'total': 170}, const _Metadata(false, true)),
    _Snapshot(id, {'total': 190}, const _Metadata(false, false)),
  ]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Snapshot implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.id, this.value, this.metadata);
  @override
  final String id;
  final Map<String, dynamic> value;
  @override
  final SnapshotMetadata metadata;
  @override
  bool get exists => true;
  @override
  Map<String, dynamic> data() => value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Query implements QuerySnapshot<Map<String, dynamic>> {
  _Query(this.docs, this.metadata);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  final SnapshotMetadata metadata;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Metadata implements SnapshotMetadata {
  const _Metadata(this.isFromCache, this.hasPendingWrites);
  @override
  final bool isFromCache;
  @override
  final bool hasPendingWrites;
}
