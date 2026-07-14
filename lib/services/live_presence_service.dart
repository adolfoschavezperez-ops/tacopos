import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../models/employee.dart';

class LivePresenceService {
  LivePresenceService._();

  static final LivePresenceService instance = LivePresenceService._();

  final _db = FirebaseFirestore.instance;
  Timer? _heartbeatTimer;
  Employee? _employee;
  String? _sessionId;
  String? _deviceId;
  Map<String, Object?> _lastState = const {};
  DateTime? _lastWriteAt;
  bool _createdCurrentSession = false;

  CollectionReference<Map<String, dynamic>> get _sessionsRef => _db
      .collection('restaurants')
      .doc(AppConstants.restaurantId)
      .collection('activeSessions');

  void start(Employee employee) {
    _employee = employee;
    _deviceId ??= _buildDeviceId();
    _sessionId = '${employee.id}_${_platformKey()}';
    _heartbeatTimer?.cancel();
    update(
      appMode: 'app',
      currentScreen: 'Inicio',
      currentAction: 'Sesion iniciada',
      force: true,
    );
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      update(force: true);
    });
  }

  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final sessionId = _sessionId;
    if (sessionId == null) {
      _employee = null;
      return;
    }
    await _sessionsRef.doc(sessionId).set({
      'isOnline': false,
      'currentOrderId': null,
      'currentTableId': null,
      'currentTableName': null,
      'currentTakeoutOrderId': null,
      'currentKitchenBundleId': null,
      'currentPersonNumber': null,
      'currentAction': 'Sesion cerrada',
      'lastSeenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _employee = null;
    _sessionId = null;
    _lastState = const {};
    _lastWriteAt = null;
    _createdCurrentSession = false;
  }

  Future<void> clearCurrentOrder({
    String currentScreen = 'Mesas',
    String currentAction = 'Orden finalizada',
    bool force = true,
  }) {
    return update(
      currentScreen: currentScreen,
      currentAction: currentAction,
      force: force,
    );
  }

  Future<void> updateCurrentScreen({
    String? appMode,
    required String currentScreen,
    required String currentAction,
    String? currentTableId,
    String? currentTableName,
    String? currentOrderId,
    String? currentTakeoutOrderId,
    String? currentKitchenBundleId,
    int? currentPersonNumber,
    bool force = false,
  }) {
    return update(
      appMode: appMode,
      currentScreen: currentScreen,
      currentAction: currentAction,
      currentTableId: currentTableId,
      currentTableName: currentTableName,
      currentOrderId: currentOrderId,
      currentTakeoutOrderId: currentTakeoutOrderId,
      currentKitchenBundleId: currentKitchenBundleId,
      currentPersonNumber: currentPersonNumber,
      force: force,
    );
  }

  Future<void> markOffline() => stop();

  Future<void> heartbeat() => update(force: true);

  Future<int> cleanupInactiveSessions() async {
    final snapshot = await _sessionsRef.limit(200).get();
    final cutoff = DateTime.now().subtract(const Duration(seconds: 180));
    final latestByEmployee =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    DateTime? seenAt(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      final data = doc.data();
      final value = data['lastSeenAt'] ?? data['updatedAt'];
      return value is Timestamp ? value.toDate() : null;
    }

    String groupKey(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      final data = doc.data();
      final employeeId = (data['employeeId'] as String? ?? '').trim();
      if (employeeId.isNotEmpty) return employeeId;
      final deviceId = (data['deviceId'] as String? ?? '').trim();
      if (deviceId.isNotEmpty) return deviceId;
      return doc.id;
    }

    for (final doc in snapshot.docs) {
      final key = groupKey(doc);
      final current = latestByEmployee[key];
      if (current == null) {
        latestByEmployee[key] = doc;
        continue;
      }
      final currentSeen = seenAt(current) ?? DateTime(1970);
      final nextSeen = seenAt(doc) ?? DateTime(1970);
      if (nextSeen.isAfter(currentSeen)) {
        latestByEmployee[key] = doc;
      }
    }

    final batch = _db.batch();
    var count = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final seen = seenAt(doc);
      final isDuplicate = latestByEmployee[groupKey(doc)]?.id != doc.id;
      final isOld = seen == null || seen.isBefore(cutoff);
      final isOnline = data['isOnline'] as bool? ?? false;
      final archived = data['archived'] as bool? ?? false;
      if (archived || (!isDuplicate && isOnline && !isOld)) {
        continue;
      }
      batch.set(doc.reference, {
        'archived': true,
        'isOnline': false,
        'currentOrderId': null,
        'currentTableId': null,
        'currentTableName': null,
        'currentTakeoutOrderId': null,
        'currentKitchenBundleId': null,
        'currentPersonNumber': null,
        'archivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      count++;
    }
    if (count > 0) {
      await batch.commit();
    }
    return count;
  }

  Future<void> update({
    String? appMode,
    String? currentScreen,
    String? currentAction,
    String? currentTableId,
    String? currentTableName,
    String? currentOrderId,
    String? currentTakeoutOrderId,
    String? currentKitchenBundleId,
    int? currentPersonNumber,
    bool force = false,
  }) async {
    final employee = _employee;
    final sessionId = _sessionId;
    final deviceId = _deviceId;
    if (employee == null || sessionId == null || deviceId == null) {
      return;
    }

    final nextState = Map<String, Object?>.from(_lastState);
    if (appMode != null || currentScreen != null) {
      nextState.remove('currentTableId');
      nextState.remove('currentTableName');
      nextState.remove('currentOrderId');
      nextState.remove('currentTakeoutOrderId');
      nextState.remove('currentKitchenBundleId');
      nextState.remove('currentPersonNumber');
    }
    void setIfPresent(String key, Object? value) {
      if (value != null) {
        nextState[key] = value;
      }
    }

    setIfPresent('appMode', appMode);
    setIfPresent('currentScreen', currentScreen);
    setIfPresent('currentAction', currentAction);
    setIfPresent('currentTableId', currentTableId);
    setIfPresent('currentTableName', currentTableName);
    setIfPresent('currentOrderId', currentOrderId);
    setIfPresent('currentTakeoutOrderId', currentTakeoutOrderId);
    setIfPresent('currentKitchenBundleId', currentKitchenBundleId);
    setIfPresent('currentPersonNumber', currentPersonNumber);
    final changed = !_mapEquals(_lastState, nextState);
    final lastWriteAt = _lastWriteAt;
    final heartbeatDue =
        lastWriteAt == null ||
        DateTime.now().difference(lastWriteAt) > const Duration(seconds: 35);
    if (!force && !changed && !heartbeatDue) {
      return;
    }

    _lastState = nextState;
    _lastWriteAt = DateTime.now();
    await _sessionsRef.doc(sessionId).set({
      'employeeId': employee.id,
      'employeeName': employee.name,
      'deviceId': deviceId,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'appMode': nextState['appMode'] ?? 'app',
      'currentScreen': nextState['currentScreen'] ?? 'Inicio',
      'currentAction': nextState['currentAction'] ?? 'Activo',
      'currentTableId': nextState['currentTableId'],
      'currentTableName': nextState['currentTableName'],
      'currentOrderId': nextState['currentOrderId'],
      'currentTakeoutOrderId': nextState['currentTakeoutOrderId'],
      'currentKitchenBundleId': nextState['currentKitchenBundleId'],
      'currentPersonNumber': nextState['currentPersonNumber'],
      'isOnline': true,
      'archived': false,
      'archivedAt': null,
      'lastSeenAt': FieldValue.serverTimestamp(),
      if (!_createdCurrentSession) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _createdCurrentSession = true;
  }

  String _buildDeviceId() {
    return _platformKey();
  }

  String _platformKey() {
    return kIsWeb ? 'web' : defaultTargetPlatform.name;
  }

  bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
