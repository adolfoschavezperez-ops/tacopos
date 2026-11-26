import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OperationalEmployeeSessionIdentity {
  const OperationalEmployeeSessionIdentity({
    required this.employeeId,
    required this.restaurantId,
    required this.branchId,
  });

  final String employeeId;
  final String restaurantId;
  final String branchId;
}

abstract interface class OperationalEmployeeSessionStore {
  Future<OperationalEmployeeSessionIdentity?> read();

  Future<void> write(OperationalEmployeeSessionIdentity identity);

  Future<void> clear();
}

class SecureOperationalEmployeeSessionStore
    implements OperationalEmployeeSessionStore {
  SecureOperationalEmployeeSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static final instance = SecureOperationalEmployeeSessionStore();

  static const _employeeIdKey = 'operational_session_employee_id';
  static const _restaurantIdKey = 'operational_session_restaurant_id';
  static const _branchIdKey = 'operational_session_branch_id';

  final FlutterSecureStorage _storage;

  @override
  Future<OperationalEmployeeSessionIdentity?> read() async {
    final values = await Future.wait([
      _storage.read(key: _employeeIdKey),
      _storage.read(key: _restaurantIdKey),
      _storage.read(key: _branchIdKey),
    ]);
    final employeeId = values[0]?.trim() ?? '';
    final restaurantId = values[1]?.trim() ?? '';
    final branchId = values[2]?.trim() ?? '';
    if (employeeId.isEmpty || restaurantId.isEmpty || branchId.isEmpty) {
      if (values.any((value) => value != null)) await clear();
      return null;
    }
    return OperationalEmployeeSessionIdentity(
      employeeId: employeeId,
      restaurantId: restaurantId,
      branchId: branchId,
    );
  }

  @override
  Future<void> write(OperationalEmployeeSessionIdentity identity) async {
    await _storage.write(key: _employeeIdKey, value: identity.employeeId);
    await _storage.write(key: _restaurantIdKey, value: identity.restaurantId);
    await _storage.write(key: _branchIdKey, value: identity.branchId);
  }

  @override
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _employeeIdKey),
      _storage.delete(key: _restaurantIdKey),
      _storage.delete(key: _branchIdKey),
    ]);
  }
}
