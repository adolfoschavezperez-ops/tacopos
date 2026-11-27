import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/cash_session.dart';
import '../../../models/payment.dart';

/// Multi-tenant safe Cash Repository for Backoffice 2.0.
///
/// Unlike legacy `TacoPosRepository.getCashDifferenceAudit` (which executed an
/// unscoped `_db.collectionGroup('payments').get()`), this repository strictly
/// scopes all queries to `restaurants/{restaurantId}` and the target
/// `cashSessionId` or `businessDate`.
class CashRepository {
  CashRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<List<CashSession>> fetchCashSessionsByDate({
    required String restaurantId,
    required String businessDate,
    String? branchId,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('cashSessions')
        .where('businessDate', isEqualTo: businessDate);

    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }

    final snapshot = await query.limit(50).get();
    return snapshot.docs.map(CashSession.fromDoc).toList(growable: false);
  }

  /// Scoped payment lookup for a single cash session.
  ///
  /// Reads payments only from orders belonging to `restaurants/{restaurantId}`
  /// for the session's `branchId` and `businessDate`, avoiding cross-tenant
  /// `collectionGroup('payments')` scans.
  Future<List<Payment>> fetchScopedPaymentsForSession({
    required String restaurantId,
    required CashSession session,
  }) async {
    final ordersSnap = await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('orders')
        .where('branchId', isEqualTo: session.branchId)
        .where('businessDate', isEqualTo: session.businessDate)
        .limit(500)
        .get();

    final payments = <Payment>[];
    const batchSize = 15;
    final docs = ordersSnap.docs;

    for (var i = 0; i < docs.length; i += batchSize) {
      final chunk = docs.sublist(i, (i + batchSize).clamp(0, docs.length));
      final results = await Future.wait(
        chunk.map((doc) => doc.reference.collection('payments').get()),
      );
      for (final snap in results) {
        for (final pDoc in snap.docs) {
          final payment = Payment.fromDoc(pDoc);
          final sid = (payment.cashSessionId ?? '').trim();
          if (sid == session.id || sid.isEmpty) {
            payments.add(payment);
          }
        }
      }
    }
    return payments;
  }
}
