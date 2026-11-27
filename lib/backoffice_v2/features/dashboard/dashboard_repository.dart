import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/reports/canonical_sales_summary.dart';
import '../../../models/branch.dart';
import '../../../models/order.dart';
import '../../../models/order_item.dart';
import '../../../models/payment.dart';
import '../../core/adapters/sales_adapter.dart';

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

class ExecutiveDashboardData {
  const ExecutiveDashboardData({
    required this.summary,
    required this.previousSummary,
    required this.dailySeries,
    required this.branchBreakdown,
    required this.channelBreakdown,
    required this.recentOrders,
    required this.cancelledOrdersCount,
    required this.queriedOrderCount,
    required this.truncatedToLimit,
  });

  final CanonicalSalesSummary summary;
  final CanonicalSalesSummary previousSummary;
  final List<DailyRevenuePoint> dailySeries;
  final List<BranchSalesBreakdown> branchBreakdown;
  final ChannelBreakdown channelBreakdown;
  final List<PosOrder> recentOrders;
  final int cancelledOrdersCount;
  final int queriedOrderCount;
  final bool truncatedToLimit;

  double? get netSalesDeltaPct => _pctDelta(summary.netSales, previousSummary.netSales);
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

/// Bounded, on-demand repository for the Executive Dashboard.
class DashboardRepository {
  DashboardRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const int maxOrdersPerQuery = 600;

  Future<ExecutiveDashboardData> loadDashboard({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    required List<Branch> branches,
    String? branchId,
  }) async {
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

    return ExecutiveDashboardData(
      summary: current.summary,
      previousSummary: previous.summary,
      dailySeries: dailySeries,
      branchBreakdown: branchBreakdown,
      channelBreakdown: ChannelBreakdown(
        dineInSales: dineInSales,
        dineInOrders: dineInOrders,
        takeoutSales: takeoutSales,
        takeoutOrders: takeoutOrders,
      ),
      recentOrders: current.orders.take(6).toList(growable: false),
      cancelledOrdersCount: cancelledCount,
      queriedOrderCount: current.orders.length,
      truncatedToLimit: current.truncated,
    );
  }

  Future<({List<PosOrder> orders, CanonicalSalesSummary summary, bool truncated})>
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
    return (orders: orders, summary: summary, truncated: truncated);
  }
}
