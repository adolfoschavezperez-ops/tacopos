import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';

class ActiveSession {
  const ActiveSession({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.deviceId,
    required this.platform,
    required this.appMode,
    required this.currentScreen,
    required this.currentAction,
    required this.isOnline,
    this.currentTableId,
    this.currentTableName,
    this.currentOrderId,
    this.currentTakeoutOrderId,
    this.currentKitchenBundleId,
    this.currentPersonNumber,
    this.lastSeenAt,
    this.createdAt,
    this.updatedAt,
    this.archived = false,
    this.archivedAt,
    this.sessionType,
    this.restaurantId = AppConstants.restaurantId,
    this.restaurantName = AppConstants.restaurantName,
    this.branchId = AppConstants.defaultBranchId,
    this.branchName = AppConstants.defaultBranchName,
  });

  final String id;
  final String employeeId;
  final String employeeName;
  final String deviceId;
  final String platform;
  final String appMode;
  final String currentScreen;
  final String currentAction;
  final bool isOnline;
  final String? currentTableId;
  final String? currentTableName;
  final String? currentOrderId;
  final String? currentTakeoutOrderId;
  final String? currentKitchenBundleId;
  final int? currentPersonNumber;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool archived;
  final DateTime? archivedAt;
  final String? sessionType;
  final String restaurantId;
  final String restaurantName;
  final String branchId;
  final String branchName;

  bool get hasRecentConnection {
    final seen = lastSeenAt;
    if (seen == null) return false;
    return DateTime.now().difference(seen).inSeconds <= 180;
  }

  bool get isVisibleInLiveViewer {
    return !isBackofficeSession && !archived && isOnline && hasRecentConnection;
  }

  bool get isBackofficeSession {
    return platform.toLowerCase().trim() == 'web' ||
        appMode.toLowerCase().trim() == 'admin' ||
        currentScreen.toLowerCase().trim() == 'backoffice' ||
        currentAction.toLowerCase().trim() == 'viendo backoffice' ||
        (sessionType ?? '').toLowerCase().trim() == 'backoffice';
  }

  String get connectionLabel {
    final seen = lastSeenAt;
    if (isOnline && seen != null) {
      final ageSeconds = DateTime.now().difference(seen).inSeconds;
      if (ageSeconds <= 90) return 'En linea';
      if (ageSeconds <= 180) return 'Inactivo';
    }
    return 'Sin conexion reciente';
  }

  factory ActiveSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ActiveSession(
      id: doc.id,
      employeeId: data['employeeId'] as String? ?? '',
      employeeName: data['employeeName'] as String? ?? 'Empleado',
      deviceId: data['deviceId'] as String? ?? '',
      platform: data['platform'] as String? ?? '-',
      appMode: data['appMode'] as String? ?? '-',
      currentScreen: data['currentScreen'] as String? ?? '-',
      currentAction: data['currentAction'] as String? ?? '-',
      isOnline: data['isOnline'] as bool? ?? false,
      currentTableId: data['currentTableId'] as String?,
      currentTableName: data['currentTableName'] as String?,
      currentOrderId: data['currentOrderId'] as String?,
      currentTakeoutOrderId: data['currentTakeoutOrderId'] as String?,
      currentKitchenBundleId: data['currentKitchenBundleId'] as String?,
      currentPersonNumber: (data['currentPersonNumber'] as num?)?.toInt(),
      lastSeenAt: _toDate(data['lastSeenAt']),
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
      archived: data['archived'] as bool? ?? false,
      archivedAt: _toDate(data['archivedAt']),
      sessionType: data['sessionType'] as String?,
      restaurantId:
          data['restaurantId'] as String? ?? AppConstants.restaurantId,
      restaurantName:
          data['restaurantName'] as String? ?? AppConstants.restaurantName,
      branchId: data['branchId'] as String? ?? AppConstants.defaultBranchId,
      branchName:
          data['branchName'] as String? ?? AppConstants.defaultBranchName,
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
