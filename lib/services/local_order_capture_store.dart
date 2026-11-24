import 'dart:convert';

import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../core/orders/local_order_capture.dart';
import 'local_order_capture_database.dart';

class LocalOrderCaptureStore {
  LocalOrderCaptureStore({required Database database}) : _database = database;

  static final Future<LocalOrderCaptureStore> _defaultInstance =
      openLocalOrderCaptureDatabase().then(
        (database) => LocalOrderCaptureStore(database: database),
      );

  static Future<LocalOrderCaptureStore> get instance => _defaultInstance;

  static final _lineStore = StoreRef<String, Map<String, dynamic>>(
    'orderCaptureDraftLines',
  );
  static final _submissionStore = StoreRef<String, Map<String, dynamic>>(
    'orderCaptureSubmissions',
  );
  static final _operationStore = StoreRef<String, Map<String, dynamic>>(
    'orderCaptureTapOperations',
  );

  final Database _database;

  Future<List<LocalOrderCaptureLine>> loadLines({
    required String restaurantId,
    required String branchId,
    required String orderId,
  }) async {
    final rows = await _lineStore.find(
      _database,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('restaurantId', restaurantId),
          Filter.equals('branchId', branchId),
          Filter.equals('orderId', orderId),
        ]),
        sortOrders: [SortOrder('capturedAtMicros'), SortOrder('id')],
      ),
    );
    return rows
        .map((row) => LocalOrderCaptureLine.fromMap(row.value))
        .toList(growable: false);
  }

  Future<List<LocalOrderCaptureRecoveryEntry>> loadRecoveryEntries({
    required String restaurantId,
    required String branchId,
  }) async {
    final scope = Filter.and([
      Filter.equals('restaurantId', restaurantId),
      Filter.equals('branchId', branchId),
    ]);
    final lineRows = await _lineStore.find(
      _database,
      finder: Finder(
        filter: scope,
        sortOrders: [SortOrder('capturedAtMicros'), SortOrder('id')],
      ),
    );
    final submissionRows = await _submissionStore.find(
      _database,
      finder: Finder(
        filter: Filter.and([scope, Filter.equals('state', 'pending')]),
        sortOrders: [SortOrder('createdAtMicros')],
      ),
    );
    final linesByOrder = <String, List<LocalOrderCaptureLine>>{};
    for (final row in lineRows) {
      final line = LocalOrderCaptureLine.fromMap(row.value);
      (linesByOrder[line.orderId] ??= []).add(line);
    }
    final submissionsByOrder = <String, LocalOrderCaptureSubmission>{};
    for (final row in submissionRows) {
      final submission = LocalOrderCaptureSubmission.fromMap(row.value);
      final previous = submissionsByOrder[submission.orderId];
      if (previous != null) {
        throw StateError(
          'Hay varios envios pendientes para la orden ${submission.orderId}.',
        );
      }
      submissionsByOrder[submission.orderId] = submission;
    }
    final orderIds = {...linesByOrder.keys, ...submissionsByOrder.keys};
    final entries = orderIds.map((orderId) {
      return LocalOrderCaptureRecoveryEntry(
        restaurantId: restaurantId,
        branchId: branchId,
        orderId: orderId,
        lines: List.unmodifiable(linesByOrder[orderId] ?? const []),
        submission: submissionsByOrder[orderId],
      );
    }).toList();
    entries.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return List.unmodifiable(entries);
  }

  Stream<List<LocalOrderCaptureLine>> watchLines({
    required String restaurantId,
    required String branchId,
    required String orderId,
  }) => _lineStore
      .query(
        finder: Finder(
          filter: Filter.and([
            Filter.equals('restaurantId', restaurantId),
            Filter.equals('branchId', branchId),
            Filter.equals('orderId', orderId),
          ]),
          sortOrders: [SortOrder('capturedAtMicros'), SortOrder('id')],
        ),
      )
      .onSnapshots(_database)
      .map(
        (rows) => rows
            .map((row) => LocalOrderCaptureLine.fromMap(row.value))
            .toList(growable: false),
      );

  Future<List<LocalOrderCaptureLine>> addTap(
    LocalOrderCaptureLine newLine, {
    String? operationId,
  }) => _database.transaction((transaction) async {
    final cleanOperationId = operationId?.trim().isNotEmpty == true
        ? operationId!.trim()
        : newLine.id;
    final pending = await _pendingForOrder(
      transaction,
      restaurantId: newLine.restaurantId,
      branchId: newLine.branchId,
      orderId: newLine.orderId,
    );
    if (pending.isNotEmpty) {
      throw StateError('Hay un envio pendiente. Reintenta antes de editar.');
    }

    final operation = await _operationStore
        .record(cleanOperationId)
        .get(transaction);
    if (operation != null) {
      if (operation['orderId'] != newLine.orderId ||
          operation['branchId'] != newLine.branchId ||
          operation['restaurantId'] != newLine.restaurantId ||
          operation['lineCanonical'] != newLine.canonicalJson()) {
        throw StateError('El identificador de captura ya fue utilizado.');
      }
      return _findLines(
        transaction,
        restaurantId: newLine.restaurantId,
        branchId: newLine.branchId,
        orderId: newLine.orderId,
      );
    }

    final currentLines = await _findLines(
      transaction,
      restaurantId: newLine.restaurantId,
      branchId: newLine.branchId,
      orderId: newLine.orderId,
    );
    LocalOrderCaptureLine? matching;
    for (final line in currentLines) {
      if (line.deviceUid == newLine.deviceUid &&
          line.employeeId == newLine.employeeId &&
          line.personNumber == newLine.personNumber &&
          line.productId == newLine.productId &&
          line.appliedPlatformId == newLine.appliedPlatformId) {
        matching = line;
        break;
      }
    }
    if (matching == null) {
      await _lineStore.record(newLine.id).put(transaction, newLine.toMap());
    } else {
      await _lineStore
          .record(matching.id)
          .put(transaction, matching.withQty(matching.qty + 1).toMap());
    }
    await _operationStore.record(cleanOperationId).put(transaction, {
      'operationId': cleanOperationId,
      'restaurantId': newLine.restaurantId,
      'branchId': newLine.branchId,
      'orderId': newLine.orderId,
      'lineCanonical': newLine.canonicalJson(),
      'createdAtMicros': newLine.capturedAtMicros,
    });
    return _findLines(
      transaction,
      restaurantId: newLine.restaurantId,
      branchId: newLine.branchId,
      orderId: newLine.orderId,
    );
  });

  Future<List<LocalOrderCaptureLine>> adjustQty({
    required String id,
    required int delta,
    required String operationId,
    required String restaurantId,
    required String branchId,
    required String orderId,
  }) => _database.transaction((transaction) async {
    final previousOperation = await _operationStore
        .record(operationId)
        .get(transaction);
    if (previousOperation != null) {
      if (previousOperation['lineId'] != id ||
          previousOperation['delta'] != delta ||
          previousOperation['orderId'] != orderId ||
          previousOperation['branchId'] != branchId ||
          previousOperation['restaurantId'] != restaurantId) {
        throw StateError('El identificador de captura ya fue utilizado.');
      }
      return _findLines(
        transaction,
        restaurantId: restaurantId,
        branchId: branchId,
        orderId: orderId,
      );
    }
    if (delta == 0) {
      return _findLines(
        transaction,
        restaurantId: restaurantId,
        branchId: branchId,
        orderId: orderId,
      );
    }
    final line = await _lineStore.record(id).get(transaction);
    if (line == null ||
        line['restaurantId'] != restaurantId ||
        line['branchId'] != branchId ||
        line['orderId'] != orderId) {
      throw StateError('La captura local ya no existe.');
    }
    if ((await _pendingForOrder(
      transaction,
      restaurantId: restaurantId,
      branchId: branchId,
      orderId: orderId,
    )).isNotEmpty) {
      throw StateError('Hay un envio pendiente. Reintenta antes de editar.');
    }
    final current = LocalOrderCaptureLine.fromMap(line);
    final next = current.qty + delta;
    if (next <= 0) {
      await _lineStore.record(id).delete(transaction);
    } else {
      await _lineStore
          .record(id)
          .put(transaction, current.withQty(next).toMap());
    }
    await _operationStore.record(operationId).put(transaction, {
      'operationId': operationId,
      'restaurantId': restaurantId,
      'branchId': branchId,
      'orderId': orderId,
      'lineId': id,
      'delta': delta,
    });
    return _findLines(
      transaction,
      restaurantId: restaurantId,
      branchId: branchId,
      orderId: orderId,
    );
  });

  Future<List<LocalOrderCaptureLine>> setQty({
    required String id,
    required int qty,
    required String restaurantId,
    required String branchId,
    required String orderId,
  }) => _database.transaction((transaction) async {
    final line = await _lineStore.record(id).get(transaction);
    if (line == null ||
        line['restaurantId'] != restaurantId ||
        line['branchId'] != branchId ||
        line['orderId'] != orderId) {
      throw StateError('La captura local ya no existe.');
    }
    if (await _pendingForOrder(
      transaction,
      restaurantId: restaurantId,
      branchId: branchId,
      orderId: orderId,
    ).then((rows) => rows.isNotEmpty)) {
      throw StateError('Hay un envio pendiente. Reintenta antes de editar.');
    }
    if (qty <= 0) {
      await _lineStore.record(id).delete(transaction);
    } else {
      await _lineStore
          .record(id)
          .put(
            transaction,
            LocalOrderCaptureLine.fromMap(line).withQty(qty).toMap(),
          );
    }
    return _findLines(
      transaction,
      restaurantId: restaurantId,
      branchId: branchId,
      orderId: orderId,
    );
  });

  Future<List<LocalOrderCaptureLine>> removeLine({
    required String id,
    required String restaurantId,
    required String branchId,
    required String orderId,
  }) => setQty(
    id: id,
    qty: 0,
    restaurantId: restaurantId,
    branchId: branchId,
    orderId: orderId,
  );

  Future<LocalOrderCaptureSubmission?> pendingSubmission({
    required String restaurantId,
    required String branchId,
    required String orderId,
  }) async {
    final rows = await _pendingForOrder(
      _database,
      restaurantId: restaurantId,
      branchId: branchId,
      orderId: orderId,
    );
    if (rows.isEmpty) return null;
    if (rows.length > 1) {
      throw StateError('Hay mas de un envio pendiente para esta orden.');
    }
    return LocalOrderCaptureSubmission.fromMap(rows.single.value);
  }

  Future<LocalOrderCaptureSubmission> freeze({
    required String restaurantId,
    required String branchId,
    required String orderId,
    required bool sendToKitchen,
  }) => _database.transaction((transaction) async {
    final pending = await _pendingForOrder(
      transaction,
      restaurantId: restaurantId,
      branchId: branchId,
      orderId: orderId,
    );
    if (pending.length > 1) {
      throw StateError('Hay mas de un envio pendiente para esta orden.');
    }
    if (pending.isNotEmpty) {
      return LocalOrderCaptureSubmission.fromMap(pending.single.value);
    }

    final rows = await _lineStore.find(
      transaction,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('restaurantId', restaurantId),
          Filter.equals('branchId', branchId),
          Filter.equals('orderId', orderId),
        ]),
        sortOrders: [SortOrder('capturedAtMicros'), SortOrder('id')],
      ),
    );
    if (rows.isEmpty) {
      throw StateError('No hay productos locales pendientes.');
    }
    final lines = rows
        .map((row) => LocalOrderCaptureLine.fromMap(row.value))
        .toList(growable: false);
    final payload = jsonEncode(lines.map((line) => line.toMap()).toList());
    final submission = LocalOrderCaptureSubmission(
      id: const Uuid().v4(),
      restaurantId: restaurantId,
      branchId: branchId,
      orderId: orderId,
      payloadHash: localCapturePayloadHash(lines),
      payloadJson: payload,
      lineIds: lines.map((line) => line.id).toList(growable: false),
      sendToKitchen: sendToKitchen,
      createdAtMicros: DateTime.now().microsecondsSinceEpoch,
    );
    await _submissionStore
        .record(submission.id)
        .put(transaction, submission.toMap());
    return submission;
  });

  Future<void> complete(LocalOrderCaptureSubmission submission) =>
      _database.transaction((transaction) async {
        final current = await _submissionStore
            .record(submission.id)
            .get(transaction);
        if (current == null) return;
        final stored = LocalOrderCaptureSubmission.fromMap(current);
        if (stored.payloadHash != submission.payloadHash ||
            stored.orderId != submission.orderId ||
            stored.branchId != submission.branchId ||
            stored.restaurantId != submission.restaurantId) {
          throw StateError('El envio local cambio mientras se confirmaba.');
        }
        for (final lineId in stored.lineIds) {
          final line = await _lineStore.record(lineId).get(transaction);
          if (line != null &&
              line['restaurantId'] == stored.restaurantId &&
              line['branchId'] == stored.branchId &&
              line['orderId'] == stored.orderId) {
            await _lineStore.record(lineId).delete(transaction);
          }
        }
        await _submissionStore.record(stored.id).delete(transaction);
      });

  /// Opens a frozen submission only after the server has atomically written an
  /// abort tombstone on its idempotency marker. This makes any in-flight older
  /// submission transaction observe the tombstone instead of committing later.
  Future<void> releaseAuthoritativelyAborted(
    LocalOrderCaptureSubmission submission,
  ) => _database.transaction((transaction) async {
    final current = await _submissionStore
        .record(submission.id)
        .get(transaction);
    if (current == null) return;
    final stored = LocalOrderCaptureSubmission.fromMap(current);
    if (stored.payloadHash != submission.payloadHash ||
        stored.orderId != submission.orderId ||
        stored.branchId != submission.branchId ||
        stored.restaurantId != submission.restaurantId) {
      throw StateError('El envio local cambio mientras se recuperaba.');
    }
    await _submissionStore.record(stored.id).delete(transaction);
  });

  Future<List<RecordSnapshot<String, Map<String, dynamic>>>> _pendingForOrder(
    DatabaseClient transaction, {
    required String restaurantId,
    required String branchId,
    required String orderId,
  }) => _submissionStore.find(
    transaction,
    finder: Finder(
      filter: Filter.and([
        Filter.equals('restaurantId', restaurantId),
        Filter.equals('branchId', branchId),
        Filter.equals('orderId', orderId),
        Filter.equals('state', 'pending'),
      ]),
    ),
  );

  Future<List<LocalOrderCaptureLine>> _findLines(
    Transaction transaction, {
    required String restaurantId,
    required String branchId,
    required String orderId,
  }) async {
    final rows = await _lineStore.find(
      transaction,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('restaurantId', restaurantId),
          Filter.equals('branchId', branchId),
          Filter.equals('orderId', orderId),
        ]),
        sortOrders: [SortOrder('capturedAtMicros'), SortOrder('id')],
      ),
    );
    return rows
        .map((row) => LocalOrderCaptureLine.fromMap(row.value))
        .toList(growable: false);
  }
}
