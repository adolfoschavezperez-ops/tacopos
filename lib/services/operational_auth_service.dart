import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class OperationalAuthStatus {
  const OperationalAuthStatus({
    required this.ready,
    required this.authPresent,
    required this.uidPresent,
    required this.isAnonymous,
    this.errorCode,
    this.errorMessage,
  });

  const OperationalAuthStatus.ready({required bool isAnonymous})
    : this(
        ready: true,
        authPresent: true,
        uidPresent: true,
        isAnonymous: isAnonymous,
      );

  const OperationalAuthStatus.failed({
    required String errorMessage,
    String? errorCode,
  }) : this(
         ready: false,
         authPresent: false,
         uidPresent: false,
         isAnonymous: null,
         errorCode: errorCode,
         errorMessage: errorMessage,
       );

  final bool ready;
  final bool authPresent;
  final bool uidPresent;
  final bool? isAnonymous;
  final String? errorCode;
  final String? errorMessage;
}

class OperationalAuthService {
  OperationalAuthService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Future<OperationalAuthStatus> ensureSignedIn() async {
    try {
      var user = _auth.currentUser;
      _logBootstrap('expense-auth: bootstrap-start', user: user);

      if (user == null && !kIsWeb) {
        _logBootstrap('expense-auth: signin-start', user: null);
        final credential = await _auth.signInAnonymously();
        user = credential.user ?? _auth.currentUser;
        _logBootstrap('expense-auth: signin-success', user: user);
      }

      final ready = user != null && user.uid.trim().isNotEmpty;
      if (ready) {
        return OperationalAuthStatus.ready(isAnonymous: user.isAnonymous);
      }

      return const OperationalAuthStatus.failed(
        errorMessage:
            'No fue posible autenticar este dispositivo. Intenta nuevamente.',
        errorCode: 'user-null',
      );
    } on FirebaseAuthException catch (error, stackTrace) {
      _logAuthError(error, stackTrace);
      return OperationalAuthStatus.failed(
        errorCode: error.code,
        errorMessage:
            'No fue posible autenticar este dispositivo (${error.code}). Intenta nuevamente.',
      );
    } catch (error, stackTrace) {
      _logUnknownError(error, stackTrace);
      return const OperationalAuthStatus.failed(
        errorCode: 'unknown',
        errorMessage:
            'No fue posible autenticar este dispositivo (unknown). Intenta nuevamente.',
      );
    }
  }

  void _logBootstrap(String marker, {required User? user}) {
    if (!kDebugMode) return;
    developer.log(
      '$marker '
      'firebaseAppsInitialized=${Firebase.apps.isNotEmpty} '
      'currentUserExists=${user != null} '
      'uidPresent=${user?.uid.trim().isNotEmpty ?? false} '
      'isAnonymous=${user?.isAnonymous}',
      name: 'OperationalAuthService',
    );
  }

  void _logAuthError(FirebaseAuthException error, StackTrace stackTrace) {
    if (!kDebugMode) return;
    developer.log(
      'expense-auth: signin-error '
      'firebaseAppsInitialized=${Firebase.apps.isNotEmpty} '
      'exceptionType=${error.runtimeType} '
      'firebaseAuthCode=${error.code} '
      'firebaseAuthMessage=${error.message}',
      name: 'OperationalAuthService',
      error: {'code': error.code, 'message': error.message},
      stackTrace: stackTrace,
    );
  }

  void _logUnknownError(Object error, StackTrace stackTrace) {
    if (!kDebugMode) return;
    developer.log(
      'expense-auth: signin-error '
      'firebaseAppsInitialized=${Firebase.apps.isNotEmpty} '
      'exceptionType=${error.runtimeType} '
      'firebaseAuthCode=unknown '
      'firebaseAuthMessage=$error',
      name: 'OperationalAuthService',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
