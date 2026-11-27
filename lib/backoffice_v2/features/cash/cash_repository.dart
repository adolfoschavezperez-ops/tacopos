import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/reports/canonical_sales_summary.dart';
import '../../../models/cash_session.dart';
import '../../../models/cash_withdrawal_request.dart';
import '../../../models/order.dart';
import '../../../models/payment.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/preview/preview_api_client.dart';
import '../../core/read_only_guard.dart';

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
  CashRepository({
    FirebaseFirestore? firestore,
    PreviewApiClient? previewClient,
    this.isReadOnly = false,
  }) : _dbOverride = firestore,
       _previewClient = previewClient;

  final FirebaseFirestore? _dbOverride;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  final PreviewApiClient? _previewClient;
  final bool isReadOnly;

  Future<CashDashboardData> loadCashDashboard({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
    String? employeeQuery,
    String? selectedSessionId,
  }) async {
    final preview = _previewClient;
    final List<DocumentSnapshot<Map<String, dynamic>>> sessionDocs;
    final List<DocumentSnapshot<Map<String, dynamic>>> withdrawalDocs;

    if (preview != null) {
      final results = await Future.wait([
        preview.queryAllPages(
          restaurantId: restaurantId,
          collection: 'cashSessions',
          branchId: branchId,
          startBusinessDate: startBusinessDate,
          endBusinessDate: endBusinessDate,
          maxDocs: 200,
        ),
        preview.queryAllPages(
          restaurantId: restaurantId,
          collection: 'cashWithdrawalRequests',
          branchId: branchId,
          startBusinessDate: startBusinessDate,
          endBusinessDate: endBusinessDate,
          maxDocs: 300,
        ),
      ]);
      sessionDocs = results[0].docs;
      withdrawalDocs = results[1].docs;
    } else {
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
      sessionDocs = results[0].docs;
      withdrawalDocs = results[1].docs;
    }

    var sessions = sessionDocs
        .map(CashSession.fromDoc)
        .toList(growable: false);
    final withdrawals = withdrawalDocs
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
        sessionsRead: sessionDocs.length,
        withdrawalsRead: withdrawalDocs.length,
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
    final preview = _previewClient;
    final List<DocumentSnapshot<Map<String, dynamic>>> orderDocs;
    if (preview != null) {
      final res = await preview.queryAllPages(
        restaurantId: restaurantId,
        collection: 'orders',
        branchId: session.branchId,
        startBusinessDate: session.businessDate,
        endBusinessDate: session.businessDate,
        maxDocs: 400,
      );
      orderDocs = res.docs;
    } else {
      final ordersSnap = await _db
          .collection('restaurants')
          .doc(restaurantId)
          .collection('orders')
          .where('branchId', isEqualTo: session.branchId)
          .where('businessDate', isEqualTo: session.businessDate)
          .limit(400)
          .get();
      orderDocs = ordersSnap.docs;
    }

    final orders = orderDocs
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
    for (var i = 0; i < orderDocs.length; i += batchSize) {
      final chunk = orderDocs.sublist(i, (i + batchSize).clamp(0, orderDocs.length));
      if (preview != null) {
        final snaps = await Future.wait(
          chunk.map(
            (doc) => preview.queryAllPages(
              restaurantId: restaurantId,
              collection: 'orders',
              parentDocId: doc.id,
              subcollection: 'payments',
              maxDocs: 50,
            ),
          ),
        );
        for (final snap in snaps) {
          paymentsRead += snap.dataReads;
          for (final pDoc in snap.docs) {
            final payment = Payment.fromDoc(pDoc);
            final sid = (payment.cashSessionId ?? '').trim();
            if (sid == session.id || sid.isEmpty) {
              payments.add(payment);
            }
          }
        }
      } else {
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
        ordersRead: orderDocs.length,
        paymentsRead: paymentsRead,
      ),
    );
  }

  Future<List<CashWithdrawalRequest>> _fetchWithdrawalsForSession({
    required String restaurantId,
    required CashSession session,
  }) async {
    final preview = _previewClient;
    if (preview != null) {
      final res = await preview.queryAllPages(
        restaurantId: restaurantId,
        collection: 'cashWithdrawalRequests',
        branchId: session.branchId,
        startBusinessDate: session.businessDate,
        endBusinessDate: session.businessDate,
        maxDocs: 100,
      );
      return res.docs
          .map(CashWithdrawalRequest.fromDoc)
          .where((w) => w.cashSessionId == session.id)
          .toList(growable: false);
    }
    final snap = await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('cashWithdrawalRequests')
        .where('businessDate', isGreaterThanOrEqualTo: session.businessDate)
        .where('businessDate', isLessThanOrEqualTo: session.businessDate)
        .where('branchId', isEqualTo: session.branchId)
        .limit(100)
        .get();
    return snap.docs
        .map(CashWithdrawalRequest.fromDoc)
        .where((w) => w.cashSessionId == session.id)
        .toList(growable: false);
  }

  /// Registers an approved historical expense on an already-closed cash session.
  ///
  /// Throws [StateError] if the session is still open or closing to prevent
  /// concurrency collisions with the Android POS terminal.
  Future<void> addHistoricalCashExpense({
    required String restaurantId,
    required String sessionId,
    required double amount,
    required String reason,
    required String employeeId,
    required String employeeName,
  }) async {
    BackofficeReadOnlyGuard.assertWritable(
      isReadOnly: isReadOnly,
      action: 'Agregar gasto histórico en caja',
    );
    final trimmedReason = reason.trim();
    if (amount <= 0) {
      throw ArgumentError('El monto del gasto debe ser mayor a cero.');
    }
    if (trimmedReason.length < 3) {
      throw ArgumentError('Ingresa un motivo descriptivo (mínimo 3 caracteres).');
    }

    final restaurantRef = _db.collection('restaurants').doc(restaurantId);
    final sessionRef = restaurantRef.collection('cashSessions').doc(sessionId);
    final withdrawalRef = restaurantRef.collection('cashWithdrawalRequests').doc();
    final logRef = restaurantRef.collection('activityLog').doc();

    await _db.runTransaction((tx) async {
      final sessionSnap = await tx.get(sessionRef);
      if (!sessionSnap.exists) {
        throw StateError('No se encontró la sesión de caja.');
      }
      final data = sessionSnap.data() ?? const <String, dynamic>{};
      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      if (status != 'closed') {
        throw StateError(
          'Solo se pueden agregar gastos históricos en cortes cerrados.',
        );
      }

      final branchId = (data['branchId'] ?? '').toString();
      final branchName = (data['branchName'] ?? '').toString();
      final businessDate = (data['businessDate'] ?? '').toString();
      final prevApproved =
          ((data['approvedWithdrawalsTotal'] as num?) ?? 0).toDouble();
      final prevExpectedCash =
          ((data['expectedCashAmount'] as num?) ?? 0).toDouble();
      final countedCash =
          ((data['countedCashAmount'] as num?) ?? 0).toDouble();
      final cardDiff = ((data['cardDifference'] as num?) ?? 0).toDouble();

      final newApproved = prevApproved + amount;
      final newExpectedCash = prevExpectedCash - amount;
      final newCashDiff = countedCash - newExpectedCash;
      final newNetDiff = newCashDiff + cardDiff;
      final newShortage = newNetDiff < 0 ? -newNetDiff : 0.0;
      final newOver = newNetDiff > 0 ? newNetDiff : 0.0;

      tx.set(withdrawalRef, {
        'id': withdrawalRef.id,
        'restaurantId': restaurantId,
        'branchId': branchId,
        'branchName': branchName,
        'cashSessionId': sessionId,
        'businessDate': businessDate,
        'amount': amount,
        'reason': trimmedReason,
        'status': 'approved',
        'isHistorical': true,
        'source': 'historical_backoffice',
        'sourceName': 'Gasto histórico Backoffice',
        'requestedByEmployeeId': employeeId,
        'requestedByEmployeeName': employeeName,
        'authorizedByEmployeeId': employeeId,
        'authorizedByEmployeeName': employeeName,
        'approvedByEmployeeId': employeeId,
        'approvedByEmployeeName': employeeName,
        'requestedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'authorizedAt': FieldValue.serverTimestamp(),
        'approvedAt': FieldValue.serverTimestamp(),
      });

      tx.update(sessionRef, {
        'approvedWithdrawalsTotal': newApproved,
        'expectedCashAmount': newExpectedCash,
        'cashDifference': newCashDiff,
        'netDifference': newNetDiff,
        'shortageAmount': newShortage,
        'overAmount': newOver,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.set(logRef, {
        'type': 'historical_cash_expense_added',
        'restaurantId': restaurantId,
        'branchId': branchId,
        'cashSessionId': sessionId,
        'withdrawalId': withdrawalRef.id,
        'amount': amount,
        'reason': trimmedReason,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Recalculates and persists totals for an already-closed cash session.
  ///
  /// Refuses to mutate open/closing sessions to avoid race conditions with POS.
  Future<void> recalculateClosedCashSession({
    required String restaurantId,
    required String sessionId,
    required CashReconciliationSummary summary,
    required String employeeId,
    required String employeeName,
  }) async {
    BackofficeReadOnlyGuard.assertWritable(
      isReadOnly: isReadOnly,
      action: 'Recalcular corte de caja cerrado',
    );
    final restaurantRef = _db.collection('restaurants').doc(restaurantId);
    final sessionRef = restaurantRef.collection('cashSessions').doc(sessionId);
    final logRef = restaurantRef.collection('activityLog').doc();

    await _db.runTransaction((tx) async {
      final sessionSnap = await tx.get(sessionRef);
      if (!sessionSnap.exists) {
        throw StateError('No se encontró la sesión de caja.');
      }
      final data = sessionSnap.data() ?? const <String, dynamic>{};
      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      if (status != 'closed') {
        throw StateError(
          'Solo se pueden recalcular cortes de caja cerrados.',
        );
      }

      final branchId = (data['branchId'] ?? '').toString();
      tx.update(sessionRef, {
        'expectedCashAmount': summary.expectedCashInDrawer,
        'expectedCardChargedAmount': summary.cardCollected,
        'expectedPlatformAmount': summary.platformCollected,
        'approvedWithdrawalsTotal': summary.approvedWithdrawalsTotal,
        'pendingWithdrawalsTotal': summary.pendingWithdrawalsTotal,
        'cashDifference': summary.cashDifference,
        'cardDifference': summary.cardDifference,
        'netDifference': summary.netDifference,
        'shortageAmount': summary.shortageAmount,
        'overAmount': summary.overAmount,
        'totalExpectedRealMoney': summary.totalExpectedRealMoney,
        'totalCountedRealMoney': summary.totalCountedRealMoney,
        'recalculatedAt': FieldValue.serverTimestamp(),
        'recalculatedByEmployeeId': employeeId,
        'recalculatedByEmployeeName': employeeName,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.set(logRef, {
        'type': 'historical_cash_correction',
        'restaurantId': restaurantId,
        'branchId': branchId,
        'cashSessionId': sessionId,
        'expectedCashAmount': summary.expectedCashInDrawer,
        'netDifference': summary.netDifference,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
