import 'package:uuid/uuid.dart';

/// Keeps a payment attempt stable until the server returns an authoritative
/// result. The shared registry survives widget reconstruction in the running
/// process; the same identifier is also persisted as the payment document ID.
class PaymentAttemptCoordinator {
  PaymentAttemptCoordinator({Uuid uuid = const Uuid()}) : _uuid = uuid;

  static final Map<String, String> _activeAttempts = {};

  final Uuid _uuid;

  String acquire(String key) {
    return _activeAttempts.putIfAbsent(key, _uuid.v4);
  }

  void complete(String key, String attemptId) {
    if (_activeAttempts[key] == attemptId) {
      _activeAttempts.remove(key);
    }
  }

  static void clearForTesting() {
    _activeAttempts.clear();
  }
}
