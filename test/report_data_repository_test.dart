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
      expect(results.first.bundle.key, results.last.bundle.key);
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

    test('partitions multi-day ranges and reuses cached days', () async {
      final repository = ReportDataRepository(
        currentBusinessDateProvider: () => '2026-08-13',
      );
      final requestedDays = <String>[];

      Future<ReportDataBundle> loader(ReportDataKey dayKey) async {
        requestedDays.add(dayKey.startBusinessDate);
        return _bundle(dayKey, orderDocuments: 1);
      }

      await repository.loadRange(
        key: key.copyWith(
          startBusinessDate: '2026-08-01',
          endBusinessDate: '2026-08-03',
        ),
        dayLoader: loader,
      );
      final second = await repository.loadRange(
        key: key.copyWith(
          startBusinessDate: '2026-08-02',
          endBusinessDate: '2026-08-04',
        ),
        dayLoader: loader,
      );

      expect(requestedDays, [
        '2026-08-01',
        '2026-08-02',
        '2026-08-03',
        '2026-08-04',
      ]);
      expect(second.bundle.cacheHits, 2);
      expect(second.bundle.cacheMisses, 1);
      expect(second.bundle.orderDocuments, 3);
    });

    test('deduplicates simultaneous requests for the same day', () async {
      final repository = ReportDataRepository();
      final completer = Completer<ReportDataBundle>();
      var loads = 0;
      final dayKey = key.copyWith(
        startBusinessDate: '2026-08-01',
        endBusinessDate: '2026-08-01',
      );

      Future<ReportDataBundle> loader(ReportDataKey _) {
        loads++;
        return completer.future;
      }

      final first = repository.loadRange(key: dayKey, dayLoader: loader);
      final second = repository.loadRange(key: dayKey, dayLoader: loader);
      completer.complete(_bundle(dayKey));
      final results = await Future.wait([first, second]);

      expect(loads, 1);
      expect(results.last.sharedInFlight, isTrue);
    });

    test('manual invalidation of one day does not remove other days', () async {
      final repository = ReportDataRepository();
      final requestedDays = <String>[];

      Future<ReportDataBundle> loader(ReportDataKey dayKey) async {
        requestedDays.add(dayKey.startBusinessDate);
        return _bundle(dayKey, orderDocuments: 1);
      }

      final rangeKey = key.copyWith(
        startBusinessDate: '2026-08-01',
        endBusinessDate: '2026-08-03',
      );
      await repository.loadRange(key: rangeKey, dayLoader: loader);
      repository.invalidate(startBusinessDate: '2026-08-02');
      final reloaded = await repository.loadRange(
        key: rangeKey,
        dayLoader: loader,
      );

      expect(requestedDays.where((day) => day == '2026-08-02').length, 2);
      expect(requestedDays.where((day) => day == '2026-08-01').length, 1);
      expect(requestedDays.where((day) => day == '2026-08-03').length, 1);
      expect(reloaded.bundle.cacheHits, 2);
      expect(reloaded.bundle.cacheMisses, 1);
    });

    test(
      'uses short freshness for current day and long freshness for history',
      () async {
        final repository = ReportDataRepository(
          currentTtl: const Duration(milliseconds: 1),
          historicalTtl: const Duration(hours: 1),
          currentBusinessDateProvider: () => '2026-08-13',
        );
        var currentLoads = 0;
        var historyLoads = 0;

        final currentKey = key.copyWith(
          startBusinessDate: '2026-08-13',
          endBusinessDate: '2026-08-13',
        );
        final historyKey = key.copyWith(
          startBusinessDate: '2026-08-01',
          endBusinessDate: '2026-08-01',
        );
        await repository.loadRange(
          key: currentKey,
          dayLoader: (dayKey) async {
            currentLoads++;
            return _bundle(dayKey);
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await repository.loadRange(
          key: currentKey,
          dayLoader: (dayKey) async {
            currentLoads++;
            return _bundle(dayKey);
          },
        );
        await repository.loadRange(
          key: historyKey,
          dayLoader: (dayKey) async {
            historyLoads++;
            return _bundle(dayKey);
          },
        );
        await repository.loadRange(
          key: historyKey,
          dayLoader: (dayKey) async {
            historyLoads++;
            return _bundle(dayKey);
          },
        );

        expect(currentLoads, 2);
        expect(historyLoads, 1);
      },
    );

    test(
      'keeps cache keys separated by restaurant, range and item detail',
      () async {
        final repository = ReportDataRepository();
        var loads = 0;

        Future<ReportDataBundle> loader(ReportDataKey dayKey) async {
          loads++;
          return _bundle(dayKey);
        }

        await repository.loadRange(key: key, dayLoader: loader);
        await repository.loadRange(
          key: key.copyWith(restaurantId: 'other'),
          dayLoader: loader,
        );
        await repository.loadRange(
          key: key.copyWith(endBusinessDate: '2026-07-30'),
          dayLoader: loader,
        );
        await repository.loadRange(
          key: key.copyWith(includeItems: false),
          dayLoader: loader,
        );

        expect(loads, greaterThan(31));
      },
    );

    test('cache hit does not call loader and cache miss does', () async {
      final repository = ReportDataRepository();
      var loads = 0;

      Future<ReportDataBundle> loader(ReportDataKey dayKey) async {
        loads++;
        return _bundle(dayKey);
      }

      final first = await repository.loadRange(key: key, dayLoader: loader);
      final second = await repository.loadRange(key: key, dayLoader: loader);

      expect(first.bundle.cacheMisses, greaterThan(0));
      expect(second.bundle.cacheHits, greaterThan(0));
      expect(loads, 31);
    });

    test('force refresh bypasses cache', () async {
      final repository = ReportDataRepository();
      var loads = 0;

      Future<ReportDataBundle> loader(ReportDataKey dayKey) async {
        loads++;
        return _bundle(dayKey);
      }

      await repository.loadRange(key: key, dayLoader: loader);
      await repository.loadRange(
        key: key,
        dayLoader: loader,
        forceRefresh: true,
      );

      expect(loads, 62);
    });

    test('failed refresh does not destroy previous valid cache', () async {
      final repository = ReportDataRepository();
      var fail = false;
      var loads = 0;

      Future<ReportDataBundle> loader(ReportDataKey dayKey) async {
        loads++;
        if (fail) throw StateError('firestore');
        return _bundle(dayKey);
      }

      await repository.loadRange(key: key, dayLoader: loader);
      fail = true;
      await expectLater(
        repository.loadRange(key: key, dayLoader: loader, forceRefresh: true),
        throwsStateError,
      );
      fail = false;
      final cached = await repository.loadRange(key: key, dayLoader: loader);

      expect(cached.bundle.cacheHits, 31);
      expect(loads, 62);
    });

    test('dashboard summary key does not require items by default', () {
      final summaryKey = key.copyWith(includeItems: false);
      final detailKey = key.copyWith(includeItems: true);

      expect(summaryKey.value, isNot(detailKey.value));
      expect(summaryKey.includeItems, isFalse);
      expect(detailKey.includeItems, isTrue);
    });

    test('sales by item can request item detail explicitly', () {
      final productsKey = key.copyWith(includeItems: true);

      expect(productsKey.includeItems, isTrue);
      expect(productsKey.value, contains('full'));
    });

    test('yesterday and previous week use cached historical days', () async {
      final repository = ReportDataRepository(
        currentBusinessDateProvider: () => '2026-08-13',
      );
      final days = <String>[];

      Future<ReportDataBundle> loader(ReportDataKey dayKey) async {
        days.add(dayKey.startBusinessDate);
        return _bundle(dayKey);
      }

      await repository.loadRange(
        key: key.copyWith(
          startBusinessDate: '2026-08-12',
          endBusinessDate: '2026-08-13',
        ),
        dayLoader: loader,
      );
      final yesterdayAgain = await repository.loadRange(
        key: key.copyWith(
          startBusinessDate: '2026-08-12',
          endBusinessDate: '2026-08-12',
        ),
        dayLoader: loader,
      );
      await repository.loadRange(
        key: key.copyWith(
          startBusinessDate: '2026-08-06',
          endBusinessDate: '2026-08-06',
        ),
        dayLoader: loader,
      );
      final previousWeekAgain = await repository.loadRange(
        key: key.copyWith(
          startBusinessDate: '2026-08-06',
          endBusinessDate: '2026-08-06',
        ),
        dayLoader: loader,
      );

      expect(yesterdayAgain.fromCache, isTrue);
      expect(previousWeekAgain.fromCache, isTrue);
      expect(days.where((day) => day == '2026-08-12').length, 1);
      expect(days.where((day) => day == '2026-08-06').length, 1);
    });

    test('weekly comparison reuses already loaded days', () async {
      final repository = ReportDataRepository();
      final days = <String>[];

      Future<ReportDataBundle> loader(ReportDataKey dayKey) async {
        days.add(dayKey.startBusinessDate);
        return _bundle(dayKey);
      }

      await repository.loadRange(
        key: key.copyWith(
          startBusinessDate: '2026-08-01',
          endBusinessDate: '2026-08-14',
        ),
        dayLoader: loader,
      );
      final second = await repository.loadRange(
        key: key.copyWith(
          startBusinessDate: '2026-08-08',
          endBusinessDate: '2026-08-21',
        ),
        dayLoader: loader,
      );

      expect(second.bundle.cacheHits, 7);
      expect(second.bundle.cacheMisses, 7);
      expect(days.toSet().length, 21);
    });

    test('diagnostics counts cache and in-flight reuse locally', () async {
      final repository = ReportDataRepository();
      final completer = Completer<ReportDataBundle>();
      final dayKey = key.copyWith(
        startBusinessDate: '2026-08-01',
        endBusinessDate: '2026-08-01',
      );
      var loads = 0;

      Future<ReportDataBundle> loader(ReportDataKey _) {
        loads++;
        return completer.future;
      }

      final first = repository.loadRange(key: dayKey, dayLoader: loader);
      final second = repository.loadRange(key: dayKey, dayLoader: loader);
      completer.complete(_bundle(dayKey, firestoreQueries: 3));
      await Future.wait([first, second]);
      await repository.loadRange(key: dayKey, dayLoader: loader);

      final diagnostics = repository.diagnosticsSnapshot();

      expect(loads, 1);
      expect(diagnostics.cacheHits, 1);
      expect(diagnostics.cacheMisses, 1);
      expect(diagnostics.inFlightReused, 1);
      expect(diagnostics.firestoreQueries, 3);
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

ReportDataBundle _bundle(
  ReportDataKey key, {
  int firestoreQueries = 0,
  int orderDocuments = 0,
  int paymentDocuments = 0,
  int itemDocuments = 0,
}) {
  return ReportDataBundle(
    key: key,
    orders: const [],
    payments: const [],
    paymentsByOrder: const {},
    itemsByOrder: const {},
    canonicalSummary: null,
    firestoreQueries: firestoreQueries,
    orderDocuments: orderDocuments,
    paymentDocuments: paymentDocuments,
    itemDocuments: itemDocuments,
  );
}
