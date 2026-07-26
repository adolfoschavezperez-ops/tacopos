import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/report_data_bundle.dart';

void main() {
  group('ReportDataRepository', () {
    const key = ReportDataKey(
      restaurantId: 'restaurant',
      branchId: 'branch',
      startBusinessDate: '2026-07-01',
      endBusinessDate: '2026-07-31',
      includeItems: true,
    );

    test('shares simultaneous loads with the same key', () async {
      final repository = ReportDataRepository();
      final completer = Completer<ReportDataBundle>();
      var loads = 0;

      Future<ReportDataBundle> loader() {
        loads++;
        return completer.future;
      }

      final first = repository.load(key: key, loader: loader);
      final second = repository.load(key: key, loader: loader);
      expect(loads, 1);

      completer.complete(_bundle(key));
      final results = await Future.wait([first, second]);

      expect(results.first.sharedInFlight, isFalse);
      expect(results.last.sharedInFlight, isTrue);
      expect(results.first.bundle, same(results.last.bundle));
    });

    test('returns a fresh cached bundle and supports invalidation', () async {
      final repository = ReportDataRepository();
      var loads = 0;

      Future<ReportDataBundle> loader() async {
        loads++;
        return _bundle(key);
      }

      final first = await repository.load(key: key, loader: loader);
      final cached = await repository.load(key: key, loader: loader);
      repository.invalidate(branchId: key.branchId);
      final reloaded = await repository.load(key: key, loader: loader);

      expect(first.fromCache, isFalse);
      expect(cached.fromCache, isTrue);
      expect(reloaded.fromCache, isFalse);
      expect(loads, 2);
    });

    test('does not cache loader errors', () async {
      final repository = ReportDataRepository();
      var loads = 0;

      Future<ReportDataBundle> loader() async {
        loads++;
        if (loads == 1) throw StateError('fallo temporal');
        return _bundle(key);
      }

      await expectLater(
        repository.load(key: key, loader: loader),
        throwsStateError,
      );
      final recovered = await repository.load(key: key, loader: loader);

      expect(recovered.fromCache, isFalse);
      expect(loads, 2);
    });
  });

  test('runInBatches preserves order and limits concurrency', () async {
    var active = 0;
    var maxActive = 0;
    final results = await runInBatches<int, int>(
      List.generate(47, (index) => index),
      batchSize: 15,
      action: (value) async {
        active++;
        if (active > maxActive) maxActive = active;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        active--;
        return value * 2;
      },
    );

    expect(maxActive, 15);
    expect(results, List.generate(47, (index) => index * 2));
  });
}

ReportDataBundle _bundle(ReportDataKey key) {
  return ReportDataBundle(
    key: key,
    orders: const [],
    payments: const [],
    paymentsByOrder: const {},
    itemsByOrder: const {},
    canonicalSummary: null,
    firestoreQueries: 0,
    orderDocuments: 0,
    paymentDocuments: 0,
    itemDocuments: 0,
  );
}
