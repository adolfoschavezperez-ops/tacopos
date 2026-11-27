import 'package:flutter/foundation.dart';

import 'operational_diagnostics_service.dart';

/// Local-only timing spans for login diagnosis in debug builds.
///
/// Events are written to OperationalDiagnosticsService's bounded device file;
/// no PIN, token, employee ID, exception message, or Firebase write is added.
class LoginPerformanceTrace {
  LoginPerformanceTrace._();

  static Stopwatch? _appLaunch;

  static void beginAppLaunch() {
    if (!kDebugMode) return;
    _appLaunch = Stopwatch()..start();
    mark('app_launch_begin');
  }

  static void mark(String stage, {String result = 'ok'}) {
    if (!kDebugMode) return;
    OperationalDiagnosticsService.instance.record(
      'login_perf',
      stage,
      result: result,
      duration: _appLaunch?.elapsed,
      fields: {'stage': stage},
    );
  }

  static Stopwatch start() => kDebugMode ? (Stopwatch()..start()) : Stopwatch();

  static void finish(
    String stage,
    Stopwatch timer, {
    String result = 'ok',
    Object? error,
  }) {
    if (!kDebugMode) return;
    OperationalDiagnosticsService.instance.record(
      'login_perf',
      stage,
      result: error?.runtimeType.toString() ?? result,
      duration: timer.elapsed,
      fields: {
        'stage': stage,
        if (error != null) 'errorCode': error.runtimeType.toString(),
      },
    );
  }

  static Future<T> measure<T>(
    String stage,
    Future<T> Function() operation,
  ) async {
    if (!kDebugMode) return operation();
    final timer = start();
    try {
      final result = await operation();
      finish(stage, timer);
      return result;
    } catch (error) {
      finish(stage, timer, error: error);
      rethrow;
    }
  }
}
