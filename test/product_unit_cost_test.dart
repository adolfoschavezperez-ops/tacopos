import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/catalog/product_unit_cost.dart';
import 'package:tacopos/core/reports/canonical_sales_summary.dart';
import 'package:tacopos/models/order.dart';
import 'package:tacopos/models/order_item.dart';
import 'package:tacopos/models/product.dart';

void main() {
  group('Product unitCost serialization', () {
    test('legacy product without unitCost loads correctly', () {
      final product = Product.fromMap('legacy', _productMap());

      expect(product.unitCost, isNull);
      expect(product.price, 45);
    });

    test('unitCost int converts to double', () {
      final product = Product.fromMap('int-cost', _productMap(unitCost: 20));

      expect(product.unitCost, 20.0);
    });

    test('unitCost double loads correctly', () {
      final product = Product.fromMap(
        'double-cost',
        _productMap(unitCost: 19.8),
      );

      expect(product.unitCost, 19.8);
    });

    test('serialization preserves unitCost', () {
      final product = Product.fromMap('with-cost', _productMap(unitCost: 19.8));

      expect(product.toMap()['unitCost'], 19.8);
    });

    test('serialization omits unitCost when null', () {
      final product = Product.fromMap('without-cost', _productMap());

      expect(product.toMap().containsKey('unitCost'), isFalse);
    });

    test('unitCost does not modify sale price', () {
      final product = Product.fromMap(
        'with-cost',
        _productMap(price: 45, unitCost: 19.8),
      );

      expect(product.price, 45);
      expect(product.priceForPlatform(null), 45);
    });

    test('model remains backward-compatible for Android legacy products', () {
      final product = Product.fromMap('android-legacy', {
        'name': 'Coca',
        'category': 'Bebidas',
        'price': 30,
      });

      expect(product.unitCost, isNull);
      expect(product.active, isTrue);
      expect(product.price, 30);
    });
  });

  group('Product unitCost input', () {
    test('empty field is null', () {
      final result = parseProductUnitCostInput('');

      expect(result.isValid, isTrue);
      expect(result.value, isNull);
    });

    test('creates product with cost 19.80', () {
      final result = parseProductUnitCostInput('19.80');

      expect(result.isValid, isTrue);
      expect(result.value, 19.8);
    });

    test('edits cost 19.80 to 21.25', () {
      final initial = parseProductUnitCostInput('19.80');
      final edited = parseProductUnitCostInput('21.25');

      expect(initial.value, 19.8);
      expect(edited.value, 21.25);
    });

    test('cost 0 is valid', () {
      final result = parseProductUnitCostInput('0');

      expect(result.isValid, isTrue);
      expect(result.value, 0);
    });

    test('negative cost is rejected', () {
      final result = parseProductUnitCostInput('-1');

      expect(result.isValid, isFalse);
    });

    test('text, NaN, infinity, and more than 2 decimals are rejected', () {
      for (final value in ['abc', 'NaN', 'Infinity', '19.999']) {
        expect(
          parseProductUnitCostInput(value).isValid,
          isFalse,
          reason: value,
        );
      }
    });

    test('list labels show cost and Sin costo', () {
      expect(productUnitCostLabel(19.8), r'$19.80');
      expect(productUnitCostLabel(null), 'Sin costo');
    });
  });

  test('unitCost does not modify sale calculation', () {
    final summary = buildCanonicalSalesSummary([
      SalesOrderBundleInput(
        order: const PosOrder(
          id: 'order-1',
          tableId: 'table-1',
          tableName: 'Mesa 1',
          status: 'ready',
          kitchenStatus: 'ready',
          paymentStatus: 'pending',
          total: 90,
          paidTotal: 0,
          pendingTotal: 90,
          personNames: {},
          orderType: 'dine_in',
        ),
        items: const [
          OrderItem(
            id: 'item-1',
            personNumber: 1,
            personName: 'Cliente',
            productId: 'taco',
            productName: 'Taco arrachera',
            category: 'Tacos',
            qty: 2,
            unitPrice: 45,
            total: 90,
            notes: '',
            sendToKitchen: true,
            kitchenStatus: 'ready',
            paymentStatus: 'pending',
          ),
        ],
        payments: const [],
      ),
    ]);

    expect(summary.grossSales, 90);
    expect(summary.netSales, 90);
  });

  test('Backoffice product catalog exposes unit cost field and list chip', () {
    final source = File(
      'lib/screens/admin/product_catalog_screen.dart',
    ).readAsStringSync();

    expect(source, contains("labelText: 'Costo unitario'"));
    expect(source, contains('productUnitCostLabel(product.unitCost)'));
    expect(
      source,
      contains("'Costo \${productUnitCostLabel(product.unitCost)}'"),
    );
  });

  test('repository writes unitCost without changing Android version', () {
    final repositorySource = File(
      'lib/services/taco_pos_repository.dart',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(repositorySource, contains("'unitCost': unitCost"));
    expect(pubspec, contains('version: 1.5.4+21'));
  });
}

Map<String, dynamic> _productMap({double price = 45, Object? unitCost}) {
  final data = <String, dynamic>{
    'name': 'Taco arrachera',
    'categoryId': 'tacos',
    'categoryName': 'Tacos',
    'category': 'Tacos',
    'price': price,
    'active': true,
    'sendToKitchen': true,
    'sortOrder': 1,
    'platformPrices': const {},
    'affectsKitchenStock': false,
  };
  if (unitCost != null) {
    data['unitCost'] = unitCost;
  }
  return data;
}
