import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/constants/app_constants.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import 'app_session.dart';

class BackofficeAdminAuthService {
  BackofficeAdminAuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  String? _explicitOperatorSessionUserId;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// True only after this service instance completes a PIN login.
  bool get hasExplicitOperatorSession =>
      _explicitOperatorSessionUserId != null &&
      _auth.currentUser?.uid == _explicitOperatorSessionUserId;

  Future<List<BackofficeLoginUser>> listBackofficeUsers({
    String restaurantId = AppConstants.restaurantId,
  }) async {
    final callable = _functions.httpsCallable('listBackofficeUsers');
    final response = await callable.call<Map<String, dynamic>>({
      'restaurantId': restaurantId,
    });
    final rawUsers = response.data['users'];
    if (rawUsers is! List) {
      return const [];
    }
    return rawUsers
        .whereType<Map>()
        .map(BackofficeLoginUser.fromMap)
        .where((user) => user.id.isNotEmpty && user.displayName.isNotEmpty)
        .toList(growable: false);
  }

  Future<BackofficeAdminSession> signInWithPin({
    required String employeeId,
    required String pin,
    String restaurantId = AppConstants.restaurantId,
  }) async {
    // The Backoffice operator identity must not survive a Web reload.
    await _auth.setPersistence(Persistence.NONE);
    final callable = _functions.httpsCallable('backofficePinLogin');
    final response = await callable.call<Map<String, dynamic>>({
      'restaurantId': restaurantId,
      'employeeId': employeeId.trim(),
      'pin': pin,
      'clientRequestId': DateTime.now().microsecondsSinceEpoch.toString(),
    });
    final customToken = response.data['customToken'] as String? ?? '';
    if (customToken.isEmpty) {
      throw const BackofficeAdminAuthException(
        'No se pudo iniciar sesion administrativa.',
      );
    }
    final credential = await _auth.signInWithCustomToken(customToken);
    final user = credential.user;
    if (user == null) {
      throw const BackofficeAdminAuthException(
        'No se pudo iniciar sesion administrativa.',
      );
    }
    _explicitOperatorSessionUserId = user.uid;
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
    _explicitOperatorSessionUserId = null;
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

class BackofficeLoginUser {
  const BackofficeLoginUser({required this.id, required this.displayName});

  final String id;
  final String displayName;

  static BackofficeLoginUser fromMap(Map<Object?, Object?> data) {
    return BackofficeLoginUser(
      id: data['id']?.toString().trim() ?? '',
      displayName: data['displayName']?.toString().trim() ?? '',
    );
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
    required this.employeeId,
  });

  final String uid;
  final String email;
  final bool exists;
  final bool active;
  final bool isSuperAdmin;
  final Map<String, bool> permissions;
  final String displayName;
  final String employeeId;

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
      employeeId: (data?['employeeId'] as String?) ?? uid,
    );
  }

  Employee toEmployee({required String restaurantId, String? defaultBranchId}) {
    bool read(String key) => isSuperAdmin || permissions[key] == true;
    return Employee(
      id: employeeId,
      name: displayName.trim().isEmpty ? email : displayName,
      active: active,
      pin: '',
      canTakeOrders: false,
      canCharge: false,
      canViewKitchen: read('canViewKitchen'),
      canViewAdmin: read('canViewAdmin'),
      canManageProducts: read('canManageProducts'),
      canManageTables: read('canManageTables'),
      canManagePlatforms: read('canManagePlatforms'),
      canManageEmployees: read('canManageEmployees'),
      canManageCash: read('canManageCash'),
      canAuthorizeCashWithdrawals: read('canAuthorizeCashWithdrawals'),
      canOpenKitchen: read('canOpenKitchen'),
      canCloseKitchen: read('canCloseKitchen'),
      canViewKitchenReports: read('canViewKitchenReports'),
      canViewKitchenHourlySalesComparison: read(
        'canViewKitchenHourlySalesComparison',
      ),
      canManageKitchenStock: read('canManageKitchenStock'),
      canCancelOrders: read('canCancelOrders'),
      canCancelPayments: read('canCancelPayments'),
      canCancelItems: read('canCancelItems'),
      canApproveKitchenCancellations: read('canApproveKitchenCancellations'),
      canViewLiveOperations: read('canViewLiveOperations'),
      canControlLiveOperations: read('canControlLiveOperations'),
      canViewPurchases: read('canViewPurchases'),
      canManageSuppliers: read('canManageSuppliers'),
      canRegisterPurchases: read('canRegisterPurchases'),
      canPaySuppliers: read('canPaySuppliers'),
      canCancelSupplierPayments: read('canCancelSupplierPayments'),
      canViewAccountsPayable: read('canViewAccountsPayable'),
      canViewPurchaseReports: read('canViewPurchaseReports'),
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
