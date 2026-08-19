import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/constants/app_constants.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import 'app_session.dart';

class BackofficeAdminAuthService {
  BackofficeAdminAuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<BackofficeAdminSession> signIn({
    required String email,
    required String password,
    String restaurantId = AppConstants.restaurantId,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw const BackofficeAdminAuthException(
        'No se pudo iniciar sesion administrativa.',
      );
    }
    return loadCurrentAdminSession(restaurantId: restaurantId);
  }

  Future<BackofficeAdminSession> loadCurrentAdminSession({
    String restaurantId = AppConstants.restaurantId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const BackofficeAdminAuthException(
        'Inicia sesion para acceder al Backoffice.',
      );
    }
    if (user.isAnonymous) {
      throw const BackofficeAdminAuthException(
        'El Backoffice requiere una cuenta administrativa.',
      );
    }

    final doc = await _firestore
        .collection('restaurants')
        .doc(restaurantId)
        .collection('authUsers')
        .doc(user.uid)
        .get();
    final admin = BackofficeAdminRecord.fromMap(
      uid: user.uid,
      email: user.email ?? '',
      data: doc.data(),
    );
    if (!admin.canAccessBackoffice) {
      await _auth.signOut();
      throw const BackofficeAdminAuthException(
        'No tienes permisos para acceder al Backoffice.',
      );
    }

    final branches = await _loadBranches(restaurantId);
    final employee = admin.toEmployee(
      restaurantId: restaurantId,
      defaultBranchId: branches.isEmpty ? null : branches.first.id,
    );
    AppSession.instance.signIn(
      employee,
      branches: branches.isEmpty ? const [Branch.defaultBranch] : branches,
    );
    return BackofficeAdminSession(user: user, admin: admin, branches: branches);
  }

  Future<void> signOut() async {
    AppSession.instance.signOut();
    await _auth.signOut();
  }

  Future<List<Branch>> _loadBranches(String restaurantId) async {
    final snapshot = await _firestore
        .collection('restaurants')
        .doc(restaurantId)
        .collection('branches')
        .where('active', isEqualTo: true)
        .get();
    final branches =
        snapshot.docs
            .map((doc) => Branch.fromDoc(doc, restaurantId: restaurantId))
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return branches;
  }
}

class BackofficeAdminSession {
  const BackofficeAdminSession({
    required this.user,
    required this.admin,
    required this.branches,
  });

  final User user;
  final BackofficeAdminRecord admin;
  final List<Branch> branches;
}

class BackofficeAdminRecord {
  const BackofficeAdminRecord({
    required this.uid,
    required this.email,
    required this.exists,
    required this.active,
    required this.isSuperAdmin,
    required this.permissions,
    required this.displayName,
  });

  final String uid;
  final String email;
  final bool exists;
  final bool active;
  final bool isSuperAdmin;
  final Map<String, bool> permissions;
  final String displayName;

  bool get canAccessBackoffice =>
      exists &&
      active &&
      (isSuperAdmin ||
          permissions['canViewAdmin'] == true ||
          permissions['canAuthorizeCashWithdrawals'] == true);

  bool get canWriteSensitiveSettings => canAccessBackoffice;
  bool get canManageExpensePolicies => canAccessBackoffice;
  bool get canManageDevices => canAccessBackoffice;
  bool get canManageAppUpdates => canAccessBackoffice;

  static BackofficeAdminRecord fromMap({
    required String uid,
    required String email,
    required Map<String, dynamic>? data,
  }) {
    final permissions = <String, bool>{};
    final rawPermissions = data?['permissions'];
    if (rawPermissions is Map) {
      for (final entry in rawPermissions.entries) {
        permissions[entry.key.toString()] = entry.value == true;
      }
    }
    return BackofficeAdminRecord(
      uid: uid,
      email: email,
      exists: data != null,
      active: data?['active'] == true,
      isSuperAdmin: data?['isSuperAdmin'] == true,
      permissions: permissions,
      displayName:
          (data?['displayName'] as String?) ??
          (data?['name'] as String?) ??
          email,
    );
  }

  Employee toEmployee({required String restaurantId, String? defaultBranchId}) {
    return Employee(
      id: uid,
      name: displayName.trim().isEmpty ? email : displayName,
      active: active,
      pin: '',
      canTakeOrders: false,
      canCharge: false,
      canViewKitchen: true,
      canViewAdmin: true,
      canManageProducts: true,
      canManageTables: true,
      canManagePlatforms: true,
      canManageEmployees: true,
      canManageCash: true,
      canAuthorizeCashWithdrawals: true,
      canOpenKitchen: true,
      canCloseKitchen: true,
      canViewKitchenReports: true,
      canViewKitchenHourlySalesComparison: true,
      canManageKitchenStock: true,
      canCancelOrders: true,
      canCancelPayments: true,
      canCancelItems: true,
      canApproveKitchenCancellations: true,
      canViewLiveOperations: true,
      canControlLiveOperations: true,
      canViewPurchases: true,
      canManageSuppliers: true,
      canRegisterPurchases: true,
      canPaySuppliers: true,
      canCancelSupplierPayments: true,
      canViewAccountsPayable: true,
      canViewPurchaseReports: true,
      isSuperAdmin: isSuperAdmin,
      defaultRestaurantId: restaurantId,
      defaultBranchId: defaultBranchId ?? AppConstants.defaultBranchId,
      restaurantAccess: [restaurantId],
    );
  }
}

class BackofficeAdminAuthException implements Exception {
  const BackofficeAdminAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
