import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/local_order_capture.dart';
import 'package:tacopos/core/orders/submission_error_presentation.dart';

void main() {
  test('safely aborted unwraps original business failure', () {
    final result = SubmissionErrorPresentation.from(
      LocalOrderCaptureSafelyAborted(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'El producto fue desactivado.',
        ),
      ),
    );

    expect(result.isConnectivityFailure, isFalse);
    expect(result.canRetry, isFalse);
    expect(result.message, 'El producto fue desactivado.');
  });

  test('only transport timeout/unavailable is called connectivity failure', () {
    final result = SubmissionErrorPresentation.from(
      LocalOrderCaptureSafelyAborted(
        FirebaseFunctionsException(code: 'unavailable', message: ''),
      ),
    );

    expect(result.isConnectivityFailure, isTrue);
    expect(result.canRetry, isTrue);
    expect(result.message, contains('Conexión inestable'));
  });

  test('App Check rejection is not presented as expired employee session', () {
    final result = SubmissionErrorPresentation.from(
      LocalOrderCaptureSafelyAborted(
        FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'App Check token invalid',
        ),
      ),
    );

    expect(result.isConnectivityFailure, isFalse);
    expect(result.canRetry, isFalse);
    expect(result.message, contains('validar esta instalación'));
  });

  test('unknown error receives neutral saved-order message', () {
    final result = SubmissionErrorPresentation.from(StateError('unexpected'));

    expect(result.isConnectivityFailure, isFalse);
    expect(result.canRetry, isTrue);
    expect(result.message, contains('No se pudo confirmar'));
    expect(result.message, isNot(contains('Conexión inestable')));
  });
}
