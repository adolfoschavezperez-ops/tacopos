import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../core/orders/local_order_capture.dart';

const _useFirebaseEmulators = bool.fromEnvironment(
  'TACOPOS_FIREBASE_EMULATORS',
  defaultValue: false,
);

class LocalOrderCaptureSubmitter {
  static Future<void> _appCheckRetryTail = Future<void>.value();

  LocalOrderCaptureSubmitter._(this._call, this._resolve);

  factory LocalOrderCaptureSubmitter.production({
    FirebaseFunctions? functions,
  }) {
    Future<Map<String, dynamic>> call(
      String name,
      LocalOrderCaptureSubmission submission,
    ) async {
      final instance =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      final response = await instance
          .httpsCallable(
            name,
            options: HttpsCallableOptions(
              // Functions Emulator deliberately disables App Check
              // enforcement; requesting a limited-use production token in
              // this isolated demo mode would require a real provider/service.
              // Release builds keep limited-use App Check tokens enabled.
              limitedUseAppCheckToken: !_useFirebaseEmulators,
            ),
          )
          .call(submission.toMap());
      if (response.data is! Map) {
        throw StateError('El servidor devolvio una respuesta invalida.');
      }
      return Map<String, dynamic>.from(response.data as Map);
    }

    return LocalOrderCaptureSubmitter._(
      (submission) => call('submitLocalOrderCapture', submission),
      (submission) => call('resolveLocalOrderCaptureSubmission', submission),
    );
  }

  factory LocalOrderCaptureSubmitter.fake(
    Future<Map<String, dynamic>> Function(
      LocalOrderCaptureSubmission submission,
    )
    call, {
    Future<Map<String, dynamic>> Function(
      LocalOrderCaptureSubmission submission,
    )?
    resolve,
  }) => LocalOrderCaptureSubmitter._(
    call,
    resolve ??
        (_) => Future.error(
          StateError('La resolucion de envios no esta disponible.'),
        ),
  );

  final Future<Map<String, dynamic>> Function(
    LocalOrderCaptureSubmission submission,
  )
  _call;
  final Future<Map<String, dynamic>> Function(
    LocalOrderCaptureSubmission submission,
  )
  _resolve;

  Future<Map<String, dynamic>> submit(
    LocalOrderCaptureSubmission submission, {
    void Function()? onAppCheckRetry,
  }) =>
      _submitWithAppCheckRecovery(submission, onAppCheckRetry: onAppCheckRetry);

  Future<Map<String, dynamic>> _submitWithAppCheckRecovery(
    LocalOrderCaptureSubmission submission, {
    void Function()? onAppCheckRetry,
  }) async {
    try {
      return await _call(submission);
    } on FirebaseFunctionsException catch (error) {
      if (!_isExplicitAppCheckRejection(error)) rethrow;
      // Serialize retries so simultaneous rejected requests don't fan out
      // token recovery calls. Every order still gets one retry with its own
      // frozen payload and idempotency key.
      final previousRetry = _appCheckRetryTail;
      final retrySlot = Completer<void>();
      _appCheckRetryTail = retrySlot.future;
      await previousRetry;
      try {
        onAppCheckRetry?.call();
        // The callable SDK obtains a fresh limited-use App Check token.
        return await _call(submission);
      } finally {
        retrySlot.complete();
      }
    }
  }

  static bool isExplicitAppCheckRejection(FirebaseFunctionsException error) =>
      _isExplicitAppCheckRejection(error);

  Future<Map<String, dynamic>> resolve(
    LocalOrderCaptureSubmission submission,
  ) => _resolve(submission);
}

bool _isExplicitAppCheckRejection(FirebaseFunctionsException error) {
  if (error.code != 'unauthenticated' && error.code != 'permission-denied') {
    return false;
  }
  final details = error.details;
  final detailText = details is Map
      ? '${details['reason'] ?? ''} ${details['message'] ?? ''}'
      : details?.toString() ?? '';
  final text = '${error.message ?? ''} $detailText'.toLowerCase();
  return text.contains('app check') ||
      text.contains('appcheck') ||
      text.contains('app_check') ||
      text.contains('decoding app check token failed');
}
