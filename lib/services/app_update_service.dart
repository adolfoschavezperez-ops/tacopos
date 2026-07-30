import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/app_update/app_update_policy.dart';
import '../core/constants/app_constants.dart';

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.decision,
    required this.currentVersionCode,
    required this.minimumSupportedVersionCode,
    required this.recommendedVersionCode,
    required this.playUpdateAvailable,
    this.errorMessage,
  });

  final AppUpdateDecision decision;
  final int currentVersionCode;
  final int minimumSupportedVersionCode;
  final int recommendedVersionCode;
  final bool playUpdateAvailable;
  final String? errorMessage;
}

class AppUpdateService {
  static const MethodChannel _channel = MethodChannel('tacopos/app_update');

  AppUpdateService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<AppUpdateCheckResult> checkForUpdate() async {
    if (!isSupportedPlatform) {
      return const AppUpdateCheckResult(
        decision: AppUpdateDecision(
          severity: AppUpdateSeverity.none,
          message: '',
          canContinue: true,
        ),
        currentVersionCode: 0,
        minimumSupportedVersionCode: 0,
        recommendedVersionCode: 0,
        playUpdateAvailable: false,
      );
    }

    final currentVersionCode = await _currentVersionCode();

    try {
      final snapshot = await _firestore
          .collection('restaurants')
          .doc(AppConstants.restaurantId)
          .collection('settings')
          .doc('appUpdates')
          .get()
          .timeout(const Duration(seconds: 8));
      final data = snapshot.data() ?? const <String, dynamic>{};
      final minimumSupportedVersionCode = _readInt(
        data['minimumSupportedVersionCode'],
        fallback: 1,
      );
      final recommendedVersionCode = _readInt(
        data['recommendedVersionCode'],
        fallback: 1,
      );
      final decision = evaluateAppUpdatePolicy(
        AppUpdatePolicyInput(
          currentVersionCode: currentVersionCode,
          minimumSupportedVersionCode: minimumSupportedVersionCode,
          recommendedVersionCode: recommendedVersionCode,
          forceUpdate: data['forceUpdate'] == true,
          updateMessage:
              data['updateMessage']?.toString() ??
              'Hay una nueva version de TacoPOS disponible.',
        ),
      );

      var playUpdateAvailable = false;
      if (decision.severity != AppUpdateSeverity.none) {
        playUpdateAvailable = await _isPlayUpdateAvailable();
      }

      return AppUpdateCheckResult(
        decision: decision,
        currentVersionCode: currentVersionCode,
        minimumSupportedVersionCode: minimumSupportedVersionCode,
        recommendedVersionCode: recommendedVersionCode,
        playUpdateAvailable: playUpdateAvailable,
      );
    } catch (error) {
      return AppUpdateCheckResult(
        decision: const AppUpdateDecision(
          severity: AppUpdateSeverity.none,
          message: '',
          canContinue: true,
        ),
        currentVersionCode: currentVersionCode,
        minimumSupportedVersionCode: currentVersionCode,
        recommendedVersionCode: currentVersionCode,
        playUpdateAvailable: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> startFlexibleUpdate() async {
    await _channel.invokeMethod<void>('openPlayStore');
  }

  Future<void> startImmediateUpdate() async {
    await _channel.invokeMethod<void>('openPlayStore');
  }

  Future<bool> _isPlayUpdateAvailable() async {
    try {
      final available = await _channel.invokeMethod<bool>('canOpenPlayStore');
      return available ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<int> _currentVersionCode() async {
    try {
      final value = await _channel.invokeMethod<int>('versionCode');
      return value ?? 0;
    } catch (_) {
      return 0;
    }
  }

  int _readInt(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
