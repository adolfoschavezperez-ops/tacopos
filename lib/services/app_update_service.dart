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
    required this.flexibleAllowed,
    required this.immediateAllowed,
    required this.installedFromPlay,
    required this.installerPackageName,
    this.updateAvailability,
    this.availableVersionCode,
    this.installStatus,
    this.errorCode,
    this.errorMessage,
  });

  final bool updateAvailable;
  final bool flexibleAllowed;
  final bool immediateAllowed;
  final bool installedFromPlay;
  final String installerPackageName;
  final int? updateAvailability;
  final int? availableVersionCode;
  final int? installStatus;
  final String? errorCode;
  final String? errorMessage;

  bool get canStartFlexibleUpdate =>
      installedFromPlay && updateAvailable && flexibleAllowed;

  bool get canStartImmediateUpdate =>
      installedFromPlay && updateAvailable && immediateAllowed;
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
  bool get canStartFlexibleUpdate =>
      playUpdateAvailability.canStartFlexibleUpdate;
  bool get canStartImmediateUpdate =>
      playUpdateAvailability.canStartImmediateUpdate;
  bool get requiredButPlayUnavailable =>
      decision.isRequired && !canStartImmediateUpdate;

  AppUpdateCheckResult copyWith({
    AppUpdateDecision? decision,
    PlayUpdateAvailability? playUpdateAvailability,
    String? errorCode,
    String? errorMessage,
  }) {
    return AppUpdateCheckResult(
      decision: decision ?? this.decision,
      currentVersionCode: currentVersionCode,
      currentVersionName: currentVersionName,
      minimumSupportedVersionCode: minimumSupportedVersionCode,
      recommendedVersionCode: recommendedVersionCode,
      playUpdateAvailability:
          playUpdateAvailability ?? this.playUpdateAvailability,
      configActive: configActive,
      errorCode: errorCode ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      releaseNotes: releaseNotes,
      rolloutGroup: rolloutGroup,
      criticalReason: criticalReason,
    );
  }
}

class AppUpdateService {
  static const MethodChannel _channel = MethodChannel('tacopos/app_update');
  static final StreamController<AppUpdateInstallProgress> _progressController =
      StreamController<AppUpdateInstallProgress>.broadcast();
  static final StreamController<void> _downloadedController =
      StreamController<void>.broadcast();
  static final StreamController<void> _immediateInProgressController =
      StreamController<void>.broadcast();
  static bool _methodHandlerConfigured = false;
  static AppUpdateCheckResult? _lastValidPolicyResult;

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
  Stream<void> get immediateUpdateInProgress =>
      _immediateInProgressController.stream;

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
        playUpdateAvailability: _emptyPlayAvailability(),
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
          playUpdateAvailability: await _checkPlayUpdate(),
          configActive: false,
        );
      }

      final deviceRolloutGroup = config.rolloutGroups.isEmpty
          ? null
          : await _loadDeviceRolloutGroup();
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
      final playAvailability = await _checkPlayUpdate();

      final adjustedDecision = _avoidNonPlayUpdateLoop(
        decision,
        playAvailability,
      );

      final result = AppUpdateCheckResult(
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
        errorCode: _diagnosticCode(adjustedDecision, playAvailability),
        errorMessage: _diagnosticMessage(adjustedDecision, playAvailability),
      );
      if (result.errorCode == 'APP_UPDATE_REQUIRED_NOT_AVAILABLE') {
        debugPrint(
          'APP_UPDATE_REQUIRED_NOT_AVAILABLE '
          'currentVersionCode=${result.currentVersionCode} '
          'minimumSupportedVersionCode=${result.minimumSupportedVersionCode} '
          'recommendedVersionCode=${result.recommendedVersionCode} '
          'availableVersionCode=${playAvailability.availableVersionCode} '
          'updateAvailability=${playAvailability.updateAvailability} '
          'immediateAllowed=${playAvailability.immediateAllowed}',
        );
      }
      _lastValidPolicyResult = result;
      return result;
    } catch (error) {
      debugPrint('APP_UPDATE_CHECK_FAILED: $error');
      final cached = _lastValidPolicyResult;
      if (cached != null) {
        return cached.copyWith(
          errorCode: 'APP_UPDATE_CONFIG_UNAVAILABLE',
          errorMessage: error.toString(),
        );
      }
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
        playUpdateAvailability: _emptyPlayAvailability(),
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

  Future<void> openGooglePlay() async {
    await _channel.invokeMethod<void>('openGooglePlay');
  }

  Future<PlayUpdateAvailability> _checkPlayUpdate() async {
    if (!isSupportedPlatform) {
      return _emptyPlayAvailability();
    }
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'checkUpdate',
      );
      final data = value ?? const <String, Object?>{};
      return PlayUpdateAvailability(
        updateAvailability: _readIntOrNull(data['updateAvailability']),
        updateAvailable: data['updateAvailable'] == true,
        flexibleAllowed: data['flexibleAllowed'] == true,
        immediateAllowed: data['immediateAllowed'] == true,
        installedFromPlay: data['installedFromPlay'] == true,
        installerPackageName: data['installerPackageName']?.toString() ?? '',
        availableVersionCode: _readIntOrNull(data['availableVersionCode']),
        installStatus: _readIntOrNull(data['installStatus']),
      );
    } on PlatformException catch (error) {
      debugPrint(
        'APP_UPDATE_PLAY_CHECK_FAILED: ${error.code} ${error.message}',
      );
      return _emptyPlayAvailability(
        errorCode: error.code,
        errorMessage: error.message,
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
    try {
      final snapshot = await _firestore
          .collection('restaurants')
          .doc(AppConstants.restaurantId)
          .collection('devices')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 5));
      return snapshot.data()?['rolloutGroup']?.toString();
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        'DEVICE_ROLLOUT_DIAGNOSTIC '
        'restaurantId=${AppConstants.restaurantId} '
        'deviceId=$uid '
        'documentPath=restaurants/${AppConstants.restaurantId}/devices/$uid '
        'firebaseCode=${error.code} '
        'firebaseMessage=${error.message} '
        'exceptionType=${error.runtimeType} '
        'stackTrace=$stackTrace',
      );
      return null;
    } catch (error, stackTrace) {
      debugPrint(
        'DEVICE_ROLLOUT_DIAGNOSTIC '
        'restaurantId=${AppConstants.restaurantId} '
        'deviceId=$uid '
        'documentPath=restaurants/${AppConstants.restaurantId}/devices/$uid '
        'exceptionType=${error.runtimeType} '
        'firebaseCode=unknown '
        'firebaseMessage=$error '
        'stackTrace=$stackTrace',
      );
      return null;
    }
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

  String? _diagnosticCode(
    AppUpdateDecision decision,
    PlayUpdateAvailability availability,
  ) {
    if (availability.errorCode != null) return availability.errorCode;
    if (!availability.installedFromPlay &&
        decision.severity != AppUpdateSeverity.none) {
      return 'APP_UPDATE_NOT_PLAY_INSTALLED';
    }
    if (decision.isRequired && !availability.canStartImmediateUpdate) {
      return 'APP_UPDATE_REQUIRED_NOT_AVAILABLE';
    }
    return null;
  }

  String? _diagnosticMessage(
    AppUpdateDecision decision,
    PlayUpdateAvailability availability,
  ) {
    return switch (_diagnosticCode(decision, availability)) {
      'APP_UPDATE_NOT_PLAY_INSTALLED' =>
        'La app no fue instalada desde Google Play.',
      'APP_UPDATE_REQUIRED_NOT_AVAILABLE' =>
        'Google Play todavia no muestra la actualizacion para este dispositivo.',
      final code when code != null => availability.errorMessage,
      _ => null,
    };
  }

  PlayUpdateAvailability _emptyPlayAvailability({
    bool installedFromPlay = false,
    String? errorCode,
    String? errorMessage,
  }) {
    return PlayUpdateAvailability(
      updateAvailable: false,
      flexibleAllowed: false,
      immediateAllowed: false,
      installedFromPlay: installedFromPlay,
      installerPackageName: '',
      errorCode: errorCode,
      errorMessage: errorMessage,
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
      if (call.method == 'immediateUpdateInProgress') {
        _immediateInProgressController.add(null);
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
