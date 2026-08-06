import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/checkout_submission_guard.dart';

void main() {
  test('checkout submission guard rejects a second active confirmation', () {
    final guard = CheckoutSubmissionGuard();

    expect(guard.acquire(), isTrue);
    expect(guard.isLocked, isTrue);
    expect(guard.acquire(), isFalse);

    guard.release();

    expect(guard.isLocked, isFalse);
    expect(guard.acquire(), isTrue);
  });
}
