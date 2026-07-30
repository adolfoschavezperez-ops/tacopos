import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/app_update/app_update_policy.dart';
import '../core/constants/app_constants.dart';

class AppVersionInfo {
  const AppVersionInfo({required this.versionName, required this.versionCode});

  final String versionName;
  final int versionCode;
}

class PlayUpdateAvailability {
  const PlayUpdateAvailability({
    required this.updateAvailable,
    required this.updateAllowed,
    required this.installedFromPlay,
    required this.installerPackageName,
    this.availableVersionCode,
    this.installStatus,
  });

  final bool updateAvailable;
  final bool updateAllowed;
  final bool installedFromPlay;
  final String installerPackageName;
  final int? availableVersionCode;
  final int? installStatus;

  bool get canStartUpdate =>
      installedFromPlay && updateAvailable && updateAllowed;
}

class AppUpdateInstallProgress {
  const AppUpdateInstallProgress({
    required this.installStatus,
    required this.bytesDownloaded,
    required this.totalBytesToDownload,
  });

  final int installStatus;
  final int bytesDownloaded;
  final int totalBytesToDownload;

  double? get progress {
    if (totalBytesToDownload <= 0) return null;
    return bytesDownloaded / totalBytesToDownload;
  }
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.decision,
    required this.currentVersionCode,
    required this.currentVersionName,
    required this.minimumSupportedVersionCode,
    required this.recommendedVersionCode,
    required this.playUpdateAvailability,
    required this.configActive,
    this.errorCode,
    this.errorMessage,
    this.releaseNotes,
    this.rolloutGroup,
    this.criticalReason,
  });

  final AppUpdateDecision decision;
  final int currentVersionCode;
  final String currentVersionName;
  final int minimumSupportedVersionCode;
  final int recommendedVersionCode;
  final PlayUpdateAvailability playUpdateAvailability;
  final bool configActive;
  final String? errorCode;
  final String? errorMessage;
  final String? releaseNotes;
  final String? rolloutGroup;
  final String? criticalReason;

  bool get installedFromPlay => playUpdateAvailability.installedFromPlay;
  bool get canStartPlayUpdate => playUpdateAvailability.canStartUpdate;
}

class AppUpdateService {
  static const MethodChannel _channel = MethodChannel('tacopos/app_update');
  static final StreamController<AppUpdateInstallProgress> _progressController =
      StreamController<AppUpdateInstallProgress>.broadcast();
  static final StreamController<void> _downloadedController =
      StreamController<void>.broadcast();
  static bool _methodHandlerConfigured = false;

  AppUpdateService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance {
    _configureMethodHandler();
  }

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Stream<AppUpdateInstallProgress> get flexibleUpdateProgress =>
      _progressController.stream;
  Stream<void> get flexibleUpdateDownloaded => _downloadedController.stream;

  bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<AppUpdateCheckResult> checkForUpdate() async {
    final currentVersion = await currentVersionInfo();
    if (!isSupportedPlatform) {
      return AppUpdateCheckResult(
        decision: const AppUpdateDecision(
          severity: AppUpdateSeverity.none,
          message: '',
          canContinue: true,
        ),
        currentVersionCode: currentVersion.versionCode,
        currentVersionName: currentVersion.versionName,
        minimumSupportedVersionCode: currentVersion.versionCode,
        recommendedVersionCode: currentVersion.versionCode,
        playUpdateAvailability: _emptyPlayAvailability(
          installedFromPlay: false,
        ),
        configActive: false,
      );
    }

    try {
      final config = await _loadRemoteUpdateConfig();
      if (config == null || config.active != true) {
        return AppUpdateCheckResult(
          decision: const AppUpdateDecision(
            severity: AppUpdateSeverity.none,
            message: '',
            canContinue: true,
          ),
          currentVersionCode: currentVersion.versionCode,
          currentVersionName: currentVersion.versionName,
          minimumSupportedVersionCode: currentVersion.versionCode,
          recommendedVersionCode: currentVersion.versionCode,
          playUpdateAvailability: await _checkPlayUpdate('flexible'),
          configActive: false,
        );
      }

      final deviceRolloutGroup = await _loadDeviceRolloutGroup();
      final decision = evaluateAppUpdatePolicy(
        AppUpdatePolicyInput(
          currentVersionCode: currentVersion.versionCode,
          minimumSupportedVersionCode: config.minimumSupportedVersionCode,
          recommendedVersionCode: config.recommendedVersionCode,
          forceUpdate: config.forceUpdate,
          updateMessage: config.updateMessage,
          active: config.active,
          rolloutGroup: deviceRolloutGroup,
          enabledRolloutGroups: config.rolloutGroups,
        ),
      );
      final playAvailability = decision.isRequired
          ? await _checkPlayUpdate('immediate')
          : decision.isRecommended
          ? await _checkPlayUpdate('flexible')
          : await _checkPlayUpdate('flexible');

      final adjustedDecision = _avoidNonPlayUpdateLoop(
        decision,
        playAvailability,
      );

      return AppUpdateCheckResult(
        decision: adjustedDecision,
        currentVersionCode: currentVersion.versionCode,
        currentVersionName: currentVersion.versionName,
        minimumSupportedVersionCode: config.minimumSupportedVersionCode,
        recommendedVersionCode: config.recommendedVersionCode,
        playUpdateAvailability: playAvailability,
        configActive: config.active,
        releaseNotes: config.releaseNotes,
        rolloutGroup: deviceRolloutGroup,
        criticalReason: config.criticalReason,
        errorCode: playAvailability.installedFromPlay
            ? null
            : 'APP_UPDATE_NOT_PLAY_INSTALLED',
        errorMessage: playAvailability.installedFromPlay
            ? null
            : 'La app no fue instalada desde Google Play.',
      );
    } catch (error) {
      debugPrint('APP_UPDATE_CHECK_FAILED: $error');
      return AppUpdateCheckResult(
        decision: const AppUpdateDecision(
          severity: AppUpdateSeverity.none,
          message: '',
          canContinue: true,
        ),
        currentVersionCode: currentVersion.versionCode,
        currentVersionName: currentVersion.versionName,
        minimumSupportedVersionCode: currentVersion.versionCode,
        recommendedVersionCode: currentVersion.versionCode,
        playUpdateAvailability: _emptyPlayAvailability(
          installedFromPlay: false,
        ),
        configActive: false,
        errorCode: 'APP_UPDATE_CONFIG_UNAVAILABLE',
        errorMessage: error.toString(),
      );
    }
  }

  Future<AppVersionInfo> currentVersionInfo() async {
    if (!isSupportedPlatform) {
      return const AppVersionInfo(versionName: 'web', versionCode: 0);
    }
    final versionCode = await _invokeInt('versionCode');
    final versionName = await _invokeString('versionName');
    return AppVersionInfo(versionName: versionName, versionCode: versionCode);
  }

  Future<void> startFlexibleUpdate() async {
    await _channel.invokeMethod<void>('startFlexibleUpdate');
  }

  Future<void> startImmediateUpdate() async {
    await _channel.invokeMethod<void>('startImmediateUpdate');
  }

  Future<void> completeFlexibleUpdate() async {
    await _channel.invokeMethod<void>('completeFlexibleUpdate');
  }

  Future<PlayUpdateAvailability> _checkPlayUpdate(String mode) async {
    if (!isSupportedPlatform) {
      return _emptyPlayAvailability(installedFromPlay: false);
    }
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'checkUpdate',
        {'mode': mode},
      );
      final data = value ?? const <String, Object?>{};
      return PlayUpdateAvailability(
        updateAvailable: data['updateAvailable'] == true,
        updateAllowed: data['updateAllowed'] == true,
        installedFromPlay: data['installedFromPlay'] == true,
        installerPackageName: data['installerPackageName']?.toString() ?? '',
        availableVersionCode: _readIntOrNull(data['availableVersionCode']),
        installStatus: _readIntOrNull(data['installStatus']),
      );
    } on PlatformException catch (error) {
      debugPrint(
        'APP_UPDATE_PLAY_CHECK_FAILED: ${error.code} ${error.message}',
      );
      return const PlayUpdateAvailability(
        updateAvailable: false,
        updateAllowed: false,
        installedFromPlay: false,
        installerPackageName: '',
      );
    }
  }

  Future<_RemoteUpdateConfig?> _loadRemoteUpdateConfig() async {
    final snapshot = await _firestore
        .collection('restaurants')
        .doc(AppConstants.restaurantId)
        .collection('settings')
        .doc('appUpdates')
        .get()
        .timeout(const Duration(seconds: 8));
    final data = snapshot.data();
    if (data == null) return null;
    return _RemoteUpdateConfig.fromMap(data);
  }

  Future<String?> _loadDeviceRolloutGroup() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    final snapshot = await _firestore
        .collection('restaurants')
        .doc(AppConstants.restaurantId)
        .collection('devices')
        .doc(uid)
        .get()
        .timeout(const Duration(seconds: 5));
    return snapshot.data()?['rolloutGroup']?.toString();
  }

  AppUpdateDecision _avoidNonPlayUpdateLoop(
    AppUpdateDecision decision,
    PlayUpdateAvailability availability,
  ) {
    if (availability.installedFromPlay ||
        decision.severity == AppUpdateSeverity.none) {
      return decision;
    }
    if (decision.isRequired) {
      return AppUpdateDecision(
        severity: AppUpdateSeverity.required,
        message:
            '${decision.message}\n\nAPP_UPDATE_NOT_PLAY_INSTALLED: instala TacoPOS desde el enlace privado de Prueba interna de Google Play.',
        canContinue: false,
      );
    }
    return AppUpdateDecision(
      severity: AppUpdateSeverity.recommended,
      message:
          '${decision.message}\n\nAPP_UPDATE_NOT_PLAY_INSTALLED: esta tablet debe migrarse a la version instalada desde Google Play.',
      canContinue: true,
    );
  }

  PlayUpdateAvailability _emptyPlayAvailability({
    required bool installedFromPlay,
  }) {
    return PlayUpdateAvailability(
      updateAvailable: false,
      updateAllowed: false,
      installedFromPlay: installedFromPlay,
      installerPackageName: '',
    );
  }

  Future<int> _invokeInt(String method) async {
    try {
      final value = await _channel.invokeMethod<Object?>(method);
      return _readInt(value, fallback: 0);
    } catch (_) {
      return 0;
    }
  }

  Future<String> _invokeString(String method) async {
    try {
      return (await _channel.invokeMethod<String>(method)) ?? '';
    } catch (_) {
      return '';
    }
  }

  int _readInt(Object? value, {required int fallback}) {
    return _readIntOrNull(value) ?? fallback;
  }

  int? _readIntOrNull(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  void _configureMethodHandler() {
    if (_methodHandlerConfigured) return;
    _methodHandlerConfigured = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'flexibleUpdateDownloaded') {
        _downloadedController.add(null);
        return;
      }
      if (call.method == 'flexibleUpdateStatus') {
        final args = call.arguments;
        if (args is Map) {
          _progressController.add(
            AppUpdateInstallProgress(
              installStatus: _readInt(args['installStatus'], fallback: 0),
              bytesDownloaded: _readInt(args['bytesDownloaded'], fallback: 0),
              totalBytesToDownload: _readInt(
                args['totalBytesToDownload'],
                fallback: 0,
              ),
            ),
          );
        }
      }
    });
  }
}

class _RemoteUpdateConfig {
  const _RemoteUpdateConfig({
    required this.minimumSupportedVersionCode,
    required this.recommendedVersionCode,
    required this.forceUpdate,
    required this.updateMessage,
    required this.active,
    required this.rolloutGroups,
    this.releaseNotes,
    this.criticalReason,
  });

  final int minimumSupportedVersionCode;
  final int recommendedVersionCode;
  final bool forceUpdate;
  final String updateMessage;
  final bool active;
  final List<String> rolloutGroups;
  final String? releaseNotes;
  final String? criticalReason;

  factory _RemoteUpdateConfig.fromMap(Map<String, dynamic> data) {
    final groups = data['rolloutGroups'];
    return _RemoteUpdateConfig(
      minimumSupportedVersionCode: _readInt(
        data['minimumSupportedVersionCode'],
        fallback: 1,
      ),
      recommendedVersionCode: _readInt(
        data['recommendedVersionCode'],
        fallback: 1,
      ),
      forceUpdate: data['forceUpdate'] == true,
      updateMessage:
          data['updateMessage']?.toString() ??
          'Hay una nueva version de TacoPOS disponible.',
      active: data['active'] != false,
      rolloutGroups: groups is Iterable
          ? groups.map((group) => group.toString()).toList()
          : const [],
      releaseNotes: data['releaseNotes']?.toString(),
      criticalReason: data['criticalReason']?.toString(),
    );
  }

  static int _readInt(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
