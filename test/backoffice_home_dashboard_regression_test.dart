import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/screens/admin/backoffice_screen.dart',
  ).readAsStringSync();

  test('el dashboard conserva el resumen operativo junto al nuevo home', () {
    expect(source, contains('class _BackofficeHomeSection'));
    expect(source, contains('class _DashboardSection'));
    expect(source, contains('CashStatusDashboardPanel('));
    expect(source, contains("title: 'Venta neta'"));
    expect(source, contains("title: 'Cobrado real'"));
    expect(source, contains('ExecutiveKpiCard('));
    expect(source, contains('SecondaryMetricCard('));
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
    expect(source, contains('AppSession.instance.currentBranchName'));
    expect(source, contains("DateFormat('dd/MM/yyyy')"));
    expect(source, contains('final items = _navItems('));
    expect(
      source,
      contains('where((item) => item.section != _BackofficeSection.dashboard)'),
    );
  });
}
