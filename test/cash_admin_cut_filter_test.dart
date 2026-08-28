import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final screenSource = File(
    'lib/screens/admin/cash_admin_screen.dart',
  ).readAsStringSync();
  final repositorySource = File(
    'lib/services/taco_pos_repository.dart',
  ).readAsStringSync();

  test('Cortes no consulta hasta presionar Buscar', () {
    expect(screenSource, contains('String? _searchedBusinessDate;'));
    expect(screenSource, contains("if (businessDate == null)"));
    expect(
      screenSource,
      contains("_searchedBusinessDate = _selectedBusinessDate"),
    );
    expect(
      screenSource,
      contains('Selecciona una fecha de corte para consultar.'),
    );
  });

  test('cambiar o limpiar fecha elimina el resultado anterior', () {
    expect(screenSource, contains('_searchedBusinessDate = null;'));
    expect(screenSource, contains('void _clearSearch()'));
    expect(screenSource, contains('No se encontró corte para esta fecha.'));
  });

  test('la consulta de Cortes usa igualdad exacta por businessDate', () {
    expect(
      repositorySource,
      contains("query = query.where('businessDate', isEqualTo: businessDate);"),
    );
    expect(
      screenSource,
      contains(
        'stream: repository.watchCashSessions(businessDate: businessDate)',
      ),
    );
  });

  test('Cortes navega unicamente un dia operativo por vez', () {
    expect(screenSource, contains('void _shiftSearchedDate(int days)'));
    expect(screenSource, contains("parseStrict(searched)"));
    expect(screenSource, contains('Duration(days: days)'));
    expect(screenSource, contains('Día anterior'));
    expect(screenSource, contains('Día siguiente'));
    expect(screenSource, contains('canNavigate'));
  });

  test(
    'listados largos de compras guardan su posicion durante la navegacion',
    () {
      final purchaseSource = File(
        'lib/screens/admin/purchase_admin_screen.dart',
      ).readAsStringSync();

      expect(
        purchaseSource,
        contains("PageStorageKey<String>('backoffice-suppliers-list')"),
      );
      expect(
        purchaseSource,
        contains("PageStorageKey<String>('backoffice-payables-list')"),
      );
      expect(
        purchaseSource,
        contains("PageStorageKey<String>('backoffice-supplier-payments-list')"),
      );
      expect(
        purchaseSource,
        contains(
          "PageStorageKey<String>('backoffice-supplier-statement-list')",
        ),
      );
    },
  );
}
