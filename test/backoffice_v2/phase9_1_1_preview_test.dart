import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/backoffice_v2/core/env/backoffice_env.dart';
import 'package:tacopos/backoffice_v2/core/read_only_guard.dart';

void main() {
  group('Phase 9.1.1 — Preview Environment & ReadOnlyGuard', () {
    test('EnvironmentGuard allows preview with valid HTTPS PREVIEW_API_URL and blocks prod projectIds', () {
      final cfg = EnvironmentGuard.resolveAndValidate(
        rawEnv: 'preview',
        previewApiUrl: 'https://preview-api.tacopos-dev.run.app',
        defaultRestaurantId: 'los_padrinos',
      );
      expect(cfg.isPreview, isTrue);
      expect(cfg.isReadOnly, isTrue);
      expect(cfg.isDev, isFalse);
      expect(cfg.isLocal, isFalse);
      expect(cfg.badgeLabel, 'PREVIEW — Datos reales · Solo consulta');

      expect(
        () => EnvironmentGuard.resolveAndValidate(rawEnv: 'preview'),
        throwsA(isA<EnvironmentGuardException>()),
      );
      expect(
        () => EnvironmentGuard.resolveAndValidate(
          rawEnv: 'preview',
          previewApiUrl: 'https://example.github.io/api',
        ),
        throwsA(isA<EnvironmentGuardException>()),
      );
      expect(
        () => EnvironmentGuard.resolveAndValidate(
          rawEnv: 'preview',
          previewApiUrl: 'https://preview-api.tacopos-dev.run.app',
          overrideProjectId: 'tacopos-renovadev',
        ),
        throwsA(
          isA<EnvironmentGuardException>().having(
            (e) => e.code,
            'code',
            'FORBIDDEN_PROD_PROJECT',
          ),
        ),
      );
    });

    test('BackofficeReadOnlyGuard blocks all writes in Preview mode', () {
      expect(
        () => BackofficeReadOnlyGuard.assertWritable(
          isReadOnly: true,
          action: 'Cancelar orden',
        ),
        throwsA(isA<BackofficeReadOnlyException>()),
      );
      expect(
        () => BackofficeReadOnlyGuard.assertWritable(
          isReadOnly: false,
          action: 'Cancelar orden',
        ),
        returnsNormally,
      );
    });
  });
}
