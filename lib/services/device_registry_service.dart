import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/app_update/app_update_policy.dart';
import '../core/constants/app_constants.dart';
import 'app_session.dart';
import 'app_update_service.dart';

class RegisteredDevice {
  const RegisteredDevice({
    required this.deviceId,
    required this.deviceName,
    required this.branchId,
    required this.branchName,
    required this.role,
    required this.platform,
    required this.appVersionName,
    required this.appVersionCode,
    required this.recommendedVersionCode,
    required this.availableVersionCode,
    required this.employeeId,
    required this.employeeName,
    required this.updateStatus,
    required this.rolloutGroup,
    this.lastSeenAt,
    this.updatedAt,
  });

  final String deviceId;
  final String deviceName;
  final String branchId;
  final String branchName;
  final String role;
  final String platform;
  final String appVersionName;
  final int appVersionCode;
  final int recommendedVersionCode;
  final int availableVersionCode;
  final String employeeId;
  final String employeeName;
  final DeviceUpdateStatus updateStatus;
  final String rolloutGroup;
  final DateTime? lastSeenAt;
  final DateTime? updatedAt;

  factory RegisteredDevice.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return RegisteredDevice(
      deviceId: data['deviceId']?.toString() ?? doc.id,
      deviceName: data['deviceName']?.toString() ?? 'Sin nombre',
      branchId: data['branchId']?.toString() ?? '',
      branchName: data['branchName']?.toString() ?? '',
      role: data['role']?.toString() ?? '',
      platform: data['platform']?.toString() ?? '',
      appVersionName: data['appVersionName']?.toString() ?? '',
      appVersionCode: _readInt(data['appVersionCode']),
      recommendedVersionCode: _readInt(data['recommendedVersionCode']),
      availableVersionCode: _readInt(data['availableVersionCode']),
      employeeId: data['employeeId']?.toString() ?? '',
      employeeName: data['employeeName']?.toString() ?? '',
      updateStatus: parseDeviceUpdateStatus(data['updateStatus']?.toString()),
      rolloutGroup: data['rolloutGroup']?.toString() ?? '',
      lastSeenAt: _readDate(data['lastSeenAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}

class DeviceRegistryException implements Exception {
  const DeviceRegistryException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'DeviceRegistryException($code): $message';
}

class DeviceRegistryService {
  DeviceRegistryService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    AppUpdateService? updateService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _updateService = updateService ?? AppUpdateService();

  static final instance = DeviceRegistryService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final AppUpdateService _updateService;
  DateTime? _lastHeartbeatAt;
  String? _lastStatusName;

  CollectionReference<Map<String, dynamic>> get _devicesRef => _firestore
      .collection('restaurants')
      .doc(AppConstants.restaurantId)
      .collection('devices');

  static String documentPathForDevice(String deviceId) {
    return 'restaurants/${AppConstants.restaurantId}/devices/$deviceId';
  }

  static bool isValidDeviceId(String? deviceId) {
    final value = deviceId?.trim();
    return value != null && value.isNotEmpty && !value.contains('/');
  }

  Stream<List<RegisteredDevice>> watchDevices() {
    return _devicesRef.snapshots().map((snapshot) {
      final devices = snapshot.docs.map(RegisteredDevice.fromDoc).toList();
      devices.sort((a, b) {
        final statusCompare = _statusRank(
          a.updateStatus,
        ).compareTo(_statusRank(b.updateStatus));
        if (statusCompare != 0) return statusCompare;
        return a.deviceName.compareTo(b.deviceName);
      });
      return devices;
    });
  }

  Future<void> recordHeartbeat({
    AppUpdateCheckResult? updateResult,
    bool force = false,
  }) async {
    final uid = _auth.currentUser?.uid.trim();
    if (!DeviceRegistryService.isValidDeviceId(uid)) {
      _logDiagnostic(
        deviceId: uid ?? '',
        documentPath: uid == null ? '' : documentPathForDevice(uid),
        exceptionType: 'InvalidDeviceId',
        firebaseCode: 'invalid-argument',
        firebaseMessage: 'deviceId is null, empty, or contains slash.',
        stackTrace: StackTrace.current,
        attemptedFields: const [],
      );
      return;
    }
    final deviceId = uid!;

    final status = _statusFromUpdateResult(updateResult);
    final statusName = deviceUpdateStatusName(status);
    final now = DateTime.now();
    if (!force &&
        _lastHeartbeatAt != null &&
        now.difference(_lastHeartbeatAt!) < const Duration(minutes: 30) &&
        _lastStatusName == statusName) {
      return;
    }

    try {
      final version = await _updateService.currentVersionInfo();
      final doc = _devicesRef.doc(deviceId);
      final session = AppSession.instance;
      final employee = session.employee;
      final data = <String, Object?>{
        'deviceId': deviceId,
        'deviceName': _defaultDeviceName(),
        'branchId': session.currentBranchId,
        'branchName': session.currentBranchName,
        'role': _inferRole(),
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'appVersionName': version.versionName,
        'appVersionCode': version.versionCode,
        'availableVersionCode':
            updateResult?.playUpdateAvailability.availableVersionCode ?? 0,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'lastUpdateCheckAt': FieldValue.serverTimestamp(),
        'employeeId': employee?.id ?? '',
        'employeeName': employee?.name ?? '',
        'updateStatus': statusName,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await doc.set(data, SetOptions(merge: true));
      _lastHeartbeatAt = now;
      _lastStatusName = statusName;
    } on FirebaseException catch (error, stackTrace) {
      _logDiagnostic(
        deviceId: deviceId,
        documentPath: documentPathForDevice(deviceId),
        exceptionType: error.runtimeType.toString(),
        firebaseCode: error.code,
        firebaseMessage: error.message ?? '',
        stackTrace: stackTrace,
        attemptedFields: _attemptedFields(),
      );
    } catch (error) {
      _logDiagnostic(
        deviceId: deviceId,
        documentPath: documentPathForDevice(deviceId),
        exceptionType: error.runtimeType.toString(),
        firebaseCode: 'unknown',
        firebaseMessage: error.toString(),
        stackTrace: StackTrace.current,
        attemptedFields: _attemptedFields(),
      );
    }
  }

  Future<void> ensureCurrentDeviceReady({bool recordHeartbeat = true}) async {
    final uid = _auth.currentUser?.uid.trim();
    if (!DeviceRegistryService.isValidDeviceId(uid)) {
      throw const DeviceRegistryException(
        'invalid-device-id',
        'Este dispositivo no esta registrado o activo.',
      );
    }

    final deviceId = uid!;
    final doc = await _devicesRef.doc(deviceId).get();
    if (!doc.exists) {
      throw const DeviceRegistryException(
        'device-not-registered',
        'Este dispositivo no esta registrado o activo.',
      );
    }

    final data = doc.data() ?? const <String, dynamic>{};
    if (data['active'] == false) {
      throw const DeviceRegistryException(
        'device-inactive',
        'Este dispositivo no esta registrado o activo.',
      );
    }

    final restaurantId = data['restaurantId']?.toString().trim() ?? '';
    if (restaurantId.isNotEmpty && restaurantId != AppConstants.restaurantId) {
      throw const DeviceRegistryException(
        'device-restaurant-mismatch',
        'Este dispositivo no esta registrado o activo.',
      );
    }

    final branchId = data['branchId']?.toString().trim() ?? '';
    final currentBranchId = AppSession.instance.currentBranchId.trim();
    if (branchId.isNotEmpty &&
        currentBranchId.isNotEmpty &&
        branchId != currentBranchId) {
      throw const DeviceRegistryException(
        'device-branch-mismatch',
        'Este dispositivo no esta registrado o activo.',
      );
    }

    if (recordHeartbeat) {
      await this.recordHeartbeat(force: true);
    }
  }

  DeviceUpdateStatus _statusFromUpdateResult(AppUpdateCheckResult? result) {
    if (result == null || result.errorCode != null) {
      if (result?.errorCode == 'APP_UPDATE_REQUIRED_NOT_AVAILABLE') {
        return DeviceUpdateStatus.playUpdateUnavailable;
      }
      return DeviceUpdateStatus.unknown;
    }
    return result.decision.deviceStatus;
  }

  String _inferRole() {
    if (kIsWeb) return 'Administracion';
    final employee = AppSession.instance.employee;
    if (employee == null) return 'unknown';
    if (employee.hasAdminAccess || employee.canViewAdmin) {
      return 'Administracion';
    }
    if (employee.canManageCash || employee.canCharge) return 'Caja';
    if (employee.canViewKitchen ||
        employee.canOpenKitchen ||
        employee.canCloseKitchen) {
      return 'Cocina';
    }
    if (employee.canTakeOrders) return 'Mesero';
    return 'Respaldo';
  }

  String _defaultDeviceName() {
    final role = _inferRole();
    return switch (role) {
      'Caja' => 'Caja',
      'Cocina' => 'Cocina 1',
      'Mesero' => 'Mesero 1',
      'Administracion' => 'Administracion',
      _ => 'Respaldo',
    };
  }

  int _statusRank(DeviceUpdateStatus status) {
    return switch (status) {
      DeviceUpdateStatus.updateRequired => 0,
      DeviceUpdateStatus.playUpdateUnavailable => 1,
      DeviceUpdateStatus.updateRecommended => 2,
      DeviceUpdateStatus.unknown => 3,
      DeviceUpdateStatus.upToDate => 4,
    };
  }

  List<String> _attemptedFields() {
    return const [
      'deviceId',
      'deviceName',
      'branchId',
      'branchName',
      'role',
      'platform',
      'appVersionName',
      'appVersionCode',
      'lastSeenAt',
      'employeeId',
      'employeeName',
      'updateStatus',
      'lastUpdateCheckAt',
      'availableVersionCode',
      'updatedAt',
    ];
  }

  void _logDiagnostic({
    required String deviceId,
    required String documentPath,
    required String firebaseCode,
    required String firebaseMessage,
    required String exceptionType,
    required StackTrace stackTrace,
    required List<String> attemptedFields,
  }) {
    debugPrint(
      'DEVICE_REGISTRATION_DIAGNOSTIC '
      'restaurantId=${AppConstants.restaurantId} '
      'deviceId=$deviceId '
      'documentPath=$documentPath '
      'firebaseCode=$firebaseCode '
      'firebaseMessage=$firebaseMessage '
      'exceptionType=$exceptionType '
      'attemptedFields=${attemptedFields.join(',')} '
      'stackTrace=$stackTrace',
    );
  }
}
