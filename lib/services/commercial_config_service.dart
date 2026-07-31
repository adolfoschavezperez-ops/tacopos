import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/commercial/tenant_runtime_context.dart';
import '../core/constants/app_constants.dart';
import 'app_session.dart';

class CommercialConfigService {
  CommercialConfigService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  static final instance = CommercialConfigService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> get _restaurantRef =>
      _firestore.collection('restaurants').doc(AppConstants.restaurantId);

  CollectionReference<Map<String, dynamic>> get _settingsRef =>
      _restaurantRef.collection('settings');

  DocumentReference<Map<String, dynamic>> settingRef(String id) =>
      _settingsRef.doc(id);

  Stream<CommercialBranding> watchBranding() {
    return settingRef('branding')
        .snapshots()
        .map((snapshot) => CommercialBranding.fromMap(snapshot.data()))
        .handleError((Object error, StackTrace stackTrace) {
          debugPrint(
            'COMMERCIAL_BRANDING_WARNING '
            'restaurantId=${AppConstants.restaurantId} '
            'error=$error stackTrace=$stackTrace',
          );
        });
  }

  Future<TenantRuntimeContext> loadRuntimeContext() async {
    final fallback = TenantRuntimeContext.defaults(
      branchId: AppSession.instance.currentBranchId,
      branchName: AppSession.instance.currentBranchName,
    );
    try {
      final snapshots = await Future.wait([
        settingRef('commercial').get(),
        settingRef('branding').get(),
        settingRef('features').get(),
        settingRef('operations').get(),
        settingRef('benefits').get(),
      ]).timeout(const Duration(seconds: 6));

      final commercial = snapshots[0].data();
      return fallback.copyWith(
        tenantId: _readString(commercial, 'tenantId', fallback.tenantId),
        planId: _readString(commercial, 'planId', fallback.planId),
        compatibilityMode: _readBool(
          commercial,
          'compatibilityMode',
          fallback.compatibilityMode,
        ),
        licensingEnforcement: _readBool(
          commercial,
          'licensingEnforcement',
          fallback.licensingEnforcement,
        ),
        policyEngineEnabled: _readBool(
          commercial,
          'policyEngineEnabled',
          fallback.policyEngineEnabled,
        ),
        commercialFeaturesEnabled: _readBool(
          commercial,
          'commercialFeaturesEnabled',
          fallback.commercialFeaturesEnabled,
        ),
        branding: CommercialBranding.fromMap(snapshots[1].data()),
        features: AppCapabilities.fromMap(snapshots[2].data()),
        operations: OperationalPolicy.fromMap(snapshots[3].data()),
        benefits: BenefitPolicies.fromMap(snapshots[4].data()),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'COMMERCIAL_CONTEXT_WARNING '
        'restaurantId=${AppConstants.restaurantId} '
        'error=$error stackTrace=$stackTrace',
      );
      return fallback;
    }
  }

  Future<CommercialPreparationResult> prepareCommercialConfiguration() async {
    final defaults = _defaultDocuments();
    final created = <String>[];
    final existing = <String>[];
    final errors = <String>[];

    for (final entry in defaults.entries) {
      try {
        final ref = settingRef(entry.key);
        final snapshot = await ref.get();
        if (snapshot.exists) {
          existing.add(entry.key);
          continue;
        }
        await ref.set({
          ...entry.value,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        created.add(entry.key);
      } catch (error) {
        errors.add('${entry.key}: $error');
      }
    }

    if (created.isNotEmpty) {
      await _logActivity(
        type: 'commercial_configuration_prepared',
        data: {
          'createdDocuments': created,
          'existingDocuments': existing,
          'modifiedOperationalData': 0,
        },
      );
    }

    return CommercialPreparationResult(
      createdDocuments: created,
      existingDocuments: existing,
      defaultDocuments: defaults.keys.toList(growable: false),
      errors: errors,
      modifiedOperationalData: 0,
    );
  }

  Future<void> saveBranding(CommercialBranding branding) async {
    await settingRef('branding').set({
      ...branding.toFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _logActivity(
      type: 'commercial_branding_updated',
      data: {
        'businessName': branding.businessName,
        'shortName': branding.shortName,
      },
    );
  }

  Future<void> saveOperations(OperationalPolicy operations) async {
    await settingRef('operations').set({
      ...operations.toFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _logActivity(type: 'commercial_operations_updated');
  }

  Future<void> saveBenefits(BenefitPolicies benefits) async {
    await settingRef('benefits').set({
      ...benefits.toFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _logActivity(type: 'commercial_benefits_updated');
  }

  Map<String, Map<String, Object?>> _defaultDocuments() {
    return {
      'commercial': {
        'tenantId': 'los_padrinos',
        'planId': 'signature',
        'compatibilityMode': true,
        'licensingEnforcement': false,
        'policyEngineEnabled': false,
        'commercialFeaturesEnabled': false,
        'status': 'active',
      },
      'branding': CommercialBranding.defaults().toFirestore(),
      'features': AppCapabilities.defaults().toFirestore(),
      'operations': OperationalPolicy.defaults().toFirestore(),
      'benefits': BenefitPolicies.defaults().toFirestore(),
    };
  }

  Future<void> _logActivity({
    required String type,
    Map<String, Object?> data = const {},
  }) async {
    try {
      final employee = AppSession.instance.employee;
      await _restaurantRef.collection('activityLog').add({
        'type': type,
        'restaurantId': AppConstants.restaurantId,
        'branchId': AppSession.instance.currentBranchId,
        'branchName': AppSession.instance.currentBranchName,
        'employeeId': employee?.id ?? '',
        'employeeName': employee?.name ?? '',
        'createdBy': _auth.currentUser?.uid ?? 'anonymous',
        'createdAt': FieldValue.serverTimestamp(),
        ...data,
      });
    } catch (error, stackTrace) {
      debugPrint(
        'COMMERCIAL_ACTIVITY_LOG_WARNING '
        'type=$type error=$error stackTrace=$stackTrace',
      );
    }
  }
}

class CommercialPreparationResult {
  const CommercialPreparationResult({
    required this.createdDocuments,
    required this.existingDocuments,
    required this.defaultDocuments,
    required this.errors,
    required this.modifiedOperationalData,
  });

  final List<String> createdDocuments;
  final List<String> existingDocuments;
  final List<String> defaultDocuments;
  final List<String> errors;
  final int modifiedOperationalData;

  bool get hasErrors => errors.isNotEmpty;
}

String _readString(Map<String, dynamic>? data, String key, String fallback) {
  final value = data?[key]?.toString().trim();
  return value == null || value.isEmpty ? fallback : value;
}

bool _readBool(Map<String, dynamic>? data, String key, bool fallback) {
  final value = data?[key];
  return value is bool ? value : fallback;
}
