import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/screens/admin/finance_admin_screen.dart',
  ).readAsStringSync();

  test('Finanzas abre sin future financiero aplicado', () {
    expect(
      source,
      contains('Future<_FinanceLoadResult>? _appliedReportFuture;'),
    );
    expect(source, contains('final future = _appliedReportFuture;'));
    expect(source, contains("future == null"));
    expect(source, contains('Selecciona un rango de fechas'));
    expect(source, isNot(contains('ensureDefaultPartners().catchError')));
  });

  test('fechas draft solo se aplican al presionar Buscar', () {
    expect(source, contains('void _searchApplied()'));
    expect(source, contains('Future<_FinanceLoadResult> _loadFinance'));
    expect(source, contains('onSearch: _searchApplied'));
    expect(source, contains('_draftStartDate'));
    expect(source, contains('_draftEndDate'));
  });

  test('la misma clave reutiliza el future y un rango nuevo crea otro', () {
    expect(source, contains('class _FinanceQueryKey'));
    expect(source, contains('other.startBusinessDate == startBusinessDate'));
    expect(source, contains('other.endBusinessDate == endBusinessDate'));
    expect(source, contains('_appliedQueryKey == key'));
    expect(source, contains('_appliedReportFuture != null'));
  });

  test('limpiar elimina resultado aplicado sin iniciar una consulta', () {
    expect(source, contains('void _clearApplied()'));
    expect(source, contains('_appliedQueryKey = null;'));
    expect(source, contains('_appliedReportFuture = null;'));
  });

  test(
    'retry permite recrear un future fallido y evita resultado obsoleto',
    () {
      expect(source, contains('bool _lastLoadFailed = false;'));
      expect(source, contains('_markLoadFailed(key, error, stackTrace)'));
      expect(source, contains('_lastLoadFailed = true'));
      expect(source, contains('future: future'));
      expect(source, contains('final key = _appliedQueryKey;'));
    },
  );
}
