import 'package:flutter_test/flutter_test.dart';
import 'package:tacopos/core/commercial/tenant_runtime_context.dart';
import 'package:tacopos/core/constants/app_constants.dart';
import 'package:tacopos/services/commercial_config_service.dart';

void main() {
  group('commercial configuration defaults', () {
    test('runtime defaults keep Los Padrinos compatibility disabled', () {
      final context = TenantRuntimeContext.defaults(
        branchId: 'aviacion',
        branchName: 'Aviacion',
      );

      expect(context.tenantId, 'los_padrinos');
      expect(context.restaurantId, AppConstants.restaurantId);
      expect(context.branchId, 'aviacion');
      expect(context.planId, 'signature');
      expect(context.compatibilityMode, isTrue);
      expect(context.licensingEnforcement, isFalse);
      expect(context.policyEngineEnabled, isFalse);
      expect(context.commercialFeaturesEnabled, isFalse);
    });

    test('branding missing or invalid falls back to current brand', () {
      final missing = CommercialBranding.fromMap(null);
      final corrupt = CommercialBranding.fromMap({
        'businessName': '',
        'shortName': '',
        'primaryColorHex': 'not-a-color',
        'accentColorHex': '#XYZ',
        'currencyCode': '',
        'locale': '',
        'timezone': '',
        'active': 'yes',
      });

      expect(missing.businessName, AppConstants.restaurantName);
      expect(missing.shortName, AppConstants.brandName);
      expect(missing.currencyCode, 'MXN');
      expect(corrupt.businessName, AppConstants.restaurantName);
      expect(corrupt.shortName, AppConstants.brandName);
      expect(corrupt.primaryColorHex, '#FFD54A');
      expect(corrupt.accentColorHex, '#F59A23');
      expect(corrupt.currencyCode, 'MXN');
      expect(corrupt.locale, 'es_MX');
      expect(corrupt.timezone, AppConstants.defaultTimezone);
      expect(corrupt.active, isTrue);
    });

    test('features and policies default to non blocking preparation', () {
      final features = AppCapabilities.fromMap({'pos': true, 'kitchen': 'bad'});
      final operations = OperationalPolicy.fromMap({
        'allowPaymentWithKitchenPending': true,
        'cardCommissionPercent': 'bad',
      });
      final benefits = BenefitPolicies.fromMap({
        'employeeDiscount': {'percent': 'bad'},
        'partnerDiscount': {'requiresPin': true},
      });

      expect(features.hasFeature('pos'), isTrue);
      expect(features.hasFeature('kitchen'), isTrue);
      expect(operations.allowPaymentWithKitchenPending, isTrue);
      expect(operations.cardCommissionPercent, 4);
      expect(benefits.employeeDiscount.enabled, isTrue);
      expect(benefits.employeeDiscount.percent, 30);
      expect(benefits.partnerDiscount.percent, 50);
      expect(benefits.partnerDiscount.requiresPin, isTrue);
    });

    test(
      'service without Firebase returns defaults and performs no writes',
      () async {
        final service = CommercialConfigService();

        final branding = await service.watchBranding().first;
        final context = await service.loadRuntimeContext();

        expect(branding.businessName, AppConstants.restaurantName);
        expect(context.restaurantId, AppConstants.restaurantId);
        expect(context.policyEngineEnabled, isFalse);
        expect(context.commercialFeaturesEnabled, isFalse);
        expect(
          service.prepareCommercialConfiguration,
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}
