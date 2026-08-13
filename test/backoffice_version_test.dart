import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/backoffice/backoffice_version.dart';

void main() {
  test('Backoffice version source returns 1.0.0', () {
    expect(BackofficeVersion.version, '1.0.0');
    expect(BackofficeVersion.label, 'Backoffice v1.0.0');
  });

  test('Backoffice UI shows version from the shared source', () {
    final source = File(
      'lib/screens/admin/backoffice_screen.dart',
    ).readAsStringSync();

    expect(source, contains('BackofficeVersion.label'));
    expect(source, isNot(contains("'Backoffice v1.0.0'")));
  });

  test('Android pubspec version remains intact', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('version: 1.4.2+14'));
  });
}
