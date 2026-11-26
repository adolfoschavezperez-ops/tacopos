import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tacopos/screens/login_screen.dart';
import 'package:tacopos/services/app_session.dart';
import 'package:tacopos/services/operational_employee_session_service.dart';

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
  defaultValue: 9101,
);
const _firestorePort = int.fromEnvironment(
  'TACOPOS_FIRESTORE_EMULATOR_PORT',
  defaultValue: 8082,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'LoginGate keeps the validated employee session after Firebase token refresh and resume',
    (tester) async {
      if (_projectId.startsWith('demo-') != true) {
        throw StateError('This integration test only permits a demo project.');
      }
      final app = Firebase.apps.isEmpty
          ? await Firebase.initializeApp(
              options: const FirebaseOptions(
                apiKey: 'AIzaSyD3moTacoPOSLocalEmulatorOnly00000',
                appId: '1:000000000000:android:0000000000000000000000',
                messagingSenderId: '000000000000',
                projectId: _projectId,
              ),
            )
          : Firebase.app();
      final auth = FirebaseAuth.instanceFor(app: app);
      auth.useAuthEmulator(_host, _authPort);
      final firestore = FirebaseFirestore.instanceFor(app: app);
      firestore.useFirestoreEmulator(_host, _firestorePort);

      expect(auth.currentUser, isNotNull);
      await tester.pumpWidget(const MaterialApp(home: LoginGate()));
      await tester.pump(const Duration(seconds: 3));

      expect(AppSession.instance.isLoggedIn, isTrue);
      final employeeId = AppSession.instance.employee!.id;
      final branchId = AppSession.instance.currentBranchId;
      final token = await auth.currentUser!.getIdToken(true);
      expect(token, isNotEmpty);

      final refreshResult = await OperationalEmployeeSessionService.instance
          .revalidateCurrentSession();
      expect(refreshResult.status, OperationalSessionRestoreStatus.restored);
      expect(AppSession.instance.employee?.id, employeeId);
      expect(AppSession.instance.currentBranchId, branchId);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 3));

      expect(AppSession.instance.isLoggedIn, isTrue);
      expect(AppSession.instance.employee?.id, employeeId);
      expect(AppSession.instance.currentBranchId, branchId);
      expect(firestore.app.options.projectId, _projectId);
    },
  );
}
