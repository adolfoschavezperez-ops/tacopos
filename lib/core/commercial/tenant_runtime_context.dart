import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/brand_colors.dart';

class TenantRuntimeContext {
  const TenantRuntimeContext({
    required this.tenantId,
    required this.restaurantId,
    required this.branchId,
    required this.restaurantName,
    required this.branchName,
    required this.planId,
    required this.compatibilityMode,
    required this.licensingEnforcement,
    required this.policyEngineEnabled,
    required this.commercialFeaturesEnabled,
    required this.branding,
    required this.features,
    required this.operations,
    required this.benefits,
  });

  final String tenantId;
  final String restaurantId;
  final String branchId;
  final String restaurantName;
  final String branchName;
  final String planId;
  final bool compatibilityMode;
  final bool licensingEnforcement;
  final bool policyEngineEnabled;
  final bool commercialFeaturesEnabled;
  final CommercialBranding branding;
  final AppCapabilities features;
  final OperationalPolicy operations;
  final BenefitPolicies benefits;

  static TenantRuntimeContext defaults({String? branchId, String? branchName}) {
    return TenantRuntimeContext(
      tenantId: 'los_padrinos',
      restaurantId: AppConstants.restaurantId,
      branchId: _clean(branchId, AppConstants.defaultBranchId),
      restaurantName: AppConstants.restaurantName,
      branchName: _clean(branchName, AppConstants.defaultBranchName),
      planId: 'signature',
      compatibilityMode: true,
      licensingEnforcement: false,
      policyEngineEnabled: false,
      commercialFeaturesEnabled: false,
      branding: CommercialBranding.defaults(),
      features: AppCapabilities.defaults(),
      operations: OperationalPolicy.defaults(),
      benefits: BenefitPolicies.defaults(),
    );
  }

  TenantRuntimeContext copyWith({
    String? tenantId,
    String? restaurantId,
    String? branchId,
    String? restaurantName,
    String? branchName,
    String? planId,
    bool? compatibilityMode,
    bool? licensingEnforcement,
    bool? policyEngineEnabled,
    bool? commercialFeaturesEnabled,
    CommercialBranding? branding,
    AppCapabilities? features,
    OperationalPolicy? operations,
    BenefitPolicies? benefits,
  }) {
    return TenantRuntimeContext(
      tenantId: tenantId ?? this.tenantId,
      restaurantId: restaurantId ?? this.restaurantId,
      branchId: branchId ?? this.branchId,
      restaurantName: restaurantName ?? this.restaurantName,
      branchName: branchName ?? this.branchName,
      planId: planId ?? this.planId,
      compatibilityMode: compatibilityMode ?? this.compatibilityMode,
      licensingEnforcement: licensingEnforcement ?? this.licensingEnforcement,
      policyEngineEnabled: policyEngineEnabled ?? this.policyEngineEnabled,
      commercialFeaturesEnabled:
          commercialFeaturesEnabled ?? this.commercialFeaturesEnabled,
      branding: branding ?? this.branding,
      features: features ?? this.features,
      operations: operations ?? this.operations,
      benefits: benefits ?? this.benefits,
    );
  }
}

class CommercialPlan {
  const CommercialPlan({required this.id, required this.name});

  final String id;
  final String name;

  static const plans = [
    CommercialPlan(id: 'essential', name: 'TacoPOS Esencial'),
    CommercialPlan(id: 'pro', name: 'TacoPOS Pro'),
    CommercialPlan(id: 'signature', name: 'TacoPOS Signature'),
  ];

  static String nameFor(String planId) {
    for (final plan in plans) {
      if (plan.id == planId) return plan.name;
    }
    return 'TacoPOS Signature';
  }
}

class CommercialBranding {
  const CommercialBranding({
    required this.businessName,
    required this.shortName,
    required this.logoUrl,
    required this.primaryColorHex,
    required this.accentColorHex,
    required this.address,
    required this.phone,
    required this.receiptHeader,
    required this.receiptFooter,
    required this.currencyCode,
    required this.locale,
    required this.timezone,
    required this.active,
  });

  final String businessName;
  final String shortName;
  final String logoUrl;
  final String primaryColorHex;
  final String accentColorHex;
  final String address;
  final String phone;
  final String receiptHeader;
  final String receiptFooter;
  final String currencyCode;
  final String locale;
  final String timezone;
  final bool active;

  static CommercialBranding defaults() {
    return const CommercialBranding(
      businessName: AppConstants.restaurantName,
      shortName: AppConstants.brandName,
      logoUrl: '',
      primaryColorHex: '#FFD54A',
      accentColorHex: '#F59A23',
      address: '',
      phone: '',
      receiptHeader: AppConstants.restaurantName,
      receiptFooter: 'Gracias por su compra',
      currencyCode: 'MXN',
      locale: 'es_MX',
      timezone: AppConstants.defaultTimezone,
      active: true,
    );
  }

  factory CommercialBranding.fromMap(Map<String, dynamic>? data) {
    final fallback = CommercialBranding.defaults();
    if (data == null) return fallback;
    return CommercialBranding(
      businessName: _clean(data['businessName'], fallback.businessName),
      shortName: _clean(data['shortName'], fallback.shortName),
      logoUrl: _clean(data['logoUrl'], fallback.logoUrl),
      primaryColorHex:
          _validHex(data['primaryColorHex']) ?? fallback.primaryColorHex,
      accentColorHex:
          _validHex(data['accentColorHex']) ?? fallback.accentColorHex,
      address: _clean(data['address'], fallback.address),
      phone: _clean(data['phone'], fallback.phone),
      receiptHeader: _clean(data['receiptHeader'], fallback.receiptHeader),
      receiptFooter: _clean(data['receiptFooter'], fallback.receiptFooter),
      currencyCode: _clean(data['currencyCode'], fallback.currencyCode),
      locale: _clean(data['locale'], fallback.locale),
      timezone: _clean(data['timezone'], fallback.timezone),
      active: data['active'] is bool ? data['active'] as bool : fallback.active,
    );
  }

  Map<String, Object?> toFirestore() {
    return {
      'businessName': businessName,
      'shortName': shortName,
      'logoUrl': logoUrl,
      'primaryColorHex': primaryColorHex,
      'accentColorHex': accentColorHex,
      'address': address,
      'phone': phone,
      'receiptHeader': receiptHeader,
      'receiptFooter': receiptFooter,
      'currencyCode': currencyCode,
      'locale': locale,
      'timezone': timezone,
      'active': active,
    };
  }

  Color get primaryColor =>
      _colorFromHex(primaryColorHex) ?? BrandColors.yellow;
  Color get accentColor => _colorFromHex(accentColorHex) ?? BrandColors.orange;
}

class AppCapabilities {
  const AppCapabilities(this.values);

  final Map<String, bool> values;

  static const featureKeys = [
    'pos',
    'tables',
    'takeout',
    'standingOrders',
    'kitchen',
    'cashManagement',
    'basicReports',
    'advancedReports',
    'purchases',
    'suppliers',
    'inventory',
    'cashAudit',
    'financialDashboard',
    'yieldAndRecipes',
    'multiBranch',
    'advancedPermissions',
    'customBranding',
    'supportTickets',
    'wishlist',
  ];

  static AppCapabilities defaults() {
    return AppCapabilities({for (final key in featureKeys) key: true});
  }

  factory AppCapabilities.fromMap(Map<String, dynamic>? data) {
    final fallback = AppCapabilities.defaults().values;
    if (data == null) return AppCapabilities(fallback);
    return AppCapabilities({
      for (final key in featureKeys)
        key: data[key] is bool ? data[key] as bool : fallback[key] ?? true,
    });
  }

  bool hasFeature(String feature) => values[feature] ?? false;

  bool canUseModule(String module) => hasFeature(module);

  List<String> visibleModules() {
    return values.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  Map<String, Object?> toFirestore() => Map<String, Object?>.from(values);
}

class OperationalPolicy {
  const OperationalPolicy({
    required this.requireCashOpening,
    required this.requireCashClosing,
    required this.requireKitchenOpening,
    required this.requireKitchenClosing,
    required this.blockPaymentWhileKitchenPending,
    required this.allowPaymentWithKitchenPending,
    required this.autoStartKitchenSession,
    required this.autoCloseKitchenSession,
    required this.requireCancellationReason,
    required this.requireDiscountAuthorization,
    required this.allowSplitPayments,
    required this.cardCommissionEnabled,
    required this.cardCommissionPercent,
    required this.businessDayFollowsCashSession,
  });

  final bool requireCashOpening;
  final bool requireCashClosing;
  final bool requireKitchenOpening;
  final bool requireKitchenClosing;
  final bool blockPaymentWhileKitchenPending;
  final bool allowPaymentWithKitchenPending;
  final bool autoStartKitchenSession;
  final bool autoCloseKitchenSession;
  final bool requireCancellationReason;
  final bool requireDiscountAuthorization;
  final bool allowSplitPayments;
  final bool cardCommissionEnabled;
  final double cardCommissionPercent;
  final bool businessDayFollowsCashSession;

  static OperationalPolicy defaults() {
    return const OperationalPolicy(
      requireCashOpening: true,
      requireCashClosing: true,
      requireKitchenOpening: true,
      requireKitchenClosing: true,
      blockPaymentWhileKitchenPending: false,
      allowPaymentWithKitchenPending: true,
      autoStartKitchenSession: false,
      autoCloseKitchenSession: false,
      requireCancellationReason: true,
      requireDiscountAuthorization: true,
      allowSplitPayments: true,
      cardCommissionEnabled: true,
      cardCommissionPercent: 4,
      businessDayFollowsCashSession: true,
    );
  }

  factory OperationalPolicy.fromMap(Map<String, dynamic>? data) {
    final fallback = OperationalPolicy.defaults();
    if (data == null) return fallback;
    return OperationalPolicy(
      requireCashOpening: _readBool(
        data,
        'requireCashOpening',
        fallback.requireCashOpening,
      ),
      requireCashClosing: _readBool(
        data,
        'requireCashClosing',
        fallback.requireCashClosing,
      ),
      requireKitchenOpening: _readBool(
        data,
        'requireKitchenOpening',
        fallback.requireKitchenOpening,
      ),
      requireKitchenClosing: _readBool(
        data,
        'requireKitchenClosing',
        fallback.requireKitchenClosing,
      ),
      blockPaymentWhileKitchenPending: _readBool(
        data,
        'blockPaymentWhileKitchenPending',
        fallback.blockPaymentWhileKitchenPending,
      ),
      allowPaymentWithKitchenPending: _readBool(
        data,
        'allowPaymentWithKitchenPending',
        fallback.allowPaymentWithKitchenPending,
      ),
      autoStartKitchenSession: _readBool(
        data,
        'autoStartKitchenSession',
        fallback.autoStartKitchenSession,
      ),
      autoCloseKitchenSession: _readBool(
        data,
        'autoCloseKitchenSession',
        fallback.autoCloseKitchenSession,
      ),
      requireCancellationReason: _readBool(
        data,
        'requireCancellationReason',
        fallback.requireCancellationReason,
      ),
      requireDiscountAuthorization: _readBool(
        data,
        'requireDiscountAuthorization',
        fallback.requireDiscountAuthorization,
      ),
      allowSplitPayments: _readBool(
        data,
        'allowSplitPayments',
        fallback.allowSplitPayments,
      ),
      cardCommissionEnabled: _readBool(
        data,
        'cardCommissionEnabled',
        fallback.cardCommissionEnabled,
      ),
      cardCommissionPercent: _readDouble(
        data,
        'cardCommissionPercent',
        fallback.cardCommissionPercent,
      ),
      businessDayFollowsCashSession: _readBool(
        data,
        'businessDayFollowsCashSession',
        fallback.businessDayFollowsCashSession,
      ),
    );
  }

  Map<String, Object?> toFirestore() {
    return {
      'requireCashOpening': requireCashOpening,
      'requireCashClosing': requireCashClosing,
      'requireKitchenOpening': requireKitchenOpening,
      'requireKitchenClosing': requireKitchenClosing,
      'blockPaymentWhileKitchenPending': blockPaymentWhileKitchenPending,
      'allowPaymentWithKitchenPending': allowPaymentWithKitchenPending,
      'autoStartKitchenSession': autoStartKitchenSession,
      'autoCloseKitchenSession': autoCloseKitchenSession,
      'requireCancellationReason': requireCancellationReason,
      'requireDiscountAuthorization': requireDiscountAuthorization,
      'allowSplitPayments': allowSplitPayments,
      'cardCommissionEnabled': cardCommissionEnabled,
      'cardCommissionPercent': cardCommissionPercent,
      'businessDayFollowsCashSession': businessDayFollowsCashSession,
    };
  }
}

class BenefitPolicies {
  const BenefitPolicies({
    required this.employeeDiscount,
    required this.employeeMeal,
    required this.partnerDiscount,
    required this.friendsAndFamilyDiscount,
  });

  final EmployeeDiscountPolicy employeeDiscount;
  final EmployeeMealPolicy employeeMeal;
  final PartnerDiscountPolicy partnerDiscount;
  final FriendsAndFamilyDiscountPolicy friendsAndFamilyDiscount;

  static BenefitPolicies defaults() {
    return const BenefitPolicies(
      employeeDiscount: EmployeeDiscountPolicy(
        enabled: true,
        percent: 30,
        maxOrdersPerDay: 1,
        requiresAuthorization: false,
        allowTakeout: true,
        combinable: false,
      ),
      employeeMeal: EmployeeMealPolicy(
        enabled: true,
        maxMealsPerDay: 1,
        maxAmount: 0,
        onlyDuringActiveShift: false,
        dineInOnly: true,
        requiresAuthorization: false,
      ),
      partnerDiscount: PartnerDiscountPolicy(
        enabled: true,
        percent: 50,
        maxOrdersPerDay: 1,
        requiresPin: true,
        allowGuests: true,
        combinable: false,
      ),
      friendsAndFamilyDiscount: FriendsAndFamilyDiscountPolicy(
        enabled: true,
        percent: 20,
        maxOrdersPerDay: 1,
        requiresAuthorization: true,
        requiresReason: true,
        combinable: false,
      ),
    );
  }

  factory BenefitPolicies.fromMap(Map<String, dynamic>? data) {
    final fallback = BenefitPolicies.defaults();
    if (data == null) return fallback;
    return BenefitPolicies(
      employeeDiscount: EmployeeDiscountPolicy.fromMap(
        _map(data['employeeDiscount']),
        fallback.employeeDiscount,
      ),
      employeeMeal: EmployeeMealPolicy.fromMap(
        _map(data['employeeMeal']),
        fallback.employeeMeal,
      ),
      partnerDiscount: PartnerDiscountPolicy.fromMap(
        _map(data['partnerDiscount']),
        fallback.partnerDiscount,
      ),
      friendsAndFamilyDiscount: FriendsAndFamilyDiscountPolicy.fromMap(
        _map(data['friendsAndFamilyDiscount']),
        fallback.friendsAndFamilyDiscount,
      ),
    );
  }

  Map<String, Object?> toFirestore() {
    return {
      'employeeDiscount': employeeDiscount.toFirestore(),
      'employeeMeal': employeeMeal.toFirestore(),
      'partnerDiscount': partnerDiscount.toFirestore(),
      'friendsAndFamilyDiscount': friendsAndFamilyDiscount.toFirestore(),
    };
  }
}

class EmployeeDiscountPolicy {
  const EmployeeDiscountPolicy({
    required this.enabled,
    required this.percent,
    required this.maxOrdersPerDay,
    required this.requiresAuthorization,
    required this.allowTakeout,
    required this.combinable,
  });

  final bool enabled;
  final double percent;
  final int maxOrdersPerDay;
  final bool requiresAuthorization;
  final bool allowTakeout;
  final bool combinable;

  factory EmployeeDiscountPolicy.fromMap(
    Map<String, dynamic>? data,
    EmployeeDiscountPolicy fallback,
  ) {
    return EmployeeDiscountPolicy(
      enabled: _readBool(data, 'enabled', fallback.enabled),
      percent: _readDouble(data, 'percent', fallback.percent),
      maxOrdersPerDay: _readInt(
        data,
        'maxOrdersPerDay',
        fallback.maxOrdersPerDay,
      ),
      requiresAuthorization: _readBool(
        data,
        'requiresAuthorization',
        fallback.requiresAuthorization,
      ),
      allowTakeout: _readBool(data, 'allowTakeout', fallback.allowTakeout),
      combinable: _readBool(data, 'combinable', fallback.combinable),
    );
  }

  Map<String, Object?> toFirestore() => {
    'enabled': enabled,
    'percent': percent,
    'maxOrdersPerDay': maxOrdersPerDay,
    'requiresAuthorization': requiresAuthorization,
    'allowTakeout': allowTakeout,
    'combinable': combinable,
  };
}

class EmployeeMealPolicy {
  const EmployeeMealPolicy({
    required this.enabled,
    required this.maxMealsPerDay,
    required this.maxAmount,
    required this.onlyDuringActiveShift,
    required this.dineInOnly,
    required this.requiresAuthorization,
  });

  final bool enabled;
  final int maxMealsPerDay;
  final double maxAmount;
  final bool onlyDuringActiveShift;
  final bool dineInOnly;
  final bool requiresAuthorization;

  factory EmployeeMealPolicy.fromMap(
    Map<String, dynamic>? data,
    EmployeeMealPolicy fallback,
  ) {
    return EmployeeMealPolicy(
      enabled: _readBool(data, 'enabled', fallback.enabled),
      maxMealsPerDay: _readInt(data, 'maxMealsPerDay', fallback.maxMealsPerDay),
      maxAmount: _readDouble(data, 'maxAmount', fallback.maxAmount),
      onlyDuringActiveShift: _readBool(
        data,
        'onlyDuringActiveShift',
        fallback.onlyDuringActiveShift,
      ),
      dineInOnly: _readBool(data, 'dineInOnly', fallback.dineInOnly),
      requiresAuthorization: _readBool(
        data,
        'requiresAuthorization',
        fallback.requiresAuthorization,
      ),
    );
  }

  Map<String, Object?> toFirestore() => {
    'enabled': enabled,
    'maxMealsPerDay': maxMealsPerDay,
    'maxAmount': maxAmount,
    'onlyDuringActiveShift': onlyDuringActiveShift,
    'dineInOnly': dineInOnly,
    'requiresAuthorization': requiresAuthorization,
  };
}

class PartnerDiscountPolicy {
  const PartnerDiscountPolicy({
    required this.enabled,
    required this.percent,
    required this.maxOrdersPerDay,
    required this.requiresPin,
    required this.allowGuests,
    required this.combinable,
  });

  final bool enabled;
  final double percent;
  final int maxOrdersPerDay;
  final bool requiresPin;
  final bool allowGuests;
  final bool combinable;

  factory PartnerDiscountPolicy.fromMap(
    Map<String, dynamic>? data,
    PartnerDiscountPolicy fallback,
  ) {
    return PartnerDiscountPolicy(
      enabled: _readBool(data, 'enabled', fallback.enabled),
      percent: _readDouble(data, 'percent', fallback.percent),
      maxOrdersPerDay: _readInt(
        data,
        'maxOrdersPerDay',
        fallback.maxOrdersPerDay,
      ),
      requiresPin: _readBool(data, 'requiresPin', fallback.requiresPin),
      allowGuests: _readBool(data, 'allowGuests', fallback.allowGuests),
      combinable: _readBool(data, 'combinable', fallback.combinable),
    );
  }

  Map<String, Object?> toFirestore() => {
    'enabled': enabled,
    'percent': percent,
    'maxOrdersPerDay': maxOrdersPerDay,
    'requiresPin': requiresPin,
    'allowGuests': allowGuests,
    'combinable': combinable,
  };
}

class FriendsAndFamilyDiscountPolicy {
  const FriendsAndFamilyDiscountPolicy({
    required this.enabled,
    required this.percent,
    required this.maxOrdersPerDay,
    required this.requiresAuthorization,
    required this.requiresReason,
    required this.combinable,
  });

  final bool enabled;
  final double percent;
  final int maxOrdersPerDay;
  final bool requiresAuthorization;
  final bool requiresReason;
  final bool combinable;

  factory FriendsAndFamilyDiscountPolicy.fromMap(
    Map<String, dynamic>? data,
    FriendsAndFamilyDiscountPolicy fallback,
  ) {
    return FriendsAndFamilyDiscountPolicy(
      enabled: _readBool(data, 'enabled', fallback.enabled),
      percent: _readDouble(data, 'percent', fallback.percent),
      maxOrdersPerDay: _readInt(
        data,
        'maxOrdersPerDay',
        fallback.maxOrdersPerDay,
      ),
      requiresAuthorization: _readBool(
        data,
        'requiresAuthorization',
        fallback.requiresAuthorization,
      ),
      requiresReason: _readBool(
        data,
        'requiresReason',
        fallback.requiresReason,
      ),
      combinable: _readBool(data, 'combinable', fallback.combinable),
    );
  }

  Map<String, Object?> toFirestore() => {
    'enabled': enabled,
    'percent': percent,
    'maxOrdersPerDay': maxOrdersPerDay,
    'requiresAuthorization': requiresAuthorization,
    'requiresReason': requiresReason,
    'combinable': combinable,
  };
}

class BenefitPolicySnapshot {
  const BenefitPolicySnapshot({
    required this.policyType,
    required this.policyVersion,
    required this.percent,
    required this.maxAllowed,
    required this.beneficiaryId,
    required this.authorizedBy,
    required this.appliedAt,
  });

  final String policyType;
  final String policyVersion;
  final double percent;
  final double maxAllowed;
  final String beneficiaryId;
  final String authorizedBy;
  final DateTime? appliedAt;

  Map<String, Object?> toFirestore() {
    return {
      'policyType': policyType,
      'policyVersion': policyVersion,
      'percent': percent,
      'maxAllowed': maxAllowed,
      'beneficiaryId': beneficiaryId,
      'authorizedBy': authorizedBy,
      'appliedAt': appliedAt,
    };
  }
}

String _clean(Object? value, String fallback) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

Map<String, dynamic>? _map(Object? value) {
  return value is Map ? Map<String, dynamic>.from(value) : null;
}

bool _readBool(Map<String, dynamic>? data, String key, bool fallback) {
  final value = data?[key];
  return value is bool ? value : fallback;
}

int _readInt(Map<String, dynamic>? data, String key, int fallback) {
  final value = data?[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return fallback;
}

double _readDouble(Map<String, dynamic>? data, String key, double fallback) {
  final value = data?[key];
  if (value is num) return value.toDouble();
  return fallback;
}

String? _validHex(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  final clean = text.startsWith('#') ? text.substring(1) : text;
  if (clean.length != 6 && clean.length != 8) return null;
  final parsed = int.tryParse(clean, radix: 16);
  return parsed == null ? null : '#${clean.toUpperCase()}';
}

Color? _colorFromHex(String value) {
  final clean = _validHex(value);
  if (clean == null) return null;
  final hex = clean.substring(1);
  final value32 = hex.length == 6 ? 'FF$hex' : hex;
  final parsed = int.tryParse(value32, radix: 16);
  return parsed == null ? null : Color(parsed);
}
