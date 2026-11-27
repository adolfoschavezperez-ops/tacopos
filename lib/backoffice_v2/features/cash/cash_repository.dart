import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/reports/canonical_sales_summary.dart';
import '../../../models/cash_session.dart';
import '../../../models/cash_withdrawal_request.dart';
import '../../../models/order.dart';
import '../../../models/payment.dart';
import '../../core/adapters/sales_adapter.dart';

class CashReadMetrics {
  const CashReadMetrics({
    required this.sessionsRead,
    required this.withdrawalsRead,
    required this.ordersRead,
    required this.paymentsRead,
  });

  final int sessionsRead;
  final int withdrawalsRead;
  final int ordersRead;
  final int paymentsRead;

  int get totalReads =>
      sessionsRead + withdrawalsRead + ordersRead + paymentsRead;
}

class CashReconciliationSummary {
  const CashReconciliationSummary({
    required this.openingCashAmount,
    required this.cashCollected,
    required this.cardCollected,
    required this.platformCollected,
    required this.tipsTotal,
    required this.approvedWithdrawalsTotal,
    required this.pendingWithdrawalsTotal,
    required this.expectedCashInDrawer,
    required this.countedCashAmount,
    required this.terminalReportedAmount,
    required this.cashDifference,
    required this.cardDifference,
    required this.netDifference,
    required this.shortageAmount,
    required this.overAmount,
    required this.employeeFreeMealTotal,
    required this.employeeConsumptionTotal,
    required this.explicitDiscountsTotal,
    required this.cancelledOrdersCount,
    required this.cancelledAmount,
    required this.totalExpectedRealMoney,
    required this.totalCountedRealMoney,
  });

  final double openingCashAmount;
  final double cashCollected;
  final double cardCollected;
  final double platformCollected;
  final double tipsTotal;
  final double approvedWithdrawalsTotal;
  final double pendingWithdrawalsTotal;
  final double expectedCashInDrawer;
  final double countedCashAmount;
  final double terminalReportedAmount;
  final double cashDifference;
  final double cardDifference;
  final double netDifference;
  final double shortageAmount;
  final double overAmount;

  /// Non-monetary internal benefit & discount metrics (kept separate from cash).
  final double employeeFreeMealTotal;
  final double employeeConsumptionTotal;
  final double explicitDiscountsTotal;
  final int cancelledOrdersCount;
  final double cancelledAmount;

  final double totalExpectedRealMoney;
  final double totalCountedRealMoney;

  factory CashReconciliationSummary.compute({
    required CashSession session,
    required List<PosOrder> orders,
    required List<Payment> payments,
    required List<CashWithdrawalRequest> withdrawals,
  }) {
    final paymentsByOrder = <String, List<Payment>>{};
    var tipsTotal = 0.0;
    for (final p in payments) {
      final isCancelled =
          p.status.trim().toLowerCase() == 'cancelled' ||
          p.type.trim().toLowerCase() == 'cancelled';
      if (isCancelled) continue;
      paymentsByOrder.putIfAbsent(p.orderId, () => []).add(p);
      tipsTotal += p.tipAmount;
    }

    final cancelledOrders = orders.where(isCanonicalCancelledOrder).toList();
    final cancelledAmount = cancelledOrders.fold<double>(
      0.0,
      (acc, o) => acc + o.total,
    );

    final canonical = BackofficeSalesAdapter.buildCanonicalSummary(
      orders: orders,
      itemsByOrder: const {},
      paymentsByOrder: paymentsByOrder,
    );

    final cashCollected = orders.isNotEmpty
        ? canonical.cashCollected
        : session.expectedCashAmount;
    final cardCollected = orders.isNotEmpty
        ? canonical.cardCollected
        : session.expectedCardChargedAmount;
    final platformCollected = orders.isNotEmpty
        ? canonical.platformCollected
        : session.expectedPlatformAmount;

    final approvedWithdrawals = withdrawals.isNotEmpty
        ? withdrawals
              .where((w) => w.isApproved)
              .fold<double>(0.0, (acc, w) => acc + w.amount)
        : session.approvedWithdrawalsTotal;

    final pendingWithdrawals = withdrawals.isNotEmpty
        ? withdrawals
              .where((w) => w.isPending)
              .fold<double>(0.0, (acc, w) => acc + w.amount)
        : session.pendingWithdrawalsTotal;

    final computedExpectedDrawer =
        session.openingCashAmount + cashCollected - approvedWithdrawals;
    final expectedDrawer = session.isClosed && session.expectedCashAmount > 0
        ? session.expectedCashAmount
        : computedExpectedDrawer;

    final cashDiff = session.isClosed
        ? session.cashDifference
        : (session.countedCashAmount > 0
              ? session.countedCashAmount - expectedDrawer
              : 0.0);

    final cardDiff = session.isClosed
        ? session.cardDifference
        : (session.terminalReportedAmount > 0
              ? session.terminalReportedAmount - cardCollected
              : 0.0);

    final netDiff = session.isClosed
        ? session.netDifference
        : (cashDiff + cardDiff);

    final shortage = session.isClosed
        ? session.shortageAmount
        : (netDiff < 0 ? netDiff.abs() : 0.0);
    final over = session.isClosed
        ? session.overAmount
        : (netDiff > 0 ? netDiff : 0.0);

    final employeeConsumption = orders.isNotEmpty
        ? canonical.employeeConsumption
        : session.expectedEmployeeConsumptionAmount;

    final totalExpectedReal = session.totalExpectedRealMoney > 0
        ? session.totalExpectedRealMoney
        : (expectedDrawer + cardCollected + platformCollected);
    final totalCountedReal = session.totalCountedRealMoney > 0
        ? session.totalCountedRealMoney
        : (session.countedCashAmount +
              session.terminalReportedAmount +
              platformCollected);

    final employeeFreeMealTotal = canonical.employeeFreeMealTotal > 0
        ? canonical.employeeFreeMealTotal
        : payments
              .where((p) => isCanonicalActivePayment(p) && isEmployeeFreeMealPayment(p))
              .fold<double>(
                0.0,
                (acc, p) => acc + (p.discountAmount > 0 ? p.discountAmount : p.baseAmount),
              );

    final explicitDiscountsTotal = canonical.discountTotal > 0
        ? canonical.discountTotal
        : orders
              .where((o) => !isCanonicalCancelledOrder(o))
              .fold<double>(0.0, (acc, o) => acc + o.explicitDiscount);

    return CashReconciliationSummary(
      openingCashAmount: session.openingCashAmount,
      cashCollected: cashCollected,
      cardCollected: cardCollected,
      platformCollected: platformCollected,
      tipsTotal: tipsTotal,
      approvedWithdrawalsTotal: approvedWithdrawals,
      pendingWithdrawalsTotal: pendingWithdrawals,
      expectedCashInDrawer: expectedDrawer,
      countedCashAmount: session.countedCashAmount,
      terminalReportedAmount: session.terminalReportedAmount,
      cashDifference: cashDiff,
      cardDifference: cardDiff,
      netDifference: netDiff,
      shortageAmount: shortage,
      overAmount: over,
      employeeFreeMealTotal: employeeFreeMealTotal,
      employeeConsumptionTotal: employeeConsumption,
      explicitDiscountsTotal: explicitDiscountsTotal,
      cancelledOrdersCount: cancelledOrders.length,
      cancelledAmount: cancelledAmount,
      totalExpectedRealMoney: totalExpectedReal,
      totalCountedRealMoney: totalCountedReal,
    );
  }
}

class CashSessionDetailData {
  const CashSessionDetailData({
    required this.session,
    required this.withdrawals,
    required this.orders,
    required this.payments,
    required this.summary,
    required this.metrics,
  });

  final CashSession session;
  final List<CashWithdrawalRequest> withdrawals;
  final List<PosOrder> orders;
  final List<Payment> payments;
  final CashReconciliationSummary summary;
  final CashReadMetrics metrics;
}

class CashDashboardData {
  const CashDashboardData({
    required this.sessions,
    required this.withdrawals,
    required this.openSession,
    required this.selectedDetail,
    required this.metrics,
  });

  final List<CashSession> sessions;
  final List<CashWithdrawalRequest> withdrawals;
  final CashSession? openSession;
  final CashSessionDetailData? selectedDetail;
  final CashReadMetrics metrics;
}

/// Multi-tenant safe Cash Repository for Backoffice 2.0.
///
/// Strictly scopes all queries to `restaurants/{restaurantId}` and bounded
/// `businessDate` / `branchId` filters, never executing global
/// `collectionGroup('payments')` scans.
class CashRepository {
  CashRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<CashDashboardData> loadCashDashboard({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
    String? employeeQuery,
    String? selectedSessionId,
  }) async {
    Query<Map<String, dynamic>> sessionsQuery = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('cashSessions')
        .where('businessDate', isGreaterThanOrEqualTo: startBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: endBusinessDate)
        .orderBy('businessDate', descending: true);

    Query<Map<String, dynamic>> withdrawalsQuery = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('cashWithdrawalRequests')
        .where('businessDate', isGreaterThanOrEqualTo: startBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: endBusinessDate)
        .orderBy('businessDate', descending: true);

    if (branchId != null && branchId.isNotEmpty) {
      sessionsQuery = sessionsQuery.where('branchId', isEqualTo: branchId);
      withdrawalsQuery = withdrawalsQuery.where(
        'branchId',
        isEqualTo: branchId,
      );
    }

    final results = await Future.wait([
      sessionsQuery.limit(100).get(),
      withdrawalsQuery.limit(200).get(),
    ]);

    var sessions = results[0].docs
        .map(CashSession.fromDoc)
        .toList(growable: false);
    final withdrawals = results[1].docs
        .map(CashWithdrawalRequest.fromDoc)
        .toList(growable: false);

    final cleanEmployee = (employeeQuery ?? '').trim().toLowerCase();
    if (cleanEmployee.isNotEmpty) {
      sessions = sessions
          .where(
            (s) =>
                s.openedByEmployeeName.toLowerCase().contains(cleanEmployee) ||
                (s.closedByEmployeeName ?? '')
                    .toLowerCase()
                    .contains(cleanEmployee),
          )
          .toList(growable: false);
    }

    CashSession? openSession;
    for (final s in sessions) {
      if (s.isOpen || s.isClosing) {
        openSession = s;
        break;
      }
    }

    CashSession? targetSession;
    if (selectedSessionId != null && selectedSessionId.isNotEmpty) {
      for (final s in sessions) {
        if (s.id == selectedSessionId) {
          targetSession = s;
          break;
        }
      }
    }
    targetSession ??= openSession ?? (sessions.isNotEmpty ? sessions.first : null);

    CashSessionDetailData? selectedDetail;
    var ordersRead = 0;
    var paymentsRead = 0;

    if (targetSession != null) {
      selectedDetail = await loadSessionDetail(
        restaurantId: restaurantId,
        session: targetSession,
        preloadedWithdrawals: withdrawals
            .where((w) => w.cashSessionId == targetSession!.id)
            .toList(growable: false),
      );
      ordersRead = selectedDetail.metrics.ordersRead;
      paymentsRead = selectedDetail.metrics.paymentsRead;
    }

    return CashDashboardData(
      sessions: sessions,
      withdrawals: withdrawals,
      openSession: openSession,
      selectedDetail: selectedDetail,
      metrics: CashReadMetrics(
        sessionsRead: results[0].docs.length,
        withdrawalsRead: results[1].docs.length,
        ordersRead: ordersRead,
        paymentsRead: paymentsRead,
      ),
    );
  }

  Future<CashSessionDetailData> loadSessionDetail({
    required String restaurantId,
    required CashSession session,
    List<CashWithdrawalRequest>? preloadedWithdrawals,
  }) async {
    final ordersSnap = await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('orders')
        .where('branchId', isEqualTo: session.branchId)
        .where('businessDate', isEqualTo: session.businessDate)
        .limit(400)
        .get();

    final orders = ordersSnap.docs
        .map(PosOrder.fromDoc)
        .where(
          (o) =>
              (o.cashSessionId ?? '').isEmpty ||
              o.cashSessionId == session.id,
        )
        .toList(growable: false);

    final withdrawals =
        preloadedWithdrawals ??
        await _fetchWithdrawalsForSession(
          restaurantId: restaurantId,
          session: session,
        );

    final payments = <Payment>[];
    var paymentsRead = 0;
    const batchSize = 15;
    final docs = ordersSnap.docs;
    for (var i = 0; i < docs.length; i += batchSize) {
      final chunk = docs.sublist(i, (i + batchSize).clamp(0, docs.length));
      final snaps = await Future.wait(
        chunk.map((doc) => doc.reference.collection('payments').get()),
      );
      for (final snap in snaps) {
        paymentsRead += snap.docs.length;
        for (final pDoc in snap.docs) {
          final payment = Payment.fromDoc(pDoc);
          final sid = (payment.cashSessionId ?? '').trim();
          if (sid == session.id || sid.isEmpty) {
            payments.add(payment);
          }
        }
      }
    }

    final summary = CashReconciliationSummary.compute(
      session: session,
      orders: orders,
      payments: payments,
      withdrawals: withdrawals,
    );

    return CashSessionDetailData(
      session: session,
      withdrawals: withdrawals,
      orders: orders,
      payments: payments,
      summary: summary,
      metrics: CashReadMetrics(
        sessionsRead: 1,
        withdrawalsRead: preloadedWithdrawals == null ? withdrawals.length : 0,
        ordersRead: ordersSnap.docs.length,
        paymentsRead: paymentsRead,
      ),
    );
  }

  Future<List<CashWithdrawalRequest>> _fetchWithdrawalsForSession({
    required String restaurantId,
    required CashSession session,
  }) async {
    final snap = await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('cashWithdrawalRequests')
        .where('businessDate', isEqualTo: session.businessDate)
        .where('branchId', isEqualTo: session.branchId)
        .limit(100)
        .get();
    return snap.docs
        .map(CashWithdrawalRequest.fromDoc)
        .where((w) => w.cashSessionId == session.id)
        .toList(growable: false);
  }
}
