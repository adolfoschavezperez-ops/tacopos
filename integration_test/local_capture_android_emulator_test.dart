import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:tacopos/core/orders/local_order_capture.dart';
import 'package:tacopos/services/local_order_capture_store.dart';

const _projectId = String.fromEnvironment(
  'TACOPOS_EMULATOR_PROJECT_ID',
  defaultValue: 'demo-tacopos-local-capture',
);
const _emulatorHost = String.fromEnvironment(
  'TACOPOS_EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);
const _functionsPort = int.fromEnvironment(
  'TACOPOS_FUNCTIONS_EMULATOR_PORT',
  defaultValue: 5002,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android outbox survives database reopen and recovers a committed lost response idempotently',
    (_) async {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'emulator-only-invalid-key',
          appId: '1:000000000000:android:0000000000000000000000',
          messagingSenderId: '000000000000',
          projectId: _projectId,
        ),
      );
      final auth = FirebaseAuth.instance;
      auth.useAuthEmulator(_emulatorHost, 9099);
      await auth.signInWithEmailAndPassword(
        email: 'capture-test@example.invalid',
        password: 'emulator-only-password',
      );
      final uid = auth.currentUser!.uid;
      expect(uid, 'local-capture-android-test');

      final firestore = FirebaseFirestore.instance;
      firestore.useFirestoreEmulator(_emulatorHost, 8080);
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      functions.useFunctionsEmulator(_emulatorHost, _functionsPort);

      final directory = await getApplicationSupportDirectory();
      final databasePath = path.join(
        directory.path,
        'capture-emulator-test.db',
      );
      await databaseFactoryIo.deleteDatabase(databasePath);

      Database database = await databaseFactoryIo.openDatabase(databasePath);
      LocalOrderCaptureStore store = LocalOrderCaptureStore(database: database);
      for (var index = 0; index < 30; index++) {
        await store.addTap(
          _captureLine(uid: uid, id: 'tap-line-$index', capturedAt: index),
          operationId: 'tap-operation-$index',
        );
      }
      final orderScope = {
        'restaurantId': 'local-capture-demo',
        'branchId': 'branch-demo',
        'orderId': 'android-order',
      };
      final locallySaved = await store.loadLines(
        restaurantId: orderScope['restaurantId']!,
        branchId: orderScope['branchId']!,
        orderId: orderScope['orderId']!,
      );
      expect(locallySaved, hasLength(1));
      expect(locallySaved.single.qty, 30);

      await database.close();
      database = await databaseFactoryIo.openDatabase(databasePath);
      store = LocalOrderCaptureStore(database: database);
      final restored = await store.loadLines(
        restaurantId: orderScope['restaurantId']!,
        branchId: orderScope['branchId']!,
        orderId: orderScope['orderId']!,
      );
      expect(restored.single.qty, 30);

      final submission = await store.freeze(
        restaurantId: orderScope['restaurantId']!,
        branchId: orderScope['branchId']!,
        orderId: orderScope['orderId']!,
        sendToKitchen: true,
      );
      final payload = submission.toMap();
      final submit = functions.httpsCallable('submitLocalOrderCapture');
      final resolve = functions.httpsCallable(
        'resolveLocalOrderCaptureSubmission',
      );

      Object? lostResponse;
      try {
        await submit.call(payload);
      } catch (error) {
        lostResponse = error;
      }
      expect(lostResponse, isNotNull);

      final resolution = Map<String, dynamic>.from(
        (await resolve.call(payload)).data as Map,
      );
      expect(resolution['state'], 'committed');
      final retry = Map<String, dynamic>.from(
        (await submit.call(payload)).data as Map,
      );
      final confirmedResult = Map<String, dynamic>.from(
        resolution['result'] as Map,
      );
      expect(retry['submissionId'], submission.id);
      expect(retry['payloadHash'], submission.payloadHash);
      expect(retry['acceptedQty'], 30);
      expect(retry['acceptedLineCount'], 1);
      expect(retry['sentCount'], 1);
      expect(confirmedResult['submissionId'], retry['submissionId']);
      expect(confirmedResult['payloadHash'], retry['payloadHash']);

      final restaurant = firestore
          .collection('restaurants')
          .doc('local-capture-demo');
      final order = await restaurant
          .collection('orders')
          .doc('android-order')
          .get(const GetOptions(source: Source.server));
      final items = await restaurant
          .collection('orders')
          .doc('android-order')
          .collection('items')
          .get(const GetOptions(source: Source.server));
      final batches = await restaurant
          .collection('orders')
          .doc('android-order')
          .collection('kitchenBatches')
          .get(const GetOptions(source: Source.server));
      expect(items.docs, hasLength(1));
      expect(items.docs.single.id, restored.single.id);
      expect(items.docs.single.data()['qty'], 30);
      expect(items.docs.single.data()['total'], 360);
      expect(items.docs.single.data()['kitchenStatus'], 'sent');
      expect(batches.docs, hasLength(1));
      expect(order.data()?['total'], 360);
      expect(order.data()?['pendingTotal'], 360);
      expect(order.data()?['paymentStatus'], 'pending');

      await store.complete(submission);
      expect(
        await store.loadLines(
          restaurantId: orderScope['restaurantId']!,
          branchId: orderScope['branchId']!,
          orderId: orderScope['orderId']!,
        ),
        isEmpty,
      );
      await database.close();
      await databaseFactoryIo.deleteDatabase(databasePath);
      await auth.signOut();
    },
  );
}

LocalOrderCaptureLine _captureLine({
  required String uid,
  required String id,
  required int capturedAt,
}) => LocalOrderCaptureLine(
  id: id,
  restaurantId: 'local-capture-demo',
  restaurantName: 'Demo',
  branchId: 'branch-demo',
  branchName: 'Demo',
  orderId: 'android-order',
  tableId: 'table-demo',
  tableName: 'Mesa demo',
  tableIds: const ['table-demo'],
  tableNames: const ['Mesa demo'],
  tableGroupLabel: '',
  deviceUid: uid,
  employeeId: 'waiter-demo',
  employeeName: 'Mesero Demo',
  personNumber: 1,
  personName: 'Persona 1',
  productId: 'taco-demo',
  productName: 'Taco demo',
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
  capturedAtMicros: 1_795_584_000_000_000 + capturedAt,
);
