import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/unit_reconciliation_audit.dart';

ResalePurchase buy(String date, int qty, {String name = 'Agua 600 ml',
  String supplier = 'Aguas Fanny', String unit = 'pza', String id = 'p',
  String stock = '', String sku = ''}) => ResalePurchase(id: '$id-$date', date: date,
  supplier: supplier, name: name, quantity: qty.toDouble(), unit: unit,
  lineCost: qty * 10.0, stockItemId: stock, purchaseItemId: sku);

ResaleExit out(String date, int qty, {String name = 'Agua 600 ml',
  String productId = 'water', ResaleExitKind kind = ResaleExitKind.paid,
  String stock = ''}) => ResaleExit(date: date, productId: productId,
  name: name, category: 'Bebidas', quantity: qty, saleAmount: qty * 25.0,
  kind: kind, stockItemId: stock);

ResaleAudit audit(List<ResalePurchase> purchases, List<ResaleExit> sales,
    {List<ResaleCheckpoint> checkpoints = const []}) => buildResaleAudit(
  purchases: purchases, exits: sales, checkpoints: checkpoints,
  endDate: '2026-10-01');

void main() {
  test('30 bought and 30 sold are balanced, but initial stock is unknown', () {
    final p = audit([buy('2026-09-01', 30)], [out('2026-09-01', 30)]).products.single;
    expect(p.relativeBalance, 0);
    expect(p.theoreticalInventory, isNull);
    expect(p.physicalDifference, isNull);
  });
  test('30 bought 20 sold carry 10 into next day, then clear', () {
    final p = audit([buy('2026-09-01', 30)], [
      out('2026-09-01', 20), out('2026-09-02', 10)]).products.single;
    expect(p.days.map((d) => d.relativeBalance), [10, 0]);
    expect(p.sold, 30);
  });
  test('restock before exhausting inventory and multiple purchases same day', () {
    final p = audit([buy('2026-09-01', 30),
      buy('2026-09-02', 10, id: 'second'),
      buy('2026-09-02', 20, id: 'third')], [
      out('2026-09-01', 18), out('2026-09-02', 7)]).products.single;
    expect(p.days.map((d) => d.relativeBalance), [12, 35]);
    expect(p.days.last.bought, 30);
  });
  test('different water presentations never merge', () {
    final a = audit([buy('2026-09-01', 30),
      buy('2026-09-01', 12, name: 'Agua 1 litro')], [
      out('2026-09-01', 20),
      out('2026-09-01', 5, name: 'Agua 1 litro', productId: 'liter')]);
    expect(a.products, hasLength(2));
    expect(a.products.map((p) => p.relativeBalance).toSet(), {10, 7});
  });
  test('a shared stock link does not merge bottle sizes', () {
    final a = audit([buy('2026-09-01', 30, stock: 'generic-water'),
      buy('2026-09-01', 12, name: 'Agua 1 litro', stock: 'generic-water')], [
      out('2026-09-01', 20, stock: 'generic-water')]);
    expect(a.products, hasLength(2));
    expect(a.products.firstWhere((p) => p.name == 'agua 1 litro').sold, 0);
  });
  test('a shared stock link without a matching presentation stays unresolved', () {
    final a = audit([buy('2026-09-01', 30, stock: 'generic-water')], [
      out('2026-09-01', 5, name: 'Agua 1 litro', stock: 'generic-water')]);
    expect(a.products.single.sold, 0);
    expect(a.unmatchedSales, hasLength(1));
  });
  test('same display name across purchase SKUs needs a unique link', () {
    final a = audit([buy('2026-09-01', 30, sku: 'bottle-a', stock: 'a'),
      buy('2026-09-01', 30, sku: 'bottle-b', stock: 'b', id: 'b')], [
      out('2026-09-01', 10),
      out('2026-09-01', 7, productId: 'linked', stock: 'b')]);
    expect(a.products, hasLength(2));
    expect(a.unmatchedSales, hasLength(1));
    expect(a.products.firstWhere((p) => p.key == 'water:sku:bottle-b').sold, 7);
    expect(a.products.firstWhere((p) => p.key == 'water:sku:bottle-a').sold, 0);
  });
  test('reused purchase SKU across presentations leaves purchases unresolved', () {
    final a = audit([buy('2026-09-01', 30, sku: 'reused'),
      buy('2026-09-01', 12, name: 'Agua 1 litro', sku: 'reused', id: 'b')], [
      out('2026-09-01', 5)]);
    expect(a.products, isEmpty);
    expect(a.unmatchedPurchases, hasLength(2));
    expect(a.unmatchedSales, hasLength(1));
  });
  test('safe resale name aliases match real POS names', () {
    final a = audit([
      buy('2026-09-01', 20, name: 'Agua de Jamaica', sku: 'jamaica'),
      buy('2026-09-01', 18, name: 'Agua de Horchata', sku: 'horchata',
        id: 'horchata'),
      buy('2026-09-01', 10, name: 'Empanadas', supplier: 'Empanaditas',
        sku: 'empanadas', id: 'empanadas'),
    ], [
      out('2026-09-01', 7, name: 'Agua Jamaica', productId: 'jamaica-sale'),
      out('2026-09-01', 6, name: 'Agua Horchata', productId: 'horchata-sale'),
      out('2026-09-01', 4, name: 'Empanada', productId: 'empanada-sale'),
    ]);
    expect(a.unmatchedSales, isEmpty);
    expect(a.products.firstWhere((p) => p.name == 'agua de jamaica').sold, 7);
    expect(a.products.firstWhere((p) => p.name == 'agua de horchata').sold, 6);
    expect(a.products.firstWhere((p) => p.name == 'empanadas').sold, 4);
  });

  test('irrelevant meats and soft drinks are not resale unmatched noise', () {
    final a = audit([
      buy('2026-09-01', 20, name: 'Agua de Jamaica', sku: 'jamaica'),
    ], [
      out('2026-09-01', 2, name: 'Bistec', productId: 'bistec',
        stock: 'meat-stock'),
      out('2026-09-01', 2, name: 'Coca Regular', productId: 'coca',
        stock: 'drink-stock'),
      out('2026-09-01', 2, name: 'Refresco Sabor', productId: 'refresco',
        stock: 'drink-stock-2'),
      out('2026-09-01', 2, name: 'Agua Piña', productId: 'pina'),
    ]);
    expect(a.unmatchedSales, hasLength(1));
    expect(a.unmatchedSales.single, contains('Agua Piña'));
  });

  test('similar water from a different supplier is excluded', () {
    final a = audit([buy('2026-09-01', 30, supplier: 'Otra agua')], []);
    expect(a.products, isEmpty);
  });
  test('supplier identifies flavor purchases without literal family words', () {
    final a = audit([
      buy('2026-09-01', 30, name: 'Jamaica', sku: 'jamaica'),
      buy('2026-09-01', 20, name: 'Horchata', sku: 'horchata'),
      buy('2026-09-01', 15, name: 'Piña', supplier: 'Empanaditas', sku: 'pina'),
      buy('2026-09-01', 15, name: 'Cajeta', supplier: 'Empanaditas', sku: 'cajeta'),
      buy('2026-09-01', 10, name: 'Refresco cola', id: 'soft-drink'),
    ], [
      out('2026-09-01', 8, name: 'Jamaica', productId: 'jamaica'),
      out('2026-09-01', 6, name: 'Horchata', productId: 'horchata'),
      out('2026-09-01', 5, name: 'Piña', productId: 'pina'),
      out('2026-09-01', 4, name: 'Cajeta', productId: 'cajeta'),
    ]);
    expect(a.products, hasLength(4));
    expect(a.products.firstWhere((p) => p.key == 'water:sku:jamaica').sold, 8);
    expect(a.products.firstWhere((p) => p.key == 'empanada:sku:cajeta').sold, 4);
    expect(a.unmatchedPurchases, hasLength(1));
  });
  test('flavor sold under two supplier families stays unmatched', () {
    final a = audit([
      buy('2026-09-01', 20, name: 'Piña', sku: 'water-pina'),
      buy('2026-09-01', 20, name: 'Piña', supplier: 'Empanaditas',
        sku: 'pie-pina', id: 'pie'),
    ], [out('2026-09-01', 3, name: 'Piña', productId: 'pina')]);
    expect(a.products, hasLength(2));
    expect(a.products.every((p) => p.sold == 0), isTrue);
    expect(a.unmatchedSales.single, contains('match ambiguo'));
  });
  test('supplier spelling, accents and whitespace normalize', () {
    expect(resaleSupplierFamily(' AGUAS   FÁNNY '), ResaleFamily.water);
    expect(resaleSupplierFamily('EMPANADITAS'), ResaleFamily.empanada);
  });
  test('30 finished empanadas bought and 30 sold', () {
    final p = audit([buy('2026-09-01', 30,
      name: 'Empanadas', supplier: 'Empanaditas')], [
      out('2026-09-01', 30, name: 'Empanadas', productId: 'pie')]).products.single;
    expect(p.relativeBalance, 0);
  });
  test('generic empanada purchase aggregates flavors only when sole purchase type', () {
    final p = audit([buy('2026-09-01', 30,
      name: 'Empanadas', supplier: 'Empanaditas')], [
      out('2026-09-01', 12, name: 'Empanada de cajeta', productId: 'cajeta'),
      out('2026-09-01', 18, name: 'Empanada de piña', productId: 'pina')]).products.single;
    expect(p.sold, 30);
    expect(p.productIds, ['cajeta', 'pina']);
  });
  test('flavored purchases remain separate and generic sales unresolved', () {
    final a = audit([buy('2026-09-01', 10,
      name: 'Empanada cajeta', supplier: 'Empanaditas'),
      buy('2026-09-01', 20,
      name: 'Empanada piña', supplier: 'Empanaditas')], [
      out('2026-09-01', 5, name: 'Empanadas', productId: 'generic')]);
    expect(a.products, hasLength(2));
    expect(a.unmatchedSales, hasLength(1));
  });
  test('cancellation before delivery is not an exit', () {
    final p = audit([buy('2026-09-01', 30)], [out('2026-09-01', 1,
      kind: ResaleExitKind.cancellationWithoutDeliveryProof)]).products.single;
    expect(p.relativeBalance, 30);
    expect(p.unprovenCancellations, 1);
  });
  test('explicitly recorded legitimate exit is separate from sale', () {
    final p = audit([buy('2026-09-01', 30)], [
      out('2026-09-01', 20), out('2026-09-01', 2,
        kind: ResaleExitKind.recordedOther)]).products.single;
    expect(p.other, 2);
    expect(p.relativeBalance, 8);
  });
  test('known opening count anchors absolute balance', () {
    final p = audit([buy('2026-09-02', 30)], [out('2026-09-02', 20)],
      checkpoints: const [ResaleCheckpoint(date: '2026-09-01',
        key: 'water:name:agua 600 ml', physicalCount: 12)]).products.single;
    expect(p.initialUnknown, isFalse);
    expect(p.theoreticalInventory, 22);
    expect(p.physicalDifference, isNull);
  });
  test('zero relative balance does not close a cycle without physical anchor', () {
    final p = audit([buy('2026-09-01', 30), buy('2026-09-03', 30)], [
      out('2026-09-02', 30)]).products.single;
    expect(p.anchoredCycleStarts, isEmpty);
    final anchored = audit([buy('2026-09-01', 30), buy('2026-09-03', 30)], [
      out('2026-09-02', 30)], checkpoints: const [
        ResaleCheckpoint(date: '2026-08-31',
          key: 'water:name:agua 600 ml', physicalCount: 0)]).products.single;
    expect(anchored.anchoredCycleStarts, ['2026-09-01', '2026-09-03']);
  });
  test('two physical counts establish a confirmable difference', () {
    final p = audit([buy('2026-09-02', 30)], [out('2026-09-02', 20)],
      checkpoints: const [
        ResaleCheckpoint(date: '2026-09-01',
          key: 'water:name:agua 600 ml', physicalCount: 0),
        ResaleCheckpoint(date: '2026-09-03',
          key: 'water:name:agua 600 ml', physicalCount: 8),
      ]).products.single;
    expect(p.physicalDifference, -2);
    expect(p.theoreticalInventory, 8);
  });
  test('a checkpoint without a closing boundary does not anchor inventory', () {
    final p = audit([buy('2026-09-02', 30)], [], checkpoints: const [
      ResaleCheckpoint(date: '2026-09-01', key: 'water:name:agua 600 ml',
        physicalCount: 5, boundary: 'opening'),
    ]).products.single;
    expect(p.initialUnknown, isTrue);
    expect(p.theoreticalInventory, isNull);
  });
  test('historical declaration is not a confirmed physical anchor', () {
    final p = audit([buy('2026-09-02', 30)], [out('2026-09-02', 20)],
      checkpoints: [
        ResaleCheckpoint(date: '2026-09-01', key: 'water:name:agua 600 ml',
          physicalCount: 0, confirmed: false),
        ResaleCheckpoint(date: '2026-09-03', key: 'water:name:agua 600 ml',
          physicalCount: 8, confirmed: false),
      ]).products.single;
    expect(resaleClosingCountIsRecent(DateTime.utc(2026, 9, 1),
      DateTime.utc(2026, 10, 1)), isFalse);
    expect(p.initialUnknown, isTrue);
    expect(p.theoreticalInventory, isNull);
    expect(p.physicalDifference, isNull);
  });
  test('append-only correction chain supersedes without rewriting original', () {
    final recorded = DateTime.utc(2026, 9, 1, 23);
    final original = ResaleCheckpoint(date: '2026-09-01',
      key: 'water:name:agua 600 ml', physicalCount: 12, recordedAt: recorded);
    final effective = resaleEffectiveCheckpoint(original, [
      ResaleCheckpointCorrection(revision: 1, physicalCount: 10,
        reason: 'Captura duplicada de dos botellas',
        recordedAt: recorded.add(const Duration(hours: 1))),
      ResaleCheckpointCorrection(revision: 2, physicalCount: 9,
        reason: 'Revisado contra hoja firmada',
        recordedAt: recorded.add(const Duration(hours: 2))),
    ]);
    expect(original.physicalCount, 12);
    expect(effective.physicalCount, 9);
    expect(effective.correctionRevision, 2);
    expect(effective.confirmed, isTrue);
    expect(effective.originalPhysicalCount, 12);
    expect(effective.corrections.map((c) => c.physicalCount), [10, 9]);
    final pWithCorrection = audit([buy('2026-09-02', 30)],
      [out('2026-09-02', 20)], checkpoints: [
        effective,
        const ResaleCheckpoint(date: '2026-09-03',
          key: 'water:name:agua 600 ml', physicalCount: 17),
      ]).products.single;
    expect(pWithCorrection.checkpoints, hasLength(2));
    expect(pWithCorrection.physicalDifference, -2);
    final late = resaleEffectiveCheckpoint(original, [
      ResaleCheckpointCorrection(revision: 1, physicalCount: 8,
        reason: 'Revisión tardía del registro físico',
        recordedAt: recorded.add(const Duration(days: 30))),
    ]);
    expect(late.physicalCount, 8);
    expect(late.confirmed, isFalse);
    final p = audit([buy('2026-09-02', 30)], [], checkpoints: [late]).products.single;
    expect(p.theoreticalInventory, isNull);
  });
  test('negative theoretical relative balance means data integrity review', () {
    final p = audit([buy('2026-09-02', 3)], [
      out('2026-09-01', 7)]).products.single;
    expect(p.hasNegativeRelativeBalance, isTrue);
    expect(p.relativeBalance, -4);
    expect(p.physicalDifference, isNull);
  });
  test('closed Sunday adds no artificial movement', () {
    final p = audit([buy('2026-09-05', 30)], [
      out('2026-09-07', 20)]).products.single;
    expect(p.days.map((d) => d.date), ['2026-09-05', '2026-09-07']);
    expect(p.relativeBalance, 10);
  });
  test('July 15-August versus September shows deltas with carryover', () {
    final p = audit([buy('2026-07-10', 40), buy('2026-07-30', 30),
      buy('2026-09-01', 30)], [
      out('2026-08-01', 20), out('2026-09-03', 25)]).products.single;
    expect(p.period('2026-07-15', '2026-08-31').netUnits, 10);
    expect(p.period('2026-09-01', '2026-09-30').netUnits, 5);
    expect(p.relativeBalance, 55);
  });
  test('100% employee meal and courtesy are registered other exits', () {
    expect(resaleFinalizedExitKind(discountType: 'employee_free_meal',
      method: 'employee_consumption', discountPercent: 100,
      discountAmount: 25, subtotal: 25, chargedAmount: 0),
      ResaleExitKind.recordedOther);
    expect(resaleFinalizedExitKind(discountType: 'courtesy', method: 'cash',
      discountPercent: 100, discountAmount: 25, subtotal: 25,
      chargedAmount: 0), ResaleExitKind.recordedOther);
    expect(resaleFinalizedExitKind(discountType: '',
      method: 'employee_consumption', discountPercent: 0,
      discountAmount: 0, subtotal: 25, chargedAmount: 25,
      baseAmount: 25),
      ResaleExitKind.recordedOther);
    expect(resaleFinalizedExitKind(discountType: '',
      method: 'employee_consumption', discountPercent: 0,
      legacyDiscountPercent: 30, discountAmount: 0,
      subtotal: 25, chargedAmount: 17.5, baseAmount: 25),
      ResaleExitKind.paid);
    expect(resaleFinalizedExitKind(discountType: 'employee_30',
      method: 'employee_consumption', discountPercent: 30,
      discountAmount: 7.5, subtotal: 25, chargedAmount: 17.5),
      ResaleExitKind.paid);
  });
  test('Firestore piece unit is treated as one resale unit', () {
    final a = audit([
      buy('2026-09-01', 8, name: 'Agua de Jamaica', unit: 'piece'),
      buy('2026-09-01', 10, name: 'Empanadas', supplier: 'Empanaditas',
        unit: 'piece', id: 'emp'),
    ], [
      out('2026-09-01', 5, name: 'Agua de Jamaica', productId: 'jamaica'),
      out('2026-09-01', 6, name: 'Empanadas', productId: 'empanadas'),
    ]);
    expect(a.unmatchedPurchases, isEmpty);
    expect(a.products, hasLength(2));
    expect(a.products.firstWhere((p) => p.name == 'agua de jamaica').bought, 8);
    expect(a.products.firstWhere((p) => p.name == 'empanadas').bought, 10);
  });

  test('pack x30 converts once; unsupported units stay unmatched', () {
    final a = audit([buy('2026-09-01', 1,
      name: 'Agua 600 ml x 30', unit: 'caja'),
      buy('2026-09-02', 1, name: 'Agua 600 ml', unit: 'kg')], [
      out('2026-09-01', 30)]);
    expect(a.products.single.bought, 30);
    expect(a.unmatchedPurchases, hasLength(1));
  });
  test('x30 with quantity one and piece unit remains ambiguous', () {
    final a = audit([buy('2026-09-01', 1,
      name: 'Agua 600 ml x 30', unit: 'pza')], []);
    expect(a.products, isEmpty);
    expect(a.unmatchedPurchases, hasLength(1));
  });
}
