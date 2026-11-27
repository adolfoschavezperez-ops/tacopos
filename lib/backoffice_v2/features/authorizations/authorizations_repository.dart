import 'package:cloud_firestore/cloud_firestore.dart';

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
}
