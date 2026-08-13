import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('order screen no longer exposes table move or session chrome', () {
    final source = File(
      'lib/screens/waiter/order_screen.dart',
    ).readAsStringSync();

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
}
