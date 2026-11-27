import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/orders/backoffice_sales_cancellation.dart';
import '../../../core/reports/canonical_sales_summary.dart';
import '../../../models/branch.dart';
import '../../../models/order.dart';
import '../../../models/order_item.dart';
import '../../../models/payment.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/cache/backoffice_cache_scope.dart';

class DailyRevenuePoint {
  const DailyRevenuePoint({
    required this.businessDate,
    required this.netSales,
    required this.ordersCount,
  });

  final String businessDate;
  final double netSales;
  final int ordersCount;
}

class BranchSalesBreakdown {
  const BranchSalesBreakdown({
    required this.branchId,
    required this.branchName,
    required this.netSales,
    required this.ordersCount,
    required this.averageTicket,
  });

  final String branchId;
  final String branchName;
  final double netSales;
  final int ordersCount;
  final double averageTicket;
}

class EmployeeSalesBreakdown {
  const EmployeeSalesBreakdown({
    required this.employeeName,
    required this.collectedAmount,
    required this.tipsAmount,
    required this.operationsCount,
  });

  final String employeeName;
  final double collectedAmount;
  final double tipsAmount;
  final int operationsCount;
}

class ChannelBreakdown {
  const ChannelBreakdown({
    required this.dineInSales,
    required this.dineInOrders,
    required this.takeoutSales,
    required this.takeoutOrders,
  });

  final double dineInSales;
  final int dineInOrders;
  final double takeoutSales;
  final int takeoutOrders;
}

class DashboardReadMetrics {
  const DashboardReadMetrics({
    required this.orderReads,
    required this.itemReads,
    required this.paymentReads,
    required this.fromCache,
    required this.durationMs,
  });

  final int orderReads;
  final int itemReads;
  final int paymentReads;
  final bool fromCache;
  final int durationMs;

  int get totalReads => orderReads + itemReads + paymentReads;
}

class ExecutiveDashboardData {
  const ExecutiveDashboardData({
    required this.summary,
    required this.previousSummary,
    required this.dailySeries,
    required this.branchBreakdown,
    required this.employeeBreakdown,
    required this.channelBreakdown,
    required this.recentOrders,
    required this.cancelledOrdersCount,
    required this.totalTips,
    required this.totalCardFeesAbsorbed,
    required this.totalSurcharges,
    required this.queriedOrderCount,
    required this.truncatedToLimit,
    required this.readMetrics,
  });

  final CanonicalSalesSummary summary;
  final CanonicalSalesSummary previousSummary;
  final List<DailyRevenuePoint> dailySeries;
  final List<BranchSalesBreakdown> branchBreakdown;
  final List<EmployeeSalesBreakdown> employeeBreakdown;
  final ChannelBreakdown channelBreakdown;
  final List<PosOrder> recentOrders;
  final int cancelledOrdersCount;
  final double totalTips;
  final double totalCardFeesAbsorbed;
  final double totalSurcharges;
  final int queriedOrderCount;
  final bool truncatedToLimit;
  final DashboardReadMetrics readMetrics;

  double? get netSalesDeltaPct =>
      _pctDelta(summary.netSales, previousSummary.netSales);
  double? get ordersDeltaPct => _pctDelta(
    summary.paidOrdersCount.toDouble(),
    previousSummary.paidOrdersCount.toDouble(),
  );
  double? get avgTicketDeltaPct =>
      _pctDelta(summary.averageTicket, previousSummary.averageTicket);

  static double? _pctDelta(double current, double previous) {
    if (previous <= 0) return null;
    return ((current - previous) / previous) * 100.0;
  }
}

class _CachedEntry {
  const _CachedEntry({required this.data, required this.cachedAt});
  final ExecutiveDashboardData data;
  final DateTime cachedAt;
}

/// Bounded, on-demand repository for the Executive Dashboard with 60s TTL cache.
class DashboardRepository {
  DashboardRepository({
    FirebaseFirestore? firestore,
    BackofficeCacheScope? cacheScope,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _cacheScope = cacheScope ?? BackofficeCacheScope() {
    _cacheScope.registerInvalidator(invalidateCache);
  }

  final FirebaseFirestore _db;
  final BackofficeCacheScope _cacheScope;
  final Map<String, _CachedEntry> _cache = {};

  static const int maxOrdersPerQuery = 600;
  static const Duration cacheTtl = Duration(seconds: 60);

  void invalidateCache() => _cache.clear();

  Future<ExecutiveDashboardData> loadDashboard({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    required List<Branch> branches,
    String? branchId,
    bool forceRefresh = false,
  }) async {
    final requestEpoch = _cacheScope.epoch;
    final cacheKey = _cacheScope.buildScopedKey('dashboard', [
      restaurantId,
      branchId ?? 'all',
      startBusinessDate,
      endBusinessDate,
    ]);
    if (!forceRefresh) {
      final cached = _cache[cacheKey];
      if (cached != null &&
          DateTime.now().difference(cached.cachedAt) < cacheTtl) {
        final d = cached.data;
        return ExecutiveDashboardData(
          summary: d.summary,
          previousSummary: d.previousSummary,
          dailySeries: d.dailySeries,
          branchBreakdown: d.branchBreakdown,
          employeeBreakdown: d.employeeBreakdown,
          channelBreakdown: d.channelBreakdown,
          recentOrders: d.recentOrders,
          cancelledOrdersCount: d.cancelledOrdersCount,
          totalTips: d.totalTips,
          totalCardFeesAbsorbed: d.totalCardFeesAbsorbed,
          totalSurcharges: d.totalSurcharges,
          queriedOrderCount: d.queriedOrderCount,
          truncatedToLimit: d.truncatedToLimit,
          readMetrics: const DashboardReadMetrics(
            orderReads: 0,
            itemReads: 0,
            paymentReads: 0,
            fromCache: true,
            durationMs: 0,
          ),
        );
      }
    }

    final sw = Stopwatch()..start();
    final startDt = DateTime.parse(startBusinessDate);
    final endDt = DateTime.parse(endBusinessDate);
    final spanDays = endDt.difference(startDt).inDays + 1;
    final prevEndDt = startDt.subtract(const Duration(days: 1));
    final prevStartDt = prevEndDt.subtract(Duration(days: spanDays - 1));

    final results = await Future.wait([
      _fetchPeriod(
        restaurantId: restaurantId,
        startBusinessDate: startBusinessDate,
        endBusinessDate: endBusinessDate,
        branchId: branchId,
      ),
      _fetchPeriod(
        restaurantId: restaurantId,
        startBusinessDate: BackofficeSalesAdapter.formatBusinessDate(prevStartDt),
        endBusinessDate: BackofficeSalesAdapter.formatBusinessDate(prevEndDt),
        branchId: branchId,
      ),
    ]);

    final current = results[0];
    final previous = results[1];

    final dailyTotals = <String, ({double total, int count})>{};
    final branchTotals = <String, ({double total, int count})>{};
    var dineInSales = 0.0;
    var dineInOrders = 0;
    var takeoutSales = 0.0;
    var takeoutOrders = 0;

    for (final row in current.summary.orderRows) {
      final dateKey = row.businessDate;
      final prevDay = dailyTotals[dateKey] ?? (total: 0.0, count: 0);
      dailyTotals[dateKey] = (
        total: prevDay.total + row.netSales,
        count: prevDay.count + 1,
      );

      final bId = row.order.branchId;
      final prevBranch = branchTotals[bId] ?? (total: 0.0, count: 0);
      branchTotals[bId] = (
        total: prevBranch.total + row.netSales,
        count: prevBranch.count + 1,
      );

      if (row.order.orderType.trim().toLowerCase() == 'takeout') {
        takeoutSales += row.netSales;
        takeoutOrders++;
      } else {
        dineInSales += row.netSales;
        dineInOrders++;
      }
    }

    var totalTips = 0.0;
    var totalCardFeesAbsorbed = 0.0;
    var totalSurcharges = 0.0;
    final empMap = <String, ({double collected, double tips, int count})>{};

    for (final entry in current.paymentsByOrder.entries) {
      for (final p in entry.value) {
        final active = isBackofficeActivePayment(
          status: p.status,
          hasCancelledAt: p.cancelledAt != null,
          appliedAmount: p.chargedAmount,
        );
        if (!active) continue;
        totalTips += p.tipAmount;
        totalCardFeesAbsorbed += p.cardFeeAbsorbedAmount;
        totalSurcharges += p.surchargeAmount;

        final empName =
            (p.createdByEmployeeName ?? p.employeeName ?? 'Personal en turno')
                .trim();
        final resolvedName = empName.isEmpty ? 'Personal en turno' : empName;
        final prevEmp = empMap[resolvedName] ?? (collected: 0.0, tips: 0.0, count: 0);
        empMap[resolvedName] = (
          collected: prevEmp.collected + p.chargedAmount,
          tips: prevEmp.tips + p.tipAmount,
          count: prevEmp.count + 1,
        );
      }
    }

    final employeeBreakdown = empMap.entries
        .map(
          (e) => EmployeeSalesBreakdown(
            employeeName: e.key,
            collectedAmount: e.value.collected,
            tipsAmount: e.value.tips,
            operationsCount: e.value.count,
          ),
        )
        .toList()
      ..sort((a, b) => b.collectedAmount.compareTo(a.collectedAmount));

    final dailySeries = dailyTotals.entries
        .map(
          (e) => DailyRevenuePoint(
            businessDate: e.key,
            netSales: e.value.total,
            ordersCount: e.value.count,
          ),
        )
        .toList()
      ..sort((a, b) => a.businessDate.compareTo(b.businessDate));

    final branchNameMap = {for (final b in branches) b.id: b.name};
    final branchBreakdown = branchTotals.entries
        .map(
          (e) => BranchSalesBreakdown(
            branchId: e.key,
            branchName: branchNameMap[e.key] ?? e.key,
            netSales: e.value.total,
            ordersCount: e.value.count,
            averageTicket: e.value.count == 0 ? 0 : e.value.total / e.value.count,
          ),
        )
        .toList()
      ..sort((a, b) => b.netSales.compareTo(a.netSales));

    final cancelledCount = current.orders
        .where((o) => o.status.trim().toLowerCase() == 'cancelled')
        .length;

    sw.stop();
    final data = ExecutiveDashboardData(
      summary: current.summary,
      previousSummary: previous.summary,
      dailySeries: dailySeries,
      branchBreakdown: branchBreakdown,
      employeeBreakdown: employeeBreakdown,
      channelBreakdown: ChannelBreakdown(
        dineInSales: dineInSales,
        dineInOrders: dineInOrders,
        takeoutSales: takeoutSales,
        takeoutOrders: takeoutOrders,
      ),
      recentOrders: current.orders.take(6).toList(growable: false),
      cancelledOrdersCount: cancelledCount,
      totalTips: totalTips,
      totalCardFeesAbsorbed: totalCardFeesAbsorbed,
      totalSurcharges: totalSurcharges,
      queriedOrderCount: current.orders.length,
      truncatedToLimit: current.truncated,
      readMetrics: DashboardReadMetrics(
        orderReads: current.orderReads + previous.orderReads,
        itemReads: current.itemReads + previous.itemReads,
        paymentReads: current.paymentReads + previous.paymentReads,
        fromCache: false,
        durationMs: sw.elapsedMilliseconds,
      ),
    );

    if (requestEpoch == _cacheScope.epoch) {
      _cache[cacheKey] = _CachedEntry(data: data, cachedAt: DateTime.now());
    }
    return data;
  }

  Future<
    ({
      List<PosOrder> orders,
      Map<String, List<Payment>> paymentsByOrder,
      CanonicalSalesSummary summary,
      bool truncated,
      int orderReads,
      int itemReads,
      int paymentReads,
    })
  >
  _fetchPeriod({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('orders')
        .where('businessDate', isGreaterThanOrEqualTo: startBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: endBusinessDate)
        .orderBy('businessDate', descending: true);

    if (branchId != null && branchId.isNotEmpty) {
      query = query.where('branchId', isEqualTo: branchId);
    }

    final snapshot = await query.limit(maxOrdersPerQuery + 1).get();
    final truncated = snapshot.docs.length > maxOrdersPerQuery;
    final docs = truncated
        ? snapshot.docs.take(maxOrdersPerQuery).toList(growable: false)
        : snapshot.docs;

    final orders = docs.map(PosOrder.fromDoc).toList(growable: false);
    final itemsByOrder = <String, List<OrderItem>>{};
    final paymentsByOrder = <String, List<Payment>>{};
    var itemReads = 0;
    var paymentReads = 0;

    final activeOrders = orders
        .where((o) => o.status == 'paid' || o.paidTotal > 0)
        .toList(growable: false);

    const batchSize = 15;
    for (var i = 0; i < activeOrders.length; i += batchSize) {
      final chunk = activeOrders.sublist(
        i,
        (i + batchSize).clamp(0, activeOrders.length),
      );
      await Future.wait(
        chunk.map((order) async {
          final orderRef = _db
              .collection('restaurants')
              .doc(restaurantId)
              .collection('orders')
              .doc(order.id);
          final results = await Future.wait([
            orderRef.collection('items').get(),
            orderRef.collection('payments').get(),
          ]);
          itemReads += results[0].docs.length;
          paymentReads += results[1].docs.length;
          itemsByOrder[order.id] = results[0].docs
              .map(OrderItem.fromDoc)
              .toList(growable: false);
          paymentsByOrder[order.id] = results[1].docs
              .map(Payment.fromDoc)
              .toList(growable: false);
        }),
      );
    }

    final summary = BackofficeSalesAdapter.buildCanonicalSummary(
      orders: orders,
      itemsByOrder: itemsByOrder,
      paymentsByOrder: paymentsByOrder,
    );
    return (
      orders: orders,
      paymentsByOrder: paymentsByOrder,
      summary: summary,
      truncated: truncated,
      orderReads: docs.length,
      itemReads: itemReads,
      paymentReads: paymentReads,
    );
  }
}
