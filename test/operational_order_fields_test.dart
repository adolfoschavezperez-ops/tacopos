import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/orders/operational_order_fields.dart';

void main() {
  test(
    'maps missing legacy states and branch to current active/default semantics',
    () {
      expect(operationalOrderFields(const {}, defaultBranchId: 'aviacion'), {
        'operationalActive': true,
        'effectiveBranchId': 'aviacion',
      });
    },
  );

  test('keeps old open orders active across business dates', () {
    expect(
      operationalOrderFields({
        'status': 'sent',
        'paymentStatus': 'partial',
        'createdAt': DateTime(2020),
        'businessDate': '2020-01-01',
        'branchId': ' norte ',
      }, defaultBranchId: 'aviacion'),
      {'operationalActive': true, 'effectiveBranchId': 'norte'},
    );
  });

  test('preserves terminal aliases and paidAt tolerance', () {
    for (final status in ['cancelado', 'voided', 'CERRADA', 'paid']) {
      expect(
        operationalOrderFields({
          'status': status,
        }, defaultBranchId: 'aviacion')['operationalActive'],
        isFalse,
      );
    }
    expect(
      operationalOrderFields({
        'paidAt': DateTime(2026),
        'pendingTotal': 0.02,
      }, defaultBranchId: 'aviacion')['operationalActive'],
      isFalse,
    );
    expect(
      operationalOrderFields({
        'paidAt': DateTime(2026),
        'pendingTotal': 0.03,
      }, defaultBranchId: 'aviacion')['operationalActive'],
      isTrue,
    );
  });

  test('cancellation timestamps terminate regardless of missing status', () {
    expect(
      operationalOrderFields({
        'cancelledAt': DateTime(2026),
      }, defaultBranchId: 'aviacion')['operationalActive'],
      isFalse,
    );
    expect(
      operationalOrderFields({
        'closedAt': DateTime(2026),
      }, defaultBranchId: 'aviacion')['operationalActive'],
      isFalse,
    );
  });
}
