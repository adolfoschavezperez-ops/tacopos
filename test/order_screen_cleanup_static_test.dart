import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final source = File('lib/screens/waiter/order_screen.dart').readAsStringSync();

void main() {
  test('order screen no longer exposes table move or session chrome', () {
    expect(source, isNot(contains('Cambiar mesa')));
    expect(source, isNot(contains('Fecha de operaci')));
    expect(source, isNot(contains('Cerrar sesi')));
    expect(source, contains('showOperationDate: false'));
    expect(source, contains('showSessionAction: false'));
  });

  test('tables screen owns table move action next to table join', () {
    final source = File(
      'lib/screens/waiter/tables_screen.dart',
    ).readAsStringSync();

    expect(source, contains('Juntar mesas'));
    expect(source, contains('Cambiar mesa'));
    expect(source, contains('changeOrderTable'));
  });

  test('order capture does not render an order or person monetary total', () {
    expect(source, isNot(contains("'TOTAL'")));
    expect(source, isNot(contains('value: widget.order.total')));
    expect(source, isNot(contains('subtotal: subtotal')));
  });

  test(
    'Cobrar flushes and prepares the authoritative order before navigation',
    () {
      final paymentHandler = source.substring(
        source.indexOf('Future<void> _openPayment()'),
      );
      final flushIndex = paymentHandler.indexOf(
        'await _repository.flushPendingMutations(operationOrderId);',
      );
      final prepareIndex = paymentHandler.indexOf(
        'await _repository.prepareOrderForCheckout(',
      );
      final paymentIndex = paymentHandler.indexOf('PaymentScreen(');

      expect(flushIndex, greaterThanOrEqualTo(0));
      expect(prepareIndex, greaterThan(flushIndex));
      expect(paymentIndex, greaterThan(prepareIndex));
      expect(source, contains("key: ValueKey('payment-\$operationOrderId')"));
    },
  );
}
