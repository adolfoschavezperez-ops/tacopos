import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'backoffice_v2/app/backoffice_app.dart';
import 'backoffice_v2/app/isolation_blocked_screen.dart';
import 'backoffice_v2/core/env/backoffice_env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final BackofficeConfig config;
  try {
    config = EnvironmentGuard.resolveFromEnvironment();
  } catch (error) {
    runApp(IsolationBlockedApp(error: error));
    return;
  }

  await Firebase.initializeApp(options: config.firebaseOptions);

  if (config.useEmulators) {
    await FirebaseAuth.instance.useAuthEmulator(
      config.emulatorHost,
      config.authEmulatorPort,
    );
    FirebaseFirestore.instance.useFirestoreEmulator(
      config.emulatorHost,
      config.firestoreEmulatorPort,
    );
    FirebaseFunctions.instanceFor(region: config.functionsRegion)
        .useFunctionsEmulator(
          config.emulatorHost,
          config.functionsEmulatorPort,
        );
  }

  runApp(BackofficeV2App(config: config));
}
