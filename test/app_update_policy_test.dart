import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/app_update/app_update_policy.dart';

void main() {
  group('evaluateAppUpdatePolicy', () {
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

    test('forceUpdate requires versions below recommended', () {
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
  });
}
