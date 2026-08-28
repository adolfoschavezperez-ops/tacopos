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
}
