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
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

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
      final doc = _devicesRef.doc(uid);
      final existing = await doc.get().timeout(const Duration(seconds: 5));
      final session = AppSession.instance;
      final employee = session.employee;
      final data = <String, Object?>{
        'deviceId': uid,
        'branchId': session.currentBranchId,
        'branchName': session.currentBranchName,
        'role': _inferRole(),
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'appVersionName': version.versionName,
        'appVersionCode': version.versionCode,
        'recommendedVersionCode': updateResult?.recommendedVersionCode ?? 0,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'employeeId': employee?.id ?? '',
        'employeeName': employee?.name ?? '',
        'updateStatus': statusName,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!existing.exists) {
        data['deviceName'] = _defaultDeviceName();
        data['rolloutGroup'] = 'pilot';
      }
      await doc.set(data, SetOptions(merge: true));
      _lastHeartbeatAt = now;
      _lastStatusName = statusName;
    } catch (error) {
      debugPrint('DEVICE_REGISTRY_WRITE_FAILED: $error');
    }
  }

  DeviceUpdateStatus _statusFromUpdateResult(AppUpdateCheckResult? result) {
    if (result == null || result.errorCode != null) {
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
      DeviceUpdateStatus.updateRecommended => 1,
      DeviceUpdateStatus.unknown => 2,
      DeviceUpdateStatus.upToDate => 3,
    };
  }
}
