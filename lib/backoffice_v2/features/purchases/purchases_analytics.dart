import '../../../models/purchase_models.dart';

class PurchaseTrendPoint {
  const PurchaseTrendPoint({
    required this.label,
    required this.amount,
    required this.count,
  });

  final String label;
  final double amount;
  final int count;
}

class PriceIncreaseAlert {
  const PriceIncreaseAlert({
    required this.itemName,
    required this.unit,
    required this.previousUnitCost,
    required this.latestUnitCost,
    required this.increasePct,
    required this.supplierName,
  });

  final String itemName;
  final String unit;
  final double previousUnitCost;
  final double latestUnitCost;
  final double increasePct;
  final String supplierName;
}

class SupplierComparisonMetric {
  const SupplierComparisonMetric({
    required this.supplierId,
    required this.supplierName,
    required this.totalQty,
    required this.totalAmount,
    required this.weightedAvgCost,
    required this.lastUnitCost,
    required this.operationsCount,
  });

  final String supplierId;
  final String supplierName;
  final double totalQty;
  final double totalAmount;
  final double weightedAvgCost;
  final double lastUnitCost;
  final int operationsCount;
}

class ItemPricePoint {
  const ItemPricePoint({
    required this.dateLabel,
    required this.unitCost,
    required this.supplierName,
    required this.folio,
  });

  final String dateLabel;
  final double unitCost;
  final String supplierName;
  final String folio;
}

class ItemPurchaseReportRow {
  const ItemPurchaseReportRow({
    required this.itemKey,
    required this.itemName,
    required this.category,
    required this.unit,
    required this.totalQuantity,
    required this.totalAmount,
    required this.weightedAvgCost,
    required this.lastUnitCost,
    required this.minUnitCost,
    required this.maxUnitCost,
    required this.previousPeriodAmount,
    required this.variationPct,
    required this.priceHistory,
    required this.supplierComparison,
    required this.purchaseIds,
  });

  final String itemKey;
  final String itemName;
  final String category;
  final String unit;
  final double totalQuantity;
  final double totalAmount;
  final double weightedAvgCost;
  final double lastUnitCost;
  final double minUnitCost;
  final double maxUnitCost;
  final double previousPeriodAmount;
  final double variationPct;
  final List<ItemPricePoint> priceHistory;
  final List<SupplierComparisonMetric> supplierComparison;
  final List<String> purchaseIds;
}

class SupplierReportSummary {
  const SupplierReportSummary({
    required this.supplierId,
    required this.supplierName,
    required this.totalAmount,
    required this.previousTotalAmount,
    required this.variationPct,
    required this.sharePct,
    required this.operationsCount,
    required this.pendingBalance,
    required this.suppliedItems,
    required this.purchases,
  });

  final String supplierId;
  final String supplierName;
  final double totalAmount;
  final double previousTotalAmount;
  final double variationPct;
  final double sharePct;
  final int operationsCount;
  final double pendingBalance;
  final List<String> suppliedItems;
  final List<SupplierPurchase> purchases;
}

class AgingBucketSummary {
  const AgingBucketSummary({
    required this.label,
    required this.count,
    required this.amount,
  });

  final String label;
  final int count;
  final double amount;
}

class SupplierBalanceSummary {
  const SupplierBalanceSummary({
    required this.supplierId,
    required this.supplierName,
    required this.pendingAmount,
    required this.overdueAmount,
    required this.documentsCount,
  });

  final String supplierId;
  final String supplierName;
  final double pendingAmount;
  final double overdueAmount;
  final int documentsCount;
}

class AccountsPayableSummary {
  const AccountsPayableSummary({
    required this.totalPending,
    required this.overdueAmount,
    required this.dueSoonAmount,
    required this.agingBuckets,
    required this.balancesBySupplier,
    required this.openPurchases,
    required this.reconciliationMismatches,
  });

  final double totalPending;
  final double overdueAmount;
  final double dueSoonAmount;
  final List<AgingBucketSummary> agingBuckets;
  final List<SupplierBalanceSummary> balancesBySupplier;
  final List<SupplierPurchase> openPurchases;
  final List<SupplierPurchase> reconciliationMismatches;
}

class PurchaseEfficiencyMetric {
  const PurchaseEfficiencyMetric({
    required this.label,
    required this.purchasesAmount,
    required this.netSalesAmount,
    required this.costPer100Sales,
    required this.previousCostPer100Sales,
    required this.targetPer100Sales,
    required this.deviationPer100Sales,
  });

  final String label;
  final double purchasesAmount;
  final double netSalesAmount;
  final double costPer100Sales;
  final double previousCostPer100Sales;
  final double? targetPer100Sales;
  final double? deviationPer100Sales;
}

class WeeklyItemBudgetEvaluation {
  const WeeklyItemBudgetEvaluation({
    required this.itemKey,
    required this.itemName,
    required this.unit,
    required this.targetWeeklyQty,
    required this.purchasedQty,
    required this.differenceQty,
    required this.accumulatedSpend,
    required this.avgUnitCost,
    required this.isExceeded,
  });

  final String itemKey;
  final String itemName;
  final String unit;
  final double targetWeeklyQty;
  final double purchasedQty;
  final double differenceQty;
  final double accumulatedSpend;
  final double avgUnitCost;
  final bool isExceeded;
}

class PurchasesDashboardMetrics {
  const PurchasesDashboardMetrics({
    required this.totalAmount,
    required this.previousTotalAmount,
    required this.variationPct,
    required this.paidAmount,
    required this.pendingAmount,
    required this.purchasesCount,
    required this.byCategory,
    required this.byBranch,
    required this.dailyTrend,
    required this.weeklyTrend,
    required this.monthlyTrend,
    required this.supplierReports,
    required this.itemReports,
    required this.priceAlerts,
  });

  final double totalAmount;
  final double previousTotalAmount;
  final double variationPct;
  final double paidAmount;
  final double pendingAmount;
  final int purchasesCount;
  final Map<String, double> byCategory;
  final Map<String, double> byBranch;
  final List<PurchaseTrendPoint> dailyTrend;
  final List<PurchaseTrendPoint> weeklyTrend;
  final List<PurchaseTrendPoint> monthlyTrend;
  final List<SupplierReportSummary> supplierReports;
  final List<ItemPurchaseReportRow> itemReports;
  final List<PriceIncreaseAlert> priceAlerts;
}

class PurchasesAnalytics {
  const PurchasesAnalytics._();

  static String itemUniqueKey({
    String? purchaseItemId,
    required String itemName,
    required String unit,
  }) {
    final cleanId = (purchaseItemId ?? '').trim();
    final cleanUnit = unit.trim().toLowerCase();
    if (cleanId.isNotEmpty) {
      return '$cleanId|$cleanUnit';
    }
    return '${itemName.trim().toLowerCase()}|$cleanUnit';
  }

  static double variationPercent(double current, double previous) {
    if (previous <= 0.0001) {
      return current > 0 ? 100.0 : 0.0;
    }
    return ((current - previous) / previous) * 100.0;
  }

  static PurchasesDashboardMetrics computeDashboard({
    required List<SupplierPurchase> currentPurchases,
    required List<SupplierPurchase> previousPurchases,
    required Map<String, List<SupplierPurchaseItem>> currentItemsByPurchase,
    required Map<String, List<SupplierPurchaseItem>> previousItemsByPurchase,
    required List<PurchaseItem> catalogItems,
    required Map<String, String> branchNames,
  }) {
    final activeCurrent = currentPurchases
        .where((p) => !p.isCancelled)
        .toList(growable: false);
    final activePrev = previousPurchases
        .where((p) => !p.isCancelled)
        .toList(growable: false);

    final totalAmount = activeCurrent.fold<double>(
      0.0,
      (acc, p) => acc + p.total,
    );
    final previousTotalAmount = activePrev.fold<double>(
      0.0,
      (acc, p) => acc + p.total,
    );
    final paidAmount = activeCurrent.fold<double>(
      0.0,
      (acc, p) => acc + p.paidTotal,
    );
    final pendingAmount = activeCurrent.fold<double>(
      0.0,
      (acc, p) => acc + (p.balance > 0 ? p.balance : 0.0),
    );

    final catalogById = {for (final item in catalogItems) item.id: item};
    final catalogByName = {
      for (final item in catalogItems) item.name.trim().toLowerCase(): item,
    };

    final byCategory = <String, double>{};
    final byBranch = <String, double>{};
    final dailyMap = <String, ({double amount, int count})>{};
    final weeklyMap = <String, ({double amount, int count})>{};
    final monthlyMap = <String, ({double amount, int count})>{};

    for (final p in activeCurrent) {
      final branchLabel = branchNames[p.branchId] ?? p.branchName;
      byBranch[branchLabel] = (byBranch[branchLabel] ?? 0.0) + p.total;

      final bDate = _resolvePurchaseBusinessDate(p);
      final d = dailyMap[bDate];
      dailyMap[bDate] = (
        amount: (d?.amount ?? 0.0) + p.total,
        count: (d?.count ?? 0) + 1,
      );

      final weekKey = _weekLabel(p.purchaseDate);
      final w = weeklyMap[weekKey];
      weeklyMap[weekKey] = (
        amount: (w?.amount ?? 0.0) + p.total,
        count: (w?.count ?? 0) + 1,
      );

      final monthKey =
          '${p.purchaseDate.year}-${p.purchaseDate.month.toString().padLeft(2, '0')}';
      final m = monthlyMap[monthKey];
      monthlyMap[monthKey] = (
        amount: (m?.amount ?? 0.0) + p.total,
        count: (m?.count ?? 0) + 1,
      );

      final lines = currentItemsByPurchase[p.id] ?? const [];
      if (lines.isEmpty) {
        byCategory['General'] = (byCategory['General'] ?? 0.0) + p.total;
      } else {
        for (final line in lines.where((l) => l.isActive)) {
          final cat = _resolveCategory(line, catalogById, catalogByName);
          byCategory[cat] = (byCategory[cat] ?? 0.0) + line.lineTotal;
        }
      }
    }

    final supplierReports = computeSupplierReports(
      currentPurchases: activeCurrent,
      previousPurchases: activePrev,
      itemsByPurchase: currentItemsByPurchase,
      totalPurchasesAmount: totalAmount,
    );

    final itemReports = computeItemReports(
      currentPurchases: activeCurrent,
      previousPurchases: activePrev,
      currentItemsByPurchase: currentItemsByPurchase,
      previousItemsByPurchase: previousItemsByPurchase,
      catalogItems: catalogItems,
    );

    final priceAlerts = <PriceIncreaseAlert>[];
    for (final row in itemReports) {
      if (row.priceHistory.length >= 2) {
        final prevPrice = row.priceHistory[row.priceHistory.length - 2].unitCost;
        final latest = row.priceHistory.last;
        if (prevPrice > 0) {
          final pct = ((latest.unitCost - prevPrice) / prevPrice) * 100.0;
          if (pct >= 8.0) {
            priceAlerts.add(
              PriceIncreaseAlert(
                itemName: row.itemName,
                unit: row.unit,
                previousUnitCost: prevPrice,
                latestUnitCost: latest.unitCost,
                increasePct: pct,
                supplierName: latest.supplierName,
              ),
            );
          }
        }
      }
    }
    priceAlerts.sort((a, b) => b.increasePct.compareTo(a.increasePct));

    return PurchasesDashboardMetrics(
      totalAmount: totalAmount,
      previousTotalAmount: previousTotalAmount,
      variationPct: variationPercent(totalAmount, previousTotalAmount),
      paidAmount: paidAmount,
      pendingAmount: pendingAmount,
      purchasesCount: activeCurrent.length,
      byCategory: byCategory,
      byBranch: byBranch,
      dailyTrend: _sortedTrend(dailyMap),
      weeklyTrend: _sortedTrend(weeklyMap),
      monthlyTrend: _sortedTrend(monthlyMap),
      supplierReports: supplierReports,
      itemReports: itemReports,
      priceAlerts: priceAlerts,
    );
  }

  static List<SupplierReportSummary> computeSupplierReports({
    required List<SupplierPurchase> currentPurchases,
    required List<SupplierPurchase> previousPurchases,
    required Map<String, List<SupplierPurchaseItem>> itemsByPurchase,
    required double totalPurchasesAmount,
  }) {
    final prevBySupplier = <String, double>{};
    for (final p in previousPurchases.where((e) => !e.isCancelled)) {
      prevBySupplier[p.supplierId] =
          (prevBySupplier[p.supplierId] ?? 0.0) + p.total;
    }

    final grouped = <String, List<SupplierPurchase>>{};
    for (final p in currentPurchases.where((e) => !e.isCancelled)) {
      grouped.putIfAbsent(p.supplierId, () => []).add(p);
    }

    final reports = <SupplierReportSummary>[];
    for (final entry in grouped.entries) {
      final list = entry.value
        ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
      final name = list.first.supplierName;
      final total = list.fold<double>(0.0, (acc, p) => acc + p.total);
      final pending = list.fold<double>(
        0.0,
        (acc, p) => acc + (p.balance > 0 ? p.balance : 0.0),
      );
      final prevTotal = prevBySupplier[entry.key] ?? 0.0;
      final itemsSet = <String>{};
      for (final p in list) {
        for (final line in (itemsByPurchase[p.id] ?? const [])) {
          if (line.isActive && line.purchaseItemName.trim().isNotEmpty) {
            itemsSet.add(line.purchaseItemName.trim());
          }
        }
      }
      reports.add(
        SupplierReportSummary(
          supplierId: entry.key,
          supplierName: name,
          totalAmount: total,
          previousTotalAmount: prevTotal,
          variationPct: variationPercent(total, prevTotal),
          sharePct: totalPurchasesAmount > 0
              ? (total / totalPurchasesAmount) * 100.0
              : 0.0,
          operationsCount: list.length,
          pendingBalance: pending,
          suppliedItems: itemsSet.toList()..sort(),
          purchases: list,
        ),
      );
    }
    reports.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    return reports;
  }

  static List<ItemPurchaseReportRow> computeItemReports({
    required List<SupplierPurchase> currentPurchases,
    required List<SupplierPurchase> previousPurchases,
    required Map<String, List<SupplierPurchaseItem>> currentItemsByPurchase,
    required Map<String, List<SupplierPurchaseItem>> previousItemsByPurchase,
    required List<PurchaseItem> catalogItems,
  }) {
    final catalogById = {for (final item in catalogItems) item.id: item};
    final catalogByName = {
      for (final item in catalogItems) item.name.trim().toLowerCase(): item,
    };

    final prevTotals = <String, double>{};
    for (final p in previousPurchases.where((e) => !e.isCancelled)) {
      for (final line in (previousItemsByPurchase[p.id] ?? const [])) {
        if (!line.isActive) continue;
        final key = itemUniqueKey(
          purchaseItemId: line.purchaseItemId,
          itemName: line.purchaseItemName,
          unit: line.unit,
        );
        prevTotals[key] = (prevTotals[key] ?? 0.0) + line.lineTotal;
      }
    }

    final acc = <String, _ItemAccumulator>{};
    final sortedCurrent = currentPurchases
        .where((p) => !p.isCancelled)
        .toList()
      ..sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));

    for (final p in sortedCurrent) {
      final bDate = _resolvePurchaseBusinessDate(p);
      for (final line in (currentItemsByPurchase[p.id] ?? const [])) {
        if (!line.isActive) continue;
        final key = itemUniqueKey(
          purchaseItemId: line.purchaseItemId,
          itemName: line.purchaseItemName,
          unit: line.unit,
        );
        final cat = _resolveCategory(line, catalogById, catalogByName);
        final bucket = acc.putIfAbsent(
          key,
          () => _ItemAccumulator(
            key: key,
            name: line.purchaseItemName,
            category: cat,
            unit: line.unit.trim().isEmpty ? 'unidad' : line.unit.trim(),
          ),
        );
        bucket.totalQty += line.quantity;
        bucket.totalAmount += line.lineTotal;
        final uCost = line.unitCostCalculated > 0
            ? line.unitCostCalculated
            : (line.quantity > 0 ? line.lineTotal / line.quantity : line.unitCost);
        if (uCost > 0) {
          if (bucket.minCost == null || uCost < bucket.minCost!) {
            bucket.minCost = uCost;
          }
          if (bucket.maxCost == null || uCost > bucket.maxCost!) {
            bucket.maxCost = uCost;
          }
          bucket.lastCost = uCost;
          bucket.priceHistory.add(
            ItemPricePoint(
              dateLabel: bDate,
              unitCost: uCost,
              supplierName: p.supplierName,
              folio: p.folio,
            ),
          );
        }
        bucket.purchaseIds.add(p.id);
        final supBucket = bucket.bySupplier.putIfAbsent(
          p.supplierId,
          () => _SupplierLineAcc(
            supplierId: p.supplierId,
            supplierName: p.supplierName,
          ),
        );
        supBucket.totalQty += line.quantity;
        supBucket.totalAmount += line.lineTotal;
        supBucket.operationsCount += 1;
        if (uCost > 0) supBucket.lastCost = uCost;
      }
    }

    final rows = <ItemPurchaseReportRow>[];
    for (final bucket in acc.values) {
      final weighted = bucket.totalQty > 0
          ? bucket.totalAmount / bucket.totalQty
          : 0.0;
      final prevAmount = prevTotals[bucket.key] ?? 0.0;
      final supplierComparisons = bucket.bySupplier.values
          .map(
            (s) => SupplierComparisonMetric(
              supplierId: s.supplierId,
              supplierName: s.supplierName,
              totalQty: s.totalQty,
              totalAmount: s.totalAmount,
              weightedAvgCost: s.totalQty > 0 ? s.totalAmount / s.totalQty : 0.0,
              lastUnitCost: s.lastCost,
              operationsCount: s.operationsCount,
            ),
          )
          .toList()
        ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

      rows.add(
        ItemPurchaseReportRow(
          itemKey: bucket.key,
          itemName: bucket.name,
          category: bucket.category,
          unit: bucket.unit,
          totalQuantity: bucket.totalQty,
          totalAmount: bucket.totalAmount,
          weightedAvgCost: weighted,
          lastUnitCost: bucket.lastCost,
          minUnitCost: bucket.minCost ?? 0.0,
          maxUnitCost: bucket.maxCost ?? 0.0,
          previousPeriodAmount: prevAmount,
          variationPct: variationPercent(bucket.totalAmount, prevAmount),
          priceHistory: bucket.priceHistory,
          supplierComparison: supplierComparisons,
          purchaseIds: bucket.purchaseIds.toList(),
        ),
      );
    }

    rows.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    return rows;
  }

  static AccountsPayableSummary computeAccountsPayable({
    required List<SupplierPurchase> purchases,
    DateTime? asOf,
  }) {
    final today = asOf ?? DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final openPurchases = <SupplierPurchase>[];
    final mismatches = <SupplierPurchase>[];

    var totalPending = 0.0;
    var overdueAmount = 0.0;
    var dueSoonAmount = 0.0;

    var currentCount = 0;
    var currentAmount = 0.0;
    var d1to15Count = 0;
    var d1to15Amount = 0.0;
    var d16to30Count = 0;
    var d16to30Amount = 0.0;
    var dOver30Count = 0;
    var dOver30Amount = 0.0;

    final bySupplier = <String, _CxpSupplierAcc>{};

    for (final p in purchases) {
      if (p.isCancelled) continue;

      final expectedBalance = (p.total - p.paidTotal).clamp(0.0, double.infinity);
      if ((expectedBalance - p.balance).abs() > 0.05) {
        mismatches.add(p);
      }

      // Paid purchases never generate CXP obligations
      if (!p.hasBalance || p.status == 'paid') continue;

      openPurchases.add(p);
      totalPending += p.balance;

      final due = p.dueDate ?? p.purchaseDate;
      final dueDateOnly = DateTime(due.year, due.month, due.day);
      final daysPastDue = todayDate.difference(dueDateOnly).inDays;

      final isOverdue = daysPastDue > 0;
      if (isOverdue) {
        overdueAmount += p.balance;
        if (daysPastDue <= 15) {
          d1to15Count += 1;
          d1to15Amount += p.balance;
        } else if (daysPastDue <= 30) {
          d16to30Count += 1;
          d16to30Amount += p.balance;
        } else {
          dOver30Count += 1;
          dOver30Amount += p.balance;
        }
      } else {
        currentCount += 1;
        currentAmount += p.balance;
        if (daysPastDue >= -7) {
          dueSoonAmount += p.balance;
        }
      }

      final sup = bySupplier.putIfAbsent(
        p.supplierId,
        () => _CxpSupplierAcc(
          supplierId: p.supplierId,
          supplierName: p.supplierName,
        ),
      );
      sup.pendingAmount += p.balance;
      if (isOverdue) sup.overdueAmount += p.balance;
      sup.documentsCount += 1;
    }

    openPurchases.sort((a, b) {
      final aDue = a.dueDate ?? a.purchaseDate;
      final bDue = b.dueDate ?? b.purchaseDate;
      return aDue.compareTo(bDue);
    });

    final supplierBalances = bySupplier.values
        .map(
          (s) => SupplierBalanceSummary(
            supplierId: s.supplierId,
            supplierName: s.supplierName,
            pendingAmount: s.pendingAmount,
            overdueAmount: s.overdueAmount,
            documentsCount: s.documentsCount,
          ),
        )
        .toList()
      ..sort((a, b) => b.pendingAmount.compareTo(a.pendingAmount));

    return AccountsPayableSummary(
      totalPending: totalPending,
      overdueAmount: overdueAmount,
      dueSoonAmount: dueSoonAmount,
      agingBuckets: [
        AgingBucketSummary(
          label: 'Al corriente',
          count: currentCount,
          amount: currentAmount,
        ),
        AgingBucketSummary(
          label: '1-15 días vencido',
          count: d1to15Count,
          amount: d1to15Amount,
        ),
        AgingBucketSummary(
          label: '16-30 días vencido',
          count: d16to30Count,
          amount: d16to30Amount,
        ),
        AgingBucketSummary(
          label: '+30 días vencido',
          count: dOver30Count,
          amount: dOver30Amount,
        ),
      ],
      balancesBySupplier: supplierBalances,
      openPurchases: openPurchases,
      reconciliationMismatches: mismatches,
    );
  }

  static PurchaseEfficiencyMetric computeEfficiency({
    required String label,
    required double purchasesAmount,
    required double netSalesAmount,
    required double previousPurchasesAmount,
    required double previousNetSalesAmount,
    double? targetPer100Sales,
  }) {
    final costPer100 = netSalesAmount > 0
        ? (purchasesAmount / netSalesAmount) * 100.0
        : 0.0;
    final prevCostPer100 = previousNetSalesAmount > 0
        ? (previousPurchasesAmount / previousNetSalesAmount) * 100.0
        : 0.0;
    final deviation = targetPer100Sales != null
        ? costPer100 - targetPer100Sales
        : null;

    return PurchaseEfficiencyMetric(
      label: label,
      purchasesAmount: purchasesAmount,
      netSalesAmount: netSalesAmount,
      costPer100Sales: costPer100,
      previousCostPer100Sales: prevCostPer100,
      targetPer100Sales: targetPer100Sales,
      deviationPer100Sales: deviation,
    );
  }

  static WeeklyItemBudgetEvaluation evaluateWeeklyBudget({
    required ItemPurchaseReportRow itemReport,
    required double targetWeeklyQty,
  }) {
    final diff = itemReport.totalQuantity - targetWeeklyQty;
    return WeeklyItemBudgetEvaluation(
      itemKey: itemReport.itemKey,
      itemName: itemReport.itemName,
      unit: itemReport.unit,
      targetWeeklyQty: targetWeeklyQty,
      purchasedQty: itemReport.totalQuantity,
      differenceQty: diff,
      accumulatedSpend: itemReport.totalAmount,
      avgUnitCost: itemReport.weightedAvgCost,
      isExceeded: diff > 0.0001,
    );
  }

  static String _resolvePurchaseBusinessDate(SupplierPurchase p) {
    final b = (p.businessDate ?? '').trim();
    if (b.isNotEmpty) return b;
    final d = p.purchaseDate;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _weekLabel(DateTime dt) {
    final monday = dt.subtract(Duration(days: dt.weekday - 1));
    return 'Sem ${monday.month.toString().padLeft(2, '0')}/${monday.day.toString().padLeft(2, '0')}';
  }

  static String _resolveCategory(
    SupplierPurchaseItem line,
    Map<String, PurchaseItem> byId,
    Map<String, PurchaseItem> byName,
  ) {
    final id = (line.purchaseItemId ?? '').trim();
    if (id.isNotEmpty && byId.containsKey(id)) {
      return byId[id]!.category;
    }
    final nameKey = line.purchaseItemName.trim().toLowerCase();
    if (byName.containsKey(nameKey)) {
      return byName[nameKey]!.category;
    }
    return 'General';
  }

  static List<PurchaseTrendPoint> _sortedTrend(
    Map<String, ({double amount, int count})> source,
  ) {
    final keys = source.keys.toList()..sort();
    return keys
        .map(
          (k) => PurchaseTrendPoint(
            label: k,
            amount: source[k]!.amount,
            count: source[k]!.count,
          ),
        )
        .toList(growable: false);
  }
}

class _ItemAccumulator {
  _ItemAccumulator({
    required this.key,
    required this.name,
    required this.category,
    required this.unit,
  });

  final String key;
  final String name;
  final String category;
  final String unit;
  double totalQty = 0;
  double totalAmount = 0;
  double lastCost = 0;
  double? minCost;
  double? maxCost;
  final List<ItemPricePoint> priceHistory = [];
  final Set<String> purchaseIds = {};
  final Map<String, _SupplierLineAcc> bySupplier = {};
}

class _SupplierLineAcc {
  _SupplierLineAcc({required this.supplierId, required this.supplierName});

  final String supplierId;
  final String supplierName;
  double totalQty = 0;
  double totalAmount = 0;
  double lastCost = 0;
  int operationsCount = 0;
}

class _CxpSupplierAcc {
  _CxpSupplierAcc({required this.supplierId, required this.supplierName});

  final String supplierId;
  final String supplierName;
  double pendingAmount = 0;
  double overdueAmount = 0;
  int documentsCount = 0;
}
