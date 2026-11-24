import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:tacopos/core/orders/local_order_capture.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/services/local_order_capture_store.dart';

void main() {
  late Directory directory;
  late String databasePath;
  late Database database;
  late LocalOrderCaptureStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tacopos-local-capture-');
    databasePath = '${directory.path}${Platform.pathSeparator}capture.db';
    database = await databaseFactoryIo.openDatabase(databasePath);
    store = LocalOrderCaptureStore(database: database);
  });

  tearDown(() async {
    await database.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    '30 taps persist locally with exact quantity and no Firestore dependency',
    () async {
      for (var index = 0; index < 30; index++) {
        await store.addTap(line(id: 'local-line-$index'));
      }
      final lines = await store.loadLines(
        restaurantId: 'restaurant-a',
        branchId: 'branch-a',
        orderId: 'order-a',
      );
      expect(lines, hasLength(1));
      expect(lines.single.qty, 30);
    },
  );

  test(
    '30 accepted taps without waiting for widget rebuilds are counted once',
    () async {
      await Future.wait([
        for (var index = 0; index < 30; index++)
          store.addTap(
            line(id: 'rapid-line-$index'),
            operationId: 'rapid-operation-$index',
          ),
      ]);
      final lines = await store.loadLines(
        restaurantId: 'restaurant-a',
        branchId: 'branch-a',
        orderId: 'order-a',
      );
      expect(lines.single.qty, 30);
    },
  );

  test(
    '30 concurrent local increment deltas apply against latest DB quantity',
    () async {
      await store.addTap(line(id: 'delta-seed'), operationId: 'delta-seed-op');
      final itemId = (await store.loadLines(
        restaurantId: 'restaurant-a',
        branchId: 'branch-a',
        orderId: 'order-a',
      )).single.id;
      await Future.wait([
        for (var index = 0; index < 30; index++)
          store.adjustQty(
            id: itemId,
            delta: 1,
            operationId: 'delta-operation-$index',
            restaurantId: 'restaurant-a',
            branchId: 'branch-a',
            orderId: 'order-a',
          ),
      ]);
      final lines = await store.loadLines(
        restaurantId: 'restaurant-a',
        branchId: 'branch-a',
        orderId: 'order-a',
      );
      expect(lines.single.qty, 31);
    },
  );

  test(
    'tap operation replay is idempotent and cannot change its payload',
    () async {
      final accepted = line(id: 'replayed-line');
      await store.addTap(accepted, operationId: 'same-operation');
      await store.addTap(accepted, operationId: 'same-operation');
      expect(
        (await store.loadLines(
          restaurantId: 'restaurant-a',
          branchId: 'branch-a',
          orderId: 'order-a',
        )).single.qty,
        1,
      );
      await expectLater(
        store.addTap(
          line(id: 'different-line', productId: 'different-product'),
          operationId: 'same-operation',
        ),
        throwsStateError,
      );
    },
  );

  test('server acknowledgement wins over same-ID local outbox draft', () {
    final draft = line(id: 'same-id').toOrderItem();
    final confirmed = OrderItem(
      id: draft.id,
      personNumber: draft.personNumber,
      personName: draft.personName,
      productId: draft.productId,
      productName: draft.productName,
      category: draft.category,
      qty: draft.qty,
      unitPrice: draft.unitPrice,
      total: draft.total,
      notes: draft.notes,
      sendToKitchen: draft.sendToKitchen,
      kitchenStatus: 'sent',
      paymentStatus: 'pending',
    );
    final remainingLocal = line(id: 'other-id').toOrderItem();
    final visible = unacknowledgedLocalCaptureDrafts(
      confirmedItems: [confirmed],
      localItems: [draft, remainingLocal],
    );
    expect(visible, hasLength(1));
    expect(visible.single.id, 'other-id');
    expect(visible.single.isLocalCaptureDraft, isTrue);
  });

  test(
    'captured lines survive database close and process-style reopen',
    () async {
      for (var index = 0; index < 5; index++) {
        await store.addTap(line(id: 'draft-$index', productId: 'taco-$index'));
      }
      await database.close();
      database = await databaseFactoryIo.openDatabase(databasePath);
      store = LocalOrderCaptureStore(database: database);

      final lines = await store.loadLines(
        restaurantId: 'restaurant-a',
        branchId: 'branch-a',
        orderId: 'order-a',
      );
      expect(lines, hasLength(5));
      expect(lines.map((entry) => entry.productId).toSet(), hasLength(5));
    },
  );

  test('personas and five flavors keep their independent quantities', () async {
    const quantities = [1, 2, 3, 5, 10];
    for (var flavor = 0; flavor < quantities.length; flavor++) {
      for (var tap = 0; tap < quantities[flavor]; tap++) {
        await store.addTap(
          line(
            id: 'person-1-flavor-$flavor-tap-$tap',
            productId: 'flavor-$flavor',
          ),
        );
      }
      await store.addTap(
        line(
          id: 'person-2-flavor-$flavor',
          productId: 'flavor-$flavor',
          personNumber: 2,
        ),
      );
    }
    final lines = await store.loadLines(
      restaurantId: 'restaurant-a',
      branchId: 'branch-a',
      orderId: 'order-a',
    );
    expect(lines, hasLength(10));
    for (var flavor = 0; flavor < quantities.length; flavor++) {
      expect(
        lines
            .singleWhere(
              (entry) =>
                  entry.productId == 'flavor-$flavor' &&
                  entry.personNumber == 1,
            )
            .qty,
        quantities[flavor],
      );
      expect(
        lines
            .singleWhere(
              (entry) =>
                  entry.productId == 'flavor-$flavor' &&
                  entry.personNumber == 2,
            )
            .qty,
        1,
      );
    }
  });

  test(
    'submission freezes stable id and payload; retry cannot include new edits',
    () async {
      await store.addTap(line(id: 'line-a'));
      final frozen = await store.freeze(
        restaurantId: 'restaurant-a',
        branchId: 'branch-a',
        orderId: 'order-a',
        sendToKitchen: true,
      );
      final retry = await store.freeze(
        restaurantId: 'restaurant-a',
        branchId: 'branch-a',
        orderId: 'order-a',
        sendToKitchen: false,
      );
      expect(retry.id, frozen.id);
      expect(retry.payloadHash, frozen.payloadHash);
      expect(retry.sendToKitchen, isTrue);
      await expectLater(store.addTap(line(id: 'line-new')), throwsStateError);
    },
  );

  test('only confirmed submission clears its frozen lines', () async {
    await store.addTap(line(id: 'line-a'));
    final frozen = await store.freeze(
      restaurantId: 'restaurant-a',
      branchId: 'branch-a',
      orderId: 'order-a',
      sendToKitchen: true,
    );
    await expectLater(
      store.complete(frozen.copyWithForTest(payloadHash: 'wrong')),
      throwsStateError,
    );
    expect(
      await store.loadLines(
        restaurantId: 'restaurant-a',
        branchId: 'branch-a',
        orderId: 'order-a',
      ),
      hasLength(1),
    );
    await store.complete(frozen);
    expect(
      await store.loadLines(
        restaurantId: 'restaurant-a',
        branchId: 'branch-a',
        orderId: 'order-a',
      ),
      isEmpty,
    );
  });
}

LocalOrderCaptureLine line({
  required String id,
  String productId = 'taco',
  int personNumber = 1,
}) => LocalOrderCaptureLine(
  id: id,
  restaurantId: 'restaurant-a',
  restaurantName: 'Restaurant',
  branchId: 'branch-a',
  branchName: 'Branch',
  orderId: 'order-a',
  tableId: 'table-a',
  tableName: 'Table 1',
  tableIds: const ['table-a'],
  tableNames: const ['Table 1'],
  tableGroupLabel: '',
  deviceUid: 'device-a',
  employeeId: 'employee-a',
  employeeName: 'Waiter',
  personNumber: personNumber,
  personName: 'Person $personNumber',
  productId: productId,
  productName: 'Taco',
  categoryId: 'tacos',
  categoryName: 'Tacos',
  qty: 1,
  unitPrice: 12,
  notes: '',
  sendToKitchen: true,
  affectsKitchenStock: false,
  kitchenStockItemId: null,
  kitchenStockItemName: null,
  kitchenStockUnit: null,
  stockConsumptionQty: null,
  recipeItems: const [],
  appliedPlatformId: null,
  appliedPlatformName: null,
  priceSource: 'store',
  capturedAtMicros: 1,
);

extension on LocalOrderCaptureSubmission {
  LocalOrderCaptureSubmission copyWithForTest({String? payloadHash}) =>
      LocalOrderCaptureSubmission(
        id: id,
        restaurantId: restaurantId,
        branchId: branchId,
        orderId: orderId,
        payloadHash: payloadHash ?? this.payloadHash,
        payloadJson: payloadJson,
        lineIds: lineIds,
        sendToKitchen: sendToKitchen,
        createdAtMicros: createdAtMicros,
      );
}
