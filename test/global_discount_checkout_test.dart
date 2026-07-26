import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/global_discount_checkout.dart';

void main() {
  group('global discount checkout', () {
    test('calculates the saved 20 percent snapshot before checkout', () {
      final result = calculateGlobalDiscountAmounts(
        grossSubtotal: 500,
        percent: 20,
      );

      expect(result.grossSubtotal, 500);
      expect(result.discountAmount, 100);
      expect(result.netTotal, 400);
    });

    test('keeps gross and net equal without an active discount', () {
      final result = calculateGlobalDiscountAmounts(
        grossSubtotal: 500,
        percent: 0,
      );

      expect(result.discountAmount, 0);
      expect(result.netTotal, 500);
    });

    test('uses the currently supplied percentage for an unpaid order', () {
      final original = calculateGlobalDiscountAmounts(
        grossSubtotal: 500,
        percent: 10,
      );
      final updated = calculateGlobalDiscountAmounts(
        grossSubtotal: 500,
        percent: 20,
      );

      expect(original.netTotal, 450);
      expect(updated.netTotal, 400);
    });

    test('freezes the snapshot as soon as an active payment exists', () {
      expect(
        shouldRefreshGlobalDiscountSnapshot(hasActivePayments: false),
        isTrue,
      );
      expect(
        shouldRefreshGlobalDiscountSnapshot(hasActivePayments: true),
        isFalse,
      );
    });

    test('allocates cents exactly and leaves residual to last person', () {
      final first = allocateGlobalDiscount(
        orderGrossSubtotal: 500,
        orderDiscountAmount: 100,
        selectedGrossSubtotal: 166.67,
        remainingGrossSubtotal: 500,
        previouslyAllocatedDiscount: 0,
      );
      final second = allocateGlobalDiscount(
        orderGrossSubtotal: 500,
        orderDiscountAmount: 100,
        selectedGrossSubtotal: 166.67,
        remainingGrossSubtotal: 333.33,
        previouslyAllocatedDiscount: first,
      );
      final last = allocateGlobalDiscount(
        orderGrossSubtotal: 500,
        orderDiscountAmount: 100,
        selectedGrossSubtotal: 166.66,
        remainingGrossSubtotal: 166.66,
        previouslyAllocatedDiscount: first + second,
      );

      expect(first, 33.33);
      expect(second, 33.33);
      expect(last, 33.34);
      expect(roundCheckoutMoney(first + second + last), 100);
      expect(
        roundCheckoutMoney(
          (166.67 - first) + (166.67 - second) + (166.66 - last),
        ),
        400,
      );
    });

    test('never allocates the order discount twice', () {
      final allocation = allocateGlobalDiscount(
        orderGrossSubtotal: 500,
        orderDiscountAmount: 100,
        selectedGrossSubtotal: 500,
        remainingGrossSubtotal: 500,
        previouslyAllocatedDiscount: 0,
      );
      final exhausted = allocateGlobalDiscount(
        orderGrossSubtotal: 500,
        orderDiscountAmount: 100,
        selectedGrossSubtotal: 100,
        remainingGrossSubtotal: 100,
        previouslyAllocatedDiscount: allocation,
      );

      expect(allocation, 100);
      expect(exhausted, 0);
    });
  });
}
