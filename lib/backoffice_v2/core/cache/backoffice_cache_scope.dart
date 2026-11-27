import 'package:flutter/foundation.dart';

/// Session-bound cache scope that isolates in-memory repository caches by
/// user identity, restaurant, branch, permissions fingerprint, and epoch.
///
/// Prevents cross-user cache leaks within the 60s TTL window and prevents
/// stale in-flight async responses from polluting a newer session's cache.
class BackofficeCacheScope {
  int _epoch = 0;
  String _userId = '';
  String _restaurantId = '';
  String _branchId = '';
  String _permissionsFingerprint = '';
  final List<VoidCallback> _invalidators = [];

  int get epoch => _epoch;
  String get userId => _userId;
  String get restaurantId => _restaurantId;
  String get branchId => _branchId;
  String get permissionsFingerprint => _permissionsFingerprint;

  void registerInvalidator(VoidCallback callback) {
    if (!_invalidators.contains(callback)) {
      _invalidators.add(callback);
    }
  }

  /// Updates the active session context and invalidates all caches if the
  /// user, restaurant, branch, or permissions fingerprint changed.
  void updateContext({
    required String userId,
    required String restaurantId,
    required String branchId,
    required String permissionsFingerprint,
  }) {
    final changed =
        _userId != userId ||
        _restaurantId != restaurantId ||
        _branchId != branchId ||
        _permissionsFingerprint != permissionsFingerprint;
    if (!changed) return;
    _userId = userId;
    _restaurantId = restaurantId;
    _branchId = branchId;
    _permissionsFingerprint = permissionsFingerprint;
    invalidateAll();
  }

  /// Clears context on sign-out or revocation and bumps the epoch so any
  /// in-flight async requests from the prior session cannot populate cache.
  void resetSession() {
    _userId = '';
    _restaurantId = '';
    _branchId = '';
    _permissionsFingerprint = '';
    invalidateAll();
  }

  /// Bumps the cache epoch and clears all registered repository caches.
  void invalidateAll() {
    _epoch++;
    for (final cb in List<VoidCallback>.of(_invalidators)) {
      cb();
    }
  }

  /// Builds a fully isolated cache key scoped to the active session epoch,
  /// user, restaurant, branch, and permissions fingerprint.
  String buildScopedKey(String prefix, List<String> parts) {
    final branchPart = _branchId.isEmpty ? 'all' : _branchId;
    return 'e$_epoch|u:$_userId|r:$_restaurantId|b:$branchPart|p:$_permissionsFingerprint|$prefix|${parts.join('|')}';
  }
}
