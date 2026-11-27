import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/services/operational_diagnostics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late File file;
  final diagnostics = OperationalDiagnosticsService.instance;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tacopos_diagnostics_');
    file = File('${directory.path}${Platform.pathSeparator}events.jsonl');
    await diagnostics.configureForTesting(file);
  });

  tearDown(() async {
    await diagnostics.configureForTesting(
      File('${Directory.systemTemp.path}${Platform.pathSeparator}unused.jsonl'),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('persists bounded incident identifiers and drops secrets', () async {
    diagnostics.record(
      'capture',
      'local_persisted',
      result: 'ok',
      fields: {
        'durationMs': 12,
        'documents': 3,
        'orderId': 'order-secret-id',
        'submissionId': 'submission-123',
        'invalidOrderId': 'order/with/path',
        'pin': '1234',
        'token': 'firebase-token',
      },
      employeeId: 'employee-42',
      branchId: 'branch-aviacion',
    );

    await diagnostics.flushForTesting();
    final rows = await diagnostics.readRecent();
    expect(rows, hasLength(1));
    expect(rows.single['durationMs'], 12);
    expect(rows.single['documents'], 3);
    expect(rows.single['orderId'], 'order-secret-id');
    expect(rows.single['submissionId'], 'submission-123');
    expect(rows.single, isNot(contains('invalidOrderId')));
    expect(rows.single['employeeTag'], isNot('employee-42'));
    expect(rows.single['branchTag'], isNot('branch-aviacion'));
    expect(file.readAsStringSync(), isNot(contains('firebase-token')));
    expect(file.readAsStringSync(), isNot(contains('1234')));
  });

  test(
    'tracks listener lifecycle identifiers and counts without underflow',
    () async {
      final tablesId = diagnostics.newSubscriptionId('tables');
      final kitchenId = diagnostics.newSubscriptionId('kitchen');
      diagnostics.listenerAttached(
        'tables.orders',
        screenId: 'tables',
        subscriptionId: tablesId,
      );
      diagnostics.listenerAttached(
        'kitchen.orders',
        screenId: 'kitchen',
        subscriptionId: kitchenId,
      );
      expect(diagnostics.activeListeners, 2);

      diagnostics.listenerCancelled(
        'tables.orders',
        screenId: 'tables',
        subscriptionId: tablesId,
      );
      diagnostics.listenerCancelled(
        'kitchen.orders',
        screenId: 'kitchen',
        subscriptionId: kitchenId,
      );
      diagnostics.listenerCancelled('extra.cancel');
      expect(diagnostics.activeListeners, 0);

      await diagnostics.flushForTesting();
      final rows = await diagnostics.readRecent();
      expect(rows.map((row) => row['event']), [
        'cancel',
        'cancel',
        'cancel',
        'attach',
        'attach',
      ]);
      expect(rows[1]['listenerDetach'], 1);
      expect(rows[1]['activeListeners'], 0);
      expect(rows[1]['screenId'], 'kitchen');
      expect(rows[1]['subscriptionId'], kitchenId);
      expect(rows[3]['listenerAttach'], 1);
      expect(rows[3]['activeListeners'], 2);
      expect(rows[3]['screenId'], 'kitchen');
      expect(rows[3]['subscriptionId'], kitchenId);
      expect(rows[4]['listenerAttach'], 1);
      expect(rows[4]['activeListeners'], 1);
      expect(rows[4]['screenId'], 'tables');
      expect(rows[4]['subscriptionId'], tablesId);
    },
  );
}
