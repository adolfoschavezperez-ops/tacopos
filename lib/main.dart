import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'services/operational_session_service.dart';
import 'widgets/app_update_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _activateAppCheck();
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
      home: kIsWeb
          ? const LoginGate()
          : const AppUpdateGate(child: LoginGate()),
    );
  }
}
