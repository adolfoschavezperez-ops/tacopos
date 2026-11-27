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

enum FinancePeriodPreset {
  daily('Diario'),
  weekly('Semanal'),
  monthly('Mensual'),
  quarterly('Trimestral'),
  annual('Anual'),
  custom('Personalizado');

  const FinancePeriodPreset(this.label);
  final String label;
}

enum BreakEvenHorizon {
  daily('Diario', 1),
  weekly('Semanal', 7),
  monthly('Mensual', 30);

  const BreakEvenHorizon(this.label, this.defaultDays);
  final String label;
  final int defaultDays;
}

/// Normalizes status strings used across Backoffice 1.0 and 2.0.
bool isApprovedExpenseStatus(String raw) {
  final s = raw.trim().toLowerCase();
  return s == 'approved' ||
      s == 'aprobado' ||
      s == 'aprobada' ||
      s == 'paid' ||
      s == 'pagado' ||
      s == 'pagada';
}

/// Returns true when a withdrawal request represents an operating expense
/// (excluding supplier payments, partner contributions, or cash transfers).
bool isFinanceOperatingExpense(CashWithdrawalRequest req) {
  if (!isApprovedExpenseStatus(req.status)) return false;
  final src = req.source.trim().toLowerCase();
  if (src == 'supplier_payment' ||
      src == 'pago_proveedor' ||
      src == 'partner_contribution' ||
      src == 'aportacion_socio' ||
      src == 'aportacion_socios' ||
      src == 'cash_transfer' ||
      src == 'transferencia_interna') {
    return false;
  }
  return req.amount > 0;
}

bool isPayrollExpense(CashWithdrawalRequest req) {
  final r = req.reason.trim().toLowerCase();
  return r.contains('nómina') ||
      r.contains('nomina') ||
      r.contains('sueldo') ||
      r.contains('salario');
}

String normalizeExpenseConcept(String reason) {
  final cleaned = reason.trim();
  if (cleaned.isEmpty) return 'Sin concepto';
  return cleaned[0].toUpperCase() + cleaned.substring(1);
}

bool isPartnerSupplierPayment(SupplierPayment p) {
  final m = p.method.trim().toLowerCase();
  final f = p.fundingSource.trim().toLowerCase();
  const aliases = {
    'partner_contribution',
    'partner contribution',
    'partner_cash',
    'partner_transfer',
    'aportacion_socio',
    'aportacion socio',
    'aportacion_socios',
    'aportación de socios',
  };
  return aliases.contains(m) || aliases.contains(f);
}

class PeriodDelta {
  const PeriodDelta({
    required this.current,
    required this.previous,
    required this.delta,
    required this.deltaPercent,
  });

  final double current;
  final double previous;
  final double delta;
  final double? deltaPercent;

  factory PeriodDelta.compute(double current, double previous) {
    final delta = current - previous;
    final pct = previous.abs() < 0.005 ? null : (delta / previous) * 100.0;
    return PeriodDelta(
      current: current,
      previous: previous,
      delta: delta,
      deltaPercent: pct,
    );
  }
}

class ExpenseConceptBreakdown {
  const ExpenseConceptBreakdown({
    required this.concept,
    required this.totalAmount,
    required this.count,
    required this.historicalAmount,
    required this.cashDrawerAmount,
  });

  final String concept;
  final double totalAmount;
  final int count;
  final double historicalAmount;
  final double cashDrawerAmount;
}

class FinancePeriodSummary {
  const FinancePeriodSummary({
    required this.grossSales,
    required this.discounts,
    required this.employeeFreeMeals,
    required this.netSales,
    required this.ordersCount,
    required this.cashCollected,
    required this.cardCollected,
    required this.cardFeeAbsorbed,
    required this.platformCollected,
    required this.otherCollected,
    required this.realCollected,
    required this.tipsTotal,
    required this.purchasesTotal,
    required this.estimatedCogs,
    required this.cogsCoveredRevenue,
    required this.cogsMissingRevenue,
    required this.operatingExpensesPaid,
    required this.cashDrawerExpenses,
    required this.historicalExpenses,
    required this.payrollExpenses,
    required this.grossProfit,
    required this.operatingResultFlow,
    required this.operatingProfitAccounting,
    required this.profitMarginPercent,
    required this.accountsPayableTotal,
    required this.supplierPaidFromSales,
    required this.supplierPaidByPartners,
    required this.partnerContributionsTotal,
    required this.operatingCashFlow,
    required this.cashFlowWithPartners,
    required this.expensesByConcept,
    required this.expensesByBranch,
  });

  final double grossSales;
  final double discounts;
  final double employeeFreeMeals;
  final double netSales;
  final int ordersCount;

  final double cashCollected;
  final double cardCollected;
  final double cardFeeAbsorbed;
  final double platformCollected;
  final double otherCollected;
  final double realCollected;

  /// Tips belong to staff, NEVER included in [realCollected] or [netSales].
  final double tipsTotal;

  /// Total supplier purchases invoiced in period (NOT equal to COGS).
  final double purchasesTotal;

  /// Theoretical Cost of Goods Sold computed from recipes + yields + item costs.
  final double estimatedCogs;
  final double cogsCoveredRevenue;
  final double cogsMissingRevenue;

  final double operatingExpensesPaid;
  final double cashDrawerExpenses;
  final double historicalExpenses;
  final double payrollExpenses;

  /// [netSales] - [estimatedCogs] (partial when [cogsMissingRevenue] > 0).
  final double grossProfit;

  /// Backoffice 1.0 parity operating result:
  /// [realCollected] - [operatingExpensesPaid] - [purchasesTotal].
  final double operatingResultFlow;

  /// Accounting operating profit:
  /// [netSales] - [estimatedCogs] - [operatingExpensesPaid].
  final double operatingProfitAccounting;

  final double? profitMarginPercent;

  final double accountsPayableTotal;
  final double supplierPaidFromSales;
  final double supplierPaidByPartners;

  /// Deduplicated partner contributions (NEVER counted as restaurant sales).
  final double partnerContributionsTotal;

  final double operatingCashFlow;
  final double cashFlowWithPartners;

  final List<ExpenseConceptBreakdown> expensesByConcept;
  final Map<String, double> expensesByBranch;

  bool get hasCompleteCogs => cogsMissingRevenue <= 0.01 && netSales > 0;
  bool get hasPartialCogs =>
      cogsCoveredRevenue > 0.01 && cogsMissingRevenue > 0.01;
  double get cogsCoveragePercent =>
      netSales > 0.005 ? (cogsCoveredRevenue / netSales) * 100.0 : 0.0;
  double get coveredGrossProfit => cogsCoveredRevenue - estimatedCogs;

  static FinancePeriodSummary compute({
    required List<PosOrder> orders,
    Map<String, List<OrderItem>> itemsByOrder = const {},
    Map<String, List<Payment>> paymentsByOrder = const {},
    required List<CashSession> cashSessions,
    required List<CashWithdrawalRequest> withdrawals,
    required List<SupplierPurchase> purchases,
    required List<SupplierPayment> supplierPayments,
    required List<PartnerContribution> partnerContributions,
    required List<ProductProfitabilityRow> productProfitability,
  }) {
    final salesSummary = BackofficeSalesAdapter.buildCanonicalSummary(
      orders: orders,
      itemsByOrder: itemsByOrder,
      paymentsByOrder: paymentsByOrder,
    );

    var cashCollected = 0.0;
    var cardCollected = 0.0;
    var cardFeeAbsorbed = 0.0;
    var platformCollected = 0.0;
    var otherCollected = 0.0;
    var tipsTotal = 0.0;
    for (final list in paymentsByOrder.values) {
      for (final p in list) {
        if (isCanonicalActivePayment(p) && p.tipAmount > 0) {
          tipsTotal += p.tipAmount;
        }
      }
    }

    if (cashSessions.isNotEmpty) {
      for (final s in cashSessions) {
        final expectedCashIncome =
            s.expectedCashAmount -
            s.openingCashAmount +
            s.approvedWithdrawalsTotal;
        final cash = s.isClosed
            ? (s.countedCashAmount -
                  s.openingCashAmount +
                  s.approvedWithdrawalsTotal)
            : expectedCashIncome;
        cashCollected += cash > 0 ? cash : 0.0;
        final cardBase = s.isClosed && s.terminalReportedAmount > 0
            ? s.terminalReportedAmount
            : s.expectedCardChargedAmount;
        cardFeeAbsorbed += s.expectedCardFeeAbsorbedAmount;
        cardCollected += (cardBase - s.expectedCardFeeAbsorbedAmount).clamp(
          0.0,
          double.infinity,
        );
        platformCollected += s.expectedPlatformAmount;
      }
    } else {
      cashCollected = salesSummary.cashCollected;
      cardCollected = salesSummary.cardCollected;
      platformCollected = salesSummary.platformCollected;
      otherCollected = salesSummary.otherCollected;
    }

    final realCollected =
        cashCollected + cardCollected + platformCollected + otherCollected;

    // Operating expenses (excluding supplier payments & partner contributions)
    final operatingExpenses = withdrawals
        .where(isFinanceOperatingExpense)
        .toList(growable: false);
    var operatingExpensesPaid = 0.0;
    var cashDrawerExpenses = 0.0;
    var historicalExpenses = 0.0;
    var payrollExpenses = 0.0;

    final conceptBuckets = <String, List<CashWithdrawalRequest>>{};
    final branchTotals = <String, double>{};

    for (final w in operatingExpenses) {
      operatingExpensesPaid += w.amount;
      if (w.isHistorical) {
        historicalExpenses += w.amount;
      } else {
        cashDrawerExpenses += w.amount;
      }
      if (isPayrollExpense(w)) {
        payrollExpenses += w.amount;
      }
      final label = normalizeExpenseConcept(w.reason);
      conceptBuckets.putIfAbsent(label, () => []).add(w);
      branchTotals[w.branchId] = (branchTotals[w.branchId] ?? 0.0) + w.amount;
    }

    final expensesByConcept =
        conceptBuckets.entries
            .map((e) {
              var total = 0.0;
              var hist = 0.0;
              var drawer = 0.0;
              for (final item in e.value) {
                total += item.amount;
                if (item.isHistorical) {
                  hist += item.amount;
                } else {
                  drawer += item.amount;
                }
              }
              return ExpenseConceptBreakdown(
                concept: e.key,
                totalAmount: total,
                count: e.value.length,
                historicalAmount: hist,
                cashDrawerAmount: drawer,
              );
            })
            .toList()
          ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    // Active supplier purchases & CXP
    final activePurchases = purchases
        .where((p) => p.status.trim().toLowerCase() != 'cancelled')
        .toList(growable: false);
    final purchasesTotal = activePurchases.fold<double>(
      0.0,
      (acc, p) => acc + p.total,
    );
    final accountsPayableTotal = activePurchases.fold<double>(
      0.0,
      (acc, p) => acc + (p.balance > 0 ? p.balance : 0.0),
    );

    // Supplier payments split by funding source
    final activePayments = supplierPayments
        .where((p) => p.status.trim().toLowerCase() != 'cancelled')
        .toList(growable: false);
    var supplierPaidFromSales = 0.0;
    var supplierPaidByPartners = 0.0;
    final linkedPaymentIds = <String>{};
    for (final p in activePayments) {
      if (isPartnerSupplierPayment(p)) {
        supplierPaidByPartners += p.amount;
        linkedPaymentIds.add(p.id);
      } else {
        supplierPaidFromSales += p.amount;
      }
    }

    // Deduplicate PartnerContribution rows already counted via linkedSupplierPaymentId
    var standalonePartnerContributions = 0.0;
    for (final c in partnerContributions) {
      if (c.status.trim().toLowerCase() == 'cancelled') continue;
      final linked = (c.linkedSupplierPaymentId ?? '').trim();
      if (linked.isNotEmpty && linkedPaymentIds.contains(linked)) {
        continue;
      }
      standalonePartnerContributions += c.amount;
    }
    final partnerContributionsTotal =
        supplierPaidByPartners + standalonePartnerContributions;

    // Theoretical COGS from product profitability
    var estimatedCogs = 0.0;
    var cogsCoveredRevenue = 0.0;
    var cogsMissingRevenue = 0.0;
    for (final row in productProfitability) {
      if (row.hasCost && row.totalCost != null) {
        estimatedCogs += row.totalCost!;
        cogsCoveredRevenue += row.netRevenue;
      } else {
        cogsMissingRevenue += row.netRevenue;
      }
    }

    final netSales = salesSummary.netSales;
    final grossProfit = netSales - estimatedCogs;
    final operatingResultFlow =
        realCollected - operatingExpensesPaid - purchasesTotal;
    final operatingProfitAccounting =
        netSales - estimatedCogs - operatingExpensesPaid;
    final profitMarginPercent =
        (netSales <= 0.005 || cogsMissingRevenue > 0.01)
            ? null
            : (operatingProfitAccounting / netSales) * 100.0;

    final operatingCashFlow =
        realCollected - operatingExpensesPaid - supplierPaidFromSales;
    final cashFlowWithPartners =
        operatingCashFlow +
        partnerContributionsTotal -
        supplierPaidByPartners;

    return FinancePeriodSummary(
      grossSales: salesSummary.grossSales,
      discounts: salesSummary.discountTotal,
      employeeFreeMeals: salesSummary.employeeFreeMealTotal,
      netSales: netSales,
      ordersCount: salesSummary.paidOrdersCount,
      cashCollected: cashCollected,
      cardCollected: cardCollected,
      cardFeeAbsorbed: cardFeeAbsorbed,
      platformCollected: platformCollected,
      otherCollected: otherCollected,
      realCollected: realCollected,
      tipsTotal: tipsTotal,
      purchasesTotal: purchasesTotal,
      estimatedCogs: estimatedCogs,
      cogsCoveredRevenue: cogsCoveredRevenue,
      cogsMissingRevenue: cogsMissingRevenue,
      operatingExpensesPaid: operatingExpensesPaid,
      cashDrawerExpenses: cashDrawerExpenses,
      historicalExpenses: historicalExpenses,
      payrollExpenses: payrollExpenses,
      grossProfit: grossProfit,
      operatingResultFlow: operatingResultFlow,
      operatingProfitAccounting: operatingProfitAccounting,
      profitMarginPercent: profitMarginPercent,
      accountsPayableTotal: accountsPayableTotal,
      supplierPaidFromSales: supplierPaidFromSales,
      supplierPaidByPartners: supplierPaidByPartners,
      partnerContributionsTotal: partnerContributionsTotal,
      operatingCashFlow: operatingCashFlow,
      cashFlowWithPartners: cashFlowWithPartners,
      expensesByConcept: expensesByConcept,
      expensesByBranch: branchTotals,
    );
  }
}

class ProductSaleAggregate {
  const ProductSaleAggregate({
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.unitsSold,
    required this.netRevenue,
  });

  final String productId;
  final String productName;
  final String categoryName;
  final double unitsSold;
  final double netRevenue;
}

class IngredientCostEstimate {
  const IngredientCostEstimate({
    required this.stockItemId,
    required this.costPerBaseUnit,
    required this.baseUnit,
    required this.isHistoricalFallback,
  });

  final String stockItemId;
  final double costPerBaseUnit;
  final String baseUnit;
  final bool isHistoricalFallback;
}

class ProductProfitabilityRow {
  const ProductProfitabilityRow({
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.unitsSold,
    required this.avgRealPrice,
    required this.netRevenue,
    required this.hasRecipe,
    required this.hasCost,
    required this.usesHistoricalCost,
    required this.theoreticalUnitCost,
    required this.totalCost,
    required this.estimatedGrossProfit,
    required this.marginPercent,
    required this.salesSharePercent,
    required this.profitSharePercent,
    required this.costNote,
  });

  final String productId;
  final String productName;
  final String categoryName;
  final double unitsSold;
  final double avgRealPrice;
  final double netRevenue;
  final bool hasRecipe;
  final bool hasCost;
  final bool usesHistoricalCost;
  final double? theoreticalUnitCost;
  final double? totalCost;
  final double? estimatedGrossProfit;
  final double? marginPercent;
  final double salesSharePercent;
  final double? profitSharePercent;
  final String costNote;
}

double convertToBaseUnit(double qty, String unit) {
  final u = unit.trim().toLowerCase();
  if (u == 'kg' || u == 'l' || u == 'lt' || u == 'litro' || u == 'litros') {
    return qty * 1000.0;
  }
  return qty;
}

String normalizeBaseUnitFamily(String unit) {
  final u = unit.trim().toLowerCase();
  if (u == 'kg' || u == 'g' || u == 'gr' || u == 'gramo' || u == 'gramos') {
    return 'g';
  }
  if (u == 'l' || u == 'lt' || u == 'ml' || u == 'litro' || u == 'litros') {
    return 'ml';
  }
  return 'piece';
}

/// Computes weighted-average ingredient costs per base unit (`g`, `ml`, `piece`),
/// distinguishing current-period costs from historical fallback costs.
Map<String, IngredientCostEstimate> resolveIngredientCosts({
  required List<SupplierPurchaseItem> periodPurchaseItems,
  required List<SupplierPurchaseItem> historicalPurchaseItems,
}) {
  final result = <String, IngredientCostEstimate>{};
  final periodBuckets = <String, List<SupplierPurchaseItem>>{};
  for (final item in periodPurchaseItems) {
    final stockId = (item.kitchenStockItemId ?? '').trim();
    if (stockId.isEmpty || item.quantity <= 0 || item.lineTotal <= 0) continue;
    periodBuckets.putIfAbsent(stockId, () => []).add(item);
  }

  for (final entry in periodBuckets.entries) {
    var totalCost = 0.0;
    var totalBase = 0.0;
    var baseFamily = 'g';
    for (final item in entry.value) {
      totalCost += item.lineTotal;
      totalBase += convertToBaseUnit(item.quantity, item.unit);
      baseFamily = normalizeBaseUnitFamily(item.unit);
    }
    if (totalBase > 0) {
      result[entry.key] = IngredientCostEstimate(
        stockItemId: entry.key,
        costPerBaseUnit: totalCost / totalBase,
        baseUnit: baseFamily,
        isHistoricalFallback: false,
      );
    }
  }

  for (final item in historicalPurchaseItems) {
    final stockId = (item.kitchenStockItemId ?? '').trim();
    if (stockId.isEmpty ||
        result.containsKey(stockId) ||
        item.quantity <= 0 ||
        item.lineTotal <= 0) {
      continue;
    }
    final baseQty = convertToBaseUnit(item.quantity, item.unit);
    if (baseQty > 0) {
      result[stockId] = IngredientCostEstimate(
        stockItemId: stockId,
        costPerBaseUnit: item.lineTotal / baseQty,
        baseUnit: normalizeBaseUnitFamily(item.unit),
        isHistoricalFallback: true,
      );
    }
  }
  return result;
}

/// Builds product-level profitability matching Backoffice 1.0's yield & recipe rules.
///
/// Products without a complete recipe or without ingredient cost data NEVER
/// default to zero cost; instead `hasCost = false` and `theoreticalUnitCost = null`.
List<ProductProfitabilityRow> buildProductProfitabilityReport({
  required List<ProductSaleAggregate> sales,
  required List<TheoreticalProductRecipe> recipes,
  required List<IngredientYieldProfile> yieldProfiles,
  required Map<String, IngredientCostEstimate> ingredientCosts,
}) {
  final recipeByProduct = {for (final r in recipes) r.productId: r};
  final yieldByStock = {for (final y in yieldProfiles) y.stockItemId: y};
  final totalSalesRevenue = sales.fold<double>(
    0.0,
    (acc, s) => acc + s.netRevenue,
  );

  final drafts = <_ProfitDraft>[];
  var totalEstimatedProfit = 0.0;

  for (final s in sales) {
    final avgPrice = s.unitsSold > 0 ? s.netRevenue / s.unitsSold : 0.0;
    final recipe = recipeByProduct[s.productId];
    if (recipe == null ||
        !recipe.active ||
        recipe.ingredients.isEmpty ||
        recipe.recipeStatus != 'complete') {
      drafts.add(
        _ProfitDraft(
          sale: s,
          avgPrice: avgPrice,
          hasRecipe: recipe != null && recipe.ingredients.isNotEmpty,
          hasCost: false,
          usesHistoricalCost: false,
          unitCost: null,
          totalCost: null,
          grossProfit: null,
          marginPercent: null,
          costNote: recipe == null || recipe.ingredients.isEmpty
              ? 'Costo no disponible (sin receta teórica)'
              : 'Costo no disponible (receta incompleta)',
        ),
      );
      continue;
    }

    var unitCost = 0.0;
    var valid = true;
    var usesHistorical = false;
    var missingReason = '';

    for (final ing in recipe.ingredients) {
      final cost = ingredientCosts[ing.stockItemId];
      if (cost == null) {
        valid = false;
        missingReason =
            'Costo no disponible (sin compras de ${ing.stockItemName})';
        break;
      }
      final ingFamily = normalizeBaseUnitFamily(ing.unit);
      if (ingFamily != cost.baseUnit) {
        valid = false;
        missingReason =
            'Costo no disponible (unidad incompatible en ${ing.stockItemName})';
        break;
      }
      var rawBaseQty = convertToBaseUnit(ing.quantity, ing.unit);
      if (ing.inputStage == 'cooked') {
        final yp = yieldByStock[ing.stockItemId];
        final rate = yp?.cookingYieldRate ?? 1.0;
        if (rate <= 0) {
          valid = false;
          missingReason =
              'Costo no disponible (rendimiento inválido en ${ing.stockItemName})';
          break;
        }
        rawBaseQty = rawBaseQty / rate;
      }
      if (cost.isHistoricalFallback) usesHistorical = true;
      unitCost += rawBaseQty * cost.costPerBaseUnit;
    }

    if (!valid) {
      drafts.add(
        _ProfitDraft(
          sale: s,
          avgPrice: avgPrice,
          hasRecipe: true,
          hasCost: false,
          usesHistoricalCost: false,
          unitCost: null,
          totalCost: null,
          grossProfit: null,
          marginPercent: null,
          costNote: missingReason,
        ),
      );
      continue;
    }

    final totalCost = unitCost * s.unitsSold;
    final profit = s.netRevenue - totalCost;
    final margin = s.netRevenue > 0.005 ? (profit / s.netRevenue) * 100.0 : null;
    totalEstimatedProfit += profit;

    drafts.add(
      _ProfitDraft(
        sale: s,
        avgPrice: avgPrice,
        hasRecipe: true,
        hasCost: true,
        usesHistoricalCost: usesHistorical,
        unitCost: unitCost,
        totalCost: totalCost,
        grossProfit: profit,
        marginPercent: margin,
        costNote: usesHistorical
            ? 'Costo teórico (insumo con costo histórico)'
            : 'Costo teórico del periodo',
      ),
    );
  }

  return drafts
      .map(
        (d) => ProductProfitabilityRow(
          productId: d.sale.productId,
          productName: d.sale.productName,
          categoryName: d.sale.categoryName,
          unitsSold: d.sale.unitsSold,
          avgRealPrice: d.avgPrice,
          netRevenue: d.sale.netRevenue,
          hasRecipe: d.hasRecipe,
          hasCost: d.hasCost,
          usesHistoricalCost: d.usesHistoricalCost,
          theoreticalUnitCost: d.unitCost,
          totalCost: d.totalCost,
          estimatedGrossProfit: d.grossProfit,
          marginPercent: d.marginPercent,
          salesSharePercent: totalSalesRevenue > 0.005
              ? (d.sale.netRevenue / totalSalesRevenue) * 100.0
              : 0.0,
          profitSharePercent:
              d.grossProfit != null && totalEstimatedProfit.abs() > 0.005
              ? (d.grossProfit! / totalEstimatedProfit) * 100.0
              : null,
          costNote: d.costNote,
        ),
      )
      .toList(growable: false)
    ..sort((a, b) => b.netRevenue.compareTo(a.netRevenue));
}

class _ProfitDraft {
  const _ProfitDraft({
    required this.sale,
    required this.avgPrice,
    required this.hasRecipe,
    required this.hasCost,
    required this.usesHistoricalCost,
    required this.unitCost,
    required this.totalCost,
    required this.grossProfit,
    required this.marginPercent,
    required this.costNote,
  });

  final ProductSaleAggregate sale;
  final double avgPrice;
  final bool hasRecipe;
  final bool hasCost;
  final bool usesHistoricalCost;
  final double? unitCost;
  final double? totalCost;
  final double? grossProfit;
  final double? marginPercent;
  final String costNote;
}

class BreakEvenAnalysis {
  const BreakEvenAnalysis({
    required this.horizon,
    required this.fixedCosts,
    required this.variableCostRatio,
    required this.contributionMarginRatio,
    required this.breakEvenSales,
    required this.accumulatedSales,
    required this.gapToBreakEven,
    required this.projectedEndSales,
    required this.requiredDailySalesRemaining,
    required this.isReached,
  });

  final BreakEvenHorizon horizon;
  final double fixedCosts;
  final double variableCostRatio;
  final double contributionMarginRatio;
  final double? breakEvenSales;
  final double accumulatedSales;
  final double? gapToBreakEven;
  final double projectedEndSales;
  final double? requiredDailySalesRemaining;
  final bool isReached;

  static BreakEvenAnalysis compute({
    required BreakEvenHorizon horizon,
    required double fixedCosts,
    required double variableCostRatio,
    required double accumulatedSales,
    required int elapsedDays,
    required int totalDaysInPeriod,
  }) {
    final safeVarRatio = variableCostRatio.clamp(0.0, 0.99);
    final contributionMargin = 1.0 - safeVarRatio;
    final breakEven = contributionMargin > 0.001
        ? fixedCosts / contributionMargin
        : null;
    final gap = breakEven == null ? null : breakEven - accumulatedSales;
    final safeElapsed = elapsedDays > 0 ? elapsedDays : 1;
    final safeTotalDays = totalDaysInPeriod > 0
        ? totalDaysInPeriod
        : horizon.defaultDays;
    final dailyRunRate = accumulatedSales / safeElapsed;
    final projected = dailyRunRate * safeTotalDays;
    final remainingDays = (safeTotalDays - safeElapsed).clamp(0, safeTotalDays);
    final reqDaily = gap == null || gap <= 0 || remainingDays == 0
        ? 0.0
        : gap / remainingDays;

    return BreakEvenAnalysis(
      horizon: horizon,
      fixedCosts: fixedCosts,
      variableCostRatio: safeVarRatio,
      contributionMarginRatio: contributionMargin,
      breakEvenSales: breakEven,
      accumulatedSales: accumulatedSales,
      gapToBreakEven: gap,
      projectedEndSales: projected,
      requiredDailySalesRemaining: breakEven == null ? null : reqDaily,
      isReached: breakEven != null && accumulatedSales >= breakEven,
    );
  }
}

class EfficiencyMetricRow {
  const EfficiencyMetricRow({
    required this.key,
    required this.label,
    required this.actualPercent,
    required this.targetPercent,
    required this.amount,
    required this.note,
  });

  final String key;
  final String label;
  final double? actualPercent;
  final double targetPercent;
  final double amount;
  final String note;

  bool get isOverTarget =>
      actualPercent != null && actualPercent! > targetPercent;
}

List<EfficiencyMetricRow> buildEfficiencyComparisons({
  required FinancePeriodSummary summary,
  required List<KitchenSessionItem> kitchenItems,
  required Map<String, double> targetsByKey,
}) {
  final sales = summary.netSales;
  double? pct(double value) => sales > 0.005 ? (value / sales) * 100.0 : null;

  var totalMerma = 0.0;
  var totalUsed = 0.0;
  for (final k in kitchenItems) {
    totalMerma += k.wasteQty;
    totalUsed += k.usedQty;
  }
  final mermaPct = totalUsed > 0.005 ? (totalMerma / totalUsed) * 100.0 : null;

  return [
    EfficiencyMetricRow(
      key: 'purchases_vs_sales',
      label: 'Compras vs Ventas netas',
      actualPercent: pct(summary.purchasesTotal),
      targetPercent: targetsByKey['purchases_vs_sales'] ?? 35.0,
      amount: summary.purchasesTotal,
      note: 'Flujo de abastecimiento (no equivale a COGS)',
    ),
    EfficiencyMetricRow(
      key: 'cogs_vs_sales',
      label: 'Costo de venta teórico vs Ventas',
      actualPercent: summary.cogsCoveredRevenue > 0.005
          ? (summary.estimatedCogs / summary.cogsCoveredRevenue) * 100.0
          : null,
      targetPercent: targetsByKey['cogs_vs_sales'] ?? 32.0,
      amount: summary.estimatedCogs,
      note: summary.hasCompleteCogs
          ? 'Cobertura completa de recetas'
          : 'Cobertura parcial (${summary.cogsCoveragePercent.toStringAsFixed(0)}% de ventas con receta/costo)',
    ),
    EfficiencyMetricRow(
      key: 'payroll_vs_sales',
      label: 'Nómina vs Ventas netas',
      actualPercent: pct(summary.payrollExpenses),
      targetPercent: targetsByKey['payroll_vs_sales'] ?? 18.0,
      amount: summary.payrollExpenses,
      note: summary.payrollExpenses > 0
          ? 'Gastos identificados como nómina/sueldos'
          : 'Sin registros explícitos de nómina en el periodo',
    ),
    EfficiencyMetricRow(
      key: 'opex_vs_sales',
      label: 'Gastos operativos vs Ventas',
      actualPercent: pct(summary.operatingExpensesPaid),
      targetPercent: targetsByKey['opex_vs_sales'] ?? 20.0,
      amount: summary.operatingExpensesPaid,
      note: 'Retiros operativos aprobados + gastos históricos',
    ),
    EfficiencyMetricRow(
      key: 'profit_vs_sales',
      label: 'Utilidad operativa vs Ventas',
      actualPercent: pct(summary.operatingProfitAccounting),
      targetPercent: targetsByKey['profit_vs_sales'] ?? 20.0,
      amount: summary.operatingProfitAccounting,
      note: 'Ventas netas - COGS teórico - gastos operativos',
    ),
    EfficiencyMetricRow(
      key: 'merma_vs_consumption',
      label: 'Merma cocina vs Consumo',
      actualPercent: mermaPct,
      targetPercent: targetsByKey['merma_vs_consumption'] ?? 5.0,
      amount: totalMerma,
      note: totalUsed > 0
          ? 'Consumo medido en sesiones de cocina'
          : 'Sin sesiones de cocina cerradas en el periodo',
    ),
  ];
}

class PartnerShareProposal {
  const PartnerShareProposal({
    required this.partner,
    required this.contributedInPeriod,
    required this.proposedShareAmount,
  });

  final Partner partner;
  final double contributedInPeriod;
  final double proposedShareAmount;
}

class PartnerFinanceSummary {
  const PartnerFinanceSummary({
    required this.totalContributed,
    required this.distributableBase,
    required this.proposals,
  });

  final double totalContributed;
  final double distributableBase;
  final List<PartnerShareProposal> proposals;
}

PartnerFinanceSummary buildPartnerFinanceSummary({
  required List<Partner> partners,
  required List<SupplierPayment> supplierPayments,
  required List<PartnerContribution> contributions,
  required double distributableBase,
}) {
  final byPartner = <String, double>{};
  final linkedPaymentIds = <String>{};

  for (final p in supplierPayments) {
    if (p.status.trim().toLowerCase() == 'cancelled') continue;
    if (!isPartnerSupplierPayment(p)) continue;
    linkedPaymentIds.add(p.id);
    final pid = (p.partnerId ?? '').trim();
    if (pid.isNotEmpty) {
      byPartner[pid] = (byPartner[pid] ?? 0.0) + p.amount;
    }
  }

  for (final c in contributions) {
    if (c.status.trim().toLowerCase() == 'cancelled') continue;
    final linked = (c.linkedSupplierPaymentId ?? '').trim();
    if (linked.isNotEmpty && linkedPaymentIds.contains(linked)) continue;
    byPartner[c.partnerId] = (byPartner[c.partnerId] ?? 0.0) + c.amount;
  }

  final safeBase = distributableBase > 0 ? distributableBase : 0.0;
  final proposals = partners
      .map(
        (partner) => PartnerShareProposal(
          partner: partner,
          contributedInPeriod: byPartner[partner.id] ?? 0.0,
          proposedShareAmount: safeBase * (partner.ownershipPercent / 100.0),
        ),
      )
      .toList(growable: false);

  final total = byPartner.values.fold<double>(0.0, (a, b) => a + b);
  return PartnerFinanceSummary(
    totalContributed: total,
    distributableBase: safeBase,
    proposals: proposals,
  );
}
