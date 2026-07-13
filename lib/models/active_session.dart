import 'package:cloud_firestore/cloud_firestore.dart';

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

  bool get hasRecentConnection {
    final seen = lastSeenAt;
    if (seen == null) return false;
    return DateTime.now().difference(seen).inMinutes < 2;
  }

  String get connectionLabel {
    if (isOnline && hasRecentConnection) return 'En linea';
    if (hasRecentConnection) return 'Inactivo';
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
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
