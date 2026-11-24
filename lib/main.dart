import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'services/operational_session_service.dart';
import 'widgets/app_update_gate.dart';
import 'widgets/expense_cutoff_reminder_coordinator.dart';

const _useFirebaseEmulators = bool.fromEnvironment(
  'TACOPOS_FIREBASE_EMULATORS',
  defaultValue: false,
);
const _emulatorProjectId = String.fromEnvironment(
  'TACOPOS_EMULATOR_PROJECT_ID',
  defaultValue: 'demo-tacopos-local-capture',
);
const _emulatorHost = String.fromEnvironment(
  'TACOPOS_EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_useFirebaseEmulators &&
      (!kDebugMode || !_emulatorProjectId.startsWith('demo-'))) {
    throw StateError(
      'El modo Firebase Emulator solo admite debug y proyectos demo-*.',
    );
  }
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: _useFirebaseEmulators
          ? FirebaseOptions(
              apiKey: 'emulator-only-invalid-key',
              appId: '1:000000000000:android:0000000000000000000000',
              messagingSenderId: '000000000000',
              projectId: _emulatorProjectId,
            )
          : DefaultFirebaseOptions.currentPlatform,
    );
  } else if (_useFirebaseEmulators &&
      Firebase.app().options.projectId != _emulatorProjectId) {
    throw StateError(
      'Firebase nativo apunta a ${Firebase.app().options.projectId}; '
      'el emulador requiere $_emulatorProjectId.',
    );
  }
  if (_useFirebaseEmulators) {
    FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
    FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).useFunctionsEmulator(_emulatorHost, 5001);
  } else {
    await _activateAppCheck();
  }
  await _ensureAnonymousLogin();

  runApp(const TacoPosApp());
}

Future<void> _activateAppCheck() async {
  if (kIsWeb) {
    return;
  }
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kReleaseMode
        ? const AndroidPlayIntegrityProvider()
        : const AndroidDebugProvider(),
  );
}

Future<void> _ensureAnonymousLogin() async {
  if (kIsWeb) {
    return;
  }
  final status = await OperationalSessionService.instance.bootstrapAuth();
  if (!status.ready) {
    throw FirebaseAuthException(
      code: status.errorCode ?? 'unknown',
      message: status.errorMessage,
    );
  }
}

class TacoPosApp extends StatelessWidget {
  const TacoPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kIsWeb ? 'TacoPOS Backoffice' : 'TacoPOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      builder: (context, child) => kIsWeb
          ? child ?? const SizedBox.shrink()
          : ExpenseCutoffReminderCoordinator(
              child: child ?? const SizedBox.shrink(),
            ),
      home: kIsWeb
          ? const LoginGate()
          : _useFirebaseEmulators
          ? const LoginGate()
          : const AppUpdateGate(child: LoginGate()),
    );
  }
}
