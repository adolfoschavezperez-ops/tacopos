import 'package:cloud_functions/cloud_functions.dart';

import '../core/orders/local_order_capture.dart';

class LocalOrderCaptureSubmitter {
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
            options: HttpsCallableOptions(limitedUseAppCheckToken: true),
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

  Future<Map<String, dynamic>> submit(LocalOrderCaptureSubmission submission) =>
      _call(submission);

  Future<Map<String, dynamic>> resolve(
    LocalOrderCaptureSubmission submission,
  ) => _resolve(submission);
}
