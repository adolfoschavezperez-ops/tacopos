import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/constants/app_constants.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import 'app_session.dart';
import 'device_registry_service.dart';
import 'operational_employee_session_store.dart';

enum OperationalSessionRestoreStatus {
  noSavedSession,
  restored,
  revoked,
  waitingForValidation,
}

class OperationalSessionRestoreResult {
  const OperationalSessionRestoreResult(this.status, {this.message});

  final OperationalSessionRestoreStatus status;
  final String? message;
}

class ResolvedOperationalEmployeeSession {
  const ResolvedOperationalEmployeeSession({
    required this.employee,
    required this.branches,
    required this.selectedBranch,
  });

  final Employee employee;
  final List<Branch> branches;
  final Branch selectedBranch;
}

class OperationalEmployeeSessionRevoked implements Exception {
  const OperationalEmployeeSessionRevoked(this.message);

  final String message;
}

typedef OperationalEmployeeSessionResolver =
    Future<ResolvedOperationalEmployeeSession?> Function(
      OperationalEmployeeSessionIdentity identity,
    );

class OperationalEmployeeSessionService {
  OperationalEmployeeSessionService({
    OperationalEmployeeSessionStore? store,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    OperationalEmployeeSessionResolver? resolver,
    bool Function()? isAuthenticated,
    Future<void> Function(String branchId)? deviceValidator,
    Future<bool> Function()? authRevocationCheck,
  }) : _store = store ?? SecureOperationalEmployeeSessionStore.instance,
       _auth = auth,
       _firestore = firestore,
       _resolver = resolver,
       _isAuthenticated = isAuthenticated,
       _deviceValidator = deviceValidator,
       _authRevocationCheck = authRevocationCheck;

  static final instance = OperationalEmployeeSessionService();

  final OperationalEmployeeSessionStore _store;
  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
  final OperationalEmployeeSessionResolver? _resolver;
  final bool Function()? _isAuthenticated;
  final Future<void> Function(String branchId)? _deviceValidator;
  final Future<bool> Function()? _authRevocationCheck;
  int _operationGeneration = 0;

  Future<void> persistLogin(Employee employee, Branch branch) async {
    _operationGeneration++;
    await _store.write(
      OperationalEmployeeSessionIdentity(
        employeeId: employee.id,
        restaurantId: branch.restaurantId,
        branchId: branch.id,
      ),
    );
  }

  Future<void> persistBranch(Employee employee, Branch branch) async {
    await persistLogin(employee, branch);
  }

  Future<void> validateDeviceForOperationalLogin(String branchId) =>
      (_deviceValidator ?? _validateDevice)(branchId);

  Future<void> clear() {
    _operationGeneration++;
    return _store.clear();
  }

  Future<OperationalSessionRestoreResult> restore() async {
    final operation = ++_operationGeneration;
    OperationalEmployeeSessionIdentity? identity;
    try {
      identity = await _store.read();
    } catch (error) {
      return OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.waitingForValidation,
        message: 'No se pudo abrir el almacenamiento seguro: $error',
      );
    }
    if (identity == null) {
      return const OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.noSavedSession,
      );
    }

    if (!(_isAuthenticated?.call() ??
        (_auth ?? FirebaseAuth.instance).currentUser != null)) {
      return const OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.waitingForValidation,
        message: 'Esperando autenticación segura para validar la sesión.',
      );
    }
    try {
      final resolved = await (_resolver ?? _resolveFromFirestore)(identity);
      if (!_isCurrentOperation(operation) ||
          !await _identityIsCurrent(identity)) {
        return _staleResult();
      }
      if (resolved == null) {
        await _store.clear();
        return OperationalSessionRestoreResult(
          OperationalSessionRestoreStatus.revoked,
          message: identity.restaurantId != AppConstants.restaurantId
              ? 'La sesión guardada pertenece a otro restaurante.'
              : 'El empleado o su sucursal ya no tienen acceso vigente.',
        );
      }

      try {
        await (_deviceValidator ?? _validateDevice)(resolved.selectedBranch.id);
      } on DeviceRegistryException catch (error) {
        if (error.code == 'device-inactive' ||
            error.code == 'device-restaurant-mismatch' ||
            error.code == 'device-branch-mismatch') {
          if (!_isCurrentOperation(operation) ||
              !await _identityIsCurrent(identity)) {
            return _staleResult();
          }
          await _store.clear();
          return OperationalSessionRestoreResult(
            OperationalSessionRestoreStatus.revoked,
            message: error.message,
          );
        }
        return OperationalSessionRestoreResult(
          OperationalSessionRestoreStatus.waitingForValidation,
          message: error.message,
        );
      }

      if (!_isCurrentOperation(operation) ||
          !await _identityIsCurrent(identity)) {
        return _staleResult();
      }
      AppSession.instance.signIn(
        resolved.employee,
        branches: resolved.branches,
        initialBranch: resolved.selectedBranch,
      );
      return const OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.restored,
      );
    } on OperationalEmployeeSessionRevoked catch (error) {
      if (!_isCurrentOperation(operation) ||
          !await _identityIsCurrent(identity)) {
        return _staleResult();
      }
      await _store.clear();
      return OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.revoked,
        message: error.message,
      );
    } on FirebaseException catch (error) {
      if (error.code == 'unauthenticated' &&
          await _isFirebaseAuthenticationRevoked()) {
        if (!_isCurrentOperation(operation) ||
            !await _identityIsCurrent(identity)) {
          return _staleResult();
        }
        await _store.clear();
        return const OperationalSessionRestoreResult(
          OperationalSessionRestoreStatus.revoked,
          message: 'La autenticación segura del dispositivo fue revocada.',
        );
      }
      return OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.waitingForValidation,
        message: 'No se pudo revalidar la sesión (${error.code}).',
      );
    } catch (error) {
      return OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.waitingForValidation,
        message: 'No se pudo revalidar la sesión: $error',
      );
    }
  }

  Future<OperationalSessionRestoreResult> revalidateCurrentSession() async {
    final currentEmployee = AppSession.instance.employee;
    if (currentEmployee == null) {
      return const OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.noSavedSession,
      );
    }
    final appSessionRevision = AppSession.instance.sessionRevision;
    final operation = ++_operationGeneration;
    OperationalEmployeeSessionIdentity? identity;
    try {
      identity = await _store.read();
    } catch (error) {
      return OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.waitingForValidation,
        message: 'No se pudo abrir el almacenamiento seguro: $error',
      );
    }
    if (identity == null) {
      return const OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.waitingForValidation,
        message: 'No saved operational identity is available.',
      );
    }
    if (identity.employeeId != currentEmployee.id ||
        identity.restaurantId != AppSession.instance.currentRestaurantId ||
        identity.branchId != AppSession.instance.currentBranchId) {
      return OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.waitingForValidation,
        message: 'La sucursal activa cambió; se revalidará la sesión actual.',
      );
    }
    if (!(_isAuthenticated?.call() ??
        (_auth ?? FirebaseAuth.instance).currentUser != null)) {
      return const OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.waitingForValidation,
        message: 'Esperando autenticación segura para validar permisos.',
      );
    }
    try {
      final resolved = await (_resolver ?? _resolveFromFirestore)(identity);
      if (!_isCurrentOperation(operation) ||
          AppSession.instance.sessionRevision != appSessionRevision ||
          !await _identityIsCurrent(identity)) {
        return _staleResult();
      }
      if (resolved == null) {
        await AppSession.instance.signOut(reason: 'access_revoked');
        return const OperationalSessionRestoreResult(
          OperationalSessionRestoreStatus.revoked,
          message: 'El empleado o la sucursal ya no tienen acceso vigente.',
        );
      }
      await (_deviceValidator ?? _validateDevice)(resolved.selectedBranch.id);
      if (!_isCurrentOperation(operation) ||
          AppSession.instance.sessionRevision != appSessionRevision ||
          !await _identityIsCurrent(identity)) {
        return _staleResult();
      }
      AppSession.instance.refreshEmployee(
        resolved.employee,
        branches: resolved.branches,
        selectedBranch: resolved.selectedBranch,
      );
      return const OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.restored,
      );
    } on OperationalEmployeeSessionRevoked catch (error) {
      if (!_isCurrentOperation(operation) ||
          AppSession.instance.sessionRevision != appSessionRevision ||
          !await _identityIsCurrent(identity)) {
        return _staleResult();
      }
      await AppSession.instance.signOut(reason: 'employee_or_branch_revoked');
      return OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.revoked,
        message: error.message,
      );
    } on DeviceRegistryException catch (error) {
      if (error.code == 'device-inactive' ||
          error.code == 'device-restaurant-mismatch' ||
          error.code == 'device-branch-mismatch') {
        if (!_isCurrentOperation(operation) ||
            AppSession.instance.sessionRevision != appSessionRevision ||
            !await _identityIsCurrent(identity)) {
          return _staleResult();
        }
        await AppSession.instance.signOut(reason: 'device_revoked');
        return OperationalSessionRestoreResult(
          OperationalSessionRestoreStatus.revoked,
          message: error.message,
        );
      }
      return OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.waitingForValidation,
        message: error.message,
      );
    } on FirebaseException catch (error) {
      if (error.code == 'unauthenticated' &&
          await _isFirebaseAuthenticationRevoked()) {
        if (!_isCurrentOperation(operation) ||
            AppSession.instance.sessionRevision != appSessionRevision ||
            !await _identityIsCurrent(identity)) {
          return _staleResult();
        }
        await AppSession.instance.signOut(reason: 'firebase_auth_revoked');
        return const OperationalSessionRestoreResult(
          OperationalSessionRestoreStatus.revoked,
          message: 'La autenticación segura del dispositivo fue revocada.',
        );
      }
      return OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.waitingForValidation,
        message: 'No se pudo revalidar la sesión (${error.code}).',
      );
    } catch (error) {
      return OperationalSessionRestoreResult(
        OperationalSessionRestoreStatus.waitingForValidation,
        message: 'No se pudo revalidar la sesión: $error',
      );
    }
  }

  bool _isCurrentOperation(int operation) => operation == _operationGeneration;

  Future<bool> _isFirebaseAuthenticationRevoked() async {
    final customCheck = _authRevocationCheck;
    if (customCheck != null) {
      try {
        return await customCheck();
      } catch (_) {
        return false;
      }
    }
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) return true;
    try {
      await user.reload();
      await user.getIdToken(true);
      return false;
    } on FirebaseAuthException catch (error) {
      return const {
        'user-disabled',
        'user-not-found',
        'user-token-expired',
        'invalid-user-token',
      }.contains(error.code);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _identityIsCurrent(
    OperationalEmployeeSessionIdentity identity,
  ) async {
    final current = await _store.read();
    return current?.employeeId == identity.employeeId &&
        current?.restaurantId == identity.restaurantId &&
        current?.branchId == identity.branchId;
  }

  OperationalSessionRestoreResult _staleResult() =>
      OperationalSessionRestoreResult(
        AppSession.instance.isLoggedIn
            ? OperationalSessionRestoreStatus.restored
            : OperationalSessionRestoreStatus.waitingForValidation,
        message: 'Se descartó una respuesta de validación obsoleta.',
      );

  Future<void> _validateDevice(String branchId) =>
      DeviceRegistryService.instance.ensureCurrentDeviceReady(
        recordHeartbeat: false,
        expectedBranchId: branchId,
      );

  Future<ResolvedOperationalEmployeeSession?> _resolveFromFirestore(
    OperationalEmployeeSessionIdentity identity,
  ) async {
    if (identity.restaurantId != AppConstants.restaurantId) return null;
    final firestore = _firestore ?? FirebaseFirestore.instance;
    final restaurant = firestore
        .collection('restaurants')
        .doc(identity.restaurantId);
    final employeeDoc = await restaurant
        .collection('employees')
        .doc(identity.employeeId)
        .get(const GetOptions(source: Source.server));
    if (!employeeDoc.exists) {
      throw const OperationalEmployeeSessionRevoked(
        'El empleado ya no está registrado.',
      );
    }

    final employee = Employee.fromDoc(employeeDoc);
    if (!employee.active) {
      throw const OperationalEmployeeSessionRevoked(
        'El acceso del empleado fue desactivado.',
      );
    }
    final branchesSnapshot = await restaurant
        .collection('branches')
        .where('active', isEqualTo: true)
        .get(const GetOptions(source: Source.server));
    final allActiveBranches = branchesSnapshot.docs
        .map(
          (doc) => Branch.fromDoc(
            doc,
            restaurantId: identity.restaurantId,
            restaurantName: AppConstants.restaurantName,
          ),
        )
        .toList(growable: false);

    final allowedIds = employee.effectiveBranchAccess
        .where((access) => access.active)
        .map((access) => access.branchId)
        .toSet();
    final branches = employee.hasAdminAccess
        ? allActiveBranches
        : allowedIds.isEmpty
        ? allActiveBranches
              .where((branch) => branch.id == AppConstants.defaultBranchId)
              .toList(growable: false)
        : allActiveBranches
              .where((branch) => allowedIds.contains(branch.id))
              .toList(growable: false);
    for (final branch in branches) {
      if (branch.id == identity.branchId) {
        return ResolvedOperationalEmployeeSession(
          employee: employee,
          branches: branches,
          selectedBranch: branch,
        );
      }
    }
    throw const OperationalEmployeeSessionRevoked(
      'El empleado ya no tiene acceso a la sucursal guardada.',
    );
  }
}
