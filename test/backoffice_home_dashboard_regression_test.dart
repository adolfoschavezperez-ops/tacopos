import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/screens/admin/backoffice_screen.dart',
  ).readAsStringSync();

  test('el dashboard operativo es la unica vista inicial renderizada', () {
    expect(source, contains('class _DashboardSection'));
    expect(source, contains('CashStatusDashboardPanel('));
    expect(source, contains("title: 'Venta neta'"));
    expect(source, contains("title: 'Cobrado real'"));
    expect(source, contains('ExecutiveKpiCard('));
    expect(source, contains('SecondaryMetricCard('));
    expect(source, isNot(contains('showQuickAccesses: false')));
    expect(source, isNot(contains('showHero: false')));
  });

  test('el dashboard operativo mantiene la carga y filtros existentes', () {
    expect(source, contains('getReportDataBundle('));
    expect(source, contains('includeItems: includeItems'));
    expect(
      source,
      contains('_BackofficeSection.dashboard => _DashboardSection('),
    );
    expect(source, contains('startBusinessDate: startBusinessDate'));
    expect(source, contains('endBusinessDate: endBusinessDate'));
  });

  test('el hub conserva contexto de sucursal, fecha y permisos', () {
    expect(source, contains('CashStatusDashboardPanel('));
    expect(source, contains("title: 'Dashboard'"));
    expect(source, contains('startBusinessDate: startBusinessDate'));
    expect(source, contains('endBusinessDate: endBusinessDate'));
    expect('_BackofficeHomeSection('.allMatches(source).length, 1);
  });
}
