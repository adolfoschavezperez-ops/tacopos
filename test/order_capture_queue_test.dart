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

  test('flush includes 100 + 30 + 40 + last 20 before checkout', () async {
    final queue = OrderCaptureQueue();
    final releases = List.generate(3, (_) => Completer<void>());
    var persisted = 100;
    var total = 100;
    var opened = false;
    final writes = <Future<void>>[];
    for (var i = 0; i < 3; i++) {
      writes.add(
        queue.enqueue('order', () async {
          await releases[i].future;
          persisted += [30, 40, 20][i];
        }, recalculate: () async => total = persisted),
      );
    }
    final flush = queue
        .flush('order', recalculate: () async => total = persisted)
        .then((_) => opened = true);
    for (var i = 0; i < 2; i++) {
      releases[i].complete();
      await writes[i];
      expect(opened, isFalse);
      expect(total, 100);
    }
    releases.last.complete();
    await flush;
    expect(opened, isTrue);
    expect(total, 190);
    queue.dispose();
  });

  test('flush waits for a mutation added while it awaits a write', () async {
    final queue = OrderCaptureQueue();
    final first = Completer<void>();
    final last = Completer<void>();
    var opened = false;
    final one = queue.enqueue(
      'order',
      () => first.future,
      recalculate: () async {},
    );
    final flush = queue
        .flush('order', recalculate: () async {})
        .then((_) => opened = true);
    final two = queue.enqueue(
      'order',
      () => last.future,
      recalculate: () async {},
    );
    first.complete();
    await one;
    await Future<void>.delayed(Duration.zero);
    expect(opened, isFalse);
    last.complete();
    await Future.wait([two, flush]);
    expect(opened, isTrue);
    queue.dispose();
  });

  test('failed write blocks flush even when a later write succeeds', () async {
    final queue = OrderCaptureQueue();
    final failed = queue.enqueue(
      'order',
      () async => throw StateError('write failed'),
      recalculate: () async {},
    );
    final failure = expectLater(failed, throwsStateError);
    final next = queue.enqueue('order', () async {}, recalculate: () async {});
    await expectLater(
      queue.flush('order', recalculate: () async {}),
      throwsStateError,
    );
    await Future.wait([failure, next]);
    // An explicit retry can validate the persisted state after the error.
    await queue.flush('order', recalculate: () async {});
    queue.dispose();
  });

  test(
    'failed background reconciliation blocks checkout without retry loop',
    () async {
      final queue = OrderCaptureQueue();
      var attempts = 0;
      await queue.enqueue(
        'order',
        () async {},
        recalculate: () async {
          attempts++;
          throw StateError('reconciliation failed');
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 1);
      await expectLater(
        queue.flush('order', recalculate: () async {}),
        throwsStateError,
      );
      await queue.flush('order', recalculate: () async {});
      queue.dispose();
    },
  );

  test(
    'flush propagates its own reconciliation failure and allows retry',
    () async {
      final queue = OrderCaptureQueue();
      await expectLater(
        queue.flush(
          'order',
          recalculate: () async {
            throw StateError('server unavailable');
          },
        ),
        throwsStateError,
      );
      await queue.flush('order', recalculate: () async {});
      queue.dispose();
    },
  );
}
