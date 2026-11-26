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

  test(
    'persists bounded diagnostic fields and drops identifiers/secrets',
    () async {
      diagnostics.record(
        'capture',
        'local_persisted',
        result: 'ok',
        fields: {
          'durationMs': 12,
          'documents': 3,
          'orderId': 'order-secret-id',
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
      expect(rows.single['employeeTag'], isNot('employee-42'));
      expect(rows.single['branchTag'], isNot('branch-aviacion'));
      expect(file.readAsStringSync(), isNot(contains('order-secret-id')));
      expect(file.readAsStringSync(), isNot(contains('firebase-token')));
      expect(file.readAsStringSync(), isNot(contains('1234')));
    },
  );

  test('tracks listener attach and cancel counts without underflow', () async {
    diagnostics.listenerAttached('tables.orders');
    diagnostics.listenerAttached('kitchen.orders');
    expect(diagnostics.activeListeners, 2);

    diagnostics.listenerCancelled('tables.orders');
    diagnostics.listenerCancelled('kitchen.orders');
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
  });
}
