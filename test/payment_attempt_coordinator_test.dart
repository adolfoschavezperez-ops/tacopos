import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/payments/payment_attempt_coordinator.dart';
import 'package:uuid/uuid.dart';

void main() {
  setUp(PaymentAttemptCoordinator.clearForTesting);
  tearDown(PaymentAttemptCoordinator.clearForTesting);

  test('retry and widget reconstruction reuse the same attempt', () {
    final first = PaymentAttemptCoordinator(uuid: const Uuid());
    final attemptId = first.acquire('order|full_table');

    final reconstructed = PaymentAttemptCoordinator(uuid: const Uuid());

    expect(reconstructed.acquire('order|full_table'), attemptId);
  });

  test('failure before persistence keeps the attempt available for retry', () {
    final coordinator = PaymentAttemptCoordinator(uuid: const Uuid());
    final beforeFailure = coordinator.acquire('order|full_table');

    // A thrown operation never calls complete.
    final retry = PaymentAttemptCoordinator(
      uuid: const Uuid(),
    ).acquire('order|full_table');

    expect(retry, beforeFailure);
  });

  test('authoritative response releases the attempt for a new payment', () {
    final coordinator = PaymentAttemptCoordinator(uuid: const Uuid());
    final first = coordinator.acquire('order|partial|5000');

    coordinator.complete('order|partial|5000', first);
    final second = coordinator.acquire('order|partial|5000');

    expect(second, isNot(first));
  });

  test('a stale completion cannot clear a newer attempt', () {
    final coordinator = PaymentAttemptCoordinator(uuid: const Uuid());
    final current = coordinator.acquire('order|person|2');

    coordinator.complete('order|person|2', 'different-attempt');

    expect(coordinator.acquire('order|person|2'), current);
  });
}
