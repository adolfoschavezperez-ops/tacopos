import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/reports/unit_reconciliation_audit.dart';

ResalePurchase buy(String date, int qty, {String name = 'Agua 600 ml',
  String supplier = 'Aguas Fanny', String unit = 'pza', String id = 'p',
  String stock = ''}) => ResalePurchase(id: '$id-$date', date: date,
  supplier: supplier, name: name, quantity: qty.toDouble(), unit: unit,
  lineCost: qty * 10.0, stockItemId: stock);

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
  test('similar water from a different supplier is excluded', () {
    final a = audit([buy('2026-09-01', 30, supplier: 'Otra agua')], []);
    expect(a.products, isEmpty);
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
  test('July-August versus September shows deltas with carryover', () {
    final p = audit([buy('2026-07-30', 30), buy('2026-09-01', 30)], [
      out('2026-08-01', 20), out('2026-09-03', 25)]).products.single;
    expect(p.period('2026-07-01', '2026-08-31').netUnits, 10);
    expect(p.period('2026-09-01', '2026-09-30').netUnits, 5);
    expect(p.relativeBalance, 15);
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
