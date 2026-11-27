import 'package:firebase_core/firebase_core.dart';

/// Isolated Firebase configuration for the `tacopos-backoffice-dev` project.
///
/// Never references production (`tacopos-renovadev`) credentials or endpoints.
class BackofficeDevFirebaseOptions {
  const BackofficeDevFirebaseOptions._();

  static const String projectId = 'tacopos-backoffice-dev';

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAOwtsS_OQWslygRAtEp8U-zuuecobsLAo',
    appId: '1:422466617516:web:cf170e732b6eaa5aa69f09',
    messagingSenderId: '422466617516',
    projectId: projectId,
    authDomain: 'tacopos-backoffice-dev.firebaseapp.com',
    storageBucket: 'tacopos-backoffice-dev.firebasestorage.app',
  );

  /// Synthetic local emulator configuration (never connects to remote GCP).
  static const FirebaseOptions localEmulator = FirebaseOptions(
    apiKey: 'AIzaSyDemoBackofficeV2LocalEmulatorOnly00',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-tacopos-backoffice-v2',
    authDomain: 'localhost',
    storageBucket: 'demo-tacopos-backoffice-v2.appspot.com',
  );
}
