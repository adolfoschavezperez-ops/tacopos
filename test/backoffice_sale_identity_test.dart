import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/sales/backoffice_sale_identity.dart';
import 'package:tacopos/core/sales/daily_sale_folio.dart';
import 'package:tacopos/models/order.dart';

void main() {
  group('backoffice sale identity', () {
    test('separates visible order id and daily folio', () {
      final order = _order(
        id: '6Da0ZHproductionDocument',
        saleFolioDisplay: '0001',
        saleFolioSequence: 1,
        saleFolioFull: 'AVI-20260731-0001',
      );

      final identity = backofficeSaleIdentity(order);

      expect(identity.visibleOrderId, '6Da0ZH');
      expect(identity.dailyFolio, '0001');
      expect(identity.fullFolio, 'AVI-20260731-0001');
      expect(identity.dailyFolio, isNot(identity.visibleOrderId));
    });

    test('formats saleFolioSequence when display is missing', () {
      final identity = backofficeSaleIdentity(
        _order(id: 'A12345productionDocument', saleFolioSequence: 7),
      );

      expect(identity.visibleOrderId, 'A12345');
      expect(identity.dailyFolio, '0007');
    });

    test(
      'historical sale shows id and Sin folio without missing incidence',
      () {
        final identity = backofficeSaleIdentity(_order(id: 'uEDTp2'));

        expect(identity.visibleOrderId, 'uEDTp2');
        expect(identity.dailyFolio, backofficeHistoricalNoFolioText);
        expect(identity.dailyFolio, isNot(saleFolioMissingIncidence));
      },
    );

    test(
      'search matches visible id, document id, display, sequence and full',
      () {
        final order = _order(
          id: '6Da0ZHproductionDocument',
          saleFolioDisplay: '0001',
          saleFolioSequence: 1,
          saleFolioFull: 'AVI-20260731-0001',
        );

        expect(backofficeSaleMatchesQuery(order, '6Da0ZH'), isTrue);
        expect(backofficeSaleMatchesQuery(order, 'productionDocument'), isTrue);
        expect(backofficeSaleMatchesQuery(order, '0001'), isTrue);
        expect(backofficeSaleMatchesQuery(order, '1'), isTrue);
        expect(backofficeSaleMatchesQuery(order, 'AVI-20260731-0001'), isTrue);
      },
    );

    test('search matches table and customer', () {
      final order = _order(
        id: 'ABC123',
        tableName: 'Mesa 3',
        customerName: 'Adolfo Chavez',
      );

      expect(backofficeSaleMatchesQuery(order, 'mesa 3'), isTrue);
      expect(backofficeSaleMatchesQuery(order, 'adolfo'), isTrue);
      expect(backofficeSaleMatchesQuery(order, '0001'), isFalse);
    });
  });
}

PosOrder _order({
  required String id,
  String tableName = 'Mesa 1',
  String? customerName,
  int? saleFolioSequence,
  String? saleFolioDisplay,
  String? saleFolioFull,
}) {
  return PosOrder(
    id: id,
    tableId: 'table-1',
    tableName: tableName,
    status: 'paid',
    kitchenStatus: 'served',
    paymentStatus: 'paid',
    total: 120,
    paidTotal: 120,
    pendingTotal: 0,
    personNames: const {},
    orderType: 'dine_in',
    customerName: customerName,
    saleFolioSequence: saleFolioSequence,
    saleFolioDisplay: saleFolioDisplay,
    saleFolioFull: saleFolioFull,
  );
}
