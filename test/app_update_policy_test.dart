import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/app_update/app_update_policy.dart';
import 'package:tacopos/services/app_update_service.dart';
import 'package:tacopos/services/device_registry_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('evaluateAppUpdatePolicy', () {
    test(
      'canonical policy returns upToDate for current 3 minimum 3 recommended 3',
      () {
        final status = evaluateCanonicalAppUpdatePolicy(
          currentVersionCode: 3,
          active: true,
          minimumSupportedVersionCode: 3,
          recommendedVersionCode: 3,
          forceUpdate: false,
        );

        expect(status, AppUpdatePolicyStatus.upToDate);
      },
    );

    test(
      'canonical policy returns recommended for current 3 recommended 4',
      () {
        final status = evaluateCanonicalAppUpdatePolicy(
          currentVersionCode: 3,
          active: true,
          minimumSupportedVersionCode: 3,
          recommendedVersionCode: 4,
          forceUpdate: false,
        );

        expect(status, AppUpdatePolicyStatus.recommended);
      },
    );

    test('canonical policy returns required below minimum', () {
      final status = evaluateCanonicalAppUpdatePolicy(
        currentVersionCode: 3,
        active: true,
        minimumSupportedVersionCode: 4,
        recommendedVersionCode: 4,
        forceUpdate: false,
      );

      expect(status, AppUpdatePolicyStatus.required);
    });

    test('canonical policy forceUpdate requires below recommended', () {
      final required = evaluateCanonicalAppUpdatePolicy(
        currentVersionCode: 3,
        active: true,
        minimumSupportedVersionCode: 4,
        recommendedVersionCode: 4,
        forceUpdate: true,
      );
      final upToDate = evaluateCanonicalAppUpdatePolicy(
        currentVersionCode: 3,
        active: true,
        minimumSupportedVersionCode: 3,
        recommendedVersionCode: 4,
        forceUpdate: true,
      );

      expect(required, AppUpdatePolicyStatus.required);
      expect(upToDate, AppUpdatePolicyStatus.required);
    });

    test('canonical policy active false is upToDate', () {
      final status = evaluateCanonicalAppUpdatePolicy(
        currentVersionCode: 1,
        active: false,
        minimumSupportedVersionCode: 4,
        recommendedVersionCode: 4,
        forceUpdate: true,
      );

      expect(status, AppUpdatePolicyStatus.upToDate);
    });

    test('does nothing when current version is up to date', () {
      final decision = evaluateAppUpdatePolicy(
        const AppUpdatePolicyInput(
          currentVersionCode: 2,
          minimumSupportedVersionCode: 1,
          recommendedVersionCode: 2,
          forceUpdate: false,
          updateMessage: 'Update available',
        ),
      );

      expect(decision.severity, AppUpdateSeverity.none);
      expect(decision.canContinue, isTrue);
    });

    test('recommends update when current is below recommended', () {
      final decision = evaluateAppUpdatePolicy(
        const AppUpdatePolicyInput(
          currentVersionCode: 1,
          minimumSupportedVersionCode: 1,
          recommendedVersionCode: 2,
          forceUpdate: false,
          updateMessage: 'Nueva version disponible',
        ),
      );

      expect(decision.severity, AppUpdateSeverity.recommended);
      expect(decision.canContinue, isTrue);
      expect(decision.message, 'Nueva version disponible');
    });

    test('requires update when current is below minimum', () {
      final decision = evaluateAppUpdatePolicy(
        const AppUpdatePolicyInput(
          currentVersionCode: 1,
          minimumSupportedVersionCode: 2,
          recommendedVersionCode: 2,
          forceUpdate: false,
          updateMessage: 'Actualizacion requerida',
        ),
      );

      expect(decision.severity, AppUpdateSeverity.required);
      expect(decision.canContinue, isFalse);
    });

    test('forceUpdate blocks versions below recommended', () {
      final decision = evaluateAppUpdatePolicy(
        const AppUpdatePolicyInput(
          currentVersionCode: 2,
          minimumSupportedVersionCode: 1,
          recommendedVersionCode: 3,
          forceUpdate: true,
          updateMessage: '',
        ),
      );

      expect(decision.severity, AppUpdateSeverity.required);
      expect(decision.canContinue, isFalse);
      expect(decision.message, isNotEmpty);
    });

    test(
      'installed 10 minimum 10 recommended 11 force false does not block',
      () {
        final decision = evaluateAppUpdatePolicy(
          const AppUpdatePolicyInput(
            currentVersionCode: 10,
            minimumSupportedVersionCode: 10,
            recommendedVersionCode: 11,
            forceUpdate: false,
            updateMessage: 'Nueva version disponible',
          ),
        );

        expect(decision.severity, AppUpdateSeverity.recommended);
        expect(decision.canContinue, isTrue);
      },
    );

    test('installed 10 minimum 10 recommended 11 force true blocks', () {
      final decision = evaluateAppUpdatePolicy(
        const AppUpdatePolicyInput(
          currentVersionCode: 10,
          minimumSupportedVersionCode: 10,
          recommendedVersionCode: 11,
          forceUpdate: true,
          updateMessage: 'Actualizacion requerida',
        ),
      );

      expect(decision.severity, AppUpdateSeverity.required);
      expect(decision.canContinue, isFalse);
    });

    test(
      'installed 11 minimum 10 recommended 11 force true does not block',
      () {
        final decision = evaluateAppUpdatePolicy(
          const AppUpdatePolicyInput(
            currentVersionCode: 11,
            minimumSupportedVersionCode: 10,
            recommendedVersionCode: 11,
            forceUpdate: true,
            updateMessage: '',
          ),
        );

        expect(decision.severity, AppUpdateSeverity.none);
        expect(decision.canContinue, isTrue);
      },
    );

    test('forceUpdate requires versions below minimum', () {
      final decision = evaluateAppUpdatePolicy(
        const AppUpdatePolicyInput(
          currentVersionCode: 10,
          minimumSupportedVersionCode: 11,
          recommendedVersionCode: 11,
          forceUpdate: true,
          updateMessage: 'Actualizacion requerida',
        ),
      );

      expect(decision.severity, AppUpdateSeverity.required);
      expect(decision.canContinue, isFalse);
    });

    test('recommended higher with forceUpdate false does not block', () {
      final decision = evaluateAppUpdatePolicy(
        const AppUpdatePolicyInput(
          currentVersionCode: 10,
          minimumSupportedVersionCode: 10,
          recommendedVersionCode: 11,
          forceUpdate: false,
          updateMessage: 'Nueva version disponible',
        ),
      );

      expect(decision.severity, AppUpdateSeverity.recommended);
      expect(decision.canContinue, isTrue);
    });

    test('inactive config does not block', () {
      final decision = evaluateAppUpdatePolicy(
        const AppUpdatePolicyInput(
          currentVersionCode: 1,
          minimumSupportedVersionCode: 3,
          recommendedVersionCode: 3,
          forceUpdate: true,
          updateMessage: 'Actualizacion requerida',
          active: false,
        ),
      );

      expect(decision.severity, AppUpdateSeverity.none);
      expect(decision.canContinue, isTrue);
    });

    test('rollout only applies to enabled groups', () {
      final outsideRollout = evaluateAppUpdatePolicy(
        const AppUpdatePolicyInput(
          currentVersionCode: 1,
          minimumSupportedVersionCode: 1,
          recommendedVersionCode: 3,
          forceUpdate: false,
          updateMessage: 'Nueva version',
          rolloutGroup: 'all',
          enabledRolloutGroups: ['pilot'],
        ),
      );
      final insideRollout = evaluateAppUpdatePolicy(
        const AppUpdatePolicyInput(
          currentVersionCode: 1,
          minimumSupportedVersionCode: 1,
          recommendedVersionCode: 3,
          forceUpdate: false,
          updateMessage: 'Nueva version',
          rolloutGroup: 'pilot',
          enabledRolloutGroups: ['pilot'],
        ),
      );

      expect(outsideRollout.severity, AppUpdateSeverity.none);
      expect(insideRollout.severity, AppUpdateSeverity.recommended);
    });

    test('device status is derived from update severity', () {
      final required = evaluateAppUpdatePolicy(
        const AppUpdatePolicyInput(
          currentVersionCode: 1,
          minimumSupportedVersionCode: 2,
          recommendedVersionCode: 2,
          forceUpdate: false,
          updateMessage: 'Actualizacion requerida',
        ),
      );

      expect(required.deviceStatus, DeviceUpdateStatus.updateRequired);
      expect(deviceUpdateStatusName(required.deviceStatus), 'update_required');
      expect(
        parseDeviceUpdateStatus('update_recommended'),
        DeviceUpdateStatus.updateRecommended,
      );
      expect(parseDeviceUpdateStatus('otro'), DeviceUpdateStatus.unknown);
    });

    test('current 4 minimum 3 recommended 4 is upToDate', () {
      final status = evaluateCanonicalAppUpdatePolicy(
        currentVersionCode: 4,
        active: true,
        minimumSupportedVersionCode: 3,
        recommendedVersionCode: 4,
        forceUpdate: false,
      );

      expect(status, AppUpdatePolicyStatus.upToDate);
    });

    test('current 11 and minimum 11 allows continuing', () {
      final decision = evaluateAppUpdatePolicy(
        const AppUpdatePolicyInput(
          currentVersionCode: 11,
          minimumSupportedVersionCode: 11,
          recommendedVersionCode: 11,
          forceUpdate: false,
          updateMessage: '',
        ),
      );

      expect(decision.canContinue, isTrue);
      expect(decision.severity, AppUpdateSeverity.none);
    });

    test('current 11 and minimum 10 allows continuing', () {
      final decision = evaluateAppUpdatePolicy(
        const AppUpdatePolicyInput(
          currentVersionCode: 11,
          minimumSupportedVersionCode: 10,
          recommendedVersionCode: 11,
          forceUpdate: false,
          updateMessage: '',
        ),
      );

      expect(decision.canContinue, isTrue);
      expect(decision.severity, AppUpdateSeverity.none);
    });

    test('current 12 and minimum 11 allows continuing', () {
      final decision = evaluateAppUpdatePolicy(
        const AppUpdatePolicyInput(
          currentVersionCode: 12,
          minimumSupportedVersionCode: 11,
          recommendedVersionCode: 11,
          forceUpdate: false,
          updateMessage: '',
        ),
      );

      expect(decision.canContinue, isTrue);
      expect(decision.severity, AppUpdateSeverity.none);
    });

    test('current 10 and minimum 11 blocks', () {
      final decision = evaluateAppUpdatePolicy(
        const AppUpdatePolicyInput(
          currentVersionCode: 10,
          minimumSupportedVersionCode: 11,
          recommendedVersionCode: 11,
          forceUpdate: false,
          updateMessage: '',
        ),
      );

      expect(decision.canContinue, isFalse);
      expect(decision.severity, AppUpdateSeverity.required);
    });

    test('device registry uses the expected restaurant devices path', () {
      expect(
        DeviceRegistryService.documentPathForDevice('device-123'),
        'restaurants/main_restaurant/devices/device-123',
      );
    });

    test('device id validation rejects empty and slash ids', () {
      expect(DeviceRegistryService.isValidDeviceId(null), isFalse);
      expect(DeviceRegistryService.isValidDeviceId(''), isFalse);
      expect(DeviceRegistryService.isValidDeviceId('abc/def'), isFalse);
      expect(DeviceRegistryService.isValidDeviceId('firebase-uid'), isTrue);
    });

    test('telemetry failures do not change an upToDate policy result', () {
      final policyStatus = evaluateCanonicalAppUpdatePolicy(
        currentVersionCode: 4,
        active: true,
        minimumSupportedVersionCode: 3,
        recommendedVersionCode: 4,
        forceUpdate: false,
      );
      final telemetryStatus = parseDeviceUpdateStatus('unknown');

      expect(policyStatus, AppUpdatePolicyStatus.upToDate);
      expect(telemetryStatus, DeviceUpdateStatus.unknown);
    });

    test('incomplete or invalid config fields do not throw or block', () {
      final input = appUpdatePolicyInputFromConfigDataForTest(<String, dynamic>{
        'minimumSupportedVersionCode': 'invalid',
        'recommendedVersionCode': null,
        'forceUpdate': 'true',
        'active': 'yes',
        'rolloutGroups': 'all',
      }, currentVersionCode: 11);

      expect(input.minimumSupportedVersionCode, 11);
      expect(input.recommendedVersionCode, 11);
      expect(input.forceUpdate, isFalse);
      expect(input.updateMessage, isEmpty);
      expect(input.active, isFalse);
      expect(input.enabledRolloutGroups, isEmpty);
      expect(() => evaluateAppUpdatePolicy(input), returnsNormally);
      expect(evaluateAppUpdatePolicy(input).canContinue, isTrue);
    });
  });

  group('AppUpdatePolicyCache', () {
    setUp(() {
      resetAppUpdatePolicyMemoryCacheForTest();
    });

    test('guarda una politica valida localmente', () async {
      final cache = _MemoryAppUpdatePolicyCache();
      final policy = _storedPolicy(
        active: true,
        minimumSupportedVersionCode: 11,
        recommendedVersionCode: 11,
        forceUpdate: true,
      );

      await cache.save(policy);
      final restored = await cache.load();

      expect(restored, isNotNull);
      expect(restored!.active, isTrue);
      expect(restored.minimumSupportedVersionCode, 11);
      expect(restored.recommendedVersionCode, 11);
      expect(restored.forceUpdate, isTrue);
      expect(restored.updateMessage, 'Actualizacion requerida');
      expect(restored.fetchedAt, policy.fetchedAt);
    });

    test('restaura la politica despues de simular reinicio', () async {
      final cache = _MemoryAppUpdatePolicyCache();
      await cache.save(
        _storedPolicy(
          active: true,
          minimumSupportedVersionCode: 11,
          recommendedVersionCode: 11,
          forceUpdate: false,
        ),
      );
      resetAppUpdatePolicyMemoryCacheForTest();

      final restartedCache = _MemoryAppUpdatePolicyCache(restored: cache.saved);
      final restored = await restartedCache.load();
      final decision = evaluateAppUpdatePolicy(
        restored!.toPolicyInput(currentVersionCode: 10),
      );

      expect(decision.severity, AppUpdateSeverity.required);
      expect(decision.canContinue, isFalse);
    });

    test('mantiene bloqueo sin internet despues del reinicio', () async {
      final cache = _MemoryAppUpdatePolicyCache();
      await cache.save(
        _storedPolicy(
          active: true,
          minimumSupportedVersionCode: 11,
          recommendedVersionCode: 11,
          forceUpdate: false,
        ),
      );
      resetAppUpdatePolicyMemoryCacheForTest();

      final restored = await _MemoryAppUpdatePolicyCache(
        restored: cache.saved,
      ).load();
      final decision = evaluateAppUpdatePolicy(
        restored!.toPolicyInput(currentVersionCode: 10),
      );

      expect(decision.severity, AppUpdateSeverity.required);
      expect(decision.canContinue, isFalse);
    });

    test('no bloquea sin internet cuando nunca hubo politica valida', () async {
      final restored = await _MemoryAppUpdatePolicyCache().load();
      final decision = restored == null
          ? evaluateAppUpdatePolicy(
              const AppUpdatePolicyInput(
                currentVersionCode: 10,
                minimumSupportedVersionCode: 10,
                recommendedVersionCode: 10,
                forceUpdate: false,
                updateMessage: '',
                active: false,
              ),
            )
          : evaluateAppUpdatePolicy(
              restored.toPolicyInput(currentVersionCode: 10),
            );

      expect(restored, isNull);
      expect(decision.canContinue, isTrue);
      expect(decision.severity, AppUpdateSeverity.none);
    });

    test(
      'no sobrescribe la politica almacenada con configuracion invalida',
      () async {
        final cache = _MemoryAppUpdatePolicyCache();
        await cache.save(
          _storedPolicy(
            active: true,
            minimumSupportedVersionCode: 11,
            recommendedVersionCode: 11,
            forceUpdate: true,
          ),
        );
        final invalidPolicy =
            appUpdateStoredPolicyFromConfigDataForTest(<String, dynamic>{
              'active': 'yes',
              'minimumSupportedVersionCode': 'once',
              'recommendedVersionCode': null,
              'forceUpdate': 'true',
              'updateMessage': 123,
            });
        if (invalidPolicy != null) {
          await cache.save(invalidPolicy);
        }

        final restored = await cache.load();

        expect(invalidPolicy, isNull);
        expect(restored!.minimumSupportedVersionCode, 11);
        expect(restored.recommendedVersionCode, 11);
        expect(restored.forceUpdate, isTrue);
      },
    );
  });
}

AppUpdateStoredPolicy _storedPolicy({
  required bool active,
  required int minimumSupportedVersionCode,
  required int recommendedVersionCode,
  required bool forceUpdate,
}) {
  return AppUpdateStoredPolicy(
    active: active,
    minimumSupportedVersionCode: minimumSupportedVersionCode,
    recommendedVersionCode: recommendedVersionCode,
    forceUpdate: forceUpdate,
    updateMessage: forceUpdate
        ? 'Actualizacion requerida'
        : 'Nueva version disponible',
    fetchedAt: DateTime.utc(2026, 8, 4, 12),
  );
}

class _MemoryAppUpdatePolicyCache implements AppUpdatePolicyCache {
  _MemoryAppUpdatePolicyCache({AppUpdateStoredPolicy? restored})
    : saved = restored;

  AppUpdateStoredPolicy? saved;

  @override
  Future<AppUpdateStoredPolicy?> load() async {
    return saved;
  }

  @override
  Future<void> save(AppUpdateStoredPolicy policy) async {
    saved = policy;
  }
}
