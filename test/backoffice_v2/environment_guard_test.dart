import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/backoffice_v2/core/env/backoffice_env.dart';
import 'package:tacopos/backoffice_v2/core/env/firebase_options_dev.dart';

void main() {
  group('EnvironmentGuard isolation protections', () {
    test('blocks when ENV is missing', () {
      expect(
        () => EnvironmentGuard.resolveAndValidate(rawEnv: ''),
        throwsA(
          isA<EnvironmentGuardException>().having(
            (e) => e.code,
            'code',
            'MISSING_ENV',
          ),
        ),
      );
    });

    test('blocks when ENV is unknown', () {
      expect(
        () => EnvironmentGuard.resolveAndValidate(rawEnv: 'staging'),
        throwsA(
          isA<EnvironmentGuardException>().having(
            (e) => e.code,
            'code',
            'UNKNOWN_ENV',
          ),
        ),
      );
    });

    test('blocks PROD environment in Phase 2', () {
      expect(
        () => EnvironmentGuard.resolveAndValidate(rawEnv: 'prod'),
        throwsA(
          isA<EnvironmentGuardException>().having(
            (e) => e.code,
            'code',
            'PROD_BLOCKED',
          ),
        ),
      );
    });

    test('blocks production projectId tacopos-renovadev', () {
      expect(
        () => EnvironmentGuard.resolveAndValidate(
          rawEnv: 'dev',
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

    test('blocks DEV build containing production endpoints', () {
      const prodLikeOptions = FirebaseOptions(
        apiKey: 'fake',
        appId: 'fake',
        messagingSenderId: '123',
        projectId: 'tacopos-backoffice-dev',
        authDomain: 'tacopos-renovadev.firebaseapp.com',
        storageBucket: 'tacopos-renovadev.firebasestorage.app',
      );
      expect(
        () => EnvironmentGuard.resolveAndValidate(
          rawEnv: 'dev',
          customOptions: prodLikeOptions,
        ),
        throwsA(
          isA<EnvironmentGuardException>().having(
            (e) => e.code,
            'code',
            'FORBIDDEN_ENDPOINT',
          ),
        ),
      );
    });

    test('blocks LOCAL build with unauthorized emulator host', () {
      expect(
        () => EnvironmentGuard.resolveAndValidate(
          rawEnv: 'local',
          emulatorHost: '192.168.1.50',
        ),
        throwsA(
          isA<EnvironmentGuardException>().having(
            (e) => e.code,
            'code',
            'UNAUTHORIZED_EMULATOR_HOST',
          ),
        ),
      );
    });

    test('blocks LOCAL build without demo- prefix', () {
      expect(
        () => EnvironmentGuard.resolveAndValidate(
          rawEnv: 'local',
          overrideProjectId: 'tacopos-backoffice-dev',
        ),
        throwsA(
          isA<EnvironmentGuardException>().having(
            (e) => e.code,
            'code',
            'INVALID_LOCAL_PROJECT',
          ),
        ),
      );
    });

    test('accepts valid LOCAL emulator config with isolated ports', () {
      final config = EnvironmentGuard.resolveAndValidate(rawEnv: 'local');
      expect(config.env, BackofficeEnv.local);
      expect(config.useEmulators, isTrue);
      expect(config.projectId, 'demo-tacopos-backoffice-v2');
      expect(config.authEmulatorPort, 9199);
      expect(config.firestoreEmulatorPort, 8180);
      expect(config.functionsEmulatorPort, 5101);
    });

    test('accepts valid DEV config pointing exclusively to tacopos-backoffice-dev', () {
      final config = EnvironmentGuard.resolveAndValidate(rawEnv: 'dev');
      expect(config.env, BackofficeEnv.dev);
      expect(config.useEmulators, isFalse);
      expect(config.projectId, BackofficeDevFirebaseOptions.projectId);
      expect(config.firebaseOptions.authDomain, 'tacopos-backoffice-dev.firebaseapp.com');
    });
  });
}
