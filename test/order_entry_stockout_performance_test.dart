import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final orderScreen = File(
    'lib/screens/waiter/order_screen.dart',
  ).readAsStringSync();
  final repository = File(
    'lib/services/taco_pos_repository.dart',
  ).readAsStringSync();

  test(
    'order screen keeps one stockout stream and passes its cached decision',
    () {
      expect(
        orderScreen,
        contains(
          'late final Stream<Map<String, ProductStockOutRow>> _stockOutsStream;',
        ),
      );
      expect(orderScreen, contains('stockOutsStream: _stockOutsStream'));
      expect(orderScreen, contains('knownStockedOut: stockedOut'));
      expect(orderScreen, contains('businessDateFuture: _businessDateFuture'));
    },
  );

  test(
    'cached available and exhausted products use memory without a tap read',
    () {
      expect(repository, contains('bool? knownStockedOut'));
      expect(
        repository,
        contains('if (knownStockedOut ?? await isProductStockedOut(product))'),
      );
      expect(repository, contains('Future<String>? businessDateFuture'));
      expect(
        repository,
        contains('businessDateFuture ?? currentKitchenBusinessDate()'),
      );
    },
  );

  test(
    'stockout updates remain listener-driven and kitchen send is unchanged',
    () {
      expect(orderScreen, contains('onLongPressCompleted'));
      expect(orderScreen, contains('onSendToKitchen: _sendToKitchen'));
      expect(repository, contains('_productStockOutsRef.snapshots()'));
      expect(repository, contains('row.isActive'));
    },
  );
}
