import 'package:cloud_functions/cloud_functions.dart';

import '../core/orders/local_order_capture.dart';

class LocalOrderCaptureSubmitter {
  LocalOrderCaptureSubmitter._(this._call);

  factory LocalOrderCaptureSubmitter.production({
    FirebaseFunctions? functions,
  }) {
    return LocalOrderCaptureSubmitter._((submission) async {
      final instance =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
      final response = await instance
          .httpsCallable(
            'submitLocalOrderCapture',
            options: HttpsCallableOptions(limitedUseAppCheckToken: true),
          )
          .call(submission.toMap());
      if (response.data is! Map) {
        throw StateError('El servidor devolvio una respuesta invalida.');
      }
      return Map<String, dynamic>.from(response.data as Map);
    });
  }

  factory LocalOrderCaptureSubmitter.fake(
    Future<Map<String, dynamic>> Function(
      LocalOrderCaptureSubmission submission,
    )
    call,
  ) => LocalOrderCaptureSubmitter._(call);

  final Future<Map<String, dynamic>> Function(
    LocalOrderCaptureSubmission submission,
  )
  _call;

  Future<Map<String, dynamic>> submit(LocalOrderCaptureSubmission submission) =>
      _call(submission);
}
