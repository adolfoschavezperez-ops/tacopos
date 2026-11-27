import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/branch.dart';
import '../../models/employee.dart';
import '../../services/backoffice_admin_auth_service.dart';
import '../core/env/backoffice_env.dart';
import '../core/preview/preview_api_client.dart';

class BackofficeAuthException implements Exception {
  const BackofficeAuthException(
    this.message, {
    this.functionsUnavailableInSpark = false,
  });

  final String message;
  final bool functionsUnavailableInSpark;

  @override
  String toString() => message;
}

class BackofficeAuthResult {
  const BackofficeAuthResult({
    required this.employee,
    required this.isSuperAdmin,
    required this.restaurantId,
    required this.restaurantName,
    required this.branches,
  });

  final Employee employee;
  final bool isSuperAdmin;
  final String restaurantId;
  final String restaurantName;
  final List<Branch> branches;
}

/// Real Firebase Authentication service for Backoffice 2.0.
///
/// Reuses the existing Cloud Functions contract (`listBackofficeUsers` and
/// `backofficePinLogin`) in LOCAL emulator mode, and supports Email/Password
/// Firebase Auth against `restaurants/{restaurantId}/authUsers/{uid}` in DEV
/// while Cloud Functions remain undeployed under Spark plan.
class BackofficeV2AuthService {
  BackofficeV2AuthService({
    required this.config,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    PreviewApiClient? previewClient,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: config.functionsRegion),
       _previewClient = previewClient;

  final BackofficeConfig config;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final PreviewApiClient? _previewClient;

  Future<List<BackofficeLoginUser>> listUsers({
    required String restaurantId,
  }) async {
    try {
      final callable = _functions.httpsCallable('listBackofficeUsers');
      final response = await callable.call<Map<String, dynamic>>({
        'restaurantId': restaurantId.trim(),
      });
      final raw = response.data['users'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map(BackofficeLoginUser.fromMap)
          .where((u) => u.id.isNotEmpty && u.displayName.isNotEmpty)
          .toList(growable: false);
    } on FirebaseFunctionsException catch (e) {
      final isSparkUnavailable =
          !config.isLocal &&
          (e.code == 'not-found' ||
              e.code == 'unavailable' ||
              e.code == 'internal');
      if (isSparkUnavailable) {
        throw const BackofficeAuthException(
          'Cloud Functions remotas no desplegadas en DEV (plan Spark). Usa Email/Contraseña en DEV o ejecuta en ambiente LOCAL con Emulators.',
          functionsUnavailableInSpark: true,
        );
      }
      throw BackofficeAuthException(
        e.message ?? 'No se pudieron cargar los usuarios del restaurante.',
      );
    } catch (_) {
      if (!config.isLocal) {
        throw const BackofficeAuthException(
          'Cloud Functions remotas no disponibles en DEV (plan Spark). Usa Email/Contraseña en DEV o ambiente LOCAL.',
          functionsUnavailableInSpark: true,
        );
      }
      rethrow;
    }
  }

  Future<BackofficeAuthResult> signInWithPin({
    required String restaurantId,
    required String employeeId,
    required String pin,
  }) async {
    final cleanRestaurant = restaurantId.trim();
    if (cleanRestaurant.isEmpty) {
      throw const BackofficeAuthException('Ingresa el ID del restaurante.');
    }
    await _auth.setPersistence(Persistence.NONE);
    try {
      final callable = _functions.httpsCallable('backofficePinLogin');
      final response = await callable.call<Map<String, dynamic>>({
        'restaurantId': cleanRestaurant,
        'employeeId': employeeId.trim(),
        'pin': pin,
        'clientRequestId': DateTime.now().microsecondsSinceEpoch.toString(),
      });
      final token = response.data['customToken'] as String? ?? '';
      if (token.isEmpty) {
        throw const BackofficeAuthException(
          'No se recibió token de autenticación.',
        );
      }
      await _auth.signInWithCustomToken(token);
      return _loadAuthorizedSession(restaurantId: cleanRestaurant);
    } on FirebaseFunctionsException catch (e) {
      final isSparkUnavailable =
          !config.isLocal &&
          (e.code == 'not-found' ||
              e.code == 'unavailable' ||
              e.code == 'internal');
      throw BackofficeAuthException(
        isSparkUnavailable
            ? 'backofficePinLogin no está desplegado en DEV (plan Spark). Usa Email/Contraseña o ambiente LOCAL.'
            : (e.message ?? 'Credenciales inválidas.'),
        functionsUnavailableInSpark: isSparkUnavailable,
      );
    }
  }

  Future<BackofficeAuthResult> signInWithEmail({
    required String restaurantId,
    required String email,
    required String password,
  }) async {
    final cleanRestaurant = restaurantId.trim();
    if (cleanRestaurant.isEmpty) {
      throw const BackofficeAuthException(
        'Ingresa el identificador de tu restaurante.',
      );
    }
    await _auth.setPersistence(Persistence.LOCAL);
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return _loadAuthorizedSession(restaurantId: cleanRestaurant);
    } on FirebaseAuthException catch (e) {
      throw BackofficeAuthException(_friendlyAuthError(e));
    }
  }

  static String _friendlyAuthError(FirebaseAuthException e) {
    return switch (e.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' =>
        'Correo o contraseña incorrectos. Verifica tus datos e intenta de nuevo.',
      'invalid-email' => 'El formato del correo electrónico no es válido.',
      'user-disabled' =>
        'Esta cuenta ha sido deshabilitada. Contacta al administrador.',
      'too-many-requests' =>
        'Demasiados intentos fallidos. Espera un momento antes de volver a intentar.',
      'network-request-failed' =>
        'No se pudo conectar. Verifica tu conexión a internet.',
      _ => e.message ?? 'No se pudo iniciar sesión. Intenta nuevamente.',
    };
  }

  Future<BackofficeAuthResult?> restoreSessionIfSignedIn({
    required String restaurantId,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      return null;
    }
    try {
      await user.getIdToken(true);
      return await _loadAuthorizedSession(restaurantId: restaurantId);
    } catch (_) {
      await _auth.signOut();
      return null;
    }
  }

  /// Forces ID token refresh and verifies that `authUsers/{uid}` remains
  /// active and authorized for the current restaurant.
  Future<bool> verifyActiveSession({
    required String restaurantId,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      return false;
    }
    try {
      await user.getIdToken(true);
      if (config.isPreview) {
        final preview = _previewClient;
        if (preview == null) return false;
        await preview.fetchSession(restaurantId: restaurantId);
        return true;
      }
      final authDoc = await _firestore
          .collection('restaurants')
          .doc(restaurantId)
          .collection('authUsers')
          .doc(user.uid)
          .get();
      final record = BackofficeAdminRecord.fromMap(
        uid: user.uid,
        email: user.email ?? '',
        data: authDoc.data(),
      );
      if (!record.canAccessBackoffice) {
        await _auth.signOut();
        return false;
      }
      // P1-8: If linked employee doc is readable without legacy PIN, verify active == true.
      // Server-side Firestore Rules also enforce employees/{employeeId}.active == true.
      if (record.employeeId.trim().isNotEmpty) {
        try {
          final empDoc = await _firestore
              .collection('restaurants')
              .doc(restaurantId)
              .collection('employees')
              .doc(record.employeeId.trim())
              .get();
          if (empDoc.exists && empDoc.data()?['active'] == false) {
            await _auth.signOut();
            return false;
          }
        } on FirebaseException catch (e) {
          if (e.code != 'permission-denied') rethrow;
        }
      }
      return true;
    } catch (_) {
      await _auth.signOut();
      return false;
    }
  }

  Future<BackofficeAuthResult> _loadAuthorizedSession({
    required String restaurantId,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw const BackofficeAuthException(
        'Se requiere una sesión autenticada autorizada.',
      );
    }

    if (config.isPreview) {
      final preview = _previewClient;
      if (preview == null) {
        await _auth.signOut();
        throw const BackofficeAuthException(
          'Preview API no configurada. No se permite fallback a Firestore.',
        );
      }
      try {
        final session = await preview.fetchSession(restaurantId: restaurantId);
        final allowedBranches = session.branches
            .map(Branch.fromDoc)
            .where((b) => b.active)
            .toList(growable: false);
        final record = BackofficeAdminRecord(
          uid: session.uid,
          email: user.email ?? '',
          displayName: session.displayName,
          employeeId: session.employeeId,
          exists: true,
          active: true,
          isSuperAdmin: session.isSuperAdmin,
          permissions: session.permissions,
        );
        final employee = record.toEmployee(
          restaurantId: session.restaurantId,
          defaultBranchId:
              allowedBranches.isEmpty ? null : allowedBranches.first.id,
        );
        return BackofficeAuthResult(
          employee: employee,
          isSuperAdmin: session.isSuperAdmin,
          restaurantId: session.restaurantId,
          restaurantName: session.restaurantName,
          branches: allowedBranches,
        );
      } on PreviewApiException catch (e) {
        await _auth.signOut();
        throw BackofficeAuthException(e.message);
      }
    }

    final authDoc = await _firestore
        .collection('restaurants')
        .doc(restaurantId)
        .collection('authUsers')
        .doc(user.uid)
        .get();

    final record = BackofficeAdminRecord.fromMap(
      uid: user.uid,
      email: user.email ?? '',
      data: authDoc.data(),
    );

    if (!record.canAccessBackoffice) {
      await _auth.signOut();
      throw const BackofficeAuthException(
        'Tu cuenta no tiene permisos administrativos para este restaurante.',
      );
    }

    final restaurantSnap = await _firestore
        .collection('restaurants')
        .doc(restaurantId)
        .get();
    final restaurantName =
        (restaurantSnap.data()?['name'] as String?)?.trim().isNotEmpty == true
        ? (restaurantSnap.data()!['name'] as String).trim()
        : restaurantId;

    final branchSnap = await _firestore
        .collection('restaurants')
        .doc(restaurantId)
        .collection('branches')
        .orderBy('sortOrder')
        .get();

    final allBranches = branchSnap.docs
        .map(Branch.fromDoc)
        .where((b) => b.active)
        .toList(growable: false);

    final rawBranchAccess = authDoc.data()?['branchAccess'];
    final branchAccess = rawBranchAccess is List
        ? rawBranchAccess.map((e) => e.toString()).toSet()
        : <String>{};
    final allBranchesAccess = authDoc.data()?['allBranchesAccess'] == true;

    final allowedBranches = (record.isSuperAdmin || allBranchesAccess)
        ? allBranches
        : allBranches
              .where((b) => branchAccess.contains(b.id))
              .toList(growable: false);

    if (!record.isSuperAdmin && !allBranchesAccess && allowedBranches.isEmpty) {
      await _auth.signOut();
      throw const BackofficeAuthException(
        'Tu cuenta no tiene sucursales autorizadas en este restaurante.',
      );
    }

    final employee = record.toEmployee(
      restaurantId: restaurantId,
      defaultBranchId: allowedBranches.isEmpty
          ? null
          : allowedBranches.first.id,
    );

    return BackofficeAuthResult(
      employee: employee,
      isSuperAdmin: record.isSuperAdmin,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      branches: allowedBranches,
    );
  }

  Future<void> signOut() => _auth.signOut();
}

/// Prevents redundant token-refresh / Firestore `authUsers` checks when
/// `idTokenChanges()` and `getIdToken(true)` interact across lifecycle events.
class SessionRenewalGuard {
  SessionRenewalGuard({this.cooldown = const Duration(seconds: 60)});

  final Duration cooldown;
  DateTime? _lastCheckAt;
  bool _inFlight = false;
  int executedChecks = 0;
  int skippedChecks = 0;

  bool get isInFlight => _inFlight;

  Future<bool?> runGuarded(
    Future<bool> Function() check, {
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    if (_inFlight) {
      skippedChecks += 1;
      return null;
    }
    if (_lastCheckAt != null && current.difference(_lastCheckAt!) < cooldown) {
      skippedChecks += 1;
      return null;
    }
    _inFlight = true;
    _lastCheckAt = current;
    executedChecks += 1;
    try {
      return await check();
    } finally {
      _inFlight = false;
    }
  }
}
