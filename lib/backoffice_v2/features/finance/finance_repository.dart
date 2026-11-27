import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/expenses/expense_policy.dart';
import '../../../core/reports/canonical_sales_summary.dart';
import '../../../models/cash_session.dart';
import '../../../models/cash_withdrawal_request.dart';
import '../../../models/kitchen_session.dart';
import '../../../models/order.dart';
import '../../../models/order_item.dart';
import '../../../models/payment.dart';
import '../../../models/purchase_models.dart';
import '../../../models/yield_profit_models.dart';
import '../../core/adapters/sales_adapter.dart';
import 'finance_analytics.dart';

class FinanceDashboardBundle {
  const FinanceDashboardBundle({
    required this.summary,
    required this.previousSummary,
    required this.orders,
    required this.withdrawals,
    required this.purchases,
    required this.supplierPayments,
    required this.productProfitability,
    required this.efficiencyMetrics,
    required this.partnerSummary,
    required this.partners,
    required this.partnerContributions,
    required this.expensePolicySettings,
    required this.expensePolicies,
    required this.savedTargets,
    required this.salesTargetAmount,
    required this.expenseBudgetAmount,
    required this.readCount,
  });

  final FinancePeriodSummary summary;
  final FinancePeriodSummary previousSummary;
  final List<PosOrder> orders;
  final List<CashWithdrawalRequest> withdrawals;
  final List<SupplierPurchase> purchases;
  final List<SupplierPayment> supplierPayments;
  final List<ProductProfitabilityRow> productProfitability;
  final List<EfficiencyMetricRow> efficiencyMetrics;
  final PartnerFinanceSummary partnerSummary;
  final List<Partner> partners;
  final List<PartnerContribution> partnerContributions;
  final ExpensePolicySettings expensePolicySettings;
  final List<ExpensePolicy> expensePolicies;
  final Map<String, double> savedTargets;
  final double? salesTargetAmount;
  final double? expenseBudgetAmount;
  final int readCount;
}

class FinanceRepository {
  FinanceRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<FinanceDashboardBundle> loadFinanceDashboard({
    required String restaurantId,
    required DateTime startDate,
    required DateTime endDate,
    String? branchId,
  }) async {
    final startStr = BackofficeSalesAdapter.formatBusinessDate(startDate);
    final endStr = BackofficeSalesAdapter.formatBusinessDate(endDate);

    final daysSpan = endDate.difference(startDate).inDays + 1;
    final prevEnd = startDate.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(Duration(days: daysSpan - 1));
    final prevStartStr = BackofficeSalesAdapter.formatBusinessDate(prevStart);
    final prevEndStr = BackofficeSalesAdapter.formatBusinessDate(prevEnd);

    final restRef = _db.collection('restaurants').doc(restaurantId);

    Query<Map<String, dynamic>> boundedByDate(
      String collection, {
      String dateField = 'businessDate',
      required String from,
      required String to,
      int limit = 300,
    }) {
      return restRef
          .collection(collection)
          .where(dateField, isGreaterThanOrEqualTo: from)
          .where(dateField, isLessThanOrEqualTo: to)
          .orderBy(dateField, descending: true)
          .limit(limit);
    }

    final results = await Future.wait([
      boundedByDate('orders', from: startStr, to: endStr, limit: 400).get(),
      boundedByDate('orders', from: prevStartStr, to: prevEndStr, limit: 400)
          .get(),
      boundedByDate('cashSessions', from: startStr, to: endStr, limit: 100)
          .get(),
      boundedByDate(
        'cashSessions',
        from: prevStartStr,
        to: prevEndStr,
        limit: 100,
      ).get(),
      boundedByDate(
        'cashWithdrawalRequests',
        from: startStr,
        to: endStr,
        limit: 200,
      ).get(),
      boundedByDate(
        'cashWithdrawalRequests',
        from: prevStartStr,
        to: prevEndStr,
        limit: 200,
      ).get(),
      boundedByDate(
        'supplierPurchases',
        from: startStr,
        to: endStr,
        limit: 200,
      ).get(),
      boundedByDate(
        'supplierPurchases',
        from: prevStartStr,
        to: prevEndStr,
        limit: 200,
      ).get(),
      boundedByDate(
        'supplierPayments',
        from: startStr,
        to: endStr,
        limit: 200,
      ).get(),
      restRef.collection('partners').limit(50).get(),
      boundedByDate(
        'partnerContributions',
        dateField: 'date',
        from: startStr,
        to: endStr,
        limit: 150,
      ).get(),
      restRef.collection('productRecipes').limit(200).get(),
      restRef.collection('ingredientYieldProfiles').limit(100).get(),
      restRef.collection('expensePolicies').limit(50).get(),
      restRef.collection('settings').doc('expensePolicies').get(),
      restRef.collection('kitchenSessions')
          .where('businessDate', isGreaterThanOrEqualTo: startStr)
          .where('businessDate', isLessThanOrEqualTo: endStr)
          .limit(40)
          .get(),
      restRef.collection('backofficePurchaseTargets').limit(50).get(),
      restRef.collection('backofficeFinanceBudgets').limit(50).get(),
    ]);

    var readCount = 0;
    for (final r in results) {
      if (r is QuerySnapshot) {
        readCount += r.docs.length;
      } else {
        readCount += 1;
      }
    }

    bool matchesBranch(String docBranch) =>
        branchId == null || branchId.isEmpty || docBranch == branchId;

    final orders = (results[0] as QuerySnapshot<Map<String, dynamic>>).docs
        .map(PosOrder.fromDoc)
        .where((o) => matchesBranch(o.branchId))
        .toList(growable: false);
    final prevOrders = (results[1] as QuerySnapshot<Map<String, dynamic>>).docs
        .map(PosOrder.fromDoc)
        .where((o) => matchesBranch(o.branchId))
        .toList(growable: false);

    final cashSessions =
        (results[2] as QuerySnapshot<Map<String, dynamic>>).docs
            .map(CashSession.fromDoc)
            .where((s) => matchesBranch(s.branchId))
            .toList(growable: false);
    final prevCashSessions =
        (results[3] as QuerySnapshot<Map<String, dynamic>>).docs
            .map(CashSession.fromDoc)
            .where((s) => matchesBranch(s.branchId))
            .toList(growable: false);

    final withdrawals =
        (results[4] as QuerySnapshot<Map<String, dynamic>>).docs
            .map(CashWithdrawalRequest.fromDoc)
            .where((w) => matchesBranch(w.branchId))
            .toList(growable: false);
    final prevWithdrawals =
        (results[5] as QuerySnapshot<Map<String, dynamic>>).docs
            .map(CashWithdrawalRequest.fromDoc)
            .where((w) => matchesBranch(w.branchId))
            .toList(growable: false);

    final purchases = (results[6] as QuerySnapshot<Map<String, dynamic>>).docs
        .map(SupplierPurchase.fromDoc)
        .where((p) => matchesBranch(p.branchId))
        .toList(growable: false);
    final prevPurchases =
        (results[7] as QuerySnapshot<Map<String, dynamic>>).docs
            .map(SupplierPurchase.fromDoc)
            .where((p) => matchesBranch(p.branchId))
            .toList(growable: false);

    final supplierPayments =
        (results[8] as QuerySnapshot<Map<String, dynamic>>).docs
            .map(SupplierPayment.fromDoc)
            .where((p) => matchesBranch(p.branchId))
            .toList(growable: false);

    final partners = (results[9] as QuerySnapshot<Map<String, dynamic>>).docs
        .map(Partner.fromDoc)
        .toList(growable: false);

    final contributions =
        (results[10] as QuerySnapshot<Map<String, dynamic>>).docs
            .map(PartnerContribution.fromDoc)
            .where((c) => matchesBranch(c.branchId))
            .toList(growable: false);

    final recipes = (results[11] as QuerySnapshot<Map<String, dynamic>>).docs
        .map(TheoreticalProductRecipe.fromDoc)
        .toList(growable: false);

    final yieldProfiles =
        (results[12] as QuerySnapshot<Map<String, dynamic>>).docs
            .map(IngredientYieldProfile.fromDoc)
            .toList(growable: false);

    final expensePolicies =
        (results[13] as QuerySnapshot<Map<String, dynamic>>).docs
            .map((d) => ExpensePolicy.fromMap(d.id, d.data()))
            .toList(growable: false);

    final settingsSnap = results[14] as DocumentSnapshot<Map<String, dynamic>>;
    final expensePolicySettings = settingsSnap.exists
        ? ExpensePolicySettings.fromMap(settingsSnap.data())
        : const ExpensePolicySettings();

    final kitchenSessions =
        (results[15] as QuerySnapshot<Map<String, dynamic>>).docs
            .map(KitchenSession.fromDoc)
            .where((s) => matchesBranch(s.branchId))
            .toList(growable: false);

    final savedTargets = <String, double>{};
    for (final doc
        in (results[16] as QuerySnapshot<Map<String, dynamic>>).docs) {
      final d = doc.data();
      final b = (d['branchId'] ?? '').toString();
      if (!matchesBranch(b)) continue;
      final cat = (d['category'] ?? '').toString();
      final val = (d['targetPer100Sales'] as num?)?.toDouble();
      if (cat.isNotEmpty && val != null) savedTargets[cat] = val;
    }

    double? salesTargetAmount;
    double? expenseBudgetAmount;
    for (final doc
        in (results[17] as QuerySnapshot<Map<String, dynamic>>).docs) {
      final d = doc.data();
      final b = (d['branchId'] ?? '').toString();
      if (!matchesBranch(b)) continue;
      final key = (d['budgetType'] ?? '').toString();
      final val = (d['amount'] as num?)?.toDouble();
      if (key == 'sales_target' && val != null) salesTargetAmount = val;
      if (key == 'expense_budget' && val != null) expenseBudgetAmount = val;
    }

    // Load order items & payments for active orders (bounded batches) & purchase items for COGS
    final activeOrders = orders
        .where((o) => !isCanonicalCancelledOrder(o))
        .take(120)
        .toList(growable: false);
    final activePurchases = purchases
        .where((p) => p.status.trim().toLowerCase() != 'cancelled')
        .take(60)
        .toList(growable: false);

    final itemsByOrder = await _fetchOrderItemSubcollections(
      restRef,
      activeOrders,
    );
    final paymentsByOrder = await _fetchOrderPaymentSubcollections(
      restRef,
      activeOrders,
    );
    final purchaseItemSnaps = await _fetchPurchaseItemSubcollections(
      restRef,
      activePurchases,
    );
    final allOrderItems = itemsByOrder.values
        .expand((list) => list)
        .toList(growable: false);
    readCount +=
        allOrderItems.length +
        paymentsByOrder.values.fold<int>(0, (a, b) => a + b.length) +
        purchaseItemSnaps.length;

    final kitchenItems = <KitchenSessionItem>[];
    for (final ks in kitchenSessions.take(10)) {
      final snap = await restRef
          .collection('kitchenSessions')
          .doc(ks.id)
          .collection('items')
          .limit(60)
          .get();
      readCount += snap.docs.length;
      kitchenItems.addAll(snap.docs.map(KitchenSessionItem.fromDoc));
    }

    final productSales = _aggregateProductSales(allOrderItems);
    final ingredientCosts = resolveIngredientCosts(
      periodPurchaseItems: purchaseItemSnaps,
      historicalPurchaseItems: const [],
    );
    final productProfitability = buildProductProfitabilityReport(
      sales: productSales,
      recipes: recipes,
      yieldProfiles: yieldProfiles,
      ingredientCosts: ingredientCosts,
    );

    final summary = FinancePeriodSummary.compute(
      orders: orders,
      itemsByOrder: itemsByOrder,
      paymentsByOrder: paymentsByOrder,
      cashSessions: cashSessions,
      withdrawals: withdrawals,
      purchases: purchases,
      supplierPayments: supplierPayments,
      partnerContributions: contributions,
      productProfitability: productProfitability,
    );

    final previousSummary = FinancePeriodSummary.compute(
      orders: prevOrders,
      cashSessions: prevCashSessions,
      withdrawals: prevWithdrawals,
      purchases: prevPurchases,
      supplierPayments: const [],
      partnerContributions: const [],
      productProfitability: const [],
    );

    final efficiencyMetrics = buildEfficiencyComparisons(
      summary: summary,
      kitchenItems: kitchenItems,
      targetsByKey: savedTargets,
    );

    final partnerSummary = buildPartnerFinanceSummary(
      partners: partners,
      supplierPayments: supplierPayments,
      contributions: contributions,
      distributableBase: summary.operatingCashFlow,
    );

    return FinanceDashboardBundle(
      summary: summary,
      previousSummary: previousSummary,
      orders: orders,
      withdrawals: withdrawals,
      purchases: purchases,
      supplierPayments: supplierPayments,
      productProfitability: productProfitability,
      efficiencyMetrics: efficiencyMetrics,
      partnerSummary: partnerSummary,
      partners: partners,
      partnerContributions: contributions,
      expensePolicySettings: expensePolicySettings,
      expensePolicies: expensePolicies,
      savedTargets: savedTargets,
      salesTargetAmount: salesTargetAmount,
      expenseBudgetAmount: expenseBudgetAmount,
      readCount: readCount,
    );
  }

  Future<Map<String, List<OrderItem>>> _fetchOrderItemSubcollections(
    DocumentReference<Map<String, dynamic>> restRef,
    List<PosOrder> orders,
  ) async {
    final out = <String, List<OrderItem>>{};
    for (var i = 0; i < orders.length; i += 20) {
      final chunk = orders.sublist(i, (i + 20).clamp(0, orders.length));
      final snaps = await Future.wait(
        chunk.map(
          (o) => restRef.collection('orders').doc(o.id).collection('items').get(),
        ),
      );
      for (var j = 0; j < chunk.length; j++) {
        out[chunk[j].id] = snaps[j].docs
            .map(OrderItem.fromDoc)
            .where(
              (item) =>
                  item.status.trim().toLowerCase() != 'cancelled' &&
                  item.cancelStatus.trim().toLowerCase() != 'cancelled',
            )
            .toList(growable: false);
      }
    }
    return out;
  }

  Future<Map<String, List<Payment>>> _fetchOrderPaymentSubcollections(
    DocumentReference<Map<String, dynamic>> restRef,
    List<PosOrder> orders,
  ) async {
    final out = <String, List<Payment>>{};
    for (var i = 0; i < orders.length; i += 20) {
      final chunk = orders.sublist(i, (i + 20).clamp(0, orders.length));
      final snaps = await Future.wait(
        chunk.map(
          (o) =>
              restRef.collection('orders').doc(o.id).collection('payments').get(),
        ),
      );
      for (var j = 0; j < chunk.length; j++) {
        out[chunk[j].id] =
            snaps[j].docs.map(Payment.fromDoc).toList(growable: false);
      }
    }
    return out;
  }

  Future<List<SupplierPurchaseItem>> _fetchPurchaseItemSubcollections(
    DocumentReference<Map<String, dynamic>> restRef,
    List<SupplierPurchase> purchases,
  ) async {
    final out = <SupplierPurchaseItem>[];
    for (var i = 0; i < purchases.length; i += 20) {
      final chunk = purchases.sublist(i, (i + 20).clamp(0, purchases.length));
      final snaps = await Future.wait(
        chunk.map(
          (p) => restRef
              .collection('supplierPurchases')
              .doc(p.id)
              .collection('items')
              .get(),
        ),
      );
      for (final s in snaps) {
        out.addAll(s.docs.map(SupplierPurchaseItem.fromDoc));
      }
    }
    return out;
  }

  List<ProductSaleAggregate> _aggregateProductSales(List<OrderItem> items) {
    final map = <String, _MutableProductSale>{};
    for (final item in items) {
      final isCancelled =
          item.status.trim().toLowerCase() == 'cancelled' ||
          item.cancelStatus.trim().toLowerCase() == 'cancelled';
      if (isCancelled || item.qty <= 0) continue;
      final key = item.productId.trim().isNotEmpty
          ? item.productId.trim()
          : item.productName.trim();
      final bucket = map.putIfAbsent(
        key,
        () => _MutableProductSale(
          productId: key,
          productName: item.productName,
          categoryName: item.category.isNotEmpty ? item.category : 'General',
        ),
      );
      bucket.units += item.qty.toDouble();
      bucket.revenue += item.total;
    }
    return map.values
        .map(
          (v) => ProductSaleAggregate(
            productId: v.productId,
            productName: v.productName,
            categoryName: v.categoryName,
            unitsSold: v.units,
            netRevenue: v.revenue,
          ),
        )
        .toList(growable: false);
  }

  Future<void> savePartner({
    required String restaurantId,
    String? partnerId,
    required String name,
    required double ownershipPercent,
    String phone = '',
    String notes = '',
    bool active = true,
  }) async {
    final col = _db.collection('restaurants').doc(restaurantId).collection('partners');
    final ref = partnerId != null && partnerId.isNotEmpty
        ? col.doc(partnerId)
        : col.doc();
    await ref.set({
      'id': ref.id,
      'restaurantId': restaurantId,
      'name': name.trim(),
      'ownershipPercent': ownershipPercent.clamp(0.0, 100.0),
      'phone': phone.trim(),
      'notes': notes.trim(),
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
      if (partnerId == null || partnerId.isEmpty)
        'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> registerPartnerContribution({
    required String restaurantId,
    required String branchId,
    required String partnerId,
    required String partnerName,
    required String businessDate,
    required double amount,
    required String method,
    String reference = '',
    String notes = '',
    required String employeeId,
    required String employeeName,
  }) async {
    if (amount <= 0) throw ArgumentError('El monto debe ser mayor a cero.');
    final restRef = _db.collection('restaurants').doc(restaurantId);
    final ref = restRef.collection('partnerContributions').doc();
    final logRef = restRef.collection('activityLog').doc();

    final batch = _db.batch();
    batch.set(ref, {
      'id': ref.id,
      'restaurantId': restaurantId,
      'branchId': branchId,
      'partnerId': partnerId,
      'partnerName': partnerName,
      'date': businessDate,
      'amount': amount,
      'method': method,
      'reference': reference.trim(),
      'notes': notes.trim(),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'createdByEmployeeId': employeeId,
      'createdByEmployeeName': employeeName,
    });
    batch.set(logRef, {
      'type': 'partner_contribution_created',
      'restaurantId': restaurantId,
      'branchId': branchId,
      'contributionId': ref.id,
      'partnerId': partnerId,
      'amount': amount,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> saveExpensePolicySettings({
    required String restaurantId,
    required ExpensePolicySettings settings,
    required String employeeId,
    required String employeeName,
  }) async {
    final restRef = _db.collection('restaurants').doc(restaurantId);
    final ref = restRef.collection('settings').doc('expensePolicies');
    await ref.set({
      'expensePoliciesEnabled': settings.expensePoliciesEnabled,
      'expensePolicyMode': settings.expensePolicyMode.name,
      'manualApprovalCutoffEnabled': settings.manualApprovalCutoffEnabled,
      'manualApprovalCutoffTime': settings.manualApprovalCutoffTime,
      'defaultReceiptRequired': settings.defaultReceiptRequired,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmployeeId': employeeId,
      'updatedByEmployeeName': employeeName,
    }, SetOptions(merge: true));
  }

  Future<void> saveExpensePolicy({
    required String restaurantId,
    required ExpensePolicy policy,
    required String employeeId,
    required String employeeName,
  }) async {
    final col = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('expensePolicies');
    final isNew = policy.id.trim().isEmpty;
    final ref = isNew ? col.doc() : col.doc(policy.id.trim());
    await ref.set({
      ...policy.toMap(),
      'id': ref.id,
      'restaurantId': restaurantId,
      'policyVersion': isNew ? 1 : policy.policyVersion + 1,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': employeeName,
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      if (isNew) 'createdBy': employeeName,
    }, SetOptions(merge: true));
  }

  /// Persists additive DEV-only efficiency target (`backofficePurchaseTargets`).
  Future<void> saveEfficiencyTarget({
    required String restaurantId,
    required String branchId,
    required String categoryKey,
    required double targetPer100Sales,
    required String employeeId,
    required String employeeName,
  }) async {
    final docId = '${branchId}_$categoryKey';
    await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('backofficePurchaseTargets')
        .doc(docId)
        .set({
          'restaurantId': restaurantId,
          'branchId': branchId,
          'category': categoryKey,
          'targetPer100Sales': targetPer100Sales,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedByEmployeeId': employeeId,
          'updatedByEmployeeName': employeeName,
        }, SetOptions(merge: true));
  }

  /// Persists additive DEV-only finance budget (`backofficeFinanceBudgets`).
  Future<void> saveFinanceBudget({
    required String restaurantId,
    required String branchId,
    required String budgetType,
    required double amount,
    required String periodLabel,
    required String employeeId,
    required String employeeName,
  }) async {
    final docId = '${branchId}_$budgetType';
    await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('backofficeFinanceBudgets')
        .doc(docId)
        .set({
          'restaurantId': restaurantId,
          'branchId': branchId,
          'budgetType': budgetType,
          'amount': amount,
          'periodLabel': periodLabel,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedByEmployeeId': employeeId,
          'updatedByEmployeeName': employeeName,
        }, SetOptions(merge: true));
  }
}

class _MutableProductSale {
  _MutableProductSale({
    required this.productId,
    required this.productName,
    required this.categoryName,
  });

  final String productId;
  final String productName;
  final String categoryName;
  double units = 0;
  double revenue = 0;
}
