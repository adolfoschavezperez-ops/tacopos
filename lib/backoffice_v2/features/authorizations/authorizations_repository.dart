import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/cash_session.dart';
import '../../../models/cash_withdrawal_request.dart';
import '../../../models/discount_authorization_request.dart';

class AuthorizationsData {
  const AuthorizationsData({
    required this.withdrawals,
    required this.discounts,
    required this.readCount,
  });

  final List<CashWithdrawalRequest> withdrawals;
  final List<DiscountAuthorizationRequest> discounts;
  final int readCount;

  int get pendingCount =>
      withdrawals.where((w) => w.isPending).length +
      discounts.where((d) => d.isPending).length;

  int get approvedCount =>
      withdrawals.where((w) => w.isApproved).length +
      discounts.where((d) => d.isApproved).length;

  int get rejectedCount =>
      withdrawals.where((w) => w.isRejected).length +
      discounts.where((d) => d.isRejected).length;

  double get approvedWithdrawalsAmount => withdrawals
      .where((w) => w.isApproved)
      .fold<double>(0.0, (acc, w) => acc + w.amount);

  double get approvedDiscountsAmount => discounts
      .where((d) => d.isApproved)
      .fold<double>(0.0, (acc, d) => acc + d.estimatedDiscountAmount);
}

class AuthorizationsRepository {
  AuthorizationsRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<AuthorizationsData> loadAuthorizations({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
    String? statusFilter,
  }) async {
    Query<Map<String, dynamic>> withdrawalsQuery = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('cashWithdrawalRequests')
        .where('businessDate', isGreaterThanOrEqualTo: startBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: endBusinessDate)
        .orderBy('businessDate', descending: true);

    Query<Map<String, dynamic>> discountsQuery = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('discountAuthorizationRequests')
        .where('businessDate', isGreaterThanOrEqualTo: startBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: endBusinessDate)
        .orderBy('businessDate', descending: true);

    if (branchId != null && branchId.isNotEmpty) {
      withdrawalsQuery = withdrawalsQuery.where('branchId', isEqualTo: branchId);
      discountsQuery = discountsQuery.where('branchId', isEqualTo: branchId);
    }

    if (statusFilter != null && statusFilter.isNotEmpty) {
      withdrawalsQuery = withdrawalsQuery.where(
        'status',
        isEqualTo: statusFilter,
      );
      discountsQuery = discountsQuery.where('status', isEqualTo: statusFilter);
    }

    final results = await Future.wait([
      withdrawalsQuery.limit(150).get(),
      discountsQuery.limit(150).get(),
    ]);

    final withdrawals = results[0].docs
        .map(CashWithdrawalRequest.fromDoc)
        .toList(growable: false);
    final discounts = results[1].docs
        .map(DiscountAuthorizationRequest.fromDoc)
        .toList(growable: false);

    return AuthorizationsData(
      withdrawals: withdrawals,
      discounts: discounts,
      readCount: results[0].docs.length + results[1].docs.length,
    );
  }

  /// Atomically approves or rejects a pending cash withdrawal request,
  /// ensuring the target cash session is still open and preventing duplicate resolution.
  Future<void> resolveCashWithdrawal({
    required String restaurantId,
    required String requestId,
    required bool approved,
    required String notesOrReason,
    required String employeeId,
    required String employeeName,
  }) async {
    final cleanNotes = notesOrReason.trim();
    if (!approved && cleanNotes.isEmpty) {
      throw ArgumentError('Captura el motivo del rechazo.');
    }

    final reqRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('cashWithdrawalRequests')
        .doc(requestId);
    final logRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('activityLog')
        .doc();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(reqRef);
      if (!snap.exists) throw StateError('La solicitud ya no existe.');
      final req = CashWithdrawalRequest.fromDoc(snap);
      if (!req.isPending) {
        throw StateError('Esta solicitud ya fue atendida.');
      }

      if (req.cashSessionId.isNotEmpty) {
        final sessionSnap = await tx.get(
          _db
              .collection('restaurants')
              .doc(restaurantId)
              .collection('cashSessions')
              .doc(req.cashSessionId),
        );
        if (!sessionSnap.exists || !CashSession.fromDoc(sessionSnap).isOpen) {
          throw StateError(
            'La caja está en cierre o cerrada y no admite autorizaciones.',
          );
        }
      }

      final now = FieldValue.serverTimestamp();
      tx.update(reqRef, {
        'status': approved ? 'approved' : 'rejected',
        'authorizedByEmployeeId': employeeId,
        'authorizedByEmployeeName': employeeName,
        'authorizedAt': now,
        'adminNotes': cleanNotes,
        if (approved) ...{
          'approvedByEmployeeId': employeeId,
          'approvedByEmployeeName': employeeName,
          'approvedAt': now,
        } else ...{
          'rejectedByEmployeeId': employeeId,
          'rejectedByEmployeeName': employeeName,
          'rejectedAt': now,
          'rejectReason': cleanNotes,
        },
        'updatedAt': now,
      });

      tx.set(logRef, {
        'id': logRef.id,
        'restaurantId': restaurantId,
        'branchId': req.branchId,
        'branchName': req.branchName,
        'type': approved ? 'withdrawal_approved' : 'withdrawal_rejected',
        'actionType': approved ? 'withdrawal_approved' : 'withdrawal_rejected',
        'requestId': requestId,
        'amount': req.amount,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'message':
            '${approved ? 'Autorizó' : 'Rechazó'} retiro de \$${req.amount.toStringAsFixed(2)} (${req.reason})',
        'timestamp': now,
        'createdAt': now,
      });
    });
  }

  /// Atomically approves or rejects a pending discount authorization request.
  Future<void> resolveDiscountAuthorization({
    required String restaurantId,
    required String requestId,
    required bool approved,
    required String rejectReason,
    required String employeeId,
    required String employeeName,
  }) async {
    final cleanReason = rejectReason.trim();
    if (!approved && cleanReason.isEmpty) {
      throw ArgumentError('Captura el motivo del rechazo.');
    }

    final reqRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('discountAuthorizationRequests')
        .doc(requestId);
    final logRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('activityLog')
        .doc();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(reqRef);
      if (!snap.exists) throw StateError('La solicitud ya no existe.');
      final req = DiscountAuthorizationRequest.fromDoc(snap);
      if (!req.isPending) {
        throw StateError('Esta solicitud ya fue atendida.');
      }

      final now = FieldValue.serverTimestamp();
      tx.update(reqRef, {
        'status': approved ? 'approved' : 'rejected',
        if (approved) ...{
          'approvedAt': now,
          'approvedByEmployeeId': employeeId,
          'approvedByEmployeeName': employeeName,
        } else ...{
          'rejectedAt': now,
          'rejectedByEmployeeId': employeeId,
          'rejectedByEmployeeName': employeeName,
          'rejectReason': cleanReason,
        },
        'updatedAt': now,
      });

      tx.set(logRef, {
        'id': logRef.id,
        'restaurantId': restaurantId,
        'branchId': req.branchId,
        'branchName': req.branchName,
        'type': approved ? 'discount_approved' : 'discount_rejected',
        'actionType': approved ? 'discount_approved' : 'discount_rejected',
        'requestId': requestId,
        'orderId': req.orderId,
        'amount': req.estimatedDiscountAmount,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'message':
            '${approved ? 'Autorizó' : 'Rechazó'} descuento ${req.requestedDiscountName} (${req.requestedDiscountPercent.toStringAsFixed(0)}%)',
        'timestamp': now,
        'createdAt': now,
      });
    });
  }
}
