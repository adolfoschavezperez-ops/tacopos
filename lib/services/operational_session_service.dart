import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'device_registry_service.dart';
import 'app_update_service.dart';
import 'operational_auth_service.dart';
import 'operational_diagnostics_service.dart';

class OperationalSessionStatus {
  const OperationalSessionStatus({
    required this.ready,
    required this.authReady,
    required this.deviceReady,
    this.authErrorCode,
    this.message,
  });

  const OperationalSessionStatus.ready()
    : this(ready: true, authReady: true, deviceReady: true);

  const OperationalSessionStatus.authNotReady({
    String? authErrorCode,
    String? message,
  }) : this(
         ready: false,
         authReady: false,
         deviceReady: false,
         authErrorCode: authErrorCode,
         message: message,
       );

  const OperationalSessionStatus.deviceNotReady(String message)
    : this(ready: false, authReady: true, deviceReady: false, message: message);

  final bool ready;
  final bool authReady;
  final bool deviceReady;
  final String? authErrorCode;
  final String? message;
}

class OperationalSessionService {
  OperationalSessionService({
    FirebaseAuth? auth,
    OperationalAuthService? authService,
    DeviceRegistryService? deviceRegistryService,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _authService = authService ?? OperationalAuthService(auth: auth),
       _deviceRegistryService =
           deviceRegistryService ?? DeviceRegistryService.instance;

  static final instance = OperationalSessionService();

  final FirebaseAuth _auth;
  final OperationalAuthService _authService;
  final DeviceRegistryService _deviceRegistryService;

  Future<OperationalAuthStatus> bootstrapAuth() async {
    final timer = Stopwatch()..start();
    _log('app-bootstrap: start');
    final status = await _authService.ensureSignedIn();
    if (status.ready) {
      try {
        await _auth.currentUser?.getIdToken();
        _log('auth: ready');
      } on FirebaseAuthException catch (error, stackTrace) {
        // A cached anonymous Firebase session can still restore the operator
        // after a process restart while a transient network interruption is
        // preventing token refresh. Firestore authorization is rechecked
        // before the operator session is restored.
        _log(
          'auth: token-refresh-pending code=${error.code}',
          error,
          stackTrace,
        );
      }
    } else {
      _log('auth: not-ready authErrorCode=${status.errorCode ?? 'none'}');
    }
    timer.stop();
    OperationalDiagnosticsService.instance.record(
      'auth',
      'bootstrap',
      result: status.ready ? 'ready' : 'pending',
      duration: timer.elapsed,
      fields: {if (status.errorCode != null) 'errorCode': status.errorCode},
    );
    return status;
  }

  Future<OperationalSessionStatus> ensureReadyForCurrentSession({
    AppUpdateCheckResult? updateResult,
  }) async {
    final authStatus = _authService.currentStatus();
    if (!authStatus.ready) {
      _log('auth: not-ready authErrorCode=${authStatus.errorCode ?? 'none'}');
      return OperationalSessionStatus.authNotReady(
        authErrorCode: authStatus.errorCode,
        message: authStatus.errorMessage,
      );
    }

    try {
      final timer = Stopwatch()..start();
      await _deviceRegistryService.recordHeartbeat(
        updateResult: updateResult,
        force: true,
      );
      await _deviceRegistryService.ensureCurrentDeviceReady(
        recordHeartbeat: false,
      );
      _log('device: ready');
      timer.stop();
      OperationalDiagnosticsService.instance.record(
        'auth',
        'device_validation',
        duration: timer.elapsed,
        result: 'ready',
      );
      return const OperationalSessionStatus.ready();
    } on DeviceRegistryException catch (error, stackTrace) {
      OperationalDiagnosticsService.instance.record(
        'auth',
        'device_validation',
        result: error.code,
      );
      _log(
        'device: not-ready deviceErrorCode=${error.code}',
        error,
        stackTrace,
      );
      return OperationalSessionStatus.deviceNotReady(error.message);
    } catch (error, stackTrace) {
      OperationalDiagnosticsService.instance.record(
        'auth',
        'device_validation',
        result: 'error',
      );
      _log('device: not-ready deviceErrorCode=unknown', error, stackTrace);
      return const OperationalSessionStatus.deviceNotReady(
        'Este dispositivo no esta registrado o activo.',
      );
    }
  }

  void _log(String marker, [Object? error, StackTrace? stackTrace]) {
    if (!kDebugMode) return;
    unawaited(
      Future<void>(() {
        developer.log(
          marker,
          name: 'OperationalSessionService',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }
}
