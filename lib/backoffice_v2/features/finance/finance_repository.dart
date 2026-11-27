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
import '../../core/cache/backoffice_cache_scope.dart';
import '../../core/preview/preview_api_client.dart';
import '../../core/read_only_guard.dart';
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
    this.isPartial = false,
    this.partialNote,
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
  final bool isPartial;
  final String? partialNote;
}

class FinanceRepository {
  FinanceRepository({
    FirebaseFirestore? firestore,
    BackofficeCacheScope? cacheScope,
    PreviewApiClient? previewClient,
    this.isReadOnly = false,
  }) : _dbOverride = firestore,
       _cacheScope = cacheScope ?? BackofficeCacheScope(),
       _previewClient = previewClient {
    _cacheScope.registerInvalidator(invalidateCache);
  }

  final FirebaseFirestore? _dbOverride;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  final BackofficeCacheScope _cacheScope;
  final PreviewApiClient? _previewClient;
  final bool isReadOnly;
  final Map<String, _CachedFinanceBundle> _bundleCache = {};

  void invalidateCache() => _bundleCache.clear();

  /// Fetches all matching documents using Firestore cursors (`startAfterDocument`)
  /// up to [maxDocs], explicitly flagging truncation instead of silently dropping data.
  Future<({List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, bool hitLimit})>
  _fetchAllWithCursor(
    Query<Map<String, dynamic>> baseQuery, {
    int pageSize = 400,
    int maxDocs = 3000,
  }) async {
    final collected = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? lastDoc;
    var hitLimit = false;

    while (collected.length < maxDocs) {
      var q = baseQuery.limit(pageSize);
      if (lastDoc != null) {
        q = q.startAfterDocument(lastDoc);
      }
      final snap = await q.get();
      if (snap.docs.isEmpty) break;
      collected.addAll(snap.docs);
      lastDoc = snap.docs.last;
      if (snap.docs.length < pageSize) break;
      if (collected.length >= maxDocs) {
        hitLimit = true;
        break;
      }
    }
    return (docs: collected, hitLimit: hitLimit);
  }

  Future<FinanceDashboardBundle> loadFinanceDashboard({
    required String restaurantId,
    required DateTime startDate,
    required DateTime endDate,
    String? branchId,
    String cacheUserScope = '',
    bool forceRefresh = false,
  }) async {
    final startStr = BackofficeSalesAdapter.formatBusinessDate(startDate);
    final endStr = BackofficeSalesAdapter.formatBusinessDate(endDate);
    final requestEpoch = _cacheScope.epoch;
    final cacheKey = _cacheScope.buildScopedKey('finance', [
      restaurantId,
      startStr,
      endStr,
      branchId ?? 'all',
      cacheUserScope,
    ]);
    final cached = _bundleCache[cacheKey];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.cachedAt) <
            const Duration(seconds: 60)) {
      return cached.bundle;
    }

    final daysSpan = endDate.difference(startDate).inDays + 1;
    final prevEnd = startDate.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(Duration(days: daysSpan - 1));
    final prevStartStr = BackofficeSalesAdapter.formatBusinessDate(prevStart);
    final prevEndStr = BackofficeSalesAdapter.formatBusinessDate(prevEnd);

    final preview = _previewClient;
    final restRef = preview == null
        ? _db.collection('restaurants').doc(restaurantId)
        : null;

    Query<Map<String, dynamic>> boundedByDate(
      String collection, {
      String dateField = 'businessDate',
      required String from,
      required String to,
      int limit = 300,
    }) {
      return restRef!
          .collection(collection)
          .where(dateField, isGreaterThanOrEqualTo: from)
          .where(dateField, isLessThanOrEqualTo: to)
          .orderBy(dateField, descending: true)
          .limit(limit);
    }
    late final List<DocumentSnapshot<Map<String, dynamic>>> ordersDocs;
    late final List<DocumentSnapshot<Map<String, dynamic>>> prevOrdersDocs;
    late final List<DocumentSnapshot<Map<String, dynamic>>> cashDocs;
    late final List<DocumentSnapshot<Map<String, dynamic>>> prevCashDocs;
    late final List<DocumentSnapshot<Map<String, dynamic>>> withdrawalDocs;
    late final List<DocumentSnapshot<Map<String, dynamic>>> prevWithdrawalDocs;
    late final List<DocumentSnapshot<Map<String, dynamic>>> purchaseDocs;
    late final List<DocumentSnapshot<Map<String, dynamic>>> prevPurchaseDocs;
    late final List<DocumentSnapshot<Map<String, dynamic>>> supplierPaymentDocs;
    late final List<DocumentSnapshot<Map<String, dynamic>>> partnerDocs;
    late final List<DocumentSnapshot<Map<String, dynamic>>> contributionDocs;
    late final List<DocumentSnapshot<Map<String, dynamic>>> recipeDocs;
    late final List<DocumentSnapshot<Map<String, dynamic>>> yieldDocs;
    late final List<DocumentSnapshot<Map<String, dynamic>>> policyDocs;
    late final DocumentSnapshot<Map<String, dynamic>>? policySettingsDoc;
    late final List<DocumentSnapshot<Map<String, dynamic>>> kitchenDocs;
    late final List<DocumentSnapshot<Map<String, dynamic>>> targetDocs;
    late final List<DocumentSnapshot<Map<String, dynamic>>> budgetDocs;
    var hitLimit = false;
    var readCount = 0;

    if (preview != null) {
      final pResults = await Future.wait([
        preview.queryAllPages(restaurantId: restaurantId, collection: 'orders', branchId: branchId, startBusinessDate: startStr, endBusinessDate: endStr, maxDocs: 3000),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'orders', branchId: branchId, startBusinessDate: prevStartStr, endBusinessDate: prevEndStr, maxDocs: 3000),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'cashSessions', branchId: branchId, startBusinessDate: startStr, endBusinessDate: endStr, maxDocs: 200),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'cashSessions', branchId: branchId, startBusinessDate: prevStartStr, endBusinessDate: prevEndStr, maxDocs: 200),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'cashWithdrawalRequests', branchId: branchId, startBusinessDate: startStr, endBusinessDate: endStr, maxDocs: 200),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'cashWithdrawalRequests', branchId: branchId, startBusinessDate: prevStartStr, endBusinessDate: prevEndStr, maxDocs: 200),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'supplierPurchases', branchId: branchId, startBusinessDate: startStr, endBusinessDate: endStr, maxDocs: 200),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'supplierPurchases', branchId: branchId, startBusinessDate: prevStartStr, endBusinessDate: prevEndStr, maxDocs: 200),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'supplierPayments', branchId: branchId, startBusinessDate: startStr, endBusinessDate: endStr, maxDocs: 200),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'partners', maxDocs: 50),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'partnerContributions', branchId: branchId, maxDocs: 150),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'productRecipes', maxDocs: 200),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'ingredientYieldProfiles', maxDocs: 100),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'expensePolicies', maxDocs: 50),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'kitchenSessions', branchId: branchId, startBusinessDate: startStr, endBusinessDate: endStr, maxDocs: 40),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'backofficePurchaseTargets', maxDocs: 50),
        preview.queryAllPages(restaurantId: restaurantId, collection: 'backofficeFinanceBudgets', maxDocs: 50),
      ]);
      policySettingsDoc = await preview.fetchDoc(
        restaurantId: restaurantId,
        collection: 'settings',
        docId: 'expensePolicies',
      );
      ordersDocs = pResults[0].docs;
      prevOrdersDocs = pResults[1].docs;
      cashDocs = pResults[2].docs;
      prevCashDocs = pResults[3].docs;
      withdrawalDocs = pResults[4].docs;
      prevWithdrawalDocs = pResults[5].docs;
      purchaseDocs = pResults[6].docs;
      prevPurchaseDocs = pResults[7].docs;
      supplierPaymentDocs = pResults[8].docs;
      partnerDocs = pResults[9].docs;
      contributionDocs = pResults[10].docs;
      recipeDocs = pResults[11].docs;
      yieldDocs = pResults[12].docs;
      policyDocs = pResults[13].docs;
      kitchenDocs = pResults[14].docs;
      targetDocs = pResults[15].docs;
      budgetDocs = pResults[16].docs;
      hitLimit = pResults[0].isPartial || pResults[1].isPartial;
      readCount = pResults.fold<int>(1, (a, r) => a + r.dataReads);
    } else {
      final ordersCursorFuture = _fetchAllWithCursor(
        boundedByDate('orders', from: startStr, to: endStr),
      );
      final prevOrdersCursorFuture = _fetchAllWithCursor(
        boundedByDate('orders', from: prevStartStr, to: prevEndStr),
      );

      final results = await Future.wait([
        ordersCursorFuture,
        prevOrdersCursorFuture,
        boundedByDate('cashSessions', from: startStr, to: endStr, limit: 200)
            .get(),
        boundedByDate(
          'cashSessions',
          from: prevStartStr,
          to: prevEndStr,
          limit: 200,
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
        restRef!.collection('partners').limit(50).get(),
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

      final ordersCursor =
          results[0]
              as ({
                List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
                bool hitLimit,
              });
      final prevOrdersCursor =
          results[1]
              as ({
                List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
                bool hitLimit,
              });

      readCount = ordersCursor.docs.length + prevOrdersCursor.docs.length;
      for (var idx = 2; idx < results.length; idx++) {
        final r = results[idx];
        if (r is QuerySnapshot) {
          readCount += r.docs.length;
        } else {
          readCount += 1;
        }
      }
      ordersDocs = ordersCursor.docs;
      prevOrdersDocs = prevOrdersCursor.docs;
      cashDocs = (results[2] as QuerySnapshot<Map<String, dynamic>>).docs;
      prevCashDocs = (results[3] as QuerySnapshot<Map<String, dynamic>>).docs;
      withdrawalDocs = (results[4] as QuerySnapshot<Map<String, dynamic>>).docs;
      prevWithdrawalDocs = (results[5] as QuerySnapshot<Map<String, dynamic>>).docs;
      purchaseDocs = (results[6] as QuerySnapshot<Map<String, dynamic>>).docs;
      prevPurchaseDocs = (results[7] as QuerySnapshot<Map<String, dynamic>>).docs;
      supplierPaymentDocs = (results[8] as QuerySnapshot<Map<String, dynamic>>).docs;
      partnerDocs = (results[9] as QuerySnapshot<Map<String, dynamic>>).docs;
      contributionDocs = (results[10] as QuerySnapshot<Map<String, dynamic>>).docs;
      recipeDocs = (results[11] as QuerySnapshot<Map<String, dynamic>>).docs;
      yieldDocs = (results[12] as QuerySnapshot<Map<String, dynamic>>).docs;
      policyDocs = (results[13] as QuerySnapshot<Map<String, dynamic>>).docs;
      policySettingsDoc = results[14] as DocumentSnapshot<Map<String, dynamic>>;
      kitchenDocs = (results[15] as QuerySnapshot<Map<String, dynamic>>).docs;
      targetDocs = (results[16] as QuerySnapshot<Map<String, dynamic>>).docs;
      budgetDocs = (results[17] as QuerySnapshot<Map<String, dynamic>>).docs;
      hitLimit = ordersCursor.hitLimit || prevOrdersCursor.hitLimit;
    }

    bool matchesBranch(String docBranch) =>
        branchId == null || branchId.isEmpty || docBranch == branchId;

    final orders = ordersDocs
        .map(PosOrder.fromDoc)
        .where((o) => matchesBranch(o.branchId))
        .toList(growable: false);
    final prevOrders = prevOrdersDocs
        .map(PosOrder.fromDoc)
        .where((o) => matchesBranch(o.branchId))
        .toList(growable: false);

    final cashSessions = cashDocs
        .map(CashSession.fromDoc)
        .where((s) => matchesBranch(s.branchId))
        .toList(growable: false);
    final prevCashSessions = prevCashDocs
        .map(CashSession.fromDoc)
        .where((s) => matchesBranch(s.branchId))
        .toList(growable: false);

    final withdrawals = withdrawalDocs
        .map(CashWithdrawalRequest.fromDoc)
        .where((w) => matchesBranch(w.branchId))
        .toList(growable: false);
    final prevWithdrawals = prevWithdrawalDocs
        .map(CashWithdrawalRequest.fromDoc)
        .where((w) => matchesBranch(w.branchId))
        .toList(growable: false);

    final purchases = purchaseDocs
        .map(SupplierPurchase.fromDoc)
        .where((p) => matchesBranch(p.branchId))
        .toList(growable: false);
    final prevPurchases = prevPurchaseDocs
        .map(SupplierPurchase.fromDoc)
        .where((p) => matchesBranch(p.branchId))
        .toList(growable: false);

    final supplierPayments = supplierPaymentDocs
        .map(SupplierPayment.fromDoc)
        .where((p) => matchesBranch(p.branchId))
        .toList(growable: false);

    final partners = partnerDocs
        .map(Partner.fromDoc)
        .toList(growable: false);

    final contributions = contributionDocs
        .map(PartnerContribution.fromDoc)
        .where((c) => matchesBranch(c.branchId))
        .toList(growable: false);

    final recipes = recipeDocs
        .map(TheoreticalProductRecipe.fromDoc)
        .toList(growable: false);

    final yieldProfiles = yieldDocs
        .map(IngredientYieldProfile.fromDoc)
        .toList(growable: false);

    final expensePolicies = policyDocs
        .map((d) => ExpensePolicy.fromMap(d.id, d.data() ?? const {}))
        .toList(growable: false);

    final expensePolicySettings =
        policySettingsDoc != null && policySettingsDoc.exists
        ? ExpensePolicySettings.fromMap(policySettingsDoc.data())
        : const ExpensePolicySettings();

    final kitchenSessions = kitchenDocs
        .map(KitchenSession.fromDoc)
        .where((s) => matchesBranch(s.branchId))
        .toList(growable: false);

    final savedTargets = <String, double>{};
    for (final doc in targetDocs) {
      final d = doc.data() ?? const {};
      final b = (d['branchId'] ?? '').toString();
      if (!matchesBranch(b)) continue;
      final cat = (d['category'] ?? '').toString();
      final val = (d['targetPer100Sales'] as num?)?.toDouble();
      if (cat.isNotEmpty && val != null) savedTargets[cat] = val;
    }

    double? salesTargetAmount;
    double? expenseBudgetAmount;
    for (final doc in budgetDocs) {
      final d = doc.data() ?? const {};
      final b = (d['branchId'] ?? '').toString();
      if (!matchesBranch(b)) continue;
      final key = (d['budgetType'] ?? '').toString();
      final val = (d['amount'] as num?)?.toDouble();
      if (key == 'sales_target' && val != null) salesTargetAmount = val;
      if (key == 'expense_budget' && val != null) expenseBudgetAmount = val;
    }

    // Load order items, payments, purchase items, & kitchen items in parallel
    // without silent take(400)/take(200) truncation.
    final activeOrders = orders
        .where((o) => !isCanonicalCancelledOrder(o))
        .toList(growable: false);
    final activePurchases = purchases
        .where((p) => p.status.trim().toLowerCase() != 'cancelled')
        .toList(growable: false);

    final subResults = await Future.wait([
      _fetchOrderItemSubcollections(restaurantId, restRef, activeOrders),
      _fetchOrderPaymentSubcollections(restaurantId, restRef, activeOrders),
      _fetchPurchaseItemSubcollections(restaurantId, restRef, activePurchases),
      _fetchKitchenItems(restaurantId, restRef, kitchenSessions.take(10).toList()),
    ]);
    final itemsByOrder = subResults[0] as Map<String, List<OrderItem>>;
    final paymentsByOrder = subResults[1] as Map<String, List<Payment>>;
    final purchaseItemSnaps = subResults[2] as List<SupplierPurchaseItem>;
    final kitchenItems = subResults[3] as List<KitchenSessionItem>;

    final allOrderItems = itemsByOrder.values
        .expand((list) => list)
        .toList(growable: false);
    readCount +=
        allOrderItems.length +
        paymentsByOrder.values.fold<int>(0, (a, b) => a + b.length) +
        purchaseItemSnaps.length +
        kitchenItems.length;

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

    final bundle = FinanceDashboardBundle(
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
      isPartial: hitLimit,
      partialNote: hitLimit
          ? 'El rango supera 3,000 órdenes; los totales mostrados son parciales. Acota el periodo para exactitud completa.'
          : null,
    );
    if (requestEpoch == _cacheScope.epoch) {
      _bundleCache[cacheKey] = _CachedFinanceBundle(
        bundle: bundle,
        cachedAt: DateTime.now(),
      );
    }
    return bundle;
  }

  Future<List<KitchenSessionItem>> _fetchKitchenItems(
    String restaurantId,
    DocumentReference<Map<String, dynamic>>? restRef,
    List<KitchenSession> sessions,
  ) async {
    if (sessions.isEmpty) return const [];
    final preview = _previewClient;
    if (preview != null) {
      final snaps = await Future.wait(
        sessions.map(
          (ks) => preview.queryAllPages(
            restaurantId: restaurantId,
            collection: 'kitchenSessions',
            parentDocId: ks.id,
            subcollection: 'items',
            maxDocs: 60,
          ),
        ),
      );
      return snaps
          .expand((s) => s.docs.map(KitchenSessionItem.fromDoc))
          .toList(growable: false);
    }
    final snaps = await Future.wait(
      sessions.map(
        (ks) => restRef!
            .collection('kitchenSessions')
            .doc(ks.id)
            .collection('items')
            .limit(60)
            .get(),
      ),
    );
    return snaps
        .expand((s) => s.docs.map(KitchenSessionItem.fromDoc))
        .toList(growable: false);
  }

  Future<Map<String, List<OrderItem>>> _fetchOrderItemSubcollections(
    String restaurantId,
    DocumentReference<Map<String, dynamic>>? restRef,
    List<PosOrder> orders,
  ) async {
    final preview = _previewClient;
    final out = <String, List<OrderItem>>{};
    for (var i = 0; i < orders.length; i += 50) {
      final chunk = orders.sublist(i, (i + 50).clamp(0, orders.length));
      if (preview != null) {
        final snaps = await Future.wait(
          chunk.map(
            (o) => preview.queryAllPages(
              restaurantId: restaurantId,
              collection: 'orders',
              parentDocId: o.id,
              subcollection: 'items',
              maxDocs: 200,
            ),
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
      } else {
        final snaps = await Future.wait(
          chunk.map(
            (o) => restRef!.collection('orders').doc(o.id).collection('items').get(),
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
    }
    return out;
  }

  Future<Map<String, List<Payment>>> _fetchOrderPaymentSubcollections(
    String restaurantId,
    DocumentReference<Map<String, dynamic>>? restRef,
    List<PosOrder> orders,
  ) async {
    final preview = _previewClient;
    final out = <String, List<Payment>>{};
    for (var i = 0; i < orders.length; i += 50) {
      final chunk = orders.sublist(i, (i + 50).clamp(0, orders.length));
      if (preview != null) {
        final snaps = await Future.wait(
          chunk.map(
            (o) => preview.queryAllPages(
              restaurantId: restaurantId,
              collection: 'orders',
              parentDocId: o.id,
              subcollection: 'payments',
              maxDocs: 100,
            ),
          ),
        );
        for (var j = 0; j < chunk.length; j++) {
          out[chunk[j].id] =
              snaps[j].docs.map(Payment.fromDoc).toList(growable: false);
        }
      } else {
        final snaps = await Future.wait(
          chunk.map(
            (o) =>
                restRef!.collection('orders').doc(o.id).collection('payments').get(),
          ),
        );
        for (var j = 0; j < chunk.length; j++) {
          out[chunk[j].id] =
              snaps[j].docs.map(Payment.fromDoc).toList(growable: false);
        }
      }
    }
    return out;
  }

  Future<List<SupplierPurchaseItem>> _fetchPurchaseItemSubcollections(
    String restaurantId,
    DocumentReference<Map<String, dynamic>>? restRef,
    List<SupplierPurchase> purchases,
  ) async {
    final preview = _previewClient;
    final out = <SupplierPurchaseItem>[];
    for (var i = 0; i < purchases.length; i += 20) {
      final chunk = purchases.sublist(i, (i + 20).clamp(0, purchases.length));
      if (preview != null) {
        final snaps = await Future.wait(
          chunk.map(
            (p) => preview.queryAllPages(
              restaurantId: restaurantId,
              collection: 'supplierPurchases',
              parentDocId: p.id,
              subcollection: 'items',
              maxDocs: 100,
            ),
          ),
        );
        for (final s in snaps) {
          out.addAll(s.docs.map(SupplierPurchaseItem.fromDoc));
        }
      } else {
        final snaps = await Future.wait(
          chunk.map(
            (p) => restRef!
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
    BackofficeReadOnlyGuard.assertWritable(
      isReadOnly: isReadOnly,
      action: 'Guardar socio',
    );
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
    BackofficeReadOnlyGuard.assertWritable(
      isReadOnly: isReadOnly,
      action: 'Registrar aportación de socio',
    );
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
    BackofficeReadOnlyGuard.assertWritable(
      isReadOnly: isReadOnly,
      action: 'Guardar configuración de políticas de gastos',
    );
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
    BackofficeReadOnlyGuard.assertWritable(
      isReadOnly: isReadOnly,
      action: 'Guardar política de gastos',
    );
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
    BackofficeReadOnlyGuard.assertWritable(
      isReadOnly: isReadOnly,
      action: 'Guardar meta de eficiencia',
    );
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
    BackofficeReadOnlyGuard.assertWritable(
      isReadOnly: isReadOnly,
      action: 'Guardar presupuesto financiero',
    );
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

class _CachedFinanceBundle {
  const _CachedFinanceBundle({required this.bundle, required this.cachedAt});

  final FinanceDashboardBundle bundle;
  final DateTime cachedAt;
}
