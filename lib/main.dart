import 'dart:async';

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
import 'services/operational_diagnostics_service.dart';
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
const _authEmulatorPort = int.fromEnvironment(
  'TACOPOS_AUTH_EMULATOR_PORT',
  defaultValue: 9099,
);
const _firestoreEmulatorPort = int.fromEnvironment(
  'TACOPOS_FIRESTORE_EMULATOR_PORT',
  defaultValue: 8080,
);
const _functionsEmulatorPort = int.fromEnvironment(
  'TACOPOS_FUNCTIONS_EMULATOR_PORT',
  defaultValue: 5001,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_useFirebaseEmulators &&
      (!kDebugMode ||
          !_emulatorProjectId.startsWith('demo-') ||
          _authEmulatorPort < 1 ||
          _authEmulatorPort > 65535 ||
          _firestoreEmulatorPort < 1 ||
          _firestoreEmulatorPort > 65535 ||
          _functionsEmulatorPort < 1 ||
          _functionsEmulatorPort > 65535)) {
    throw StateError(
      'El modo Firebase Emulator solo admite debug y proyectos demo-*.',
    );
  }
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: _useFirebaseEmulators
          ? FirebaseOptions(
              // The Firebase client SDK validates the API-key shape before
              // sending callable requests, even when the endpoint is local.
              // This syntactically valid placeholder is used only for the
              // demo-project emulator path; no release build can select it.
              apiKey: 'AIzaSyD3moTacoPOSLocalEmulatorOnly00000',
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
    FirebaseAuth.instance.useAuthEmulator(_emulatorHost, _authEmulatorPort);
    FirebaseFirestore.instance.useFirestoreEmulator(
      _emulatorHost,
      _firestoreEmulatorPort,
    );
    FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).useFunctionsEmulator(_emulatorHost, _functionsEmulatorPort);
  } else {
    await _activateAppCheck();
  }
  await _ensureAnonymousLogin();
  unawaited(OperationalDiagnosticsService.instance.initialize());

  runApp(const TacoPosApp());
}

Future<void> _activateAppCheck() async {
  if (kIsWeb) {
    return;
  }
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kReleaseMode
          ? const AndroidPlayIntegrityProvider()
          : const AndroidDebugProvider(),
    );
    OperationalDiagnosticsService.instance.record(
      'app_check',
      'activation',
      result: 'ready',
    );
  } catch (error) {
    OperationalDiagnosticsService.instance.record(
      'app_check',
      'activation',
      result: error.runtimeType.toString(),
    );
    rethrow;
  }
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
