import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/local_order_capture.dart';
import 'package:tacopos/services/local_order_capture_submitter.dart';

void main() {
  const submission = LocalOrderCaptureSubmission(
    id: 'submission-abc123',
    restaurantId: 'restaurant',
    branchId: 'branch',
    orderId: 'order-abc123',
    payloadHash: 'hash',
    payloadJson: '[]',
    lineIds: [],
    sendToKitchen: true,
    createdAtMicros: 1,
  );

  test(
    'explicit App Check rejection retries once with the same submission',
    () async {
      var calls = 0;
      var retryNotified = 0;
      final submitted = <LocalOrderCaptureSubmission>[];
      final client = LocalOrderCaptureSubmitter.fake((value) async {
        calls++;
        submitted.add(value);
        if (calls == 1) {
          throw FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'Decoding App Check token failed',
          );
        }
        return {'submissionId': value.id, 'state': 'committed'};
      });

      final result = await client.submit(
        submission,
        onAppCheckRetry: () => retryNotified++,
      );

      expect(calls, 2);
      expect(retryNotified, 1);
      expect(identical(submitted[0], submitted[1]), isTrue);
      expect(result['submissionId'], submission.id);
    },
  );

  test('generic auth rejection is not retried', () async {
    var calls = 0;
    final client = LocalOrderCaptureSubmitter.fake((_) async {
      calls++;
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Authentication required',
      );
    });

    await expectLater(
      client.submit(submission),
      throwsA(isA<FirebaseFunctionsException>()),
    );
    expect(calls, 1);
  });

  test(
    'persistent explicit App Check rejection stops after one retry',
    () async {
      var calls = 0;
      final client = LocalOrderCaptureSubmitter.fake((_) async {
        calls++;
        throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'AppCheck token was rejected',
        );
      });

      await expectLater(
        client.submit(submission),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      expect(calls, 2);
    },
  );

  test('concurrent App Check failures retry serially per submission', () async {
    final retryRelease = Completer<void>();
    var firstCalls = 0;
    var secondCalls = 0;
    var retries = 0;
    final first = LocalOrderCaptureSubmitter.fake((value) async {
      firstCalls++;
      if (firstCalls == 1) {
        throw FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'App Check token was rejected',
        );
      }
      await retryRelease.future;
      return {'submissionId': value.id};
    });
    final second = LocalOrderCaptureSubmitter.fake((_) async {
      secondCalls++;
      if (secondCalls == 1) {
        throw FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'App Check token was rejected',
        );
      }
      return {'submissionId': submission.id, 'state': 'committed'};
    });

    final firstSubmission = first.submit(
      submission,
      onAppCheckRetry: () => retries++,
    );
    await Future<void>.delayed(Duration.zero);
    final secondSubmission = second.submit(
      submission,
      onAppCheckRetry: () => retries++,
    );

    retryRelease.complete();
    await expectLater(firstSubmission, completes);
    await expectLater(secondSubmission, completes);
    expect(firstCalls, 2);
    expect(secondCalls, 2);
    expect(retries, 2);
  });
}
