import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/order_capture_queue.dart';
import 'package:tacopos/models/order_item.dart';

void main() {
  OrderItem item(int qty) => OrderItem(
    id: 'item',
    personNumber: 1,
    personName: 'Persona 1',
    productId: 'product',
    productName: 'Producto',
    category: 'tacos',
    qty: qty,
    unitPrice: 10,
    total: qty * 10,
    notes: '',
    sendToKitchen: true,
    kitchenStatus: 'pending',
    paymentStatus: 'pending',
  );

  test('keeps optimistic quantity while an old snapshot arrives', () {
    final state = OrderCaptureState();
    state.reconcile([item(1)]);
    state.apply(item(4));
    state.reconcile([item(2)]);
    expect(state.effectiveItems.single.qty, 4);
    state.reconcile([item(4)]);
    expect(state.effectiveItems.single.qty, 4);
  });

  test('serializes mutations for an order', () async {
    final queue = OrderCaptureQueue();
    final events = <String>[];
    final first = Completer<void>();

    final one = queue.enqueue('order', () async {
      events.add('one-start');
      await first.future;
      events.add('one-end');
    }, recalculate: () async => events.add('recalculate'));
    final two = queue.enqueue(
      'order',
      () async => events.add('two'),
      recalculate: () async => events.add('recalculate'),
    );

    await Future<void>.delayed(Duration.zero);
    expect(events, ['one-start']);
    first.complete();
    await Future.wait([one, two]);
    await queue.flush('order', recalculate: () async {});
    expect(events.indexOf('one-end'), lessThan(events.indexOf('two')));
    queue.dispose();
  });

  test('debounces a burst to one recalculation', () async {
    final queue = OrderCaptureQueue();
    var recalculations = 0;
    final mutations = <Future<void>>[];
    for (var index = 0; index < 5; index++) {
      mutations.add(
        queue.enqueue(
          'order',
          () async {},
          recalculate: () async => recalculations++,
        ),
      );
    }
    await Future.wait(mutations);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(recalculations, 1);
    queue.dispose();
  });

  test('waits for the queue to drain before recalculating', () async {
    final queue = OrderCaptureQueue();
    final release = Completer<void>();
    var recalculations = 0;
    final mutation = queue.enqueue(
      'order',
      () => release.future,
      recalculate: () async => recalculations++,
    );
    await Future<void>.delayed(Duration.zero);
    expect(recalculations, 0);
    release.complete();
    await mutation;
    await Future<void>.delayed(Duration.zero);
    expect(recalculations, 1);
    queue.dispose();
  });

  test(
    'allows one final recalculation after a mutation during recalculate',
    () async {
      final queue = OrderCaptureQueue();
      var recalculations = 0;
      final mutations = <Future<void>>[];
      mutations.add(
        queue.enqueue(
          'order',
          () async {},
          recalculate: () async {
            recalculations++;
            if (recalculations == 1) {
              mutations.add(
                queue.enqueue(
                  'order',
                  () async {},
                  recalculate: () async => recalculations++,
                ),
              );
            }
          },
        ),
      );
      await Future.wait(mutations);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(recalculations, 2);
      queue.dispose();
    },
  );

  test('drains a second burst after a slow recalculation completes', () async {
    final queue = OrderCaptureQueue();
    final recalculateStarted = Completer<void>();
    final releaseRecalculate = Completer<void>();
    var recalculations = 0;

    final first = queue.enqueue(
      'order',
      () async {},
      recalculate: () async {
        recalculations++;
        if (recalculations == 1) {
          recalculateStarted.complete();
          await releaseRecalculate.future;
        }
      },
    );
    await first;
    await recalculateStarted.future;

    final second = queue.enqueue(
      'order',
      () async {},
      recalculate: () async => recalculations++,
    );
    await second;
    expect(recalculations, 1);

    releaseRecalculate.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(recalculations, 2);
    queue.dispose();
  });
}
