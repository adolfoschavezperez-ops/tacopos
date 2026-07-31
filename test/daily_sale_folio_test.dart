import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/sales/daily_sale_folio.dart';

void main() {
  group('daily sale folio', () {
    test('formats four digits without a hard upper limit', () {
      expect(formatSaleFolioDisplay(1, 4), '0001');
      expect(formatSaleFolioDisplay(42, 4), '0042');
      expect(formatSaleFolioDisplay(10000, 4), '10000');
    });

    test('uses AVI prefix for Aviacion branch', () {
      final assignment = buildSaleFolioAssignment(
        sequence: 7,
        businessDate: '2026-07-31',
        branchId: 'aviacion',
        branchName: 'Los Padrinos Tacos - Aviacion',
        restaurantId: 'tacopos-renovadev',
      );

      expect(assignment.display, '0007');
      expect(assignment.full, 'AVI-2026-07-31-0007');
    });

    test('detects missing sequences between one and last sequence', () {
      final missing = missingSaleFolioSequences(
        lastSequence: 6,
        issuedSequences: const [1, 2, 4, 6],
      );

      expect(missing, const [3, 5]);
    });

    test('respects enabled from business date', () {
      final config = SaleFolioConfig.fromMap({
        'saleFolioControlEnabled': true,
        'saleFolioControlEnabledFromBusinessDate': '2026-07-31',
        'saleFolioDigits': 4,
      });

      expect(config.appliesToBusinessDate('2026-07-30'), isFalse);
      expect(config.appliesToBusinessDate('2026-07-31'), isTrue);
      expect(config.appliesToBusinessDate('2026-08-01'), isTrue);
    });

    test('returns safe retry message for folio connectivity failures', () {
      expect(
        saleFolioFailureMessage(Exception('unavailable')),
        'No se pudo generar el folio de venta. Revisa la conexion e intentalo nuevamente. No se realizo un cobro duplicado.',
      );
    });
  });
}
