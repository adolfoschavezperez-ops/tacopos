import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tacopos/core/backoffice/catalog_cache.dart';

void main() {
  final cache = BackofficeCatalogCache.instance;

  setUp(cache.clear);

  test('comparte un listener y reutiliza el ultimo catalogo', () async {
    final sourceController = StreamController<List<String>>.broadcast();
    var sourceCalls = 0;
    final stream = cache.watch<String>(
      catalog: 'test-catalog',
      source: () {
        sourceCalls++;
        return sourceController.stream;
      },
    );
    final first = <List<String>>[];
    final second = <List<String>>[];
    final firstSubscription = stream.listen(first.add);
    final secondSubscription = stream.listen(second.add);

    await Future<void>.delayed(Duration.zero);
    sourceController.add(['uno', 'dos']);
    await Future<void>.delayed(Duration.zero);

    expect(sourceCalls, 1);
    expect(first, [
      ['uno', 'dos'],
    ]);
    expect(second, [
      ['uno', 'dos'],
    ]);

    await firstSubscription.cancel();
    await secondSubscription.cancel();
    await sourceController.close();

    final replay = <List<String>>[];
    final replaySubscription = cache
        .watch<String>(
          catalog: 'test-catalog',
          source: () {
            sourceCalls++;
            return const Stream<List<String>>.empty();
          },
        )
        .listen(replay.add);
    await Future<void>.delayed(Duration.zero);

    expect(sourceCalls, 2);
    expect(replay, [
      ['uno', 'dos'],
    ]);
    await replaySubscription.cancel();
  });

  test('invalidar descarta el snapshot compartido', () async {
    final sourceController = StreamController<List<int>>.broadcast();
    final stream = cache.watch<int>(
      catalog: 'test-catalog',
      source: () => sourceController.stream,
    );
    final subscription = stream.listen((_) {});
    await Future<void>.delayed(Duration.zero);
    sourceController.add([1]);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    await sourceController.close();

    cache.invalidate('test-catalog');
    final next = <List<int>>[];
    final nextSubscription = cache
        .watch<int>(
          catalog: 'test-catalog',
          source: () => const Stream<List<int>>.empty(),
        )
        .listen(next.add);
    await Future<void>.delayed(Duration.zero);

    expect(next, isEmpty);
    await nextSubscription.cancel();
  });
}
