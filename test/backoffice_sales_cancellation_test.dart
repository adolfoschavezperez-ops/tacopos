import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/backoffice_sales_cancellation.dart';

void main() {
  group('validación de cancelaciones de ventas', () {
    test('exige un motivo con contenido', () {
      expect(isValidCancellationReason(''), isFalse);
      expect(isValidCancellationReason('   '), isFalse);
      expect(isValidCancellationReason('Pago de prueba'), isTrue);
    });

    test('reconoce permisos específicos y fallback de administración', () {
      expect(
        hasBackofficeCancellationPermission(
          specificPermission: true,
          canViewAdmin: false,
          hasAdminAccess: false,
        ),
        isTrue,
      );
      expect(
        hasBackofficeCancellationPermission(
          specificPermission: false,
          canViewAdmin: true,
          hasAdminAccess: false,
        ),
        isTrue,
      );
      expect(
        hasBackofficeCancellationPermission(
          specificPermission: false,
          canViewAdmin: false,
          hasAdminAccess: false,
        ),
        isFalse,
      );
    });

    test('solo considera activos pagos no cancelados con importe', () {
      expect(
        isBackofficeActivePayment(
          status: 'active',
          hasCancelledAt: false,
          appliedAmount: 50,
        ),
        isTrue,
      );
      expect(
        isBackofficeActivePayment(
          status: 'cancelado',
          hasCancelledAt: false,
          appliedAmount: 50,
        ),
        isFalse,
      );
      expect(
        isBackofficeActivePayment(
          status: 'active',
          hasCancelledAt: true,
          appliedAmount: 50,
        ),
        isFalse,
      );
      expect(
        isBackofficeActivePayment(
          status: 'active',
          hasCancelledAt: false,
          appliedAmount: 0,
        ),
        isFalse,
      );
    });
  });

  group('recálculo después de cancelar pago', () {
    test('sin pagos deja el total pendiente', () {
      final totals = deriveCustomerPaymentCancellationTotals(
        orderNetTotal: 115,
        activePaymentAmounts: const [],
      );

      expect(totals.paidTotal, 0);
      expect(totals.pendingTotal, 115);
      expect(totals.paymentStatus, 'pending');
    });

    test('con pago parcial conserva saldo pendiente', () {
      final totals = deriveCustomerPaymentCancellationTotals(
        orderNetTotal: 115,
        activePaymentAmounts: const [40, 25],
      );

      expect(totals.paidTotal, 65);
      expect(totals.pendingTotal, 50);
      expect(totals.paymentStatus, 'partial');
    });

    test('tolera diferencias monetarias de dos centavos al quedar pagada', () {
      final totals = deriveCustomerPaymentCancellationTotals(
        orderNetTotal: 100,
        activePaymentAmounts: const [99.99],
      );

      expect(totals.paymentStatus, 'paid');
      expect(totals.pendingTotal, 0.01);
    });

    test('recupera un estado operativo sin modificar estados de cocina', () {
      expect(
        deriveOrderStatusAfterCustomerPaymentCancellation(
          currentOrderStatus: 'paid',
          paymentStatus: 'pending',
          hasActiveItems: true,
          activeKitchenStatuses: const ['ready'],
        ),
        'ready',
      );
      expect(
        deriveOrderStatusAfterCustomerPaymentCancellation(
          currentOrderStatus: 'closed',
          paymentStatus: 'partial',
          hasActiveItems: true,
          activeKitchenStatuses: const ['cooking'],
        ),
        'cooking',
      );
      expect(
        deriveOrderStatusAfterCustomerPaymentCancellation(
          currentOrderStatus: 'closed',
          paymentStatus: 'pending',
          hasActiveItems: false,
          activeKitchenStatuses: const [],
        ),
        'open',
      );
    });
  });

  group('cancelación de orden', () {
    test('solo libera una mesa que todavía apunta a la orden', () {
      expect(
        shouldReleaseBackofficeCancelledOrderTable(
          currentOrderId: 'order-1',
          cancelledOrderId: 'order-1',
        ),
        isTrue,
      );
      expect(
        shouldReleaseBackofficeCancelledOrderTable(
          currentOrderId: 'order-2',
          cancelledOrderId: 'order-1',
        ),
        isFalse,
      );
      expect(
        shouldReleaseBackofficeCancelledOrderTable(
          currentOrderId: null,
          cancelledOrderId: 'order-1',
        ),
        isFalse,
      );
    });

    test('reconoce estados terminales en español e inglés', () {
      expect(isTerminalCancellationStatus('cancelled'), isTrue);
      expect(isTerminalCancellationStatus('cancelado'), isTrue);
      expect(isTerminalCancellationStatus('voided'), isTrue);
      expect(isTerminalCancellationStatus('paid'), isFalse);
    });

    test('la guardia evita doble envío y puede liberarse tras error', () {
      final guard = BackofficeCancellationGuard();

      expect(guard.tryStart(), isTrue);
      expect(guard.tryStart(), isFalse);
      guard.release();
      expect(guard.tryStart(), isTrue);
    });
  });
}
