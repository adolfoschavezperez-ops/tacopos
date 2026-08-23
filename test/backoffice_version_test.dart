import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/backoffice/backoffice_version.dart';

void main() {
  test('Backoffice version source returns 1.1.14', () {
    expect(BackofficeVersion.version, '1.1.14');
    expect(BackofficeVersion.label, 'Backoffice v1.1.14');
  });

  test('Backoffice UI shows version from the shared source', () {
    final source = File(
      'lib/screens/admin/backoffice_screen.dart',
    ).readAsStringSync();

    expect(source, contains('BackofficeVersion.label'));
    expect(source, isNot(contains("'Backoffice v1.0.2'")));
  });

  test('Login web version shows Backoffice source instead of update code', () {
    final source = File('lib/screens/login_screen.dart').readAsStringSync();

    expect(source, contains('BackofficeVersion.label'));
    expect(source, contains('kIsWeb ? displayVersion'));
  });

  test('Android pubspec version increments for appbundle release', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('version: 1.5.7+24'));
  });
}
