import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _projectId = String.fromEnvironment(
  'TACOPOS_EMULATOR_PROJECT_ID',
  defaultValue: 'demo-tacopos-2-0-1',
);
const _host = String.fromEnvironment(
  'TACOPOS_EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);
const _authPort = int.fromEnvironment(
  'TACOPOS_AUTH_EMULATOR_PORT',
  defaultValue: 9099,
);
const _firestorePort = int.fromEnvironment(
  'TACOPOS_FIRESTORE_EMULATOR_PORT',
  defaultValue: 8080,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android SDK reads branch tables and payment collectionGroup from candidate Rules',
    (tester) async {
      // Validate the Android default app created from google-services.json.
      // The production app uses these default instances; a separately named
      // Firebase app below must not mask a mismatched native configuration.
      final defaultApp = await Firebase.initializeApp();
      expect(defaultApp.options.projectId, _projectId);
      final defaultAuth = FirebaseAuth.instanceFor(app: defaultApp);
      defaultAuth.useAuthEmulator(_host, _authPort);
      await defaultAuth.signInAnonymously();
      final defaultFirestore = FirebaseFirestore.instanceFor(app: defaultApp);
      defaultFirestore.useFirestoreEmulator(_host, _firestorePort);
      final defaultTables = await defaultFirestore
          .collection('restaurants')
          .doc('main_restaurant')
          .collection('tables')
          .get();
      expect(defaultTables.docs, hasLength(4));
      expect(
        defaultTables.docs.every(
          (table) => table.data()['branchId'] == 'aviacion',
        ),
        isTrue,
      );
      await defaultAuth.signOut();

      final app = await Firebase.initializeApp(
        name: 'phase6-candidate-rules',
        options: FirebaseOptions(
          apiKey: 'AIzaSyD3moTacoPOSLocalEmulatorOnly00000',
          appId: '1:000000000000:android:0000000000000000000000',
          messagingSenderId: '000000000000',
          projectId: _projectId,
        ),
      );
      final auth = FirebaseAuth.instanceFor(app: app);
      auth.useAuthEmulator(_host, _authPort);
      await auth.signInAnonymously();

      final firestore = FirebaseFirestore.instanceFor(app: app);
      firestore.useFirestoreEmulator(_host, _firestorePort);
      final restaurant = firestore
          .collection('restaurants')
          .doc('main_restaurant');
      final tables = await restaurant.collection('tables').get();
      expect(tables.docs, isNotEmpty);
      expect(
        tables.docs.every((table) => table.data()['branchId'] == 'aviacion'),
        isTrue,
      );

      final employees = await restaurant.collection('employees').get();
      expect(
        employees.docs.map((employee) => employee.id),
        containsAll(['admin', 'cashier', 'cook', 'waiter_a', 'waiter_b']),
      );

      final payments = await firestore.collectionGroup('payments').get();
      expect(payments, isA<QuerySnapshot<Map<String, dynamic>>>());
      await auth.signOut();
      await app.delete();
    },
  );
}
