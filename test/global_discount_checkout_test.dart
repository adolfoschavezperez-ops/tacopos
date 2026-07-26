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

  group('checkout account presentation', () {
    test('shows gross total when there is no discount', () {
      final totals = calculateCheckoutAccountTotals(
        orderTotal: 500,
        discountAmount: 0,
        activePaymentAmounts: const [],
      );

      expect(totals.netTotal, 500);
      expect(totals.paidTotal, 0);
      expect(totals.pendingTotal, 500);
      expect(totals.hasDiscount, isFalse);
    });

    test('uses saved net total directly without discounting it twice', () {
      final totals = calculateCheckoutAccountTotals(
        orderTotal: 500,
        grossSubtotal: 500,
        discountAmount: 100,
        netTotal: 400,
        activePaymentAmounts: const [],
      );

      expect(totals.netTotal, 400);
      expect(totals.pendingTotal, 400);
      expect(totals.hasDiscount, isTrue);
    });

    test(
      'falls back to gross minus discount only without a valid net total',
      () {
        final totals = calculateCheckoutAccountTotals(
          orderTotal: 500,
          grossSubtotal: 500,
          discountAmount: 100,
          netTotal: double.nan,
          activePaymentAmounts: const [],
        );

        expect(totals.netTotal, 400);
        expect(totals.pendingTotal, 400);
      },
    );

    test('updates paid and pending from active net payment amounts', () {
      final totals = calculateCheckoutAccountTotals(
        orderTotal: 500,
        grossSubtotal: 500,
        discountAmount: 100,
        netTotal: 400,
        activePaymentAmounts: const [150],
      );

      expect(totals.netTotal, 400);
      expect(totals.paidTotal, 150);
      expect(totals.pendingTotal, 250);
    });

    test('prefers the canonical applied payment amount', () {
      final applied = checkoutAppliedPaymentAmount(
        baseAmount: 200,
        chargedAmount: 170,
        totalAfterDiscount: 160,
        discountAmount: 40,
        appliedAmount: 150,
      );
      final discountedFallback = checkoutAppliedPaymentAmount(
        baseAmount: 200,
        chargedAmount: 0,
        totalAfterDiscount: 160,
        discountAmount: 40,
      );

      expect(applied, 150);
      expect(discountedFallback, 160);
    });

    test('builds a compact indicator only for an active discount', () {
      expect(
        checkoutDiscountIndicator(
          hasDiscount: true,
          concept: 'Promocion de reapertura',
          percent: 20,
        ),
        'Promocion de reapertura · 20% aplicado',
      );
      expect(
        checkoutDiscountIndicator(
          hasDiscount: false,
          concept: 'Promocion de reapertura',
          percent: 20,
        ),
        isNull,
      );
    });

    test('labels every supported order type in the account header', () {
      expect(
        checkoutAccountTitle(orderType: 'dine_in', displayName: 'Mesa 1'),
        'Cuenta actual · Mesa 1',
      );
      expect(
        checkoutAccountTitle(
          orderType: 'dine_in',
          displayName: 'Mesa 1 + Mesa 2',
        ),
        'Cuenta actual · Mesa 1 + Mesa 2',
      );
      expect(
        checkoutAccountTitle(
          orderType: 'takeout',
          displayName: 'Para llevar',
          customerName: 'Juan',
        ),
        'Cuenta actual · Para llevar · Juan',
      );
      expect(
        checkoutAccountTitle(
          orderType: 'standing',
          displayName: 'Sin mesa · Pedro',
          customerName: 'Pedro',
        ),
        'Cuenta actual · Parados sin mesa · Pedro',
      );
    });
  });
}
