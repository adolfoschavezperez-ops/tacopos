import 'package:firebase_core/firebase_core.dart';

import 'firebase_options_dev.dart';

enum BackofficeEnv { local, dev, preview, prod }

class EnvironmentGuardException implements Exception {
  const EnvironmentGuardException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'EnvironmentGuardException($code): $message';
}

class BackofficeConfig {
  const BackofficeConfig({
    required this.env,
    required this.firebaseOptions,
    required this.useEmulators,
    required this.emulatorHost,
    required this.authEmulatorPort,
    required this.firestoreEmulatorPort,
    required this.functionsEmulatorPort,
    required this.functionsRegion,
    required this.defaultRestaurantId,
    this.previewApiUrl = '',
  });

  final BackofficeEnv env;
  final FirebaseOptions firebaseOptions;
  final bool useEmulators;
  final String emulatorHost;
  final int authEmulatorPort;
  final int firestoreEmulatorPort;
  final int functionsEmulatorPort;
  final String functionsRegion;
  final String defaultRestaurantId;
  final String previewApiUrl;

  String get projectId => firebaseOptions.projectId;

  String get badgeLabel => switch (env) {
    BackofficeEnv.local => 'LOCAL • EMULADOR',
    BackofficeEnv.dev => 'DEV • $projectId',
    BackofficeEnv.preview => 'PREVIEW — Datos reales · Solo consulta',
    BackofficeEnv.prod => 'PROD',
  };

  bool get isLocal => env == BackofficeEnv.local;
  bool get isDev => env == BackofficeEnv.dev;
  bool get isPreview => env == BackofficeEnv.preview;
  bool get isReadOnly => env == BackofficeEnv.preview;
}

class EnvironmentGuard {
  const EnvironmentGuard._();

  /// Production and other protected project IDs that Backoffice 2.0 must NEVER
  /// connect to during Phase 2 or in local/dev builds.
  static const Set<String> forbiddenProjectIds = {
    'tacopos-renovadev',
    'tacopos-control',
  };

  static const Set<String> forbiddenHostFragments = {
    'tacopos-renovadev',
    'tacopos-control',
    'github.io',
  };

  static const Set<String> allowedEmulatorHosts = {
    'localhost',
    '127.0.0.1',
  };

  static const String compileTimeEnv = String.fromEnvironment('ENV');
  static const String compileTimeProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const String compileTimeEmulatorHost = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  static const String compileTimeRestaurantId = String.fromEnvironment(
    'DEFAULT_RESTAURANT_ID',
    defaultValue: 'rest_alpha',
  );
  static const String compileTimePreviewApiUrl = String.fromEnvironment(
    'PREVIEW_API_URL',
  );
  static const bool compileTimeUseEmulators = bool.fromEnvironment(
    'USE_EMULATORS',
  );

  static BackofficeConfig resolveFromEnvironment() {
    return resolveAndValidate(
      rawEnv: compileTimeEnv,
      overrideProjectId: compileTimeProjectId,
      emulatorHost: compileTimeEmulatorHost,
      defaultRestaurantId: compileTimeRestaurantId,
      previewApiUrl: compileTimePreviewApiUrl,
      useEmulatorsInPreview: compileTimeUseEmulators,
    );
  }

  static BackofficeConfig resolveAndValidate({
    required String rawEnv,
    String overrideProjectId = '',
    String emulatorHost = '127.0.0.1',
    String defaultRestaurantId = 'rest_alpha',
    String previewApiUrl = '',
    bool useEmulatorsInPreview = false,
    FirebaseOptions? customOptions,
  }) {
    final normalizedEnv = rawEnv.trim().toLowerCase();
    if (normalizedEnv.isEmpty) {
      throw const EnvironmentGuardException(
        'MISSING_ENV',
        'Falta la variable de ambiente ENV. Especifica --dart-define=ENV=local o --dart-define=ENV=dev.',
      );
    }

    final BackofficeEnv env;
    switch (normalizedEnv) {
      case 'local':
        env = BackofficeEnv.local;
        break;
      case 'dev':
        env = BackofficeEnv.dev;
        break;
      case 'preview':
        env = BackofficeEnv.preview;
        break;
      case 'prod':
        throw const EnvironmentGuardException(
          'PROD_BLOCKED',
          'El ambiente PROD está reservado y bloqueado en Fase 2. No se permite conexión a producción.',
        );
      default:
        throw EnvironmentGuardException(
          'UNKNOWN_ENV',
          'Configuración de ambiente desconocida: "$rawEnv". Valores permitidos: local, dev, preview.',
        );
    }

    final effectiveUseEmulators =
        env == BackofficeEnv.local ||
        (env == BackofficeEnv.preview &&
            useEmulatorsInPreview &&
            overrideProjectId.trim().startsWith('demo-'));

    final FirebaseOptions options =
        customOptions ??
        switch (env) {
          BackofficeEnv.local => BackofficeDevFirebaseOptions.localEmulator,
          BackofficeEnv.dev => BackofficeDevFirebaseOptions.web,
          BackofficeEnv.preview =>
            effectiveUseEmulators
                ? BackofficeDevFirebaseOptions.localEmulator
                : BackofficeDevFirebaseOptions.web,
          BackofficeEnv.prod => throw const EnvironmentGuardException(
            'PROD_BLOCKED',
            'PROD bloqueado.',
          ),
        };

    final effectiveProjectId = overrideProjectId.trim().isNotEmpty
        ? overrideProjectId.trim()
        : options.projectId.trim();

    if (effectiveProjectId.isEmpty) {
      throw const EnvironmentGuardException(
        'MISSING_PROJECT_ID',
        'Falta el projectId de Firebase en la configuración.',
      );
    }

    if (forbiddenProjectIds.contains(effectiveProjectId.toLowerCase())) {
      throw EnvironmentGuardException(
        'FORBIDDEN_PROD_PROJECT',
        'Bloqueado por seguridad: el projectId "$effectiveProjectId" corresponde a un ambiente productivo o protegido.',
      );
    }

    final authDomain = (options.authDomain ?? '').toLowerCase();
    final storageBucket = (options.storageBucket ?? '').toLowerCase();
    for (final fragment in forbiddenHostFragments) {
      if (authDomain.contains(fragment) || storageBucket.contains(fragment)) {
        throw EnvironmentGuardException(
          'FORBIDDEN_ENDPOINT',
          'Se detectó un endpoint no autorizado ("$fragment") en la configuración de $normalizedEnv.',
        );
      }
    }

    if (env == BackofficeEnv.dev) {
      if (effectiveProjectId != BackofficeDevFirebaseOptions.projectId) {
        throw EnvironmentGuardException(
          'INVALID_DEV_PROJECT',
          'La compilación DEV solo puede apuntar a "${BackofficeDevFirebaseOptions.projectId}", pero recibió "$effectiveProjectId".',
        );
      }
      if (!authDomain.contains(BackofficeDevFirebaseOptions.projectId)) {
        throw const EnvironmentGuardException(
          'INVALID_DEV_AUTH_DOMAIN',
          'El authDomain de DEV no coincide con tacopos-backoffice-dev.',
        );
      }
    }

    if (env == BackofficeEnv.local) {
      if (!effectiveProjectId.startsWith('demo-')) {
        throw EnvironmentGuardException(
          'INVALID_LOCAL_PROJECT',
          'El ambiente LOCAL requiere un projectId aislado con prefijo "demo-", recibido: "$effectiveProjectId".',
        );
      }
      final normalizedHost = emulatorHost.trim().toLowerCase();
      if (!allowedEmulatorHosts.contains(normalizedHost)) {
        throw EnvironmentGuardException(
          'UNAUTHORIZED_EMULATOR_HOST',
          'Host de emulador no autorizado: "$emulatorHost". Solo se permite localhost o 127.0.0.1.',
        );
      }
    }

    if (env == BackofficeEnv.preview) {
      final cleanPreviewUrl = previewApiUrl.trim();
      final uri = Uri.tryParse(cleanPreviewUrl);
      final isLocalLoopback = uri != null &&
          (uri.host == '127.0.0.1' || uri.host == 'localhost') &&
          (uri.scheme == 'http' || uri.scheme == 'https');
      final isHttps = uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
      if (cleanPreviewUrl.isEmpty || (!isHttps && !isLocalLoopback)) {
        throw const EnvironmentGuardException(
          'INVALID_PREVIEW_API_URL',
          'El ambiente PREVIEW requiere PREVIEW_API_URL válida con HTTPS (o loopback en pruebas locales).',
        );
      }
      if (cleanPreviewUrl.toLowerCase().contains('github.io')) {
        throw const EnvironmentGuardException(
          'FORBIDDEN_PREVIEW_ENDPOINT',
          'PREVIEW_API_URL no puede apuntar a github.io.',
        );
      }
      if (!effectiveUseEmulators &&
          (defaultRestaurantId.trim().isEmpty ||
              defaultRestaurantId.trim() == 'rest_alpha')) {
        throw const EnvironmentGuardException(
          'INVALID_PREVIEW_RESTAURANT_ID',
          'En ambiente PREVIEW real se debe configurar DEFAULT_RESTAURANT_ID con el identificador real del restaurante (no rest_alpha).',
        );
      }
    }

    return BackofficeConfig(
      env: env,
      firebaseOptions: options,
      useEmulators:
          env == BackofficeEnv.local ||
          (env == BackofficeEnv.preview &&
              useEmulatorsInPreview &&
              effectiveProjectId.startsWith('demo-')),
      emulatorHost: emulatorHost.trim(),
      authEmulatorPort: 9199,
      firestoreEmulatorPort: 8180,
      functionsEmulatorPort: 5101,
      functionsRegion: 'us-central1',
      defaultRestaurantId: defaultRestaurantId.trim().isEmpty
          ? 'rest_alpha'
          : defaultRestaurantId.trim(),
      previewApiUrl: previewApiUrl.trim(),
    );
  }
}
