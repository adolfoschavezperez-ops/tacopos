import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/cash/cash_close_execution.dart';
import '../core/cash/cash_session_timing.dart';
import '../core/cash/operational_business_date.dart';
import '../core/orders/backoffice_sales_cancellation.dart';
import '../core/orders/global_discount_checkout.dart';
import '../core/orders/employee_benefit_checkout.dart';
import '../core/orders/order_activity.dart';
import '../core/orders/order_payment_reconciliation.dart';
import '../core/orders/order_types.dart';
import '../core/expenses/expense_policy.dart';
import '../core/expenses/local_expense_policy_flow.dart';
import '../core/payments/payment_operational_scope.dart';
import '../core/purchases/purchase_capture_discount.dart';
import '../core/reports/canonical_sales_summary.dart';
import '../core/reports/cash_difference_audit.dart';
import '../core/reports/cash_schedule_report.dart';
import '../core/reports/finance_dashboard.dart';
import '../core/reports/hourly_sales_comparison.dart';
import '../core/reports/operational_blockers.dart';
import '../core/reports/report_data_bundle.dart';
import '../core/reports/report_performance_tracer.dart';
import '../core/reports/yield_profit_report.dart';
import '../core/sales/daily_sale_folio.dart';
import '../core/visits/visit_classification.dart';
import '../models/cash_session.dart';
import '../models/cash_withdrawal_request.dart';
import '../models/active_session.dart';
import '../models/activity_event.dart';
import '../models/branch.dart';
import '../models/discount_authorization_request.dart';
import '../models/employee.dart';
import '../models/kitchen_session.dart';
import '../models/kitchen_stock_item.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../models/order_platform.dart';
import '../models/payment.dart';
import '../models/pos_table.dart';
import '../models/product.dart';
import '../models/product_category.dart';
import '../models/product_recipe_item.dart';
import '../models/purchase_models.dart';
import '../models/restaurant.dart';
import '../models/yield_profit_models.dart';
import '../utils/category_utils.dart';
import 'app_session.dart';
import 'device_registry_service.dart';
import 'operational_auth_service.dart';

export '../core/orders/order_activity.dart'
    show
        isActiveCustomerPayment,
        isActiveOrderItem,
        isActiveOrderState,
        activeOrderItems,
        activeOrderItemsTotal,
        hasActiveOrderItems,
        isActivePayment,
        isGhostOrder,
        isPartialCancellationWithActiveItems,
        awaitingKitchenSendItemsCount,
        itemWasSentToKitchen,
        hasPendingKitchenItems,
        hasItemsAwaitingKitchenSend,
        itemCanBeSentToKitchenBatch,
        itemIsAwaitingKitchenSend,
        isKitchenPendingItem,
        isKitchenReadyItem,
        itemRequiresKitchen,
        kitchenStatusForItems,
        isOperationalOrderActive,
        shouldKeepTableOccupiedForOrder,
        isStandingOrderVisibleInLiveViewer;
export '../core/orders/table_operational_status.dart';
export '../core/orders/order_types.dart';

double _numberToDouble(Object? value) {
  return value is num ? value.toDouble() : 0.0;
}

DateTime? _timestampToDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  return null;
}

class KitchenOrderBundle {
  const KitchenOrderBundle({required this.order, required this.items});

  final PosOrder order;
  final List<OrderItem> items;

  String get kitchenBatchId {
    for (final item in items) {
      final batchId = item.kitchenBatchId?.trim();
      if (batchId != null && batchId.isNotEmpty) return batchId;
    }
    return '';
  }

  String get stableKitchenKey {
    final batchId = kitchenBatchId;
    return batchId.isEmpty ? 'order:${order.id}' : 'order:${order.id}:$batchId';
  }

  bool get isKitchenExpress {
    return items.any(
      (item) =>
          item.isKitchenExpress ||
          item.kitchenBatchType.trim().toLowerCase() == 'express',
    );
  }

  String get kitchenBatchLabel =>
      isKitchenExpress ? 'Surtido express' : 'Orden inicial';

  int get personCount => items.map((item) => item.personNumber).toSet().length;

  String get personLabel {
    final namesByPerson = <int, String>{};
    for (final item in items) {
      namesByPerson.putIfAbsent(item.personNumber, () => item.personName);
    }
    final names = namesByPerson.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return names.map((entry) => entry.value).join(', ');
  }

  DateTime? get firstSentToKitchenAt {
    return items
        .map((item) => item.sentToKitchenAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (min, date) => min == null || date.isBefore(min) ? date : min,
        );
  }

  String get shortSummary {
    final counts = <String, int>{};
    for (final item in items) {
      counts[item.productName] = (counts[item.productName] ?? 0) + item.qty;
    }

    return counts.entries
        .take(3)
        .map((entry) => '${entry.value} ${entry.key}')
        .join(' · ');
  }

  List<MapEntry<String, double>> get ingredientSummary {
    final counts = <String, double>{};
    for (final item in items) {
      if (item.recipeItems.isNotEmpty) {
        final recipeItem = item.recipeItems.first;
        final key = recipeItem.kitchenStockItemName.trim().isNotEmpty
            ? recipeItem.kitchenStockItemName.trim()
            : recipeItem.kitchenStockItemId;
        counts[key] =
            (counts[key] ?? 0) + item.qty * recipeItem.consumptionFactor;
        continue;
      }
      final key =
          (item.kitchenStockItemName?.trim().isNotEmpty == true
                  ? item.kitchenStockItemName
                  : item.productName)!
              .trim();
      counts[key] = (counts[key] ?? 0) + item.qty;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }
}

class _KitchenSendTransactionResult {
  const _KitchenSendTransactionResult({
    required this.order,
    required this.sentCount,
  });

  final PosOrder order;
  final int sentCount;
}

class LiveStandingOrderBundle {
  const LiveStandingOrderBundle({
    required this.order,
    required this.items,
    required this.payments,
  });

  final PosOrder order;
  final List<OrderItem> items;
  final List<Payment> payments;
}

class PaymentResult {
  const PaymentResult({required this.allPaid, this.saleFolioDisplay});

  final bool allPaid;
  final String? saleFolioDisplay;
}

class SaleFolioPaymentException implements Exception {
  const SaleFolioPaymentException({
    required this.stage,
    required this.code,
    required this.message,
    required this.plugin,
    required this.originalError,
    required this.stackTrace,
  });

  final String stage;
  final String code;
  final String message;
  final String plugin;
  final Object originalError;
  final StackTrace stackTrace;

  @override
  String toString() {
    return 'No se pudo completar el cobro con folio diario. '
        'Etapa: $stage. Codigo: $code. $message';
  }
}

class BackofficeCancellationResult {
  const BackofficeCancellationResult({
    required this.affectedClosedCashSession,
    this.previousPaidTotal = 0,
    this.newPaidTotal = 0,
    this.previousPendingTotal = 0,
    this.newPendingTotal = 0,
    this.cancelledItemsCount = 0,
  });

  final bool affectedClosedCashSession;
  final double previousPaidTotal;
  final double newPaidTotal;
  final double previousPendingTotal;
  final double newPendingTotal;
  final int cancelledItemsCount;
}

class OrderTotalsRecalculation {
  const OrderTotalsRecalculation({
    required this.orderId,
    required this.grossSubtotal,
    required this.discountAmount,
    required this.netTotal,
    required this.changed,
  });

  final String orderId;
  final double grossSubtotal;
  final double discountAmount;
  final double netTotal;
  final bool changed;
}

class OperationalStateReconciliationResult {
  const OperationalStateReconciliationResult({
    required this.orderId,
    required this.folio,
    required this.tableId,
    required this.tableName,
    required this.tableStatusBefore,
    required this.tableStatusAfter,
    required this.orderStatus,
    required this.orderKitchenStatusBefore,
    required this.orderKitchenStatusAfter,
    required this.activeItemsCount,
    required this.pendingKitchenItemsCount,
    required this.readyKitchenItemsCount,
    required this.cancelledItemsCount,
    required this.kitchenViewerIncluded,
    required this.chargeBlocked,
    required this.repairApplied,
    required this.reason,
  });

  final String orderId;
  final String folio;
  final String tableId;
  final String tableName;
  final String tableStatusBefore;
  final String tableStatusAfter;
  final String orderStatus;
  final String orderKitchenStatusBefore;
  final String orderKitchenStatusAfter;
  final int activeItemsCount;
  final int pendingKitchenItemsCount;
  final int readyKitchenItemsCount;
  final int cancelledItemsCount;
  final bool kitchenViewerIncluded;
  final bool chargeBlocked;
  final bool repairApplied;
  final String reason;
}

class CheckoutPreparation {
  const CheckoutPreparation({
    required this.orderId,
    required this.grossSubtotal,
    required this.discountAmount,
    required this.netTotal,
    required this.discountSource,
    required this.discountCatalogId,
    required this.discountName,
    required this.discountPercent,
    required this.frozenByPayments,
  });

  final String orderId;
  final double grossSubtotal;
  final double discountAmount;
  final double netTotal;
  final String discountSource;
  final String? discountCatalogId;
  final String? discountName;
  final double discountPercent;
  final bool frozenByPayments;

  bool get hasGlobalDiscount =>
      discountSource == globalDiscountSource && discountAmount > 0.01;
}

class OrderTotalsCorrectionPreview {
  const OrderTotalsCorrectionPreview({
    required this.safe,
    required this.message,
    required this.grossSubtotal,
    required this.discountAmount,
    required this.netTotal,
    required this.paymentTotal,
    required this.totalLiquidated,
    required this.previousDiscountAmount,
    required this.previousNetTotal,
    required this.previousTotal,
    required this.newTotal,
    required this.previousPaidTotal,
    required this.newPaidTotal,
    required this.previousPendingTotal,
    required this.newPendingTotal,
    required this.hasDiscount,
  });

  final bool safe;
  final String message;
  final double grossSubtotal;
  final double discountAmount;
  final double netTotal;
  final double paymentTotal;
  final double totalLiquidated;
  final double previousDiscountAmount;
  final double previousNetTotal;
  final double previousTotal;
  final double newTotal;
  final double previousPaidTotal;
  final double newPaidTotal;
  final double previousPendingTotal;
  final double newPendingTotal;
  final bool hasDiscount;
}

class BranchSummary {
  const BranchSummary({
    required this.tableCount,
    required this.openOrderCount,
    required this.cashOpen,
    required this.employeeAccessCount,
  });

  final int tableCount;
  final int openOrderCount;
  final bool cashOpen;
  final int employeeAccessCount;
}

class HistoricalCashCorrectionPreview {
  const HistoricalCashCorrectionPreview({
    required this.branch,
    required this.businessDate,
    required this.cashSessionId,
    required this.existingSession,
    required this.openingCashAmount,
    required this.cashSalesAmount,
    required this.cardSalesAmount,
    required this.cardBaseAmount,
    required this.cardSurchargeAmount,
    required this.cardCommissionAmount,
    required this.platformAmount,
    required this.employeeConsumptionAmount,
    required this.approvedWithdrawalsTotal,
    required this.pendingWithdrawalsTotal,
    required this.withdrawalRequestCount,
    required this.countedCashAmount,
    required this.terminalReportedAmount,
    required this.expectedCashAmount,
    required this.cashUserSalesAmount,
    required this.cashSalesExpectedAfterWithdrawals,
    required this.cashDifference,
    required this.cardDifference,
    required this.netDifference,
    required this.totalExpectedRealMoney,
    required this.totalCountedRealMoney,
    required this.shortageAmount,
    required this.overAmount,
    required this.paymentCount,
  });

  final Branch branch;
  final String businessDate;
  final String cashSessionId;
  final CashSession? existingSession;
  final double openingCashAmount;
  final double cashSalesAmount;
  final double cardSalesAmount;
  final double cardBaseAmount;
  final double cardSurchargeAmount;
  final double cardCommissionAmount;
  final double platformAmount;
  final double employeeConsumptionAmount;
  final double approvedWithdrawalsTotal;
  final double pendingWithdrawalsTotal;
  final int withdrawalRequestCount;
  final double countedCashAmount;
  final double terminalReportedAmount;
  final double expectedCashAmount;
  final double cashUserSalesAmount;
  final double cashSalesExpectedAfterWithdrawals;
  final double cashDifference;
  final double cardDifference;
  final double netDifference;
  final double totalExpectedRealMoney;
  final double totalCountedRealMoney;
  final double shortageAmount;
  final double overAmount;
  final int paymentCount;

  bool get hasExistingSession => existingSession != null;
  bool get hasMovements =>
      paymentCount > 0 ||
      approvedWithdrawalsTotal > 0 ||
      pendingWithdrawalsTotal > 0;
}

class HistoricalCashExpenseResult {
  const HistoricalCashExpenseResult({
    required this.cashSession,
    required this.withdrawalRequestId,
    required this.previousApprovedWithdrawals,
    required this.newApprovedWithdrawals,
    required this.previousExpectedCash,
    required this.newExpectedCash,
    required this.previousCashDifference,
    required this.newCashDifference,
  });

  final CashSession cashSession;
  final String withdrawalRequestId;
  final double previousApprovedWithdrawals;
  final double newApprovedWithdrawals;
  final double previousExpectedCash;
  final double newExpectedCash;
  final double previousCashDifference;
  final double newCashDifference;
}

class CashPaymentDetails {
  const CashPaymentDetails({
    required this.receivedAmount,
    required this.changeAmount,
  });

  final double receivedAmount;
  final double changeAmount;
}

class AppliedDiscountDetails {
  const AppliedDiscountDetails({
    required this.type,
    required this.name,
    required this.percent,
    required this.amountBeforeDiscount,
    required this.discountAmount,
    required this.totalAfterDiscount,
    this.orderId,
    this.restaurantId,
    this.branchId,
    this.businessDate,
    this.totalSnapshot,
    this.authorizedByPartnerId,
    this.authorizedByPartnerName,
    this.authorizedByPartnerLinkedEmployeeId,
    this.authorizedByPartnerLinkedEmployeeName,
    this.employeeBeneficiaryId,
    this.employeeBeneficiaryName,
    this.discountAuthorizationRequestId,
    this.authorizationMode = '',
    this.authorizationStatus = '',
    this.reason = '',
  });

  final String type;
  final String name;
  final double percent;
  final double amountBeforeDiscount;
  final double discountAmount;
  final double totalAfterDiscount;
  final String? orderId;
  final String? restaurantId;
  final String? branchId;
  final String? businessDate;
  final double? totalSnapshot;
  final String? authorizedByPartnerId;
  final String? authorizedByPartnerName;
  final String? authorizedByPartnerLinkedEmployeeId;
  final String? authorizedByPartnerLinkedEmployeeName;
  final String? employeeBeneficiaryId;
  final String? employeeBeneficiaryName;
  final String? discountAuthorizationRequestId;
  final String authorizationMode;
  final String authorizationStatus;
  final String reason;
}

class GeneralDiscountConfig {
  const GeneralDiscountConfig({
    required this.active,
    required this.name,
    required this.percent,
    this.catalogId = globalDiscountCatalogId,
    this.description = '',
    this.branchId = 'all',
  });

  final bool active;
  final String name;
  final double percent;
  final String catalogId;
  final String description;
  final String branchId;

  bool appliesToCurrentBranch(String currentBranchId) {
    return active &&
        percent > 0 &&
        (branchId == 'all' || branchId.isEmpty || branchId == currentBranchId);
  }
}

class DiscountUsageRow {
  const DiscountUsageRow({
    required this.id,
    required this.businessDate,
    required this.discountType,
    required this.discountName,
    required this.amountBeforeDiscount,
    required this.discountPercent,
    required this.discountAmount,
    required this.totalAfterDiscount,
    required this.status,
    this.employeeName = '',
    this.partnerName = '',
    this.linkedEmployeeId = '',
    this.linkedEmployeeName = '',
    this.discountAuthorizationRequestId = '',
    this.orderId = '',
    this.createdByEmployeeName = '',
    this.branchId = '',
    this.branchName = '',
  });

  final String id;
  final String businessDate;
  final String discountType;
  final String discountName;
  final double amountBeforeDiscount;
  final double discountPercent;
  final double discountAmount;
  final double totalAfterDiscount;
  final String status;
  final String employeeName;
  final String partnerName;
  final String linkedEmployeeId;
  final String linkedEmployeeName;
  final String discountAuthorizationRequestId;
  final String orderId;
  final String createdByEmployeeName;
  final String branchId;
  final String branchName;

  factory DiscountUsageRow.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return DiscountUsageRow.fromMap(doc.id, data);
  }

  factory DiscountUsageRow.fromMap(String id, Map<String, dynamic> data) {
    return DiscountUsageRow(
      id: id,
      businessDate: data['businessDate'] as String? ?? '',
      discountType: data['discountType'] as String? ?? '',
      discountName: data['discountName'] as String? ?? '',
      amountBeforeDiscount: _numberToDouble(data['amountBeforeDiscount']),
      discountPercent: _numberToDouble(data['discountPercent']),
      discountAmount: _numberToDouble(data['discountAmount']),
      totalAfterDiscount: _numberToDouble(data['totalAfterDiscount']),
      status: data['status'] as String? ?? 'active',
      employeeName: data['employeeName'] as String? ?? '',
      partnerName: data['partnerName'] as String? ?? '',
      linkedEmployeeId: data['linkedEmployeeId'] as String? ?? '',
      linkedEmployeeName: data['linkedEmployeeName'] as String? ?? '',
      discountAuthorizationRequestId:
          data['discountAuthorizationRequestId'] as String? ?? '',
      orderId: data['orderId'] as String? ?? '',
      createdByEmployeeName: data['createdByEmployeeName'] as String? ?? '',
      branchId: data['branchId'] as String? ?? '',
      branchName: data['branchName'] as String? ?? '',
    );
  }
}

class ProductStockOutRow {
  const ProductStockOutRow({
    required this.id,
    required this.businessDate,
    required this.branchId,
    required this.branchName,
    required this.productId,
    required this.productName,
    required this.categoryId,
    required this.categoryName,
    required this.status,
    required this.reason,
    required this.soldOutTimeLabel,
    required this.soldOutByEmployeeId,
    required this.soldOutByEmployeeName,
    this.soldOutAt,
    this.clearedAt,
    this.clearedByEmployeeId = '',
    this.clearedByEmployeeName = '',
    this.clearedReason = '',
  });

  final String id;
  final String businessDate;
  final String branchId;
  final String branchName;
  final String productId;
  final String productName;
  final String categoryId;
  final String categoryName;
  final String status;
  final String reason;
  final DateTime? soldOutAt;
  final String soldOutTimeLabel;
  final String soldOutByEmployeeId;
  final String soldOutByEmployeeName;
  final DateTime? clearedAt;
  final String clearedByEmployeeId;
  final String clearedByEmployeeName;
  final String clearedReason;

  bool get isActive => status == 'active';
  bool get isCleared => status == 'cleared';

  factory ProductStockOutRow.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return ProductStockOutRow(
      id: doc.id,
      businessDate: data['businessDate'] as String? ?? '',
      branchId: data['branchId'] as String? ?? '',
      branchName: data['branchName'] as String? ?? '',
      productId: data['productId'] as String? ?? '',
      productName: data['productName'] as String? ?? '',
      categoryId: data['categoryId'] as String? ?? '',
      categoryName: data['categoryName'] as String? ?? '',
      status: data['status'] as String? ?? 'active',
      reason: data['reason'] as String? ?? '',
      soldOutAt: _timestampToDate(data['soldOutAt'] ?? data['createdAt']),
      soldOutTimeLabel: data['soldOutTimeLabel'] as String? ?? '',
      soldOutByEmployeeId:
          data['soldOutByEmployeeId'] as String? ??
          data['createdByEmployeeId'] as String? ??
          '',
      soldOutByEmployeeName:
          data['soldOutByEmployeeName'] as String? ??
          data['createdByEmployeeName'] as String? ??
          '',
      clearedAt: _timestampToDate(data['clearedAt']),
      clearedByEmployeeId: data['clearedByEmployeeId'] as String? ?? '',
      clearedByEmployeeName: data['clearedByEmployeeName'] as String? ?? '',
      clearedReason: data['clearedReason'] as String? ?? '',
    );
  }
}

class KitchenCloseInput {
  const KitchenCloseInput({
    required this.finalRemainingQty,
    required this.wasteQty,
    required this.notes,
  });

  final double finalRemainingQty;
  final double wasteQty;
  final String notes;
}

class KitchenOpeningInput {
  const KitchenOpeningInput({
    required this.item,
    required this.previousRemainingQty,
    required this.todayInputQty,
  });

  final KitchenStockItem item;
  final double previousRemainingQty;
  final double todayInputQty;
}

class CashCloseBlockers {
  const CashCloseBlockers({
    required this.openTableCount,
    required this.openTakeoutCount,
    required this.openStandingCount,
    required this.pendingKitchenItemCount,
    required this.pendingPaymentCount,
    required this.kitchenNotClosed,
    required this.kitchenCloseIncomplete,
    this.operationalSummary,
  });

  final int openTableCount;
  final int openTakeoutCount;
  final int openStandingCount;
  final int pendingKitchenItemCount;
  final int pendingPaymentCount;
  final bool kitchenNotClosed;
  final bool kitchenCloseIncomplete;
  final OperationalOpenOrdersSummary? operationalSummary;

  bool get canClose =>
      openTableCount == 0 &&
      openTakeoutCount == 0 &&
      openStandingCount == 0 &&
      pendingKitchenItemCount == 0 &&
      pendingPaymentCount == 0 &&
      !kitchenNotClosed &&
      !kitchenCloseIncomplete;

  String get message {
    if (kitchenNotClosed) {
      return 'No puedes cerrar caja. Primero debes cerrar cocina.';
    }
    if (kitchenCloseIncomplete) {
      return 'No puedes cerrar caja. El cierre de cocina esta incompleto.';
    }
    final orderCount = operationalSummary?.blockers.length ?? 0;
    if (orderCount > 0) {
      return 'No se puede cerrar la caja porque existen $orderCount ordenes activas:';
    }
    return 'No puedes cerrar caja. Hay mesas, pedidos o cocina pendientes.';
  }

  String get detail {
    final blockers = operationalSummary?.blockers ?? const [];
    if (blockers.isNotEmpty) {
      return blockers
          .map((row) {
            final origin = row.order.displayName;
            final folio = row.order.id.length <= 6
                ? row.order.id
                : row.order.id.substring(0, 6);
            return '$origin - Folio $folio - '
                'Pendiente \$${row.order.pendingTotal.toStringAsFixed(2)} - '
                '${row.activeItemCount} items activos - '
                '${row.order.status}/${row.order.paymentStatus} - '
                '${row.reason}';
          })
          .join('\n');
    }
    return [
      '$openTableCount mesas abiertas',
      '$openTakeoutCount pedidos para llevar abiertos',
      '$openStandingCount ordenes sin mesa abiertas',
      '$pendingKitchenItemCount productos pendientes en cocina',
      '$pendingPaymentCount cuentas pendientes de cobrar',
    ].join('\n');
  }
}

class _TableLinkCleanupResult {
  const _TableLinkCleanupResult({required this.stale, required this.released});

  final int stale;
  final int released;
}

class GhostOrderReconciliationResult {
  const GhostOrderReconciliationResult({
    required this.businessDate,
    required this.branchId,
    required this.candidatesChecked,
    required this.cancelledOrderIds,
    required this.staleTableLinks,
    required this.releasedTableLinks,
  });

  final String businessDate;
  final String branchId;
  final int candidatesChecked;
  final List<String> cancelledOrderIds;
  final int staleTableLinks;
  final int releasedTableLinks;

  int get cancelledOrders => cancelledOrderIds.length;
}

class _GhostOrderRepair {
  const _GhostOrderRepair({required this.orderId, required this.tableReleased});

  final String orderId;
  final bool tableReleased;
}

class KitchenYieldReportRow {
  const KitchenYieldReportRow({
    required this.item,
    required this.currentItem,
    required this.previousRemainingQty,
    required this.initialInputQty,
    required this.additionalEntriesQty,
    required this.availableQty,
    required this.finalRemainingQty,
    required this.wasteQty,
    required this.usedQty,
    required this.usefulConsumedQty,
    required this.soldQty,
    required this.currentYield,
    required this.averageYield,
  });

  final KitchenStockItem item;
  final KitchenSessionItem? currentItem;
  final double previousRemainingQty;
  final double initialInputQty;
  final double additionalEntriesQty;
  final double availableQty;
  final double finalRemainingQty;
  final double wasteQty;
  final double usedQty;
  final double usefulConsumedQty;
  final double soldQty;
  final double currentYield;
  final double averageYield;

  double get optimalYield => item.optimalConsumptionPerSaleQty;
  bool get hasSales => soldQty > 0;
  bool get hasConsumption => usefulConsumedQty > 0;
}

class _CashScheduleCacheEntry {
  const _CashScheduleCacheEntry({
    required this.sessions,
    required this.loadedAt,
  });

  final List<CashSession> sessions;
  final DateTime loadedAt;
}

class ExpenseRequestFunctionPayload {
  const ExpenseRequestFunctionPayload({
    required this.restaurantId,
    required this.branchId,
    required this.policyId,
    required this.amount,
    required this.supplierId,
    required this.paymentSource,
    required this.reason,
    required this.requesterId,
    required this.requesterName,
    required this.requesterRole,
    required this.businessDate,
    required this.cashSessionId,
    required this.clientRequestId,
    required this.hasReceipt,
  });

  final String restaurantId;
  final String branchId;
  final String policyId;
  final double amount;
  final String supplierId;
  final String paymentSource;
  final String reason;
  final String requesterId;
  final String requesterName;
  final String requesterRole;
  final String businessDate;
  final String cashSessionId;
  final String clientRequestId;
  final bool hasReceipt;

  Map<String, Object?> toMap() => {
    'restaurantId': restaurantId,
    'branchId': branchId,
    'policyId': policyId,
    'amount': amount,
    'supplierId': supplierId,
    'paymentSource': paymentSource,
    'reason': reason,
    'requesterId': requesterId,
    'requesterName': requesterName,
    'requesterRole': requesterRole,
    'businessDate': businessDate,
    'cashSessionId': cashSessionId,
    'clientRequestId': clientRequestId,
    'hasReceipt': hasReceipt,
  };
}

class ExpenseRequestFunctionClient {
  ExpenseRequestFunctionClient._({required this.call});

  factory ExpenseRequestFunctionClient.production({
    FirebaseFunctions? functions,
  }) {
    final instance =
        functions ??
        FirebaseFunctions.instanceFor(region: expenseRequestFunctionRegion);
    return ExpenseRequestFunctionClient._(
      call: (payload) async {
        final callable = instance.httpsCallable(
          submitExpenseRequestFunctionName,
          options: expenseRequestCallableOptions(),
        );
        final response = await callable.call(payload.toMap());
        final data = response.data;
        if (data is Map) return Map<String, dynamic>.from(data);
        throw StateError('Respuesta invalida al validar la politica.');
      },
    );
  }

  factory ExpenseRequestFunctionClient.fake(
    Future<Map<String, dynamic>> Function(ExpenseRequestFunctionPayload payload)
    call,
  ) {
    return ExpenseRequestFunctionClient._(call: call);
  }

  static const submitExpenseRequestFunctionName = 'submitExpenseRequest';
  static const expenseRequestFunctionRegion = 'us-central1';

  final Future<Map<String, dynamic>> Function(
    ExpenseRequestFunctionPayload payload,
  )
  call;
}

HttpsCallableOptions expenseRequestCallableOptions() =>
    HttpsCallableOptions(limitedUseAppCheckToken: true);

class ExpenseRequestAuthStatus {
  const ExpenseRequestAuthStatus({
    required this.ready,
    required this.authPresent,
    required this.uidPresent,
    required this.isAnonymous,
    this.errorCode,
    this.errorMessage,
  });

  const ExpenseRequestAuthStatus.ready({required bool isAnonymous})
    : this(
        ready: true,
        authPresent: true,
        uidPresent: true,
        isAnonymous: isAnonymous,
      );

  const ExpenseRequestAuthStatus.failed(String message, {String? errorCode})
    : this(
        ready: false,
        authPresent: false,
        uidPresent: false,
        isAnonymous: null,
        errorCode: errorCode,
        errorMessage: message,
      );

  final bool ready;
  final bool authPresent;
  final bool uidPresent;
  final bool? isAnonymous;
  final String? errorCode;
  final String? errorMessage;
}

class ExpenseRequestAuthSession {
  ExpenseRequestAuthSession._({required this.ensureReady});

  factory ExpenseRequestAuthSession.production(FirebaseAuth auth) {
    return ExpenseRequestAuthSession._(
      ensureReady: () async {
        final status = OperationalAuthService(auth: auth).currentStatus();
        return ExpenseRequestAuthStatus(
          ready: status.ready,
          authPresent: status.authPresent,
          uidPresent: status.uidPresent,
          isAnonymous: status.isAnonymous,
          errorCode: status.errorCode,
          errorMessage: status.errorMessage,
        );
      },
    );
  }

  factory ExpenseRequestAuthSession.fake(
    Future<ExpenseRequestAuthStatus> Function() ensureReady,
  ) {
    return ExpenseRequestAuthSession._(ensureReady: ensureReady);
  }

  final Future<ExpenseRequestAuthStatus> Function() ensureReady;
}

class ExpenseRequestDeviceSession {
  ExpenseRequestDeviceSession._({required this.ensureReady});

  factory ExpenseRequestDeviceSession.production({
    DeviceRegistryService? registryService,
  }) {
    final service = registryService ?? DeviceRegistryService.instance;
    return ExpenseRequestDeviceSession._(
      ensureReady: () => service.ensureCurrentDeviceReady(),
    );
  }

  factory ExpenseRequestDeviceSession.fake(
    Future<void> Function() ensureReady,
  ) {
    return ExpenseRequestDeviceSession._(ensureReady: ensureReady);
  }

  final Future<void> Function() ensureReady;
}

class ExpenseRequestDebugContext {
  const ExpenseRequestDebugContext({
    required this.restaurantId,
    required this.branchId,
    required this.cashSessionId,
    required this.cashSessionStatus,
    required this.policyId,
    required this.policyMode,
    required this.networkAvailable,
  });

  final String restaurantId;
  final String branchId;
  final String cashSessionId;
  final String cashSessionStatus;
  final String policyId;
  final String policyMode;
  final bool? networkAvailable;
}

Future<Map<String, dynamic>> submitExpenseRequestWithPreparedSession({
  required ExpenseRequestAuthSession authSession,
  required ExpenseRequestDeviceSession deviceSession,
  required ExpenseRequestFunctionClient functionClient,
  required ExpenseRequestFunctionPayload payload,
  required ExpenseRequestDebugContext debugContext,
  void Function(String marker, {Object? error, StackTrace? stackTrace})?
  debugLog,
}) async {
  debugLog?.call('expense-request: before-call');
  final authStatus = await authSession.ensureReady();
  if (!authStatus.ready) {
    debugLog?.call(
      'expense-request: auth-not-ready '
      'firebaseInitialized=true '
      'authPresent=${authStatus.authPresent} '
      'uidPresent=${authStatus.uidPresent} '
      'isAnonymous=${authStatus.isAnonymous} '
      'authErrorCode=${authStatus.errorCode ?? 'none'} '
      'restaurantId=${debugContext.restaurantId.isNotEmpty} '
      'branchId=${debugContext.branchId.isNotEmpty} '
      'cashSessionId=${debugContext.cashSessionId.isNotEmpty} '
      'cashSessionStatus=${debugContext.cashSessionStatus} '
      'selectedPolicyId=${debugContext.policyId.isNotEmpty} '
      'policyMode=${debugContext.policyMode} '
      'networkAvailable=${debugContext.networkAvailable}',
    );
    throw StateError(
      authStatus.errorMessage ??
          'No fue posible autenticar este dispositivo (${authStatus.errorCode ?? 'unknown'}). Intenta nuevamente.',
    );
  }

  debugLog?.call('expense-request: auth-ready');
  try {
    await deviceSession.ensureReady();
    debugLog?.call('expense-request: device-ready');
  } catch (error, stackTrace) {
    debugLog?.call(
      'expense-request: device-error',
      error: error,
      stackTrace: stackTrace,
    );
    final message = error is DeviceRegistryException
        ? error.message
        : 'Este dispositivo no esta registrado o activo.';
    throw StateError(message);
  }

  debugLog?.call('expense-request: callable-start');
  try {
    final result = await functionClient.call(payload);
    debugLog?.call('expense-request: callable-success');
    return result;
  } on FirebaseFunctionsException catch (error, stackTrace) {
    debugLog?.call(
      'expense-request: callable-error',
      error: {
        'code': error.code,
        'message': error.message,
        'detailsReason': _functionDetailsReason(error.details),
      },
      stackTrace: stackTrace,
    );
    throw StateError(submitExpenseRequestErrorMessage(error));
  } catch (error, stackTrace) {
    debugLog?.call(
      'expense-request: callable-error',
      error: error,
      stackTrace: stackTrace,
    );
    throw StateError(submitExpenseRequestErrorMessage(error));
  }
}

String submitExpenseRequestErrorMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    return switch (error.code) {
      'unavailable' || 'network-request-failed' =>
        'No hay conexion. El gasto no puede autoautorizarse sin Internet.',
      'deadline-exceeded' =>
        'No se pudo validar el gasto a tiempo. Intenta nuevamente.',
      'unauthenticated' =>
        _looksLikeAppCheckFailure(error)
            ? 'No fue posible validar este dispositivo. Cierra y vuelve a abrir TacoPOS.'
            : 'No fue posible autenticar este dispositivo. Intenta nuevamente.',
      'permission-denied' =>
        _looksLikeAppCheckFailure(error) || _looksLikeDeviceFailure(error)
            ? 'No fue posible validar este dispositivo. Cierra y vuelve a abrir TacoPOS.'
            : 'No fue posible validar este dispositivo para solicitar el gasto.',
      'invalid-argument' || 'failed-precondition' => _cleanFunctionMessage(
        error,
        fallback:
            'No fue posible validar este gasto con la politica seleccionada.',
      ),
      'resource-exhausted' =>
        'La politica alcanzo su limite de uso. Solicita aprobacion manual.',
      'internal' || 'unknown' =>
        'No fue posible validar la politica en este momento. Intenta nuevamente.',
      _ => _cleanFunctionMessage(
        error,
        fallback: 'No fue posible validar la politica de gasto.',
      ),
    };
  }
  if (error is StateError || error is ArgumentError) {
    final message = error.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
    return message.trim().isEmpty
        ? 'No fue posible validar la politica de gasto.'
        : message;
  }
  return 'No fue posible validar la politica de gasto.';
}

bool _looksLikeAppCheckFailure(FirebaseFunctionsException error) {
  final text = '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();
  return text.contains('app check') ||
      text.contains('appcheck') ||
      text.contains('token app check');
}

bool _looksLikeDeviceFailure(FirebaseFunctionsException error) {
  final text = '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();
  return text.contains('dispositivo') ||
      text.contains('device_not_registered') ||
      text.contains('device_inactive') ||
      text.contains('branch_mismatch');
}

Object? _functionDetailsReason(Object? details) {
  if (details is Map) {
    return details['reason'];
  }
  return null;
}

String _cleanFunctionMessage(
  FirebaseFunctionsException error, {
  required String fallback,
}) {
  final message = error.message?.trim();
  return message == null || message.isEmpty ? fallback : message;
}

class TacoPosRepository {
  TacoPosRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    ExpenseRequestAuthSession? expenseRequestAuthSession,
    ExpenseRequestDeviceSession? expenseRequestDeviceSession,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _expenseRequestAuthSession =
           expenseRequestAuthSession ??
           ExpenseRequestAuthSession.production(auth ?? FirebaseAuth.instance),
       _expenseRequestDeviceSession =
           expenseRequestDeviceSession ??
           ExpenseRequestDeviceSession.production();

  static const cardSurchargeRate = 0.04;
  static const operationResetPin = '072026';
  static final ReportDataRepository _reportDataRepository =
      ReportDataRepository();
  static final FinanceDashboardCache _financeDashboardCache =
      FinanceDashboardCache();
  static final YieldProfitBundleCache _yieldProfitBundleCache =
      YieldProfitBundleCache();
  static final Map<String, _CashScheduleCacheEntry> _cashScheduleCache = {};

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final ExpenseRequestAuthSession _expenseRequestAuthSession;
  final ExpenseRequestDeviceSession _expenseRequestDeviceSession;

  DocumentReference<Map<String, dynamic>> get _restaurantRef =>
      _db.collection('restaurants').doc(AppConstants.restaurantId);

  CollectionReference<Map<String, dynamic>> get _tablesRef =>
      _restaurantRef.collection('tables');

  CollectionReference<Map<String, dynamic>> get _productsRef =>
      _restaurantRef.collection('products');

  CollectionReference<Map<String, dynamic>> get _productCategoriesRef =>
      _restaurantRef.collection('productCategories');

  CollectionReference<Map<String, dynamic>> get _employeesRef =>
      _restaurantRef.collection('employees');
  CollectionReference<Map<String, dynamic>> get _activeSessionsRef =>
      _restaurantRef.collection('activeSessions');

  CollectionReference<Map<String, dynamic>> get _platformsRef =>
      _restaurantRef.collection('orderPlatforms');

  CollectionReference<Map<String, dynamic>> get _ordersRef =>
      _restaurantRef.collection('orders');

  CollectionReference<Map<String, dynamic>> get _cashSessionsRef =>
      _restaurantRef.collection('cashSessions');

  CollectionReference<Map<String, dynamic>> get _cashWithdrawalRequestsRef =>
      _restaurantRef.collection('cashWithdrawalRequests');

  CollectionReference<Map<String, dynamic>> get _expensePoliciesRef =>
      _restaurantRef.collection('expensePolicies');

  CollectionReference<Map<String, dynamic>> get _expensePolicyUsageRef =>
      _restaurantRef.collection('expensePolicyUsage');

  CollectionReference<Map<String, dynamic>> get _kitchenStockItemsRef =>
      _restaurantRef.collection('kitchenStockItems');

  CollectionReference<Map<String, dynamic>> get _kitchenSessionsRef =>
      _restaurantRef.collection('kitchenSessions');

  CollectionReference<Map<String, dynamic>> get _productStockOutsRef =>
      _restaurantRef.collection('productStockOuts');

  CollectionReference<Map<String, dynamic>> get _branchesRef =>
      _restaurantRef.collection('branches');

  CollectionReference<Map<String, dynamic>> get _suppliersRef =>
      _restaurantRef.collection('suppliers');

  CollectionReference<Map<String, dynamic>> get _purchaseItemsRef =>
      _restaurantRef.collection('purchaseItems');

  CollectionReference<Map<String, dynamic>> get _supplierPurchasesRef =>
      _restaurantRef.collection('supplierPurchases');

  CollectionReference<Map<String, dynamic>> get _supplierPaymentsRef =>
      _restaurantRef.collection('supplierPayments');

  CollectionReference<Map<String, dynamic>> get _ingredientYieldProfilesRef =>
      _restaurantRef.collection('ingredientYieldProfiles');

  CollectionReference<Map<String, dynamic>> get _productRecipesRef =>
      _restaurantRef.collection('productRecipes');

  CollectionReference<Map<String, dynamic>> get _partnersRef =>
      _restaurantRef.collection('partners');

  CollectionReference<Map<String, dynamic>> get _partnerContributionsRef =>
      _restaurantRef.collection('partnerContributions');

  CollectionReference<Map<String, dynamic>> get _discountUsageRef =>
      _restaurantRef.collection('discountUsage');

  CollectionReference<Map<String, dynamic>>
  get _discountAuthorizationRequestsRef =>
      _restaurantRef.collection('discountAuthorizationRequests');

  DocumentReference<Map<String, dynamic>> get _discountSettingsRef =>
      _restaurantRef.collection('settings').doc('discounts');

  DocumentReference<Map<String, dynamic>> get _saleFolioSettingsRef =>
      _restaurantRef.collection('settings').doc('saleFolio');

  DocumentReference<Map<String, dynamic>> get _purchaseFolioCounterRef =>
      _restaurantRef.collection('settings').doc('purchaseFolioCounter');

  DocumentReference<Map<String, dynamic>> get _expensePolicySettingsRef =>
      _restaurantRef.collection('settings').doc('expensePolicies');

  CollectionReference<Map<String, dynamic>> _dailySaleCountersRef(
    String branchId,
  ) => _branchesRef.doc(branchId).collection('dailySaleCounters');

  CollectionReference<Map<String, dynamic>> _saleAuditEventsRef(
    String branchId,
  ) => _branchesRef.doc(branchId).collection('saleAuditEvents');

  Map<String, Object?> get _currentBranchFields {
    final session = AppSession.instance;
    return {
      'restaurantId': session.currentRestaurantId,
      'restaurantName': session.currentRestaurantName,
      'branchId': session.currentBranchId,
      'branchName': session.currentBranchName,
    };
  }

  bool _matchesCurrentBranch(String? branchId) {
    return _matchesBranch(branchId, AppSession.instance.currentBranchId);
  }

  bool _matchesBranch(String? branchId, String selectedBranchId) {
    final cleanBranchId = branchId?.trim();
    if (cleanBranchId == null || cleanBranchId.isEmpty) {
      return selectedBranchId == AppConstants.defaultBranchId;
    }
    return cleanBranchId == selectedBranchId;
  }

  List<T> _filterCurrentBranch<T>(
    Iterable<T> items,
    String? Function(T item) branchId,
  ) {
    return items
        .where((item) => _matchesCurrentBranch(branchId(item)))
        .toList();
  }

  Stream<List<Restaurant>> watchRestaurants({bool activeOnly = true}) {
    return _db.collection('restaurants').snapshots().map((snapshot) {
      final restaurants = snapshot.docs.map(Restaurant.fromDoc).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return activeOnly
          ? restaurants.where((restaurant) => restaurant.active).toList()
          : restaurants;
    });
  }

  Stream<List<Branch>> watchBranches({bool activeOnly = false}) {
    return _branchesRef.snapshots().map((snapshot) {
      final branches =
          snapshot.docs
              .map(
                (doc) => Branch.fromDoc(
                  doc,
                  restaurantId: AppConstants.restaurantId,
                  restaurantName: AppConstants.restaurantName,
                ),
              )
              .toList()
            ..sort((a, b) {
              final sortCompare = a.sortOrder.compareTo(b.sortOrder);
              return sortCompare != 0 ? sortCompare : a.name.compareTo(b.name);
            });
      return activeOnly
          ? branches.where((branch) => branch.active).toList()
          : branches;
    });
  }

  Future<List<Branch>> getBranchesOnce({bool activeOnly = true}) async {
    final snapshot = await _branchesRef.get();
    final branches =
        snapshot.docs
            .map(
              (doc) => Branch.fromDoc(
                doc,
                restaurantId: AppConstants.restaurantId,
                restaurantName: AppConstants.restaurantName,
              ),
            )
            .toList()
          ..sort((a, b) {
            final sortCompare = a.sortOrder.compareTo(b.sortOrder);
            return sortCompare != 0 ? sortCompare : a.name.compareTo(b.name);
          });
    return activeOnly
        ? branches.where((branch) => branch.active).toList()
        : branches;
  }

  Future<List<Branch>> getAccessibleBranches(Employee employee) async {
    await ensureDefaultBranch();
    final branches = await getBranchesOnce(activeOnly: true);
    if (employee.hasAdminAccess) {
      return branches.isEmpty ? const [Branch.defaultBranch] : branches;
    }
    final allowedIds = employee.effectiveBranchAccess
        .where((access) => access.active)
        .map((access) => access.branchId)
        .toSet();
    final allowed = branches
        .where((branch) => allowedIds.contains(branch.id))
        .toList();
    return allowed.isEmpty ? const [Branch.defaultBranch] : allowed;
  }

  Future<void> ensureDefaultBranch() async {
    final batch = _db.batch();
    batch.set(_restaurantRef, {
      'name': AppConstants.restaurantName,
      'active': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(_branchesRef.doc(AppConstants.defaultBranchId), {
      'id': AppConstants.defaultBranchId,
      'restaurantId': AppConstants.restaurantId,
      'restaurantName': AppConstants.restaurantName,
      'name': AppConstants.defaultBranchName,
      'normalizedName': AppConstants.defaultBranchId,
      'active': true,
      'sortOrder': 1,
      'timezone': AppConstants.defaultTimezone,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> saveBranch({
    String? branchId,
    required String name,
    required bool active,
    required int sortOrder,
    String address = '',
    String phone = '',
  }) async {
    _requireAdminPermission(
      _canManageBranches(),
      'No tienes permiso para administrar sucursales.',
    );
    final normalized = normalizeBranchName(name);
    final id = (branchId == null || branchId.trim().isEmpty)
        ? normalized
        : branchId.trim();
    final docRef = _branchesRef.doc(id);
    await docRef.set({
      'id': id,
      'restaurantId': AppConstants.restaurantId,
      'restaurantName': AppConstants.restaurantName,
      'name': name.trim(),
      'normalizedName': normalized,
      'active': active,
      'sortOrder': sortOrder,
      'address': address.trim(),
      'phone': phone.trim(),
      'timezone': AppConstants.defaultTimezone,
      if (branchId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleBranch(Branch branch) async {
    _requireAdminPermission(
      _canManageBranches(),
      'No tienes permiso para administrar sucursales.',
    );
    await _branchesRef.doc(branch.id).update({
      'active': !branch.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<BranchSummary> branchSummary(Branch branch) async {
    final tablesSnapshot = await _tablesRef.get();
    final ordersSnapshot = await _ordersRef.get();
    final cashSnapshot = await _cashSessionsRef.get();
    final employeesSnapshot = await _employeesRef.get();
    final tableCount = tablesSnapshot.docs
        .map(PosTable.fromDoc)
        .where((table) => _matchesBranch(table.branchId, branch.id))
        .length;
    final openOrderCount = ordersSnapshot.docs
        .map(PosOrder.fromDoc)
        .where(
          (order) =>
              _matchesBranch(order.branchId, branch.id) && isActiveOrder(order),
        )
        .length;
    final cashOpen = cashSnapshot.docs
        .map(CashSession.fromDoc)
        .any(
          (session) =>
              _matchesBranch(session.branchId, branch.id) && session.isOpen,
        );
    final employeeAccessCount = employeesSnapshot.docs
        .map(Employee.fromDoc)
        .where(
          (employee) =>
              employee.isSuperAdmin ||
              employee.effectiveBranchAccess.any(
                (access) => access.active && access.branchId == branch.id,
              ),
        )
        .length;
    return BranchSummary(
      tableCount: tableCount,
      openOrderCount: openOrderCount,
      cashOpen: cashOpen,
      employeeAccessCount: employeeAccessCount,
    );
  }

  Future<int> countDefaultBranchBackfillPending() async {
    _requireAdminPermission(
      _canManageBranches(),
      'No tienes permiso para revisar datos de sucursales.',
    );
    var pending = 0;

    bool needsBranch(DocumentSnapshot<Map<String, dynamic>> doc) {
      final data = doc.data() ?? {};
      final branchId = data['branchId']?.toString().trim();
      return branchId == null || branchId.isEmpty;
    }

    for (final collectionName in [
      'tables',
      'cashSessions',
      'cashWithdrawalRequests',
      'kitchenSessions',
      'activeSessions',
      'activityLog',
    ]) {
      final snapshot = await _restaurantRef.collection(collectionName).get();
      pending += snapshot.docs.where(needsBranch).length;
    }

    final ordersSnapshot = await _ordersRef.get();
    for (final orderDoc in ordersSnapshot.docs) {
      if (needsBranch(orderDoc)) pending++;

      final itemSnapshot = await orderDoc.reference.collection('items').get();
      pending += itemSnapshot.docs.where(needsBranch).length;

      final paymentSnapshot = await orderDoc.reference
          .collection('payments')
          .get();
      pending += paymentSnapshot.docs.where(needsBranch).length;
    }

    return pending;
  }

  Future<int> backfillDefaultBranch() async {
    _requireAdminPermission(
      _canManageBranches(),
      'No tienes permiso para preparar datos de sucursales.',
    );
    await ensureDefaultBranch();
    var updated = 0;
    var batch = _db.batch();
    var batchWrites = 0;

    Future<void> commitIfNeeded({bool force = false}) async {
      if (batchWrites == 0 || (!force && batchWrites < 450)) return;
      await batch.commit();
      batch = _db.batch();
      batchWrites = 0;
    }

    void setBranchIfMissing(
      DocumentSnapshot<Map<String, dynamic>> doc, {
      Map<String, Object?> extra = const {},
    }) {
      final data = doc.data() ?? {};
      final branchId = data['branchId']?.toString().trim();
      if (branchId != null && branchId.isNotEmpty) {
        return;
      }
      batch.set(doc.reference, {
        'restaurantId': AppConstants.restaurantId,
        'restaurantName': AppConstants.restaurantName,
        'branchId': AppConstants.defaultBranchId,
        'branchName': AppConstants.defaultBranchName,
        ...extra,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      updated++;
      batchWrites++;
    }

    for (final collectionName in [
      'tables',
      'cashSessions',
      'cashWithdrawalRequests',
      'kitchenSessions',
      'activeSessions',
      'activityLog',
    ]) {
      final snapshot = await _restaurantRef.collection(collectionName).get();
      for (final doc in snapshot.docs) {
        setBranchIfMissing(doc);
        await commitIfNeeded();
      }
    }

    final ordersSnapshot = await _ordersRef.get();
    for (final orderDoc in ordersSnapshot.docs) {
      setBranchIfMissing(orderDoc);
      await commitIfNeeded();

      final itemSnapshot = await orderDoc.reference.collection('items').get();
      for (final itemDoc in itemSnapshot.docs) {
        setBranchIfMissing(itemDoc);
        await commitIfNeeded();
      }

      final paymentSnapshot = await orderDoc.reference
          .collection('payments')
          .get();
      for (final paymentDoc in paymentSnapshot.docs) {
        setBranchIfMissing(paymentDoc);
        await commitIfNeeded();
      }
    }

    await commitIfNeeded(force: true);
    return updated;
  }

  Stream<List<PosTable>> watchTables({bool activeOnly = true}) {
    return _tablesRef.snapshots().map((snapshot) {
      final tables = _filterCurrentBranch(
        snapshot.docs.map(PosTable.fromDoc),
        (table) => table.branchId,
      )..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return activeOnly
          ? tables.where((table) => table.active).toList()
          : tables;
    });
  }

  Stream<List<OrderPlatform>> watchOrderPlatforms({bool activeOnly = true}) {
    return _platformsRef.snapshots().map((snapshot) {
      final platforms = snapshot.docs.map(OrderPlatform.fromDoc).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return activeOnly
          ? platforms.where((platform) => platform.active).toList()
          : platforms;
    });
  }

  Future<void> ensureDefaultOrderPlatforms() async {
    final snapshot = await _platformsRef.limit(1).get();
    if (snapshot.docs.isNotEmpty) {
      return;
    }

    final batch = _db.batch();
    const defaults = [
      {'id': 'en_persona', 'name': 'En persona', 'sortOrder': 1},
      {'id': 'didi', 'name': 'DiDi', 'sortOrder': 2},
      {'id': 'uber', 'name': 'Uber', 'sortOrder': 3},
      {'id': 'rappi', 'name': 'Rappi', 'sortOrder': 4},
    ];

    for (final platform in defaults) {
      final id = platform['id']! as String;
      batch.set(_platformsRef.doc(id), {
        ...platform,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Stream<List<ProductCategory>> watchProductCategories({
    bool activeOnly = false,
  }) {
    return _productCategoriesRef.snapshots().map((snapshot) {
      final categories = snapshot.docs.map(ProductCategory.fromDoc).toList()
        ..sort((a, b) {
          final sortCompare = a.sortOrder.compareTo(b.sortOrder);
          return sortCompare != 0 ? sortCompare : a.name.compareTo(b.name);
        });
      return activeOnly
          ? categories.where((category) => category.active).toList()
          : categories;
    });
  }

  Future<List<ProductCategory>> getProductCategoriesOnce({
    bool activeOnly = false,
  }) async {
    final snapshot = await _productCategoriesRef.get();
    final categories = snapshot.docs.map(ProductCategory.fromDoc).toList()
      ..sort((a, b) {
        final sortCompare = a.sortOrder.compareTo(b.sortOrder);
        return sortCompare != 0 ? sortCompare : a.name.compareTo(b.name);
      });
    return activeOnly
        ? categories.where((category) => category.active).toList()
        : categories;
  }

  Future<void> ensureDefaultProductCategories() async {
    await seedDefaultProductCategoriesIfNeeded();
  }

  Future<void> seedDefaultProductCategoriesIfNeeded() async {
    const defaults = [
      _DefaultProductCategory('Tacos', 1, '#F59A23'),
      _DefaultProductCategory('Gringas', 2, '#BFA7FF'),
      _DefaultProductCategory('Bebidas', 3, '#72B7D2'),
      _DefaultProductCategory('Quesadillas', 4, '#55D98B'),
      _DefaultProductCategory('Extras', 5, '#D986A1'),
      _DefaultProductCategory('Otros', 99, '#8A8F98'),
    ];

    final existing = await _productCategoriesRef.get();
    final existingIds = existing.docs.map((doc) => doc.id).toSet();
    final existingNormalizedNames = existing.docs
        .map((doc) => ProductCategory.fromDoc(doc).normalizedName)
        .toSet();
    final batch = _db.batch();
    var writes = 0;
    for (final category in defaults) {
      final id = categoryIdForName(category.name);
      final normalizedName = normalizeCategory(category.name);
      if (existingIds.contains(id) ||
          existingNormalizedNames.contains(normalizedName)) {
        continue;
      }
      batch.set(_productCategoriesRef.doc(id), {
        'id': id,
        'name': category.name,
        'normalizedName': normalizedName,
        'active': true,
        'sortOrder': category.sortOrder,
        'colorHex': category.colorHex,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      writes++;
    }
    if (writes > 0) {
      await batch.commit();
    }
  }

  Future<ProductCategory?> findCategoryByNormalizedName(
    String normalizedName,
  ) async {
    final snapshot = await _productCategoriesRef
        .where('normalizedName', isEqualTo: normalizeCategory(normalizedName))
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return ProductCategory.fromDoc(snapshot.docs.first);
  }

  Future<void> normalizeProductCategories() async {
    await normalizeProductCategoriesAndProducts();
  }

  Future<void> normalizeProductCategoriesAndProducts() async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageProducts == true,
      'No tienes permiso para administrar productos.',
    );
    await seedDefaultProductCategoriesIfNeeded();
    final categoriesSnapshot = await _productCategoriesRef.get();
    final categoriesByName = <String, ProductCategory>{
      for (final doc in categoriesSnapshot.docs)
        ProductCategory.fromDoc(doc).normalizedName: ProductCategory.fromDoc(
          doc,
        ),
    };
    final productsSnapshot = await _productsRef.get();
    final batch = _db.batch();
    var writes = 0;

    for (final productDoc in productsSnapshot.docs) {
      final data = productDoc.data();
      final legacyName = _readText(data['category'], 'Otros');
      final categoryName = _readText(data['categoryName'], legacyName);
      final normalizedName = normalizeCategory(categoryName);
      var category = categoriesByName[normalizedName];
      if (category == null) {
        final categoryId = categoryIdForName(categoryName);
        batch.set(_productCategoriesRef.doc(categoryId), {
          'id': categoryId,
          'name': categoryName,
          'normalizedName': normalizedName,
          'active': true,
          'sortOrder': 90,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        writes++;
        category = ProductCategory(
          id: categoryId,
          name: categoryName,
          normalizedName: normalizedName,
          active: true,
          sortOrder: 90,
        );
        categoriesByName[normalizedName] = category;
      }

      if (data['categoryId'] != category.id ||
          data['categoryName'] != category.name ||
          data['category'] != category.name) {
        batch.set(productDoc.reference, {
          'categoryId': category.id,
          'categoryName': category.name,
          'category': category.name,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        writes++;
      }
    }

    if (writes > 0) {
      await batch.commit();
    }
  }

  Future<void> createProductCategory({
    required String name,
    required int sortOrder,
    bool active = true,
    String? colorHex,
  }) async {
    await saveProductCategory(
      name: name,
      active: active,
      sortOrder: sortOrder,
      colorHex: colorHex,
    );
  }

  Future<void> updateProductCategory({
    required String categoryId,
    required String name,
    required bool active,
    required int sortOrder,
    String? colorHex,
  }) async {
    await saveProductCategory(
      categoryId: categoryId,
      name: name,
      active: active,
      sortOrder: sortOrder,
      colorHex: colorHex,
    );
  }

  Future<void> saveProductCategory({
    String? categoryId,
    required String name,
    required bool active,
    required int sortOrder,
    String? colorHex,
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageProducts == true,
      'No tienes permiso para administrar productos.',
    );
    final cleanName = _cleanCategoryDisplayName(name);
    if (cleanName.isEmpty) {
      throw ArgumentError('Captura el nombre de la categoria.');
    }
    final existing = categoryId == null
        ? await findCategoryByNormalizedName(cleanName)
        : null;
    final id = (categoryId ?? existing?.id ?? categoryIdForName(cleanName))
        .trim();
    await _productCategoriesRef.doc(id).set({
      'id': id,
      'name': cleanName,
      'normalizedName': normalizeCategory(cleanName),
      'active': active,
      'sortOrder': sortOrder,
      'colorHex': _cleanColorHex(colorHex),
      if (categoryId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setActive(ProductCategory category, bool active) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageProducts == true,
      'No tienes permiso para administrar productos.',
    );
    await _productCategoriesRef.doc(category.id).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> toggleProductCategory(ProductCategory category) async {
    await setActive(category, !category.active);
  }

  Stream<List<Product>> watchProducts({bool activeOnly = false}) {
    return _productsRef.snapshots().map((snapshot) {
      final products = snapshot.docs.map(Product.fromDoc).toList()
        ..sort((a, b) {
          final categoryCompare = compareCategories(a.category, b.category);
          return categoryCompare != 0
              ? categoryCompare
              : a.sortOrder.compareTo(b.sortOrder);
        });
      return activeOnly
          ? products.where((product) => product.active).toList()
          : products;
    });
  }

  Future<
    (
      List<Product>,
      List<KitchenStockItem>,
      List<IngredientYieldProfile>,
      List<TheoreticalProductRecipe>,
    )
  >
  getYieldConfiguration() async {
    _requireYieldProfitAdmin();
    final productFuture = _productsRef.get();
    final stockFuture = _kitchenStockItemsRef.get();
    final profileFuture = _ingredientYieldProfilesRef.get();
    final recipeFuture = _productRecipesRef.get();
    final productSnapshot = await productFuture;
    final stockSnapshot = await stockFuture;
    final profileSnapshot = await profileFuture;
    final recipeSnapshot = await recipeFuture;
    final products = productSnapshot.docs.map(Product.fromDoc).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final stockItems = stockSnapshot.docs.map(KitchenStockItem.fromDoc).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final profiles =
        profileSnapshot.docs.map(IngredientYieldProfile.fromDoc).toList()
          ..sort((a, b) => a.stockItemName.compareTo(b.stockItemName));
    final recipes =
        recipeSnapshot.docs.map(TheoreticalProductRecipe.fromDoc).toList()
          ..sort((a, b) => a.productName.compareTo(b.productName));
    return (products, stockItems, profiles, recipes);
  }

  Future<InitialYieldSeedPlan> ensureInitialYieldProfiles() async {
    _requireYieldProfitAdmin();
    final stockFuture = _kitchenStockItemsRef.get();
    final profileFuture = _ingredientYieldProfilesRef.get();
    final stockSnapshot = await stockFuture;
    final profileSnapshot = await profileFuture;
    final plan = planInitialYieldSeed(
      restaurantId: AppSession.instance.currentRestaurantId,
      stockItems: stockSnapshot.docs.map(KitchenStockItem.fromDoc),
      existingProfiles: profileSnapshot.docs.map(
        IngredientYieldProfile.fromDoc,
      ),
    );
    if (plan.toCreate.isNotEmpty) {
      final employee = AppSession.instance.employee;
      final batch = _db.batch();
      for (final profile in plan.toCreate) {
        batch.set(_ingredientYieldProfilesRef.doc(profile.stockItemId), {
          'restaurantId': AppSession.instance.currentRestaurantId,
          'stockItemId': profile.stockItemId,
          'stockItemName': profile.stockItemName,
          'rawBaseUnit': 'g',
          'cookedBaseUnit': 'g',
          'cookingYieldPercent': profile.cookingYieldPercent,
          'cookingYieldRate': profile.cookingYieldRate,
          'estimatedReductionPercent': profile.estimatedReductionPercent,
          'isEstimated': true,
          'needsInternalValidation': true,
          'sourceLabel': initialYieldSourceLabel,
          'notes': '',
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
          'createdByEmployeeId': employee?.id ?? '',
          'createdByEmployeeName': employee?.name ?? '',
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedByEmployeeId': employee?.id ?? '',
          'updatedByEmployeeName': employee?.name ?? '',
        });
      }
      await batch.commit();
      _yieldProfitBundleCache.clear();
    }
    return plan;
  }

  Future<void> saveIngredientYieldProfile(
    IngredientYieldProfile profile,
  ) async {
    _requireYieldProfitAdmin();
    final percent = profile.cookingYieldPercent;
    if (percent <= 0 || percent > 100) {
      throw ArgumentError('El rendimiento debe estar entre 0.01% y 100%.');
    }
    final employee = AppSession.instance.employee;
    final validating = !profile.needsInternalValidation;
    await _ingredientYieldProfilesRef.doc(profile.stockItemId).set({
      'restaurantId': AppSession.instance.currentRestaurantId,
      'stockItemId': profile.stockItemId,
      'stockItemName': profile.stockItemName,
      'rawBaseUnit': 'g',
      'cookedBaseUnit': 'g',
      'cookingYieldPercent': percent,
      'cookingYieldRate': percent / 100,
      'estimatedReductionPercent': 100 - percent,
      'isEstimated': profile.isEstimated,
      'needsInternalValidation': profile.needsInternalValidation,
      'sourceLabel': profile.sourceLabel,
      'notes': profile.notes.trim(),
      'active': profile.active,
      if (profile.createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
      if (profile.createdAt == null) 'createdByEmployeeId': employee?.id ?? '',
      if (profile.createdAt == null)
        'createdByEmployeeName': employee?.name ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmployeeId': employee?.id ?? '',
      'updatedByEmployeeName': employee?.name ?? '',
      if (validating) 'validatedAt': FieldValue.serverTimestamp(),
      if (validating) 'validatedByEmployeeId': employee?.id ?? '',
      if (validating) 'validatedByEmployeeName': employee?.name ?? '',
    }, SetOptions(merge: true));
    _yieldProfitBundleCache.clear();
  }

  Future<void> saveTheoreticalProductRecipe(
    TheoreticalProductRecipe recipe,
  ) async {
    _requireYieldProfitAdmin();
    if (recipe.productId.trim().isEmpty) {
      throw ArgumentError('Selecciona un producto.');
    }
    if (recipe.ingredients.any(
      (ingredient) =>
          ingredient.stockItemId.trim().isEmpty ||
          ingredient.baseQuantity <= 0 ||
          !const {
            'raw',
            'cooked',
            'ready_to_serve',
          }.contains(ingredient.inputStage),
    )) {
      throw ArgumentError('Revisa ingredientes, cantidades y etapas.');
    }
    final employee = AppSession.instance.employee;
    final ref = _productRecipesRef.doc(recipe.productId);
    final current = await ref.get();
    final validating = !recipe.needsInternalValidation;
    await ref.set({
      'restaurantId': AppSession.instance.currentRestaurantId,
      'productId': recipe.productId,
      'productName': recipe.productName,
      'ingredients': recipe.ingredients
          .map((ingredient) => ingredient.toMap())
          .toList(),
      'active': recipe.active,
      'isEstimated': recipe.isEstimated,
      'needsInternalValidation': recipe.needsInternalValidation,
      'notes': recipe.notes.trim(),
      'recipeStatus': recipe.recipeStatus,
      'missingIngredientNotes': recipe.missingIngredientNotes.trim(),
      'version': recipe.version < 1 ? 1 : recipe.version,
      'effectiveFrom':
          recipe.effectiveFrom ??
          current.data()?['effectiveFrom'] ??
          FieldValue.serverTimestamp(),
      'effectiveTo': recipe.effectiveTo,
      if (!current.exists) 'createdAt': FieldValue.serverTimestamp(),
      if (!current.exists) 'createdByEmployeeId': employee?.id ?? '',
      if (!current.exists) 'createdByEmployeeName': employee?.name ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmployeeId': employee?.id ?? '',
      'updatedByEmployeeName': employee?.name ?? '',
      if (validating) 'validatedAt': FieldValue.serverTimestamp(),
      if (validating) 'validatedByEmployeeId': employee?.id ?? '',
      if (validating) 'validatedByEmployeeName': employee?.name ?? '',
    }, SetOptions(merge: true));
    _yieldProfitBundleCache.clear();
  }

  Future<RecipeCreationResult> createSuggestedYieldRecipes(
    Iterable<TheoreticalProductRecipe> suggestions,
  ) async {
    _requireYieldProfitAdmin();
    final selected = suggestions.toList(growable: false);
    if (selected.isEmpty) {
      return const RecipeCreationResult(
        createdProductIds: [],
        incompleteCreated: 0,
        skippedExisting: 0,
      );
    }
    final existing = await _productRecipesRef.get();
    final existingIds = existing.docs.map((doc) => doc.id).toSet();
    final employee = AppSession.instance.employee;
    final batch = _db.batch();
    final createdIds = <String>[];
    var incompleteCreated = 0;
    var skippedExisting = 0;
    for (final recipe in selected) {
      if (existingIds.contains(recipe.productId)) {
        skippedExisting++;
        continue;
      }
      batch.set(_productRecipesRef.doc(recipe.productId), {
        'restaurantId': AppSession.instance.currentRestaurantId,
        'productId': recipe.productId,
        'productName': recipe.productName,
        'ingredients': recipe.ingredients
            .map((ingredient) => ingredient.toMap())
            .toList(),
        'active': true,
        'isEstimated': true,
        'needsInternalValidation': true,
        'notes': 'Sugerencia inicial por nombre; requiere validacion interna.',
        'recipeStatus': recipe.recipeStatus,
        'missingIngredientNotes': recipe.missingIngredientNotes,
        'version': 1,
        'effectiveFrom': FieldValue.serverTimestamp(),
        'effectiveTo': null,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByEmployeeId': employee?.id ?? '',
        'createdByEmployeeName': employee?.name ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByEmployeeId': employee?.id ?? '',
        'updatedByEmployeeName': employee?.name ?? '',
      });
      createdIds.add(recipe.productId);
      if (recipe.isIncomplete) incompleteCreated++;
    }
    if (createdIds.isNotEmpty) await batch.commit();
    _yieldProfitBundleCache.clear();
    return RecipeCreationResult(
      createdProductIds: createdIds,
      incompleteCreated: incompleteCreated,
      skippedExisting: skippedExisting,
    );
  }

  Stream<Map<String, ProductStockOutRow>> watchActiveProductStockOuts() {
    return _productStockOutsRef.snapshots().asyncMap((snapshot) async {
      final businessDate = await currentKitchenBusinessDate();
      final branchId = AppSession.instance.currentBranchId;
      final rows = snapshot.docs
          .map(ProductStockOutRow.fromDoc)
          .where(
            (row) =>
                row.branchId == branchId &&
                row.businessDate == businessDate &&
                row.isActive,
          );
      return {for (final row in rows) row.productId: row};
    });
  }

  Stream<List<ProductStockOutRow>> watchProductStockOutReport({
    String? startBusinessDate,
    String? endBusinessDate,
  }) {
    return _productStockOutsRef.snapshots().map((snapshot) {
      final start = startBusinessDate?.trim();
      final end = endBusinessDate?.trim();
      final rows =
          snapshot.docs.map(ProductStockOutRow.fromDoc).where((row) {
            if (!_matchesCurrentBranch(row.branchId)) return false;
            if (start != null &&
                start.isNotEmpty &&
                row.businessDate.compareTo(start) < 0) {
              return false;
            }
            if (end != null &&
                end.isNotEmpty &&
                row.businessDate.compareTo(end) > 0) {
              return false;
            }
            return true;
          }).toList()..sort((a, b) {
            final dateCompare = b.businessDate.compareTo(a.businessDate);
            if (dateCompare != 0) return dateCompare;
            final aTime = a.soldOutAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = b.soldOutAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });
      return rows;
    });
  }

  Future<void> markProductStockOut(Product product) async {
    _requireTakeOrders();
    final businessDate = await currentKitchenBusinessDate();
    final branchId = AppSession.instance.currentBranchId;
    final branchName = AppSession.instance.currentBranchName;
    final employee = AppSession.instance.employee;
    final docRef = _productStockOutsRef.doc(
      _productStockOutId(branchId, businessDate, product.id),
    );
    final existing = await docRef.get();
    if (existing.exists && existing.data()?['status'] == 'active') {
      throw StateError('Este producto ya esta marcado como agotado.');
    }
    final soldOutAt = Timestamp.now();
    final soldOutTimeLabel = DateFormat('HH:mm').format(soldOutAt.toDate());
    await docRef.set({
      'id': docRef.id,
      'restaurantId': AppConstants.restaurantId,
      'restaurantName': AppConstants.restaurantName,
      'branchId': branchId,
      'branchName': branchName,
      'businessDate': businessDate,
      'productId': product.id,
      'productName': product.name,
      'categoryId': product.categoryId,
      'categoryName': product.categoryName,
      'status': 'active',
      'reason': 'agotado',
      'soldOutAt': soldOutAt,
      'soldOutTimeLabel': soldOutTimeLabel,
      'soldOutByEmployeeId': employee?.id ?? '',
      'soldOutByEmployeeName': employee?.name ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'createdByEmployeeId': employee?.id ?? '',
      'createdByEmployeeName': employee?.name ?? '',
      'clearedAt': null,
      'clearedByEmployeeId': '',
      'clearedByEmployeeName': '',
      'clearedReason': '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> clearProductStockOut(
    Product product, {
    String reason = 'manual',
  }) async {
    _requireTakeOrders();
    final businessDate = await currentKitchenBusinessDate();
    final branchId = AppSession.instance.currentBranchId;
    final docRef = _productStockOutsRef.doc(
      _productStockOutId(branchId, businessDate, product.id),
    );
    await _clearProductStockOutRef(docRef, reason: reason);
  }

  Future<bool> isProductStockedOut(Product product) async {
    final businessDate = await currentKitchenBusinessDate();
    final branchId = AppSession.instance.currentBranchId;
    final doc = await _productStockOutsRef
        .doc(_productStockOutId(branchId, businessDate, product.id))
        .get();
    return doc.exists && doc.data()?['status'] == 'active';
  }

  Stream<List<Employee>> watchEmployees({bool activeOnly = true}) {
    return _employeesRef.snapshots().map((snapshot) {
      final employees = snapshot.docs.map(Employee.fromDoc).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return activeOnly
          ? employees.where((employee) => employee.active).toList()
          : employees;
    });
  }

  Future<List<Employee>> getEmployeesOnce({bool activeOnly = true}) async {
    final snapshot = await _employeesRef.get();
    final employees = snapshot.docs.map(Employee.fromDoc).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return activeOnly
        ? employees.where((employee) => employee.active).toList()
        : employees;
  }

  Stream<List<Supplier>> watchSuppliers({bool activeOnly = false}) {
    return _suppliersRef.snapshots().map((snapshot) {
      final suppliers = snapshot.docs.map(Supplier.fromDoc).toList()
        ..sort((a, b) => a.commercialName.compareTo(b.commercialName));
      return activeOnly
          ? suppliers.where((supplier) => supplier.active).toList()
          : suppliers;
    });
  }

  Future<void> saveSupplier({
    String? supplierId,
    required String commercialName,
    String legalName = '',
    String rfc = '',
    String phone = '',
    String contactName = '',
    String address = '',
    String notes = '',
    required bool active,
    required String preferredPaymentMethod,
    required int creditDays,
    required String paymentWeekday,
    required String paymentWeekdayName,
  }) async {
    _requirePurchaseAccess(manage: true);
    final name = commercialName.trim();
    if (name.isEmpty) {
      throw ArgumentError('Captura el nombre comercial del proveedor.');
    }
    final employee = AppSession.instance.employee;
    final docRef = supplierId == null || supplierId.trim().isEmpty
        ? _suppliersRef.doc()
        : _suppliersRef.doc(supplierId.trim());
    await docRef.set({
      'id': docRef.id,
      'commercialName': name,
      'legalName': legalName.trim(),
      'rfc': rfc.trim(),
      'phone': phone.trim(),
      'contactName': contactName.trim(),
      'address': address.trim(),
      'notes': notes.trim(),
      'active': active,
      'preferredPaymentMethod': preferredPaymentMethod,
      'creditDays': creditDays < 0 ? 0 : creditDays,
      'paymentWeekday': paymentWeekday,
      'paymentWeekdayName': paymentWeekdayName,
      if (supplierId == null || supplierId.trim().isEmpty)
        'createdAt': FieldValue.serverTimestamp(),
      if (supplierId == null || supplierId.trim().isEmpty)
        'createdByEmployeeId': employee?.id ?? '',
      if (supplierId == null || supplierId.trim().isEmpty)
        'createdByEmployeeName': employee?.name ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmployeeId': employee?.id ?? '',
      'updatedByEmployeeName': employee?.name ?? '',
    }, SetOptions(merge: true));
  }

  Stream<List<PurchaseItem>> watchPurchaseItems({bool activeOnly = false}) {
    return _purchaseItemsRef.snapshots().map((snapshot) {
      final items = snapshot.docs.map(PurchaseItem.fromDoc).toList()
        ..sort((a, b) {
          final categoryCompare = a.category.compareTo(b.category);
          return categoryCompare != 0
              ? categoryCompare
              : a.name.compareTo(b.name);
        });
      return activeOnly ? items.where((item) => item.active).toList() : items;
    });
  }

  Future<void> savePurchaseItem({
    String? purchaseItemId,
    required String name,
    required String category,
    required String unit,
    required bool active,
    String? defaultSupplierId,
    String? defaultSupplierName,
    required bool affectsKitchenStock,
    String? kitchenStockItemId,
    String? kitchenStockItemName,
    String notes = '',
  }) async {
    _requirePurchaseAccess(manage: true);
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('Captura el nombre del insumo de compra.');
    }
    if (affectsKitchenStock && (kitchenStockItemId ?? '').trim().isEmpty) {
      throw ArgumentError('Selecciona el insumo de cocina relacionado.');
    }
    final docRef = purchaseItemId == null || purchaseItemId.trim().isEmpty
        ? _purchaseItemsRef.doc()
        : _purchaseItemsRef.doc(purchaseItemId.trim());
    await docRef.set({
      'id': docRef.id,
      'name': cleanName,
      'normalizedName': cleanName.toLowerCase(),
      'category': category.trim().isEmpty ? 'General' : category.trim(),
      'unit': unit.trim().isEmpty ? 'pieza' : unit.trim(),
      'active': active,
      'defaultSupplierId': defaultSupplierId,
      'defaultSupplierName': defaultSupplierName,
      'affectsKitchenStock': affectsKitchenStock,
      'kitchenStockItemId': affectsKitchenStock ? kitchenStockItemId : null,
      'kitchenStockItemName': affectsKitchenStock ? kitchenStockItemName : null,
      'notes': notes.trim(),
      if (purchaseItemId == null || purchaseItemId.trim().isEmpty)
        'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<SupplierPurchase>> watchSupplierPurchases({
    bool currentBranchOnly = true,
  }) {
    return _supplierPurchasesRef
        .orderBy('purchaseDate', descending: true)
        .snapshots()
        .map((snapshot) {
          final purchases = snapshot.docs.map(SupplierPurchase.fromDoc);
          return currentBranchOnly
              ? _filterCurrentBranch(purchases, (purchase) => purchase.branchId)
              : purchases.toList();
        });
  }

  Future<List<SupplierPurchase>> getSupplierPurchasesForPeriod({
    required DateTime startInclusive,
    required DateTime endExclusive,
    bool currentBranchOnly = true,
  }) async {
    _requirePurchaseAccess();
    final snapshot = await _supplierPurchasesRef
        .where('purchaseDate', isGreaterThanOrEqualTo: startInclusive)
        .where('purchaseDate', isLessThan: endExclusive)
        .get();
    final purchases = snapshot.docs.map(SupplierPurchase.fromDoc).toList()
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    return currentBranchOnly
        ? _filterCurrentBranch(purchases, (purchase) => purchase.branchId)
        : purchases;
  }

  Future<int> getNextSupplierPurchaseFolio() async {
    _requirePurchaseAccess(register: true);
    final counter = await _purchaseFolioCounterRef.get();
    final counterLast = (counter.data()?['lastSequence'] as num?)?.toInt();
    if (counterLast != null && counterLast >= 0) {
      return counterLast + 1;
    }
    final latest = await _latestSupplierPurchaseFolioNumber();
    return latest + 1;
  }

  Future<List<SupplierPurchase>> searchSupplierPurchasesByDueDate({
    String? supplierId,
    DateTime? startInclusive,
    DateTime? endExclusive,
    bool currentBranchOnly = true,
  }) async {
    _requirePurchaseAccess();
    Query<Map<String, dynamic>> query = _supplierPurchasesRef;
    final cleanSupplierId = supplierId?.trim() ?? '';
    if (cleanSupplierId.isNotEmpty) {
      query = query.where('supplierId', isEqualTo: cleanSupplierId);
    }
    if (startInclusive != null) {
      query = query.where('dueDate', isGreaterThanOrEqualTo: startInclusive);
    }
    if (endExclusive != null) {
      query = query.where('dueDate', isLessThan: endExclusive);
    }
    query = query.orderBy('dueDate');
    final snapshot = await query.get();
    final purchases = snapshot.docs.map(SupplierPurchase.fromDoc).toList()
      ..sort((a, b) {
        final byDue = _compareNullableDate(a.dueDate, b.dueDate);
        if (byDue != 0) return byDue;
        return b.purchaseDate.compareTo(a.purchaseDate);
      });
    return currentBranchOnly
        ? _filterCurrentBranch(purchases, (purchase) => purchase.branchId)
        : purchases;
  }

  Future<List<SupplierPurchase>> getSupplierPurchasesForSupplier({
    required String supplierId,
    bool currentBranchOnly = true,
  }) async {
    _requirePurchaseAccess();
    final snapshot = await _supplierPurchasesRef
        .where('supplierId', isEqualTo: supplierId.trim())
        .orderBy('purchaseDate', descending: true)
        .get();
    final purchases = snapshot.docs.map(SupplierPurchase.fromDoc).toList();
    return currentBranchOnly
        ? _filterCurrentBranch(purchases, (purchase) => purchase.branchId)
        : purchases;
  }

  Future<List<SupplierPayment>> searchSupplierPayments({
    String? supplierId,
    DateTime? startInclusive,
    DateTime? endExclusive,
    bool currentBranchOnly = true,
  }) async {
    _requirePurchaseAccess();
    Query<Map<String, dynamic>> query = _supplierPaymentsRef;
    final cleanSupplierId = supplierId?.trim() ?? '';
    if (cleanSupplierId.isNotEmpty) {
      query = query.where('supplierId', isEqualTo: cleanSupplierId);
    }
    if (startInclusive != null) {
      query = query.where(
        'paymentDate',
        isGreaterThanOrEqualTo: startInclusive,
      );
    }
    if (endExclusive != null) {
      query = query.where('paymentDate', isLessThan: endExclusive);
    }
    query = query.orderBy('paymentDate', descending: true);
    final snapshot = await query.get();
    final payments = snapshot.docs.map(SupplierPayment.fromDoc).toList();
    return currentBranchOnly
        ? _filterCurrentBranch(payments, (payment) => payment.branchId)
        : payments;
  }

  Future<List<SupplierPayment>> getSupplierPaymentsForSupplier({
    required String supplierId,
    bool currentBranchOnly = true,
  }) {
    return searchSupplierPayments(
      supplierId: supplierId,
      currentBranchOnly: currentBranchOnly,
    );
  }

  Future<List<SupplierPayment>> getSupplierPaymentsForPurchase(
    String purchaseId, {
    bool currentBranchOnly = true,
  }) async {
    _requirePurchaseAccess();
    final snapshot = await _supplierPaymentsRef
        .where('purchaseId', isEqualTo: purchaseId.trim())
        .orderBy('paymentDate', descending: true)
        .get();
    final payments = snapshot.docs.map(SupplierPayment.fromDoc).toList();
    return currentBranchOnly
        ? _filterCurrentBranch(payments, (payment) => payment.branchId)
        : payments;
  }

  Stream<List<SupplierPayment>> watchSupplierPayments({
    bool currentBranchOnly = true,
  }) {
    return _supplierPaymentsRef
        .orderBy('paymentDate', descending: true)
        .snapshots()
        .map((snapshot) {
          final payments = snapshot.docs.map(SupplierPayment.fromDoc);
          return currentBranchOnly
              ? _filterCurrentBranch(payments, (payment) => payment.branchId)
              : payments.toList();
        });
  }

  Stream<List<Partner>> watchPartners({bool activeOnly = false}) {
    return _partnersRef.snapshots().map((snapshot) {
      final partners = snapshot.docs.map(Partner.fromDoc).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return activeOnly
          ? partners.where((partner) => partner.active).toList()
          : partners;
    });
  }

  Future<List<Partner>> getPartnersOnce({bool activeOnly = false}) async {
    final snapshot = await _partnersRef.get();
    final partners = snapshot.docs.map(Partner.fromDoc).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return activeOnly
        ? partners.where((partner) => partner.active).toList()
        : partners;
  }

  Future<List<SupplierPurchaseItem>> getSupplierPurchaseItemsOnce(
    String purchaseId,
  ) async {
    final snapshot = await _supplierPurchasesRef
        .doc(purchaseId)
        .collection('items')
        .get();
    return snapshot.docs
        .map(SupplierPurchaseItem.fromDoc)
        .where((item) => item.isActive)
        .toList(growable: false);
  }

  Stream<List<DiscountAuthorizationRequest>>
  watchDiscountAuthorizationRequests({
    String? status,
    String? startBusinessDate,
    String? endBusinessDate,
    String? partnerId,
    String? requestedByEmployeeId,
  }) {
    return _discountAuthorizationRequestsRef.snapshots().map((snapshot) {
      final requests =
          snapshot.docs.map(DiscountAuthorizationRequest.fromDoc).where((
            request,
          ) {
            if (!_matchesCurrentBranch(request.branchId)) return false;
            if (status != null &&
                status.trim().isNotEmpty &&
                request.status != status.trim() &&
                !(status.trim() == 'approved' &&
                    request.status == 'auto_approved')) {
              return false;
            }
            if (startBusinessDate != null &&
                startBusinessDate.isNotEmpty &&
                request.businessDate.compareTo(startBusinessDate) < 0) {
              return false;
            }
            if (endBusinessDate != null &&
                endBusinessDate.isNotEmpty &&
                request.businessDate.compareTo(endBusinessDate) > 0) {
              return false;
            }
            if (partnerId != null &&
                partnerId.trim().isNotEmpty &&
                request.requestedPartnerId != partnerId.trim() &&
                request.approvedByPartnerId != partnerId.trim() &&
                request.rejectedByPartnerId != partnerId.trim()) {
              return false;
            }
            if (requestedByEmployeeId != null &&
                requestedByEmployeeId.trim().isNotEmpty &&
                request.requestedByEmployeeId != requestedByEmployeeId.trim()) {
              return false;
            }
            return true;
          }).toList()..sort((a, b) {
            final aDate =
                a.requestedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate =
                b.requestedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
      return requests;
    });
  }

  Stream<List<DiscountAuthorizationRequest>>
  watchDiscountAuthorizationRequestsForOrder(String orderId) {
    final cleanOrderId = orderId.trim();
    return watchDiscountAuthorizationRequests().map(
      (requests) => requests
          .where(
            (request) =>
                request.orderId == cleanOrderId &&
                request.requestedDiscountType == 'family_friend_20',
          )
          .toList(),
    );
  }

  Future<String> requestFamilyFriendDiscountAuthorization({
    required PosOrder order,
    required double amountBeforeDiscount,
    required String requestedPartnerId,
    required String reason,
  }) async {
    _requireCharge();
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Captura el motivo de la autorización.');
    }
    if (amountBeforeDiscount <= 0 || order.paymentStatus == 'paid') {
      throw StateError('No hay saldo pendiente para solicitar descuento.');
    }
    final partner = await _partnerById(requestedPartnerId);
    if (partner == null || !partner.active) {
      throw StateError('Selecciona un socio activo.');
    }
    final cashSession = await _requireOpenCashSessionForPayment();
    final employee = AppSession.instance.employee;
    final estimatedDiscount = (amountBeforeDiscount * 0.20).clamp(
      0,
      amountBeforeDiscount,
    );
    final docRef = _discountAuthorizationRequestsRef.doc();
    await docRef.set({
      'id': docRef.id,
      'restaurantId': order.restaurantId,
      'restaurantName': order.restaurantName,
      'branchId': order.branchId,
      'branchName': order.branchName,
      'businessDate': cashSession.businessDate,
      'orderId': order.id,
      'tableId': order.tableId,
      'tableName': order.displayName,
      'orderType': order.orderType,
      'customerName': order.customerName,
      'requestedDiscountType': 'family_friend_20',
      'requestedDiscountName': 'Familia / amigos 20%',
      'requestedDiscountPercent': 20.0,
      'amountBeforeDiscount': amountBeforeDiscount,
      'estimatedDiscountAmount': estimatedDiscount,
      'estimatedTotalAfterDiscount': amountBeforeDiscount - estimatedDiscount,
      'requestedPartnerId': partner.id,
      'requestedPartnerName': partner.name,
      'requestReason': cleanReason,
      'status': 'pending',
      'requestedAt': FieldValue.serverTimestamp(),
      'requestedByEmployeeId': employee?.id ?? '',
      'requestedByEmployeeName': employee?.name ?? '',
      'approvedAt': null,
      'approvedByEmployeeId': '',
      'approvedByEmployeeName': '',
      'approvedByPartnerId': '',
      'approvedByPartnerName': '',
      'rejectedAt': null,
      'rejectedByEmployeeId': '',
      'rejectedByEmployeeName': '',
      'rejectedByPartnerId': '',
      'rejectedByPartnerName': '',
      'rejectReason': '',
      'cancelledAt': null,
      'cancelledByEmployeeId': '',
      'cancelledByEmployeeName': '',
      'cancelReason': '',
      'usedAt': null,
      'usedPaymentId': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> cancelDiscountAuthorizationRequest({
    required String requestId,
    String reason = '',
  }) async {
    _requireCharge();
    final docRef = _discountAuthorizationRequestsRef.doc(requestId.trim());
    final doc = await docRef.get();
    if (!doc.exists) {
      throw StateError('La solicitud ya no existe.');
    }
    final request = DiscountAuthorizationRequest.fromDoc(doc);
    if (!request.isPending) {
      throw StateError('Solo se pueden cancelar solicitudes pendientes.');
    }
    final employee = AppSession.instance.employee;
    await docRef.update({
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledByEmployeeId': employee?.id ?? '',
      'cancelledByEmployeeName': employee?.name ?? '',
      'cancelReason': reason.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Partner?> currentEmployeeActivePartner() {
    final employeeId = AppSession.instance.employee?.id ?? '';
    return _activePartnerLinkedToEmployee(employeeId);
  }

  Future<void> resolveDiscountAuthorizationRequest({
    required String requestId,
    required bool approved,
    String rejectReason = '',
  }) async {
    final employee = AppSession.instance.employee;
    if (employee == null) {
      throw StateError('Inicia sesión para revisar autorizaciones.');
    }
    final partner = await _activePartnerLinkedToEmployee(employee.id);
    if (partner == null) {
      throw StateError('Solo un socio puede autorizar este descuento.');
    }
    final cleanRejectReason = rejectReason.trim();
    if (!approved && cleanRejectReason.isEmpty) {
      throw ArgumentError('Captura el motivo del rechazo.');
    }
    final docRef = _discountAuthorizationRequestsRef.doc(requestId.trim());
    final doc = await docRef.get();
    if (!doc.exists) {
      throw StateError('La solicitud ya no existe.');
    }
    final request = DiscountAuthorizationRequest.fromDoc(doc);
    if (!request.isPending) {
      throw StateError('La solicitud ya fue atendida.');
    }

    await docRef.update({
      'status': approved ? 'approved' : 'rejected',
      if (approved) ...{
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedByEmployeeId': employee.id,
        'approvedByEmployeeName': employee.name,
        'approvedByPartnerId': partner.id,
        'approvedByPartnerName': partner.name,
      } else ...{
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedByEmployeeId': employee.id,
        'rejectedByEmployeeName': employee.name,
        'rejectedByPartnerId': partner.id,
        'rejectedByPartnerName': partner.name,
        'rejectReason': cleanRejectReason,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<GeneralDiscountConfig> watchGeneralDiscountConfig() {
    return _discountSettingsRef.snapshots().map(
      (doc) => _generalDiscountFromData(doc.data()),
    );
  }

  Future<GeneralDiscountConfig> getGeneralDiscountConfigOnce() async {
    final doc = await _discountSettingsRef.get();
    return _generalDiscountFromData(doc.data());
  }

  Future<void> saveGeneralDiscountConfig({
    required bool active,
    required String name,
    required double percent,
    String description = '',
    String branchId = 'all',
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.hasAdminAccess == true,
      'No tienes permiso para configurar descuentos.',
    );
    if (percent < 0 || percent > 100) {
      throw ArgumentError('Captura un porcentaje entre 0 y 100.');
    }
    await _discountSettingsRef.set({
      'active': active,
      'name': name.trim().isEmpty ? 'Descuento general' : name.trim(),
      'percent': percent,
      'description': description.trim(),
      'branchId': branchId.trim().isEmpty ? 'all' : branchId.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      ..._employeeAuditFields(prefix: 'updatedBy'),
    }, SetOptions(merge: true));
  }

  Stream<List<DiscountUsageRow>> watchDiscountUsage() {
    return _discountUsageRef
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(DiscountUsageRow.fromDoc)
              .where((row) => _matchesCurrentBranch(row.branchId))
              .toList(),
        );
  }

  Future<AppliedDiscountDetails?> authorizeDiscount({
    required PosOrder order,
    required double amountBeforeDiscount,
    required String discountType,
    String? employeeId,
    String pin = '',
    String? partnerId,
    String reason = '',
  }) async {
    if (amountBeforeDiscount <= 0 || order.paymentStatus == 'paid') {
      throw StateError('No hay saldo pendiente para aplicar descuento.');
    }
    final cashSession = await _requireOpenCashSessionForPayment();
    final type = discountType.trim();

    if (type == 'general') {
      final config = await getGeneralDiscountConfigOnce();
      if (!config.appliesToCurrentBranch(AppSession.instance.currentBranchId)) {
        throw StateError('El descuento general no esta activo.');
      }
      return _discountDetails(
        order: order,
        type: 'general',
        name: config.name,
        percent: config.percent,
        amountBeforeDiscount: amountBeforeDiscount,
      );
    }

    final employeeBenefitType = employeeBenefitTypeFromDiscountType(type);
    if (employeeBenefitType != null) {
      if (employeeBenefitType == EmployeeBenefitType.dailyMeal &&
          order.orderType == 'takeout') {
        throw StateError('La comida del dia solo aplica en consumo local.');
      }
      final employee = await _employeeById(employeeId);
      if (employee == null || !employee.active) {
        throw StateError('PIN incorrecto. No se aplico descuento.');
      }
      final linkedPartner = await _activePartnerLinkedToEmployee(employee.id);
      if (linkedPartner != null) {
        throw StateError(
          'Este usuario está registrado como socio. No aplica beneficio de empleado.',
        );
      }
      if (employee.pin != pin.trim()) {
        throw StateError('PIN incorrecto. No se aplico descuento.');
      }
      await _ensureEmployeeDiscountNotUsed(
        employeeId: employee.id,
        discountType: type,
        businessDate: cashSession.businessDate,
        branchId: order.branchId,
      );
      final benefit = calculateEmployeeBenefitCheckout(
        type: employeeBenefitType,
        eligiblePendingAmount: amountBeforeDiscount,
      );
      return _discountDetails(
        order: order,
        type: benefit.discountType,
        name: benefit.name,
        percent: benefit.percent,
        amountBeforeDiscount: benefit.amountBeforeDiscount,
        discountAmountOverride: benefit.discountAmount,
        totalAfterDiscountOverride: benefit.totalAfterDiscount,
        employeeBeneficiaryId: employee.id,
        employeeBeneficiaryName: employee.name,
      );
    }

    if (type == 'family_friend_20') {
      final cleanReason = reason.trim();
      if (cleanReason.isEmpty) {
        throw ArgumentError('Captura el motivo del descuento.');
      }
      final cleanRequestId = await _createAutomaticFamilyFriendAuthorization(
        order: order,
        cashSession: cashSession,
        amountBeforeDiscount: amountBeforeDiscount,
        reason: cleanReason,
      );
      if (cleanRequestId.isEmpty) {
        throw StateError(
          'Solicita autorización antes de aplicar este descuento.',
        );
      }
      final requestDoc = await _discountAuthorizationRequestsRef
          .doc(cleanRequestId)
          .get();
      if (!requestDoc.exists) {
        throw StateError('La autorización ya no existe.');
      }
      final request = DiscountAuthorizationRequest.fromDoc(requestDoc);
      if (request.orderId != order.id ||
          request.requestedDiscountType != 'family_friend_20') {
        throw StateError('La autorización no corresponde a esta orden.');
      }
      if (!request.isUsable) {
        throw StateError(
          request.isRejected
              ? 'Descuento rechazado.'
              : 'La autorización no está disponible.',
        );
      }
      final approvedPartnerId = request.approvedByPartnerId.isNotEmpty
          ? request.approvedByPartnerId
          : request.requestedPartnerId;
      final approvedPartner = await _partnerById(approvedPartnerId);
      return _discountDetails(
        order: order,
        type: type,
        name: 'Familia / amigos 20%',
        percent: 20.0,
        amountBeforeDiscount: amountBeforeDiscount,
        authorizedByPartnerId: approvedPartnerId,
        authorizedByPartnerName: request.approvedByPartnerName.isNotEmpty
            ? request.approvedByPartnerName
            : request.requestedPartnerName,
        authorizedByPartnerLinkedEmployeeId: approvedPartner?.linkedEmployeeId,
        authorizedByPartnerLinkedEmployeeName:
            approvedPartner?.linkedEmployeeName,
        discountAuthorizationRequestId: request.id,
        authorizationMode: 'automatic',
        authorizationStatus: 'auto_approved',
        reason: request.requestReason,
      );
    }

    if (type == 'partner_50') {
      final partner = await _partnerById(partnerId);
      if (partner == null || !partner.active || partner.pin != pin.trim()) {
        throw StateError('PIN incorrecto. No se aplico descuento.');
      }
      return _discountDetails(
        order: order,
        type: type,
        name: 'Socio 50%',
        percent: 50.0,
        amountBeforeDiscount: amountBeforeDiscount,
        authorizedByPartnerId: partner.id,
        authorizedByPartnerName: partner.name,
        authorizedByPartnerLinkedEmployeeId: partner.linkedEmployeeId,
        authorizedByPartnerLinkedEmployeeName: partner.linkedEmployeeName,
        reason: reason.trim(),
      );
    }

    throw ArgumentError('Selecciona un descuento valido.');
  }

  GeneralDiscountConfig _generalDiscountFromData(Map<String, dynamic>? data) {
    final values = data ?? const {};
    return GeneralDiscountConfig(
      active: values['active'] as bool? ?? false,
      name: values['name'] as String? ?? 'Descuento general',
      percent: _numberToDouble(values['percent']),
      description: values['description'] as String? ?? '',
      branchId: values['branchId'] as String? ?? 'all',
    );
  }

  Future<String> _createAutomaticFamilyFriendAuthorization({
    required PosOrder order,
    required CashSession cashSession,
    required double amountBeforeDiscount,
    required String reason,
  }) async {
    final employee = AppSession.instance.employee;
    final discountAmount = (amountBeforeDiscount * 0.20).clamp(
      0,
      amountBeforeDiscount,
    );
    final totalAfterDiscount = amountBeforeDiscount - discountAmount;
    final docRef = _discountAuthorizationRequestsRef.doc();
    await docRef.set({
      'id': docRef.id,
      'restaurantId': order.restaurantId,
      'restaurantName': order.restaurantName,
      'branchId': order.branchId,
      'branchName': order.branchName,
      'businessDate': cashSession.businessDate,
      'orderId': order.id,
      'tableId': order.tableId,
      'tableName': order.tableName,
      'orderType': order.orderType,
      'requestedDiscountType': 'family_friend_20',
      'type': 'family_friend_20',
      'requestedDiscountName': 'Familia / amigos 20%',
      'requestedDiscountPercent': 20.0,
      'amountBeforeDiscount': amountBeforeDiscount,
      'subtotal': amountBeforeDiscount,
      'estimatedDiscountAmount': discountAmount,
      'discountAmount': discountAmount,
      'estimatedTotalAfterDiscount': totalAfterDiscount,
      'totalAfterDiscount': totalAfterDiscount,
      'requestedPartnerId': '',
      'requestedPartnerName': '',
      'requestReason': reason,
      'discountReason': reason,
      'status': 'auto_approved',
      'authorizationMode': 'automatic',
      'requestedAt': FieldValue.serverTimestamp(),
      'approvedAt': FieldValue.serverTimestamp(),
      'requestedByEmployeeId': employee?.id ?? '',
      'requestedByEmployeeName': employee?.name ?? '',
      'approvedByEmployeeId': employee?.id ?? '',
      'approvedByEmployeeName': employee?.name ?? 'Autorizacion automatica',
      'approvedByPartnerId': '',
      'approvedByPartnerName': 'Autorizacion automatica',
      'rejectedAt': null,
      'rejectedByEmployeeId': '',
      'rejectedByEmployeeName': '',
      'rejectedByPartnerId': '',
      'rejectedByPartnerName': '',
      'rejectReason': '',
      'cancelledAt': null,
      'cancelledByEmployeeId': '',
      'cancelledByEmployeeName': '',
      'cancelReason': '',
      'usedAt': null,
      'usedPaymentId': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  AppliedDiscountDetails _discountDetails({
    required PosOrder order,
    required String type,
    required String name,
    required double percent,
    required double amountBeforeDiscount,
    String? authorizedByPartnerId,
    String? authorizedByPartnerName,
    String? authorizedByPartnerLinkedEmployeeId,
    String? authorizedByPartnerLinkedEmployeeName,
    String? employeeBeneficiaryId,
    String? employeeBeneficiaryName,
    String? discountAuthorizationRequestId,
    String authorizationMode = '',
    String authorizationStatus = '',
    String reason = '',
    double? discountAmountOverride,
    double? totalAfterDiscountOverride,
  }) {
    final percentValue = percent.isFinite ? percent : 0.0;
    final amountValue = amountBeforeDiscount.isFinite
        ? amountBeforeDiscount
        : 0.0;
    final cleanPercent = percentValue.clamp(0, 100).toDouble();
    final subtotal = roundCheckoutMoney(
      amountValue.clamp(0, double.infinity).toDouble(),
    );
    final discountAmount = roundCheckoutMoney(
      (discountAmountOverride ?? subtotal * cleanPercent / 100)
          .clamp(0, subtotal)
          .toDouble(),
    );
    final totalAfterDiscount = roundCheckoutMoney(
      (totalAfterDiscountOverride ?? subtotal - discountAmount)
          .clamp(0, double.infinity)
          .toDouble(),
    );
    return AppliedDiscountDetails(
      type: type,
      name: name,
      percent: cleanPercent,
      amountBeforeDiscount: subtotal,
      discountAmount: discountAmount,
      totalAfterDiscount: totalAfterDiscount,
      orderId: order.id,
      restaurantId: order.restaurantId,
      branchId: order.branchId,
      businessDate: _businessDateForOrder(order),
      totalSnapshot: order.total,
      authorizedByPartnerId: authorizedByPartnerId,
      authorizedByPartnerName: authorizedByPartnerName,
      authorizedByPartnerLinkedEmployeeId: authorizedByPartnerLinkedEmployeeId,
      authorizedByPartnerLinkedEmployeeName:
          authorizedByPartnerLinkedEmployeeName,
      employeeBeneficiaryId: employeeBeneficiaryId,
      employeeBeneficiaryName: employeeBeneficiaryName,
      discountAuthorizationRequestId: discountAuthorizationRequestId,
      authorizationMode: authorizationMode,
      authorizationStatus: authorizationStatus,
      reason: reason,
    );
  }

  Future<Employee?> _employeeById(String? employeeId) async {
    final cleanId = employeeId?.trim();
    if (cleanId == null || cleanId.isEmpty) return null;
    final doc = await _employeesRef.doc(cleanId).get();
    return doc.exists ? Employee.fromDoc(doc) : null;
  }

  Future<Partner?> _partnerById(String? partnerId) async {
    final cleanId = partnerId?.trim();
    if (cleanId == null || cleanId.isEmpty) return null;
    final doc = await _partnersRef.doc(cleanId).get();
    return doc.exists ? Partner.fromDoc(doc) : null;
  }

  Future<Partner?> _activePartnerLinkedToEmployee(String employeeId) async {
    final cleanId = employeeId.trim();
    if (cleanId.isEmpty) return null;
    final snapshot = await _partnersRef
        .where('active', isEqualTo: true)
        .where('linkedEmployeeId', isEqualTo: cleanId)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return Partner.fromDoc(snapshot.docs.first);
  }

  Future<void> _ensureEmployeeDiscountNotUsed({
    required String employeeId,
    required String discountType,
    required String businessDate,
    required String branchId,
  }) async {
    final snapshot = await _discountUsageRef
        .where('employeeId', isEqualTo: employeeId)
        .where('discountType', isEqualTo: discountType)
        .where('businessDate', isEqualTo: businessDate)
        .where('branchId', isEqualTo: branchId)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (snapshot.docs.isNotEmpty) {
      throw StateError(
        discountType == 'employee_free_meal'
            ? 'Este empleado ya uso su comida del dia.'
            : 'Este empleado ya uso su descuento del 30% hoy.',
      );
    }
  }

  Stream<List<PartnerContribution>> watchPartnerContributions({
    bool currentBranchOnly = true,
  }) {
    return _partnerContributionsRef
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
          final contributions = snapshot.docs.map(PartnerContribution.fromDoc);
          return currentBranchOnly
              ? _filterCurrentBranch(
                  contributions,
                  (contribution) => contribution.branchId,
                )
              : contributions.toList();
        });
  }

  Future<void> ensureDefaultPartners() async {
    _requirePurchaseAccess(manage: true);
    final snapshot = await _partnersRef.get();
    final existingNames = snapshot.docs
        .map((doc) => (doc.data()['name'] ?? '').toString().toLowerCase())
        .toSet();
    final batch = _db.batch();
    var hasUpdates = false;
    for (final name in const ['Adolfo', 'Gabriel', 'Cristian']) {
      if (existingNames.contains(name.toLowerCase())) {
        continue;
      }
      final ref = _partnersRef.doc();
      batch.set(ref, {
        'id': ref.id,
        'name': name,
        'active': true,
        'ownershipPercent': 0.0,
        'phone': '',
        'pin': '',
        'linkedEmployeeId': '',
        'linkedEmployeeName': '',
        'notes': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      hasUpdates = true;
    }
    if (hasUpdates) {
      await batch.commit();
    }
  }

  Future<void> savePartner({
    String? partnerId,
    required String name,
    required bool active,
    double ownershipPercent = 0,
    String phone = '',
    String pin = '',
    String linkedEmployeeId = '',
    String linkedEmployeeName = '',
    String notes = '',
  }) async {
    _requirePurchaseAccess(manage: true);
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('Captura el nombre del socio.');
    }
    final docRef = partnerId == null || partnerId.trim().isEmpty
        ? _partnersRef.doc()
        : _partnersRef.doc(partnerId.trim());
    await docRef.set({
      'id': docRef.id,
      'name': cleanName,
      'active': active,
      'ownershipPercent': ownershipPercent < 0 ? 0 : ownershipPercent,
      'phone': phone.trim(),
      if (pin.trim().isNotEmpty) 'pin': pin.trim(),
      'linkedEmployeeId': linkedEmployeeId.trim(),
      'linkedEmployeeName': linkedEmployeeName.trim(),
      'notes': notes.trim(),
      if (partnerId == null || partnerId.trim().isEmpty)
        'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<SupplierPurchaseItem>> watchSupplierPurchaseItems(
    String purchaseId,
  ) {
    return _supplierPurchasesRef
        .doc(purchaseId)
        .collection('items')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(SupplierPurchaseItem.fromDoc)
              .where((item) => item.isActive)
              .toList(),
        );
  }

  Future<List<SupplierPurchaseItem>> getSupplierPurchaseItemsForPurchases(
    Iterable<SupplierPurchase> purchases,
  ) async {
    final items = <SupplierPurchaseItem>[];
    for (final purchase in purchases) {
      if (purchase.status == 'cancelled') {
        continue;
      }
      final snapshot = await _supplierPurchasesRef
          .doc(purchase.id)
          .collection('items')
          .get();
      items.addAll(
        snapshot.docs
            .map(SupplierPurchaseItem.fromDoc)
            .where((item) => item.isActive),
      );
    }
    return items;
  }

  Future<int> _latestSupplierPurchaseFolioNumber() async {
    final withCanonical = await _supplierPurchasesRef
        .orderBy('folioNumber', descending: true)
        .limit(1)
        .get();
    for (final doc in withCanonical.docs) {
      final value = (doc.data()['folioNumber'] as num?)?.toInt();
      if (value != null && value > 0) return value;
    }
    final legacy = await _supplierPurchasesRef
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    var latest = 0;
    for (final doc in legacy.docs) {
      final purchase = SupplierPurchase.fromDoc(doc);
      final number = purchase.folioNumber;
      if (number != null && number > latest) latest = number;
    }
    return latest;
  }

  Future<SupplierPurchase> createSupplierPurchase({
    required Supplier supplier,
    required DateTime purchaseDate,
    required DateTime dueDate,
    required String folio,
    required String documentType,
    required List<PurchaseLineInput> items,
    String notes = '',
  }) async {
    _requirePurchaseAccess(register: true);
    if (items.isEmpty) {
      throw ArgumentError('Agrega al menos un renglon de compra.');
    }
    final invalidItem = items.any((item) => !isValidPurchaseLineInput(item));
    if (invalidItem) {
      throw ArgumentError('Revisa cantidad e importe de los renglones.');
    }
    final employee = AppSession.instance.employee;
    final total = purchaseLinesTotal(items);
    if (total <= 0) {
      throw ArgumentError(
        'El total final de la compra debe ser mayor a \$0.00.',
      );
    }
    final initialLastFolio = await _latestSupplierPurchaseFolioNumber();
    final purchaseRef = _supplierPurchasesRef.doc();
    final branchFields = _currentBranchFields;
    final assignedFolio = await _db.runTransaction<int>((transaction) async {
      final counterDoc = await transaction.get(_purchaseFolioCounterRef);
      final currentLast =
          (counterDoc.data()?['lastSequence'] as num?)?.toInt() ??
          initialLastFolio;
      final nextFolio = currentLast + 1;
      final now = FieldValue.serverTimestamp();
      transaction.set(_purchaseFolioCounterRef, {
        'lastSequence': nextFolio,
        'updatedAt': now,
        'updatedByEmployeeId': employee?.id ?? '',
        'updatedByEmployeeName': employee?.name ?? '',
      }, SetOptions(merge: true));
      transaction.set(purchaseRef, {
        'id': purchaseRef.id,
        ...branchFields,
        'supplierId': supplier.id,
        'supplierName': supplier.commercialName,
        'purchaseDate': Timestamp.fromDate(purchaseDate),
        'dueDate': Timestamp.fromDate(dueDate),
        'paymentWeekdaySnapshot': supplier.paymentWeekday,
        'paymentWeekdayNameSnapshot': supplier.paymentWeekdayName,
        'folio': nextFolio.toString(),
        'folioNumber': nextFolio,
        'documentType': documentType,
        'status': 'pending',
        'subtotal': total,
        'total': total,
        'paidTotal': 0.0,
        'balance': total,
        'notes': notes.trim(),
        'createdAt': now,
        'updatedAt': now,
        'createdByEmployeeId': employee?.id ?? '',
        'createdByEmployeeName': employee?.name ?? '',
      });
      for (final item in items) {
        final itemRef = purchaseRef.collection('items').doc();
        final itemId = item.kitchenStockItemId ?? item.purchaseItemId;
        final itemName = item.kitchenStockItemName ?? item.purchaseItemName;
        transaction.set(itemRef, {
          'id': itemRef.id,
          'itemId': itemId,
          'itemName': itemName.trim(),
          'purchaseItemId': item.purchaseItemId,
          'purchaseItemName': item.purchaseItemName.trim(),
          'kitchenStockItemId': item.kitchenStockItemId,
          'kitchenStockItemName': item.kitchenStockItemName,
          'affectsKitchenStock': item.affectsKitchenStock,
          'affectsKitchenPerformance': item.affectsKitchenStock,
          'quantity': item.quantity,
          'unit': item.unit,
          'unitCost': item.unitCostCalculated,
          'unitCostCalculated': item.unitCostCalculated,
          'lineTotal': item.lineTotal,
          'lineTotalCents': item.lineTotalCents,
          'calculationMode': item.calculationMode,
          'total': item.lineTotal,
          'status': 'active',
          'notes': item.notes.trim(),
          'updatedAt': now,
        });
      }
      return nextFolio;
    });
    return SupplierPurchase(
      id: purchaseRef.id,
      restaurantId: branchFields['restaurantId']?.toString() ?? '',
      restaurantName: branchFields['restaurantName']?.toString() ?? '',
      branchId: branchFields['branchId']?.toString() ?? '',
      branchName: branchFields['branchName']?.toString() ?? '',
      supplierId: supplier.id,
      supplierName: supplier.commercialName,
      purchaseDate: purchaseDate,
      dueDate: dueDate,
      paymentWeekdaySnapshot: supplier.paymentWeekday,
      paymentWeekdayNameSnapshot: supplier.paymentWeekdayName,
      folio: assignedFolio.toString(),
      folioNumber: assignedFolio,
      documentType: documentType,
      status: 'pending',
      subtotal: total,
      total: total,
      paidTotal: 0,
      balance: total,
      notes: notes.trim(),
      createdByEmployeeId: employee?.id ?? '',
      createdByEmployeeName: employee?.name ?? '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> updateSupplierPurchase({
    required SupplierPurchase purchase,
    required Supplier supplier,
    required DateTime purchaseDate,
    required DateTime dueDate,
    required String folio,
    required String documentType,
    required List<PurchaseLineInput> items,
    String notes = '',
  }) async {
    _requirePurchaseAccess(manage: true);
    if (items.isEmpty) {
      throw ArgumentError('La compra debe tener al menos un articulo.');
    }
    final invalidItem = items.any(
      (item) =>
          (item.kitchenStockItemId ?? item.purchaseItemId ?? '')
              .trim()
              .isEmpty ||
          !isValidPurchaseLineInput(item),
    );
    if (invalidItem) {
      throw ArgumentError('Revisa cantidad e importe de los renglones.');
    }
    final purchaseRef = _supplierPurchasesRef.doc(purchase.id);
    final purchaseDoc = await purchaseRef.get();
    if (!purchaseDoc.exists) {
      throw StateError('No se encontro la compra a proveedor.');
    }
    final currentPurchase = SupplierPurchase.fromDoc(purchaseDoc);
    if (currentPurchase.isCancelled) {
      throw StateError('No puedes editar una compra cancelada.');
    }
    final total = purchaseLinesTotal(items);
    if (total <= 0) {
      throw ArgumentError(
        'El total final de la compra debe ser mayor a \$0.00.',
      );
    }
    if (total + 0.01 < currentPurchase.paidTotal) {
      throw ArgumentError(
        'No puedes dejar el total por debajo de lo ya pagado.',
      );
    }
    final nextBalance = (total - currentPurchase.paidTotal).clamp(
      0,
      double.infinity,
    );
    final nextStatus = currentPurchase.paidTotal <= 0.01
        ? 'pending'
        : nextBalance <= 0.01
        ? 'paid'
        : 'partial';
    final employee = AppSession.instance.employee;
    final existingItemsSnapshot = await purchaseRef.collection('items').get();
    final existingActiveDocs = {
      for (final doc in existingItemsSnapshot.docs)
        if (SupplierPurchaseItem.fromDoc(doc).isActive) doc.id: doc.reference,
    };
    final previousItemsCount = existingActiveDocs.length;
    final paymentsSnapshot = await _supplierPaymentsRef
        .where('purchaseId', isEqualTo: currentPurchase.id)
        .get();
    final batch = _db.batch();
    batch.set(purchaseRef, {
      'supplierId': supplier.id,
      'supplierName': supplier.commercialName,
      'purchaseDate': Timestamp.fromDate(purchaseDate),
      'dueDate': Timestamp.fromDate(dueDate),
      'paymentWeekdaySnapshot': supplier.paymentWeekday,
      'paymentWeekdayNameSnapshot': supplier.paymentWeekdayName,
      'folio': folio.trim(),
      'folioNumber': int.tryParse(folio.trim()),
      'documentType': documentType,
      'status': nextStatus,
      'subtotal': total,
      'total': total,
      'balance': nextBalance,
      'notes': notes.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmployeeId': employee?.id ?? '',
      'updatedByEmployeeName': employee?.name ?? '',
    }, SetOptions(merge: true));
    final keptItemIds = <String>{};
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final existingItemId = item.supplierPurchaseItemId?.trim();
      final itemRef =
          existingItemId != null &&
              existingItemId.isNotEmpty &&
              existingActiveDocs.containsKey(existingItemId)
          ? existingActiveDocs[existingItemId]!
          : purchaseRef.collection('items').doc();
      keptItemIds.add(itemRef.id);
      final itemId = item.kitchenStockItemId ?? item.purchaseItemId;
      final itemName = item.kitchenStockItemName ?? item.purchaseItemName;
      batch.set(itemRef, {
        'id': itemRef.id,
        'itemId': itemId,
        'itemName': itemName.trim(),
        'purchaseItemId': item.purchaseItemId,
        'purchaseItemName': item.purchaseItemName.trim(),
        'kitchenStockItemId': item.kitchenStockItemId,
        'kitchenStockItemName': item.kitchenStockItemName,
        'affectsKitchenStock': item.affectsKitchenStock,
        'affectsKitchenPerformance': item.affectsKitchenStock,
        'quantity': item.quantity,
        'unit': item.unit,
        'unitCost': item.unitCostCalculated,
        'unitCostCalculated': item.unitCostCalculated,
        'lineTotal': item.lineTotal,
        'lineTotalCents': item.lineTotalCents,
        'calculationMode': item.calculationMode,
        'total': item.lineTotal,
        'status': 'active',
        'notes': item.notes.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    for (final entry in existingActiveDocs.entries) {
      if (keptItemIds.contains(entry.key)) {
        continue;
      }
      batch.set(entry.value, {
        'status': 'removed',
        'quantity': 0,
        'unitCost': 0,
        'unitCostCalculated': 0,
        'lineTotal': 0,
        'lineTotalCents': 0,
        'calculationMode': 'line_total',
        'total': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    for (final paymentDoc in paymentsSnapshot.docs) {
      batch.set(paymentDoc.reference, {
        'supplierId': supplier.id,
        'supplierName': supplier.commercialName,
        'purchaseFolio': folio.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    final logRef = _restaurantRef.collection('activityLog').doc();
    batch.set(logRef, {
      'id': logRef.id,
      ..._currentBranchFields,
      'type': 'supplier_purchase_updated',
      'actionType': 'supplier_purchase_updated',
      'message':
          'Se modifico la compra a proveedor ${supplier.commercialName} folio ${folio.trim()}',
      'supplierId': supplier.id,
      'supplierName': supplier.commercialName,
      'purchaseId': currentPurchase.id,
      'purchaseFolio': folio.trim(),
      'previousTotal': currentPurchase.total,
      'newTotal': total,
      'previousItemsCount': previousItemsCount,
      'newItemsCount': items.length,
      'employeeId': employee?.id ?? '',
      'employeeName': employee?.name ?? '',
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
    });
    await batch.commit();
    invalidateReportDataCache(branchId: currentPurchase.branchId);
  }

  Future<void> updateSupplierPurchaseDueDate({
    required SupplierPurchase purchase,
    required DateTime dueDate,
    required String reason,
  }) async {
    _requirePurchaseAccess(manage: true);
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Captura el motivo del cambio.');
    }
    final purchaseRef = _supplierPurchasesRef.doc(purchase.id);
    final purchaseDoc = await purchaseRef.get();
    if (!purchaseDoc.exists) {
      throw StateError('No se encontro la compra a proveedor.');
    }
    final currentPurchase = SupplierPurchase.fromDoc(purchaseDoc);
    if (currentPurchase.isCancelled) {
      throw StateError(
        'No puedes cambiar vencimiento de una compra cancelada.',
      );
    }
    final employee = AppSession.instance.employee;
    final logRef = _restaurantRef.collection('activityLog').doc();
    final batch = _db.batch();
    batch.set(purchaseRef, {
      'dueDate': Timestamp.fromDate(dueDate),
      'dueDateUpdatedAt': FieldValue.serverTimestamp(),
      'dueDateUpdatedByEmployeeId': employee?.id ?? '',
      'dueDateUpdatedByEmployeeName': employee?.name ?? '',
      'dueDateUpdateReason': cleanReason,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(logRef, {
      'id': logRef.id,
      ..._currentBranchFields,
      'type': 'supplier_purchase_due_date_updated',
      'actionType': 'supplier_purchase_due_date_updated',
      'message':
          'Se cambio la fecha de vencimiento de la compra ${currentPurchase.folio} '
          'del proveedor ${currentPurchase.supplierName}',
      'supplierId': currentPurchase.supplierId,
      'supplierName': currentPurchase.supplierName,
      'purchaseId': currentPurchase.id,
      'purchaseFolio': currentPurchase.folio,
      'previousDueDate': currentPurchase.dueDate == null
          ? null
          : Timestamp.fromDate(currentPurchase.dueDate!),
      'newDueDate': Timestamp.fromDate(dueDate),
      'reason': cleanReason,
      'employeeId': employee?.id ?? '',
      'employeeName': employee?.name ?? '',
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
    });
    await batch.commit();
  }

  Future<void> updateSupplierPurchaseBackofficeDates({
    required SupplierPurchase purchase,
    required DateTime purchaseDate,
    required DateTime dueDate,
  }) async {
    _requirePurchaseAccess(manage: true);
    final purchaseRef = _supplierPurchasesRef.doc(purchase.id);
    final purchaseDoc = await purchaseRef.get();
    if (!purchaseDoc.exists) {
      throw StateError('No se encontro la compra a proveedor.');
    }
    final currentPurchase = SupplierPurchase.fromDoc(purchaseDoc);
    if (currentPurchase.isCancelled) {
      throw StateError('No puedes cambiar fechas de una compra cancelada.');
    }
    final employee = AppSession.instance.employee;
    final logRef = _restaurantRef.collection('activityLog').doc();
    final batch = _db.batch();
    batch.set(purchaseRef, {
      'purchaseDate': Timestamp.fromDate(purchaseDate),
      'dueDate': Timestamp.fromDate(dueDate),
      'backofficeDatesUpdatedAt': FieldValue.serverTimestamp(),
      'backofficeDatesUpdatedByEmployeeId': employee?.id ?? '',
      'backofficeDatesUpdatedByEmployeeName': employee?.name ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(logRef, {
      'id': logRef.id,
      ..._currentBranchFields,
      'type': 'supplier_purchase_backoffice_dates_updated',
      'actionType': 'supplier_purchase_backoffice_dates_updated',
      'message':
          'Se cambiaron fechas de la compra ${currentPurchase.folio} '
          'del proveedor ${currentPurchase.supplierName} desde Backoffice',
      'supplierId': currentPurchase.supplierId,
      'supplierName': currentPurchase.supplierName,
      'purchaseId': currentPurchase.id,
      'purchaseFolio': currentPurchase.folio,
      'previousPurchaseDate': Timestamp.fromDate(currentPurchase.purchaseDate),
      'newPurchaseDate': Timestamp.fromDate(purchaseDate),
      'previousDueDate': currentPurchase.dueDate == null
          ? null
          : Timestamp.fromDate(currentPurchase.dueDate!),
      'newDueDate': Timestamp.fromDate(dueDate),
      'previousStatus': currentPurchase.status,
      'previousTotal': currentPurchase.total,
      'previousPaidTotal': currentPurchase.paidTotal,
      'previousBalance': currentPurchase.balance,
      'employeeId': employee?.id ?? '',
      'employeeName': employee?.name ?? '',
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
    });
    await batch.commit();
    invalidateReportDataCache(branchId: currentPurchase.branchId);
  }

  Future<void> registerSupplierPayment({
    required SupplierPurchase purchase,
    required double amount,
    required String fundingSource,
    DateTime? paymentDate,
    String reference = '',
    String notes = '',
  }) async {
    _requirePurchaseAccess(pay: true);
    if (purchase.isCancelled) {
      throw StateError('No puedes pagar una compra cancelada.');
    }
    final purchaseRef = _supplierPurchasesRef.doc(purchase.id);
    final purchaseDoc = await purchaseRef.get();
    if (!purchaseDoc.exists) {
      throw StateError('No se encontro la compra a proveedor.');
    }
    final currentPurchase = SupplierPurchase.fromDoc(purchaseDoc);
    if (currentPurchase.isCancelled) {
      throw StateError('No puedes pagar una compra cancelada.');
    }
    if (amount <= 0) {
      throw ArgumentError('Captura un monto de pago valido.');
    }
    if (amount > currentPurchase.balance + 0.01) {
      throw ArgumentError('No puedes pagar mas del saldo pendiente.');
    }
    final method = _normalizeSupplierPaymentMethod(fundingSource);
    if (!_supplierPaymentMethodLabels.containsKey(method)) {
      throw ArgumentError('Selecciona la forma de pago.');
    }

    final employee = AppSession.instance.employee;
    final paymentRef = _supplierPaymentsRef.doc();
    final nextPaidTotal = currentPurchase.paidTotal + amount;
    final nextBalance = (currentPurchase.total - nextPaidTotal).clamp(
      0,
      double.infinity,
    );
    final nextStatus = nextBalance <= 0.01 ? 'paid' : 'partial';
    final batch = _db.batch();
    batch.set(paymentRef, {
      'id': paymentRef.id,
      ..._currentBranchFields,
      'supplierId': currentPurchase.supplierId,
      'supplierName': currentPurchase.supplierName,
      'purchaseId': currentPurchase.id,
      'purchaseFolio': currentPurchase.folio,
      'paymentDate': Timestamp.fromDate(paymentDate ?? DateTime.now()),
      'amount': amount,
      'method': method,
      'methodName': _supplierPaymentMethodLabels[method],
      'paymentMethod': method,
      'paymentMethodName': _supplierPaymentMethodLabels[method],
      'fundingSource': fundingSource,
      'fundingSourceName': _supplierPaymentMethodLabels[method],
      'partnerId': null,
      'partnerName': null,
      'reference': reference.trim(),
      'notes': notes.trim(),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'createdByEmployeeId': employee?.id ?? '',
      'createdByEmployeeName': employee?.name ?? '',
    });
    batch.update(purchaseRef, {
      'paidTotal': nextPaidTotal,
      'balance': nextBalance,
      'status': nextStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> cancelSupplierPurchase({
    required SupplierPurchase purchase,
    required String reason,
  }) async {
    _requireCancelSupplierPurchaseAccess();
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Captura el motivo de cancelacion.');
    }

    final purchaseRef = _supplierPurchasesRef.doc(purchase.id);
    final purchaseDoc = await purchaseRef.get();
    if (!purchaseDoc.exists) {
      throw StateError('No se encontro la compra a proveedor.');
    }
    final currentPurchase = SupplierPurchase.fromDoc(purchaseDoc);
    if (currentPurchase.isCancelled) {
      throw StateError('Esta compra ya fue cancelada.');
    }

    final paymentsSnapshot = await _supplierPaymentsRef
        .where('purchaseId', isEqualTo: currentPurchase.id)
        .get();
    final activePayments = paymentsSnapshot.docs
        .map(SupplierPayment.fromDoc)
        .where((payment) => payment.isActive)
        .toList();
    if (activePayments.isNotEmpty) {
      throw StateError(
        'No puedes cancelar esta compra porque ya tiene pagos aplicados. '
        'Cancela primero los pagos del proveedor y despues cancela la compra.',
      );
    }

    final employee = AppSession.instance.employee;
    final logRef = _restaurantRef.collection('activityLog').doc();
    final batch = _db.batch();
    batch.set(purchaseRef, {
      'status': 'cancelled',
      'balance': 0.0,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledByEmployeeId': employee?.id ?? '',
      'cancelledByEmployeeName': employee?.name ?? '',
      'cancelReason': cleanReason,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(logRef, {
      'id': logRef.id,
      ..._currentBranchFields,
      'type': 'supplier_purchase_cancelled',
      'actionType': 'supplier_purchase_cancelled',
      'message':
          'Se cancelo la compra a proveedor ${currentPurchase.supplierName} '
          'folio ${currentPurchase.folio} por '
          '\$${currentPurchase.total.toStringAsFixed(2)}',
      'supplierId': currentPurchase.supplierId,
      'supplierName': currentPurchase.supplierName,
      'purchaseId': currentPurchase.id,
      'purchaseFolio': currentPurchase.folio,
      'amount': currentPurchase.total,
      'cancelReason': cleanReason,
      'employeeId': employee?.id ?? '',
      'employeeName': employee?.name ?? '',
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
    });
    await batch.commit();
  }

  Future<void> cancelSupplierPayment({
    required SupplierPayment payment,
    required String reason,
  }) async {
    _requireCancelSupplierPaymentAccess();
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Captura el motivo de cancelacion.');
    }
    final paymentRef = _supplierPaymentsRef.doc(payment.id);
    final paymentDoc = await paymentRef.get();
    if (!paymentDoc.exists) {
      throw StateError('No se encontro el pago a proveedor.');
    }
    final currentPayment = SupplierPayment.fromDoc(paymentDoc);
    if (currentPayment.isCancelled) {
      throw StateError('Este pago ya fue cancelado.');
    }
    final purchaseRef = _supplierPurchasesRef.doc(currentPayment.purchaseId);
    final purchaseDoc = await purchaseRef.get();
    if (!purchaseDoc.exists) {
      throw StateError('No se encontro la compra relacionada.');
    }
    final purchase = SupplierPurchase.fromDoc(purchaseDoc);
    final employee = AppSession.instance.employee;
    final activePaymentsSnapshot = await _supplierPaymentsRef
        .where('purchaseId', isEqualTo: currentPayment.purchaseId)
        .get();
    final activePaidTotal = activePaymentsSnapshot.docs
        .map(SupplierPayment.fromDoc)
        .where((item) => item.id != currentPayment.id && item.isActive)
        .fold<double>(0, (runningTotal, item) => runningTotal + item.amount);
    final nextBalance = (purchase.total - activePaidTotal).clamp(
      0,
      double.infinity,
    );
    final nextStatus = purchase.status == 'cancelled'
        ? 'cancelled'
        : activePaidTotal <= 0.01
        ? 'pending'
        : nextBalance <= 0.01
        ? 'paid'
        : 'partial';
    final batch = _db.batch();
    batch.set(paymentRef, {
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledByEmployeeId': employee?.id ?? '',
      'cancelledByEmployeeName': employee?.name ?? '',
      'cancelReason': cleanReason,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(purchaseRef, {
      'paidTotal': activePaidTotal,
      'balance': nextBalance,
      'status': nextStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  List<SupplierStatementRow> buildSupplierStatement({
    required String supplierId,
    required Iterable<SupplierPurchase> purchases,
    required Iterable<SupplierPayment> payments,
  }) {
    final events = <SupplierStatementRow>[];
    for (final purchase in purchases.where(
      (purchase) => purchase.supplierId == supplierId,
    )) {
      if (purchase.isCancelled) {
        final cancelReason = purchase.cancelReason?.trim() ?? '';
        final cancelledBy = purchase.cancelledByEmployeeName?.trim() ?? '';
        events.add(
          SupplierStatementRow(
            date:
                purchase.cancelledAt ??
                purchase.updatedAt ??
                purchase.purchaseDate,
            type: 'Compra cancelada',
            folio: purchase.folio,
            charge: 0,
            credit: 0,
            balance: 0,
            method: '',
            notes:
                'Monto original: \$${purchase.total.toStringAsFixed(2)}. '
                'Motivo: ${cancelReason.isEmpty ? '-' : cancelReason}. '
                'Cancelo: ${cancelledBy.isEmpty ? '-' : cancelledBy}.',
            dueDate: purchase.dueDate,
            supplierName: purchase.supplierName,
            purchaseId: purchase.id,
            status: 'cancelled',
            cancelReason: purchase.cancelReason,
            cancelledByEmployeeName: purchase.cancelledByEmployeeName,
            cancelledAt: purchase.cancelledAt,
          ),
        );
      } else {
        events.add(
          SupplierStatementRow(
            date: purchase.purchaseDate,
            type: 'Compra',
            folio: purchase.folio,
            charge: purchase.total,
            credit: 0,
            balance: 0,
            method: '',
            notes: purchase.notes,
            dueDate: purchase.dueDate,
            supplierName: purchase.supplierName,
            purchaseId: purchase.id,
            status: purchase.status,
          ),
        );
      }
    }
    for (final payment in payments.where(
      (payment) => payment.supplierId == supplierId,
    )) {
      final isCancelled = payment.isCancelled;
      events.add(
        SupplierStatementRow(
          date: isCancelled
              ? payment.cancelledAt ?? payment.paymentDate
              : payment.paymentDate,
          type: isCancelled ? 'Pago cancelado' : 'Pago proveedor',
          folio: payment.purchaseFolio,
          charge: 0,
          credit: isCancelled ? 0 : payment.amount,
          balance: 0,
          method: payment.method,
          notes: isCancelled
              ? 'Pago cancelado. Monto original: \$${payment.amount.toStringAsFixed(2)}. '
                    'Motivo: ${payment.cancelReason ?? ''}. '
                    'Cancelado por: ${payment.cancelledByEmployeeName ?? ''}.'
              : payment.notes,
          supplierName: payment.supplierName,
          purchaseId: payment.purchaseId,
          paymentId: payment.id,
          fundingSourceName:
              _supplierPaymentMethodLabels[payment.method] ??
              payment.fundingSourceName,
          partnerName: payment.partnerName,
          reference: payment.reference,
          status: payment.status,
          cancelReason: payment.cancelReason,
          cancelledByEmployeeName: payment.cancelledByEmployeeName,
          cancelledAt: payment.cancelledAt,
        ),
      );
    }
    events.sort((a, b) => a.date.compareTo(b.date));
    var balance = 0.0;
    return events.map((event) {
      balance += event.charge - event.credit;
      return SupplierStatementRow(
        date: event.date,
        type: event.type,
        folio: event.folio,
        charge: event.charge,
        credit: event.credit,
        balance: balance,
        method: event.method,
        notes: event.notes,
        dueDate: event.dueDate,
        supplierName: event.supplierName,
        purchaseId: event.purchaseId,
        paymentId: event.paymentId,
        fundingSourceName: event.fundingSourceName,
        partnerName: event.partnerName,
        reference: event.reference,
        status: event.status,
        cancelReason: event.cancelReason,
        cancelledByEmployeeName: event.cancelledByEmployeeName,
        cancelledAt: event.cancelledAt,
      );
    }).toList();
  }

  List<PurchaseSupplierReportRow> buildPurchasesBySupplierReport({
    required Iterable<Supplier> suppliers,
    required Iterable<SupplierPurchase> purchases,
    required Iterable<SupplierPayment> payments,
  }) {
    final supplierById = {
      for (final supplier in suppliers) supplier.id: supplier,
    };
    final ids = <String>{
      ...purchases.map((purchase) => purchase.supplierId),
      ...payments.map((payment) => payment.supplierId),
    };
    final rows = <PurchaseSupplierReportRow>[];
    for (final supplierId in ids) {
      final supplier = supplierById[supplierId];
      final supplierPurchases = purchases.where(
        (purchase) =>
            purchase.supplierId == supplierId && purchase.status != 'cancelled',
      );
      final supplierPayments = payments.where(
        (payment) =>
            payment.supplierId == supplierId && payment.status == 'active',
      );
      final purchaseList = supplierPurchases.toList();
      final paymentList = supplierPayments.toList();
      final totalPurchased = supplierPurchases.fold<double>(
        0,
        (runningTotal, purchase) => runningTotal + purchase.total,
      );
      final totalPaid = supplierPayments.fold<double>(
        0,
        (runningTotal, payment) => runningTotal + payment.amount,
      );
      rows.add(
        PurchaseSupplierReportRow(
          supplierId: supplierId,
          supplierName:
              supplier?.commercialName ??
              (purchaseList.isEmpty ? null : purchaseList.first.supplierName) ??
              (paymentList.isEmpty ? null : paymentList.first.supplierName) ??
              'Proveedor',
          totalPurchased: totalPurchased,
          totalPaid: totalPaid,
          balance: (totalPurchased - totalPaid).clamp(0, double.infinity),
          noteCount: supplierPurchases.length,
          paymentWeekdayName: supplier?.paymentWeekdayName ?? 'Sin dia fijo',
          purchases: purchaseList,
        ),
      );
    }
    rows.sort((a, b) => b.balance.compareTo(a.balance));
    return rows;
  }

  List<PurchaseItemReportRow> buildPurchasesByItemReport({
    required Iterable<SupplierPurchaseItem> items,
  }) {
    final totals = <String, _PurchaseItemReportAccumulator>{};
    for (final item in items) {
      final itemId =
          item.kitchenStockItemId ??
          item.purchaseItemId ??
          item.purchaseItemName.trim().toLowerCase();
      final itemName = item.kitchenStockItemName ?? item.purchaseItemName;
      final key = itemId.trim().isEmpty
          ? item.purchaseItemName.trim().toLowerCase()
          : itemId.trim();
      final current = totals.putIfAbsent(
        key,
        () => _PurchaseItemReportAccumulator(
          itemId: key,
          itemName: itemName.trim().isEmpty ? 'Insumo' : itemName.trim(),
          unit: item.unit,
          affectsKitchenPerformance: item.affectsKitchenStock,
        ),
      );
      current.quantity += item.quantity;
      current.totalCents += item.lineTotalCents;
      current.noteCount++;
      current.affectsKitchenPerformance =
          current.affectsKitchenPerformance || item.affectsKitchenStock;
    }
    final rows =
        totals.values
            .map(
              (item) => PurchaseItemReportRow(
                itemId: item.itemId,
                itemName: item.itemName,
                quantity: item.quantity,
                unit: item.unit,
                total: item.total,
                averageUnitCostCalculated: item.averageUnitCostCalculated,
                noteCount: item.noteCount,
                affectsKitchenPerformance: item.affectsKitchenPerformance,
              ),
            )
            .toList()
          ..sort((a, b) => b.total.compareTo(a.total));
    return rows;
  }

  Stream<List<ActiveSession>> watchActiveSessions() {
    return _activeSessionsRef
        .orderBy('lastSeenAt', descending: true)
        .limit(60)
        .snapshots()
        .map((snapshot) {
          final latestByUser = <String, ActiveSession>{};
          for (final session in snapshot.docs.map(ActiveSession.fromDoc)) {
            if (!session.isVisibleInLiveViewer ||
                !_matchesCurrentBranch(session.branchId)) {
              continue;
            }
            final key = _activeSessionGroupKey(session);
            final current = latestByUser[key];
            if (current == null || _sessionIsNewer(session, current)) {
              latestByUser[key] = session;
            }
          }
          return latestByUser.values.toList()..sort((a, b) {
            final aSeen = a.lastSeenAt ?? a.updatedAt ?? DateTime(1970);
            final bSeen = b.lastSeenAt ?? b.updatedAt ?? DateTime(1970);
            return bSeen.compareTo(aSeen);
          });
        });
  }

  Future<int> cleanupInactiveActiveSessions() async {
    _requireAdminPermission(
      AppSession.instance.employee?.canViewAdmin == true ||
          AppSession.instance.employee?.canControlLiveOperations == true,
      'No tienes permiso para limpiar sesiones operativas.',
    );
    final snapshot = await _activeSessionsRef.limit(200).get();
    final cutoff = DateTime.now().subtract(const Duration(seconds: 180));
    final latestByUser = <String, ActiveSession>{};
    final sessions = snapshot.docs.map(ActiveSession.fromDoc).toList();
    for (final session in sessions.where(
      (session) => !session.isBackofficeSession,
    )) {
      final key = _activeSessionGroupKey(session);
      final current = latestByUser[key];
      if (current == null || _sessionIsNewer(session, current)) {
        latestByUser[key] = session;
      }
    }

    final batch = _db.batch();
    var count = 0;
    for (final session in sessions) {
      final seen = session.lastSeenAt ?? session.updatedAt;
      final key = _activeSessionGroupKey(session);
      final isDuplicate = latestByUser[key]?.id != session.id;
      final isOld = seen == null || seen.isBefore(cutoff);
      final shouldArchive =
          session.isBackofficeSession ||
          isDuplicate ||
          isOld ||
          !session.isOnline;
      if (session.archived || !shouldArchive) {
        continue;
      }
      batch.set(_activeSessionsRef.doc(session.id), {
        'archived': true,
        'isOnline': false,
        'currentOrderId': null,
        'currentTableId': null,
        'currentTableName': null,
        'currentTakeoutOrderId': null,
        'currentKitchenBundleId': null,
        'currentPersonNumber': null,
        'archivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      count++;
    }
    if (count > 0) {
      await batch.commit();
    }
    return count;
  }

  Stream<List<ActivityEvent>> watchRecentActivityEvents({int limit = 50}) {
    return _restaurantRef
        .collection('activityLog')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(ActivityEvent.fromDoc)
              .where((event) => _matchesCurrentBranch(event.branchId))
              .toList(),
        );
  }

  Future<void> logBackofficeIntervention({
    required String type,
    String? orderId,
    String? targetId,
    String? note,
  }) async {
    final employee = AppSession.instance.employee;
    await _restaurantRef.collection('activityLog').add({
      'type': type,
      ..._currentBranchFields,
      'orderId': orderId,
      'targetId': targetId,
      'note': note,
      'adminEmployeeId': employee?.id,
      'adminEmployeeName': employee?.name,
      'employeeId': employee?.id,
      'employeeName': employee?.name,
      'actionSource': 'backoffice_live_viewer',
      'createdAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> ensureInitialAdminEmployee() async {
    final adminRef = _employeesRef.doc('admin');
    final doc = await adminRef.get();
    if (doc.exists) {
      final data = doc.data() ?? {};
      if (data['pin'] != operationResetPin ||
          data['canManageCash'] != true ||
          data['canAuthorizeCashWithdrawals'] != true ||
          data['canOpenKitchen'] != true ||
          data['canCloseKitchen'] != true ||
          data['canViewKitchenReports'] != true ||
          data['canManageKitchenStock'] != true ||
          data['canCancelOrders'] != true ||
          data['canCancelPayments'] != true ||
          data['canCancelItems'] != true ||
          data['canApproveKitchenCancellations'] != true ||
          data['canViewLiveOperations'] != true ||
          data['canControlLiveOperations'] != true) {
        await adminRef.set({
          'pin': operationResetPin,
          'canManageCash': true,
          'canAuthorizeCashWithdrawals': true,
          'canOpenKitchen': true,
          'canCloseKitchen': true,
          'canViewKitchenReports': true,
          'canManageKitchenStock': true,
          'canCancelOrders': true,
          'canCancelPayments': true,
          'canCancelItems': true,
          'canApproveKitchenCancellations': true,
          'canViewLiveOperations': true,
          'canControlLiveOperations': true,
          'isSuperAdmin': true,
          'defaultRestaurantId': AppConstants.restaurantId,
          'defaultBranchId': AppConstants.defaultBranchId,
          'restaurantAccess': [AppConstants.restaurantId],
          'branchAccess': [
            {
              'restaurantId': AppConstants.restaurantId,
              'branchId': AppConstants.defaultBranchId,
              'branchName': AppConstants.defaultBranchName,
              'active': true,
              'permissions': {
                'canTakeOrders': true,
                'canCharge': true,
                'canViewKitchen': true,
                'canViewAdmin': true,
                'canManageProducts': true,
                'canManageTables': true,
                'canManagePlatforms': true,
                'canManageEmployees': true,
                'canManageCash': true,
                'canAuthorizeCashWithdrawals': true,
                'canOpenKitchen': true,
                'canCloseKitchen': true,
                'canViewKitchenReports': true,
                'canManageKitchenStock': true,
                'canCancelOrders': true,
                'canCancelPayments': true,
                'canCancelItems': true,
                'canApproveKitchenCancellations': true,
                'canViewLiveOperations': true,
                'canControlLiveOperations': true,
              },
            },
          ],
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      return;
    }

    final adminByName = await _employeesRef
        .where('name', isEqualTo: 'Admin')
        .limit(1)
        .get();
    if (adminByName.docs.isNotEmpty) {
      await adminByName.docs.first.reference.set({
        'pin': operationResetPin,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    await adminRef.set({
      'id': 'admin',
      'name': 'Admin',
      // TODO: Replace plain PIN storage with a salted hash before production.
      'pin': operationResetPin,
      'active': true,
      'canTakeOrders': true,
      'canCharge': true,
      'canViewKitchen': true,
      'canViewAdmin': true,
      'canManageProducts': true,
      'canManageTables': true,
      'canManagePlatforms': true,
      'canManageEmployees': true,
      'canManageCash': true,
      'canAuthorizeCashWithdrawals': true,
      'canOpenKitchen': true,
      'canCloseKitchen': true,
      'canViewKitchenReports': true,
      'canManageKitchenStock': true,
      'canCancelOrders': true,
      'canCancelPayments': true,
      'canCancelItems': true,
      'canApproveKitchenCancellations': true,
      'canViewLiveOperations': true,
      'canControlLiveOperations': true,
      'isSuperAdmin': true,
      'defaultRestaurantId': AppConstants.restaurantId,
      'defaultBranchId': AppConstants.defaultBranchId,
      'restaurantAccess': [AppConstants.restaurantId],
      'branchAccess': [
        {
          'restaurantId': AppConstants.restaurantId,
          'branchId': AppConstants.defaultBranchId,
          'branchName': AppConstants.defaultBranchName,
          'active': true,
          'permissions': {
            'canTakeOrders': true,
            'canCharge': true,
            'canViewKitchen': true,
            'canViewAdmin': true,
            'canManageProducts': true,
            'canManageTables': true,
            'canManagePlatforms': true,
            'canManageEmployees': true,
            'canManageCash': true,
            'canAuthorizeCashWithdrawals': true,
            'canOpenKitchen': true,
            'canCloseKitchen': true,
            'canViewKitchenReports': true,
            'canManageKitchenStock': true,
            'canCancelOrders': true,
            'canCancelPayments': true,
            'canCancelItems': true,
            'canApproveKitchenCancellations': true,
            'canViewLiveOperations': true,
            'canControlLiveOperations': true,
          },
        },
      ],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> validateEmployeePin({
    required String employeeId,
    required String pin,
  }) async {
    final doc = await _employeesRef.doc(employeeId).get();
    if (!doc.exists) {
      return false;
    }

    final employee = Employee.fromDoc(doc);
    return employee.active && employee.pin == pin;
  }

  Future<void> resetOperationalDataForBranch(String branchId) async {
    _requireAdminPermission(
      _canManageBranches(),
      'No tienes permiso para reiniciar la operacion.',
    );
    final cleanBranchId = branchId.trim();
    if (cleanBranchId.isEmpty) {
      throw ArgumentError('Selecciona una sucursal.');
    }

    var batch = _db.batch();
    var batchWrites = 0;

    Future<void> commitIfNeeded({bool force = false}) async {
      if (batchWrites == 0 || (!force && batchWrites < 430)) {
        return;
      }
      await batch.commit();
      batch = _db.batch();
      batchWrites = 0;
    }

    Future<void> deleteDoc(
      DocumentReference<Map<String, dynamic>> docRef,
    ) async {
      batch.delete(docRef);
      batchWrites++;
      await commitIfNeeded();
    }

    Future<void> deleteOperationalDocWithSubcollections(
      DocumentSnapshot<Map<String, dynamic>> doc,
      List<String> subcollections,
    ) async {
      for (final subcollection in subcollections) {
        final subSnapshot = await doc.reference.collection(subcollection).get();
        for (final subDoc in subSnapshot.docs) {
          await deleteDoc(subDoc.reference);
        }
      }
      await deleteDoc(doc.reference);
    }

    Future<void> deleteMatchingCollection(String collectionName) async {
      if (_operationResetProtectedCollections.contains(collectionName)) {
        throw StateError(
          'La coleccion $collectionName no forma parte del reinicio operativo.',
        );
      }
      final collection = _restaurantRef.collection(collectionName);
      final snapshot = await collection.get();
      for (final doc in snapshot.docs) {
        if (_belongsToResetBranch(doc.data(), cleanBranchId)) {
          await deleteDoc(doc.reference);
        }
      }
    }

    final ordersSnapshot = await _ordersRef.get();
    for (final orderDoc in ordersSnapshot.docs) {
      if (_belongsToResetBranch(orderDoc.data(), cleanBranchId)) {
        await deleteOperationalDocWithSubcollections(orderDoc, [
          'items',
          'payments',
        ]);
      }
    }

    final kitchenSessionsSnapshot = await _kitchenSessionsRef.get();
    for (final sessionDoc in kitchenSessionsSnapshot.docs) {
      if (_belongsToResetBranch(sessionDoc.data(), cleanBranchId)) {
        await deleteOperationalDocWithSubcollections(sessionDoc, [
          'items',
          'additionalEntries',
          'entries',
        ]);
      }
    }

    for (final collectionName in _operationResetCollections) {
      await deleteMatchingCollection(collectionName);
    }

    final tablesSnapshot = await _tablesRef.get();
    for (final tableDoc in tablesSnapshot.docs) {
      if (!_belongsToResetBranch(tableDoc.data(), cleanBranchId)) {
        continue;
      }
      batch.set(tableDoc.reference, {
        'status': 'available',
        'currentOrderId': null,
        'currentOrderStatus': null,
        'occupiedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batchWrites++;
      await commitIfNeeded();
    }

    await commitIfNeeded(force: true);
  }

  bool _belongsToResetBranch(Map<String, dynamic> data, String branchId) {
    final docBranchId = data['branchId']?.toString().trim();
    if (docBranchId != null && docBranchId.isNotEmpty) {
      return docBranchId == branchId;
    }
    return branchId == AppConstants.defaultBranchId;
  }

  static const Set<String> _operationResetCollections = {
    'payments',
    'cashSessions',
    'cashWithdrawalRequests',
    'activeSessions',
    'activityLog',
    'interventions',
  };

  static const Set<String> _operationResetProtectedCollections = {
    'suppliers',
    'supplierPurchases',
    'supplierPayments',
    'partnerContributions',
    'partners',
    'purchaseItems',
    'kitchenStockItems',
    'products',
    'productCategories',
    'employees',
    'tables',
    'branches',
    'orderPlatforms',
    'settings',
    'config',
  };

  Stream<List<PosOrder>> watchOpenOrders() {
    return _ordersRef.snapshots().map((snapshot) {
      final orders =
          _filterCurrentBranch(
            snapshot.docs.map(PosOrder.fromDoc).where(isActiveOrder),
            (order) => order.branchId,
          )..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
      return orders;
    });
  }

  Stream<List<PosOrder>> watchOpenTakeoutOrders() {
    return _ordersRef.snapshots().map((snapshot) {
      final orders =
          _filterCurrentBranch(
            snapshot.docs
                .map(PosOrder.fromDoc)
                .where(
                  (order) =>
                      order.orderType == 'takeout' && isActiveOrder(order),
                ),
            (order) => order.branchId,
          )..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
      return orders;
    });
  }

  Stream<List<PosOrder>> watchOpenStandingOrders() {
    return _ordersRef.snapshots().map((snapshot) {
      final orders =
          _filterCurrentBranch(
            snapshot.docs
                .map(PosOrder.fromDoc)
                .where(
                  (order) =>
                      order.orderType == standingOrderType &&
                      isActiveOrder(order),
                ),
            (order) => order.branchId,
          )..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
      return orders;
    });
  }

  Stream<List<LiveStandingOrderBundle>>
  watchOperationalStandingOrderBundles() async* {
    final businessDate = await currentKitchenBusinessDate();
    final selectedBranchId = AppSession.instance.currentBranchId;
    await for (final orders in _watchOrdersForOperationalDate(businessDate)) {
      final candidates = orders.where((order) {
        return isStandingOrder(order) &&
            _matchesBranch(order.branchId, selectedBranchId) &&
            _businessDateForOrder(order) == businessDate;
      }).toList();
      final bundles = <LiveStandingOrderBundle>[];
      for (final order in candidates) {
        final items = await getOrderItemsOnce(order.id);
        final payments = await getOrderPaymentsOnce(order.id);
        if (!isStandingOrderVisibleInLiveViewer(
          order: order,
          items: items,
          payments: payments,
          belongsToSelectedBranchAndDate: true,
        )) {
          continue;
        }
        bundles.add(
          LiveStandingOrderBundle(
            order: order,
            items: items,
            payments: payments,
          ),
        );
      }
      bundles.sort((a, b) {
        final aDate =
            a.order.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            b.order.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      yield bundles;
    }
  }

  Stream<OperationalOpenOrdersSummary>
  watchOperationalOpenOrdersSummary() async* {
    final branchId = AppSession.instance.currentBranchId;
    final cashSession = await getOpenCashSession();
    final businessDate =
        cashSession?.businessDate ?? await currentKitchenBusinessDate();
    await reconcileGhostOrdersAndTableLinks(
      branchId: branchId,
      businessDate: businessDate,
      triggeredBy: 'live_operations_viewer',
    );
    await for (final _ in _watchOrdersForOperationalDate(
      businessDate,
      cashSessionId: cashSession?.id,
    )) {
      yield await getOperationalOpenOrdersSummary(
        businessDate: businessDate,
        cashSessionId: cashSession?.id,
        forceRefresh: true,
      );
    }
  }

  Stream<List<PosOrder>> _watchOrdersForOperationalDate(
    String businessDate, {
    String? cashSessionId,
  }) {
    late StreamController<List<PosOrder>> controller;
    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    final documentsBySource =
        <String, Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>>{};

    void emit() {
      final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final documents in documentsBySource.values) {
        merged.addAll(documents);
      }
      controller.add(merged.values.map(PosOrder.fromDoc).toList());
    }

    void listenTo(String source, Query<Map<String, dynamic>> query) {
      subscriptions.add(
        query.snapshots().listen((snapshot) {
          documentsBySource[source] = {
            for (final document in snapshot.docs) document.id: document,
          };
          emit();
        }, onError: controller.addError),
      );
    }

    controller = StreamController<List<PosOrder>>(
      onListen: () {
        listenTo(
          'businessDate',
          _ordersRef.where('businessDate', isEqualTo: businessDate),
        );
        listenTo(
          'operationalDate',
          _ordersRef.where('operationalDate', isEqualTo: businessDate),
        );
        if (cashSessionId?.trim().isNotEmpty == true) {
          listenTo(
            'cashSessionId',
            _ordersRef.where('cashSessionId', isEqualTo: cashSessionId!.trim()),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  Stream<List<PosOrder>> watchAllOrders() {
    return _ordersRef.snapshots().map((snapshot) {
      final orders =
          _filterCurrentBranch(
            snapshot.docs.map(PosOrder.fromDoc),
            (order) => order.branchId,
          )..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
      return orders;
    });
  }

  Stream<List<KitchenOrderBundle>> watchKitchenOrderBundles() {
    return _ordersRef.snapshots().asyncMap((snapshot) async {
      final orders = _filterCurrentBranch(
        snapshot.docs.map(PosOrder.fromDoc).where(isActiveOrder),
        (order) => order.branchId,
      );

      final bundles = <KitchenOrderBundle>[];
      for (final order in orders) {
        final items = await getActiveKitchenItems(order.id);
        final itemsByBatch = <String, List<OrderItem>>{};
        for (final item in items) {
          final batchId = item.kitchenBatchId?.trim();
          final key = batchId == null || batchId.isEmpty
              ? 'order:${order.id}'
              : 'batch:$batchId';
          itemsByBatch.putIfAbsent(key, () => <OrderItem>[]).add(item);
        }
        for (final batchItems in itemsByBatch.values) {
          if (batchItems.isNotEmpty) {
            bundles.add(KitchenOrderBundle(order: order, items: batchItems));
          }
        }
      }

      bundles.sort((a, b) {
        final aDate =
            a.items
                .map((item) => item.sentToKitchenAt)
                .whereType<DateTime>()
                .fold<DateTime?>(
                  null,
                  (min, date) => min == null || date.isBefore(min) ? date : min,
                ) ??
            a.order.updatedAt ??
            a.order.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            b.items
                .map((item) => item.sentToKitchenAt)
                .whereType<DateTime>()
                .fold<DateTime?>(
                  null,
                  (min, date) => min == null || date.isBefore(min) ? date : min,
                ) ??
            b.order.updatedAt ??
            b.order.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return aDate.compareTo(bDate);
      });

      return bundles;
    });
  }

  Stream<PosOrder?> watchOrder(String orderId) {
    return _ordersRef.doc(orderId).snapshots().map((doc) {
      if (!doc.exists) {
        return null;
      }
      return PosOrder.fromDoc(doc);
    });
  }

  Future<PosOrder> getOrderOnce(String orderId) async {
    final doc = await _ordersRef.doc(orderId).get();
    if (!doc.exists) {
      throw StateError('La orden ya no existe.');
    }
    return PosOrder.fromDoc(doc);
  }

  Stream<List<OrderItem>> watchOrderItems(String orderId) {
    final cleanOrderId = orderId.trim();
    if (cleanOrderId.isEmpty) {
      return Stream.error(StateError('OrderId vacio al cargar articulos.'));
    }
    final path =
        'restaurants/${AppConstants.restaurantId}/orders/$cleanOrderId/items';
    developer.log(
      '[TacoPOS][itemsStream] watch path=$path orderId=$cleanOrderId',
    );

    return _ordersRef.doc(cleanOrderId).collection('items').snapshots().map((
      snapshot,
    ) {
      final items = _sortedOrderItems(snapshot.docs.map(OrderItem.fromDoc));
      final preview = items
          .take(5)
          .map((item) => '${item.id}:${item.productName}')
          .join(', ');
      developer.log(
        '[TacoPOS][itemsStream] orderId=$cleanOrderId path=$path '
        'itemCount=${items.length} firstItems=[$preview]',
      );
      return items;
    });
  }

  Future<List<OrderItem>> getOrderItemsOnce(String orderId) async {
    final cleanOrderId = orderId.trim();
    if (cleanOrderId.isEmpty) {
      throw StateError('OrderId vacio al cargar articulos.');
    }
    final snapshot = await _ordersRef
        .doc(cleanOrderId)
        .collection('items')
        .get();
    return _sortedOrderItems(snapshot.docs.map(OrderItem.fromDoc));
  }

  List<OrderItem> _sortedOrderItems(Iterable<OrderItem> source) {
    return source.toList()..sort((a, b) {
      final aDate =
          a.createdAt ?? a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          b.createdAt ?? b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dateCompare = aDate.compareTo(bDate);
      if (dateCompare != 0) {
        return dateCompare;
      }
      final personCompare = a.personNumber.compareTo(b.personNumber);
      if (personCompare != 0) {
        return personCompare;
      }
      return a.productName.compareTo(b.productName);
    });
  }

  Stream<List<OrderItem>> watchKitchenItems(
    String orderId, {
    String? kitchenBatchId,
  }) {
    return watchOrderItems(orderId).map(
      (items) => _activeKitchenItems(items, kitchenBatchId: kitchenBatchId),
    );
  }

  Future<List<OrderItem>> getActiveKitchenItems(
    String orderId, {
    String? kitchenBatchId,
  }) async {
    final snapshot = await _ordersRef.doc(orderId).collection('items').get();
    return _activeKitchenItems(
      snapshot.docs.map(OrderItem.fromDoc).toList(),
      kitchenBatchId: kitchenBatchId,
    );
  }

  List<OrderItem> _activeKitchenItems(
    List<OrderItem> items, {
    String? kitchenBatchId,
  }) {
    final cleanBatchId = kitchenBatchId?.trim();
    return items.where((item) {
      if (!isKitchenPendingItem(item)) return false;
      if (cleanBatchId == null || cleanBatchId.isEmpty) return true;
      return item.kitchenBatchId?.trim() == cleanBatchId;
    }).toList()..sort((a, b) {
      final personCompare = a.personNumber.compareTo(b.personNumber);
      return personCompare != 0
          ? personCompare
          : a.productName.compareTo(b.productName);
    });
  }

  Stream<List<Payment>> watchPayments({
    String? startBusinessDate,
    String? endBusinessDate,
  }) {
    Query<Map<String, dynamic>> query = _db.collectionGroup('payments');
    if (startBusinessDate != null) {
      query = query.where(
        'businessDate',
        isGreaterThanOrEqualTo: startBusinessDate,
      );
    }
    if (endBusinessDate != null) {
      query = query.where('businessDate', isLessThanOrEqualTo: endBusinessDate);
    }

    return query.snapshots().map((snapshot) {
      final payments =
          _filterCurrentBranch(
            snapshot.docs.map(Payment.fromDoc),
            (payment) => payment.branchId,
          )..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
      return payments;
    });
  }

  Stream<List<Payment>> watchDashboardPayments({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return Stream.fromFuture(
      getReportDataBundle(
        startBusinessDate: _businessDateFor(startDate),
        endBusinessDate: _businessDateFor(endDate),
        includeItems: false,
        reportName: 'DashboardPayments',
      ).then((bundle) => bundle.payments),
    );
  }

  Stream<List<Payment>> watchOrderPayments(String orderId) {
    return _ordersRef.doc(orderId).collection('payments').snapshots().map((
      snapshot,
    ) {
      final payments =
          snapshot.docs
              .map((doc) => Payment.fromDoc(doc).copyWith(orderId: orderId))
              .toList()
            ..sort((a, b) {
              final aDate =
                  a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bDate =
                  b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });
      return payments;
    });
  }

  Future<List<Payment>> getOrderPaymentsOnce(String orderId) async {
    final snapshot = await _ordersRef.doc(orderId).collection('payments').get();
    final payments =
        snapshot.docs
            .map((doc) => Payment.fromDoc(doc).copyWith(orderId: orderId))
            .toList()
          ..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
    return payments;
  }

  Future<List<Payment>> getPaymentsForBranchBusinessDate({
    required Branch branch,
    required String businessDate,
    bool activeOnly = true,
  }) async {
    final session = await _cashSessionForBranchAndDate(
      branch: branch,
      businessDate: businessDate,
    );
    return _paymentsForBranchAndBusinessDate(
      branch: branch,
      businessDate: businessDate,
      selectedCashSessionId: session?.id ?? '',
      selectedCashSession: session,
      activeOnly: activeOnly,
    );
  }

  Future<CashDifferenceAuditReport> getCashDifferenceAudit(
    CashSession session,
  ) async {
    final ordersSnapshot = await _ordersRef.get();
    final paymentsSnapshot = await _db.collectionGroup('payments').get();
    final cashSessionsSnapshot = await _cashSessionsRef.get();
    final withdrawalsSnapshot = await _cashWithdrawalRequestsRef.get();
    final partnerContributionsSnapshot = await _partnerContributionsRef.get();
    final orders = ordersSnapshot.docs.map(PosOrder.fromDoc).toList();
    final paymentInputs = paymentsSnapshot.docs.map((doc) {
      final parentOrderId = doc.reference.parent.parent?.id ?? '';
      final payment = Payment.fromDoc(doc);
      final resolvedOrderId = payment.orderId.trim().isEmpty
          ? parentOrderId
          : payment.orderId;
      return CashAuditPaymentInput(
        payment: payment.copyWith(orderId: resolvedOrderId),
        orderId: resolvedOrderId,
        tipAmount: _cashAuditTipAmount(doc.data()),
      );
    }).toList();
    final previousSessions =
        cashSessionsSnapshot.docs
            .map(CashSession.fromDoc)
            .where(
              (row) =>
                  row.branchId == session.branchId &&
                  row.businessDate.compareTo(session.businessDate) < 0,
            )
            .toList()
          ..sort((a, b) => b.businessDate.compareTo(a.businessDate));
    final previousSession = previousSessions.isEmpty
        ? null
        : previousSessions.first;
    final previousWithdrawals = withdrawalsSnapshot.docs
        .where((doc) {
          final data = doc.data();
          if (previousSession == null) return false;
          return data['cashSessionId'] == previousSession.id ||
              (data['branchId'] == session.branchId &&
                  data['businessDate'] == previousSession.businessDate);
        })
        .map(
          (doc) => _cashAuditMovementFromData(
            id: doc.id,
            type: 'Retiro corte anterior',
            data: doc.data(),
            includedInSession: true,
          ),
        )
        .toList();
    final nonSaleMovements = [
      ...partnerContributionsSnapshot.docs
          .where((doc) => _cashAuditMovementMatchesSession(doc.data(), session))
          .map(
            (doc) => _cashAuditMovementFromData(
              id: doc.id,
              type: 'Aportacion socio',
              data: doc.data(),
              includedInSession: doc.data()['cashSessionId'] == session.id,
            ),
          ),
      ...withdrawalsSnapshot.docs
          .where((doc) => _cashAuditMovementMatchesSession(doc.data(), session))
          .map(
            (doc) => _cashAuditMovementFromData(
              id: doc.id,
              type: 'Retiro / ajuste caja',
              data: doc.data(),
              includedInSession: doc.data()['cashSessionId'] == session.id,
            ),
          ),
    ];
    return buildCashDifferenceAuditReport(
      session: session,
      orders: orders,
      payments: paymentInputs,
      previousSession: previousSession,
      previousWithdrawals: previousWithdrawals,
      nonSaleMovements: nonSaleMovements,
    );
  }

  Future<Map<String, int>> saleFolioCountersForRange({
    required String startBusinessDate,
    required String endBusinessDate,
  }) async {
    try {
      final snapshot =
          await _dailySaleCountersRef(AppSession.instance.currentBranchId)
              .where('businessDate', isGreaterThanOrEqualTo: startBusinessDate)
              .where('businessDate', isLessThanOrEqualTo: endBusinessDate)
              .get();
      return {
        for (final doc in snapshot.docs)
          (doc.data()['businessDate'] as String? ?? doc.id):
              (doc.data()['lastSequence'] as num?)?.toInt() ?? 0,
      };
    } catch (error, stackTrace) {
      developer.log(
        'No se pudieron leer contadores de folio diario.',
        name: 'TacoPOS.saleFolio',
        error: error,
        stackTrace: stackTrace,
      );
      return const {};
    }
  }

  double _cashAuditTipAmount(Map<String, dynamic> data) {
    for (final key in const [
      'tipAmount',
      'tip',
      'tips',
      'propina',
      'gratuity',
      'employeeTip',
    ]) {
      final value = _numberToDouble(data[key]);
      if (value > 0) return value;
    }
    return 0;
  }

  bool _cashAuditMovementMatchesSession(
    Map<String, dynamic> data,
    CashSession session,
  ) {
    if (data['cashSessionId'] == session.id) return true;
    if (data['branchId'] != session.branchId) return false;
    final date = (data['businessDate'] ?? data['date'])?.toString();
    return date == session.businessDate;
  }

  CashAuditMovementRow _cashAuditMovementFromData({
    required String id,
    required String type,
    required Map<String, dynamic> data,
    required bool includedInSession,
  }) {
    final dateValue = data['businessDate'] ?? data['date'] ?? data['createdAt'];
    return CashAuditMovementRow(
      type: type,
      id: id,
      amount: _numberToDouble(data['amount']),
      method: (data['method'] ?? data['paymentMethod'] ?? 'cash').toString(),
      date: dateValue is Timestamp
          ? _businessDateFor(dateValue.toDate())
          : (dateValue ?? '').toString(),
      user:
          (data['requestedByEmployeeName'] ??
                  data['authorizedByEmployeeName'] ??
                  data['partnerName'] ??
                  data['employeeName'] ??
                  data['createdByEmployeeName'] ??
                  '')
              .toString(),
      status: (data['status'] ?? '').toString(),
      includedInSession: includedInSession,
      notes: (data['reason'] ?? data['notes'] ?? data['description'] ?? '')
          .toString(),
    );
  }

  void invalidateCanonicalSalesSummaryCache() {
    _reportDataRepository.clear();
  }

  void invalidateReportDataCache({
    String? branchId,
    String? startBusinessDate,
    String? endBusinessDate,
  }) {
    _reportDataRepository.invalidate(
      restaurantId: AppConstants.restaurantId,
      branchId: branchId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
    );
  }

  BackofficeReportDiagnostics reportDataDiagnostics() {
    return _reportDataRepository.diagnosticsSnapshot();
  }

  void invalidateFinanceDashboardCache({
    required String branchId,
    required String startBusinessDate,
    required String endBusinessDate,
  }) {
    _financeDashboardCache.invalidate(
      FinanceDashboardKey(
        restaurantId: AppSession.instance.currentRestaurantId,
        branchId: branchId,
        startBusinessDate: startBusinessDate,
        endBusinessDate: endBusinessDate,
      ),
    );
  }

  Future<FinanceDashboardBundle> getFinanceDashboardBundle({
    required String startBusinessDate,
    required String endBusinessDate,
    bool forceRefresh = false,
  }) async {
    final employee = AppSession.instance.employee;
    if (!kIsWeb || !canViewFinanceDashboard(employee)) {
      throw StateError('No tienes permiso para consultar finanzas.');
    }
    final session = AppSession.instance;
    final key = FinanceDashboardKey(
      restaurantId: session.currentRestaurantId,
      branchId: session.currentBranchId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
    );
    final stopwatch = Stopwatch()..start();
    final tracer = ReportPerformanceTracer(
      reportName: 'FINANCE_DASHBOARD_PERF',
      branchId: key.branchId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      cacheKey: key.value,
    );
    final result = await _financeDashboardCache.load(
      key: key,
      forceRefresh: forceRefresh,
      loader: () =>
          _loadFinanceDashboardBundle(key, forceRefresh: forceRefresh),
    );
    stopwatch.stop();
    final bundle = result.bundle.withLoadMetadata(
      fromCache: result.fromCache,
      loadMilliseconds: stopwatch.elapsedMilliseconds,
    );
    tracer.finish(
      cacheUsed: result.fromCache,
      sharedInFlight: result.sharedInFlight,
      cachedOrders: bundle.salesOrders.length,
      cachedPayments: bundle.customerPayments.length,
      cachedItems: 0,
      cachedQueries: result.fromCache ? 0 : bundle.firestoreQueries,
      extra: {
        'gastos': bundle.expenses.length,
        'compras': bundle.purchases.length,
        'pagosProveedor': bundle.supplierPayments.length,
      },
    );
    return bundle;
  }

  Future<FinanceDashboardBundle> _loadFinanceDashboardBundle(
    FinanceDashboardKey key, {
    required bool forceRefresh,
  }) async {
    final start = DateTime.parse(key.startBusinessDate);
    final endExclusive = DateTime.parse(
      key.endBusinessDate,
    ).add(const Duration(days: 1));

    final reportFuture = getReportDataBundle(
      restaurantId: key.restaurantId,
      branchId: key.branchId,
      startBusinessDate: key.startBusinessDate,
      endBusinessDate: key.endBusinessDate,
      includeItems: true,
      forceRefresh: forceRefresh,
      reportName: 'FinanceDashboardSales',
    );
    final cashSessionsFuture = _cashSessionsRef
        .where('businessDate', isGreaterThanOrEqualTo: key.startBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: key.endBusinessDate)
        .get();
    final expensesFuture = _cashWithdrawalRequestsRef
        .where('businessDate', isGreaterThanOrEqualTo: key.startBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: key.endBusinessDate)
        .get();
    final purchasesFuture = Future.wait([
      _supplierPurchasesRef
          .where('dueDate', isGreaterThanOrEqualTo: start)
          .where('dueDate', isLessThan: endExclusive)
          .get(),
      _supplierPurchasesRef
          .where('purchaseDate', isGreaterThanOrEqualTo: start)
          .where('purchaseDate', isLessThan: endExclusive)
          .get(),
      _supplierPurchasesRef
          .where('businessDate', isGreaterThanOrEqualTo: key.startBusinessDate)
          .where('businessDate', isLessThanOrEqualTo: key.endBusinessDate)
          .get(),
    ]);
    final supplierPaymentsFuture = Future.wait([
      _supplierPaymentsRef
          .where('paymentDate', isGreaterThanOrEqualTo: start)
          .where('paymentDate', isLessThan: endExclusive)
          .get(),
      _supplierPaymentsRef
          .where('businessDate', isGreaterThanOrEqualTo: key.startBusinessDate)
          .where('businessDate', isLessThanOrEqualTo: key.endBusinessDate)
          .get(),
    ]);
    final suppliersFuture = _suppliersRef.get();

    final report = await reportFuture;
    final cashSnapshot = await cashSessionsFuture;
    final expenseSnapshot = await expensesFuture;
    final purchaseSnapshots = await purchasesFuture;
    final supplierPaymentSnapshots = await supplierPaymentsFuture;
    final supplierSnapshot = await suppliersFuture;

    final purchaseDocs =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snapshot in purchaseSnapshots) {
      for (final doc in snapshot.docs) {
        purchaseDocs[doc.reference.path] = doc;
      }
    }
    final supplierPaymentDocs =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snapshot in supplierPaymentSnapshots) {
      for (final doc in snapshot.docs) {
        supplierPaymentDocs[doc.reference.path] = doc;
      }
    }

    return buildFinanceDashboard(
      FinanceDashboardInput(
        key: key,
        salesSummary: report.canonicalSummary!,
        paymentsByOrder: report.paymentsByOrder,
        cashSessions: cashSnapshot.docs
            .map(CashSession.fromDoc)
            .where((row) => _matchesBranch(row.branchId, key.branchId))
            .toList(growable: false),
        withdrawals: expenseSnapshot.docs
            .map(CashWithdrawalRequest.fromDoc)
            .where((row) => _matchesBranch(row.branchId, key.branchId))
            .toList(growable: false),
        purchases: purchaseDocs.values
            .map(SupplierPurchase.fromDoc)
            .where((row) => _matchesBranch(row.branchId, key.branchId))
            .toList(growable: false),
        supplierPayments: supplierPaymentDocs.values
            .map(SupplierPayment.fromDoc)
            .where((row) => _matchesBranch(row.branchId, key.branchId))
            .toList(growable: false),
        suppliers: supplierSnapshot.docs
            .map(Supplier.fromDoc)
            .toList(growable: false),
      ),
      firestoreQueries: report.firestoreQueries + 8,
    );
  }

  Future<ReportDataBundle> getReportDataBundle({
    String? restaurantId,
    String? branchId,
    required String startBusinessDate,
    required String endBusinessDate,
    bool includeItems = false,
    bool forceRefresh = false,
    String reportName = 'ReportDataBundle',
  }) async {
    final selectedBranch = AppSession.instance.selectedBranch;
    final effectiveRestaurantId = restaurantId?.trim().isNotEmpty == true
        ? restaurantId!.trim()
        : selectedBranch.restaurantId;
    final effectiveBranchId = branchId?.trim().isNotEmpty == true
        ? branchId!.trim()
        : selectedBranch.id;
    final key = ReportDataKey(
      restaurantId: effectiveRestaurantId,
      branchId: effectiveBranchId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      includeItems: includeItems,
    );
    final tracer = ReportPerformanceTracer(
      reportName: reportName,
      branchId: effectiveBranchId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      cacheKey: key.value,
    );
    final result = await _reportDataRepository.loadRange(
      key: key,
      forceRefresh: forceRefresh,
      dayLoader: (dayKey) => _loadReportDataBundle(
        dayKey,
        dayKey == key
            ? tracer
            : ReportPerformanceTracer(
                reportName: '$reportName:day',
                branchId: effectiveBranchId,
                startBusinessDate: dayKey.startBusinessDate,
                endBusinessDate: dayKey.endBusinessDate,
                cacheKey: dayKey.value,
              ),
      ),
    );
    final bundle = result.bundle;
    if (result.fromCache || result.sharedInFlight) {
      tracer.finish(
        cacheUsed: result.fromCache,
        sharedInFlight: result.sharedInFlight,
        cachedOrders: bundle.orderDocuments,
        cachedPayments: bundle.paymentDocuments,
        cachedItems: bundle.itemDocuments,
        cachedQueries: result.fromCache ? 0 : bundle.firestoreQueries,
      );
    }
    return bundle;
  }

  Future<YieldProfitReportBundle> getYieldProfitReportBundle({
    required String startBusinessDate,
    required String endBusinessDate,
    bool forceRefresh = false,
  }) async {
    _requireYieldProfitAdmin();
    final session = AppSession.instance;
    final key = YieldProfitReportKey(
      restaurantId: session.currentRestaurantId,
      branchId: session.currentBranchId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
    );
    final stopwatch = Stopwatch()..start();
    final tracer = ReportPerformanceTracer(
      reportName: 'YIELD_PROFIT_REPORT_PERF',
      branchId: key.branchId,
      startBusinessDate: key.startBusinessDate,
      endBusinessDate: key.endBusinessDate,
      cacheKey: key.value,
    );
    final result = await _yieldProfitBundleCache.load(
      key: key,
      forceRefresh: forceRefresh,
      loader: () =>
          _loadYieldProfitReportBundle(key, forceRefresh: forceRefresh),
    );
    stopwatch.stop();
    final bundle = result.$1.withMetadata(
      fromCache: result.$2,
      loadMilliseconds: stopwatch.elapsedMilliseconds,
    );
    tracer.finish(
      cacheUsed: result.$2,
      sharedInFlight: result.$3,
      cachedOrders: bundle.reportData.orderDocuments,
      cachedPayments: bundle.reportData.paymentDocuments,
      cachedItems: bundle.reportData.itemDocuments,
      cachedQueries: result.$2 ? 0 : bundle.firestoreQueries,
      extra: {
        'products': bundle.products.length,
        'recipes': bundle.recipes.length,
        'ingredients': bundle.stockItems.length,
        'purchases': bundle.purchaseLines.length,
        'totalMs': bundle.loadMilliseconds,
      },
    );
    return bundle;
  }

  Future<YieldProfitReportBundle> _loadYieldProfitReportBundle(
    YieldProfitReportKey key, {
    required bool forceRefresh,
  }) async {
    final start = DateTime.parse(key.startBusinessDate);
    final endInclusive = DateTime.parse(
      key.endBusinessDate,
    ).add(const Duration(days: 1)).subtract(const Duration(microseconds: 1));
    final endExclusive = endInclusive.add(const Duration(microseconds: 1));
    final reportFuture = getReportDataBundle(
      restaurantId: key.restaurantId,
      branchId: key.branchId,
      startBusinessDate: key.startBusinessDate,
      endBusinessDate: key.endBusinessDate,
      includeItems: true,
      forceRefresh: forceRefresh,
      reportName: 'YieldProfitSales',
    );
    final productFuture = _productsRef.get();
    final categoryFuture = _productCategoriesRef.get();
    final recipeFuture = _productRecipesRef.get();
    final profileFuture = _ingredientYieldProfilesRef.get();
    final stockFuture = _kitchenStockItemsRef.get();
    final purchaseFuture = _supplierPurchasesRef
        .where('purchaseDate', isLessThan: endExclusive)
        .get();

    final reportData = await reportFuture;
    final productSnapshot = await productFuture;
    final categorySnapshot = await categoryFuture;
    final recipeSnapshot = await recipeFuture;
    final profileSnapshot = await profileFuture;
    final stockSnapshot = await stockFuture;
    final purchaseSnapshot = await purchaseFuture;
    final purchases = purchaseSnapshot.docs
        .map(SupplierPurchase.fromDoc)
        .where(
          (purchase) =>
              !purchase.isCancelled &&
              _matchesBranch(purchase.branchId, key.branchId),
        )
        .toList(growable: false);
    final purchaseItemEntries =
        await runInBatches<
          SupplierPurchase,
          (SupplierPurchase, List<SupplierPurchaseItem>)
        >(
          purchases,
          batchSize: 15,
          action: (purchase) async {
            final snapshot = await _supplierPurchasesRef
                .doc(purchase.id)
                .collection('items')
                .get();
            return (
              purchase,
              snapshot.docs
                  .map(SupplierPurchaseItem.fromDoc)
                  .where(
                    (item) =>
                        item.isActive && item.quantity > 0 && item.unitCost > 0,
                  )
                  .toList(growable: false),
            );
          },
        );
    final stockItems = stockSnapshot.docs
        .map(KitchenStockItem.fromDoc)
        .toList(growable: false);
    final stockByName = {
      for (final item in stockItems) normalizeYieldName(item.name): item.id,
    };
    final purchaseLines = <YieldPurchaseLine>[];
    for (final entry in purchaseItemEntries) {
      for (final item in entry.$2) {
        final stockItemId = item.kitchenStockItemId?.trim().isNotEmpty == true
            ? item.kitchenStockItemId!.trim()
            : stockByName[normalizeYieldName(
                item.kitchenStockItemName ?? item.purchaseItemName,
              )];
        if (stockItemId == null || stockItemId.isEmpty) continue;
        purchaseLines.add(
          YieldPurchaseLine(
            purchaseId: entry.$1.id,
            purchaseDate: entry.$1.purchaseDate,
            supplierName: entry.$1.supplierName,
            stockItemId: stockItemId,
            stockItemName: item.kitchenStockItemName ?? item.purchaseItemName,
            quantity: item.quantity,
            unit: item.unit,
            unitCost: item.unitCost,
          ),
        );
      }
    }
    final products = productSnapshot.docs
        .map(Product.fromDoc)
        .toList(growable: false);
    final categories = categorySnapshot.docs
        .map(ProductCategory.fromDoc)
        .toList(growable: false);
    final recipes = recipeSnapshot.docs
        .map(TheoreticalProductRecipe.fromDoc)
        .toList(growable: false);
    final profiles = profileSnapshot.docs
        .map(IngredientYieldProfile.fromDoc)
        .toList(growable: false);
    final paidSalesSummary = buildCanonicalSalesSummary(
      reportData.orders
          .where(
            (order) =>
                order.status.trim().toLowerCase() == 'paid' ||
                order.paymentStatus.trim().toLowerCase() == 'paid',
          )
          .map(
            (order) => SalesOrderBundleInput(
              order: order,
              items: reportData.itemsByOrder[order.id] ?? const [],
              payments: reportData.paymentsByOrder[order.id] ?? const [],
            ),
          ),
    );
    final report = buildYieldProfitReport(
      sales: paidSalesSummary,
      recipes: recipes,
      profiles: profiles,
      stockItems: stockItems,
      purchaseLines: purchaseLines,
      start: start,
      endInclusive: endInclusive,
    );
    return YieldProfitReportBundle(
      key: key,
      reportData: reportData,
      products: products,
      categories: categories,
      recipes: recipes,
      profiles: profiles,
      stockItems: stockItems,
      purchaseLines: purchaseLines,
      report: report,
      firestoreQueries: reportData.firestoreQueries + 6 + purchases.length,
      fromCache: false,
      loadMilliseconds: 0,
    );
  }

  Future<ReportDataBundle> _loadReportDataBundle(
    ReportDataKey key,
    ReportPerformanceTracer tracer,
  ) async {
    final orderLoad = await tracer.traceOrders(
      () => _ordersForReportRange(key),
      documents: (result) => result.$2,
      queries: 5,
    );
    final orders = orderLoad.$1;

    final paymentFuture = tracer.tracePayments(
      () => runInBatches<PosOrder, (String, List<Payment>)>(
        orders,
        batchSize: 15,
        action: (order) async {
          final snapshot = await _ordersRef
              .doc(order.id)
              .collection('payments')
              .get();
          return (
            order.id,
            snapshot.docs
                .map((doc) => _paymentFromOrderPaymentDoc(doc, order))
                .where(
                  (payment) => _matchesBranch(payment.branchId, key.branchId),
                )
                .toList(),
          );
        },
      ),
      documents: (result) =>
          result.fold<int>(0, (total, entry) => total + entry.$2.length),
      queries: orders.length,
    );
    final itemFuture = key.includeItems
        ? tracer.traceItems(
            () => runInBatches<PosOrder, (String, List<OrderItem>)>(
              orders,
              batchSize: 15,
              action: (order) async {
                final snapshot = await _ordersRef
                    .doc(order.id)
                    .collection('items')
                    .get();
                return (
                  order.id,
                  _sortedOrderItems(snapshot.docs.map(OrderItem.fromDoc)),
                );
              },
            ),
            documents: (result) =>
                result.fold<int>(0, (total, entry) => total + entry.$2.length),
            queries: orders.length,
          )
        : Future<List<(String, List<OrderItem>)>>.value(const []);

    final paymentEntries = await paymentFuture;
    final itemEntries = await itemFuture;
    final paymentsByOrder = {
      for (final entry in paymentEntries) entry.$1: entry.$2,
    };
    final itemsByOrder = {for (final entry in itemEntries) entry.$1: entry.$2};
    final payments = paymentEntries.expand((entry) => entry.$2).toList()
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    final canonicalSummary = key.includeItems
        ? tracer.traceProcessing(
            () => buildCanonicalSalesSummary(
              orders.map(
                (order) => SalesOrderBundleInput(
                  order: order,
                  items: itemsByOrder[order.id] ?? const [],
                  payments: paymentsByOrder[order.id] ?? const [],
                ),
              ),
            ),
          )
        : null;
    final bundle = ReportDataBundle(
      key: key,
      orders: orders,
      payments: payments,
      paymentsByOrder: paymentsByOrder,
      itemsByOrder: itemsByOrder,
      canonicalSummary: canonicalSummary,
      firestoreQueries:
          5 + orders.length + (key.includeItems ? orders.length : 0),
      orderDocuments: orderLoad.$2,
      paymentDocuments: payments.length,
      itemDocuments: itemEntries.fold<int>(
        0,
        (total, entry) => total + entry.$2.length,
      ),
    );
    tracer.finish(cacheUsed: false);
    return bundle;
  }

  Future<(List<PosOrder>, int)> _ordersForReportRange(ReportDataKey key) async {
    if (key.startBusinessDate == key.endBusinessDate) {
      final branch = Branch(
        id: key.branchId,
        name: key.branchId,
        normalizedName: normalizeBranchName(key.branchId),
        active: true,
        sortOrder: 0,
        restaurantId: key.restaurantId,
      );
      final session = await _cashSessionForBranchAndDate(
        branch: branch,
        businessDate: key.startBusinessDate,
      );
      final docs = await _orderDocsForHistoricalCashCorrection(
        branch: branch,
        businessDate: key.startBusinessDate,
        selectedCashSessionId: session?.id ?? '',
        selectedCashSession: session,
        excludeCancelled: false,
      );
      final orders = docs.map(PosOrder.fromDoc).toList()
        ..sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
      return (orders, docs.length);
    }

    final startDate = DateTime.parse(key.startBusinessDate);
    final endExclusive = DateTime.parse(
      key.endBusinessDate,
    ).add(const Duration(days: 1));
    final snapshots = await Future.wait([
      _ordersRef
          .where('businessDate', isGreaterThanOrEqualTo: key.startBusinessDate)
          .where('businessDate', isLessThanOrEqualTo: key.endBusinessDate)
          .get(),
      _ordersRef
          .where(
            'operationalDate',
            isGreaterThanOrEqualTo: key.startBusinessDate,
          )
          .where('operationalDate', isLessThanOrEqualTo: key.endBusinessDate)
          .get(),
      _ordersRef
          .where('createdAt', isGreaterThanOrEqualTo: startDate)
          .where('createdAt', isLessThan: endExclusive)
          .get(),
      _ordersRef
          .where('updatedAt', isGreaterThanOrEqualTo: startDate)
          .where('updatedAt', isLessThan: endExclusive)
          .get(),
      _ordersRef
          .where('paidAt', isGreaterThanOrEqualTo: startDate)
          .where('paidAt', isLessThan: endExclusive)
          .get(),
    ]);
    final docsByPath = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        docsByPath[doc.reference.path] = doc;
      }
    }
    final documentsRead = snapshots.fold<int>(
      0,
      (total, snapshot) => total + snapshot.docs.length,
    );
    final orders =
        docsByPath.values.map(PosOrder.fromDoc).where((order) {
          if (!_matchesBranch(order.branchId, key.branchId)) return false;
          final businessDate = _businessDateForOrder(order);
          if (businessDate != null) {
            return businessDate.compareTo(key.startBusinessDate) >= 0 &&
                businessDate.compareTo(key.endBusinessDate) <= 0;
          }
          return _reportDateInRange(order.updatedAt, startDate, endExclusive) ||
              _reportDateInRange(order.paidAt, startDate, endExclusive);
        }).toList()..sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
    return (orders, documentsRead);
  }

  bool _reportDateInRange(
    DateTime? value,
    DateTime start,
    DateTime endExclusive,
  ) {
    return value != null &&
        !value.isBefore(start) &&
        value.isBefore(endExclusive);
  }

  Future<CanonicalSalesSummary> getCanonicalSalesSummary({
    String? restaurantId,
    String? branchId,
    required String startBusinessDate,
    required String endBusinessDate,
    bool forceRefresh = false,
  }) async {
    final bundle = await getReportDataBundle(
      restaurantId: restaurantId,
      branchId: branchId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      includeItems: true,
      forceRefresh: forceRefresh,
      reportName: 'CanonicalSales',
    );
    for (final order in bundle.orders) {
      _debugSalesDateAssignment(
        order: order,
        payments: bundle.paymentsByOrder[order.id] ?? const [],
        startBusinessDate: startBusinessDate,
        endBusinessDate: endBusinessDate,
      );
    }
    return bundle.canonicalSummary!;
  }

  Future<HourlyComparisonReport> getKitchenHourlySalesComparison() async {
    final openCash = await getOpenCashSession();
    final businessDate = openCash?.businessDate ?? _currentBusinessDate();
    final baseDate = _dateFromBusinessDate(businessDate);
    if (baseDate == null) {
      throw StateError('No se pudo determinar la fecha operativa.');
    }
    final branch = AppSession.instance.selectedBranch;
    final previousBusinessDate = _businessDateFor(
      baseDate.subtract(const Duration(days: 7)),
    );
    final currentSession =
        openCash ??
        await _cashSessionForBranchAndDate(
          branch: branch,
          businessDate: businessDate,
        );
    final previousSession = await _cashSessionForBranchAndDate(
      branch: branch,
      businessDate: previousBusinessDate,
    );

    final orderDocs = [
      ...await _orderDocsForHistoricalCashCorrection(
        branch: branch,
        businessDate: businessDate,
        selectedCashSessionId: currentSession?.id ?? '',
        selectedCashSession: currentSession,
      ),
      ...await _orderDocsForHistoricalCashCorrection(
        branch: branch,
        businessDate: previousBusinessDate,
        selectedCashSessionId: previousSession?.id ?? '',
        selectedCashSession: previousSession,
      ),
    ];
    final ordersById = <String, PosOrder>{};
    for (final doc in orderDocs) {
      final order = PosOrder.fromDoc(doc);
      ordersById[order.id] = order;
    }

    final payments = [
      ...await _paymentsForBranchAndBusinessDate(
        branch: branch,
        businessDate: businessDate,
        selectedCashSessionId: currentSession?.id ?? '',
        selectedCashSession: currentSession,
      ),
      ...await _paymentsForBranchAndBusinessDate(
        branch: branch,
        businessDate: previousBusinessDate,
        selectedCashSessionId: previousSession?.id ?? '',
        selectedCashSession: previousSession,
      ),
    ];

    return buildHourlySalesComparison(
      mode: HourlyComparisonMode.previousWeek,
      payments: payments,
      orders: ordersById.values.toList(),
      baseDate: baseDate,
    )!;
  }

  Stream<List<CashSession>> watchCashSessions({
    String? startBusinessDate,
    String? endBusinessDate,
  }) {
    Query<Map<String, dynamic>> query = _cashSessionsRef;
    if (startBusinessDate != null) {
      query = query.where(
        'businessDate',
        isGreaterThanOrEqualTo: startBusinessDate,
      );
    }
    if (endBusinessDate != null) {
      query = query.where('businessDate', isLessThanOrEqualTo: endBusinessDate);
    }

    return query.snapshots().map((snapshot) {
      final sessions =
          _filterCurrentBranch(
            snapshot.docs.map(CashSession.fromDoc),
            (session) => session.branchId,
          )..sort((a, b) {
            final aDate = a.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
      return sessions;
    });
  }

  Future<CashScheduleLoadResult> getCashScheduleSessions({
    required String startBusinessDate,
    required String endBusinessDate,
    bool forceRefresh = false,
  }) async {
    final session = AppSession.instance;
    final branchId = session.currentBranchId;
    final cacheKey = [
      session.currentRestaurantId,
      branchId,
      startBusinessDate,
      endBusinessDate,
    ].join('|');
    final stopwatch = Stopwatch()..start();
    final cached = _cashScheduleCache[cacheKey];
    final cacheIsFresh =
        cached != null &&
        DateTime.now().difference(cached.loadedAt) < const Duration(minutes: 2);

    if (!forceRefresh && cacheIsFresh) {
      stopwatch.stop();
      _debugCashSchedulePerformance(
        branchId: branchId,
        startBusinessDate: startBusinessDate,
        endBusinessDate: endBusinessDate,
        sessions: cached.sessions.length,
        queries: 0,
        totalMilliseconds: stopwatch.elapsedMilliseconds,
        cache: true,
      );
      return CashScheduleLoadResult(
        sessions: List.unmodifiable(cached.sessions),
        fromCache: true,
        queries: 0,
        totalMilliseconds: stopwatch.elapsedMilliseconds,
      );
    }

    final snapshot = await _cashSessionsRef
        .where('businessDate', isGreaterThanOrEqualTo: startBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: endBusinessDate)
        .get();
    final sessions =
        snapshot.docs
            .map(CashSession.fromDoc)
            .where((row) => _matchesBranch(row.branchId, branchId))
            .toList()
          ..sort((a, b) {
            final dateCompare = a.businessDate.compareTo(b.businessDate);
            if (dateCompare != 0) return dateCompare;
            final aDate = a.openedAt ?? a.createdAt ?? DateTime(0);
            final bDate = b.openedAt ?? b.createdAt ?? DateTime(0);
            return aDate.compareTo(bDate);
          });
    _cashScheduleCache[cacheKey] = _CashScheduleCacheEntry(
      sessions: List.unmodifiable(sessions),
      loadedAt: DateTime.now(),
    );
    stopwatch.stop();
    _debugCashSchedulePerformance(
      branchId: branchId,
      startBusinessDate: startBusinessDate,
      endBusinessDate: endBusinessDate,
      sessions: sessions.length,
      queries: 1,
      totalMilliseconds: stopwatch.elapsedMilliseconds,
      cache: false,
    );
    return CashScheduleLoadResult(
      sessions: sessions,
      fromCache: false,
      queries: 1,
      totalMilliseconds: stopwatch.elapsedMilliseconds,
    );
  }

  void invalidateCashScheduleCache({String? branchId}) {
    final cleanBranchId = branchId?.trim();
    if (cleanBranchId == null || cleanBranchId.isEmpty) {
      _cashScheduleCache.clear();
      return;
    }
    _cashScheduleCache.removeWhere((key, _) {
      final parts = key.split('|');
      return parts.length > 1 && parts[1] == cleanBranchId;
    });
  }

  void _debugCashSchedulePerformance({
    required String branchId,
    required String startBusinessDate,
    required String endBusinessDate,
    required int sessions,
    required int queries,
    required int totalMilliseconds,
    required bool cache,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      'CASH_SCHEDULE_REPORT_PERF '
      'branchId=$branchId '
      'startBusinessDate=$startBusinessDate '
      'endBusinessDate=$endBusinessDate '
      'sessions=$sessions '
      'queries=$queries '
      'totalMs=$totalMilliseconds '
      'cache=$cache',
    );
  }

  Stream<CashSession?> watchOpenCashSession() {
    return watchCashSessions().map((sessions) {
      final openSessions = sessions
          .where((session) => session.status == 'open')
          .toList();
      if (openSessions.isEmpty) {
        return null;
      }
      return openSessions.first;
    });
  }

  Stream<CashSessionTotals> watchCashSessionTotals(String cashSessionId) {
    return watchPayments().asyncMap((payments) async {
      final sessionDoc = await _cashSessionsRef.doc(cashSessionId).get();
      final session = sessionDoc.exists
          ? CashSession.fromDoc(sessionDoc)
          : null;
      final withdrawals = await _cashWithdrawalRequestsForSessionOnce(
        cashSessionId,
      );
      return _totalsForPayments(
        payments
            .where((payment) => payment.cashSessionId == cashSessionId)
            .where((payment) => payment.isActive)
            .toList(),
        openingCashAmount: session?.openingCashAmount ?? 0,
        withdrawals: withdrawals,
      );
    });
  }

  Stream<List<CashWithdrawalRequest>> watchCashWithdrawalRequests({
    String? cashSessionId,
    String? businessDate,
    String? startBusinessDate,
    String? endBusinessDate,
    String? status,
    String? requestedByEmployeeId,
  }) {
    Query<Map<String, dynamic>> query = _cashWithdrawalRequestsRef;
    if (cashSessionId != null) {
      query = query.where('cashSessionId', isEqualTo: cashSessionId);
    }
    if (businessDate != null) {
      query = query.where('businessDate', isEqualTo: businessDate);
    }
    if (startBusinessDate != null) {
      query = query.where(
        'businessDate',
        isGreaterThanOrEqualTo: startBusinessDate,
      );
    }
    if (endBusinessDate != null) {
      query = query.where('businessDate', isLessThanOrEqualTo: endBusinessDate);
    }
    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }
    if (requestedByEmployeeId != null) {
      query = query.where(
        'requestedByEmployeeId',
        isEqualTo: requestedByEmployeeId,
      );
    }

    return query.snapshots().map((snapshot) {
      final requests =
          snapshot.docs.map(CashWithdrawalRequest.fromDoc).where((request) {
            if (!_matchesCurrentBranch(request.branchId)) {
              return false;
            }
            if (cashSessionId != null &&
                request.cashSessionId != cashSessionId) {
              return false;
            }
            if (businessDate != null && request.businessDate != businessDate) {
              return false;
            }
            if (startBusinessDate != null &&
                request.businessDate.compareTo(startBusinessDate) < 0) {
              return false;
            }
            if (endBusinessDate != null &&
                request.businessDate.compareTo(endBusinessDate) > 0) {
              return false;
            }
            if (status != null && request.status != status) {
              return false;
            }
            if (requestedByEmployeeId != null &&
                request.requestedByEmployeeId != requestedByEmployeeId) {
              return false;
            }
            return true;
          }).toList()..sort((a, b) {
            final aDate =
                a.requestedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate =
                b.requestedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
      return requests;
    });
  }

  Future<CashSession?> getOpenCashSession() async {
    final snapshot = await _cashSessionsRef.get();
    final sessions =
        snapshot.docs
            .map(CashSession.fromDoc)
            .where(
              (session) =>
                  session.status == 'open' &&
                  _matchesCurrentBranch(session.branchId),
            )
            .toList()
          ..sort((a, b) {
            final aDate = a.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });

    return sessions.isEmpty ? null : sessions.first;
  }

  Stream<List<KitchenStockItem>> watchKitchenStockItems({
    bool activeOnly = false,
  }) {
    return _kitchenStockItemsRef.snapshots().map((snapshot) {
      final items = snapshot.docs.map(KitchenStockItem.fromDoc).toList()
        ..sort((a, b) {
          final orderCompare = a.sortOrder.compareTo(b.sortOrder);
          return orderCompare != 0 ? orderCompare : a.name.compareTo(b.name);
        });
      return activeOnly ? items.where((item) => item.active).toList() : items;
    });
  }

  Future<void> ensureDefaultKitchenStockItems() async {
    final snapshot = await _kitchenStockItemsRef.get();
    final existingIds = snapshot.docs.map((doc) => doc.id).toSet();

    final batch = _db.batch();
    var hasUpdates = false;
    for (final item in _defaultKitchenStockItems) {
      final id = item['id']! as String;
      if (existingIds.contains(id)) {
        continue;
      }
      batch.set(_kitchenStockItemsRef.doc(id), {
        ...item,
        'active': true,
        'affectsKitchenPerformance': true,
        'affectsKitchenStock': true,
        'affectsKitchenYield': true,
        'optimalConsumptionPerSaleQty': item['unit'] == 'piece' ? 1 : 50,
        'optimalConsumptionUnit': item['unit'] == 'piece'
            ? 'piece_per_item'
            : 'g_per_item',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      hasUpdates = true;
    }
    if (hasUpdates) {
      await batch.commit();
    }
  }

  Future<void> ensureKitchenStockLinksForProducts() async {
    await ensureDefaultKitchenStockItems();
    final productsSnapshot = await _productsRef.get();
    final stockItemsSnapshot = await _kitchenStockItemsRef.get();
    final stockById = {
      for (final item in stockItemsSnapshot.docs.map(KitchenStockItem.fromDoc))
        item.id: item,
    };
    final batch = _db.batch();
    var hasUpdates = false;

    for (final doc in productsSnapshot.docs) {
      final data = doc.data();
      final hasExplicitRecipe = ProductRecipeItem.readList(
        data['recipeItems'],
      ).isNotEmpty;
      final product = Product.fromDoc(doc);
      if (hasExplicitRecipe ||
          (!_defaultProductAffectsKitchenStock(product) &&
              product.recipeItems.isEmpty)) {
        continue;
      }
      var recipeItems = _defaultRecipeItemsForProduct(product, stockById);
      if (recipeItems.isEmpty && product.recipeItems.isNotEmpty) {
        recipeItems = product.recipeItems;
      }
      if (recipeItems.isEmpty) {
        continue;
      }
      for (final recipeItem in recipeItems) {
        if (stockById.containsKey(recipeItem.kitchenStockItemId)) {
          continue;
        }
        final stockItem = _fallbackStockItemForRecipeItem(recipeItem, product);
        batch.set(_kitchenStockItemsRef.doc(stockItem.id), {
          'id': stockItem.id,
          'name': stockItem.name,
          'category': stockItem.category,
          'unit': stockItem.unit,
          'active': true,
          'affectsKitchenPerformance': true,
          'affectsKitchenStock': true,
          'affectsKitchenYield': true,
          'sortOrder': stockItem.sortOrder,
          'optimalConsumptionPerSaleQty':
              stockItem.optimalConsumptionPerSaleQty,
          'optimalConsumptionUnit': stockItem.optimalConsumptionUnit,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        stockById[stockItem.id] = stockItem;
      }
      final primary = recipeItems.first;
      batch.set(doc.reference, {
        'affectsKitchenStock': true,
        'recipeItems': ProductRecipeItem.toMapList(recipeItems),
        'kitchenStockItemId': primary.kitchenStockItemId,
        'kitchenStockItemName': primary.kitchenStockItemName,
        'kitchenStockUnit': primary.kitchenStockUnit,
        'stockConsumptionQty': primary.consumptionFactor,
        'kitchenConsumptionFactor': primary.consumptionFactor,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      hasUpdates = true;
    }

    if (hasUpdates) {
      await batch.commit();
    }
  }

  Future<List<KitchenStockItem>> _activeControlledKitchenStockItems() async {
    final stockSnapshot = await _kitchenStockItemsRef.get();
    final productSnapshot = await _productsRef.get();
    final linkedStockIds = <String>{};
    for (final product in productSnapshot.docs.map(Product.fromDoc)) {
      if (!product.active || !product.affectsKitchenStock) {
        continue;
      }
      if (product.recipeItems.isNotEmpty) {
        linkedStockIds.add(product.recipeItems.first.kitchenStockItemId);
      }
      final legacyId = product.kitchenStockItemId;
      if (legacyId != null && legacyId.trim().isNotEmpty) {
        linkedStockIds.add(legacyId);
      }
    }

    return stockSnapshot.docs
        .map(KitchenStockItem.fromDoc)
        .where(
          (item) =>
              item.active &&
              item.affectsKitchenPerformance &&
              (linkedStockIds.contains(item.id) || item.id == 'tortilla_maiz'),
        )
        .toList()
      ..sort((a, b) {
        final categoryCompare = a.category.compareTo(b.category);
        if (categoryCompare != 0) {
          return categoryCompare;
        }
        final sortCompare = a.sortOrder.compareTo(b.sortOrder);
        return sortCompare != 0 ? sortCompare : a.name.compareTo(b.name);
      });
  }

  Future<void> saveKitchenStockItem({
    String? itemId,
    required String name,
    required String category,
    required String unit,
    required bool active,
    required int sortOrder,
    double optimalConsumptionPerSaleQty = 0,
    String optimalConsumptionUnit = '',
    bool affectsKitchenPerformance = true,
    String? defaultSupplierId,
    String? defaultSupplierName,
    String notes = '',
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageKitchenStock == true ||
          AppSession.instance.employee?.canManageSuppliers == true,
      'No tienes permiso para administrar insumos.',
    );
    final docRef = itemId == null
        ? _kitchenStockItemsRef.doc()
        : _kitchenStockItemsRef.doc(itemId);
    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'category': category,
      'unit': unit,
      'active': active,
      'affectsKitchenPerformance': affectsKitchenPerformance,
      'affectsKitchenStock': affectsKitchenPerformance,
      'affectsKitchenYield': affectsKitchenPerformance,
      'sortOrder': sortOrder,
      'optimalConsumptionPerSaleQty': optimalConsumptionPerSaleQty,
      'optimalConsumptionUnit': optimalConsumptionUnit,
      'defaultSupplierId': defaultSupplierId,
      'defaultSupplierName': defaultSupplierName,
      'notes': notes.trim(),
      if (itemId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    // TODO: Registrar kitchen_stock_item_created/updated en activityLog.
  }

  Future<void> toggleKitchenStockItem(KitchenStockItem item) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageKitchenStock == true,
      'No tienes permiso para administrar insumos de cocina.',
    );
    await _kitchenStockItemsRef.doc(item.id).update({
      'active': !item.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // TODO: Registrar kitchen_stock_item_disabled en activityLog.
  }

  Stream<KitchenSession?> watchOpenKitchenSession() {
    return _kitchenSessionsRef
        .where('status', isEqualTo: 'open')
        .snapshots()
        .map((snapshot) {
          final sessions = _filterCurrentBranch(
            snapshot.docs.map(KitchenSession.fromDoc),
            (session) => session.branchId,
          )..sort((a, b) => b.businessDate.compareTo(a.businessDate));
          return sessions.isEmpty ? null : sessions.first;
        });
  }

  Future<String> currentKitchenBusinessDate() async {
    final openCash = await getOpenCashSession();
    return openCash?.businessDate ?? _businessDateFor(DateTime.now());
  }

  Future<KitchenSession?> getOpenKitchenSessionForCurrentBusinessDate() async {
    final businessDate = await currentKitchenBusinessDate();
    final snapshot = await _kitchenSessionsRef
        .where('businessDate', isEqualTo: businessDate)
        .get();
    final sessions = snapshot.docs
        .map(KitchenSession.fromDoc)
        .where(
          (session) =>
              session.isOpen && _matchesCurrentBranch(session.branchId),
        )
        .toList();
    return sessions.isEmpty ? null : sessions.first;
  }

  Future<bool> hasCompletedOpenKitchenForCurrentBusinessDate() async {
    final session = await getOpenKitchenSessionForCurrentBusinessDate();
    if (session == null) {
      return false;
    }
    final itemsSnapshot = await _kitchenSessionsRef
        .doc(session.id)
        .collection('items')
        .limit(1)
        .get();
    return itemsSnapshot.docs.isNotEmpty;
  }

  Future<List<KitchenYieldReportRow>> kitchenYieldReport({
    required String startBusinessDate,
    required String endBusinessDate,
  }) async {
    final sessionsSnapshot = await _kitchenSessionsRef.get();
    final sessions =
        sessionsSnapshot.docs
            .map(KitchenSession.fromDoc)
            .where(
              (session) =>
                  session.businessDate.compareTo(startBusinessDate) >= 0 &&
                  session.businessDate.compareTo(endBusinessDate) <= 0 &&
                  _matchesCurrentBranch(session.branchId),
            )
            .toList()
          ..sort((a, b) => b.businessDate.compareTo(a.businessDate));

    final stockSnapshot = await _kitchenStockItemsRef.get();
    final stockById = {
      for (final item in stockSnapshot.docs.map(KitchenStockItem.fromDoc))
        item.id: item,
    };
    final totalsConsumed = <String, double>{};
    final totalsSold = <String, double>{};
    final currentByStockId = <String, KitchenSessionItem>{};

    for (final session in sessions) {
      final itemsSnapshot = await _kitchenSessionsRef
          .doc(session.id)
          .collection('items')
          .get();
      final items = itemsSnapshot.docs.map(KitchenSessionItem.fromDoc).toList();
      for (final item in items) {
        currentByStockId.putIfAbsent(item.kitchenStockItemId, () => item);
        totalsConsumed[item.kitchenStockItemId] =
            (totalsConsumed[item.kitchenStockItemId] ?? 0) +
            item.usefulConsumedQty;
        totalsSold[item.kitchenStockItemId] =
            (totalsSold[item.kitchenStockItemId] ?? 0) + item.soldQty;
        stockById.putIfAbsent(
          item.kitchenStockItemId,
          () => KitchenStockItem(
            id: item.kitchenStockItemId,
            name: item.name,
            category: item.category,
            unit: item.unit,
            active: true,
            sortOrder: 999,
            optimalConsumptionPerSaleQty: item.unit == 'piece' ? 1 : 50,
            optimalConsumptionUnit: item.unit == 'piece'
                ? 'piece_per_item'
                : 'g_per_item',
          ),
        );
      }
    }

    final rows = <KitchenYieldReportRow>[];
    for (final entry in stockById.entries) {
      final current = currentByStockId[entry.key];
      if (current == null) {
        continue;
      }
      final totalConsumed = totalsConsumed[entry.key] ?? 0;
      final totalSold = totalsSold[entry.key] ?? 0;
      rows.add(
        KitchenYieldReportRow(
          item: entry.value,
          currentItem: current,
          previousRemainingQty: current.previousRemainingQty,
          initialInputQty: current.todayInputQty,
          additionalEntriesQty: current.additionalEntriesQty,
          availableQty: current.availableQty,
          finalRemainingQty: current.finalRemainingQty,
          wasteQty: current.wasteQty,
          usedQty: current.usedQty,
          usefulConsumedQty: current.usefulConsumedQty,
          soldQty: current.soldQty,
          currentYield: _yieldPerSale(
            unit: current.unit,
            usefulConsumedQty: current.usefulConsumedQty,
            soldQty: current.soldQty,
          ),
          averageYield: _yieldPerSale(
            unit: current.unit,
            usefulConsumedQty: totalConsumed,
            soldQty: totalSold,
          ),
        ),
      );
    }
    rows.sort((a, b) {
      final categoryCompare = a.item.category.compareTo(b.item.category);
      if (categoryCompare != 0) return categoryCompare;
      final sortCompare = a.item.sortOrder.compareTo(b.item.sortOrder);
      return sortCompare != 0
          ? sortCompare
          : a.item.name.compareTo(b.item.name);
    });
    return rows;
  }

  Stream<List<KitchenSession>> watchKitchenSessions({
    String? startBusinessDate,
    String? endBusinessDate,
  }) {
    Query<Map<String, dynamic>> query = _kitchenSessionsRef;
    if (startBusinessDate != null) {
      query = query.where(
        'businessDate',
        isGreaterThanOrEqualTo: startBusinessDate,
      );
    }
    if (endBusinessDate != null) {
      query = query.where('businessDate', isLessThanOrEqualTo: endBusinessDate);
    }
    return query.snapshots().map((snapshot) {
      final sessions = _filterCurrentBranch(
        snapshot.docs.map(KitchenSession.fromDoc),
        (session) => session.branchId,
      )..sort((a, b) => b.businessDate.compareTo(a.businessDate));
      return sessions;
    });
  }

  Stream<List<KitchenSessionItem>> watchKitchenSessionItems(
    String kitchenSessionId,
  ) {
    return _kitchenSessionsRef
        .doc(kitchenSessionId)
        .collection('items')
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs.map(KitchenSessionItem.fromDoc).toList()
            ..sort((a, b) {
              final categoryCompare = a.category.compareTo(b.category);
              return categoryCompare != 0
                  ? categoryCompare
                  : a.name.compareTo(b.name);
            });
          return items;
        });
  }

  Stream<List<KitchenAdditionalEntry>> watchKitchenAdditionalEntries(
    String kitchenSessionId,
  ) {
    return _kitchenSessionsRef
        .doc(kitchenSessionId)
        .collection('additionalEntries')
        .snapshots()
        .map((snapshot) {
          final entries =
              snapshot.docs.map(KitchenAdditionalEntry.fromDoc).toList()
                ..sort((a, b) {
                  final aDate =
                      a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final bDate =
                      b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return bDate.compareTo(aDate);
                });
          return entries;
        });
  }

  Future<KitchenSession?> getKitchenSessionForBusinessDate(
    String businessDate,
  ) async {
    final sessions = await _kitchenSessionsForBusinessDate(businessDate);
    if (sessions.isEmpty) {
      return null;
    }
    final validClosed = <KitchenSession>[];
    for (final session in sessions.where((session) => session.isClosed)) {
      if (await _kitchenCloseIsComplete(session.id)) {
        validClosed.add(session);
      }
    }
    if (validClosed.isNotEmpty) {
      return validClosed.first;
    }
    final openSessions = sessions.where((session) => session.isOpen).toList();
    if (openSessions.isNotEmpty) {
      return openSessions.first;
    }
    return sessions.first;
  }

  Future<List<KitchenSession>> _kitchenSessionsForBusinessDate(
    String businessDate,
  ) async {
    final snapshot = await _kitchenSessionsRef
        .where('businessDate', isEqualTo: businessDate)
        .get();
    final sessions =
        _filterCurrentBranch(
          snapshot.docs.map(KitchenSession.fromDoc),
          (session) => session.branchId,
        )..sort((a, b) {
          final statusCompare = _kitchenSessionStatusRank(
            a,
          ).compareTo(_kitchenSessionStatusRank(b));
          if (statusCompare != 0) return statusCompare;
          final aDate = a.closedAt ?? a.openedAt ?? DateTime(0);
          final bDate = b.closedAt ?? b.openedAt ?? DateTime(0);
          return bDate.compareTo(aDate);
        });
    return sessions;
  }

  int _kitchenSessionStatusRank(KitchenSession session) {
    if (session.isClosed) return 0;
    if (session.isOpen) return 1;
    return 2;
  }

  Future<List<KitchenOpeningInput>> buildKitchenOpeningInputs() async {
    await ensureDefaultKitchenStockItems();
    await ensureKitchenStockLinksForProducts();
    final openCash = await getOpenCashSession();
    final currentBusinessDate = _currentBusinessDate();
    final businessDate = openCash?.businessDate ?? currentBusinessDate;
    if (businessDate != currentBusinessDate) {
      throw StateError(
        'No puedes abrir cocina con una fecha diferente a la fecha actual.',
      );
    }
    final existingSessions = await _kitchenSessionsForBusinessDate(
      businessDate,
    );
    if (existingSessions.any((session) => session.isOpen)) {
      throw StateError(
        'La cocina ya fue abierta para esta fecha de operacion.',
      );
    }
    if (existingSessions.any((session) => session.isClosed)) {
      throw StateError(
        'La cocina de esta sucursal ya fue cerrada hoy. No puedes abrirla nuevamente.',
      );
    }
    final previousRemaining = await _previousKitchenRemainingByItem(
      businessDate,
    );
    final items = await _activeControlledKitchenStockItems();
    return items
        .map(
          (item) => KitchenOpeningInput(
            item: item,
            previousRemainingQty: previousRemaining[item.id] ?? 0,
            todayInputQty: 0,
          ),
        )
        .toList();
  }

  Future<KitchenSession> openKitchenSessionWithInputs({
    required Map<String, double> todayInputByItemId,
  }) async {
    _requireOpenKitchen();
    await ensureDefaultKitchenStockItems();
    await ensureKitchenStockLinksForProducts();
    final openCash = await getOpenCashSession();
    final currentBusinessDate = _currentBusinessDate();
    final businessDate = openCash?.businessDate ?? currentBusinessDate;
    if (businessDate != currentBusinessDate) {
      throw StateError(
        'No puedes abrir cocina con una fecha diferente a la fecha actual.',
      );
    }
    final existingSessions = await _kitchenSessionsForBusinessDate(
      businessDate,
    );
    if (existingSessions.any((session) => session.isOpen)) {
      throw StateError(
        'La cocina ya fue abierta para esta fecha de operacion.',
      );
    }
    if (existingSessions.any((session) => session.isClosed)) {
      throw StateError(
        'La cocina de esta sucursal ya fue cerrada hoy. No puedes abrirla nuevamente.',
      );
    }

    final activeItems = await _activeControlledKitchenStockItems();
    if (activeItems.isEmpty) {
      throw StateError('No hay insumos activos para abrir cocina.');
    }
    if (todayInputByItemId.length < activeItems.length) {
      throw ArgumentError(
        'Captura las entradas del dia antes de abrir cocina.',
      );
    }

    final previousRemaining = await _previousKitchenRemainingByItem(
      businessDate,
    );
    final employee = AppSession.instance.employee;
    final docRef = _kitchenSessionsRef.doc();
    final batch = _db.batch();
    batch.set(docRef, {
      'id': docRef.id,
      'businessDate': businessDate,
      'cashSessionId': openCash?.id,
      ..._currentBranchFields,
      'status': 'open',
      'openedAt': FieldValue.serverTimestamp(),
      'openedByEmployeeId': employee?.id ?? '',
      'openedByEmployeeName': employee?.name ?? '',
      'closedAt': null,
      'closedByEmployeeId': null,
      'closedByEmployeeName': null,
      'notes': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final item in activeItems) {
      final todayInputQty = todayInputByItemId[item.id];
      if (todayInputQty == null || todayInputQty < 0) {
        throw ArgumentError(
          'Captura las entradas del dia antes de abrir cocina.',
        );
      }
      if (item.unit == 'piece' &&
          todayInputQty != todayInputQty.roundToDouble()) {
        throw ArgumentError('${item.name} debe capturarse en piezas enteras.');
      }
      final previousQty = previousRemaining[item.id] ?? 0;
      final availableQty = previousQty + todayInputQty;
      batch.set(docRef.collection('items').doc(item.id), {
        'kitchenStockItemId': item.id,
        ..._currentBranchFields,
        'name': item.name,
        'category': item.category,
        'unit': item.unit,
        'previousRemainingQty': previousQty,
        'todayInputQty': todayInputQty,
        'additionalEntriesQty': 0.0,
        'availableQty': availableQty,
        'finalRemainingQty': null,
        'wasteQty': null,
        'usedQty': null,
        'usefulConsumedQty': null,
        'soldQty': null,
        'yieldQtyPerUnit': null,
        'notes': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    // TODO: Registrar kitchen_session_opened en activityLog.
    final updated = await docRef.get();
    return KitchenSession.fromDoc(updated);
  }

  Future<void> updateKitchenSessionItemInput({
    required String kitchenSessionId,
    required KitchenSessionItem item,
    required double todayInputQty,
  }) async {
    throw StateError(
      'La apertura ya esta bloqueada. Usa Agregar entrada del dia.',
    );
  }

  Future<void> addKitchenAdditionalEntry({
    required String kitchenSessionId,
    required KitchenSessionItem item,
    required double qty,
    required String reason,
    required String notes,
  }) async {
    _requireOpenKitchen();
    if (qty <= 0) {
      throw ArgumentError('La entrada adicional debe ser mayor a cero.');
    }
    if (item.unit == 'piece' && qty != qty.roundToDouble()) {
      throw ArgumentError('${item.name} debe capturarse en piezas enteras.');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('Captura el motivo de la entrada.');
    }

    final sessionRef = _kitchenSessionsRef.doc(kitchenSessionId);
    final sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) {
      throw StateError('La cocina ya no existe.');
    }
    final session = KitchenSession.fromDoc(sessionDoc);
    if (!session.isOpen) {
      throw StateError('Solo puedes agregar entradas con cocina abierta.');
    }

    final employee = AppSession.instance.employee;
    final entryRef = sessionRef.collection('additionalEntries').doc();
    final newAdditionalQty = item.additionalEntriesQty + qty;
    final newAvailableQty =
        item.previousRemainingQty + item.todayInputQty + newAdditionalQty;
    final batch = _db.batch();
    batch.set(entryRef, {
      'id': entryRef.id,
      'kitchenSessionId': kitchenSessionId,
      'businessDate': session.businessDate,
      'restaurantId': session.restaurantId,
      'restaurantName': session.restaurantName,
      'branchId': session.branchId,
      'branchName': session.branchName,
      'kitchenStockItemId': item.kitchenStockItemId,
      'name': item.name,
      'qty': qty,
      'reason': reason.trim(),
      'notes': notes.trim(),
      'createdByEmployeeId': employee?.id ?? '',
      'createdByEmployeeName': employee?.name ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(sessionRef.collection('items').doc(item.id), {
      'additionalEntriesQty': newAdditionalQty,
      'availableQty': newAvailableQty,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(sessionRef, {'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  Future<KitchenSession> closeKitchenSession({
    required String kitchenSessionId,
    required Map<String, KitchenCloseInput> closeInputs,
    required String notes,
  }) async {
    _requireCloseKitchen();
    final docRef = _kitchenSessionsRef.doc(kitchenSessionId);
    final doc = await docRef.get();
    if (!doc.exists) {
      throw StateError('La apertura de cocina ya no existe.');
    }
    final session = KitchenSession.fromDoc(doc);
    if (!session.isOpen) {
      throw StateError('Esta cocina ya esta cerrada.');
    }
    final existingForDate = await _kitchenSessionsForBusinessDate(
      session.businessDate,
    );
    if (existingForDate.any(
      (existing) => existing.id != session.id && existing.isClosed,
    )) {
      throw StateError('Ya existe cierre de cocina para esta fecha.');
    }

    final itemsSnapshot = await docRef.collection('items').get();
    final items = itemsSnapshot.docs.map(KitchenSessionItem.fromDoc).toList();
    final soldByStockItem = await _soldQtyByKitchenStockItem(
      session.businessDate,
    );
    final employee = AppSession.instance.employee;
    final batch = _db.batch();

    for (final item in items) {
      final input = closeInputs[item.id];
      if (input == null) {
        throw ArgumentError('Captura cierre para ${item.name}.');
      }
      if (input.finalRemainingQty < 0 || input.wasteQty < 0) {
        throw ArgumentError('Los montos de cierre no pueden ser negativos.');
      }
      if (item.unit == 'piece' &&
          (input.finalRemainingQty != input.finalRemainingQty.roundToDouble() ||
              input.wasteQty != input.wasteQty.roundToDouble())) {
        throw ArgumentError('${item.name} debe capturarse en piezas enteras.');
      }
      final usedQty = item.availableQty - input.finalRemainingQty;
      final usefulConsumedQty = usedQty - input.wasteQty;
      if (usefulConsumedQty < 0) {
        throw ArgumentError(
          'El consumo util de ${item.name} no puede ser negativo.',
        );
      }
      final soldQty = soldByStockItem[item.kitchenStockItemId] ?? 0;
      final yieldQtyPerUnit = _yieldPerSale(
        unit: item.unit,
        usefulConsumedQty: usefulConsumedQty,
        soldQty: soldQty,
      );

      batch.update(docRef.collection('items').doc(item.id), {
        'finalRemainingQty': input.finalRemainingQty,
        'wasteQty': input.wasteQty,
        'usedQty': usedQty,
        'usefulConsumedQty': usefulConsumedQty,
        'soldQty': soldQty,
        'yieldQtyPerUnit': yieldQtyPerUnit,
        'notes': input.notes.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    batch.update(docRef, {
      'status': 'closed',
      'closedAt': FieldValue.serverTimestamp(),
      'closedByEmployeeId': employee?.id ?? '',
      'closedByEmployeeName': employee?.name ?? '',
      'notes': notes.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final stockOutsSnapshot = await _productStockOutsRef.get();
    for (final stockOutDoc in stockOutsSnapshot.docs) {
      final data = stockOutDoc.data();
      if (data['branchId'] != session.branchId ||
          data['businessDate'] != session.businessDate ||
          data['status'] != 'active') {
        continue;
      }
      _clearProductStockOutInBatch(
        batch,
        stockOutDoc.reference,
        reason: 'kitchen_closed',
      );
    }
    await batch.commit();
    // TODO: Registrar kitchen_session_closed en activityLog.
    final updated = await docRef.get();
    return KitchenSession.fromDoc(updated);
  }

  Future<void> openCashSession({
    required String businessDate,
    required double openingCashAmount,
  }) async {
    _requireCashOpenPermission();
    final cleanBusinessDate = businessDate.trim();
    if (cleanBusinessDate.isEmpty) {
      throw ArgumentError('Selecciona la fecha operativa.');
    }
    if (cleanBusinessDate != _currentBusinessDate()) {
      throw StateError(
        'No puedes abrir caja con una fecha diferente a la fecha actual.',
      );
    }
    if (openingCashAmount < 0) {
      throw ArgumentError('El fondo inicial no puede ser negativo.');
    }

    final openSession = await getOpenCashSession();
    if (openSession != null) {
      if (openSession.businessDate == cleanBusinessDate) {
        return;
      }
      throw StateError(
        'Ya existe una caja abierta para ${openSession.businessDate}.',
      );
    }

    final existingForDate = await _cashSessionsRef
        .where('businessDate', isEqualTo: cleanBusinessDate)
        .get();
    final hasClosed = existingForDate.docs
        .map(CashSession.fromDoc)
        .any(
          (session) =>
              (session.status == 'closed' || session.closedAt != null) &&
              _matchesCurrentBranch(session.branchId),
        );
    if (hasClosed) {
      throw StateError(
        'La caja de esta sucursal ya fue cerrada hoy. No puedes abrirla nuevamente.',
      );
    }

    final employee = AppSession.instance.employee;
    final docRef = _cashSessionsRef.doc();
    final timestamp = FieldValue.serverTimestamp();
    await docRef.set({
      'id': docRef.id,
      'businessDate': cleanBusinessDate,
      ..._currentBranchFields,
      'status': 'open',
      'openingCashAmount': openingCashAmount,
      ...cashSessionOpenTimestampFields(
        serverTimestamp: timestamp,
        employeeId: employee?.id ?? '',
        employeeName: employee?.name ?? '',
      ),
      'countedCashAmount': 0.0,
      'terminalReportedAmount': 0.0,
      'expectedCashAmount': 0.0,
      'expectedCardChargedAmount': 0.0,
      'expectedCardBaseAmount': 0.0,
      'expectedCardSurchargeAmount': 0.0,
      'expectedCardFeeAbsorbedAmount': 0.0,
      'expectedPlatformAmount': 0.0,
      'expectedEmployeeConsumptionAmount': 0.0,
      'totalExpectedRealMoney': 0.0,
      'totalCountedRealMoney': 0.0,
      'cashDifference': 0.0,
      'cardDifference': 0.0,
      'netDifference': 0.0,
      'shortageAmount': 0.0,
      'overAmount': 0.0,
      'approvedWithdrawalsTotal': 0.0,
      'pendingWithdrawalsTotal': 0.0,
      'withdrawalRequestCount': 0,
      'notes': '',
      'createdAt': timestamp,
      'updatedAt': timestamp,
    });
    invalidateCashScheduleCache(branchId: AppSession.instance.currentBranchId);
  }

  Future<void> requestCashWithdrawal({
    required String cashSessionId,
    required double amount,
    required String reason,
    String policyId = '',
    String paymentSource = 'cash',
    String supplierId = '',
    bool hasReceipt = false,
    bool offline = false,
  }) async {
    _requireCashWithdrawalRequester();
    if (amount <= 0) {
      throw ArgumentError('Captura un monto de retiro valido.');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('Captura el motivo del retiro.');
    }

    final sessionDoc = await _cashSessionsRef.doc(cashSessionId).get();
    if (!sessionDoc.exists) {
      throw StateError('No hay una caja abierta para registrar este gasto.');
    }
    final session = CashSession.fromDoc(sessionDoc);
    if (!session.isOpen) {
      throw StateError('No hay una caja abierta para registrar este gasto.');
    }

    final employee = AppSession.instance.employee;
    final docRef = _cashWithdrawalRequestsRef.doc();
    final cleanPolicyId = policyId.trim();
    if (cleanPolicyId.isEmpty) {
      final clientRequestId = docRef.id;
      await docRef.set({
        'id': docRef.id,
        'clientRequestId': clientRequestId,
        'cashSessionId': cashSessionId,
        'businessDate': session.businessDate,
        ..._currentBranchFields,
        'amount': amount,
        'reason': reason.trim(),
        'source': paymentSource,
        'sourceName': paymentSource,
        'supplierId': supplierId.trim(),
        'hasReceipt': hasReceipt,
        'requestedByEmployeeId': employee?.id ?? '',
        'requestedByEmployeeName': employee?.name ?? '',
        'requestedByDeviceId': _auth.currentUser?.uid ?? '',
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'policyId': '',
        'autoApproved': false,
        'wouldAutoApprove': false,
        'authorizedByEmployeeId': null,
        'authorizedByEmployeeName': null,
        'authorizedAt': null,
        'adminNotes': null,
        'approvedAt': null,
        'approvedByEmployeeId': null,
        'approvedByEmployeeName': null,
        'rejectedAt': null,
        'rejectedByEmployeeId': null,
        'rejectedByEmployeeName': null,
        'rejectReason': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    if (offline) {
      final clientRequestId = docRef.id;
      await docRef.set({
        'id': docRef.id,
        'clientRequestId': clientRequestId,
        'cashSessionId': cashSessionId,
        'businessDate': session.businessDate,
        ..._currentBranchFields,
        'amount': amount,
        'reason': reason.trim(),
        'source': paymentSource,
        'sourceName': paymentSource,
        'supplierId': supplierId.trim(),
        'hasReceipt': hasReceipt,
        'requestedByEmployeeId': employee?.id ?? '',
        'requestedByEmployeeName': employee?.name ?? '',
        'requestedByDeviceId': _auth.currentUser?.uid ?? '',
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'policyId': cleanPolicyId,
        'policyEvaluationMode': 'offline',
        'policyDecisionReasonCode': 'offline',
        'policyDecisionMessage':
            'La autorizacion automatica requiere conexion.',
        'policyEvaluationReason':
            'La autorizacion automatica requiere conexion.',
        'autoApproved': false,
        'wouldAutoApprove': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }
    await _submitLocalExpensePolicyRequest(
      cashSessionId: cashSessionId,
      businessDate: session.businessDate,
      amount: amount,
      reason: reason,
      policyId: cleanPolicyId,
      paymentSource: paymentSource,
      supplierId: supplierId,
      hasReceipt: hasReceipt,
      employee: employee,
    );
  }

  Future<Map<String, dynamic>> _submitLocalExpensePolicyRequest({
    required String cashSessionId,
    required String businessDate,
    required double amount,
    required String reason,
    required String policyId,
    required String paymentSource,
    required String supplierId,
    required bool hasReceipt,
    required Employee? employee,
  }) async {
    final authStatus = await _expenseRequestAuthSession.ensureReady();
    if (!authStatus.ready) {
      throw StateError(
        authStatus.errorMessage ??
            'No fue posible guardar el gasto. Intenta nuevamente.',
      );
    }
    try {
      await _expenseRequestDeviceSession.ensureReady();
    } catch (_) {
      throw StateError('Este dispositivo no esta registrado o activo.');
    }

    final clientRequestId = const Uuid().v4();
    final requestRef = _cashWithdrawalRequestsRef.doc(clientRequestId);
    final idempotencyRef = _restaurantRef
        .collection('expenseRequestIdempotency')
        .doc(clientRequestId);
    return _db.runTransaction((tx) async {
      final existingRequest = await tx.get(requestRef);
      if (existingRequest.exists) {
        final data = existingRequest.data() ?? {};
        return {
          'requestId': requestRef.id,
          'expenseId': requestRef.id,
          'status': data['status'],
          'autoApproved': data['autoApproved'] == true,
          'wouldAutoApprove': data['wouldAutoApprove'] == true,
          'policyId': data['policyId'],
          'policyVersion': data['policyVersion'],
          'reason': data['policyDecisionMessage'],
          'reasonCode': data['policyDecisionReasonCode'],
        };
      }

      final settingsDoc = await tx.get(_expensePolicySettingsRef);
      final policyRef = _expensePoliciesRef.doc(policyId);
      final policyDoc = await tx.get(policyRef);
      if (!policyDoc.exists) {
        throw StateError('La politica de gasto ya no existe.');
      }
      final policy = ExpensePolicy.fromMap(policyDoc.id, policyDoc.data()!);
      if (!_matchesCurrentBranch(policy.branchId)) {
        throw StateError('La politica no corresponde a esta sucursal.');
      }

      final periodKey = expensePolicyPeriodKey(
        policy: policy,
        businessDate: businessDate,
      );
      final usageRef = _expensePolicyUsageRef.doc(
        expensePolicyUsageDocId(
          policyId: policy.id,
          branchId: policy.branchId,
          periodKey: periodKey,
        ),
      );
      final usageDoc = await tx.get(usageRef);
      final usage = ExpensePolicyUsage.fromMap(
        usageRef.id,
        usageDoc.data() ??
            {
              'policyId': policy.id,
              'branchId': policy.branchId,
              'periodKey': periodKey,
            },
      );
      final serverNow = FieldValue.serverTimestamp();
      final plan = buildLocalExpenseTransactionPlan(
        input: LocalExpenseRequestInput(
          restaurantId: AppSession.instance.currentRestaurantId,
          restaurantName: AppSession.instance.currentRestaurantName,
          branchId: AppSession.instance.currentBranchId,
          branchName: AppSession.instance.currentBranchName,
          cashSessionId: cashSessionId,
          businessDate: businessDate,
          amount: amount,
          reason: reason,
          policy: policy,
          settings: ExpensePolicySettings.fromMap(settingsDoc.data()),
          paymentSource: paymentSource,
          supplierId: supplierId,
          hasReceipt: hasReceipt,
          clientRequestId: clientRequestId,
          requesterId: employee?.id ?? '',
          requesterName: employee?.name ?? '',
          requesterRole: employee?.hasAdminAccess == true ? 'admin' : 'staff',
          deviceId: _auth.currentUser?.uid ?? '',
        ),
        usage: usage,
        serverTimestamp: serverNow,
      );
      tx.set(requestRef, plan.requestData);
      if (plan.usageData != null) {
        tx.set(usageRef, plan.usageData!, SetOptions(merge: true));
      }
      tx.set(
        _restaurantRef.collection('activityLog').doc(),
        plan.activityLogData,
      );
      tx.set(idempotencyRef, {
        'clientRequestId': clientRequestId,
        'requestId': requestRef.id,
        'result': plan.result(usage.amountUsed),
        'createdAt': serverNow,
        'uid': _auth.currentUser?.uid ?? '',
      });
      return plan.result(usage.amountUsed);
    });
  }

  Future<void> authorizeCashWithdrawal({
    required String requestId,
    required bool approved,
    String adminNotes = '',
  }) async {
    _requireCashWithdrawalAuthorizer();
    final docRef = _cashWithdrawalRequestsRef.doc(requestId);
    final doc = await docRef.get();
    if (!doc.exists) {
      throw StateError('La solicitud ya no existe.');
    }
    final request = CashWithdrawalRequest.fromDoc(doc);
    if (!request.isPending) {
      throw StateError('La solicitud ya fue atendida.');
    }
    final cleanNotes = adminNotes.trim();
    if (!approved && cleanNotes.isEmpty) {
      throw ArgumentError('Captura el motivo del rechazo.');
    }

    final employee = AppSession.instance.employee;
    await docRef.update({
      'status': approved ? 'approved' : 'rejected',
      'authorizedByEmployeeId': employee?.id ?? '',
      'authorizedByEmployeeName': employee?.name ?? '',
      'authorizedAt': FieldValue.serverTimestamp(),
      'adminNotes': cleanNotes,
      if (approved) ...{
        'approvedByEmployeeId': employee?.id ?? '',
        'approvedByEmployeeName': employee?.name ?? '',
        'approvedAt': FieldValue.serverTimestamp(),
      } else ...{
        'rejectedByEmployeeId': employee?.id ?? '',
        'rejectedByEmployeeName': employee?.name ?? '',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectReason': cleanNotes,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>> cancelCashWithdrawalRequest({
    required String requestId,
    required String reason,
  }) async {
    final cleanRequestId = requestId.trim();
    final cleanReason = reason.trim();
    if (cleanRequestId.isEmpty || cleanReason.isEmpty) {
      throw ArgumentError('Faltan datos para cancelar.');
    }
    final uid = _auth.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      throw StateError('No fue posible guardar el gasto. Intenta nuevamente.');
    }
    final expenseRef = _cashWithdrawalRequestsRef.doc(cleanRequestId);
    return _db.runTransaction((tx) async {
      final expenseDoc = await tx.get(expenseRef);
      if (!expenseDoc.exists) {
        throw StateError('La solicitud ya no existe.');
      }
      final data = expenseDoc.data() ?? {};
      if (data['cancelledAt'] != null || data['status'] == 'cancelled') {
        return {
          'requestId': cleanRequestId,
          'status': 'cancelled',
          'restored': false,
          'reason': 'already_cancelled',
        };
      }

      final policyId = (data['policyId'] as String? ?? '').trim();
      final policyVersion = data['policyVersion'] is num
          ? (data['policyVersion'] as num).toInt()
          : 0;
      final autoApproved = data['autoApproved'] == true;
      var restored = false;
      final now = FieldValue.serverTimestamp();
      if (policyId.isNotEmpty && autoApproved) {
        final policyRef = _expensePoliciesRef.doc(policyId);
        final policyDoc = await tx.get(policyRef);
        if (policyDoc.exists) {
          final policy = ExpensePolicy.fromMap(policyDoc.id, policyDoc.data()!);
          final periodKey = expensePolicyPeriodKey(
            policy: policy,
            businessDate: data['businessDate'] as String? ?? '',
          );
          final usageRef = _expensePolicyUsageRef.doc(
            expensePolicyUsageDocId(
              policyId: policy.id,
              branchId: policy.branchId,
              periodKey: periodKey,
            ),
          );
          final usageDoc = await tx.get(usageRef);
          final usage = ExpensePolicyUsage.fromMap(
            usageRef.id,
            usageDoc.data() ??
                {
                  'policyId': policy.id,
                  'branchId': policy.branchId,
                  'periodKey': periodKey,
                },
          );
          if (policy.restoreQuotaOnCancellation &&
              usage.expenseIds.contains(cleanRequestId)) {
            tx.set(
              usageRef,
              restoredUsageData(
                usage: usage,
                requestId: cleanRequestId,
                amount: data['amount'] is num
                    ? (data['amount'] as num).toDouble()
                    : 0,
                serverTimestamp: now,
              ),
              SetOptions(merge: true),
            );
            restored = true;
          }
        }
      }

      tx.update(
        expenseRef,
        buildCancelledExpenseUpdate(
          serverTimestamp: now,
          cancelledByUid: uid,
          reason: cleanReason,
          quotaRestored: restored,
          policyVersion: policyVersion,
        ),
      );
      tx.set(_restaurantRef.collection('activityLog').doc(), {
        'type': 'EXPENSE_CANCELLED_DEVICE',
        'expenseId': cleanRequestId,
        'policyId': policyId,
        'quotaRestored': restored,
        'reason': cleanReason,
        'uid': uid,
        'createdAt': now,
      });
      return {
        'requestId': cleanRequestId,
        'status': 'cancelled',
        'restored': restored,
      };
    });
  }

  Future<CashCloseBlockers> cashCloseBlockers(
    String cashSessionId, {
    void Function(CashCloseProgressStage stage)? onStageChanged,
  }) async {
    final sessionDoc = await _cashSessionsRef.doc(cashSessionId).get();
    if (!sessionDoc.exists) {
      throw StateError('La caja ya no existe.');
    }
    final session = CashSession.fromDoc(sessionDoc);
    return _cashCloseBlockersForSession(
      session,
      onStageChanged: onStageChanged,
    );
  }

  Future<GhostOrderReconciliationResult> reconcileGhostOrdersAndTableLinks({
    String restaurantId = AppConstants.restaurantId,
    required String branchId,
    String? businessDate,
    String triggeredBy = 'operational_reconciliation',
  }) async {
    if (restaurantId.trim() != AppConstants.restaurantId) {
      throw ArgumentError('El restaurante no corresponde a esta sesion.');
    }
    final effectiveBusinessDate = businessDate?.trim().isNotEmpty == true
        ? businessDate!.trim()
        : (await getOpenCashSession())?.businessDate ?? _currentBusinessDate();
    final candidates = await _ghostOrderCandidates(
      branchId: branchId,
      businessDate: effectiveBusinessDate,
    );
    final itemEntriesFuture = runInBatches<PosOrder, (String, List<OrderItem>)>(
      candidates,
      batchSize: 15,
      action: (order) async => (order.id, await getOrderItemsOnce(order.id)),
    );
    final paymentEntriesFuture =
        runInBatches<PosOrder, (String, List<Payment>)>(
          candidates,
          batchSize: 15,
          action: (order) async =>
              (order.id, await getOrderPaymentsOnce(order.id)),
        );
    final itemsByOrder = {
      for (final entry in await itemEntriesFuture) entry.$1: entry.$2,
    };
    final paymentsByOrder = {
      for (final entry in await paymentEntriesFuture) entry.$1: entry.$2,
    };
    final ghostCandidates = candidates.where(
      (order) => isGhostOrder(
        order,
        itemsByOrder[order.id] ?? const [],
        paymentsByOrder[order.id] ?? const [],
      ),
    );
    final repairs = await runInBatches<PosOrder, _GhostOrderRepair?>(
      ghostCandidates,
      batchSize: 10,
      action: (order) =>
          _autoCancelGhostOrderIfNeeded(order.id, triggeredBy: triggeredBy),
    );
    final cancelledOrderIds = repairs
        .whereType<_GhostOrderRepair>()
        .map((repair) => repair.orderId)
        .toList();
    final tablesReleasedWithGhostOrders = repairs
        .whereType<_GhostOrderRepair>()
        .where((repair) => repair.tableReleased)
        .length;
    final blockers = <OperationalOrderBlocker>[];
    for (final order in candidates) {
      final items = itemsByOrder[order.id] ?? const <OrderItem>[];
      final payments = paymentsByOrder[order.id] ?? const <Payment>[];
      final evaluation = evaluateGhostOrder(order, items, payments);
      if (evaluation.isGhost && !cancelledOrderIds.contains(order.id)) {
        blockers.add(
          OperationalOrderBlocker(
            order: order,
            reason: 'orden ambigua; requiere revision',
            activeItemCount: evaluation.activeItemsCount,
            activePaymentCount: evaluation.activePaymentsCount,
          ),
        );
        continue;
      }
      final blocker = evaluateOperationalOrderBlocker(
        order: order,
        items: items,
        payments: payments,
        belongsToBranchAndDate: true,
      );
      if (blocker != null) blockers.add(blocker);
    }
    final cleanup = await _reconcileStaleTableOrderLinks(
      businessDate: effectiveBusinessDate,
      blockers: blockers,
      triggeredBy: triggeredBy,
    );
    if (cancelledOrderIds.isNotEmpty || cleanup.released > 0) {
      invalidateReportDataCache(
        branchId: branchId,
        startBusinessDate: effectiveBusinessDate,
        endBusinessDate: effectiveBusinessDate,
      );
    }
    return GhostOrderReconciliationResult(
      businessDate: effectiveBusinessDate,
      branchId: branchId,
      candidatesChecked: candidates.length,
      cancelledOrderIds: cancelledOrderIds,
      staleTableLinks: cleanup.stale,
      releasedTableLinks: tablesReleasedWithGhostOrders + cleanup.released,
    );
  }

  Future<List<PosOrder>> _ghostOrderCandidates({
    required String branchId,
    required String businessDate,
  }) async {
    final startDate = DateTime.parse(businessDate);
    final endExclusive = startDate.add(const Duration(days: 1));
    final snapshots = await Future.wait([
      _ordersRef.where('businessDate', isEqualTo: businessDate).get(),
      _ordersRef.where('operationalDate', isEqualTo: businessDate).get(),
      _ordersRef
          .where('createdAt', isGreaterThanOrEqualTo: startDate)
          .where('createdAt', isLessThan: endExclusive)
          .get(),
      _ordersRef
          .where('updatedAt', isGreaterThanOrEqualTo: startDate)
          .where('updatedAt', isLessThan: endExclusive)
          .get(),
      _ordersRef
          .where('paidAt', isGreaterThanOrEqualTo: startDate)
          .where('paidAt', isLessThan: endExclusive)
          .get(),
    ]);
    final docsByPath = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        docsByPath[doc.reference.path] = doc;
      }
    }
    return docsByPath.values
        .map(PosOrder.fromDoc)
        .where((order) => _matchesBranch(order.branchId, branchId))
        .where((order) => _orderBelongsToBusinessDate(order, businessDate))
        .where(isActiveOrderState)
        .toList();
  }

  Future<_GhostOrderRepair?> _autoCancelGhostOrderIfNeeded(
    String orderId, {
    required String triggeredBy,
  }) async {
    final orderRef = _ordersRef.doc(orderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists) return null;
    final order = PosOrder.fromDoc(orderDoc);
    final detail = await Future.wait([
      orderRef.collection('items').get(),
      orderRef.collection('payments').get(),
    ]);
    final items = detail[0].docs.map(OrderItem.fromDoc).toList();
    final payments = detail[1].docs
        .map((doc) => _paymentFromOrderPaymentDoc(doc, order))
        .toList();
    final evaluation = evaluateGhostOrder(order, items, payments);
    if (!evaluation.isGhost) return null;
    final employee = AppSession.instance.employee;
    final cancellationItem = items
        .where((item) {
          return !isActiveOrderItem(item) &&
              ((item.cancelAcceptedByEmployeeId?.trim().isNotEmpty ?? false) ||
                  (item.cancelledByEmployeeId?.trim().isNotEmpty ?? false));
        })
        .fold<OrderItem?>(null, (latest, item) {
          if (latest == null) return item;
          final latestAt =
              latest.cancelAcceptedAt ??
              latest.cancelledAt ??
              latest.updatedAt ??
              DateTime(1970);
          final itemAt =
              item.cancelAcceptedAt ??
              item.cancelledAt ??
              item.updatedAt ??
              DateTime(1970);
          return itemAt.isAfter(latestAt) ? item : latest;
        });
    final cancellationEmployeeId =
        cancellationItem?.cancelAcceptedByEmployeeId?.trim().isNotEmpty == true
        ? cancellationItem!.cancelAcceptedByEmployeeId!.trim()
        : cancellationItem?.cancelledByEmployeeId?.trim().isNotEmpty == true
        ? cancellationItem!.cancelledByEmployeeId!.trim()
        : employee?.id ?? '';
    final cancellationEmployeeName =
        cancellationItem?.cancelAcceptedByEmployeeName?.trim().isNotEmpty ==
            true
        ? cancellationItem!.cancelAcceptedByEmployeeName!.trim()
        : cancellationItem?.cancelledByEmployeeName?.trim().isNotEmpty == true
        ? cancellationItem!.cancelledByEmployeeName!.trim()
        : employee?.name ?? '';
    final tableRefs = orderUsesPhysicalTables(order)
        ? order.linkedTableIds.map(_tablesRef.doc).toList()
        : const <DocumentReference<Map<String, dynamic>>>[];

    final repair = await _db.runTransaction<_GhostOrderRepair?>((
      transaction,
    ) async {
      final freshOrderDoc = await transaction.get(orderRef);
      if (!freshOrderDoc.exists) return null;
      final freshOrder = PosOrder.fromDoc(freshOrderDoc);
      if (!isActiveOrderState(freshOrder) ||
          !_sameInstant(freshOrder.updatedAt, order.updatedAt)) {
        return null;
      }
      final linkedTables = <PosTable>[];
      for (final tableRef in tableRefs) {
        final tableDoc = await transaction.get(tableRef);
        if (tableDoc.exists) linkedTables.add(PosTable.fromDoc(tableDoc));
      }
      final tablesToRelease = linkedTables
          .where(
            (table) => shouldReleaseTableForGhostOrder(
              order: freshOrder,
              table: table,
            ),
          )
          .toList();
      final now = FieldValue.serverTimestamp();
      transaction.update(orderRef, {
        'status': 'cancelled',
        'paymentStatus': 'cancelled',
        'cancelStatus': 'accepted',
        'cancelReason': 'Todos los productos de la orden fueron cancelados',
        'cancelledAt': now,
        'cancelledByEmployeeId': cancellationEmployeeId,
        'cancelledByEmployeeName': cancellationEmployeeName,
        'total': 0.0,
        'grossSubtotal': 0.0,
        'netTotal': 0.0,
        'paidTotal': 0.0,
        'pendingTotal': 0.0,
        'updatedAt': now,
      });
      for (final table in tablesToRelease) {
        transaction.set(_tablesRef.doc(table.id), {
          'status': 'available',
          'currentOrderId': null,
          'currentOrderStatus': null,
          'tableGroupId': null,
          'tableGroupLabel': null,
          'groupPrimaryTableId': null,
          'occupiedAt': null,
          'updatedAt': now,
        }, SetOptions(merge: true));
      }
      final folio = _shortLogFolio(freshOrder.id);
      transaction.set(_restaurantRef.collection('activityLog').doc(), {
        'type': 'ghost_order_auto_cancelled',
        'actionType': 'ghost_order_auto_cancelled',
        'message':
            'Se canceló automáticamente la orden $folio porque todos sus productos estaban cancelados.',
        'orderId': freshOrder.id,
        'folio': folio,
        'tableId': freshOrder.tableId,
        'tableName': freshOrder.tableName,
        'restaurantId': freshOrder.restaurantId,
        'restaurantName': freshOrder.restaurantName,
        'branchId': freshOrder.branchId,
        'branchName': freshOrder.branchName,
        'businessDate':
            _businessDateForOrder(freshOrder) ?? _currentBusinessDate(),
        'previousStatus': freshOrder.status,
        'previousPaymentStatus': freshOrder.paymentStatus,
        'activeItemsCount': evaluation.activeItemsCount,
        'activePaymentsCount': evaluation.activePaymentsCount,
        'cancelledItemsCount': evaluation.cancelledItemsCount,
        'triggeredBy': triggeredBy,
        'employeeId': cancellationEmployeeId,
        'employeeName': cancellationEmployeeName,
        'timestamp': now,
        'createdAt': now,
        'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      });
      if (tablesToRelease.isNotEmpty) {
        transaction.set(_restaurantRef.collection('activityLog').doc(), {
          'type': 'stale_table_link_cleared',
          'actionType': 'stale_table_link_cleared',
          'message':
              'Se liberó ${freshOrder.displayName} al cancelar automáticamente la orden $folio.',
          'orderId': freshOrder.id,
          'folio': folio,
          'tableId': freshOrder.tableId,
          'tableName': freshOrder.tableName,
          'branchId': freshOrder.branchId,
          'branchName': freshOrder.branchName,
          'businessDate':
              _businessDateForOrder(freshOrder) ?? _currentBusinessDate(),
          'triggeredBy': triggeredBy,
          'employeeId': cancellationEmployeeId,
          'employeeName': cancellationEmployeeName,
          'timestamp': now,
          'createdAt': now,
          'createdBy': _auth.currentUser?.uid ?? 'anonymous',
        });
        if (freshOrder.isTableGroup) {
          transaction.set(_restaurantRef.collection('activityLog').doc(), {
            'type': 'table_group_released',
            'actionType': 'table_group_released',
            'orderId': freshOrder.id,
            'folio': folio,
            'tableIds': freshOrder.linkedTableIds,
            'tableNames': freshOrder.tableNames,
            'tableGroupLabel': freshOrder.displayName,
            ..._currentBranchFields,
            'businessDate':
                _businessDateForOrder(freshOrder) ?? _currentBusinessDate(),
            'employeeId': cancellationEmployeeId,
            'employeeName': cancellationEmployeeName,
            'timestamp': now,
            'createdAt': now,
          });
        }
      }
      return _GhostOrderRepair(
        orderId: freshOrder.id,
        tableReleased: tablesToRelease.isNotEmpty,
      );
    });
    if (repair != null) {
      invalidateReportDataCache(
        branchId: order.branchId,
        startBusinessDate: _businessDateForOrder(order),
        endBusinessDate: _businessDateForOrder(order),
      );
    }
    return repair;
  }

  bool _sameInstant(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == b;
    return a.microsecondsSinceEpoch == b.microsecondsSinceEpoch;
  }

  Future<CashCloseBlockers> _cashCloseBlockersForSession(
    CashSession session, {
    void Function(CashCloseProgressStage stage)? onStageChanged,
  }) async {
    onStageChanged?.call(CashCloseProgressStage.validatingOrders);
    final operationalSummary = await getOperationalOpenOrdersSummary(
      businessDate: session.businessDate,
      cashSessionId: session.id,
      reconcileTables: true,
    );
    onStageChanged?.call(CashCloseProgressStage.validatingKitchen);
    var pendingKitchenItemCount = 0;
    for (final blocker in operationalSummary.blockers) {
      final itemsSnapshot = await _ordersRef
          .doc(blocker.order.id)
          .collection('items')
          .get();
      for (final item in itemsSnapshot.docs.map(OrderItem.fromDoc)) {
        if (isKitchenPendingItem(item)) {
          pendingKitchenItemCount += item.qty;
        }
      }
    }

    final kitchenSessions = await _kitchenSessionsForBusinessDate(
      session.businessDate,
    );
    var hasValidClosedKitchen = false;
    var hasIncompleteClosedKitchen = false;
    for (final kitchenSession in kitchenSessions) {
      if (!kitchenSession.isClosed) {
        continue;
      }
      if (await _kitchenCloseIsComplete(kitchenSession.id)) {
        hasValidClosedKitchen = true;
        break;
      }
      hasIncompleteClosedKitchen = true;
    }
    final kitchenNotClosed =
        !hasValidClosedKitchen && !hasIncompleteClosedKitchen;
    final kitchenCloseIncomplete =
        !hasValidClosedKitchen && hasIncompleteClosedKitchen;

    return CashCloseBlockers(
      openTableCount: operationalSummary.openTableCount,
      openTakeoutCount: operationalSummary.openTakeoutCount,
      openStandingCount: operationalSummary.openStandingCount,
      pendingKitchenItemCount: pendingKitchenItemCount,
      pendingPaymentCount: operationalSummary.pendingPaymentCount,
      kitchenNotClosed: kitchenNotClosed,
      kitchenCloseIncomplete: kitchenCloseIncomplete,
      operationalSummary: operationalSummary,
    );
  }

  Future<OperationalOpenOrdersSummary> getOperationalOpenOrdersSummary({
    String? businessDate,
    String? cashSessionId,
    bool reconcileTables = false,
    bool forceRefresh = false,
  }) async {
    final branchId = AppSession.instance.currentBranchId;
    final effectiveBusinessDate = businessDate?.trim().isNotEmpty == true
        ? businessDate!.trim()
        : (await getOpenCashSession())?.businessDate ?? _currentBusinessDate();
    final reconciliation = reconcileTables
        ? await reconcileGhostOrdersAndTableLinks(
            branchId: branchId,
            businessDate: effectiveBusinessDate,
            triggeredBy: 'operational_summary',
          )
        : null;
    final reportData = await getReportDataBundle(
      branchId: branchId,
      startBusinessDate: effectiveBusinessDate,
      endBusinessDate: effectiveBusinessDate,
      includeItems: true,
      forceRefresh: forceRefresh,
      reportName: 'OperationalOpenOrders',
    );
    final linkedSnapshot = cashSessionId?.trim().isNotEmpty == true
        ? await _ordersRef
              .where('cashSessionId', isEqualTo: cashSessionId!.trim())
              .get()
        : null;
    final ordersById = {
      for (final order in reportData.orders) order.id: order,
      if (linkedSnapshot != null)
        for (final doc in linkedSnapshot.docs) doc.id: PosOrder.fromDoc(doc),
    };
    final extraOrders = ordersById.values
        .where((order) => !reportData.itemsByOrder.containsKey(order.id))
        .toList();
    final extraItemsFuture = runInBatches<PosOrder, (String, List<OrderItem>)>(
      extraOrders,
      batchSize: 15,
      action: (order) async => (order.id, await getOrderItemsOnce(order.id)),
    );
    final extraPaymentsFuture = runInBatches<PosOrder, (String, List<Payment>)>(
      extraOrders,
      batchSize: 15,
      action: (order) async => (
        order.id,
        await _ordersRef
            .doc(order.id)
            .collection('payments')
            .get()
            .then(
              (snapshot) => snapshot.docs
                  .map((doc) => _paymentFromOrderPaymentDoc(doc, order))
                  .toList(),
            ),
      ),
    );
    final itemsByOrder = Map<String, List<OrderItem>>.from(
      reportData.itemsByOrder,
    );
    final paymentsByOrder = Map<String, List<Payment>>.from(
      reportData.paymentsByOrder,
    );
    for (final entry in await extraItemsFuture) {
      itemsByOrder[entry.$1] = entry.$2;
    }
    for (final entry in await extraPaymentsFuture) {
      paymentsByOrder[entry.$1] = entry.$2;
    }
    final discardedReasons = <String, int>{};
    final blockers = <OperationalOrderBlocker>[];
    var ordersChecked = 0;

    for (final order in ordersById.values) {
      final membership = belongsToOperationalSession(
        order: order,
        selectedCashSessionId: cashSessionId?.trim() ?? '',
        selectedBusinessDate: effectiveBusinessDate,
        branchId: branchId,
      );
      final belongsToScope = membership.included;
      if (!belongsToScope) continue;

      ordersChecked++;
      final items = itemsByOrder[order.id] ?? const [];
      final payments = paymentsByOrder[order.id] ?? const [];
      final blocker = evaluateOperationalOrderBlocker(
        order: order,
        items: items,
        payments: payments,
        belongsToBranchAndDate: belongsToScope,
      );
      if (blocker == null) {
        final reason = operationalDiscardReason(
          order: order,
          items: items,
          payments: payments,
          belongsToBranchAndDate: belongsToScope,
        );
        discardedReasons[reason] = (discardedReasons[reason] ?? 0) + 1;
      } else {
        blockers.add(blocker);
      }
    }

    blockers.sort((a, b) {
      final aDate = a.order.createdAt ?? DateTime(1970);
      final bDate = b.order.createdAt ?? DateTime(1970);
      return aDate.compareTo(bDate);
    });

    final summary = OperationalOpenOrdersSummary(
      businessDate: effectiveBusinessDate,
      branchId: branchId,
      cashSessionId: cashSessionId?.trim() ?? '',
      ordersChecked: ordersChecked,
      discardedReasons: discardedReasons,
      staleTableLinks: reconciliation?.staleTableLinks ?? 0,
      releasedTableLinks: reconciliation?.releasedTableLinks ?? 0,
      blockers: blockers,
    );
    _debugOperationalBlockers(summary);
    _debugOperationalViewer(summary);
    return summary;
  }

  Future<T> _cashCloseStage<T>({
    required CashCloseProgressStage stage,
    required String operation,
    required String documentPath,
    required Future<T> Function() action,
    void Function(CashCloseProgressStage stage)? onStageChanged,
  }) async {
    onStageChanged?.call(stage);
    try {
      return await action();
    } catch (error, stackTrace) {
      throw CashCloseException(
        stage: stage,
        operation: operation,
        documentPath: documentPath,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<CashSession> closeCashSession({
    required String cashSessionId,
    required double countedCashAmount,
    required double terminalReportedAmount,
    required String notes,
    void Function(CashCloseProgressStage stage)? onStageChanged,
  }) async {
    _requireCashManager();
    if (!isValidCashCloseAmount(countedCashAmount) ||
        !isValidCashCloseAmount(terminalReportedAmount)) {
      throw ArgumentError('Los montos de cierre deben ser numeros validos.');
    }

    final docRef = _cashSessionsRef.doc(cashSessionId);
    final doc = await _cashCloseStage(
      stage: CashCloseProgressStage.validatingOrders,
      operation: 'read_cash_session',
      documentPath: docRef.path,
      onStageChanged: onStageChanged,
      action: docRef.get,
    );
    if (!doc.exists) {
      throw StateError('La caja ya no existe.');
    }

    final session = CashSession.fromDoc(doc);
    if (!canFinalizeCashSessionClose(
      status: session.status,
      hasClosedAt: session.closedAt != null,
    )) {
      throw StateError('Esta caja ya fue cerrada.');
    }

    final blockers = await _cashCloseStage(
      stage: CashCloseProgressStage.validatingOrders,
      operation: 'validate_cash_close_blockers',
      documentPath: docRef.path,
      onStageChanged: onStageChanged,
      action: () =>
          _cashCloseBlockersForSession(session, onStageChanged: onStageChanged),
    );
    if (!blockers.canClose) {
      throw StateError('${blockers.message}\n${blockers.detail}');
    }

    final pendingWithdrawals = await _cashCloseStage(
      stage: CashCloseProgressStage.validatingOrders,
      operation: 'validate_pending_withdrawals',
      documentPath: _cashWithdrawalRequestsRef.path,
      onStageChanged: onStageChanged,
      action: () => _pendingCashWithdrawalRequestsForClose(
        cashSessionId: cashSessionId,
        businessDate: session.businessDate,
      ),
    );
    if (pendingWithdrawals.isNotEmpty) {
      throw StateError(
        'No puedes cerrar caja. Hay solicitudes de gasto pendientes de autorizacion.',
      );
    }

    final totals = await _cashCloseStage(
      stage: CashCloseProgressStage.calculating,
      operation: 'calculate_cash_totals',
      documentPath: docRef.path,
      onStageChanged: onStageChanged,
      action: () => _cashSessionTotalsOnce(cashSessionId),
    );
    final totalCountedRealMoney = totals.totalCountedRealMoney(
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
    );
    final cashDifference = totals.cashDifference(countedCashAmount);
    final cardDifference = totals.cardDifference(terminalReportedAmount);
    final netDifference = totals.netDifference(
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
    );
    final shortageAmount = totals.shortageAmount(
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
    );
    final overAmount = totals.overAmount(
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
    );
    final employee = AppSession.instance.employee;

    final closeTimestamp = FieldValue.serverTimestamp();
    final closeData = <String, Object?>{
      ...cashSessionCloseTimestampFields(
        currentStatus: session.status,
        currentClosedAt: session.closedAt,
        serverTimestamp: closeTimestamp,
        employeeId: employee?.id ?? '',
        employeeName: employee?.name ?? '',
      ),
      'countedCashAmount': countedCashAmount,
      'terminalReportedAmount': terminalReportedAmount,
      'expectedCashAmount': totals.expectedCashAmount,
      'expectedCardChargedAmount': totals.expectedCardChargedAmount,
      'expectedCardBaseAmount': totals.expectedCardBaseAmount,
      'expectedCardSurchargeAmount': totals.expectedCardSurchargeAmount,
      'expectedCardFeeAbsorbedAmount': totals.expectedCardFeeAbsorbedAmount,
      'expectedPlatformAmount': totals.expectedPlatformAmount,
      'expectedEmployeeConsumptionAmount':
          totals.expectedEmployeeConsumptionAmount,
      'approvedWithdrawalsTotal': totals.approvedWithdrawalsTotal,
      'pendingWithdrawalsTotal': totals.pendingWithdrawalsTotal,
      'withdrawalRequestCount': totals.withdrawalRequestCount,
      'totalExpectedRealMoney': totals.totalExpectedRealMoney,
      'totalCountedRealMoney': totalCountedRealMoney,
      'cashDifference': cashDifference,
      'cardDifference': cardDifference,
      'netDifference': netDifference,
      'shortageAmount': shortageAmount,
      'overAmount': overAmount,
      'notes': notes.trim(),
    };
    _validateCashCloseFirestoreData(closeData);
    await _cashCloseStage(
      stage: CashCloseProgressStage.updatingCashSession,
      operation: 'update_cash_session',
      documentPath: docRef.path,
      onStageChanged: onStageChanged,
      action: () => _db.runTransaction((transaction) async {
        final freshDoc = await transaction.get(docRef);
        if (!freshDoc.exists) {
          throw StateError('La caja ya no existe.');
        }
        final freshSession = CashSession.fromDoc(freshDoc);
        if (!canFinalizeCashSessionClose(
          status: freshSession.status,
          hasClosedAt: freshSession.closedAt != null,
        )) {
          throw StateError('Esta caja ya fue cerrada.');
        }
        transaction.update(docRef, closeData);
      }),
    );

    if (netDifference < 0) {
      final activityRef = _restaurantRef.collection('activityLog').doc();
      try {
        await _cashCloseStage(
          stage: CashCloseProgressStage.registeringActivityLog,
          operation: 'create_cash_close_shortage_activity_log',
          documentPath: activityRef.path,
          onStageChanged: onStageChanged,
          action: () => activityRef.set({
            'type': 'cash_close_shortage',
            ..._currentBranchFields,
            'cashSessionId': cashSessionId,
            'businessDate': session.businessDate,
            'shortageAmount': shortageAmount,
            'netDifference': netDifference,
            ..._employeeAuditFields(prefix: 'createdBy'),
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': _auth.currentUser?.uid ?? 'anonymous',
          }),
        );
      } catch (error, stackTrace) {
        debugPrintCashCloseFailure(
          error: error,
          stackTrace: stackTrace,
          businessDate: session.businessDate,
          cashSessionId: cashSessionId,
          countedCashAmount: countedCashAmount,
          terminalReportedAmount: terminalReportedAmount,
        );
      }
    }

    final updatedDoc = await _cashCloseStage(
      stage: CashCloseProgressStage.updatingCashSession,
      operation: 'read_closed_cash_session',
      documentPath: docRef.path,
      onStageChanged: onStageChanged,
      action: docRef.get,
    );
    invalidateReportDataCache(
      branchId: session.branchId,
      startBusinessDate: session.businessDate,
      endBusinessDate: session.businessDate,
    );
    invalidateCashScheduleCache(branchId: session.branchId);
    return CashSession.fromDoc(updatedDoc);
  }

  void _validateCashCloseFirestoreData(Map<String, Object?> data) {
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is num && !value.isFinite) {
        throw ArgumentError(
          'Existe informacion invalida en el corte: ${entry.key}.',
        );
      }
    }
  }

  Future<HistoricalCashCorrectionPreview> previewHistoricalCashCorrection({
    required Branch branch,
    required String businessDate,
    required double countedCashAmount,
    required double terminalReportedAmount,
    required String adminPin,
    double? openingCashAmount,
  }) async {
    return recalculateHistoricalCashSessionWithoutPaymentGroupIndex(
      branch: branch,
      businessDate: businessDate,
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
      adminPin: adminPin,
      openingCashAmount: openingCashAmount,
    );
  }

  Future<HistoricalCashCorrectionPreview>
  recalculateHistoricalCashSessionWithoutPaymentGroupIndex({
    required Branch branch,
    required String businessDate,
    required double countedCashAmount,
    required double terminalReportedAmount,
    required String adminPin,
    double? openingCashAmount,
  }) async {
    _requireHistoricalCashCorrectionAdmin();
    _requireHistoricalCashCorrectionPin(adminPin);
    _validateHistoricalCashCorrectionInput(
      branch: branch,
      businessDate: businessDate,
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
      openingCashAmount: openingCashAmount,
    );
    return _historicalCashCorrectionPreview(
      branch: branch,
      businessDate: businessDate.trim(),
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
      openingCashAmount: openingCashAmount,
    );
  }

  Future<CashSession> saveHistoricalCashCorrection({
    required Branch branch,
    required String businessDate,
    required double countedCashAmount,
    required double terminalReportedAmount,
    required String notes,
    required String adminPin,
    double? openingCashAmount,
  }) async {
    _requireHistoricalCashCorrectionAdmin();
    _requireHistoricalCashCorrectionPin(adminPin);
    _validateHistoricalCashCorrectionInput(
      branch: branch,
      businessDate: businessDate,
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
      openingCashAmount: openingCashAmount,
    );

    final preview = await _historicalCashCorrectionPreview(
      branch: branch,
      businessDate: businessDate.trim(),
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
      openingCashAmount: openingCashAmount,
    );
    final employee = AppSession.instance.employee;
    final docRef = _cashSessionsRef.doc(preview.cashSessionId);
    final existing = preview.existingSession;
    final correctionNotes = notes.trim();
    final branchFields = _branchFields(branch);
    final now = FieldValue.serverTimestamp();

    await docRef.set({
      'id': docRef.id,
      'businessDate': preview.businessDate,
      ...branchFields,
      'status': 'closed',
      'openingCashAmount': preview.openingCashAmount,
      ...preservedHistoricalCashTimestampFields(existing),
      'countedCashAmount': preview.countedCashAmount,
      'terminalReportedAmount': preview.terminalReportedAmount,
      'expectedCashAmount': preview.expectedCashAmount,
      'expectedCardChargedAmount': preview.cardSalesAmount,
      'expectedCardBaseAmount': preview.cardBaseAmount,
      'expectedCardSurchargeAmount': preview.cardSurchargeAmount,
      'expectedCardFeeAbsorbedAmount': preview.cardCommissionAmount,
      'expectedPlatformAmount': preview.platformAmount,
      'expectedEmployeeConsumptionAmount': preview.employeeConsumptionAmount,
      'approvedWithdrawalsTotal': preview.approvedWithdrawalsTotal,
      'pendingWithdrawalsTotal': preview.pendingWithdrawalsTotal,
      'withdrawalRequestCount': preview.withdrawalRequestCount,
      'totalExpectedRealMoney': preview.totalExpectedRealMoney,
      'totalCountedRealMoney': preview.totalCountedRealMoney,
      'cashDifference': preview.cashDifference,
      'cardDifference': preview.cardDifference,
      'netDifference': preview.netDifference,
      'shortageAmount': preview.shortageAmount,
      'overAmount': preview.overAmount,
      'notes': correctionNotes,
      'correctionMode': true,
      'correctionReason': correctionNotes,
      'correctionNotes': correctionNotes,
      'correctedAt': now,
      'correctedByEmployeeId': employee?.id ?? '',
      'correctedByEmployeeName': employee?.name ?? '',
      'oldCashSessionId': existing?.id,
      if (existing == null) 'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    await _restaurantRef.collection('activityLog').add({
      'type': 'cash_session_historical_correction',
      'actionType': 'cash_session_historical_correction',
      ...branchFields,
      'businessDate': preview.businessDate,
      'oldCashSessionId': existing?.id ?? '',
      'newCashSessionId': docRef.id,
      'timestamp': FieldValue.serverTimestamp(),
      'message':
          'Se rehizo el corte historico de la sucursal ${branch.name} para la fecha ${preview.businessDate}',
      'employeeId': employee?.id ?? '',
      'employeeName': employee?.name ?? '',
      ..._employeeAuditFields(prefix: 'createdBy'),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
    });

    final updatedDoc = await docRef.get();
    invalidateReportDataCache(
      branchId: branch.id,
      startBusinessDate: preview.businessDate,
      endBusinessDate: preview.businessDate,
    );
    invalidateCashScheduleCache(branchId: branch.id);
    return CashSession.fromDoc(updatedDoc);
  }

  Future<HistoricalCashExpenseResult> addApprovedHistoricalCashExpense({
    required String cashSessionId,
    required double amount,
    required String reason,
    required String adminPin,
    required String idempotencyKey,
  }) async {
    _requireHistoricalCashExpenseAdmin();
    _requireHistoricalCashCorrectionPin(adminPin);
    if (cashSessionId.trim().isEmpty) {
      throw ArgumentError('Selecciona un corte cerrado.');
    }
    if (amount <= 0) {
      throw ArgumentError('Captura un importe de gasto valido.');
    }
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Captura el comentario del gasto.');
    }
    final cleanKey = idempotencyKey.trim();
    if (cleanKey.isEmpty) {
      throw ArgumentError('No se pudo preparar el registro del gasto.');
    }

    final sessionRef = _cashSessionsRef.doc(cashSessionId.trim());
    final sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) {
      throw StateError(
        'No existe un corte cerrado para esta fecha. Utiliza primero la opcion Rehacer corte historico.',
      );
    }
    final session = CashSession.fromDoc(sessionDoc);
    if (session.isOpen || session.status != 'closed') {
      throw StateError('El corte debe estar cerrado.');
    }
    final selectedDate = _dateFromBusinessDate(session.businessDate);
    if (selectedDate == null) {
      throw StateError('La fecha operativa del corte no es valida.');
    }
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    if (selectedDate.isAfter(todayOnly)) {
      throw StateError('La fecha operativa no puede ser futura.');
    }
    if (session.branchId.trim().isEmpty) {
      throw StateError('La sucursal del corte no esta identificada.');
    }

    final branch = Branch(
      id: session.branchId,
      name: session.branchName,
      normalizedName: normalizeBranchName(session.branchName),
      active: true,
      sortOrder: 0,
      restaurantId: session.restaurantId,
      restaurantName: session.restaurantName,
    );
    final withdrawalRef = _cashWithdrawalRequestsRef.doc(
      'historical_${session.id}_$cleanKey',
    );
    final activityRef = _restaurantRef.collection('activityLog').doc();
    final employee = AppSession.instance.employee;
    final now = FieldValue.serverTimestamp();
    final branchFields = _branchFields(branch);

    await _db.runTransaction((transaction) async {
      final freshSessionDoc = await transaction.get(sessionRef);
      if (!freshSessionDoc.exists) {
        throw StateError(
          'No existe un corte cerrado para esta fecha. Utiliza primero la opcion Rehacer corte historico.',
        );
      }
      final freshSession = CashSession.fromDoc(freshSessionDoc);
      if (freshSession.isOpen || freshSession.status != 'closed') {
        throw StateError('El corte debe estar cerrado.');
      }
      if (!_matchesBranch(freshSession.branchId, session.branchId) ||
          freshSession.businessDate != session.businessDate) {
        throw StateError(
          'El corte seleccionado cambio. Recarga e intenta de nuevo.',
        );
      }

      final existingWithdrawal = await transaction.get(withdrawalRef);
      if (existingWithdrawal.exists) {
        return;
      }

      transaction.set(withdrawalRef, {
        'id': withdrawalRef.id,
        'restaurantId': freshSession.restaurantId,
        'restaurantName': freshSession.restaurantName,
        'cashSessionId': freshSession.id,
        'linkedCashSessionId': freshSession.id,
        'businessDate': freshSession.businessDate,
        ...branchFields,
        'amount': amount,
        'reason': cleanReason,
        'notes': cleanReason,
        'status': 'approved',
        'requestedByEmployeeId': employee?.id ?? '',
        'requestedByEmployeeName': employee?.name ?? '',
        'requestedAt': now,
        'authorizedByEmployeeId': employee?.id ?? '',
        'authorizedByEmployeeName': employee?.name ?? '',
        'authorizedAt': now,
        'adminNotes': cleanReason,
        'approvedByEmployeeId': employee?.id ?? '',
        'approvedByEmployeeName': employee?.name ?? '',
        'approvedAt': now,
        'rejectedAt': null,
        'rejectedByEmployeeId': null,
        'rejectedByEmployeeName': null,
        'rejectReason': null,
        'source': 'historical_admin',
        'sourceName': 'Gasto historico administrativo',
        'isHistorical': true,
        'idempotencyKey': cleanKey,
        'createdAt': now,
        'updatedAt': now,
      });

      transaction.set(activityRef, {
        'type': 'historical_cash_expense_added',
        'actionType': 'historical_cash_expense_added',
        ...branchFields,
        'cashSessionId': freshSession.id,
        'withdrawalRequestId': withdrawalRef.id,
        'amount': amount,
        'reason': cleanReason,
        'previousApprovedWithdrawals': freshSession.approvedWithdrawalsTotal,
        'newApprovedWithdrawals': freshSession.approvedWithdrawalsTotal,
        'previousExpectedCash': freshSession.expectedCashAmount,
        'newExpectedCash': freshSession.expectedCashAmount,
        'previousCashDifference': freshSession.cashDifference,
        'newCashDifference': freshSession.cashDifference,
        'countedCashPreserved': freshSession.countedCashAmount,
        'terminalReportedPreserved': freshSession.terminalReportedAmount,
        'cashSessionSnapshotPreserved': true,
        'employeeId': employee?.id ?? '',
        'employeeName': employee?.name ?? '',
        'businessDate': freshSession.businessDate,
        'timestamp': now,
        'message':
            'Se agrego un gasto administrativo de \$${amount.toStringAsFixed(2)} para la sucursal ${freshSession.branchName} del dia ${freshSession.businessDate} sin modificar el corte cerrado.',
        ..._employeeAuditFields(prefix: 'createdBy'),
        'createdAt': now,
        'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      });
    });

    final updatedDoc = await sessionRef.get();
    final updatedSession = CashSession.fromDoc(updatedDoc);
    invalidateReportDataCache(
      branchId: session.branchId,
      startBusinessDate: session.businessDate,
      endBusinessDate: session.businessDate,
    );
    return HistoricalCashExpenseResult(
      cashSession: updatedSession,
      withdrawalRequestId: withdrawalRef.id,
      previousApprovedWithdrawals: session.approvedWithdrawalsTotal,
      newApprovedWithdrawals: updatedSession.approvedWithdrawalsTotal,
      previousExpectedCash: session.expectedCashAmount,
      newExpectedCash: updatedSession.expectedCashAmount,
      previousCashDifference: session.cashDifference,
      newCashDifference: updatedSession.cashDifference,
    );
  }

  Future<HistoricalCashCorrectionPreview> _historicalCashCorrectionPreview({
    required Branch branch,
    required String businessDate,
    required double countedCashAmount,
    required double terminalReportedAmount,
    double? openingCashAmount,
    double extraWithdrawalAmount = 0,
  }) async {
    final existingSession = await _cashSessionForBranchAndDate(
      branch: branch,
      businessDate: businessDate,
    );
    final selectedCashSessionId = existingSession?.id ?? '';
    if (kDebugMode) {
      debugPrint(
        'CUT_RECALC_SCOPE selectedBusinessDate=$businessDate '
        'selectedCashSessionId=${selectedCashSessionId.isEmpty ? 'not_found' : selectedCashSessionId} '
        'branchId=${branch.id}',
      );
    }
    developer.log(
      'CUT_RECALC_SCOPE selectedBusinessDate=$businessDate '
      'selectedCashSessionId=${selectedCashSessionId.isEmpty ? 'not_found' : selectedCashSessionId} '
      'branchId=${branch.id}',
      name: 'TacoPOS.cashCorrection',
    );
    final payments = await _paymentsForBranchAndBusinessDate(
      branch: branch,
      businessDate: businessDate,
      selectedCashSessionId: selectedCashSessionId,
      selectedCashSession: existingSession,
    );
    final withdrawals = await _withdrawalsForBranchAndBusinessDate(
      branch: branch,
      businessDate: businessDate,
      selectedCashSessionId: selectedCashSessionId,
    );
    final resolvedOpeningCashAmount =
        openingCashAmount ?? existingSession?.openingCashAmount ?? 0.0;
    final totals = _totalsForPayments(
      payments,
      openingCashAmount: resolvedOpeningCashAmount,
      withdrawals: withdrawals,
      extraApprovedWithdrawalAmount: extraWithdrawalAmount,
    );
    developer.log(
      'Recalculo historico totales fecha=$businessDate branchId=${branch.id} '
      'pagos=${payments.length} efectivo=${totals.expectedCashAmount - resolvedOpeningCashAmount + totals.approvedWithdrawalsTotal} '
      'tarjeta=${totals.expectedCardChargedAmount} plataforma=${totals.expectedPlatformAmount} '
      'consumoEmpleado=${totals.expectedEmployeeConsumptionAmount} '
      'retirosAprobados=${totals.approvedWithdrawalsTotal}',
      name: 'TacoPOS.cashCorrection',
    );
    debugPrint(
      'efectivo: ${totals.expectedCashAmount - resolvedOpeningCashAmount + totals.approvedWithdrawalsTotal} '
      'tarjeta: ${totals.expectedCardChargedAmount} '
      'plataforma: ${totals.expectedPlatformAmount} '
      'consumo empleado: ${totals.expectedEmployeeConsumptionAmount} '
      'retiros aprobados: ${totals.approvedWithdrawalsTotal}',
    );
    final cashSalesAmount =
        totals.expectedCashAmount -
        resolvedOpeningCashAmount +
        totals.approvedWithdrawalsTotal;
    final cashUserSalesAmount = countedCashAmount - resolvedOpeningCashAmount;
    final cashSalesExpectedAfterWithdrawals =
        cashSalesAmount - totals.approvedWithdrawalsTotal;
    final cashDifference =
        cashUserSalesAmount - cashSalesExpectedAfterWithdrawals;
    final cardDifference =
        terminalReportedAmount - totals.expectedCardChargedAmount;
    final netDifference = cashDifference + cardDifference;
    final shortageAmount = netDifference < 0 ? netDifference.abs() : 0.0;
    final overAmount = netDifference > 0 ? netDifference : 0.0;
    final docId =
        existingSession?.id ??
        await _safeHistoricalCashSessionId(
          payments: payments,
          branch: branch,
          businessDate: businessDate,
        );

    return HistoricalCashCorrectionPreview(
      branch: branch,
      businessDate: businessDate,
      cashSessionId: docId,
      existingSession: existingSession,
      openingCashAmount: resolvedOpeningCashAmount,
      cashSalesAmount: cashSalesAmount,
      cardSalesAmount: totals.expectedCardChargedAmount,
      cardBaseAmount: totals.expectedCardBaseAmount,
      cardSurchargeAmount: totals.expectedCardSurchargeAmount,
      cardCommissionAmount: totals.expectedCardChargedAmount * 0.035 * 1.16,
      platformAmount: totals.expectedPlatformAmount,
      employeeConsumptionAmount: totals.expectedEmployeeConsumptionAmount,
      approvedWithdrawalsTotal: totals.approvedWithdrawalsTotal,
      pendingWithdrawalsTotal: totals.pendingWithdrawalsTotal,
      withdrawalRequestCount: totals.withdrawalRequestCount,
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
      expectedCashAmount: totals.expectedCashAmount,
      cashUserSalesAmount: cashUserSalesAmount,
      cashSalesExpectedAfterWithdrawals: cashSalesExpectedAfterWithdrawals,
      cashDifference: cashDifference,
      cardDifference: cardDifference,
      netDifference: netDifference,
      totalExpectedRealMoney: totals.totalExpectedRealMoney,
      totalCountedRealMoney: countedCashAmount + terminalReportedAmount,
      shortageAmount: shortageAmount,
      overAmount: overAmount,
      paymentCount: payments.length,
    );
  }

  Future<CashSession?> _cashSessionForBranchAndDate({
    required Branch branch,
    required String businessDate,
  }) async {
    final snapshot = await _cashSessionsRef
        .where('businessDate', isEqualTo: businessDate)
        .get();
    final sessions =
        snapshot.docs
            .map(CashSession.fromDoc)
            .where((session) => _matchesBranch(session.branchId, branch.id))
            .toList()
          ..sort((a, b) {
            final aDate = a.closedAt ?? a.openedAt ?? DateTime(1970);
            final bDate = b.closedAt ?? b.openedAt ?? DateTime(1970);
            return bDate.compareTo(aDate);
          });
    return sessions.isEmpty ? null : sessions.first;
  }

  Future<List<Payment>> _paymentsForBranchAndBusinessDate({
    required Branch branch,
    required String businessDate,
    String selectedCashSessionId = '',
    CashSession? selectedCashSession,
    bool activeOnly = true,
  }) async {
    final orderDocs = await _orderDocsForHistoricalCashCorrection(
      branch: branch,
      businessDate: businessDate,
      selectedCashSessionId: selectedCashSessionId,
      selectedCashSession: selectedCashSession,
    );
    final payments = <Payment>[];
    for (final orderDoc in orderDocs) {
      final order = PosOrder.fromDoc(orderDoc);
      final snapshot = await orderDoc.reference.collection('payments').get();
      for (final doc in snapshot.docs) {
        final payment = _paymentFromOrderPaymentDoc(doc, order);
        final active =
            !activeOnly || _isHistoricalCorrectionPaymentActive(payment);
        final branchMatches = _matchesBranch(payment.branchId, branch.id);
        final included = active && branchMatches;
        if (kDebugMode) {
          debugPrint(
            'CUT_RECALC_PAYMENT paymentId=${payment.id} '
            'orderId=${order.id} '
            'paidAt=${payment.createdAt?.toIso8601String()} '
            'paymentBusinessDate=${payment.businessDate ?? ''} '
            'orderBusinessDate=${resolveOperationalBusinessDate(order: order)} '
            'included=$included '
            'reason=${!active
                ? 'inactive_payment'
                : !branchMatches
                ? 'branch_mismatch'
                : 'parent_order_in_scope'}',
          );
        }
        if (included) payments.add(payment);
      }
    }
    developer.log(
      'Recalculo historico ordenes=${orderDocs.length} pagos=${payments.length} '
      'fecha=$businessDate branchId=${branch.id}',
      name: 'TacoPOS.cashCorrection',
    );
    debugPrint('orders encontrados: ${orderDocs.length}');
    debugPrint('payments encontrados: ${payments.length}');
    return payments;
  }

  Payment _paymentFromOrderPaymentDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    PosOrder order,
  ) {
    final payment = Payment.fromDoc(doc);
    final data = doc.data() ?? const <String, dynamic>{};
    final resolvedOrderBusinessDate = resolveOperationalBusinessDate(
      order: order,
    );
    final orderBusinessDate = resolvedOrderBusinessDate.isEmpty
        ? null
        : resolvedOrderBusinessDate;
    final rawRestaurantId = data['restaurantId'] as String?;
    final rawRestaurantName = data['restaurantName'] as String?;
    final rawBranchId = data['branchId'] as String?;
    final rawBranchName = data['branchName'] as String?;
    return payment.copyWith(
      orderId: order.id,
      tableId: payment.tableId.trim().isEmpty ? order.tableId : payment.tableId,
      tableName: payment.tableName.trim().isEmpty
          ? order.tableName
          : payment.tableName,
      cashSessionId: (payment.cashSessionId?.trim().isNotEmpty ?? false)
          ? payment.cashSessionId
          : order.cashSessionId,
      businessDate: orderBusinessDate != null && orderBusinessDate.isNotEmpty
          ? orderBusinessDate
          : payment.businessDate,
      restaurantId: rawRestaurantId == null || rawRestaurantId.trim().isEmpty
          ? order.restaurantId
          : payment.restaurantId,
      restaurantName:
          rawRestaurantName == null || rawRestaurantName.trim().isEmpty
          ? order.restaurantName
          : payment.restaurantName,
      branchId: rawBranchId == null || rawBranchId.trim().isEmpty
          ? order.branchId
          : payment.branchId,
      branchName: rawBranchName == null || rawBranchName.trim().isEmpty
          ? order.branchName
          : payment.branchName,
    );
  }

  void _debugSalesDateAssignment({
    required PosOrder order,
    required List<Payment> payments,
    required String startBusinessDate,
    required String endBusinessDate,
  }) {
    if (!kDebugMode || !_isDebugFolio9rFQcx(order.id)) return;
    final resolvedBusinessDate = _businessDateForOrder(order);
    for (final payment in payments) {
      developer.log(
        'folio=9rFQcx orderId=${order.id} '
        'orderBusinessDate=${order.businessDate} '
        'orderOperationalDate=${order.operationalDate} '
        'orderCreatedAt=${order.createdAt?.toIso8601String()} '
        'paymentId=${payment.id} '
        'paymentOrderId=${payment.orderId} '
        'paymentBusinessDate=${payment.businessDate} '
        'paymentCreatedAt=${payment.createdAt?.toIso8601String()} '
        'resolvedBusinessDate=$resolvedBusinessDate '
        'range=$startBusinessDate..$endBusinessDate '
        'amount=${canonicalPaymentAppliedAmount(payment).toStringAsFixed(2)}',
        name: 'TacoPOS.salesDateDebug',
      );
    }
  }

  bool _isDebugFolio9rFQcx(String orderId) {
    final normalized = orderId.trim().toLowerCase();
    return normalized == '9rfqcx' || normalized.contains('9rfqcx');
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _orderDocsForHistoricalCashCorrection({
    required Branch branch,
    required String businessDate,
    String selectedCashSessionId = '',
    CashSession? selectedCashSession,
    bool excludeCancelled = true,
  }) async {
    final cleanSessionId = selectedCashSessionId.trim();
    final sessionOpenedAt = selectedCashSession?.openedAt;
    final sessionCandidateEnd = await _historicalSessionCandidateEnd(
      selectedCashSession,
      branchId: branch.id,
    );
    final snapshots = await Future.wait([
      if (cleanSessionId.isNotEmpty)
        _ordersRef.where('cashSessionId', isEqualTo: cleanSessionId).get(),
      _ordersRef.where('businessDate', isEqualTo: businessDate).get(),
      _ordersRef.where('operationalDate', isEqualTo: businessDate).get(),
      if (cleanSessionId.isNotEmpty &&
          sessionOpenedAt != null &&
          sessionCandidateEnd != null)
        _ordersRef
            .where('createdAt', isGreaterThanOrEqualTo: sessionOpenedAt)
            .where('createdAt', isLessThan: sessionCandidateEnd)
            .get(),
    ]);
    final candidates = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        candidates[doc.reference.path] = doc;
      }
    }

    final included = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in candidates.values) {
      final membership = await _orderDocHistoricalCashMembership(
        doc,
        branch: branch,
        businessDate: businessDate,
        selectedCashSessionId: cleanSessionId,
        excludeCancelled: excludeCancelled,
      );
      final order = PosOrder.fromDoc(doc);
      if (kDebugMode) {
        debugPrint(
          'CUT_RECALC_ORDER orderId=${order.id} '
          'folio=${_shortLogFolio(order.id)} '
          'createdAt=${order.createdAt?.toIso8601String()} '
          'businessDate=${order.businessDate ?? ''} '
          'cashSessionId=${order.cashSessionId ?? ''} '
          'included=${membership.included} '
          'inclusionReason=${membership.included ? membership.reason : ''} '
          'exclusionReason=${membership.included ? '' : membership.reason} '
          'inconsistency=${membership.inconsistency ?? ''}',
        );
      }
      if (membership.included) included.add(doc);
    }
    return included;
  }

  Future<OperationalSessionMembership> _orderDocHistoricalCashMembership(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required Branch branch,
    required String businessDate,
    required String selectedCashSessionId,
    required bool excludeCancelled,
  }) async {
    final order = PosOrder.fromDoc(doc);
    if (excludeCancelled &&
        _isHistoricalCorrectionOrderCancelled(order.status)) {
      return Future.value(
        const OperationalSessionMembership(
          included: false,
          reason: 'cancelled_order',
        ),
      );
    }
    final directMembership = belongsToOperationalSession(
      order: order,
      selectedCashSessionId: selectedCashSessionId,
      selectedBusinessDate: businessDate,
      branchId: branch.id,
    );
    if (directMembership.included ||
        directMembership.reason != 'missing_operational_scope' ||
        selectedCashSessionId.isEmpty) {
      return Future.value(directMembership);
    }

    final paymentsSnapshot = await doc.reference.collection('payments').get();
    return belongsToOperationalSession(
      order: order,
      selectedCashSessionId: selectedCashSessionId,
      selectedBusinessDate: businessDate,
      branchId: branch.id,
      paymentCashSessionIds: paymentsSnapshot.docs.map(
        (paymentDoc) =>
            paymentDoc.data()['cashSessionId']?.toString().trim() ?? '',
      ),
    );
  }

  Future<DateTime?> _historicalSessionCandidateEnd(
    CashSession? session, {
    required String branchId,
  }) async {
    final openedAt = session?.openedAt;
    if (openedAt == null) return null;
    final sessionsSnapshot = await _cashSessionsRef.get();
    final laterOpenings =
        sessionsSnapshot.docs
            .map(CashSession.fromDoc)
            .where(
              (candidate) =>
                  _matchesBranch(candidate.branchId, branchId) &&
                  candidate.openedAt != null &&
                  candidate.openedAt!.isAfter(openedAt),
            )
            .map((candidate) => candidate.openedAt!)
            .toList()
          ..sort();
    if (laterOpenings.isNotEmpty) return laterOpenings.first;

    final closedAt = session?.closedAt;
    if (closedAt == null) {
      return DateTime.now().add(const Duration(minutes: 5));
    }
    return closedAt.add(const Duration(minutes: 1));
  }

  bool _isHistoricalCorrectionOrderCancelled(String status) {
    final clean = status.trim().toLowerCase();
    return const {
      'cancelled',
      'canceled',
      'cancelado',
      'voided',
      'anulado',
    }.contains(clean);
  }

  bool _isHistoricalCorrectionPaymentActive(Payment payment) {
    final cleanStatus = payment.status.trim().toLowerCase();
    if (cleanStatus == 'cancelled' ||
        cleanStatus == 'canceled' ||
        cleanStatus == 'cancelado') {
      return false;
    }
    if (payment.cancelledAt != null) return false;
    return payment.chargedAmount > 0 || payment.baseAmount > 0;
  }

  Future<List<CashWithdrawalRequest>> _withdrawalsForBranchAndBusinessDate({
    required Branch branch,
    required String businessDate,
    String selectedCashSessionId = '',
  }) async {
    final cleanSessionId = selectedCashSessionId.trim();
    final snapshots = await Future.wait([
      if (cleanSessionId.isNotEmpty)
        _cashWithdrawalRequestsRef
            .where('cashSessionId', isEqualTo: cleanSessionId)
            .get(),
      _cashWithdrawalRequestsRef
          .where('businessDate', isEqualTo: businessDate)
          .get(),
    ]);
    final requestsById = <String, CashWithdrawalRequest>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        final request = CashWithdrawalRequest.fromDoc(doc);
        if (!_matchesBranch(request.branchId, branch.id)) continue;
        final requestSessionId = request.cashSessionId.trim();
        final included = cleanSessionId.isNotEmpty
            ? requestSessionId == cleanSessionId ||
                  (requestSessionId.isEmpty &&
                      request.businessDate == businessDate)
            : request.businessDate == businessDate;
        if (included) requestsById[doc.id] = request;
      }
    }
    return requestsById.values.toList();
  }

  String _predominantCashSessionId(List<Payment> payments) {
    final counts = <String, int>{};
    for (final payment in payments) {
      final id = payment.cashSessionId?.trim();
      if (id == null || id.isEmpty) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.first.key;
  }

  Future<String> _safeHistoricalCashSessionId({
    required List<Payment> payments,
    required Branch branch,
    required String businessDate,
  }) async {
    final predominantId = _predominantCashSessionId(payments);
    if (predominantId.isEmpty) return _cashSessionsRef.doc().id;
    final doc = await _cashSessionsRef.doc(predominantId).get();
    if (!doc.exists) return predominantId;
    final session = CashSession.fromDoc(doc);
    if (session.businessDate == businessDate &&
        _matchesBranch(session.branchId, branch.id)) {
      return predominantId;
    }
    return _cashSessionsRef.doc().id;
  }

  Map<String, Object?> _branchFields(Branch branch) {
    return {
      'restaurantId': branch.restaurantId,
      'restaurantName': branch.restaurantName,
      'branchId': branch.id,
      'branchName': branch.name,
    };
  }

  void _validateHistoricalCashCorrectionInput({
    required Branch branch,
    required String businessDate,
    required double countedCashAmount,
    required double terminalReportedAmount,
    double? openingCashAmount,
  }) {
    if (branch.id.trim().isEmpty) {
      throw ArgumentError('Selecciona una sucursal.');
    }
    final cleanDate = businessDate.trim();
    if (cleanDate.isEmpty || _dateFromBusinessDate(cleanDate) == null) {
      throw ArgumentError('Selecciona una fecha operativa valida.');
    }
    final selectedDate = _dateFromBusinessDate(cleanDate)!;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    if (selectedDate.isAfter(todayOnly)) {
      throw ArgumentError('No se puede rehacer un corte de fecha futura.');
    }
    if (countedCashAmount < 0 || terminalReportedAmount < 0) {
      throw ArgumentError('Los montos no pueden ser negativos.');
    }
    if (openingCashAmount != null && openingCashAmount < 0) {
      throw ArgumentError('El fondo inicial no puede ser negativo.');
    }
  }

  DateTime? _dateFromBusinessDate(String businessDate) {
    final parts = businessDate.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  Future<CashSessionTotals> _cashSessionTotalsOnce(String cashSessionId) async {
    final snapshot = await _db.collectionGroup('payments').get();
    final sessionDoc = await _cashSessionsRef.doc(cashSessionId).get();
    final session = sessionDoc.exists ? CashSession.fromDoc(sessionDoc) : null;
    final withdrawals = await _cashWithdrawalRequestsForSessionOnce(
      cashSessionId,
    );
    return _totalsForPayments(
      snapshot.docs
          .map(Payment.fromDoc)
          .where((payment) => payment.cashSessionId == cashSessionId)
          .where((payment) => payment.isActive)
          .toList(),
      openingCashAmount: session?.openingCashAmount ?? 0,
      withdrawals: withdrawals,
    );
  }

  Future<List<CashWithdrawalRequest>> _cashWithdrawalRequestsForSessionOnce(
    String cashSessionId,
  ) async {
    final snapshot = await _cashWithdrawalRequestsRef
        .where('cashSessionId', isEqualTo: cashSessionId)
        .get();
    return snapshot.docs.map(CashWithdrawalRequest.fromDoc).toList();
  }

  Future<List<CashWithdrawalRequest>> _pendingCashWithdrawalRequestsForClose({
    required String cashSessionId,
    required String businessDate,
  }) async {
    final bySession = await _cashWithdrawalRequestsRef
        .where('cashSessionId', isEqualTo: cashSessionId)
        .get();
    final byDate = await _cashWithdrawalRequestsRef
        .where('businessDate', isEqualTo: businessDate)
        .get();

    final requestsById = <String, CashWithdrawalRequest>{};
    for (final doc in [...bySession.docs, ...byDate.docs]) {
      final request = CashWithdrawalRequest.fromDoc(doc);
      if (request.isPending && _matchesCurrentBranch(request.branchId)) {
        requestsById[doc.id] = request;
      }
    }
    return requestsById.values.toList();
  }

  CashSessionTotals _totalsForPayments(
    List<Payment> payments, {
    required double openingCashAmount,
    required List<CashWithdrawalRequest> withdrawals,
    double extraApprovedWithdrawalAmount = 0,
  }) {
    double cash = 0;
    double cardCharged = 0;
    double cardBase = 0;
    double cardSurcharge = 0;
    double cardFeeAbsorbed = 0;
    double platform = 0;
    double employeeConsumption = 0;

    for (final payment in payments.where((payment) => payment.isActive)) {
      final saleApplied = canonicalPaymentAppliedAmount(payment);
      final tip = payment.tipAmount.clamp(0, double.infinity).toDouble();
      switch (payment.method) {
        case 'cash':
          cash += saleApplied + tip;
          break;
        case 'card':
          final customerCharged = payment.chargedAmount > 0
              ? payment.chargedAmount
              : saleApplied;
          final terminalAmount =
              customerCharged +
              (customerCharged <= saleApplied + 0.02 ? tip : 0.0);
          cardCharged += terminalAmount;
          cardBase += saleApplied;
          cardSurcharge += (terminalAmount - saleApplied - tip)
              .clamp(0, double.infinity)
              .toDouble();
          cardFeeAbsorbed += payment.cardFeeAbsorbedAmount;
          break;
        case 'platform_paid':
          platform += saleApplied;
          break;
        case 'employee_consumption':
          employeeConsumption += saleApplied;
          break;
      }
    }

    final approvedWithdrawals =
        withdrawals
            .where((request) => request.isApproved)
            .fold<double>(0, (total, request) => total + request.amount) +
        extraApprovedWithdrawalAmount;
    final pendingWithdrawals = withdrawals
        .where((request) => request.isPending)
        .fold<double>(0, (total, request) => total + request.amount);

    return CashSessionTotals(
      expectedCashAmount: cash + openingCashAmount - approvedWithdrawals,
      expectedCardChargedAmount: cardCharged,
      expectedCardBaseAmount: cardBase,
      expectedCardSurchargeAmount: cardSurcharge,
      expectedCardFeeAbsorbedAmount: cardFeeAbsorbed,
      expectedPlatformAmount: platform,
      expectedEmployeeConsumptionAmount: employeeConsumption,
      approvedWithdrawalsTotal: approvedWithdrawals,
      pendingWithdrawalsTotal: pendingWithdrawals,
      withdrawalRequestCount: withdrawals.length,
    );
  }

  Future<Map<String, double>> _previousKitchenRemainingByItem(
    String businessDate,
  ) async {
    final snapshot = await _kitchenSessionsRef
        .where('status', isEqualTo: 'closed')
        .get();
    final previousSessions =
        snapshot.docs
            .map(KitchenSession.fromDoc)
            .where(
              (session) =>
                  session.businessDate.compareTo(businessDate) < 0 &&
                  _matchesCurrentBranch(session.branchId),
            )
            .toList()
          ..sort((a, b) => b.businessDate.compareTo(a.businessDate));
    if (previousSessions.isEmpty) {
      return const {};
    }

    final itemsSnapshot = await _kitchenSessionsRef
        .doc(previousSessions.first.id)
        .collection('items')
        .get();
    return {
      for (final item in itemsSnapshot.docs.map(KitchenSessionItem.fromDoc))
        item.kitchenStockItemId: item.finalRemainingQty,
    };
  }

  Future<Map<String, double>> _soldQtyByKitchenStockItem(
    String businessDate,
  ) async {
    final ordersSnapshot = await _ordersRef.get();
    final orders = ordersSnapshot.docs.map(PosOrder.fromDoc).where((order) {
      if (['cancelled', 'voided'].contains(order.status)) {
        return false;
      }
      if (!_matchesCurrentBranch(order.branchId)) {
        return false;
      }
      if (['pending', 'partial'].contains(order.paymentStatus) &&
          order.status != 'paid') {
        return false;
      }
      final date = order.paidAt ?? order.createdAt;
      return _businessDateFor(date ?? DateTime.fromMillisecondsSinceEpoch(0)) ==
          businessDate;
    }).toList();

    final sold = <String, double>{};
    for (final order in orders) {
      final itemsSnapshot = await _ordersRef
          .doc(order.id)
          .collection('items')
          .get();
      for (final item in itemsSnapshot.docs.map(OrderItem.fromDoc)) {
        if (['cancelled', 'voided'].contains(item.kitchenStatus) ||
            ['cancelled', 'voided'].contains(item.paymentStatus)) {
          continue;
        }
        if (item.recipeItems.isNotEmpty) {
          final recipeItem = item.recipeItems.first;
          sold[recipeItem.kitchenStockItemId] =
              (sold[recipeItem.kitchenStockItemId] ?? 0) +
              item.qty * recipeItem.consumptionFactor;
          continue;
        }
        final stockItemId =
            item.kitchenStockItemId ??
            _stockItemIdForProductName(item.productName);
        if (stockItemId == null) {
          continue;
        }
        sold[stockItemId] = (sold[stockItemId] ?? 0) + item.qty;
      }
    }
    return sold;
  }

  String? _stockItemIdForProductName(String productName) {
    final normalized = _normalizeName(productName);
    if (normalized.contains('bistec')) return 'bistec';
    if (normalized.contains('adobada')) return 'adobada';
    if (normalized.contains('carnaza')) return 'carnaza';
    if (normalized.contains('arrachera')) return 'arrachera';
    if (normalized.contains('chorizo')) return 'chorizo';
    if (normalized.contains('higado')) return 'higado';
    if (normalized.contains('labio')) return 'labio';
    if (normalized.contains('tripa')) return 'tripa';
    if (normalized.contains('lengua')) return 'lengua';
    if (normalized.contains('coca') || normalized.contains('refresco')) {
      return 'refresco_coca_cola';
    }
    return null;
  }

  List<ProductRecipeItem> _defaultRecipeItemsForProduct(
    Product product,
    Map<String, KitchenStockItem> stockById,
  ) {
    final normalizedName = _normalizeName(product.name);
    final normalizedCategory = _normalizeName(product.category);
    final meatId = _stockItemIdForProductName(product.name);
    final isDrink =
        normalizedCategory == 'bebidas' ||
        normalizedName.contains('refresco') ||
        normalizedName.contains('coca');
    if (isDrink) {
      return [
        _recipeItemForStockId(
          'refresco_coca_cola',
          stockById,
          fallbackName: 'Refresco Coca Cola',
          fallbackUnit: 'piece',
          factor: 1,
        ),
      ];
    }

    if (meatId == null) {
      return const [];
    }

    if (normalizedName.contains('gringa')) {
      final isGrande =
          normalizedName.contains('grande') ||
          normalizedName.contains('gde') ||
          normalizedName.contains('gringa grande');
      return [
        _recipeItemForStockId(
          meatId,
          stockById,
          fallbackName: _titleFromId(meatId),
          fallbackUnit: 'kg',
          factor: isGrande ? 3.5 : 2.5,
        ),
      ];
    }

    if (normalizedCategory == 'tacos' || normalizedName.contains('taco')) {
      return [
        _recipeItemForStockId(
          meatId,
          stockById,
          fallbackName: _titleFromId(meatId),
          fallbackUnit: 'kg',
          factor: 1,
        ),
      ];
    }

    return [
      _recipeItemForStockId(
        meatId,
        stockById,
        fallbackName: _titleFromId(meatId),
        fallbackUnit: 'kg',
        factor: 1,
      ),
    ];
  }

  ProductRecipeItem _recipeItemForStockId(
    String stockItemId,
    Map<String, KitchenStockItem> stockById, {
    required String fallbackName,
    required String fallbackUnit,
    required double factor,
  }) {
    final stockItem = stockById[stockItemId];
    return ProductRecipeItem(
      kitchenStockItemId: stockItemId,
      kitchenStockItemName: stockItem?.name ?? fallbackName,
      kitchenStockUnit: stockItem?.unit ?? fallbackUnit,
      consumptionFactor: factor,
    );
  }

  String _titleFromId(String id) {
    return id
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  bool _defaultProductAffectsKitchenStock(Product product) {
    final category = _normalizeName(product.category);
    final name = _normalizeName(product.name);
    if (category == 'tacos' ||
        name.contains('taco') ||
        name.contains('gringa')) {
      return true;
    }
    if (category == 'bebidas' || name.contains('refresco')) {
      return true;
    }
    return false;
  }

  KitchenStockItem _fallbackStockItemForRecipeItem(
    ProductRecipeItem recipeItem,
    Product product,
  ) {
    final id = recipeItem.kitchenStockItemId;
    final category = _normalizeName(product.category);
    final isDrink =
        recipeItem.kitchenStockUnit == 'piece' ||
        category == 'bebidas' ||
        id.contains('refresco');
    final isTortilla = id.contains('tortilla');
    return KitchenStockItem(
      id: id,
      name: recipeItem.kitchenStockItemName,
      category: isDrink
          ? 'drink'
          : isTortilla
          ? 'tortilla'
          : id == 'queso'
          ? 'dairy'
          : 'meat',
      unit: recipeItem.kitchenStockUnit,
      active: true,
      sortOrder: isDrink
          ? 50
          : isTortilla
          ? 15
          : id == 'queso'
          ? 14
          : 20,
      optimalConsumptionPerSaleQty: recipeItem.kitchenStockUnit == 'piece'
          ? 1
          : 50,
      optimalConsumptionUnit: recipeItem.kitchenStockUnit == 'piece'
          ? 'piece_per_item'
          : 'g_per_item',
    );
  }

  String _normalizeName(String value) {
    return value
        .toLowerCase()
        .replaceAll('í', 'i')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
  }

  String _businessDateFor(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String? _businessDateForOrder(PosOrder order) {
    final resolution = resolveOperationalBusinessDateDetails(
      order: order,
      historicalFallback: order.createdAt ?? order.paidAt ?? order.updatedAt,
    );
    if (resolution.usedHistoricalFallback) {
      developer.log(
        'Orden sin businessDate; usando fallback historico diagnosticado. '
        'orderId=${order.id} resolved=${resolution.businessDate}',
        name: 'TacoPOS.canonicalSales',
      );
    }
    return resolution.businessDate.isEmpty ? null : resolution.businessDate;
  }

  String _currentBusinessDate() {
    return _businessDateFor(DateTime.now());
  }

  Future<OperationalStateReconciliationResult>
  reconcileOrderTableAndKitchenState({
    required String restaurantId,
    required String branchId,
    required String orderId,
    String reason = 'operational_state_reconciliation',
  }) async {
    final cleanOrderId = orderId.trim();
    if (cleanOrderId.isEmpty) {
      throw ArgumentError('orderId vacio para reconciliacion.');
    }
    if (restaurantId.trim().isNotEmpty &&
        restaurantId.trim() != AppConstants.restaurantId) {
      throw StateError('La orden pertenece a otro restaurante.');
    }

    final orderRef = _ordersRef.doc(cleanOrderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists) {
      throw StateError('La orden ya no existe.');
    }
    final order = PosOrder.fromDoc(orderDoc);
    if (branchId.trim().isNotEmpty &&
        !_matchesBranch(order.branchId, branchId)) {
      throw StateError('La orden pertenece a otra sucursal.');
    }

    final itemsSnapshot = await orderRef.collection('items').get();
    final items = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
    final activeItems = items.where(isActiveOrderItem).toList();
    final pendingKitchenItems = items.where(isKitchenPendingItem).toList();
    final readyKitchenItems = items.where(isKitchenReadyItem).toList();
    final cancelledItemsCount = items.length - activeItems.length;
    final nextKitchenStatus = kitchenStatusForItems(items);
    final hasPending = pendingKitchenItems.isNotEmpty;
    final linkedTableIds = order.linkedTableIds.toSet();

    PosTable? firstTable;
    final tableDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
    for (final tableId in linkedTableIds) {
      final tableDoc = await _tablesRef.doc(tableId).get();
      if (!tableDoc.exists) continue;
      tableDocs.add(tableDoc);
      firstTable ??= PosTable.fromDoc(tableDoc);
    }
    final tableStatusBefore = firstTable?.status ?? '';
    final tableIdForLog = firstTable?.id ?? order.tableId;
    final tableNameForLog = firstTable?.name ?? order.tableName;
    var tableStatusAfter = tableStatusBefore;
    var repairApplied = false;

    if (isActiveOrderState(order) && activeItems.isNotEmpty) {
      final batch = _db.batch();
      for (final tableDoc in tableDocs) {
        final table = PosTable.fromDoc(tableDoc);
        final needsOccupiedAt = table.occupiedAt == null;
        final needsRepair =
            table.status != 'occupied' ||
            table.currentOrderId?.trim() != order.id ||
            table.currentOrderStatus?.trim() != order.status ||
            needsOccupiedAt;
        if (!needsRepair) continue;
        repairApplied = true;
        batch.set(tableDoc.reference, {
          'status': 'occupied',
          'currentOrderId': order.id,
          'currentOrderStatus': order.status,
          if (needsOccupiedAt) 'occupiedAt': FieldValue.serverTimestamp(),
          ..._currentBranchFields,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      final orderNeedsKitchenRepair =
          order.kitchenStatus != nextKitchenStatus ||
          (orderDoc.data()?['hasPendingKitchenItems'] as bool?) != hasPending ||
          (orderDoc.data()?['pendingKitchenItemsCount'] as num?)?.toInt() !=
              pendingKitchenItems.length;
      if (orderNeedsKitchenRepair) {
        repairApplied = true;
        batch.update(orderRef, {
          'kitchenStatus': nextKitchenStatus,
          'hasPendingKitchenItems': hasPending,
          'pendingKitchenItemsCount': pendingKitchenItems.length,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (repairApplied) {
        _logActivityInBatch(
          batch,
          type: 'operational_state_reconciled',
          orderId: order.id,
          data: {
            'actionType': 'operational_state_reconciled',
            'folio': _shortLogFolio(order.id),
            'tableId': tableIdForLog,
            'tableName': tableNameForLog,
            'previousTableStatus': tableStatusBefore,
            'newTableStatus': 'occupied',
            'previousKitchenStatus': order.kitchenStatus,
            'newKitchenStatus': nextKitchenStatus,
            'activeItemsCount': activeItems.length,
            'pendingKitchenItemsCount': pendingKitchenItems.length,
            'readyKitchenItemsCount': readyKitchenItems.length,
            'cancelledItemsCount': cancelledItemsCount,
            'businessDate':
                _businessDateForOrder(order) ?? _currentBusinessDate(),
            'cashSessionId': order.cashSessionId ?? '',
            'branchId': order.branchId,
            'employeeId': AppSession.instance.employee?.id ?? '',
            'employeeName': AppSession.instance.employee?.name ?? '',
            'timestamp': FieldValue.serverTimestamp(),
            'reason': reason,
            'message':
                'Se reconciliaron los estados de $tableNameForLog, orden y Cocina.',
          },
        );
        await batch.commit();
        tableStatusAfter = 'occupied';
      } else if (tableDocs.isNotEmpty) {
        tableStatusAfter = PosTable.fromDoc(tableDocs.first).status;
      }
    }

    final result = OperationalStateReconciliationResult(
      orderId: order.id,
      folio: _shortLogFolio(order.id),
      tableId: tableIdForLog,
      tableName: tableNameForLog,
      tableStatusBefore: tableStatusBefore,
      tableStatusAfter: tableStatusAfter,
      orderStatus: order.status,
      orderKitchenStatusBefore: order.kitchenStatus,
      orderKitchenStatusAfter: nextKitchenStatus,
      activeItemsCount: activeItems.length,
      pendingKitchenItemsCount: pendingKitchenItems.length,
      readyKitchenItemsCount: readyKitchenItems.length,
      cancelledItemsCount: cancelledItemsCount,
      kitchenViewerIncluded: hasPending,
      chargeBlocked: hasPending,
      repairApplied: repairApplied,
      reason: reason,
    );
    developer.log(
      'OPERATIONAL_STATE_RECONCILIATION '
      'orderId=${result.orderId} '
      'folio=${result.folio} '
      'tableId=${result.tableId} '
      'tableStatusBefore=${result.tableStatusBefore} '
      'tableStatusAfter=${result.tableStatusAfter} '
      'orderStatus=${result.orderStatus} '
      'orderKitchenStatusBefore=${result.orderKitchenStatusBefore} '
      'orderKitchenStatusAfter=${result.orderKitchenStatusAfter} '
      'activeItems=${result.activeItemsCount} '
      'pendingKitchenItems=${result.pendingKitchenItemsCount} '
      'kitchenViewerIncluded=${result.kitchenViewerIncluded} '
      'chargeBlocked=${result.chargeBlocked} '
      'repairApplied=${result.repairApplied}',
      name: 'TacoPOS.operationalState',
    );
    return result;
  }

  Future<void> reconcileOpenOrdersForKitchen() async {
    final snapshot = await _ordersRef.get();
    for (final order
        in snapshot.docs
            .map(PosOrder.fromDoc)
            .where(isActiveOrder)
            .where((order) => _matchesCurrentBranch(order.branchId))) {
      if (!orderUsesPhysicalTables(order)) continue;
      try {
        await reconcileOrderTableAndKitchenState(
          restaurantId: order.restaurantId,
          branchId: order.branchId,
          orderId: order.id,
          reason: 'kitchen_opened',
        );
      } catch (error, stackTrace) {
        developer.log(
          'No se pudo reconciliar orden de cocina ${order.id}: $error',
          name: 'TacoPOS.operationalState',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<_TableLinkCleanupResult> _reconcileStaleTableOrderLinks({
    required String businessDate,
    required List<OperationalOrderBlocker> blockers,
    String triggeredBy = 'operational_reconciliation',
  }) async {
    final activeOrderIds = blockers.map((row) => row.order.id).toSet();
    final tablesSnapshot = await _tablesRef.get();
    final staleTables = <PosTable>[];
    for (final table in tablesSnapshot.docs.map(PosTable.fromDoc)) {
      if (!_matchesCurrentBranch(table.branchId)) continue;
      if (!isStaleTableLink(table, activeOrderIds: activeOrderIds)) continue;
      staleTables.add(table);
    }
    if (staleTables.isEmpty) {
      return const _TableLinkCleanupResult(stale: 0, released: 0);
    }

    final releases = await runInBatches<PosTable, bool>(
      staleTables,
      batchSize: 10,
      action: (table) => _clearStaleTableLinkIfUnchanged(
        table: table,
        activeOrderIds: activeOrderIds,
        businessDate: businessDate,
        triggeredBy: triggeredBy,
      ),
    );
    return _TableLinkCleanupResult(
      stale: staleTables.length,
      released: releases.where((released) => released).length,
    );
  }

  Future<bool> _clearStaleTableLinkIfUnchanged({
    required PosTable table,
    required Set<String> activeOrderIds,
    required String businessDate,
    required String triggeredBy,
  }) async {
    final expectedOrderId = table.currentOrderId?.trim() ?? '';
    if (expectedOrderId.isEmpty) return Future.value(false);
    final linkedOrderDoc = await _ordersRef.doc(expectedOrderId).get();
    if (linkedOrderDoc.exists) {
      final linkedOrder = PosOrder.fromDoc(linkedOrderDoc);
      final linkedItems = await getOrderItemsOnce(expectedOrderId);
      final linkedPayments = await getOrderPaymentsOnce(expectedOrderId);
      final stillOccupiesTable = shouldKeepTableOccupiedForOrder(
        order: linkedOrder,
        items: linkedItems,
        payments: linkedPayments,
      );
      if (stillOccupiesTable &&
          _matchesCurrentBranch(linkedOrder.branchId) &&
          linkedOrder.linkedTableIds.contains(table.id)) {
        await reconcileOrderTableAndKitchenState(
          restaurantId: linkedOrder.restaurantId,
          branchId: linkedOrder.branchId,
          orderId: linkedOrder.id,
          reason: 'prevent_stale_table_cleanup_active_order',
        );
        return false;
      }
    }
    final tableRef = _tablesRef.doc(table.id);
    return _db.runTransaction<bool>((transaction) async {
      final freshDoc = await transaction.get(tableRef);
      if (!freshDoc.exists) return false;
      final freshTable = PosTable.fromDoc(freshDoc);
      if (!_matchesCurrentBranch(freshTable.branchId) ||
          freshTable.currentOrderId?.trim() != expectedOrderId ||
          !isStaleTableLink(freshTable, activeOrderIds: activeOrderIds)) {
        return false;
      }

      final now = FieldValue.serverTimestamp();
      transaction.set(tableRef, {
        'status': 'available',
        'currentOrderId': null,
        'currentOrderStatus': null,
        'tableGroupId': null,
        'tableGroupLabel': null,
        'groupPrimaryTableId': null,
        'occupiedAt': null,
        'updatedAt': now,
      }, SetOptions(merge: true));
      transaction.set(_restaurantRef.collection('activityLog').doc(), {
        'type': 'stale_table_link_cleared',
        'actionType': 'stale_table_link_cleared',
        'message':
            'Se limpió el vínculo obsoleto de ${freshTable.name} con la orden $expectedOrderId.',
        ..._currentBranchFields,
        'tableId': freshTable.id,
        'tableName': freshTable.name,
        'staleOrderId': expectedOrderId,
        'businessDate': businessDate,
        'triggeredBy': triggeredBy,
        'employeeId': AppSession.instance.employee?.id ?? '',
        'employeeName': AppSession.instance.employee?.name ?? '',
        ..._employeeAuditFields(prefix: 'createdBy'),
        'timestamp': now,
        'createdAt': now,
      });
      return true;
    });
  }

  void _debugOperationalBlockers(OperationalOpenOrdersSummary summary) {
    if (!kDebugMode) return;
    developer.log(
      'OPERATIONAL_BLOCKERS_DEBUG businessDate=${summary.businessDate} '
      'branchId=${summary.branchId} cashSessionId=${summary.cashSessionId} '
      'ordenesConsultadas=${summary.ordersChecked} '
      'ordenesActivas=${summary.blockers.length} '
      'descartadas=${summary.discardedReasons} '
      'mesasObsoletas=${summary.staleTableLinks} '
      'mesasLiberadas=${summary.releasedTableLinks} '
      'takeoutsActivos=${summary.openTakeoutCount}',
      name: 'TacoPOS.operationalBlockers',
    );
  }

  void _debugOperationalViewer(OperationalOpenOrdersSummary summary) {
    if (!kDebugMode) return;
    for (final blocker in summary.blockers) {
      final order = blocker.order;
      developer.log(
        'OPERATIONAL_ORDER_DIAGNOSTIC '
        'orderId=${order.id} '
        'folio=${order.takeoutNumber ?? order.id} '
        'orderType=${order.orderType} '
        'canonicalType=${normalizeOrderType(order.orderType)} '
        'dashboardActive=true '
        'operationalViewerIncluded=true '
        'exclusionReason=none '
        'businessDate=${order.businessDate ?? order.operationalDate ?? ''} '
        'cashSessionId=${order.cashSessionId ?? ''} '
        'branchId=${order.branchId} '
        'status=${order.status} '
        'paymentStatus=${order.paymentStatus} '
        'pendingTotal=${order.pendingTotal} '
        'activeItems=${blocker.activeItemCount} '
        'reason=${blocker.reason}',
        name: 'TacoPOS.operationalViewer',
      );
    }
    final reconciliation = reconcileOperationalViewer(summary);
    developer.log(
      'OPERATIONAL_VIEWER_RECONCILIATION '
      'dashboardOpen=${reconciliation.dashboardOpen} '
      'viewerTables=${reconciliation.viewerTables} '
      'viewerTakeout=${reconciliation.viewerTakeout} '
      'viewerStanding=${reconciliation.viewerStanding} '
      'viewerTotal=${reconciliation.viewerTotal} '
      'difference=${reconciliation.difference} '
      'valid=${reconciliation.valid}',
      name: 'TacoPOS.operationalViewer',
      level: reconciliation.valid ? 0 : 900,
    );
  }

  String _productStockOutId(
    String branchId,
    String businessDate,
    String productId,
  ) {
    String clean(String value) => value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return '${clean(branchId)}_${clean(businessDate)}_${clean(productId)}';
  }

  Future<void> _clearProductStockOutRef(
    DocumentReference<Map<String, dynamic>> docRef, {
    required String reason,
  }) async {
    final doc = await docRef.get();
    if (!doc.exists || doc.data()?['status'] != 'active') return;
    final batch = _db.batch();
    _clearProductStockOutInBatch(batch, docRef, reason: reason);
    await batch.commit();
  }

  void _clearProductStockOutInBatch(
    WriteBatch batch,
    DocumentReference<Map<String, dynamic>> docRef, {
    required String reason,
  }) {
    final employee = AppSession.instance.employee;
    batch.update(docRef, {
      'status': 'cleared',
      'clearedAt': FieldValue.serverTimestamp(),
      'clearedByEmployeeId': employee?.id ?? '',
      'clearedByEmployeeName': employee?.name ?? '',
      'clearedReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  bool _orderBelongsToBusinessDate(PosOrder order, String businessDate) {
    final fallback = order.createdAt ?? order.paidAt ?? order.updatedAt;
    return resolveOperationalBusinessDate(
          order: order,
          historicalFallback: fallback,
        ) ==
        businessDate;
  }

  bool _isFinalOrderStatus(String status) {
    return ['paid', 'cancelled', 'voided'].contains(status);
  }

  Future<bool> _kitchenCloseIsComplete(String kitchenSessionId) async {
    final itemsSnapshot = await _kitchenSessionsRef
        .doc(kitchenSessionId)
        .collection('items')
        .get();
    if (itemsSnapshot.docs.isEmpty) {
      return false;
    }
    for (final doc in itemsSnapshot.docs) {
      final data = doc.data();
      if (data['finalRemainingQty'] == null ||
          data['usedQty'] == null ||
          data['usefulConsumedQty'] == null) {
        return false;
      }
    }
    return true;
  }

  double _yieldPerSale({
    required String unit,
    required double usefulConsumedQty,
    required double soldQty,
  }) {
    if (soldQty <= 0 || usefulConsumedQty <= 0) {
      return 0;
    }
    if (unit == 'kg') {
      return (usefulConsumedQty * 1000) / soldQty;
    }
    return usefulConsumedQty / soldQty;
  }

  Future<PosOrder> createOrGetOpenOrder(
    PosTable table, {
    String? visitClassification,
    bool? isFirstVisit,
    String? visitSurveyAnsweredBy,
  }) async {
    developer.log(
      '[TacoPOS][openTable] tableId=${table.id} tableName=${table.name} '
      'currentOrderId=${table.currentOrderId ?? '-'} tableStatus=${table.status}',
    );

    final activeOrdersById = <String, PosOrder>{};
    final currentOrderId = table.currentOrderId?.trim();
    if (currentOrderId != null && currentOrderId.isNotEmpty) {
      final currentDoc = await _ordersRef.doc(currentOrderId).get();
      if (currentDoc.exists) {
        final currentOrder = PosOrder.fromDoc(currentDoc);
        if (_isActiveDineInOrderForTable(currentOrder, table.id) &&
            _matchesCurrentBranch(currentOrder.branchId)) {
          activeOrdersById[currentOrder.id] = currentOrder;
        } else {
          developer.log(
            '[TacoPOS][openTable] currentOrderId stale: $currentOrderId '
            'orderStatus=${currentOrder.status} paymentStatus=${currentOrder.paymentStatus} '
            'orderTableId=${currentOrder.tableId}',
          );
        }
      } else {
        developer.log(
          '[TacoPOS][openTable] currentOrderId missing in Firestore: '
          '$currentOrderId',
        );
      }
    }

    final snapshot = await _ordersRef
        .where('tableId', isEqualTo: table.id)
        .get();
    for (final doc in snapshot.docs) {
      final order = PosOrder.fromDoc(doc);
      if (_isActiveDineInOrderForTable(order, table.id) &&
          _matchesCurrentBranch(order.branchId)) {
        activeOrdersById[order.id] = order;
      }
    }

    if (activeOrdersById.isNotEmpty) {
      _requireAnyPermission(
        takeOrders: true,
        charge: true,
        message: 'No tienes permiso para abrir ordenes.',
      );
      final order = await _bestActiveOrder(activeOrdersById.values.toList());
      await reconcileOrderTableAndKitchenState(
        restaurantId: order.restaurantId,
        branchId: order.branchId,
        orderId: order.id,
        reason: 'open_table_existing_order',
      );
      final itemCount = await _orderItemCount(order.id);
      developer.log(
        '[TacoPOS][openTable] using existing orderId=${order.id} '
        'tableId=${order.tableId} total=${order.total} itemCount=$itemCount '
        'status=${order.status} paymentStatus=${order.paymentStatus}',
      );
      return order;
    }

    _requireTakeOrders();
    final cashSession = await _requireOpenCashSessionForOrder();
    final orderRef = _ordersRef.doc();
    final data = {
      'tableId': table.id,
      'tableName': table.name,
      'orderType': 'dine_in',
      'isTableGroup': false,
      'primaryTableId': table.id,
      'primaryTableName': table.name,
      'tableIds': [table.id],
      'tableNames': [table.name],
      'status': 'open',
      'kitchenStatus': 'pending',
      'paymentStatus': 'pending',
      'total': 0.0,
      'paidTotal': 0.0,
      'pendingTotal': 0.0,
      'personNames': {'1': 'Persona 1'},
      'businessDate': businessDateForOpenCashSession(cashSession),
      'cashSessionId': cashSession.id,
      if (visitClassification != null && isFirstVisit != null) ...{
        'visitClassification': visitClassification,
        'isFirstVisit': isFirstVisit,
        'visitSurveyAnsweredAt': FieldValue.serverTimestamp(),
        'visitSurveyAnsweredBy':
            visitSurveyAnsweredBy?.trim().isNotEmpty == true
            ? visitSurveyAnsweredBy!.trim()
            : (_auth.currentUser?.uid ?? 'anonymous'),
        'visitSurveyVersion': visitSurveyVersion,
      },
      ..._currentBranchFields,
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      ..._employeeAuditFields(prefix: 'createdBy'),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = _db.batch();
    batch.set(orderRef, data);
    batch.set(_tablesRef.doc(table.id), {
      'status': 'occupied',
      'currentOrderId': orderRef.id,
      'currentOrderStatus': 'open',
      'tableGroupId': null,
      'tableGroupLabel': null,
      'groupPrimaryTableId': null,
      'occupiedAt': FieldValue.serverTimestamp(),
      ..._currentBranchFields,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();

    final doc = await orderRef.get();
    final order = PosOrder.fromDoc(doc);
    invalidateReportDataCache(
      branchId: order.branchId,
      startBusinessDate: order.businessDate,
      endBusinessDate: order.businessDate,
    );
    developer.log(
      '[TacoPOS][openTable] created new orderId=${order.id} '
      'tableId=${order.tableId} path=restaurants/${AppConstants.restaurantId}/orders/${order.id}',
    );
    return order;
  }

  bool _isActiveDineInOrderForTable(PosOrder order, String tableId) {
    return order.linkedTableIds.contains(tableId) &&
        isDineInOrder(order) &&
        ['open', 'sent', 'ready', 'cooking'].contains(order.status) &&
        ['pending', 'partial'].contains(order.paymentStatus);
  }

  Future<PosOrder> _bestActiveOrder(List<PosOrder> orders) async {
    final scored = <({PosOrder order, int itemCount})>[];
    for (final order in orders) {
      scored.add((order: order, itemCount: await _orderItemCount(order.id)));
    }
    scored.sort((a, b) {
      final aHasContent = a.itemCount > 0 || a.order.total > 0;
      final bHasContent = b.itemCount > 0 || b.order.total > 0;
      if (aHasContent != bHasContent) {
        return bHasContent ? 1 : -1;
      }
      if (a.itemCount != b.itemCount) {
        return b.itemCount.compareTo(a.itemCount);
      }
      if (a.order.total != b.order.total) {
        return b.order.total.compareTo(a.order.total);
      }
      final aDate =
          a.order.updatedAt ??
          a.order.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          b.order.updatedAt ??
          b.order.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return scored.first.order;
  }

  Future<int> _orderItemCount(String orderId) async {
    final snapshot = await _ordersRef.doc(orderId).collection('items').get();
    return snapshot.docs.length;
  }

  Future<PosOrder> createTakeoutOrder({
    required OrderPlatform platform,
    String? customerName,
    String? visitClassification,
    bool? isFirstVisit,
    String? visitSurveyAnsweredBy,
  }) async {
    _requireTakeOrders();
    final cashSession = await _requireOpenCashSessionForOrder();
    final cleanCustomer = requireCustomerName(
      customerName,
      message: 'Captura el nombre del cliente.',
    );
    final orderRef = _ordersRef.doc();
    final takeoutNumber = await _nextTakeoutNumber();
    final data = {
      'tableId': 'takeout',
      'tableName': 'Para llevar',
      'orderType': 'takeout',
      'platformId': platform.id,
      'platformName': platform.name,
      'takeoutNumber': takeoutNumber,
      'customerName': cleanCustomer,
      'status': 'open',
      'kitchenStatus': 'pending',
      'paymentStatus': 'pending',
      'total': 0.0,
      'paidTotal': 0.0,
      'pendingTotal': 0.0,
      'personNames': {'1': 'Persona 1'},
      'businessDate': businessDateForOpenCashSession(cashSession),
      'cashSessionId': cashSession.id,
      if (visitClassification != null && isFirstVisit != null) ...{
        'visitClassification': visitClassification,
        'isFirstVisit': isFirstVisit,
        'visitSurveyAnsweredAt': FieldValue.serverTimestamp(),
        'visitSurveyAnsweredBy':
            visitSurveyAnsweredBy?.trim().isNotEmpty == true
            ? visitSurveyAnsweredBy!.trim()
            : (_auth.currentUser?.uid ?? 'anonymous'),
        'visitSurveyVersion': visitSurveyVersion,
      },
      ..._currentBranchFields,
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      ..._employeeAuditFields(prefix: 'createdBy'),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await orderRef.set(data);
    final doc = await orderRef.get();
    final order = PosOrder.fromDoc(doc);
    invalidateReportDataCache(
      branchId: order.branchId,
      startBusinessDate: order.businessDate,
      endBusinessDate: order.businessDate,
    );
    return order;
  }

  Future<PosOrder> createStandingOrder({
    required String customerName,
    String? visitClassification,
    bool? isFirstVisit,
    String? visitSurveyAnsweredBy,
  }) async {
    _requireTakeOrders();
    final cleanCustomer = requireCustomerName(
      customerName,
      message: 'Captura el nombre de la persona.',
    );
    final platformsSnapshot = await _platformsRef.get();
    final platform = findInPersonPlatform(
      platformsSnapshot.docs.map(OrderPlatform.fromDoc),
    );
    if (platform == null) {
      throw StateError(
        'No se encontró la plataforma En persona en la configuración.',
      );
    }
    final cashSession = await _requireOpenCashSessionForOrder();
    final orderRef = _ordersRef.doc();
    await orderRef.set({
      'tableId': '',
      'tableName': 'Parados sin mesa',
      'orderType': standingOrderType,
      'customerName': cleanCustomer,
      'platformId': platform.id,
      'platformName': 'En persona',
      'status': 'open',
      'kitchenStatus': 'pending',
      'paymentStatus': 'pending',
      'total': 0.0,
      'paidTotal': 0.0,
      'pendingTotal': 0.0,
      'personNames': {'1': cleanCustomer},
      'businessDate': businessDateForOpenCashSession(cashSession),
      'cashSessionId': cashSession.id,
      if (visitClassification != null && isFirstVisit != null) ...{
        'visitClassification': visitClassification,
        'isFirstVisit': isFirstVisit,
        'visitSurveyAnsweredAt': FieldValue.serverTimestamp(),
        'visitSurveyAnsweredBy':
            visitSurveyAnsweredBy?.trim().isNotEmpty == true
            ? visitSurveyAnsweredBy!.trim()
            : (_auth.currentUser?.uid ?? 'anonymous'),
        'visitSurveyVersion': visitSurveyVersion,
      },
      ..._currentBranchFields,
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      ..._employeeAuditFields(prefix: 'createdBy'),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final order = PosOrder.fromDoc(await orderRef.get());
    invalidateReportDataCache(
      branchId: order.branchId,
      startBusinessDate: order.businessDate,
      endBusinessDate: order.businessDate,
    );
    return order;
  }

  Future<PosOrder> joinTables(List<PosTable> selectedTables) async {
    _requireTakeOrders();
    final decision = evaluateTableJoinSelection(selectedTables);
    if (!decision.allowed) throw StateError(decision.message);
    final selectedIds = selectedTables.map((table) => table.id).toSet();
    final tablesSnapshot = await _tablesRef.get();
    final branchTables = tablesSnapshot.docs
        .map(PosTable.fromDoc)
        .where((table) => _matchesCurrentBranch(table.branchId))
        .toList();
    final currentSelected = branchTables
        .where((table) => selectedIds.contains(table.id))
        .toList();
    if (currentSelected.length != selectedIds.length) {
      throw StateError('Una de las mesas ya no está disponible.');
    }
    final currentDecision = evaluateTableJoinSelection(currentSelected);
    if (!currentDecision.allowed) throw StateError(currentDecision.message);

    PosOrder? existingOrder;
    if (currentDecision.baseOrderId != null) {
      final doc = await _ordersRef.doc(currentDecision.baseOrderId).get();
      if (!doc.exists) {
        throw StateError('La mesa conserva un vínculo obsoleto.');
      }
      existingOrder = PosOrder.fromDoc(doc);
      if (!isActiveOrderState(existingOrder) ||
          !isDineInOrder(existingOrder) ||
          !_matchesCurrentBranch(existingOrder.branchId)) {
        throw StateError('La mesa conserva una orden cerrada u obsoleta.');
      }
    }

    final linkedIds = <String>{
      ...selectedIds,
      ...?existingOrder?.linkedTableIds,
      if (existingOrder != null)
        ...branchTables
            .where((table) => table.currentOrderId?.trim() == existingOrder!.id)
            .map((table) => table.id),
    };
    final groupedTables =
        branchTables.where((table) => linkedIds.contains(table.id)).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (groupedTables.length != linkedIds.length ||
        groupedTables.any((table) => !table.active || !table.isPhysicalTable)) {
      throw StateError('Una de las mesas no es válida para la unión.');
    }

    final primary = existingOrder == null
        ? groupedTables.first
        : groupedTables.firstWhere(
            (table) =>
                table.id ==
                (existingOrder!.primaryTableId ?? existingOrder.tableId),
            orElse: () => groupedTables.first,
          );
    final orderedTables = groupedTables;
    final tableIds = orderedTables.map((table) => table.id).toList();
    final tableNames = orderedTables.map((table) => table.name).toList();
    final label = tableNames.join(' + ');
    final orderRef = existingOrder == null
        ? _ordersRef.doc()
        : _ordersRef.doc(existingOrder.id);
    final cashSession = existingOrder == null
        ? await _requireOpenCashSessionForOrder()
        : null;
    final employee = AppSession.instance.employee;

    await _db.runTransaction((transaction) async {
      DocumentSnapshot<Map<String, dynamic>>? freshOrderDoc;
      if (existingOrder != null) {
        freshOrderDoc = await transaction.get(orderRef);
        if (!freshOrderDoc.exists) {
          throw StateError('La orden base ya no está activa.');
        }
        final freshOrder = PosOrder.fromDoc(freshOrderDoc);
        if (!isActiveOrderState(freshOrder) ||
            !setEquals(
              freshOrder.linkedTableIds.toSet(),
              existingOrder.linkedTableIds.toSet(),
            )) {
          throw StateError(
            'La agrupación cambió. Actualiza e intenta de nuevo.',
          );
        }
      }
      final freshTables = <PosTable>[];
      for (final table in orderedTables) {
        final doc = await transaction.get(_tablesRef.doc(table.id));
        if (!doc.exists) throw StateError('Una de las mesas ya no existe.');
        freshTables.add(PosTable.fromDoc(doc));
      }
      for (final table in freshTables) {
        final linkedOrderId = table.currentOrderId?.trim() ?? '';
        if (!table.active ||
            !table.isPhysicalTable ||
            !_matchesCurrentBranch(table.branchId) ||
            (linkedOrderId.isNotEmpty && linkedOrderId != orderRef.id)) {
          throw StateError(
            'No se pueden juntar mesas que ya tienen órdenes diferentes.',
          );
        }
      }

      final groupFields = {
        'isTableGroup': true,
        'primaryTableId': primary.id,
        'primaryTableName': primary.name,
        'tableIds': tableIds,
        'tableNames': tableNames,
        'tableGroupLabel': label,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (existingOrder == null) {
        transaction.set(orderRef, {
          'tableId': primary.id,
          'tableName': primary.name,
          'orderType': dineInOrderType,
          'status': 'open',
          'kitchenStatus': 'pending',
          'paymentStatus': 'pending',
          'total': 0.0,
          'paidTotal': 0.0,
          'pendingTotal': 0.0,
          'personNames': {'1': 'Persona 1'},
          'businessDate': businessDateForOpenCashSession(cashSession!),
          'cashSessionId': cashSession.id,
          ..._currentBranchFields,
          'createdBy': _auth.currentUser?.uid ?? 'anonymous',
          ..._employeeAuditFields(prefix: 'createdBy'),
          'createdAt': FieldValue.serverTimestamp(),
          ...groupFields,
        });
      } else {
        transaction.set(orderRef, groupFields, SetOptions(merge: true));
      }
      for (final table in freshTables) {
        transaction.set(_tablesRef.doc(table.id), {
          'status': 'occupied',
          'currentOrderId': orderRef.id,
          'currentOrderStatus': existingOrder?.status ?? 'open',
          'tableGroupId': orderRef.id,
          'tableGroupLabel': label,
          'groupPrimaryTableId': primary.id,
          'occupiedAt': table.occupiedAt == null
              ? FieldValue.serverTimestamp()
              : Timestamp.fromDate(table.occupiedAt!),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      final actionType = existingOrder == null
          ? 'tables_joined'
          : 'table_added_to_group';
      transaction.set(_restaurantRef.collection('activityLog').doc(), {
        'type': actionType,
        'actionType': actionType,
        'orderId': orderRef.id,
        'folio': _shortLogFolio(orderRef.id),
        'tableIds': tableIds,
        'tableNames': tableNames,
        'tableGroupLabel': label,
        ..._currentBranchFields,
        'businessDate':
            existingOrder?.businessDate ??
            (cashSession == null
                ? ''
                : businessDateForOpenCashSession(cashSession)),
        'employeeId': employee?.id ?? '',
        'employeeName': employee?.name ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    return PosOrder.fromDoc(await orderRef.get());
  }

  Future<void> removeTableFromGroup({
    required String orderId,
    required String tableId,
  }) async {
    _requireTakeOrders();
    final orderRef = _ordersRef.doc(orderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists) throw StateError('La orden ya no existe.');
    final order = PosOrder.fromDoc(orderDoc);
    if (!order.isTableGroup || order.linkedTableIds.length < 2) {
      throw StateError('La orden no tiene mesas secundarias.');
    }
    final primaryId = order.primaryTableId ?? order.tableId;
    if (tableId == primaryId) {
      throw StateError('No se puede quitar la mesa principal.');
    }
    final tablesSnapshot = await _tablesRef.get();
    final tablesById = {
      for (final doc in tablesSnapshot.docs) doc.id: PosTable.fromDoc(doc),
    };
    final remainingIds = order.linkedTableIds
        .where((id) => id != tableId)
        .toList();
    final remainingTables = remainingIds
        .map((id) => tablesById[id])
        .whereType<PosTable>()
        .toList();
    final removed = tablesById[tableId];
    if (removed == null || remainingTables.length != remainingIds.length) {
      throw StateError('No se pudieron validar las mesas del grupo.');
    }
    final remainingNames = remainingTables.map((table) => table.name).toList();
    final nextLabel = remainingNames.join(' + ');
    final stillGrouped = remainingIds.length > 1;
    final employee = AppSession.instance.employee;

    await _db.runTransaction((transaction) async {
      final freshOrderDoc = await transaction.get(orderRef);
      final freshRemoved = await transaction.get(_tablesRef.doc(tableId));
      final freshRemaining = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final remainingId in remainingIds) {
        freshRemaining.add(await transaction.get(_tablesRef.doc(remainingId)));
      }
      if (!freshOrderDoc.exists ||
          !freshRemoved.exists ||
          freshRemoved.data()?['currentOrderId'] != orderId ||
          freshRemaining.any(
            (doc) => !doc.exists || doc.data()?['currentOrderId'] != orderId,
          )) {
        throw StateError(
          'La mesa cambió de orden. Actualiza e intenta de nuevo.',
        );
      }
      final freshOrder = PosOrder.fromDoc(freshOrderDoc);
      if (!setEquals(
        freshOrder.linkedTableIds.toSet(),
        order.linkedTableIds.toSet(),
      )) {
        throw StateError('La agrupación cambió. Actualiza e intenta de nuevo.');
      }
      transaction.update(orderRef, {
        'isTableGroup': stillGrouped,
        if (stillGrouped) 'tableIds': remainingIds,
        if (!stillGrouped) 'tableIds': FieldValue.delete(),
        if (stillGrouped) 'tableNames': remainingNames,
        if (!stillGrouped) 'tableNames': FieldValue.delete(),
        if (!stillGrouped) 'primaryTableId': FieldValue.delete(),
        if (!stillGrouped) 'primaryTableName': FieldValue.delete(),
        if (stillGrouped) 'tableGroupLabel': nextLabel,
        if (!stillGrouped) 'tableGroupLabel': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(_tablesRef.doc(tableId), {
        'status': 'available',
        'currentOrderId': null,
        'currentOrderStatus': null,
        'tableGroupId': null,
        'tableGroupLabel': null,
        'groupPrimaryTableId': null,
        'occupiedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      for (final table in remainingTables) {
        transaction.set(_tablesRef.doc(table.id), {
          'tableGroupId': stillGrouped ? orderId : null,
          'tableGroupLabel': stillGrouped ? nextLabel : null,
          'groupPrimaryTableId': stillGrouped ? primaryId : null,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      transaction.set(_restaurantRef.collection('activityLog').doc(), {
        'type': 'table_removed_from_group',
        'actionType': 'table_removed_from_group',
        'orderId': orderId,
        'folio': _shortLogFolio(orderId),
        'tableId': tableId,
        'tableName': removed.name,
        'tableIds': remainingIds,
        'tableNames': remainingNames,
        'tableGroupLabel': nextLabel,
        ..._currentBranchFields,
        'businessDate': _businessDateForOrder(order) ?? _currentBusinessDate(),
        'employeeId': employee?.id ?? '',
        'employeeName': employee?.name ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<ExpensePolicySettings> watchExpensePolicySettings() {
    return _expensePolicySettingsRef.snapshots().map(
      (doc) => ExpensePolicySettings.fromMap(doc.data()),
    );
  }

  Future<ExpensePolicySettings> getExpensePolicySettingsOnce() async {
    final doc = await _expensePolicySettingsRef.get();
    return ExpensePolicySettings.fromMap(doc.data());
  }

  Future<void> saveExpensePolicySettings(ExpensePolicySettings settings) async {
    _requireCashWithdrawalAuthorizer();
    await _expensePolicySettingsRef.set({
      ...settings.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': AppSession.instance.employee?.id ?? '',
    }, SetOptions(merge: true));
    await _restaurantRef.collection('activityLog').add({
      'type': 'EXPENSE_POLICY_SETTINGS_UPDATED',
      ..._currentBranchFields,
      'expensePoliciesEnabled': settings.expensePoliciesEnabled,
      'expensePolicyMode': settings.expensePolicyMode.name,
      'manualApprovalCutoffEnabled': settings.manualApprovalCutoffEnabled,
      'manualApprovalCutoffTime': settings.manualApprovalCutoffTime,
      'employeeId': AppSession.instance.employee?.id ?? '',
      'employeeName': AppSession.instance.employee?.name ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<ExpensePolicy>> watchExpensePolicies({bool activeOnly = false}) {
    return _expensePoliciesRef.snapshots().map((snapshot) {
      final policies =
          snapshot.docs
              .map((doc) => ExpensePolicy.fromMap(doc.id, doc.data()))
              .where((policy) => _matchesCurrentBranch(policy.branchId))
              .where((policy) => !activeOnly || policy.active)
              .toList()
            ..sort((a, b) {
              final sort = a.sortOrder.compareTo(b.sortOrder);
              return sort != 0 ? sort : a.name.compareTo(b.name);
            });
      return policies;
    });
  }

  Future<List<ExpensePolicy>> getActiveExpensePoliciesOnce() async {
    final snapshot = await _expensePoliciesRef
        .where('branchId', isEqualTo: AppSession.instance.currentBranchId)
        .get();
    return snapshot.docs
        .map((doc) => ExpensePolicy.fromMap(doc.id, doc.data()))
        .where((policy) => _matchesCurrentBranch(policy.branchId))
        .where((policy) => policy.active)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Stream<List<ExpensePolicyUsage>> watchExpensePolicyUsage(String policyId) {
    return _expensePolicyUsageRef
        .where('policyId', isEqualTo: policyId)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) => ExpensePolicyUsage.fromMap(doc.id, doc.data()))
                  .where((usage) => _matchesCurrentBranch(usage.branchId))
                  .toList()
                ..sort((a, b) => b.periodKey.compareTo(a.periodKey)),
        );
  }

  Stream<List<ExpensePolicyUsage>> watchCurrentBranchExpensePolicyUsage() {
    return _expensePolicyUsageRef
        .where('branchId', isEqualTo: AppSession.instance.currentBranchId)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) => ExpensePolicyUsage.fromMap(doc.id, doc.data()))
                  .where((usage) => _matchesCurrentBranch(usage.branchId))
                  .toList()
                ..sort((a, b) => b.periodKey.compareTo(a.periodKey)),
        );
  }

  Future<String> saveExpensePolicy(ExpensePolicy policy) async {
    _requireCashWithdrawalAuthorizer();
    final employee = AppSession.instance.employee;
    final creating = policy.id.trim().isEmpty;
    final docRef = creating
        ? _expensePoliciesRef.doc()
        : _expensePoliciesRef.doc(policy.id);
    final previousDoc = creating ? null : await docRef.get();
    final previousVersion = previousDoc?.exists == true
        ? ExpensePolicy.fromMap(docRef.id, previousDoc!.data()!).policyVersion
        : 0;
    final version = creating ? 1 : previousVersion + 1;
    final data = policy
        .copyWith(
          id: docRef.id,
          restaurantId: AppSession.instance.currentRestaurantId,
          branchId: policy.branchId.trim().isEmpty
              ? AppSession.instance.currentBranchId
              : policy.branchId,
          policyVersion: version,
          createdBy: creating ? employee?.id ?? '' : policy.createdBy,
          updatedBy: employee?.id ?? '',
        )
        .toMap();
    await docRef.set({
      ...data,
      'id': docRef.id,
      'createdAt': creating
          ? FieldValue.serverTimestamp()
          : previousDoc?.data()?['createdAt'],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _restaurantRef.collection('activityLog').add({
      'type': creating ? 'POLICY_CREATED' : 'POLICY_UPDATED',
      ..._currentBranchFields,
      'policyId': docRef.id,
      'policyName': policy.name,
      'policyVersion': version,
      'employeeId': employee?.id ?? '',
      'employeeName': employee?.name ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<String> duplicateExpensePolicy(
    ExpensePolicy policy, {
    String? targetBranchId,
  }) async {
    final copy = policy.copyWith(
      id: '',
      name: '${policy.name} copia',
      branchId: targetBranchId ?? policy.branchId,
      active: false,
      policyVersion: 1,
    );
    final id = await saveExpensePolicy(copy);
    await _restaurantRef.collection('activityLog').add({
      'type': 'POLICY_DUPLICATED',
      ..._currentBranchFields,
      'sourcePolicyId': policy.id,
      'newPolicyId': id,
      'employeeId': AppSession.instance.employee?.id ?? '',
      'employeeName': AppSession.instance.employee?.name ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  Future<void> setExpensePolicyActive({
    required ExpensePolicy policy,
    required bool active,
  }) async {
    await saveExpensePolicy(policy.copyWith(active: active));
    await _restaurantRef.collection('activityLog').add({
      'type': active ? 'POLICY_ENABLED' : 'POLICY_DISABLED',
      ..._currentBranchFields,
      'policyId': policy.id,
      'employeeId': AppSession.instance.employee?.id ?? '',
      'employeeName': AppSession.instance.employee?.name ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<int> _nextTakeoutNumber() async {
    final snapshot = await _ordersRef.get();
    var maxNumber = 0;
    for (final doc in snapshot.docs) {
      final order = PosOrder.fromDoc(doc);
      if (!_matchesCurrentBranch(order.branchId)) {
        continue;
      }
      final number = (doc.data()['takeoutNumber'] as num?)?.toInt() ?? 0;
      if (number > maxNumber) {
        maxNumber = number;
      }
    }
    return maxNumber + 1;
  }

  Future<void> addProductToOrder({
    required String orderId,
    required Product product,
    required int personNumber,
  }) async {
    _requireTakeOrders();
    final cleanOrderId = orderId.trim();
    final itemsPath =
        'restaurants/${AppConstants.restaurantId}/orders/$cleanOrderId/items';
    developer.log(
      '[TacoPOS][addProduct] orderId=$cleanOrderId path=$itemsPath '
      'productName=${product.name} qty=1',
    );
    final orderDoc = await _ordersRef.doc(cleanOrderId).get();
    final order = orderDoc.exists ? PosOrder.fromDoc(orderDoc) : null;
    if (await isProductStockedOut(product)) {
      throw StateError('Producto agotado hasta cierre de cocina.');
    }
    final personName =
        order?.personName(personNumber) ?? 'Persona $personNumber';
    final platformId = order?.orderType == 'takeout' ? order?.platformId : null;
    final platformName = order?.orderType == 'takeout'
        ? order?.platformName
        : null;
    final usePlatformPrice = platformId != null && platformId != 'en_persona';
    final appliedPrice = usePlatformPrice
        ? product.priceForPlatform(platformId)
        : product.price;
    final existingItem = await _findMatchingPendingItem(
      orderId: cleanOrderId,
      productId: product.id,
      personNumber: personNumber,
      appliedPlatformId: usePlatformPrice ? platformId : null,
    );

    if (existingItem != null) {
      developer.log(
        '[TacoPOS][addProduct] updating existing itemId=${existingItem.id} '
        'path=$itemsPath/${existingItem.id} productName=${product.name} '
        'qty=${existingItem.qty + 1}',
      );
      await updateItemQty(
        orderId: cleanOrderId,
        item: existingItem,
        qty: existingItem.qty + 1,
      );
      return;
    }

    final primaryRecipe = product.recipeItems.isNotEmpty
        ? product.recipeItems.first
        : null;
    final itemRef = _ordersRef.doc(cleanOrderId).collection('items').doc();
    await itemRef.set({
      'personNumber': personNumber,
      'personName': personName,
      'productId': product.id,
      'productName': product.name,
      'categoryId': product.categoryId,
      'categoryName': product.categoryName,
      'category': product.category,
      'qty': 1,
      'unitPrice': appliedPrice,
      'total': appliedPrice,
      'appliedPlatformId': usePlatformPrice ? platformId : null,
      'appliedPlatformName': usePlatformPrice ? platformName : null,
      'priceSource': usePlatformPrice ? 'platform' : 'store',
      'notes': '',
      ..._currentBranchFields,
      ..._employeeAuditFields(prefix: 'createdBy'),
      'sendToKitchen': product.sendToKitchen,
      'affectsKitchenStock': product.affectsKitchenStock,
      'recipeItems': product.affectsKitchenStock
          ? ProductRecipeItem.toMapList(product.recipeItems.take(1).toList())
          : const [],
      'kitchenStockItemId': product.affectsKitchenStock
          ? primaryRecipe?.kitchenStockItemId ?? product.kitchenStockItemId
          : null,
      'kitchenStockItemName': product.affectsKitchenStock
          ? primaryRecipe?.kitchenStockItemName ?? product.kitchenStockItemName
          : null,
      'kitchenStockUnit': product.affectsKitchenStock
          ? primaryRecipe?.kitchenStockUnit ?? product.kitchenStockUnit
          : null,
      'stockConsumptionQty': product.affectsKitchenStock
          ? primaryRecipe?.consumptionFactor ?? product.stockConsumptionQty
          : null,
      'kitchenConsumptionFactor': product.affectsKitchenStock
          ? primaryRecipe?.consumptionFactor ?? product.stockConsumptionQty
          : null,
      'kitchenStatus': product.sendToKitchen ? 'pending' : 'not_required',
      'kitchenBatchId': null,
      'paymentStatus': 'pending',
      'status': 'active',
      'cancelStatus': 'none',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    developer.log(
      '[TacoPOS][addProduct] saved itemId=${itemRef.id} '
      'path=$itemsPath/${itemRef.id} productName=${product.name} qty=1',
    );
    await recalculateOrderTotal(cleanOrderId);
  }

  Future<void> renamePerson({
    required String orderId,
    required int personNumber,
    required String name,
  }) async {
    _requireTakeOrders();
    final cleanName = name.trim().isEmpty
        ? 'Persona $personNumber'
        : name.trim();
    final orderRef = _ordersRef.doc(orderId);
    final itemsSnapshot = await orderRef.collection('items').get();
    final batch = _db.batch();

    batch.update(orderRef, {
      'personNames.$personNumber': cleanName,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.personNumber == personNumber) {
        batch.update(doc.reference, {
          'personName': cleanName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();
  }

  Future<OrderItem?> _findMatchingPendingItem({
    required String orderId,
    required String productId,
    required int personNumber,
    String? appliedPlatformId,
  }) async {
    final snapshot = await _ordersRef.doc(orderId).collection('items').get();

    for (final doc in snapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.productId == productId &&
          item.personNumber == personNumber &&
          item.appliedPlatformId == appliedPlatformId &&
          itemIsAwaitingKitchenSend(item) &&
          item.paymentStatus == 'pending') {
        return item;
      }
    }
    return null;
  }

  Future<void> updateItemQty({
    required String orderId,
    required OrderItem item,
    required int qty,
  }) async {
    _requireTakeOrders();
    _ensureItemEditable(item);
    if (qty <= 0) {
      await deleteItem(orderId: orderId, itemId: item.id);
      return;
    }

    await _ordersRef.doc(orderId).collection('items').doc(item.id).update({
      'qty': qty,
      'total': qty * item.unitPrice,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await recalculateOrderTotal(orderId);
  }

  Future<void> deleteItem({
    required String orderId,
    required String itemId,
    String reason = 'Cancelado desde orden',
  }) async {
    await cancelOrderItem(orderId: orderId, itemId: itemId, reason: reason);
  }

  Future<void> cancelOrderItem({
    required String orderId,
    required String itemId,
    required String reason,
  }) async {
    _requireCancelItems();
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Captura el motivo de cancelacion.');
    }
    final itemDoc = await _ordersRef
        .doc(orderId)
        .collection('items')
        .doc(itemId)
        .get();
    if (!itemDoc.exists) {
      throw StateError('El articulo ya no existe.');
    }
    final item = OrderItem.fromDoc(itemDoc);
    if (item.isCancelled) {
      return;
    }
    if (item.kitchenStatus == 'ready') {
      throw StateError(
        'Este producto ya fue servido por cocina y no puede cancelarse.',
      );
    }
    if (['sent', 'cooking', 'cancel_requested'].contains(item.kitchenStatus)) {
      throw StateError(
        'Este producto ya esta en cocina. Solicita cancelacion a cocina.',
      );
    }
    if (item.paymentStatus == 'paid') {
      throw StateError('Este producto ya fue pagado y no puede cancelarse.');
    }
    await _ensureCancellationKeepsPaymentsValid(orderId, item);
    await itemDoc.reference.update({
      'status': 'cancelled',
      'kitchenStatus': 'cancelled',
      'paymentStatus': 'cancelled',
      'cancelStatus': 'accepted',
      'cancelReason': cleanReason,
      'cancelledAt': FieldValue.serverTimestamp(),
      ..._employeeAuditFields(prefix: 'cancelledBy'),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _reconcileOrderAfterItemCancellation(
      orderId,
      reason: 'order_item_cancelled',
    );
    await _restaurantRef.collection('activityLog').add({
      'type': 'order_item_cancelled',
      ..._currentBranchFields,
      'orderId': orderId,
      'itemId': item.id,
      'productName': item.productName,
      'qty': item.qty,
      'reason': cleanReason,
      'employeeId': AppSession.instance.employee?.id ?? '',
      'employeeName': AppSession.instance.employee?.name ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
    });
  }

  Future<void> requestOrderItemCancellation({
    required String orderId,
    required String itemId,
    required String reason,
  }) async {
    _requireCancelItems();
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Captura el motivo de cancelacion.');
    }
    final itemRef = _ordersRef.doc(orderId).collection('items').doc(itemId);
    final itemDoc = await itemRef.get();
    if (!itemDoc.exists) {
      throw StateError('El articulo ya no existe.');
    }
    final item = OrderItem.fromDoc(itemDoc);
    if (item.kitchenStatus == 'ready') {
      throw StateError(
        'Este producto ya fue servido por cocina y no puede cancelarse.',
      );
    }
    if (!['sent', 'cooking', 'cancel_requested'].contains(item.kitchenStatus)) {
      throw StateError('Solo se solicita cancelacion de articulos en cocina.');
    }
    if (item.hasCancellationRequested) {
      throw StateError('La cancelacion ya fue solicitada a cocina.');
    }
    await itemRef.update({
      'cancelStatus': 'requested',
      'kitchenStatus': 'cancel_requested',
      'cancelReason': cleanReason,
      'cancelRequestedAt': FieldValue.serverTimestamp(),
      ..._employeeAuditFields(prefix: 'cancelRequestedBy'),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _ordersRef.doc(orderId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resolveKitchenCancellation({
    required String orderId,
    required String itemId,
    required bool accepted,
    String rejectReason = '',
  }) async {
    _requireKitchenCancellationApprover();
    final itemRef = _ordersRef.doc(orderId).collection('items').doc(itemId);
    final itemDoc = await itemRef.get();
    if (!itemDoc.exists) {
      throw StateError('El articulo ya no existe.');
    }
    final item = OrderItem.fromDoc(itemDoc);
    if (!item.hasCancellationRequested) {
      throw StateError('Este articulo no tiene cancelacion solicitada.');
    }
    if (item.isCancelled) {
      return;
    }
    if (accepted) {
      await _ensureCancellationKeepsPaymentsValid(orderId, item);
      final now = FieldValue.serverTimestamp();
      await itemRef.update({
        'status': 'cancelled',
        'kitchenStatus': 'cancelled',
        'paymentStatus': 'cancelled',
        'cancelStatus': 'accepted',
        'cancelAcceptedAt': now,
        'cancelledAt': item.cancelledAt ?? now,
        ..._employeeAuditFields(prefix: 'cancelAcceptedBy'),
        ..._employeeAuditFields(prefix: 'cancelledBy'),
        'updatedAt': now,
      });
      await _reconcileOrderAfterItemCancellation(
        orderId,
        reason: 'kitchen_cancellation_accepted',
      );
      return;
    }

    final restoredKitchenStatus = item.cookingAt != null ? 'cooking' : 'sent';
    await itemRef.update({
      'cancelStatus': 'rejected',
      'kitchenStatus': restoredKitchenStatus,
      'cancelRejectedAt': FieldValue.serverTimestamp(),
      'cancelRejectReason': rejectReason.trim(),
      ..._employeeAuditFields(prefix: 'cancelRejectedBy'),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _ordersRef.doc(orderId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _reconcileOrderAfterItemCancellation(
    String orderId, {
    required String reason,
  }) async {
    final orderRef = _ordersRef.doc(orderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists) {
      throw StateError('La orden ya no existe.');
    }
    final order = PosOrder.fromDoc(orderDoc);
    final itemsSnapshot = await orderRef.collection('items').get();
    final items = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
    final activeItems = activeOrderItems(items);

    if (activeItems.isEmpty) {
      await recalculateOrderTotal(orderId);
      final ghostRepair = await _autoCancelGhostOrderIfNeeded(
        orderId,
        triggeredBy: reason,
      );
      if (ghostRepair == null) {
        await _syncOrderKitchenStateAfterItemChange(orderId);
      }
      return;
    }

    final payments = await getOrderPaymentsOnce(orderId);
    final paidTotal = payments
        .where((payment) => payment.isActive)
        .fold<double>(0, (total, payment) => total + payment.baseAmount);
    final grossSubtotal = activeOrderItemsTotal(activeItems);
    final discountAmount = order.explicitDiscount
        .clamp(0, grossSubtotal)
        .toDouble();
    final netTotal = (grossSubtotal - discountAmount)
        .clamp(0, double.infinity)
        .toDouble();
    final adjustedPaidTotal = paidTotal.clamp(0, netTotal).toDouble();
    final pendingTotal = (netTotal - adjustedPaidTotal)
        .clamp(0, double.infinity)
        .toDouble();
    final nextPaymentStatus = adjustedPaidTotal <= 0
        ? 'pending'
        : pendingTotal <= 0.01
        ? 'paid'
        : 'partial';
    final nextKitchenStatus = kitchenStatusForItems(items);
    final nextOrderStatus = _orderStatusForKitchenState(
      nextKitchenStatus,
      hasActiveBillableItems: true,
    );
    final pendingKitchenItems = items.where(isKitchenPendingItem).toList();
    final batchesSnapshot = await orderRef.collection('kitchenBatches').get();
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();

    batch.update(orderRef, {
      'status': nextOrderStatus,
      'kitchenStatus': nextKitchenStatus,
      'paymentStatus': nextPaymentStatus,
      'total': grossSubtotal,
      'grossSubtotal': grossSubtotal,
      'netTotal': netTotal,
      'paidTotal': adjustedPaidTotal,
      'pendingTotal': pendingTotal,
      'hasPendingKitchenItems': pendingKitchenItems.isNotEmpty,
      'pendingKitchenItemsCount': pendingKitchenItems.length,
      'cancelStatus': 'none',
      'cancelReason': FieldValue.delete(),
      'cancelledAt': FieldValue.delete(),
      'canceledAt': FieldValue.delete(),
      'cancelledByEmployeeId': FieldValue.delete(),
      'cancelledByEmployeeName': FieldValue.delete(),
      'updatedAt': now,
    });

    for (final batchDoc in batchesSnapshot.docs) {
      final batchId = batchDoc.id.trim();
      if (batchId.isEmpty) continue;
      final itemsInBatch = items
          .where((item) => item.kitchenBatchId?.trim() == batchId)
          .toList();
      if (itemsInBatch.isEmpty) continue;
      final activeInBatch = activeOrderItems(itemsInBatch);
      if (activeInBatch.isEmpty) {
        batch.set(batchDoc.reference, {
          'status': 'cancelled',
          'itemCount': 0,
          'activeItemCount': 0,
          'cancelledAt': now,
          'cancelReason': 'Todos los productos del batch fueron cancelados',
          ..._employeeAuditFields(prefix: 'cancelledBy'),
          'updatedAt': now,
        }, SetOptions(merge: true));
        continue;
      }
      batch.set(batchDoc.reference, {
        'status': _kitchenBatchStatusForItems(activeInBatch),
        'itemCount': activeInBatch.length,
        'activeItemCount': activeInBatch.length,
        'cancelledAt': FieldValue.delete(),
        'cancelReason': FieldValue.delete(),
        'updatedAt': now,
      }, SetOptions(merge: true));
    }

    _setLinkedTablesStateInBatch(batch, order, status: 'occupied');
    _logActivityInBatch(
      batch,
      type: 'partial_item_cancellation_reconciled',
      orderId: order.id,
      data: {
        'actionType': 'partial_item_cancellation_reconciled',
        'reason': reason,
        'activeItemsCount': activeItems.length,
        'cancelledItemsCount': items.length - activeItems.length,
        'grossSubtotal': grossSubtotal,
        'netTotal': netTotal,
        'pendingTotal': pendingTotal,
        'previousOrderStatus': order.status,
        'newOrderStatus': nextOrderStatus,
        'previousKitchenStatus': order.kitchenStatus,
        'newKitchenStatus': nextKitchenStatus,
        'message':
            'Se reconcilio una cancelacion parcial conservando los productos activos.',
      },
    );
    await batch.commit();
    invalidateReportDataCache(
      branchId: order.branchId,
      startBusinessDate: order.businessDate,
      endBusinessDate: order.businessDate,
    );
  }

  String _kitchenBatchStatusForItems(Iterable<OrderItem> items) {
    final status = kitchenStatusForItems(items);
    return switch (status) {
      'cooking' => 'cooking',
      'ready' => 'ready',
      'sent' || 'pending' => 'sent',
      _ => 'sent',
    };
  }

  Future<void> _syncOrderKitchenStateAfterItemChange(String orderId) async {
    final orderRef = _ordersRef.doc(orderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists) {
      return;
    }
    final order = PosOrder.fromDoc(orderDoc);
    if (_isFinalOrderStatus(order.status)) {
      return;
    }

    final itemsSnapshot = await orderRef.collection('items').get();
    final items = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
    final activeBillableItems = items.where(isActiveOrderItem).toList();
    final activeKitchenItems = items.where(isKitchenPendingItem).toList();
    final activeReadyKitchenItems = items.where(isKitchenReadyItem);

    final nextKitchenStatus = _kitchenStatusForActiveItems(
      activeKitchenItems,
      hasReadyItems: activeReadyKitchenItems.isNotEmpty,
    );
    final nextOrderStatus = _orderStatusForKitchenState(
      nextKitchenStatus,
      hasActiveBillableItems: activeBillableItems.isNotEmpty,
    );

    final batch = _db.batch();
    batch.update(orderRef, {
      'status': nextOrderStatus,
      'kitchenStatus': nextKitchenStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    _setLinkedTablesStateInBatch(
      batch,
      order,
      status: _tableStatusForKitchenState(),
    );

    await batch.commit();
  }

  String _kitchenStatusForActiveItems(
    Iterable<OrderItem> activeKitchenItems, {
    required bool hasReadyItems,
  }) {
    final statuses = activeKitchenItems
        .map((item) => normalizeStatus(item.kitchenStatus))
        .toSet();
    if (statuses.contains('cooking')) {
      return 'cooking';
    }
    if (statuses.contains('sent')) {
      return 'sent';
    }
    if (statuses.contains('pending')) {
      return 'pending';
    }
    return hasReadyItems ? 'ready' : 'not_required';
  }

  String _orderStatusForKitchenState(
    String kitchenStatus, {
    required bool hasActiveBillableItems,
  }) {
    if (!hasActiveBillableItems) {
      return 'open';
    }
    if (kitchenStatus == 'ready') {
      return 'ready';
    }
    if (kitchenStatus == 'cooking') {
      return 'cooking';
    }
    if (kitchenStatus == 'sent' || kitchenStatus == 'pending') {
      return 'sent';
    }
    return 'open';
  }

  String _tableStatusForKitchenState() {
    return 'occupied';
  }

  Future<void> cancelOrder({
    required String orderId,
    required String reason,
  }) async {
    _requireCancelOrders();
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Captura el motivo de cancelacion.');
    }

    final orderRef = _ordersRef.doc(orderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists) {
      throw StateError('La orden ya no existe.');
    }
    final order = PosOrder.fromDoc(orderDoc);
    if (_isPaidStatus(order.paymentStatus) ||
        (order.paidAt != null && order.paidTotal > 0.01)) {
      throw StateError('No se puede cancelar una orden pagada al 100%.');
    }

    final itemsSnapshot = await orderRef.collection('items').get();
    final items = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
    final activeItems = items.where(isActiveOrderItem).toList();
    if (activeItems.any((item) => item.kitchenStatus == 'ready')) {
      throw StateError(
        'No se puede cancelar: hay productos servidos por cocina.',
      );
    }

    final paymentsSnapshot = await orderRef.collection('payments').get();
    final activePayments = paymentsSnapshot.docs
        .map(Payment.fromDoc)
        .where(isActivePayment)
        .toList();
    final activePaidTotal = activePayments.fold<double>(
      0,
      (total, payment) => total + payment.baseAmount,
    );
    if (activePayments.isNotEmpty && activePaidTotal > 0.01) {
      throw StateError('No se puede cancelar: los pagos cierran la orden.');
    }

    final batch = _db.batch();
    final audit = _employeeAuditFields(prefix: 'cancelledBy');
    batch.update(orderRef, {
      'status': 'cancelled',
      'kitchenStatus': 'cancelled',
      'paymentStatus': 'cancelled',
      'total': 0.0,
      'paidTotal': 0.0,
      'pendingTotal': 0.0,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelReason': cleanReason,
      ...audit,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.isCancelled) {
        continue;
      }
      batch.update(doc.reference, {
        'kitchenStatus': 'cancelled',
        'paymentStatus': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelReason': cleanReason,
        ...audit,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _logActivityInBatch(
        batch,
        type: 'order_item_cancelled',
        orderId: order.id,
        data: {
          'itemId': item.id,
          'productName': item.productName,
          'qty': item.qty,
          'reason': cleanReason,
        },
      );
    }

    _setLinkedTablesStateInBatch(batch, order, release: true);

    _logActivityInBatch(
      batch,
      type: 'order_cancelled',
      orderId: order.id,
      data: {'reason': cleanReason, 'total': order.total},
    );
    await batch.commit();
    invalidateReportDataCache(
      branchId: order.branchId,
      startBusinessDate: order.businessDate,
      endBusinessDate: order.businessDate,
    );
  }

  Future<void> cancelEmptyOrder(String orderId) async {
    final orderDoc = await _ordersRef.doc(orderId).get();
    if (!orderDoc.exists) {
      throw StateError('La orden ya no existe.');
    }
    final order = PosOrder.fromDoc(orderDoc);
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final paymentsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('payments')
        .get();

    if (itemsSnapshot.docs.isNotEmpty) {
      throw StateError('No se puede cerrar: la orden ya tiene articulos.');
    }
    if (paymentsSnapshot.docs.isNotEmpty) {
      throw StateError('No se puede cerrar: la orden ya tiene pagos.');
    }
    if (order.status != 'open' ||
        order.sentToKitchenAt != null ||
        ['sent', 'cooking', 'ready'].contains(order.kitchenStatus)) {
      throw StateError('No se puede cerrar: la orden ya fue enviada a cocina.');
    }

    final batch = _db.batch();
    batch.update(_ordersRef.doc(orderId), {
      'status': 'cancelled',
      'kitchenStatus': 'cancelled',
      'paymentStatus': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      ..._employeeAuditFields(prefix: 'cancelledBy'),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    _setLinkedTablesStateInBatch(batch, order, release: true);

    await batch.commit();
    invalidateReportDataCache(
      branchId: order.branchId,
      startBusinessDate: order.businessDate,
      endBusinessDate: order.businessDate,
    );
  }

  Future<int> sendOrderToKitchen(String orderId) async {
    _requireTakeOrders();
    final orderRef = _ordersRef.doc(orderId);
    final itemRefs = (await orderRef.collection('items').get()).docs
        .map((doc) => doc.reference)
        .toList(growable: false);
    if (itemRefs.isEmpty) return 0;

    final result = await _db.runTransaction<_KitchenSendTransactionResult>((
      transaction,
    ) async {
      final orderDoc = await transaction.get(orderRef);
      if (!orderDoc.exists) {
        throw StateError('La orden ya no existe.');
      }
      final order = PosOrder.fromDoc(orderDoc);
      if (isCancelledOrder(order) || isPaidOrder(order)) {
        return _KitchenSendTransactionResult(order: order, sentCount: 0);
      }

      final itemDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in itemRefs) {
        final doc = await transaction.get(ref);
        if (doc.exists) itemDocs.add(doc);
      }
      final allItems = itemDocs.map(OrderItem.fromDoc).toList();
      final itemsToSend = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in itemDocs) {
        final item = OrderItem.fromDoc(doc);
        if (itemCanBeSentToKitchenBatch(item)) {
          itemsToSend.add(doc);
        }
      }
      _logKitchenSendDiagnostic(
        orderId: order.id,
        items: allItems,
        pendingItemIds: itemsToSend.map((doc) => doc.id).toList(),
      );
      if (itemsToSend.isEmpty) {
        return _KitchenSendTransactionResult(order: order, sentCount: 0);
      }

      final isExpressBatch = allItems.any((item) {
        if (!item.sendToKitchen || item.isCancelled) return false;
        final status = normalizeStatus(item.kitchenStatus);
        final batchId = item.kitchenBatchId?.trim();
        return batchId != null &&
            batchId.isNotEmpty &&
            {'sent', 'cooking', 'ready'}.contains(status);
      });
      final kitchenBatchType = isExpressBatch ? 'express' : 'initial';
      final kitchenBatchLabel = isExpressBatch
          ? 'Orden extra'
          : 'Orden inicial';
      final kitchenBatchId = orderRef.collection('kitchenBatches').doc().id;
      final batchCreatedAt = Timestamp.now();

      transaction
          .set(orderRef.collection('kitchenBatches').doc(kitchenBatchId), {
            'restaurantId': order.restaurantId,
            'restaurantName': order.restaurantName,
            'branchId': order.branchId,
            'branchName': order.branchName,
            'orderId': order.id,
            'status': 'sent',
            'type': kitchenBatchType,
            'label': kitchenBatchLabel,
            'itemCount': itemsToSend.length,
            'createdAt': batchCreatedAt,
            'updatedAt': FieldValue.serverTimestamp(),
            ..._employeeAuditFields(prefix: 'createdBy'),
          });

      for (final doc in itemsToSend) {
        transaction.update(doc.reference, {
          'kitchenStatus': 'sent',
          'kitchenBatchId': kitchenBatchId,
          'kitchenBatchCreatedAt': batchCreatedAt,
          'batchCreatedAt': batchCreatedAt,
          'isKitchenExpress': isExpressBatch,
          'expressReason': isExpressBatch ? 'Orden extra' : '',
          'expressPriority': isExpressBatch,
          if (isExpressBatch) 'expressCreatedAt': batchCreatedAt,
          'kitchenBatchType': kitchenBatchType,
          'kitchenBatchLabel': kitchenBatchLabel,
          'sentToKitchenAt': batchCreatedAt,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      transaction.update(orderRef, {
        'status': 'sent',
        'kitchenStatus': 'sent',
        'lastKitchenBatchId': kitchenBatchId,
        'lastKitchenBatchType': kitchenBatchType,
        'lastKitchenBatchLabel': kitchenBatchLabel,
        if (order.sentToKitchenAt == null) 'sentToKitchenAt': batchCreatedAt,
        'lastSentToKitchenAt': batchCreatedAt,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _setLinkedTablesStateInTransaction(transaction, order, status: 'sent');
      return _KitchenSendTransactionResult(
        order: order,
        sentCount: itemsToSend.length,
      );
    });

    if (result.sentCount == 0) {
      return 0;
    }

    invalidateReportDataCache(
      branchId: result.order.branchId,
      startBusinessDate: result.order.businessDate,
      endBusinessDate: result.order.businessDate,
    );
    return result.sentCount;
  }

  void _logKitchenSendDiagnostic({
    required String orderId,
    required List<OrderItem> items,
    required List<String> pendingItemIds,
  }) {
    final activeItems = items.where(isActiveOrderItem).toList();
    final requiresKitchen = activeItems.where(itemRequiresKitchen).toList();
    final alreadySent = requiresKitchen.where(itemWasSentToKitchen).toList();
    final pendingIds = pendingItemIds.toSet();
    final itemDetails = items
        .map(
          (item) =>
              '${item.id}{status=${item.status}, kitchenStatus=${item.kitchenStatus}, '
              'paymentStatus=${item.paymentStatus}, sendToKitchen=${item.sendToKitchen}, '
              'sentAt=${item.sentToKitchenAt?.toIso8601String() ?? '-'}, '
              'batch=${item.kitchenBatchId ?? '-'}, '
              'pending=${pendingIds.contains(item.id)}}',
        )
        .join('; ');
    developer.log(
      '[TacoPOS][sendKitchen.diagnostic] orderId=$orderId '
      'activeItems=${activeItems.length} requiresKitchen=${requiresKitchen.length} '
      'alreadySent=${alreadySent.length} pendingDetected=${pendingItemIds.length} '
      'pendingItemIds=${pendingItemIds.join(',')} items=[$itemDetails]',
    );
  }

  Future<PosOrder> changeOrderTable({
    required String orderId,
    required String destinationTableId,
  }) async {
    _requireTakeOrders();
    final cleanOrderId = orderId.trim();
    final cleanDestinationId = destinationTableId.trim();
    if (cleanOrderId.isEmpty || cleanDestinationId.isEmpty) {
      throw ArgumentError('Selecciona una orden y una mesa destino.');
    }

    final orderRef = _ordersRef.doc(cleanOrderId);
    final destinationRef = _tablesRef.doc(cleanDestinationId);
    final employee = AppSession.instance.employee;

    await _db.runTransaction((transaction) async {
      final orderDoc = await transaction.get(orderRef);
      final destinationDoc = await transaction.get(destinationRef);
      if (!orderDoc.exists) {
        throw StateError('La orden ya no existe.');
      }
      if (!destinationDoc.exists) {
        throw StateError('La mesa destino ya no existe.');
      }

      final order = PosOrder.fromDoc(orderDoc);
      final destination = PosTable.fromDoc(destinationDoc);
      if (!isActiveOrderState(order)) {
        throw StateError('Solo se pueden mover ordenes abiertas.');
      }
      final decision = evaluateChangeTableDestination(
        order: order,
        destination: destination,
      );
      if (!decision.allowed) {
        throw StateError(decision.message);
      }
      if (!_matchesCurrentBranch(order.branchId) ||
          !_matchesCurrentBranch(destination.branchId)) {
        throw StateError(
          'La orden y la mesa deben pertenecer a esta sucursal.',
        );
      }

      final sourceRefs = orderUsesPhysicalTables(order)
          ? order.linkedTableIds
                .where((id) => id.trim().isNotEmpty)
                .map((id) => _tablesRef.doc(id))
                .toList(growable: false)
          : const <DocumentReference<Map<String, dynamic>>>[];
      final sourceDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in sourceRefs) {
        sourceDocs.add(await transaction.get(ref));
      }
      for (final doc in sourceDocs) {
        if (!doc.exists) continue;
        final sourceTable = PosTable.fromDoc(doc);
        if (sourceTable.currentOrderId?.trim() != order.id) {
          throw StateError(
            'La mesa origen cambio de orden. Actualiza e intenta de nuevo.',
          );
        }
      }

      final sourceType = isStandingOrder(order) ? 'standing' : 'table';
      final sourceTableIds = order.linkedTableIds;
      final sourceTableNames = order.tableNames.isNotEmpty
          ? order.tableNames
          : [if (order.tableName.trim().isNotEmpty) order.tableName];
      final destinationName = destination.name;
      final now = FieldValue.serverTimestamp();

      transaction.update(orderRef, {
        'tableId': destination.id,
        'tableName': destinationName,
        'orderType': dineInOrderType,
        'isTableGroup': false,
        'primaryTableId': destination.id,
        'primaryTableName': destinationName,
        'tableIds': [destination.id],
        'tableNames': [destinationName],
        'tableGroupLabel': FieldValue.delete(),
        'platformId': isStandingOrder(order)
            ? FieldValue.delete()
            : order.platformId,
        'platformName': isStandingOrder(order)
            ? FieldValue.delete()
            : order.platformName,
        'previousOrderType': order.orderType,
        'previousTableId': order.tableId,
        'previousTableName': order.displayName,
        'changedTableAt': now,
        ..._employeeAuditFields(prefix: 'changedTableBy'),
        'updatedAt': now,
      });

      for (final doc in sourceDocs) {
        transaction.set(doc.reference, {
          'status': 'available',
          'currentOrderId': null,
          'currentOrderStatus': null,
          'tableGroupId': null,
          'tableGroupLabel': null,
          'groupPrimaryTableId': null,
          'occupiedAt': null,
          ..._currentBranchFields,
          'updatedAt': now,
        }, SetOptions(merge: true));
      }

      transaction.set(destinationRef, {
        'status': 'occupied',
        'currentOrderId': order.id,
        'currentOrderStatus': order.status,
        'tableGroupId': null,
        'tableGroupLabel': null,
        'groupPrimaryTableId': null,
        'occupiedAt': destination.occupiedAt == null
            ? now
            : Timestamp.fromDate(destination.occupiedAt!),
        ..._currentBranchFields,
        'updatedAt': now,
      }, SetOptions(merge: true));

      transaction.set(_restaurantRef.collection('activityLog').doc(), {
        'type': 'change_table',
        'actionType': 'CHANGE_TABLE',
        'orderId': order.id,
        'folio': _shortLogFolio(order.id),
        'sourceType': sourceType,
        'sourceTableId': order.tableId,
        'sourceTableName': order.displayName,
        'sourceTableIds': sourceTableIds,
        'sourceTableNames': sourceTableNames,
        'destinationType': 'table',
        'destinationTableId': destination.id,
        'destinationTableName': destinationName,
        ..._currentBranchFields,
        'businessDate': _businessDateForOrder(order) ?? _currentBusinessDate(),
        'employeeId': employee?.id ?? '',
        'employeeName': employee?.name ?? '',
        'timestamp': now,
        'createdAt': now,
      });
    });

    final updatedOrder = PosOrder.fromDoc(await orderRef.get());
    invalidateReportDataCache(
      branchId: updatedOrder.branchId,
      startBusinessDate: updatedOrder.businessDate,
      endBusinessDate: updatedOrder.businessDate,
    );
    return updatedOrder;
  }

  Future<void> updateKitchenStatus({
    required String orderId,
    required String status,
    String? kitchenBatchId,
  }) async {
    final normalizedStatus = status == 'preparing' ? 'cooking' : status;
    final cleanBatchId = kitchenBatchId?.trim();
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final batch = _db.batch();
    var changed = 0;

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.sendToKitchen &&
          !item.isCancelled &&
          (cleanBatchId == null ||
              cleanBatchId.isEmpty ||
              item.kitchenBatchId?.trim() == cleanBatchId) &&
          ['sent', 'cooking'].contains(item.kitchenStatus)) {
        changed += 1;
        batch.update(doc.reference, {
          'kitchenStatus': normalizedStatus,
          if (normalizedStatus == 'cooking' && item.cookingAt == null)
            'cookingAt': FieldValue.serverTimestamp(),
          if (normalizedStatus == 'ready')
            'readyAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    if (changed == 0) {
      return;
    }

    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = orderDoc.exists ? PosOrder.fromDoc(orderDoc) : null;
    final orderStatus = normalizedStatus == 'ready'
        ? 'ready'
        : normalizedStatus == 'cooking'
        ? 'cooking'
        : 'sent';

    batch.update(_ordersRef.doc(orderId), {
      'status': orderStatus,
      'kitchenStatus': normalizedStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _logActivityInBatch(
      batch,
      type: 'kitchen_status_changed',
      orderId: orderId,
      data: {'kitchenStatus': normalizedStatus},
    );

    if (order != null) {
      _setLinkedTablesStateInBatch(batch, order, status: orderStatus);
    }

    await batch.commit();
    if (order != null) {
      await reconcileOrderTableAndKitchenState(
        restaurantId: order.restaurantId,
        branchId: order.branchId,
        orderId: order.id,
        reason: 'kitchen_status_updated',
      );
    }
  }

  Future<void> updateKitchenItemsStatus({
    required String orderId,
    required Iterable<String> itemIds,
    required String status,
  }) async {
    final normalizedStatus = status == 'preparing' ? 'cooking' : status;
    final targetIds = itemIds.toSet();
    if (targetIds.isEmpty) {
      return;
    }

    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final allItems = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
    final batch = _db.batch();
    final changedIds = <String>{};

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (targetIds.contains(item.id) &&
          item.sendToKitchen &&
          !item.isCancelled &&
          ['sent', 'cooking'].contains(item.kitchenStatus)) {
        changedIds.add(item.id);
        batch.update(doc.reference, {
          'kitchenStatus': normalizedStatus,
          if (normalizedStatus == 'cooking' && item.cookingAt == null)
            'cookingAt': FieldValue.serverTimestamp(),
          if (normalizedStatus == 'ready')
            'readyAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    if (changedIds.isEmpty) {
      return;
    }

    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = orderDoc.exists ? PosOrder.fromDoc(orderDoc) : null;
    final kitchenStatus = _aggregateKitchenStatus(
      allItems: allItems,
      changedIds: changedIds,
      changedStatus: normalizedStatus,
    );
    final orderStatus = ['ready', 'not_required'].contains(kitchenStatus)
        ? 'ready'
        : kitchenStatus == 'cooking'
        ? 'cooking'
        : 'sent';

    batch.update(_ordersRef.doc(orderId), {
      'status': orderStatus,
      'kitchenStatus': kitchenStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _logActivityInBatch(
      batch,
      type: 'kitchen_status_changed',
      orderId: orderId,
      data: {'kitchenStatus': kitchenStatus},
    );

    if (order != null) {
      _setLinkedTablesStateInBatch(batch, order, status: orderStatus);
    }

    await batch.commit();
    if (order != null) {
      await reconcileOrderTableAndKitchenState(
        restaurantId: order.restaurantId,
        branchId: order.branchId,
        orderId: order.id,
        reason: 'kitchen_items_status_updated',
      );
    }
  }

  String _aggregateKitchenStatus({
    required List<OrderItem> allItems,
    required Set<String> changedIds,
    required String changedStatus,
  }) {
    var hasPending = false;
    var hasSent = false;
    var hasCooking = false;
    var hasReady = false;

    for (final item in allItems.where(
      (item) => itemRequiresKitchen(item) && isActiveOrderItem(item),
    )) {
      final status = changedIds.contains(item.id)
          ? changedStatus
          : normalizeStatus(item.kitchenStatus);

      switch (normalizeStatus(status)) {
        case 'cooking':
          hasCooking = true;
        case 'sent':
          hasSent = true;
        case 'pending':
          hasPending = true;
        case 'ready':
          hasReady = true;
      }
    }

    if (hasCooking) {
      return 'cooking';
    }
    if (hasSent) {
      return 'sent';
    }
    if (hasPending) {
      return 'pending';
    }
    if (hasReady) {
      return 'ready';
    }
    return 'not_required';
  }

  Future<void> markActiveKitchenItemsCooking(
    String orderId, {
    String? kitchenBatchId,
  }) {
    return updateKitchenStatus(
      orderId: orderId,
      status: 'cooking',
      kitchenBatchId: kitchenBatchId,
    );
  }

  Future<PaymentResult> payFullTable({
    required String orderId,
    required String method,
    String? employeeId,
    String? employeeName,
    CashPaymentDetails? cashDetails,
    AppliedDiscountDetails? discount,
  }) async {
    _requireCharge();
    final cashSession = await _requireOpenCashSessionForPayment();
    await _ensureNoPaymentType(orderId, blockedType: 'person');
    await _ensureEmployeeConsumptionAllowed(
      orderId,
      method,
      employeeId: employeeId,
    );
    await _ensureKitchenReadyForPayment(orderId);
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = PosOrder.fromDoc(orderDoc);
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final pendingItems = itemsSnapshot.docs
        .map(OrderItem.fromDoc)
        .where((item) => item.paymentStatus != 'paid' && !item.isCancelled)
        .toList();
    final baseAmount = pendingItems.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.total,
    );

    if (baseAmount <= 0) {
      return const PaymentResult(allPaid: true);
    }

    final effectiveDiscount = await _resolvePreparedGlobalDiscount(
      order: order,
      requestedDiscount: discount,
      amountBeforeDiscount: baseAmount,
      remainingGrossSubtotal: baseAmount,
    );
    await _ensureDiscountAuthorizationStillUsable(
      effectiveDiscount,
      order,
      baseAmount,
    );
    final previousActivePayments = (await getOrderPaymentsOnce(
      order.id,
    )).where((payment) => payment.isActive).toList();
    final paymentRef = _ordersRef.doc(orderId).collection('payments').doc();
    final paymentData = _paymentData(
      order: order,
      cashSession: cashSession,
      type: 'full_table',
      method: method,
      baseAmount: baseAmount,
      employeeId: employeeId,
      employeeName: employeeName,
      cashDetails: cashDetails,
      discount: effectiveDiscount,
    );
    final result = await _finalizeSaleWithDailyFolio(
      order: order,
      cashSession: cashSession,
      paymentRef: paymentRef,
      paymentData: paymentData,
      itemDocs: itemsSnapshot.docs.where((doc) {
        final item = OrderItem.fromDoc(doc);
        return item.paymentStatus != 'paid' && !item.isCancelled;
      }),
      discount: effectiveDiscount,
      previousActivePayments: previousActivePayments,
    );
    invalidateReportDataCache(
      branchId: order.branchId,
      startBusinessDate: order.businessDate,
      endBusinessDate: order.businessDate,
    );
    return result;
  }

  Future<PaymentResult> payPerson({
    required String orderId,
    required int personNumber,
    required String method,
    String? employeeId,
    String? employeeName,
    CashPaymentDetails? cashDetails,
    AppliedDiscountDetails? discount,
  }) async {
    _requireCharge();
    final cashSession = await _requireOpenCashSessionForPayment();
    await _ensureNoPaymentType(orderId, blockedType: 'partial');
    await _ensureEmployeeConsumptionAllowed(
      orderId,
      method,
      employeeId: employeeId,
    );
    await _ensureKitchenReadyForPayment(orderId);
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = PosOrder.fromDoc(orderDoc);
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final items = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
    final personItems = items
        .where(
          (item) =>
              item.personNumber == personNumber &&
              item.paymentStatus != 'paid' &&
              !item.isCancelled,
        )
        .toList();
    final personName = personItems.isEmpty
        ? 'Persona $personNumber'
        : personItems.first.personName;
    final baseAmount = personItems.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.total,
    );

    if (baseAmount <= 0) {
      return PaymentResult(allPaid: order.pendingTotal <= 0.01);
    }

    final remainingGrossSubtotal = items
        .where((item) => item.paymentStatus != 'paid' && !item.isCancelled)
        .fold<double>(0, (runningTotal, item) => runningTotal + item.total);
    final effectiveDiscount = await _resolvePreparedGlobalDiscount(
      order: order,
      requestedDiscount: discount,
      amountBeforeDiscount: baseAmount,
      remainingGrossSubtotal: remainingGrossSubtotal,
    );
    await _ensureDiscountAuthorizationStillUsable(
      effectiveDiscount,
      order,
      baseAmount,
    );
    final previousActivePayments = (await getOrderPaymentsOnce(
      order.id,
    )).where((payment) => payment.isActive).toList();
    final paymentRef = _ordersRef.doc(orderId).collection('payments').doc();
    final selectedItemDocs = itemsSnapshot.docs.where((doc) {
      final item = OrderItem.fromDoc(doc);
      return item.personNumber == personNumber &&
          item.paymentStatus != 'paid' &&
          !item.isCancelled;
    }).toList();
    final paidTotal = (order.paidTotal + baseAmount).clamp(0, order.total);
    final pendingTotal = (order.total - paidTotal).clamp(0, double.infinity);
    if (pendingTotal <= 0.01) {
      final paymentData = _paymentData(
        order: order,
        cashSession: cashSession,
        type: 'person',
        method: method,
        baseAmount: baseAmount,
        personNumber: personNumber,
        personName: personName,
        employeeId: employeeId,
        employeeName: employeeName,
        cashDetails: cashDetails,
        discount: effectiveDiscount,
      );
      final result = await _finalizeSaleWithDailyFolio(
        order: order,
        cashSession: cashSession,
        paymentRef: paymentRef,
        paymentData: paymentData,
        itemDocs: selectedItemDocs,
        discount: effectiveDiscount,
        previousActivePayments: previousActivePayments,
      );
      invalidateReportDataCache(
        branchId: order.branchId,
        startBusinessDate: order.businessDate,
        endBusinessDate: order.businessDate,
      );
      return result;
    }
    final batch = _db.batch();
    final paymentData = _setPayment(
      batch: batch,
      paymentRef: paymentRef,
      order: order,
      cashSession: cashSession,
      type: 'person',
      method: method,
      baseAmount: baseAmount,
      personNumber: personNumber,
      personName: personName,
      employeeId: employeeId,
      employeeName: employeeName,
      cashDetails: cashDetails,
      discount: effectiveDiscount,
    );

    for (final doc in selectedItemDocs) {
      batch.update(doc.reference, {
        'paymentStatus': 'paid',
        'paidAt': FieldValue.serverTimestamp(),
        'paymentId': paymentRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    final allPaid = _updateOrderPaymentTotalsInBatch(
      batch,
      order,
      baseAmount: baseAmount,
      closeItemsSnapshot: itemsSnapshot,
      discount: effectiveDiscount,
      previousActivePayments: previousActivePayments,
      newPaymentData: paymentData,
      newPaymentId: paymentRef.id,
    );
    _recordDiscountUsageInBatch(
      batch,
      usageRef: _discountUsageRef.doc(),
      order: order,
      paymentId: paymentRef.id,
      cashSession: cashSession,
      discount: effectiveDiscount,
    );
    _markDiscountAuthorizationUsedInBatch(
      batch,
      discount: effectiveDiscount,
      paymentId: paymentRef.id,
    );
    await batch.commit();
    return PaymentResult(allPaid: allPaid);
  }

  Future<PaymentResult> payPeople({
    required String orderId,
    required List<int> personNumbers,
    required String method,
    String? employeeId,
    String? employeeName,
    CashPaymentDetails? cashDetails,
    AppliedDiscountDetails? discount,
  }) async {
    final selectedPeople = personNumbers.toSet().toList()..sort();
    if (selectedPeople.isEmpty) {
      throw ArgumentError('Selecciona al menos una persona.');
    }
    if (selectedPeople.length == 1) {
      return payPerson(
        orderId: orderId,
        personNumber: selectedPeople.first,
        method: method,
        employeeId: employeeId,
        employeeName: employeeName,
        cashDetails: cashDetails,
        discount: discount,
      );
    }

    _requireCharge();
    final cashSession = await _requireOpenCashSessionForPayment();
    await _ensureNoPaymentType(orderId, blockedType: 'partial');
    await _ensureEmployeeConsumptionAllowed(
      orderId,
      method,
      employeeId: employeeId,
    );
    await _ensureKitchenReadyForPayment(orderId);
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = PosOrder.fromDoc(orderDoc);
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final items = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
    final personItems = items
        .where(
          (item) =>
              selectedPeople.contains(item.personNumber) &&
              item.paymentStatus != 'paid' &&
              !item.isCancelled,
        )
        .toList();
    final baseAmount = personItems.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.total,
    );

    if (baseAmount <= 0) {
      return PaymentResult(allPaid: order.pendingTotal <= 0.01);
    }

    final names = selectedPeople.map((person) => order.personName(person));
    final remainingGrossSubtotal = items
        .where((item) => item.paymentStatus != 'paid' && !item.isCancelled)
        .fold<double>(0, (runningTotal, item) => runningTotal + item.total);
    final effectiveDiscount = await _resolvePreparedGlobalDiscount(
      order: order,
      requestedDiscount: discount,
      amountBeforeDiscount: baseAmount,
      remainingGrossSubtotal: remainingGrossSubtotal,
    );
    await _ensureDiscountAuthorizationStillUsable(
      effectiveDiscount,
      order,
      baseAmount,
    );
    final previousActivePayments = (await getOrderPaymentsOnce(
      order.id,
    )).where((payment) => payment.isActive).toList();
    final paymentRef = _ordersRef.doc(orderId).collection('payments').doc();
    final selectedItemDocs = itemsSnapshot.docs.where((doc) {
      final item = OrderItem.fromDoc(doc);
      return selectedPeople.contains(item.personNumber) &&
          item.paymentStatus != 'paid' &&
          !item.isCancelled;
    }).toList();
    final paidTotal = (order.paidTotal + baseAmount).clamp(0, order.total);
    final pendingTotal = (order.total - paidTotal).clamp(0, double.infinity);
    if (pendingTotal <= 0.01) {
      final paymentData = _paymentData(
        order: order,
        cashSession: cashSession,
        type: 'person',
        method: method,
        baseAmount: baseAmount,
        personName: names.join(', '),
        employeeId: employeeId,
        employeeName: employeeName,
        cashDetails: cashDetails,
        discount: effectiveDiscount,
      );
      final result = await _finalizeSaleWithDailyFolio(
        order: order,
        cashSession: cashSession,
        paymentRef: paymentRef,
        paymentData: paymentData,
        itemDocs: selectedItemDocs,
        discount: effectiveDiscount,
        previousActivePayments: previousActivePayments,
      );
      invalidateReportDataCache(
        branchId: order.branchId,
        startBusinessDate: order.businessDate,
        endBusinessDate: order.businessDate,
      );
      return result;
    }
    final batch = _db.batch();
    final paymentData = _setPayment(
      batch: batch,
      paymentRef: paymentRef,
      order: order,
      cashSession: cashSession,
      type: 'person',
      method: method,
      baseAmount: baseAmount,
      personName: names.join(', '),
      employeeId: employeeId,
      employeeName: employeeName,
      cashDetails: cashDetails,
      discount: effectiveDiscount,
    );

    for (final doc in selectedItemDocs) {
      batch.update(doc.reference, {
        'paymentStatus': 'paid',
        'paidAt': FieldValue.serverTimestamp(),
        'paymentId': paymentRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    final allPaid = _updateOrderPaymentTotalsInBatch(
      batch,
      order,
      baseAmount: baseAmount,
      closeItemsSnapshot: itemsSnapshot,
      discount: effectiveDiscount,
      previousActivePayments: previousActivePayments,
      newPaymentData: paymentData,
      newPaymentId: paymentRef.id,
    );
    _recordDiscountUsageInBatch(
      batch,
      usageRef: _discountUsageRef.doc(),
      order: order,
      paymentId: paymentRef.id,
      cashSession: cashSession,
      discount: effectiveDiscount,
    );
    _markDiscountAuthorizationUsedInBatch(
      batch,
      discount: effectiveDiscount,
      paymentId: paymentRef.id,
    );
    await batch.commit();
    return PaymentResult(allPaid: allPaid);
  }

  Future<PaymentResult> payPartialAmount({
    required String orderId,
    required double baseAmount,
    required String method,
    String? employeeId,
    String? employeeName,
    CashPaymentDetails? cashDetails,
    AppliedDiscountDetails? discount,
  }) async {
    _requireCharge();
    final cashSession = await _requireOpenCashSessionForPayment();
    await _ensureNoPaymentType(orderId, blockedType: 'person');
    await _ensureEmployeeConsumptionAllowed(
      orderId,
      method,
      employeeId: employeeId,
    );
    await _ensureKitchenReadyForPayment(orderId);
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = PosOrder.fromDoc(orderDoc);

    if (baseAmount <= 0 || baseAmount > order.pendingTotal + 0.01) {
      throw ArgumentError('Monto parcial invalido.');
    }

    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final effectiveDiscount = await _resolvePreparedGlobalDiscount(
      order: order,
      requestedDiscount: discount,
      amountBeforeDiscount: baseAmount,
      remainingGrossSubtotal: order.pendingTotal,
    );
    await _ensureDiscountAuthorizationStillUsable(
      effectiveDiscount,
      order,
      baseAmount,
    );
    final previousActivePayments = (await getOrderPaymentsOnce(
      order.id,
    )).where((payment) => payment.isActive).toList();
    final paymentRef = _ordersRef.doc(orderId).collection('payments').doc();
    final paidTotal = (order.paidTotal + baseAmount).clamp(0, order.total);
    final pendingTotal = (order.total - paidTotal).clamp(0, double.infinity);
    if (pendingTotal <= 0.01) {
      final paymentData = _paymentData(
        order: order,
        cashSession: cashSession,
        type: 'partial',
        method: method,
        baseAmount: baseAmount,
        employeeId: employeeId,
        employeeName: employeeName,
        cashDetails: cashDetails,
        discount: effectiveDiscount,
      );
      final result = await _finalizeSaleWithDailyFolio(
        order: order,
        cashSession: cashSession,
        paymentRef: paymentRef,
        paymentData: paymentData,
        itemDocs: itemsSnapshot.docs,
        discount: effectiveDiscount,
        previousActivePayments: previousActivePayments,
      );
      invalidateReportDataCache(
        branchId: order.branchId,
        startBusinessDate: order.businessDate,
        endBusinessDate: order.businessDate,
      );
      return result;
    }
    final batch = _db.batch();
    final paymentData = _setPayment(
      batch: batch,
      paymentRef: paymentRef,
      order: order,
      cashSession: cashSession,
      type: 'partial',
      method: method,
      baseAmount: baseAmount,
      employeeId: employeeId,
      employeeName: employeeName,
      cashDetails: cashDetails,
      discount: effectiveDiscount,
    );

    final allPaid = _updateOrderPaymentTotalsInBatch(
      batch,
      order,
      baseAmount: baseAmount,
      closeItemsSnapshot: itemsSnapshot,
      markItemsOnlyIfClosed: true,
      discount: effectiveDiscount,
      previousActivePayments: previousActivePayments,
      newPaymentData: paymentData,
      newPaymentId: paymentRef.id,
    );
    _recordDiscountUsageInBatch(
      batch,
      usageRef: _discountUsageRef.doc(),
      order: order,
      paymentId: paymentRef.id,
      cashSession: cashSession,
      discount: effectiveDiscount,
    );
    _markDiscountAuthorizationUsedInBatch(
      batch,
      discount: effectiveDiscount,
      paymentId: paymentRef.id,
    );
    await batch.commit();
    return PaymentResult(allPaid: allPaid);
  }

  Future<PaymentResult> payPlatformOrder({required String orderId}) async {
    _requireCharge();
    final cashSession = await _requireOpenCashSessionForPayment();
    await _ensureKitchenReadyForPayment(orderId);
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = PosOrder.fromDoc(orderDoc);
    if (order.orderType != 'takeout' || order.platformId == 'en_persona') {
      throw StateError('Este pedido no aplica para pago en plataforma.');
    }

    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final pendingItems = itemsSnapshot.docs
        .map(OrderItem.fromDoc)
        .where((item) => item.paymentStatus != 'paid' && !item.isCancelled)
        .toList();
    final baseAmount = pendingItems.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.total,
    );

    if (baseAmount <= 0) {
      return const PaymentResult(allPaid: true);
    }

    final previousActivePayments = (await getOrderPaymentsOnce(
      order.id,
    )).where((payment) => payment.isActive).toList();
    final paymentRef = _ordersRef.doc(orderId).collection('payments').doc();
    final paymentData = _paymentData(
      order: order,
      cashSession: cashSession,
      type: 'platform',
      method: 'platform_paid',
      baseAmount: baseAmount,
      platformId: order.platformId,
      platformName: order.platformName,
    );
    final result = await _finalizeSaleWithDailyFolio(
      order: order,
      cashSession: cashSession,
      paymentRef: paymentRef,
      paymentData: paymentData,
      itemDocs: itemsSnapshot.docs.where((doc) {
        final item = OrderItem.fromDoc(doc);
        return item.paymentStatus != 'paid' && !item.isCancelled;
      }),
      previousActivePayments: previousActivePayments,
    );
    invalidateReportDataCache(
      branchId: order.branchId,
      startBusinessDate: order.businessDate,
      endBusinessDate: order.businessDate,
    );
    return result;
  }

  Future<CheckoutPreparation> prepareOrderForCheckout(String orderId) async {
    _requireCharge();
    final orderRef = _ordersRef.doc(orderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists) {
      throw StateError('No se encontro la orden.');
    }

    final order = PosOrder.fromDoc(orderDoc);
    await _ensureKitchenReadyForPayment(orderId);
    final itemsSnapshot = await orderRef.collection('items').get();
    final paymentsSnapshot = await orderRef.collection('payments').get();
    final activeItems = itemsSnapshot.docs
        .map(OrderItem.fromDoc)
        .where(isActiveOrderItem)
        .toList();
    final activePayments = paymentsSnapshot.docs
        .map(Payment.fromDoc)
        .where((payment) => payment.isActive)
        .toList();
    final hasActivePaymentEvidence =
        activePayments.isNotEmpty ||
        normalizeStatus(order.paymentStatus) == 'partial' ||
        order.paidTotal > 0.01;
    final grossSubtotal = roundCheckoutMoney(
      _activeItemsGrossSubtotal(activeItems),
    );

    if (!shouldRefreshGlobalDiscountSnapshot(
      hasActivePayments: hasActivePaymentEvidence,
    )) {
      return _checkoutPreparationFromOrder(
        order,
        fallbackGrossSubtotal: grossSubtotal,
        frozenByPayments: true,
      );
    }

    if (_hasSpecificDiscountSnapshot(order)) {
      return _checkoutPreparationFromOrder(
        order,
        fallbackGrossSubtotal: grossSubtotal,
        frozenByPayments: false,
      );
    }

    final config = await getGeneralDiscountConfigOnce();
    final platformOnlyPayment =
        order.orderType == takeoutOrderType &&
        order.platformId != null &&
        order.platformId != 'en_persona';
    final applies =
        !platformOnlyPayment &&
        config.appliesToCurrentBranch(AppSession.instance.currentBranchId);
    final employee = AppSession.instance.employee;

    if (!applies) {
      await orderRef.update({
        'total': grossSubtotal,
        'paidTotal': 0.0,
        'pendingTotal': grossSubtotal,
        'discountApplied': false,
        'discountSource': noDiscountSource,
        'discountCatalogId': null,
        'discountType': 'none',
        'discountName': null,
        'discountConcept': null,
        'discountPercent': 0.0,
        'discountRate': 0.0,
        'discountAmount': 0.0,
        'totalDiscountAmount': 0.0,
        'grossSubtotal': grossSubtotal,
        'netTotal': grossSubtotal,
        'discountAppliedAt': null,
        'discountAppliedByEmployeeId': null,
        'discountAppliedByEmployeeName': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return CheckoutPreparation(
        orderId: orderId,
        grossSubtotal: grossSubtotal,
        discountAmount: 0,
        netTotal: grossSubtotal,
        discountSource: noDiscountSource,
        discountCatalogId: null,
        discountName: null,
        discountPercent: 0,
        frozenByPayments: false,
      );
    }

    final amounts = calculateGlobalDiscountAmounts(
      grossSubtotal: grossSubtotal,
      percent: config.percent,
    );
    await orderRef.update({
      'total': amounts.grossSubtotal,
      'paidTotal': 0.0,
      'pendingTotal': amounts.grossSubtotal,
      'discountApplied': amounts.discountAmount > 0.01,
      'discountSource': globalDiscountSource,
      'discountCatalogId': config.catalogId,
      'discountType': 'general',
      'discountName': config.name,
      'discountConcept': config.name,
      'discountPercent': config.percent,
      'discountRate': config.percent / 100,
      'discountAmount': amounts.discountAmount,
      'totalDiscountAmount': amounts.discountAmount,
      'grossSubtotal': amounts.grossSubtotal,
      'netTotal': amounts.netTotal,
      'discountDescription': config.description,
      'discountBranchId': config.branchId,
      'discountAppliedAt': FieldValue.serverTimestamp(),
      'discountAppliedByEmployeeId': employee?.id ?? '',
      'discountAppliedByEmployeeName': employee?.name ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return CheckoutPreparation(
      orderId: orderId,
      grossSubtotal: amounts.grossSubtotal,
      discountAmount: amounts.discountAmount,
      netTotal: amounts.netTotal,
      discountSource: globalDiscountSource,
      discountCatalogId: config.catalogId,
      discountName: config.name,
      discountPercent: config.percent,
      frozenByPayments: false,
    );
  }

  AppliedDiscountDetails? preparedGlobalDiscountForAmount({
    required PosOrder order,
    required double amountBeforeDiscount,
    required double remainingGrossSubtotal,
    required Iterable<Payment> activePayments,
  }) {
    if (order.discountSource != globalDiscountSource ||
        order.explicitDiscount <= 0.01) {
      return null;
    }
    final previouslyAllocated = activePayments
        .where(
          (payment) =>
              payment.isActive &&
              payment.discountSource == globalDiscountSource,
        )
        .fold<double>(
          0,
          (runningTotal, payment) => runningTotal + payment.discountAmount,
        );
    final discountAmount = allocateGlobalDiscount(
      orderGrossSubtotal: order.grossSubtotal ?? order.total,
      orderDiscountAmount: order.explicitDiscount,
      selectedGrossSubtotal: amountBeforeDiscount,
      remainingGrossSubtotal: remainingGrossSubtotal,
      previouslyAllocatedDiscount: previouslyAllocated,
    );
    if (discountAmount <= 0.01) return null;
    return AppliedDiscountDetails(
      type: order.discountType ?? 'general',
      name: order.discountConcept ?? order.discountName ?? 'Descuento general',
      percent:
          order.discountPercent ??
          ((order.discountRate ?? 0) <= 1
              ? (order.discountRate ?? 0) * 100
              : order.discountRate ?? 0),
      amountBeforeDiscount: roundCheckoutMoney(amountBeforeDiscount),
      discountAmount: discountAmount,
      totalAfterDiscount: roundCheckoutMoney(
        amountBeforeDiscount - discountAmount,
      ),
      orderId: order.id,
      restaurantId: order.restaurantId,
      branchId: order.branchId,
      businessDate: _businessDateForOrder(order),
      totalSnapshot: order.total,
    );
  }

  Future<AppliedDiscountDetails?> _resolvePreparedGlobalDiscount({
    required PosOrder order,
    required AppliedDiscountDetails? requestedDiscount,
    required double amountBeforeDiscount,
    required double remainingGrossSubtotal,
  }) async {
    final requestedIsDifferent =
        requestedDiscount != null &&
        requestedDiscount.type != (order.discountType ?? 'general');
    if (order.discountSource != globalDiscountSource || requestedIsDifferent) {
      return requestedDiscount;
    }
    final payments = await getOrderPaymentsOnce(order.id);
    return preparedGlobalDiscountForAmount(
      order: order,
      amountBeforeDiscount: amountBeforeDiscount,
      remainingGrossSubtotal: remainingGrossSubtotal,
      activePayments: payments.where((payment) => payment.isActive),
    );
  }

  bool _hasSpecificDiscountSnapshot(PosOrder order) {
    if (order.explicitDiscount <= 0.01) return false;
    final source = order.discountSource?.trim().toLowerCase();
    final type = order.discountType?.trim().toLowerCase();
    return source != globalDiscountSource &&
        source != noDiscountSource &&
        type != 'general';
  }

  CheckoutPreparation _checkoutPreparationFromOrder(
    PosOrder order, {
    required double fallbackGrossSubtotal,
    required bool frozenByPayments,
  }) {
    final gross = order.grossSubtotal ?? fallbackGrossSubtotal;
    final discount = order.explicitDiscount.clamp(0, gross).toDouble();
    final net = order.netTotal ?? roundCheckoutMoney(gross - discount);
    return CheckoutPreparation(
      orderId: order.id,
      grossSubtotal: gross,
      discountAmount: discount,
      netTotal: net,
      discountSource:
          order.discountSource ??
          (discount > 0.01
              ? order.discountType ?? 'unknown'
              : noDiscountSource),
      discountCatalogId: order.discountCatalogId,
      discountName: order.discountConcept ?? order.discountName,
      discountPercent:
          order.discountPercent ??
          ((order.discountRate ?? 0) <= 1
              ? (order.discountRate ?? 0) * 100
              : order.discountRate ?? 0),
      frozenByPayments: frozenByPayments,
    );
  }

  Future<OrderTotalsRecalculation> recalculateOrderBeforeCheckout(
    String orderId,
  ) async {
    _requireCharge();
    final orderRef = _ordersRef.doc(orderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists) {
      throw StateError('No se encontro la orden.');
    }
    final order = PosOrder.fromDoc(orderDoc);
    final itemsSnapshot = await orderRef.collection('items').get();
    final activeItems = itemsSnapshot.docs
        .map(OrderItem.fromDoc)
        .where(isActiveOrderItem)
        .toList();
    final grossSubtotal = _activeItemsGrossSubtotal(activeItems);
    final currentData = orderDoc.data() ?? {};
    final discountAmount = _explicitOrderDiscountAmount(
      currentData,
    ).clamp(0, grossSubtotal).toDouble();
    final netTotal = (grossSubtotal - discountAmount)
        .clamp(0, double.infinity)
        .toDouble();
    final paidTotal = order.paidTotal.clamp(0, grossSubtotal).toDouble();
    final pendingTotal = (grossSubtotal - paidTotal)
        .clamp(0, double.infinity)
        .toDouble();
    final discountApplied = discountAmount > 0.01;
    final updates = <String, Object?>{
      'grossSubtotal': grossSubtotal,
      'total': grossSubtotal,
      'discountApplied': discountApplied,
      'discountAmount': discountAmount,
      'totalDiscountAmount': discountAmount,
      'netTotal': netTotal,
      'pendingTotal': pendingTotal,
      if (!discountApplied) ...{
        'discountCatalogId': null,
        'discountType': 'none',
        'discountName': null,
        'discountPercent': 0.0,
        'discountRate': 0.0,
        'discountReason': null,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final changed =
        (_numberToDouble(currentData['grossSubtotal']) - grossSubtotal).abs() >
            0.02 ||
        (order.total - grossSubtotal).abs() > 0.02 ||
        (_numberToDouble(currentData['netTotal']) - netTotal).abs() > 0.02 ||
        (order.pendingTotal - pendingTotal).abs() > 0.02 ||
        _numberToDouble(currentData['discountAmount']) != discountAmount;
    final missingFields =
        !currentData.containsKey('grossSubtotal') ||
        !currentData.containsKey('netTotal') ||
        !currentData.containsKey('discountApplied');
    if (changed || missingFields) {
      await orderRef.update(updates);
    }
    return OrderTotalsRecalculation(
      orderId: orderId,
      grossSubtotal: grossSubtotal,
      discountAmount: discountAmount,
      netTotal: netTotal,
      changed: changed || missingFields,
    );
  }

  Future<OrderTotalsCorrectionPreview> previewSafeOrderTotalsCorrection({
    required PosOrder order,
    required List<OrderItem> items,
    required List<Payment> payments,
  }) async {
    return _safeOrderTotalsCorrectionPreview(order, items, payments);
  }

  Future<void> correctOrderTotalsFromAudit({
    required String orderId,
    required String reason,
    required String adminPin,
  }) async {
    if (adminPin.trim() != '072026') {
      throw StateError('PIN administrador incorrecto.');
    }
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw StateError('Captura el motivo de la correccion.');
    }
    final employee = AppSession.instance.employee;
    if (employee?.canViewAdmin != true && employee?.hasAdminAccess != true) {
      throw StateError('No tienes permiso para corregir auditoria.');
    }

    await _db.runTransaction((transaction) async {
      final orderRef = _ordersRef.doc(orderId);
      final orderDoc = await transaction.get(orderRef);
      if (!orderDoc.exists) {
        throw StateError('No se encontro la orden.');
      }
      final order = PosOrder.fromDoc(orderDoc);
      final itemsSnapshot = await orderRef.collection('items').get();
      final paymentsSnapshot = await orderRef.collection('payments').get();
      final items = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
      final payments = paymentsSnapshot.docs.map(Payment.fromDoc).toList();
      final preview = _safeOrderTotalsCorrectionPreview(order, items, payments);
      if (!preview.safe) {
        throw StateError(preview.message);
      }
      final difference =
          preview.discountAmount - preview.previousDiscountAmount;

      transaction.update(orderRef, {
        'previousTotal': preview.previousTotal,
        'previousPaidTotal': preview.previousPaidTotal,
        'previousPendingTotal': preview.previousPendingTotal,
        'grossSubtotal': preview.grossSubtotal,
        'discountApplied': preview.discountAmount > 0.01,
        'discountAmount': preview.discountAmount,
        'totalDiscountAmount': preview.discountAmount,
        'netTotal': preview.netTotal,
        'monetaryPaid': preview.paymentTotal,
        'paidTotal': preview.newPaidTotal,
        'pendingTotal': preview.newPendingTotal,
        'totalLiquidated': preview.totalLiquidated,
        'effectiveDiscountPercent': preview.grossSubtotal <= 0.01
            ? 0.0
            : (preview.discountAmount / preview.grossSubtotal) * 100,
        'paymentStatus': 'paid',
        if (normalizeStatus(order.status) == 'paid') 'status': 'paid',
        'historicalPaymentReconciledAt': FieldValue.serverTimestamp(),
        'historicalPaymentReconciledByEmployeeId': employee?.id ?? '',
        'historicalPaymentReconciledByEmployeeName': employee?.name ?? '',
        'historicalPaymentReconciliationReason': cleanReason,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(_restaurantRef.collection('activityLog').doc(), {
        'type': 'historical_payment_reconciliation',
        'actionType': 'historical_payment_reconciliation',
        'message':
            'Se reconciliaron agregados historicos de la venta ${_shortLogFolio(order.id)}',
        'orderId': orderId,
        'folio': _shortLogFolio(order.id),
        'previousValues': {
          'total': preview.previousTotal,
          'discountAmount': preview.previousDiscountAmount,
          'netTotal': preview.previousNetTotal,
          'paidTotal': preview.previousPaidTotal,
          'pendingTotal': preview.previousPendingTotal,
        },
        'newValues': {
          'grossSubtotal': preview.grossSubtotal,
          'discountAmount': preview.discountAmount,
          'totalDiscountAmount': preview.discountAmount,
          'monetaryPaid': preview.paymentTotal,
          'paidTotal': preview.newPaidTotal,
          'pendingTotal': preview.newPendingTotal,
          'totalLiquidated': preview.totalLiquidated,
          'netTotal': preview.netTotal,
        },
        'difference': difference,
        'reasonCode': 'historical_payment_reconciliation',
        'reason': cleanReason,
        'previousTotal': preview.previousTotal,
        'newTotal': preview.newTotal,
        'previousPaidTotal': preview.previousPaidTotal,
        'newPaidTotal': preview.newPaidTotal,
        'previousDiscountAmount': preview.previousDiscountAmount,
        'newDiscountAmount': preview.discountAmount,
        'itemSubtotal': preview.grossSubtotal,
        'discountAmount': preview.discountAmount,
        'netTotal': preview.netTotal,
        'paymentTotal': preview.paymentTotal,
        'totalLiquidated': preview.totalLiquidated,
        'employeeId': employee?.id ?? '',
        'employeeName': employee?.name ?? '',
        ..._currentBranchFields,
        'createdAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
        'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      });
    });
    invalidateReportDataCache();
  }

  OrderTotalsCorrectionPreview _safeOrderTotalsCorrectionPreview(
    PosOrder order,
    List<OrderItem> items,
    List<Payment> payments,
  ) {
    final paid =
        normalizeStatus(order.status) == 'paid' ||
        normalizeStatus(order.paymentStatus) == 'paid';
    if (!paid) {
      return _unsafeTotalsPreview(order, 'La orden no esta pagada.');
    }
    if (order.pendingTotal.abs() > 0.02) {
      return _unsafeTotalsPreview(order, 'La orden tiene saldo pendiente.');
    }
    final activeItems = items.where(isActiveOrderItem).toList();
    final grossSubtotal = _activeItemsGrossSubtotal(activeItems);
    if (grossSubtotal <= 0.02) {
      return _unsafeTotalsPreview(order, 'La orden no tiene items activos.');
    }
    final activePayments = payments.where(isCanonicalActivePayment).toList();
    final totals = reconcileOrderPayments(
      orderGrossTotal: grossSubtotal,
      activePayments: activePayments.map(PaymentSettlementInput.fromPayment),
    );
    final discountAmount = totals.discountAmount;
    final netTotal = totals.netTotal;
    final paymentTotal = totals.monetaryPaid;
    final totalLiquidated = totals.totalLiquidated;
    if ((totalLiquidated - grossSubtotal).abs() > 0.02) {
      return _unsafeTotalsPreview(
        order,
        'Items y pagos no coinciden para una correccion automatica.',
      );
    }
    if (activePayments.length !=
        activePayments.map((p) => p.id).toSet().length) {
      return _unsafeTotalsPreview(order, 'Hay pagos duplicados.');
    }
    final newPaidTotal = grossSubtotal;
    final newPendingTotal = 0.0;
    final previousDiscountAmount = order.explicitDiscount
        .clamp(0, grossSubtotal)
        .toDouble();
    final previousNetTotal =
        order.netTotal ??
        (grossSubtotal - previousDiscountAmount)
            .clamp(0, double.infinity)
            .toDouble();
    final hasOnlyTotalsIssue =
        (previousDiscountAmount - discountAmount).abs() > 0.02 ||
        (previousNetTotal - netTotal).abs() > 0.02 ||
        (order.paidTotal - newPaidTotal).abs() > 0.02 ||
        (order.pendingTotal - newPendingTotal).abs() > 0.02;
    if (!hasOnlyTotalsIssue) {
      return _unsafeTotalsPreview(
        order,
        'No hay una discrepancia de totales corregible automaticamente.',
      );
    }
    return OrderTotalsCorrectionPreview(
      safe: true,
      message: 'Correccion segura disponible.',
      grossSubtotal: grossSubtotal,
      discountAmount: discountAmount.toDouble(),
      netTotal: netTotal,
      paymentTotal: paymentTotal,
      totalLiquidated: totalLiquidated,
      previousDiscountAmount: previousDiscountAmount,
      previousNetTotal: previousNetTotal,
      previousTotal: order.total,
      newTotal: order.total,
      previousPaidTotal: order.paidTotal,
      newPaidTotal: newPaidTotal,
      previousPendingTotal: order.pendingTotal,
      newPendingTotal: newPendingTotal,
      hasDiscount: discountAmount > 0.02,
    );
  }

  OrderTotalsCorrectionPreview _unsafeTotalsPreview(
    PosOrder order,
    String message,
  ) {
    return OrderTotalsCorrectionPreview(
      safe: false,
      message: message,
      grossSubtotal: 0,
      discountAmount: 0,
      netTotal: 0,
      paymentTotal: 0,
      totalLiquidated: 0,
      previousDiscountAmount: order.explicitDiscount,
      previousNetTotal: order.netTotal ?? 0,
      previousTotal: order.total,
      newTotal: order.total,
      previousPaidTotal: order.paidTotal,
      newPaidTotal: order.paidTotal,
      previousPendingTotal: order.pendingTotal,
      newPendingTotal: order.pendingTotal,
      hasDiscount: false,
    );
  }

  double _activeItemsGrossSubtotal(List<OrderItem> activeItems) {
    return activeItems.fold<double>(
      0,
      (runningTotal, item) => runningTotal + (item.qty * item.unitPrice),
    );
  }

  double _explicitOrderDiscountAmount(Map<String, dynamic> data) {
    for (final key in const [
      'totalDiscountAmount',
      'discountAmount',
      'discountTotal',
      'totalDiscount',
      'appliedDiscount',
    ]) {
      final value = _numberToDouble(data[key]);
      if (value > 0.02) return value;
    }
    return 0;
  }

  String _shortLogFolio(String id) => id.length <= 6 ? id : id.substring(0, 6);

  bool _updateOrderPaymentTotalsInBatch(
    WriteBatch batch,
    PosOrder order, {
    required double baseAmount,
    required QuerySnapshot<Map<String, dynamic>> closeItemsSnapshot,
    bool markItemsOnlyIfClosed = false,
    AppliedDiscountDetails? discount,
    Iterable<Payment> previousActivePayments = const [],
    Map<String, Object?>? newPaymentData,
    String? newPaymentId,
  }) {
    final totals = _reconcileOrderPayments(
      order: order,
      previousActivePayments: previousActivePayments,
      newPaymentData: newPaymentData,
      newPaymentId: newPaymentId,
    );
    final allPaid = totals.pendingTotal <= 0.01;

    if (allPaid) {
      for (final doc in closeItemsSnapshot.docs) {
        batch.update(doc.reference, {
          'paymentStatus': 'paid',
          'paidAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      _closeOrderInBatch(
        batch,
        order,
        discount: discount,
        reconciliationTotals: totals,
      );
    } else {
      batch.update(_ordersRef.doc(order.id), {
        'paymentStatus': 'partial',
        'paidTotal': totals.paidTotal,
        'pendingTotal': totals.pendingTotal,
        ..._orderAggregateSnapshotFromPayments(
          totals: totals,
          order: order,
          discount: discount,
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!markItemsOnlyIfClosed) {
        // Person payments already updated their own items before this method.
      }
    }

    return allPaid;
  }

  Future<PaymentResult> _finalizeSaleWithDailyFolio({
    required PosOrder order,
    required CashSession cashSession,
    required DocumentReference<Map<String, dynamic>> paymentRef,
    required Map<String, Object?> paymentData,
    required Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> itemDocs,
    AppliedDiscountDetails? discount,
    Iterable<Payment> previousActivePayments = const [],
  }) async {
    final config = await _loadSaleFolioConfig();
    final orderRef = _ordersRef.doc(order.id);
    final usageRef = _discountUsageRef.doc();
    final employee = AppSession.instance.employee;
    final actorId = employee?.id ?? _auth.currentUser?.uid ?? 'anonymous';
    final actorName = employee?.name ?? actorId;
    final deviceId = _auth.currentUser?.uid ?? 'anonymous';
    var transactionStage = 'iniciar cobro con folio diario';

    try {
      return await _db.runTransaction<PaymentResult>((transaction) async {
        transactionStage = 'leer orden';
        final freshOrderDoc = await transaction.get(orderRef);
        if (!freshOrderDoc.exists) {
          throw StateError('La orden ya no existe.');
        }
        final freshOrder = PosOrder.fromDoc(freshOrderDoc);
        final existingFolio = freshOrder.saleFolioDisplay?.trim();
        if (existingFolio != null && existingFolio.isNotEmpty) {
          return PaymentResult(allPaid: true, saleFolioDisplay: existingFolio);
        }

        final businessDate =
            _businessDateForOrder(freshOrder) ??
            businessDateForOpenCashSession(cashSession);
        final totals = _reconcileOrderPayments(
          order: freshOrder,
          previousActivePayments: previousActivePayments,
          newPaymentData: paymentData,
          newPaymentId: paymentRef.id,
        );
        if (freshOrder.total - totals.paidTotal > 0.01) {
          throw StateError('La venta aun tiene saldo pendiente.');
        }
        if (!config.appliesToBusinessDate(businessDate)) {
          transaction.set(paymentRef, paymentData);
          for (final doc in itemDocs) {
            transaction.update(doc.reference, {
              'paymentStatus': 'paid',
              'paidAt': FieldValue.serverTimestamp(),
              'paymentId': paymentRef.id,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
          transaction.update(orderRef, {
            'status': 'paid',
            'paymentStatus': 'paid',
            'paidTotal': totals.paidTotal,
            'pendingTotal': totals.pendingTotal,
            ..._orderAggregateSnapshotFromPayments(
              totals: totals,
              order: freshOrder,
              discount: discount,
            ),
            'paidAt': FieldValue.serverTimestamp(),
            ..._currentBranchFields,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          _releaseLinkedTablesInTransaction(transaction, freshOrder);
          return const PaymentResult(allPaid: true);
        }

        transactionStage = 'leer contador diario';
        final counterRef = _dailySaleCountersRef(
          freshOrder.branchId,
        ).doc(businessDate);
        final counterDoc = await transaction.get(counterRef);
        final lastSequence =
            (counterDoc.data()?['lastSequence'] as num?)?.toInt() ?? 0;
        final nextSequence = lastSequence + 1;
        final assignment = buildSaleFolioAssignment(
          sequence: nextSequence,
          businessDate: businessDate,
          branchId: freshOrder.branchId,
          branchName: freshOrder.branchName,
          restaurantId: freshOrder.restaurantId,
          config: config,
        );
        final now = FieldValue.serverTimestamp();
        final folioFields = {
          'saleFolioSequence': assignment.sequence,
          'saleFolioDisplay': assignment.display,
          'saleFolioFull': assignment.full,
          'saleFolioBusinessDate': assignment.businessDate,
          'saleFolioBranchId': assignment.branchId,
          'saleFolioRestaurantId': assignment.restaurantId,
          'saleFolioAssignedAt': now,
          'saleFolioVersion': saleFolioVersion,
        };
        final paymentWithFolio = {
          ...paymentData,
          'saleFolioSequence': assignment.sequence,
          'saleFolioDisplay': assignment.display,
          'saleFolioFull': assignment.full,
        };
        final auditPaymentSnapshot = buildSaleAuditPaymentSnapshot(
          paymentId: paymentRef.id,
          paymentData: paymentWithFolio,
          assignment: assignment,
        );

        transactionStage = 'guardar contador diario';
        transaction.set(counterRef, {
          'businessDate': businessDate,
          'restaurantId': freshOrder.restaurantId,
          'branchId': freshOrder.branchId,
          'lastSequence': nextSequence,
          'updatedAt': now,
          'updatedByDeviceId': deviceId,
          'version': saleFolioVersion,
        }, SetOptions(merge: true));
        transactionStage = 'guardar pago final';
        transaction.set(paymentRef, paymentWithFolio);
        for (final doc in itemDocs) {
          transaction.update(doc.reference, {
            'paymentStatus': 'paid',
            'paidAt': now,
            'paymentId': paymentRef.id,
            'updatedAt': now,
          });
        }
        if (discount != null && discount.discountAmount > 0) {
          transaction.set(usageRef, {
            'restaurantId': freshOrder.restaurantId,
            'restaurantName': freshOrder.restaurantName,
            'branchId': freshOrder.branchId,
            'branchName': freshOrder.branchName,
            'businessDate': cashSession.businessDate,
            'employeeId': discount.employeeBeneficiaryId,
            'employeeName': discount.employeeBeneficiaryName,
            'partnerId': discount.authorizedByPartnerId,
            'partnerName': discount.authorizedByPartnerName,
            'linkedEmployeeId': discount.authorizedByPartnerLinkedEmployeeId,
            'linkedEmployeeName':
                discount.authorizedByPartnerLinkedEmployeeName,
            'discountAuthorizationRequestId':
                discount.discountAuthorizationRequestId,
            'authorizationMode': discount.authorizationMode,
            'authorizationStatus': discount.authorizationStatus,
            'discountType': discount.type,
            'discountName': discount.name,
            'discountPercent': discount.percent,
            'orderId': freshOrder.id,
            'paymentId': paymentRef.id,
            'amountBeforeDiscount': discount.amountBeforeDiscount,
            'discountAmount': discount.discountAmount,
            'totalAfterDiscount': discount.totalAfterDiscount,
            'reason': discount.reason,
            'status': 'active',
            'createdAt': now,
            ..._employeeAuditFields(prefix: 'createdBy'),
          });
        }
        final requestId = discount?.discountAuthorizationRequestId?.trim();
        if (requestId != null && requestId.isNotEmpty) {
          transaction.update(_discountAuthorizationRequestsRef.doc(requestId), {
            'status': 'used',
            'usedAt': now,
            'usedPaymentId': paymentRef.id,
            'updatedAt': now,
          });
        }
        transactionStage = 'cerrar orden';
        transaction.update(orderRef, {
          'status': 'paid',
          'paymentStatus': 'paid',
          'paidTotal': totals.paidTotal,
          'pendingTotal': totals.pendingTotal,
          ..._orderAggregateSnapshotFromPayments(
            totals: totals,
            order: freshOrder,
            discount: discount,
          ),
          ...folioFields,
          'paidAt': now,
          ..._currentBranchFields,
          'updatedAt': now,
        });
        _releaseLinkedTablesInTransaction(transaction, freshOrder);
        transactionStage = 'registrar auditoria de folio asignado';
        _setSaleAuditEventInTransaction(
          transaction,
          branchId: freshOrder.branchId,
          eventType: 'sale_folio_assigned',
          order: freshOrder,
          assignment: assignment,
          amount: freshOrder.total,
          paymentSnapshot: auditPaymentSnapshot,
          previousStatus: freshOrder.paymentStatus,
          newStatus: 'paid',
          reason: 'Folio diario asignado al cerrar venta',
          performedBy: actorName,
          authorizedBy: actorId,
          deviceId: deviceId,
          createdAt: now,
        );
        transactionStage = 'registrar auditoria de venta completada';
        _setSaleAuditEventInTransaction(
          transaction,
          branchId: freshOrder.branchId,
          eventType: 'sale_completed',
          order: freshOrder,
          assignment: assignment,
          amount: freshOrder.total,
          paymentSnapshot: auditPaymentSnapshot,
          previousStatus: freshOrder.paymentStatus,
          newStatus: 'paid',
          reason: 'Venta completada',
          performedBy: actorName,
          authorizedBy: actorId,
          deviceId: deviceId,
          createdAt: now,
        );

        return PaymentResult(
          allPaid: true,
          saleFolioDisplay: assignment.display,
        );
      });
    } on StateError {
      rethrow;
    } on FirebaseException catch (error, stackTrace) {
      _logSaleFolioPaymentFailure(
        stage: transactionStage,
        code: error.code,
        message: error.message ?? error.toString(),
        plugin: error.plugin,
        error: error,
        stackTrace: stackTrace,
      );
      throw SaleFolioPaymentException(
        stage: transactionStage,
        code: error.code,
        message: error.message ?? error.toString(),
        plugin: error.plugin,
        originalError: error,
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      _logSaleFolioPaymentFailure(
        stage: transactionStage,
        code: 'unknown',
        message: error.toString(),
        plugin: 'tacopos',
        error: error,
        stackTrace: stackTrace,
      );
      throw SaleFolioPaymentException(
        stage: transactionStage,
        code: 'unknown',
        message: error.toString(),
        plugin: 'tacopos',
        originalError: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _logSaleFolioPaymentFailure({
    required String stage,
    required String code,
    required String message,
    required String plugin,
    required Object error,
    required StackTrace stackTrace,
  }) {
    developer.log(
      'Fallo al finalizar venta con folio diario. '
      'stage=$stage code=$code plugin=$plugin message=$message',
      name: 'TacoPOS.saleFolio.payment',
      error: error,
      stackTrace: stackTrace,
    );
  }

  Future<SaleFolioConfig> _loadSaleFolioConfig() async {
    try {
      final doc = await _saleFolioSettingsRef.get();
      return SaleFolioConfig.fromMap(doc.data());
    } catch (error, stackTrace) {
      developer.log(
        'No se pudo cargar configuracion de folio diario; usando defaults.',
        name: 'TacoPOS.saleFolio',
        error: error,
        stackTrace: stackTrace,
      );
      return const SaleFolioConfig();
    }
  }

  void _releaseLinkedTablesInTransaction(
    Transaction transaction,
    PosOrder order,
  ) {
    if (!orderUsesPhysicalTables(order)) return;
    for (final tableId in order.linkedTableIds.toSet()) {
      transaction.set(_tablesRef.doc(tableId), {
        'status': 'available',
        'currentOrderId': null,
        'currentOrderStatus': null,
        'tableGroupId': null,
        'tableGroupLabel': null,
        'groupPrimaryTableId': null,
        'occupiedAt': null,
        ..._currentBranchFields,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  void _setSaleAuditEventInTransaction(
    Transaction transaction, {
    required String branchId,
    required String eventType,
    required PosOrder order,
    required SaleFolioAssignment assignment,
    required double amount,
    required Map<String, Object?> paymentSnapshot,
    required String previousStatus,
    required String newStatus,
    required String reason,
    required String authorizedBy,
    required String performedBy,
    required String deviceId,
    required Object createdAt,
  }) {
    transaction.set(_saleAuditEventsRef(branchId).doc(), {
      'eventType': eventType,
      'orderId': order.id,
      'saleFolioSequence': assignment.sequence,
      'saleFolioFull': assignment.full,
      'businessDate': assignment.businessDate,
      'restaurantId': order.restaurantId,
      'branchId': order.branchId,
      'amount': amount,
      'paymentMethodsSnapshot': [paymentSnapshot],
      'previousStatus': previousStatus,
      'newStatus': newStatus,
      'reason': reason,
      'authorizedBy': authorizedBy,
      'performedBy': performedBy,
      'deviceId': deviceId,
      'createdAt': createdAt,
      'eventVersion': saleFolioVersion,
    });
  }

  SaleFolioAssignment? _saleFolioAssignmentFromOrder(PosOrder order) {
    final sequence = order.saleFolioSequence;
    final full = order.saleFolioFull?.trim();
    if (sequence == null || sequence <= 0 || full == null || full.isEmpty) {
      return null;
    }
    return SaleFolioAssignment(
      sequence: sequence,
      display: order.saleFolioDisplay?.trim().isNotEmpty == true
          ? order.saleFolioDisplay!.trim()
          : formatSaleFolioDisplay(sequence, 4),
      full: full,
      businessDate:
          order.saleFolioBusinessDate ??
          order.businessDate ??
          _currentBusinessDate(),
      branchId: order.saleFolioBranchId ?? order.branchId,
      restaurantId: order.saleFolioRestaurantId ?? order.restaurantId,
    );
  }

  void _closeOrderInBatch(
    WriteBatch batch,
    PosOrder order, {
    AppliedDiscountDetails? discount,
    OrderPaymentReconciliationTotals? reconciliationTotals,
  }) {
    final totals =
        reconciliationTotals ??
        reconcileOrderPayments(
          orderGrossTotal: order.total,
          activePayments: const [],
        );
    batch.update(_ordersRef.doc(order.id), {
      'status': 'paid',
      'paymentStatus': 'paid',
      'paidTotal': totals.paidTotal,
      'pendingTotal': totals.pendingTotal,
      ..._orderAggregateSnapshotFromPayments(
        totals: totals,
        order: order,
        discount: discount,
      ),
      'paidAt': FieldValue.serverTimestamp(),
      ..._currentBranchFields,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _setLinkedTablesStateInBatch(batch, order, release: true);
  }

  void _setLinkedTablesStateInBatch(
    WriteBatch batch,
    PosOrder order, {
    String? status,
    bool release = false,
  }) {
    if (!orderUsesPhysicalTables(order)) return;
    for (final tableId in order.linkedTableIds.toSet()) {
      batch.set(_tablesRef.doc(tableId), {
        'status': release ? 'available' : 'occupied',
        'currentOrderId': release ? null : order.id,
        'currentOrderStatus': release ? null : status ?? order.status,
        if (release) 'tableGroupId': null,
        if (release) 'tableGroupLabel': null,
        if (release) 'groupPrimaryTableId': null,
        if (release) 'occupiedAt': null,
        ..._currentBranchFields,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    if (release && order.isTableGroup) {
      _logActivityInBatch(
        batch,
        type: 'table_group_released',
        orderId: order.id,
        data: {
          'actionType': 'table_group_released',
          'folio': _shortLogFolio(order.id),
          'tableIds': order.linkedTableIds,
          'tableNames': order.tableNames,
          'tableGroupLabel': order.displayName,
          'businessDate':
              _businessDateForOrder(order) ?? _currentBusinessDate(),
          'timestamp': FieldValue.serverTimestamp(),
        },
      );
    }
  }

  void _setLinkedTablesStateInTransaction(
    Transaction transaction,
    PosOrder order, {
    String? status,
  }) {
    if (!orderUsesPhysicalTables(order)) return;
    for (final tableId in order.linkedTableIds.toSet()) {
      transaction.set(_tablesRef.doc(tableId), {
        'status': 'occupied',
        'currentOrderId': order.id,
        'currentOrderStatus': status ?? order.status,
        ..._currentBranchFields,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Map<String, Object?> _setPayment({
    required WriteBatch batch,
    required DocumentReference<Map<String, dynamic>> paymentRef,
    required PosOrder order,
    required CashSession cashSession,
    required String type,
    required String method,
    required double baseAmount,
    int? personNumber,
    String? personName,
    String? employeeId,
    String? employeeName,
    String? platformId,
    String? platformName,
    CashPaymentDetails? cashDetails,
    AppliedDiscountDetails? discount,
  }) {
    final data = _paymentData(
      order: order,
      cashSession: cashSession,
      type: type,
      method: method,
      baseAmount: baseAmount,
      personNumber: personNumber,
      personName: personName,
      employeeId: employeeId,
      employeeName: employeeName,
      platformId: platformId,
      platformName: platformName,
      cashDetails: cashDetails,
      discount: discount,
    );
    batch.set(paymentRef, data);
    return data;
  }

  Map<String, Object?> _paymentData({
    required PosOrder order,
    required CashSession cashSession,
    required String type,
    required String method,
    required double baseAmount,
    int? personNumber,
    String? personName,
    String? employeeId,
    String? employeeName,
    String? platformId,
    String? platformName,
    CashPaymentDetails? cashDetails,
    AppliedDiscountDetails? discount,
  }) {
    if (method == 'employee_consumption' &&
        (employeeId == null || employeeName == null)) {
      throw ArgumentError('Selecciona un empleado.');
    }
    final operationalScope = _paymentOperationalScope(
      order: order,
      openCashSession: cashSession,
    );

    final cardFeeRate = method == 'card' ? cardSurchargeRate : 0.0;
    final discountAmount = (discount?.discountAmount ?? 0).clamp(0, baseAmount);
    final chargedAmount = (baseAmount - discountAmount).clamp(
      0,
      double.infinity,
    );
    final isGlobalDiscount =
        discount != null &&
        order.discountSource == globalDiscountSource &&
        discount.type == (order.discountType ?? 'general');
    final orderGrossSubtotal = order.grossSubtotal ?? order.total;
    final orderDiscountAmount = isGlobalDiscount
        ? order.explicitDiscount
        : discountAmount;
    final orderNetTotal = isGlobalDiscount
        ? order.netTotal ?? orderGrossSubtotal - orderDiscountAmount
        : orderGrossSubtotal - orderDiscountAmount;
    final cardFeeAbsorbedAmount = chargedAmount * cardFeeRate;
    final surchargeRate = 0.0;
    final surchargeAmount = 0.0;
    if (method == 'cash' &&
        cashDetails != null &&
        cashDetails.receivedAmount + 0.01 < chargedAmount) {
      throw ArgumentError('El efectivo recibido no cubre el total.');
    }

    return {
      'orderId': order.id,
      'tableId': order.tableId,
      'tableName': order.displayName,
      'orderType': order.orderType,
      'customerName': order.customerName,
      'restaurantId': order.restaurantId,
      'restaurantName': order.restaurantName,
      'branchId': order.branchId,
      'branchName': order.branchName,
      'type': type,
      'paymentType': type,
      'personNumber': personNumber,
      'personName': personName,
      'method': method,
      'status': 'active',
      'subtotalBeforeDiscount': baseAmount,
      'discountAmount': discountAmount,
      'totalAfterDiscount': chargedAmount,
      'appliedAmount': chargedAmount,
      'appliedDiscountType': discount?.type,
      'appliedDiscountName': discount?.name,
      'appliedDiscountPercent': discount?.percent ?? 0.0,
      'discountApplied': discountAmount > 0.01,
      'discountSource': isGlobalDiscount
          ? globalDiscountSource
          : discount == null
          ? noDiscountSource
          : discount.type,
      'discountCatalogId': isGlobalDiscount
          ? order.discountCatalogId ?? globalDiscountCatalogId
          : discount?.discountAuthorizationRequestId,
      'discountName': discount?.name,
      'discountPercent': discount?.percent ?? 0.0,
      'orderDiscountAmount': orderDiscountAmount,
      'orderGrossSubtotal': orderGrossSubtotal,
      'orderNetTotal': orderNetTotal,
      'discountAuthorizedByPartnerId': discount?.authorizedByPartnerId,
      'discountAuthorizedByPartnerName': discount?.authorizedByPartnerName,
      'discountAuthorizedByPartnerLinkedEmployeeId':
          discount?.authorizedByPartnerLinkedEmployeeId,
      'discountAuthorizedByPartnerLinkedEmployeeName':
          discount?.authorizedByPartnerLinkedEmployeeName,
      'discountEmployeeBeneficiaryId': discount?.employeeBeneficiaryId,
      'discountEmployeeBeneficiaryName': discount?.employeeBeneficiaryName,
      'discountAuthorizationRequestId':
          discount?.discountAuthorizationRequestId,
      'discountAuthorizationMode': discount?.authorizationMode,
      'discountAuthorizationStatus': discount?.authorizationStatus,
      'discountReason': discount?.reason,
      if (discount != null) ...{
        'discountAppliedAt': FieldValue.serverTimestamp(),
        ..._employeeAuditFields(prefix: 'discountAppliedBy'),
      },
      'baseAmount': baseAmount,
      'amount': chargedAmount,
      'surchargeRate': surchargeRate,
      'surchargeAmount': surchargeAmount,
      'chargedAmount': chargedAmount,
      'cardFeeRate': cardFeeRate,
      'cardFeeAbsorbedAmount': cardFeeAbsorbedAmount,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'platformId': platformId,
      'platformName': platformName,
      if (method == 'cash' && cashDetails != null) ...{
        'cashReceivedAmount': cashDetails.receivedAmount,
        'cashChangeAmount': cashDetails.changeAmount,
      },
      'cashSessionId': operationalScope.cashSessionId,
      'businessDate': operationalScope.businessDate,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      ..._employeeAuditFields(prefix: 'createdBy'),
    };
  }

  OrderPaymentReconciliationTotals _reconcileOrderPayments({
    required PosOrder order,
    required Iterable<Payment> previousActivePayments,
    Map<String, Object?>? newPaymentData,
    String? newPaymentId,
  }) {
    final entries = <PaymentSettlementInput>[
      ...previousActivePayments
          .where((payment) => payment.isActive)
          .map(PaymentSettlementInput.fromPayment),
      if (newPaymentData != null)
        PaymentSettlementInput.fromPaymentData(
          newPaymentId ?? '',
          newPaymentData,
        ),
    ];
    return reconcileOrderPayments(
      orderGrossTotal: order.total,
      activePayments: entries,
    );
  }

  Map<String, Object?> _orderAggregateSnapshotFromPayments({
    required OrderPaymentReconciliationTotals totals,
    PosOrder? order,
    AppliedDiscountDetails? discount,
  }) {
    final employee = AppSession.instance.employee;
    if (!totals.discountApplied) {
      return {
        'discountApplied': false,
        'discountSource': noDiscountSource,
        'discountCatalogId': null,
        'discountType': 'none',
        'discountName': null,
        'discountConcept': null,
        'discountPercent': 0.0,
        'effectiveDiscountPercent': 0.0,
        'discountRate': 0.0,
        'discountAmount': 0.0,
        'totalDiscountAmount': 0.0,
        'grossSubtotal': totals.orderGrossTotal,
        'netTotal': totals.orderGrossTotal,
        'monetaryPaid': totals.monetaryPaid,
        'totalLiquidated': totals.totalLiquidated,
      };
    }

    final type = totals.lastDiscountType?.trim().isNotEmpty == true
        ? totals.lastDiscountType!.trim()
        : discount?.type ?? order?.discountType ?? 'mixed';
    final name = totals.lastDiscountName?.trim().isNotEmpty == true
        ? totals.lastDiscountName!.trim()
        : discount?.name ?? order?.discountName ?? 'Descuento';
    final configuredPercent = totals.lastDiscountPercent > 0
        ? totals.lastDiscountPercent
        : discount?.percent ?? order?.discountPercent ?? 0.0;
    final effectivePercent = totals.effectiveDiscountPercent;
    return {
      'discountApplied': true,
      'discountSource': type,
      'discountCatalogId':
          discount?.discountAuthorizationRequestId?.trim().isNotEmpty == true
          ? discount!.discountAuthorizationRequestId
          : order?.discountCatalogId ?? type,
      'discountType': type,
      'discountName': name,
      'discountConcept': name,
      'discountPercent': configuredPercent > 0
          ? configuredPercent
          : effectivePercent,
      'effectiveDiscountPercent': effectivePercent,
      'discountRate':
          (configuredPercent > 0 ? configuredPercent : effectivePercent) / 100,
      'discountAmount': totals.discountAmount,
      'totalDiscountAmount': totals.discountAmount,
      'grossSubtotal': totals.orderGrossTotal,
      'netTotal': totals.netTotal,
      'monetaryPaid': totals.monetaryPaid,
      'totalLiquidated': totals.totalLiquidated,
      if (discount?.reason.trim().isNotEmpty == true)
        'discountReason': discount!.reason,
      if (discount != null) 'discountAppliedAt': FieldValue.serverTimestamp(),
      if (discount != null) ...{
        'discountAppliedByEmployeeId': employee?.id ?? '',
        'discountAppliedByEmployeeName': employee?.name ?? '',
        'discountAuthorizedByEmployeeId':
            discount.authorizedByPartnerLinkedEmployeeId ??
            discount.authorizedByPartnerId ??
            '',
        'discountAuthorizedByEmployeeName':
            discount.authorizedByPartnerLinkedEmployeeName ??
            discount.authorizedByPartnerName ??
            '',
        'lastAppliedDiscountType': discount.type,
        'lastAppliedDiscountName': discount.name,
        'lastDiscountReason': discount.reason,
        'lastDiscountAuthorizationMode': discount.authorizationMode,
        'lastDiscountAuthorizationStatus': discount.authorizationStatus,
      },
    };
  }

  void _recordDiscountUsageInBatch(
    WriteBatch batch, {
    required DocumentReference<Map<String, dynamic>> usageRef,
    required PosOrder order,
    required String paymentId,
    required CashSession cashSession,
    required AppliedDiscountDetails? discount,
  }) {
    if (discount == null || discount.discountAmount <= 0) {
      return;
    }
    batch.set(usageRef, {
      'restaurantId': order.restaurantId,
      'restaurantName': order.restaurantName,
      'branchId': order.branchId,
      'branchName': order.branchName,
      'businessDate': cashSession.businessDate,
      'employeeId': discount.employeeBeneficiaryId,
      'employeeName': discount.employeeBeneficiaryName,
      'partnerId': discount.authorizedByPartnerId,
      'partnerName': discount.authorizedByPartnerName,
      'linkedEmployeeId': discount.authorizedByPartnerLinkedEmployeeId,
      'linkedEmployeeName': discount.authorizedByPartnerLinkedEmployeeName,
      'discountAuthorizationRequestId': discount.discountAuthorizationRequestId,
      'authorizationMode': discount.authorizationMode,
      'authorizationStatus': discount.authorizationStatus,
      'discountType': discount.type,
      'discountName': discount.name,
      'discountPercent': discount.percent,
      'orderId': order.id,
      'paymentId': paymentId,
      'amountBeforeDiscount': discount.amountBeforeDiscount,
      'discountAmount': discount.discountAmount,
      'totalAfterDiscount': discount.totalAfterDiscount,
      'reason': discount.reason,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      ..._employeeAuditFields(prefix: 'createdBy'),
    });
  }

  Future<void> _ensureDiscountAuthorizationStillUsable(
    AppliedDiscountDetails? discount,
    PosOrder order,
    double expectedAmountBeforeDiscount,
  ) async {
    _ensurePaymentDiscountMatchesOrder(
      order: order,
      discount: discount,
      expectedAmountBeforeDiscount: expectedAmountBeforeDiscount,
    );
    final requestId = discount?.discountAuthorizationRequestId?.trim();
    if (requestId == null || requestId.isEmpty) {
      return;
    }
    final doc = await _discountAuthorizationRequestsRef.doc(requestId).get();
    if (!doc.exists) {
      throw StateError('La autorización ya no existe.');
    }
    final request = DiscountAuthorizationRequest.fromDoc(doc);
    if (request.orderId != order.id || !request.isUsable) {
      throw StateError('La autorización ya fue usada o ya no está vigente.');
    }
  }

  void _ensurePaymentDiscountMatchesOrder({
    required PosOrder order,
    required AppliedDiscountDetails? discount,
    required double expectedAmountBeforeDiscount,
  }) {
    if (discount == null) return;
    final mismatch = validateCheckoutDraftScope(
      currentOrderId: order.id,
      currentRestaurantId: order.restaurantId,
      currentBranchId: order.branchId,
      currentBusinessDate: _businessDateForOrder(order),
      currentOrderTotal: order.total,
      currentSelectedAmount: expectedAmountBeforeDiscount,
      draftOrderId: discount.orderId,
      draftRestaurantId: discount.restaurantId,
      draftBranchId: discount.branchId,
      draftBusinessDate: discount.businessDate,
      draftTotalSnapshot: discount.totalSnapshot,
      draftAmountBeforeDiscount: discount.amountBeforeDiscount,
    );
    if (mismatch != null) throw StateError(mismatch);
    if ((discount.discountAmount +
                discount.totalAfterDiscount -
                discount.amountBeforeDiscount)
            .abs() >
        0.02) {
      throw StateError(checkoutScopeMismatchMessage);
    }
  }

  void _markDiscountAuthorizationUsedInBatch(
    WriteBatch batch, {
    required AppliedDiscountDetails? discount,
    required String paymentId,
  }) {
    final requestId = discount?.discountAuthorizationRequestId?.trim();
    if (requestId == null || requestId.isEmpty) {
      return;
    }
    batch.update(_discountAuthorizationRequestsRef.doc(requestId), {
      'status': 'used',
      'usedAt': FieldValue.serverTimestamp(),
      'usedPaymentId': paymentId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancelPayment({
    required String orderId,
    required String paymentId,
    required String reason,
  }) async {
    _requireCancelPayments();
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Captura el motivo de cancelacion.');
    }

    final orderRef = _ordersRef.doc(orderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists) {
      throw StateError('La orden ya no existe.');
    }
    final order = PosOrder.fromDoc(orderDoc);
    if (order.status == 'paid' || order.paymentStatus == 'paid') {
      throw StateError('No se puede cancelar pagos de una orden cerrada.');
    }

    final paymentRef = orderRef.collection('payments').doc(paymentId);
    final paymentDoc = await paymentRef.get();
    if (!paymentDoc.exists) {
      throw StateError('El pago ya no existe.');
    }
    final payment = Payment.fromDoc(paymentDoc);
    if (!payment.isActive) {
      throw StateError('El pago ya esta cancelado.');
    }
    final paymentsSnapshot = await orderRef.collection('payments').get();
    final remainingActivePayments = paymentsSnapshot.docs
        .map(Payment.fromDoc)
        .where((item) => item.isActive && item.id != paymentId)
        .toList();
    final totals = _reconcileOrderPayments(
      order: order,
      previousActivePayments: remainingActivePayments,
    );
    final itemsSnapshot = await orderRef.collection('items').get();
    final batch = _db.batch();

    batch.update(paymentRef, {
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelReason': cleanReason,
      ..._employeeAuditFields(prefix: 'cancelledBy'),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final discountUsageSnapshot = await _discountUsageRef
        .where('paymentId', isEqualTo: paymentId)
        .where('status', isEqualTo: 'active')
        .get();
    for (final doc in discountUsageSnapshot.docs) {
      batch.update(doc.reference, {
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelReason': cleanReason,
        ..._employeeAuditFields(prefix: 'cancelledBy'),
      });
    }
    final authorizationRequestId = payment.discountAuthorizationRequestId
        ?.trim();
    if (authorizationRequestId != null && authorizationRequestId.isNotEmpty) {
      batch.update(
        _discountAuthorizationRequestsRef.doc(authorizationRequestId),
        {
          'status': 'approved',
          'usedAt': FieldValue.delete(),
          'usedPaymentId': '',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    }
    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.paymentId == paymentId) {
        batch.update(doc.reference, {
          'paymentStatus': 'pending',
          'paymentId': FieldValue.delete(),
          'paidAt': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    batch.update(orderRef, {
      'paymentStatus': totals.paymentStatus,
      'paidTotal': totals.paidTotal,
      'pendingTotal': totals.pendingTotal,
      ..._orderAggregateSnapshotFromPayments(totals: totals, order: order),
      'paidAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _logActivityInBatch(
      batch,
      type: 'payment_cancelled',
      orderId: order.id,
      data: {
        'paymentId': paymentId,
        'reason': cleanReason,
        'baseAmount': payment.baseAmount,
        'chargedAmount': payment.chargedAmount,
      },
    );
    await batch.commit();
    invalidateReportDataCache(
      branchId: order.branchId,
      startBusinessDate: order.businessDate,
      endBusinessDate: order.businessDate,
    );
  }

  Future<bool> backofficeSaleHasClosedCashSession({
    required PosOrder order,
    required Iterable<Payment> payments,
  }) async {
    return await _closedCashSessionIdForSale(
          order: order,
          payments: payments,
        ) !=
        null;
  }

  Future<BackofficeCancellationResult> cancelCustomerPaymentFromBackoffice({
    required String orderId,
    required String paymentId,
    required String reason,
  }) async {
    _requireBackofficeCancelPayments();
    final cleanReason = reason.trim();
    if (!isValidCancellationReason(cleanReason)) {
      throw ArgumentError('Captura el motivo de cancelacion.');
    }

    final orderRef = _ordersRef.doc(orderId);
    final paymentRef = orderRef.collection('payments').doc(paymentId);
    final orderDoc = await orderRef.get();
    final paymentDoc = await paymentRef.get();
    if (!orderDoc.exists) throw StateError('La orden ya no existe.');
    if (!paymentDoc.exists) throw StateError('El pago ya no existe.');

    final initialOrder = PosOrder.fromDoc(orderDoc);
    final initialPayment = Payment.fromDoc(paymentDoc);
    final paymentsSnapshot = await orderRef.collection('payments').get();
    final itemsSnapshot = await orderRef.collection('items').get();
    final usageSnapshot = await _discountUsageRef
        .where('paymentId', isEqualTo: paymentId)
        .where('status', isEqualTo: 'active')
        .get();
    final closedCashSessionId = await _closedCashSessionIdForSale(
      order: initialOrder,
      payments: [
        initialPayment,
        ...paymentsSnapshot.docs
            .where((doc) => doc.id != paymentId)
            .map(Payment.fromDoc),
      ],
    );
    final activityRef = _restaurantRef.collection('activityLog').doc();
    final employee = AppSession.instance.employee;

    final result = await _db.runTransaction<BackofficeCancellationResult>((
      transaction,
    ) async {
      final freshOrderDoc = await transaction.get(orderRef);
      final freshPaymentDoc = await transaction.get(paymentRef);
      if (!freshOrderDoc.exists) throw StateError('La orden ya no existe.');
      if (!freshPaymentDoc.exists) throw StateError('El pago ya no existe.');

      final freshPaymentDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in paymentsSnapshot.docs) {
        freshPaymentDocs.add(await transaction.get(doc.reference));
      }
      final freshItemDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in itemsSnapshot.docs) {
        freshItemDocs.add(await transaction.get(doc.reference));
      }
      final freshUsageDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in usageSnapshot.docs) {
        freshUsageDocs.add(await transaction.get(doc.reference));
      }

      final order = PosOrder.fromDoc(freshOrderDoc);
      final payment = Payment.fromDoc(freshPaymentDoc);
      if (isTerminalCancellationStatus(payment.status) ||
          payment.cancelledAt != null) {
        throw StateError('Este pago ya fue cancelado.');
      }
      final cancelledAmount = PaymentSettlementInput.fromPayment(
        payment,
      ).grossAmount;
      if (cancelledAmount <= backofficeCancellationTolerance) {
        throw StateError('Este pago ya no tiene un importe activo.');
      }

      final remainingPayments = freshPaymentDocs
          .where((doc) => doc.id != paymentId && doc.exists)
          .map(Payment.fromDoc)
          .where((item) => item.isActive)
          .toList();
      final totals = _reconcileOrderPayments(
        order: order,
        previousActivePayments: remainingPayments,
      );
      final activeItems = freshItemDocs
          .where((doc) => doc.exists)
          .map(OrderItem.fromDoc)
          .where(isActiveOrderItem)
          .toList();
      final nextOrderStatus = deriveOrderStatusAfterCustomerPaymentCancellation(
        currentOrderStatus: order.status,
        paymentStatus: totals.paymentStatus,
        hasActiveItems: activeItems.isNotEmpty,
        activeKitchenStatuses: activeItems.map((item) => item.kitchenStatus),
      );
      final now = FieldValue.serverTimestamp();

      transaction.update(paymentRef, {
        'status': 'cancelled',
        'cancelledAt': now,
        'cancelledByEmployeeId': employee?.id ?? '',
        'cancelledByEmployeeName': employee?.name ?? '',
        'cancelReason': cleanReason,
        'updatedAt': now,
      });
      for (final doc in freshItemDocs) {
        if (!doc.exists) continue;
        final item = OrderItem.fromDoc(doc);
        if (item.paymentId == paymentId && !item.isCancelled) {
          transaction.update(doc.reference, {
            'paymentStatus': 'pending',
            'paymentId': FieldValue.delete(),
            'paidAt': FieldValue.delete(),
            'updatedAt': now,
          });
        }
      }
      for (final doc in freshUsageDocs) {
        if (!doc.exists) continue;
        transaction.update(doc.reference, {
          'status': 'cancelled',
          'cancelledAt': now,
          'cancelReason': cleanReason,
          'cancelledByEmployeeId': employee?.id ?? '',
          'cancelledByEmployeeName': employee?.name ?? '',
          'updatedAt': now,
        });
      }
      transaction.update(orderRef, {
        'status': nextOrderStatus,
        'paymentStatus': totals.paymentStatus,
        'paidTotal': totals.paidTotal,
        'pendingTotal': totals.pendingTotal,
        ..._orderAggregateSnapshotFromPayments(totals: totals, order: order),
        if (totals.paymentStatus != 'paid') ...{
          'paidAt': FieldValue.delete(),
          'closedAt': FieldValue.delete(),
        },
        'updatedAt': now,
      });
      transaction.set(activityRef, {
        'type': 'customer_payment_cancelled',
        'actionType': 'customer_payment_cancelled',
        'message':
            'Se canceló un pago de \$${cancelledAmount.toStringAsFixed(2)} de la venta ${_shortLogFolio(order.id)}.',
        'orderId': order.id,
        'folio': _shortLogFolio(order.id),
        'paymentId': payment.id,
        'method': payment.method,
        'amount': cancelledAmount,
        'cancelReason': cleanReason,
        'previousPaidTotal': order.paidTotal,
        'newPaidTotal': totals.paidTotal,
        'previousPendingTotal': order.pendingTotal,
        'newPendingTotal': totals.pendingTotal,
        'cashSessionId': payment.cashSessionId ?? order.cashSessionId ?? '',
        'businessDate': payment.businessDate ?? order.businessDate ?? '',
        'branchId': order.branchId,
        'branchName': order.branchName,
        'employeeId': employee?.id ?? '',
        'employeeName': employee?.name ?? '',
        'cashSessionRecalculationRecommended': closedCashSessionId != null,
        'timestamp': now,
        'createdAt': now,
        'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      });
      final folioAssignment = _saleFolioAssignmentFromOrder(order);
      if (folioAssignment != null) {
        _setSaleAuditEventInTransaction(
          transaction,
          branchId: order.branchId,
          eventType: 'payment_adjusted',
          order: order,
          assignment: folioAssignment,
          amount: cancelledAmount,
          paymentSnapshot: freshPaymentDoc.data() ?? const {},
          previousStatus: order.paymentStatus,
          newStatus: totals.paymentStatus,
          reason: cleanReason,
          authorizedBy: employee?.id ?? '',
          performedBy: employee?.name ?? '',
          deviceId: _auth.currentUser?.uid ?? 'anonymous',
          createdAt: now,
        );
      }

      return BackofficeCancellationResult(
        affectedClosedCashSession: closedCashSessionId != null,
        previousPaidTotal: order.paidTotal,
        newPaidTotal: totals.paidTotal,
        previousPendingTotal: order.pendingTotal,
        newPendingTotal: totals.pendingTotal,
      );
    });

    invalidateReportDataCache(
      branchId: initialOrder.branchId,
      startBusinessDate: initialOrder.businessDate,
      endBusinessDate: initialOrder.businessDate,
    );
    return result;
  }

  Future<BackofficeCancellationResult> cancelCustomerOrderFromBackoffice({
    required String orderId,
    required String reason,
  }) async {
    _requireBackofficeCancelOrders();
    final cleanReason = reason.trim();
    if (!isValidCancellationReason(cleanReason)) {
      throw ArgumentError('Captura el motivo de cancelacion.');
    }

    final orderRef = _ordersRef.doc(orderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists) throw StateError('La orden ya no existe.');
    final initialOrder = PosOrder.fromDoc(orderDoc);
    final paymentsSnapshot = await orderRef.collection('payments').get();
    final itemsSnapshot = await orderRef.collection('items').get();
    final tableRefs = orderUsesPhysicalTables(initialOrder)
        ? initialOrder.linkedTableIds.map(_tablesRef.doc).toList()
        : <DocumentReference<Map<String, dynamic>>>[];
    final closedCashSessionId = await _closedCashSessionIdForSale(
      order: initialOrder,
      payments: paymentsSnapshot.docs.map(Payment.fromDoc),
    );
    final activityRef = _restaurantRef.collection('activityLog').doc();
    final employee = AppSession.instance.employee;

    final result = await _db.runTransaction<BackofficeCancellationResult>((
      transaction,
    ) async {
      final freshOrderDoc = await transaction.get(orderRef);
      if (!freshOrderDoc.exists) throw StateError('La orden ya no existe.');
      final freshPaymentDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in paymentsSnapshot.docs) {
        freshPaymentDocs.add(await transaction.get(doc.reference));
      }
      final freshItemDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in itemsSnapshot.docs) {
        freshItemDocs.add(await transaction.get(doc.reference));
      }
      final freshTableDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in tableRefs) {
        freshTableDocs.add(await transaction.get(ref));
      }

      final order = PosOrder.fromDoc(freshOrderDoc);
      if (isTerminalCancellationStatus(order.status) ||
          order.cancelledAt != null ||
          order.canceledAt != null) {
        throw StateError('Este registro ya fue cancelado.');
      }
      final activePayments = freshPaymentDocs
          .where((doc) => doc.exists)
          .map(Payment.fromDoc)
          .where((payment) => payment.isActive)
          .toList();
      final activePaymentsTotal = activePayments.fold<double>(
        0,
        (total, payment) =>
            total + PaymentSettlementInput.fromPayment(payment).grossAmount,
      );
      if (activePaymentsTotal > backofficeCancellationTolerance) {
        throw StateError(
          'No puedes cancelar esta venta porque todavía tiene pagos activos por \$${activePaymentsTotal.toStringAsFixed(2)}. Cancela primero los pagos desde la sección Pagos.',
        );
      }

      final activeItemDocs = freshItemDocs.where((doc) {
        return doc.exists && isActiveOrderItem(OrderItem.fromDoc(doc));
      }).toList();
      final grossSubtotal = order.grossSubtotal ?? order.total;
      final netTotal =
          order.netTotal ??
          (grossSubtotal - order.explicitDiscount)
              .clamp(0, double.infinity)
              .toDouble();
      final now = FieldValue.serverTimestamp();

      transaction.update(orderRef, {
        'status': 'cancelled',
        'kitchenStatus': 'cancelled',
        'paymentStatus': 'cancelled',
        'cancelStatus': 'accepted',
        'cancelledAt': now,
        'cancelledByEmployeeId': employee?.id ?? '',
        'cancelledByEmployeeName': employee?.name ?? '',
        'cancelReason': cleanReason,
        'pendingTotal': 0.0,
        'paidTotal': 0.0,
        'updatedAt': now,
      });
      for (final doc in activeItemDocs) {
        transaction.update(doc.reference, {
          'status': 'cancelled',
          'kitchenStatus': 'cancelled',
          'paymentStatus': 'cancelled',
          'cancelStatus': 'accepted',
          'cancelReason': cleanReason,
          'cancelledAt': now,
          'cancelledByEmployeeId': employee?.id ?? '',
          'cancelledByEmployeeName': employee?.name ?? '',
          'updatedAt': now,
        });
      }
      for (final doc in freshTableDocs) {
        if (!doc.exists) continue;
        final currentOrderId = doc.data()?['currentOrderId']?.toString();
        if (!shouldReleaseBackofficeCancelledOrderTable(
          currentOrderId: currentOrderId,
          cancelledOrderId: order.id,
        )) {
          continue;
        }
        transaction.update(doc.reference, {
          'status': 'available',
          'currentOrderId': null,
          'currentOrderStatus': null,
          'tableGroupId': null,
          'tableGroupLabel': null,
          'groupPrimaryTableId': null,
          'occupiedAt': null,
          'updatedAt': now,
        });
      }
      transaction.set(activityRef, {
        'type': 'customer_order_cancelled',
        'actionType': 'customer_order_cancelled',
        'message': 'Se canceló la orden ${_shortLogFolio(order.id)}.',
        'orderId': order.id,
        'folio': _shortLogFolio(order.id),
        'orderType': order.orderType,
        'tableId': order.tableId,
        'tableIds': order.linkedTableIds,
        'grossSubtotal': grossSubtotal,
        'discountAmount': order.explicitDiscount,
        'netTotal': netTotal,
        'cancelReason': cleanReason,
        'cancelledItemsCount': activeItemDocs.length,
        'cashSessionId': order.cashSessionId ?? '',
        'businessDate': order.businessDate ?? '',
        'branchId': order.branchId,
        'branchName': order.branchName,
        'employeeId': employee?.id ?? '',
        'employeeName': employee?.name ?? '',
        'cashSessionRecalculationRecommended': closedCashSessionId != null,
        'timestamp': now,
        'createdAt': now,
        'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      });
      final folioAssignment = _saleFolioAssignmentFromOrder(order);
      if (folioAssignment != null) {
        _setSaleAuditEventInTransaction(
          transaction,
          branchId: order.branchId,
          eventType: 'sale_voided',
          order: order,
          assignment: folioAssignment,
          amount: netTotal,
          paymentSnapshot: {
            'activePaymentsTotal': activePaymentsTotal,
            'paymentsCount': activePayments.length,
          },
          previousStatus: order.paymentStatus,
          newStatus: 'cancelled',
          reason: cleanReason,
          authorizedBy: employee?.id ?? '',
          performedBy: employee?.name ?? '',
          deviceId: _auth.currentUser?.uid ?? 'anonymous',
          createdAt: now,
        );
      }

      return BackofficeCancellationResult(
        affectedClosedCashSession: closedCashSessionId != null,
        previousPaidTotal: order.paidTotal,
        previousPendingTotal: order.pendingTotal,
        cancelledItemsCount: activeItemDocs.length,
      );
    });

    invalidateReportDataCache(
      branchId: initialOrder.branchId,
      startBusinessDate: initialOrder.businessDate,
      endBusinessDate: initialOrder.businessDate,
    );
    return result;
  }

  Future<BackofficeCancellationResult>
  reconcilePartialCancellationFromBackoffice({required String orderId}) async {
    _requireBackofficeCancelOrders();
    final orderRef = _ordersRef.doc(orderId);
    final initialOrderDoc = await orderRef.get();
    if (!initialOrderDoc.exists) {
      throw StateError('La orden ya no existe.');
    }
    final initialOrder = PosOrder.fromDoc(initialOrderDoc);
    final initialItemsSnapshot = await orderRef.collection('items').get();
    final initialItems = initialItemsSnapshot.docs.map(OrderItem.fromDoc);
    if (!isPartialCancellationWithActiveItems(
      order: initialOrder,
      items: initialItems,
    )) {
      throw StateError(
        'La orden no requiere reconciliacion de cancelacion parcial.',
      );
    }

    await _reconcileOrderAfterItemCancellation(
      orderId,
      reason: 'backoffice_partial_cancellation_reconcile',
    );

    final updatedOrderDoc = await orderRef.get();
    final updatedOrder = updatedOrderDoc.exists
        ? PosOrder.fromDoc(updatedOrderDoc)
        : initialOrder;
    return BackofficeCancellationResult(
      affectedClosedCashSession: false,
      previousPaidTotal: initialOrder.paidTotal,
      newPaidTotal: updatedOrder.paidTotal,
      previousPendingTotal: initialOrder.pendingTotal,
      newPendingTotal: updatedOrder.pendingTotal,
    );
  }

  Future<String?> _closedCashSessionIdForSale({
    required PosOrder order,
    required Iterable<Payment> payments,
  }) async {
    final ids = <String>{
      if (order.cashSessionId?.trim().isNotEmpty == true)
        order.cashSessionId!.trim(),
      ...payments
          .map((payment) => payment.cashSessionId?.trim() ?? '')
          .where((id) => id.isNotEmpty),
    };
    for (final id in ids) {
      final doc = await _cashSessionsRef.doc(id).get();
      if (!doc.exists) continue;
      final session = CashSession.fromDoc(doc);
      if (!session.isOpen) return id;
    }
    return null;
  }

  Map<String, Object> _employeeAuditFields({required String prefix}) {
    final employee = AppSession.instance.employee;
    if (employee == null) {
      return const {};
    }
    return {
      '${prefix}EmployeeId': employee.id,
      '${prefix}EmployeeName': employee.name,
    };
  }

  void _requireTakeOrders() {
    final employee = AppSession.instance.employee;
    if (employee?.canTakeOrders == true ||
        employee?.canControlLiveOperations == true) {
      return;
    }
    throw StateError('No tienes permiso para levantar pedidos');
  }

  void _requireCharge() {
    final employee = AppSession.instance.employee;
    if (employee?.canCharge == true ||
        employee?.canControlLiveOperations == true) {
      return;
    }
    throw StateError('No tienes permiso para cobrar');
  }

  void _requireCancelOrders() {
    final employee = AppSession.instance.employee;
    if (employee?.canCancelOrders == true ||
        employee?.canViewAdmin == true ||
        employee?.canControlLiveOperations == true) {
      return;
    }
    throw StateError('No tienes permiso para cancelar tickets.');
  }

  void _requireBackofficeCancelOrders() {
    final employee = AppSession.instance.employee;
    if (employee != null &&
        hasBackofficeCancellationPermission(
          specificPermission: employee.canCancelOrders,
          canViewAdmin: employee.canViewAdmin,
          hasAdminAccess: employee.hasAdminAccess,
        )) {
      return;
    }
    throw StateError('No tienes permiso para cancelar órdenes.');
  }

  void _requireCancelPayments() {
    final employee = AppSession.instance.employee;
    if (employee?.canCancelPayments == true ||
        employee?.canViewAdmin == true ||
        employee?.canControlLiveOperations == true) {
      return;
    }
    throw StateError('No tienes permiso para cancelar pagos.');
  }

  void _requireBackofficeCancelPayments() {
    final employee = AppSession.instance.employee;
    if (employee != null &&
        hasBackofficeCancellationPermission(
          specificPermission: employee.canCancelPayments,
          canViewAdmin: employee.canViewAdmin,
          hasAdminAccess: employee.hasAdminAccess,
        )) {
      return;
    }
    throw StateError('No tienes permiso para cancelar pagos.');
  }

  void _requireCancelItems() {
    final employee = AppSession.instance.employee;
    if (employee?.canCancelItems == true ||
        employee?.canCancelOrders == true ||
        employee?.canViewAdmin == true ||
        employee?.canControlLiveOperations == true) {
      return;
    }
    throw StateError('No tienes permiso para cancelar articulos.');
  }

  void _requireKitchenCancellationApprover() {
    final employee = AppSession.instance.employee;
    if (employee?.canApproveKitchenCancellations == true ||
        employee?.canViewKitchen == true ||
        employee?.canViewAdmin == true ||
        employee?.canControlLiveOperations == true) {
      return;
    }
    throw StateError('No tienes permiso para resolver cancelaciones.');
  }

  void _ensureItemEditable(OrderItem item) {
    if (item.kitchenStatus == 'ready') {
      throw StateError(
        'Este producto ya fue servido por cocina y no puede modificarse.',
      );
    }
    if (['sent', 'cooking'].contains(item.kitchenStatus)) {
      throw StateError(
        'Este producto ya esta en cocina y no puede modificarse libremente.',
      );
    }
    if (item.paymentStatus == 'paid') {
      throw StateError('Este producto ya fue pagado y no puede modificarse.');
    }
  }

  Future<void> _ensureCancellationKeepsPaymentsValid(
    String orderId,
    OrderItem cancellingItem,
  ) async {
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = orderDoc.exists ? PosOrder.fromDoc(orderDoc) : null;
    if (order == null) {
      return;
    }
    final items = await getOrderItemsOnce(orderId);
    final remainingTotal = activeOrderItemsTotal(
      items.where((item) => item.id != cancellingItem.id),
    );
    final discountAmount = order.explicitDiscount
        .clamp(0, remainingTotal)
        .toDouble();
    final newTotal = (remainingTotal - discountAmount)
        .clamp(0, double.infinity)
        .toDouble();
    final payments = await getOrderPaymentsOnce(orderId);
    final paidTotal = payments
        .where((payment) => payment.isActive)
        .fold<double>(0, (total, payment) => total + payment.baseAmount);
    if (newTotal + 0.01 < paidTotal) {
      throw StateError(
        'No se puede cancelar porque la orden ya tiene pagos que superan el nuevo total.',
      );
    }
  }

  void _requireCashManager() {
    if (AppSession.instance.employee?.canManageCash == true) {
      return;
    }
    throw StateError('No tienes permiso para cerrar caja.');
  }

  void _requireHistoricalCashCorrectionAdmin() {
    if (AppSession.instance.employee?.hasAdminAccess == true) {
      return;
    }
    throw StateError('Solo un administrador puede rehacer cortes historicos.');
  }

  void _requireHistoricalCashExpenseAdmin() {
    final employee = AppSession.instance.employee;
    if (employee?.hasAdminAccess == true ||
        employee?.canViewAdmin == true ||
        employee?.canManageCash == true) {
      return;
    }
    throw StateError('No tienes permiso para agregar gastos historicos.');
  }

  void _requireHistoricalCashCorrectionPin(String pin) {
    if (pin.trim() == '072026') {
      return;
    }
    throw StateError('PIN de administrador incorrecto.');
  }

  void _requireCashWithdrawalRequester() {
    final employee = AppSession.instance.employee;
    if (employee?.canCharge == true || employee?.canManageCash == true) {
      return;
    }
    throw StateError('No tienes permiso para solicitar retiros.');
  }

  void _requireCashWithdrawalAuthorizer() {
    if (AppSession.instance.employee?.canAuthorizeCashWithdrawals == true) {
      return;
    }
    throw StateError('No tienes permiso para autorizar retiros.');
  }

  void _requirePurchaseAccess({
    bool manage = false,
    bool register = false,
    bool pay = false,
  }) {
    final employee = AppSession.instance.employee;
    if (employee?.hasAdminAccess == true) {
      return;
    }
    final allowed =
        employee?.canViewPurchases == true ||
        (manage && employee?.canManageSuppliers == true) ||
        (register && employee?.canRegisterPurchases == true) ||
        (pay && employee?.canPaySuppliers == true);
    if (allowed) {
      return;
    }
    throw StateError('No tienes permiso para administrar compras.');
  }

  void _requireCancelSupplierPaymentAccess() {
    final employee = AppSession.instance.employee;
    if (employee?.hasAdminAccess == true ||
        employee?.canCancelSupplierPayments == true ||
        employee?.canViewAdmin == true ||
        employee?.name.toLowerCase().trim() == 'admin') {
      return;
    }
    throw StateError('No tienes permiso para cancelar pagos a proveedores.');
  }

  void _requireCancelSupplierPurchaseAccess() {
    final employee = AppSession.instance.employee;
    if (employee?.hasAdminAccess == true ||
        employee?.canRegisterPurchases == true ||
        employee?.canManageSuppliers == true ||
        employee?.canViewPurchases == true ||
        employee?.canViewAccountsPayable == true ||
        employee?.name.toLowerCase().trim() == 'admin') {
      return;
    }
    throw StateError('No tienes permiso para cancelar compras a proveedor.');
  }

  void _requireOpenKitchen() {
    final employee = AppSession.instance.employee;
    if (employee?.canOpenKitchen == true ||
        employee?.canManageKitchenStock == true ||
        employee?.canViewAdmin == true) {
      return;
    }
    throw StateError('No tienes permiso para abrir cocina.');
  }

  void _requireCloseKitchen() {
    final employee = AppSession.instance.employee;
    if (employee?.canCloseKitchen == true || employee?.canViewAdmin == true) {
      return;
    }
    throw StateError('No tienes permiso para cerrar cocina.');
  }

  void _requireCashOpenPermission() {
    final employee = AppSession.instance.employee;
    if (employee?.canManageCash == true || employee?.canCharge == true) {
      return;
    }
    throw StateError('No tienes permiso para abrir caja.');
  }

  Future<CashSession> _requireOpenCashSessionForPayment() async {
    final session = await getOpenCashSession();
    if (session == null) {
      throw StateError('No hay una caja abierta para registrar el pago.');
    }
    return session;
  }

  Future<CashSession> _requireOpenCashSessionForOrder() async {
    final session = await getOpenCashSession();
    if (session == null) {
      throw StateError('Debes abrir caja antes de levantar pedidos.');
    }
    businessDateForOpenCashSession(session);
    return session;
  }

  ({String businessDate, String cashSessionId}) _paymentOperationalScope({
    required PosOrder order,
    required CashSession openCashSession,
  }) {
    final scope = resolveNewPaymentOperationalScope(
      order: order,
      activeCashSession: openCashSession,
    );
    return (
      businessDate: scope.businessDate,
      cashSessionId: scope.cashSessionId,
    );
  }

  void _logActivityInBatch(
    WriteBatch batch, {
    required String type,
    String? orderId,
    Map<String, Object?> data = const {},
  }) {
    final employee = AppSession.instance.employee;
    final logData = <String, Object?>{
      'type': type,
      ..._currentBranchFields,
      ...data,
      'employeeId': employee?.id ?? '',
      'employeeName': employee?.name ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
    };
    if (orderId != null) {
      logData['orderId'] = orderId;
    }
    batch.set(_restaurantRef.collection('activityLog').doc(), logData);
  }

  void _requireAnyPermission({
    required bool takeOrders,
    required bool charge,
    required String message,
  }) {
    final employee = AppSession.instance.employee;
    final allowed =
        (takeOrders && employee?.canTakeOrders == true) ||
        (charge && employee?.canCharge == true);
    if (!allowed) {
      throw StateError(message);
    }
  }

  Future<void> _ensureKitchenReadyForPayment(String orderId) async {
    final orderDoc = await _ordersRef.doc(orderId).get();
    if (orderDoc.exists) {
      final order = PosOrder.fromDoc(orderDoc);
      await reconcileOrderTableAndKitchenState(
        restaurantId: order.restaurantId,
        branchId: order.branchId,
        orderId: order.id,
        reason: 'payment_validation',
      );
    }
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final pendingCount = itemsSnapshot.docs
        .map(OrderItem.fromDoc)
        .where(isKitchenPendingItem)
        .length;

    if (pendingCount > 0) {
      throw StateError(
        'No se puede cobrar todavia. Hay $pendingCount ${pendingCount == 1 ? 'producto pendiente' : 'productos pendientes'} en Cocina.',
      );
    }
  }

  Future<void> _ensureNoPaymentType(
    String orderId, {
    required String blockedType,
  }) async {
    final paymentsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('payments')
        .get();
    final hasBlockedType = paymentsSnapshot.docs
        .map(Payment.fromDoc)
        .any((payment) => payment.isActive && payment.type == blockedType);

    if (hasBlockedType) {
      final message = blockedType == 'partial'
          ? 'Esta cuenta ya tiene pagos parciales. Termina el cobro por parcialidades.'
          : 'Esta cuenta ya inicio cobro por persona. Termina el cobro por persona.';
      throw StateError(message);
    }
  }

  Future<void> _ensureEmployeeConsumptionAllowed(
    String orderId,
    String method, {
    String? employeeId,
  }) async {
    if (method != 'employee_consumption') {
      return;
    }

    final cleanEmployeeId = employeeId?.trim() ?? '';
    if (cleanEmployeeId.isEmpty) {
      throw StateError('Selecciona un empleado.');
    }
    final linkedPartner = await _activePartnerLinkedToEmployee(cleanEmployeeId);
    if (linkedPartner != null) {
      throw StateError(
        'Este usuario está registrado como socio. No aplica beneficio de empleado.',
      );
    }

    final paymentsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('payments')
        .get();
    final hasClientPayment = paymentsSnapshot.docs
        .map(Payment.fromDoc)
        .any(
          (payment) =>
              payment.isActive && ['cash', 'card'].contains(payment.method),
        );

    if (hasClientPayment) {
      throw StateError(
        'Consumo empleado no disponible porque ya existe un pago de cliente.',
      );
    }
  }

  Future<void> recalculateOrderTotal(String orderId) async {
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final items = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
    final total = activeOrderItemsTotal(items);
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = orderDoc.exists ? PosOrder.fromDoc(orderDoc) : null;
    final payments = await getOrderPaymentsOnce(orderId);
    final totals = reconcileOrderPayments(
      orderGrossTotal: total,
      activePayments: payments
          .where(isCanonicalActivePayment)
          .map(PaymentSettlementInput.fromPayment),
    );

    await _ordersRef.doc(orderId).update({
      'total': total,
      'grossSubtotal': total,
      'netTotal': totals.netTotal,
      'discountAmount': totals.discountAmount,
      'totalDiscountAmount': totals.discountAmount,
      'monetaryPaid': totals.monetaryPaid,
      'totalLiquidated': totals.totalLiquidated,
      'paidTotal': totals.paidTotal,
      'pendingTotal': totals.pendingTotal,
      'paymentStatus': totals.paymentStatus,
      if (order?.status == 'paid' && totals.pendingTotal > 0.01)
        'status': 'ready',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveProduct({
    String? productId,
    required String name,
    required String categoryId,
    required String categoryName,
    required String category,
    required double price,
    double? unitCost,
    required Map<String, double> platformPrices,
    required bool active,
    required bool sendToKitchen,
    required bool affectsKitchenStock,
    required List<ProductRecipeItem> recipeItems,
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageProducts == true,
      'No tienes permiso para administrar productos.',
    );
    final docRef = productId == null
        ? _productsRef.doc()
        : _productsRef.doc(productId);
    final current = await _productsRef.get();
    final cleanCategoryName = categoryName.trim().isNotEmpty
        ? categoryName.trim()
        : category.trim();
    final cleanCategoryId = categoryId.trim().isNotEmpty
        ? categoryId.trim()
        : categoryIdForName(cleanCategoryName);
    final cleanRecipeItems = affectsKitchenStock
        ? recipeItems.where((item) => item.isValid).take(1).toList()
        : <ProductRecipeItem>[];
    if (affectsKitchenStock && cleanRecipeItems.isEmpty) {
      throw ArgumentError('Selecciona un insumo principal para rendimiento.');
    }
    final recipeIds = <String>{};
    for (final item in cleanRecipeItems) {
      if (item.consumptionFactor <= 0) {
        throw ArgumentError('El factor de equivalencia debe ser mayor a cero.');
      }
      if (!recipeIds.add(item.kitchenStockItemId)) {
        throw ArgumentError('No repitas insumos de rendimiento.');
      }
    }
    final primary = cleanRecipeItems.isEmpty ? null : cleanRecipeItems.first;

    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'categoryId': cleanCategoryId,
      'categoryName': cleanCategoryName,
      'category': cleanCategoryName,
      'price': price,
      'unitCost': unitCost,
      'platformPrices': platformPrices,
      'active': active,
      'sendToKitchen': sendToKitchen,
      'affectsKitchenStock': affectsKitchenStock,
      'recipeItems': ProductRecipeItem.toMapList(cleanRecipeItems),
      'kitchenStockItemId': primary?.kitchenStockItemId,
      'kitchenStockItemName': primary?.kitchenStockItemName,
      'kitchenStockUnit': primary?.kitchenStockUnit,
      'stockConsumptionQty': primary?.consumptionFactor,
      'kitchenConsumptionFactor': primary?.consumptionFactor,
      'sortOrder': current.docs.length + 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveTable({
    String? tableId,
    required String name,
    required String type,
    required bool active,
    required int sortOrder,
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageTables == true,
      'No tienes permiso para administrar mesas.',
    );
    final docRef = tableId == null ? _tablesRef.doc() : _tablesRef.doc(tableId);

    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'type': type,
      ..._currentBranchFields,
      'active': active,
      'sortOrder': sortOrder,
      if (tableId == null) 'status': 'available',
      if (tableId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleTable(PosTable table) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageTables == true,
      'No tienes permiso para administrar mesas.',
    );
    await _tablesRef.doc(table.id).update({
      'active': !table.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveOrderPlatform({
    String? platformId,
    required String name,
    required bool active,
    required int sortOrder,
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManagePlatforms == true,
      'No tienes permiso para administrar plataformas.',
    );
    final docRef = platformId == null
        ? _platformsRef.doc()
        : _platformsRef.doc(platformId);

    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'active': active,
      'sortOrder': sortOrder,
      if (platformId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleOrderPlatform(OrderPlatform platform) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManagePlatforms == true,
      'No tienes permiso para administrar plataformas.',
    );
    await _platformsRef.doc(platform.id).update({
      'active': !platform.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> toggleProduct(Product product) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageProducts == true,
      'No tienes permiso para administrar productos.',
    );
    await _productsRef.doc(product.id).update({
      'active': !product.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveEmployee({
    String? employeeId,
    required String name,
    required bool active,
    required String pin,
    required bool canTakeOrders,
    required bool canCharge,
    required bool canViewKitchen,
    required bool canViewAdmin,
    required bool canManageProducts,
    required bool canManageTables,
    required bool canManagePlatforms,
    required bool canManageEmployees,
    required bool canManageCash,
    required bool canAuthorizeCashWithdrawals,
    required bool canOpenKitchen,
    required bool canCloseKitchen,
    required bool canViewKitchenReports,
    required bool canViewKitchenHourlySalesComparison,
    required bool canManageKitchenStock,
    required bool canCancelOrders,
    required bool canCancelPayments,
    bool canCancelSupplierPayments = false,
    required bool canCancelItems,
    required bool canApproveKitchenCancellations,
    required bool canViewLiveOperations,
    required bool canControlLiveOperations,
    List<EmployeeBranchAccess>? branchAccess,
    String? defaultBranchId,
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageEmployees == true ||
          _canManageBranches(),
      'No tienes permiso para administrar empleados.',
    );
    final docRef = employeeId == null
        ? _employeesRef.doc()
        : _employeesRef.doc(employeeId);
    final permissions = {
      'canTakeOrders': canTakeOrders,
      'canCharge': canCharge,
      'canViewKitchen': canViewKitchen,
      'canViewAdmin': canViewAdmin,
      'canManageProducts': canManageProducts,
      'canManageTables': canManageTables,
      'canManagePlatforms': canManagePlatforms,
      'canManageEmployees': canManageEmployees,
      'canManageCash': canManageCash,
      'canAuthorizeCashWithdrawals': canAuthorizeCashWithdrawals,
      'canOpenKitchen': canOpenKitchen,
      'canCloseKitchen': canCloseKitchen,
      'canViewKitchenReports': canViewKitchenReports,
      'canViewKitchenHourlySalesComparison':
          canViewKitchenHourlySalesComparison,
      'canManageKitchenStock': canManageKitchenStock,
      'canCancelOrders': canCancelOrders,
      'canCancelPayments': canCancelPayments,
      'canCancelSupplierPayments': canCancelSupplierPayments,
      'canCancelItems': canCancelItems,
      'canApproveKitchenCancellations': canApproveKitchenCancellations,
      'canViewLiveOperations': canViewLiveOperations,
      'canControlLiveOperations': canControlLiveOperations,
    };
    final access = branchAccess == null || branchAccess.isEmpty
        ? [
            EmployeeBranchAccess(
              restaurantId: AppConstants.restaurantId,
              branchId: AppConstants.defaultBranchId,
              branchName: AppConstants.defaultBranchName,
              active: true,
              permissions: permissions,
            ),
          ]
        : branchAccess;

    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      // TODO: Replace plain PIN storage with a salted hash before production.
      'pin': pin.trim(),
      'active': active,
      'canTakeOrders': canTakeOrders,
      'canCharge': canCharge,
      'canViewKitchen': canViewKitchen,
      'canViewAdmin': canViewAdmin,
      'canManageProducts': canManageProducts,
      'canManageTables': canManageTables,
      'canManagePlatforms': canManagePlatforms,
      'canManageEmployees': canManageEmployees,
      'canManageCash': canManageCash,
      'canAuthorizeCashWithdrawals': canAuthorizeCashWithdrawals,
      'canOpenKitchen': canOpenKitchen,
      'canCloseKitchen': canCloseKitchen,
      'canViewKitchenReports': canViewKitchenReports,
      'canViewKitchenHourlySalesComparison':
          canViewKitchenHourlySalesComparison,
      'canManageKitchenStock': canManageKitchenStock,
      'canCancelOrders': canCancelOrders,
      'canCancelPayments': canCancelPayments,
      'canCancelSupplierPayments': canCancelSupplierPayments,
      'canCancelItems': canCancelItems,
      'canApproveKitchenCancellations': canApproveKitchenCancellations,
      'canViewLiveOperations': canViewLiveOperations,
      'canControlLiveOperations': canControlLiveOperations,
      'isSuperAdmin': canViewAdmin,
      'defaultRestaurantId': AppConstants.restaurantId,
      'defaultBranchId': defaultBranchId ?? access.first.branchId,
      'restaurantAccess': [AppConstants.restaurantId],
      'branchAccess': access.map((item) => item.toMap()).toList(),
      if (employeeId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleEmployee(Employee employee) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageEmployees == true ||
          _canManageBranches(),
      'No tienes permiso para administrar empleados.',
    );
    await _employeesRef.doc(employee.id).update({
      'active': !employee.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  void _requireAdminPermission(bool allowed, String message) {
    if (allowed) {
      return;
    }
    throw StateError(message);
  }

  void _requireYieldProfitAdmin() {
    final employee = AppSession.instance.employee;
    _requireAdminPermission(
      kIsWeb &&
          (employee?.hasAdminAccess == true || employee?.canViewAdmin == true),
      'No tienes permiso para administrar recetas y rendimientos.',
    );
  }

  bool _canManageBranches() {
    return AppSession.instance.employee?.hasAdminAccess == true;
  }
}

class _DefaultProductCategory {
  const _DefaultProductCategory(this.name, this.sortOrder, this.colorHex);

  final String name;
  final int sortOrder;
  final String colorHex;
}

class _PurchaseItemReportAccumulator {
  _PurchaseItemReportAccumulator({
    required this.itemId,
    required this.itemName,
    required this.unit,
    required this.affectsKitchenPerformance,
  });

  final String itemId;
  final String itemName;
  final String unit;
  bool affectsKitchenPerformance;
  double quantity = 0;
  int totalCents = 0;
  int noteCount = 0;

  double get total => purchaseAmountFromCents(totalCents);
  double get averageUnitCostCalculated => quantity <= 0 ? 0 : total / quantity;
}

String _readText(Object? value, String fallback) {
  if (value is String && value.trim().isNotEmpty) {
    return _cleanCategoryDisplayName(value);
  }
  return fallback;
}

String _cleanCategoryDisplayName(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

bool _sessionIsNewer(ActiveSession a, ActiveSession b) {
  final aSeen = a.lastSeenAt ?? a.updatedAt ?? DateTime(1970);
  final bSeen = b.lastSeenAt ?? b.updatedAt ?? DateTime(1970);
  return aSeen.isAfter(bSeen);
}

String _activeSessionGroupKey(ActiveSession session) {
  final employeeId = session.employeeId.trim();
  if (employeeId.isNotEmpty) return employeeId;
  final deviceId = session.deviceId.trim();
  if (deviceId.isNotEmpty) return deviceId;
  return session.id;
}

String normalizeStatus(Object? value) {
  return normalizeOperationalStatus(value);
}

bool isActiveOrderForLiveTables(PosOrder order) {
  return isActiveOrderState(order);
}

bool isActiveOrder(PosOrder order) => isActiveOrderForLiveTables(order);

bool _isPaidStatus(String status) {
  final normalized = normalizeStatus(status);
  return normalized == 'paid' ||
      normalized == 'pagado' ||
      normalized == 'pagada';
}

PosOrder? getActiveOrderForTable(String tableId, List<PosOrder> orders) {
  final cleanTableId = tableId.trim();
  final activeOrders =
      orders
          .where((order) => order.linkedTableIds.contains(cleanTableId))
          .where(isActiveOrderForLiveTables)
          .toList()
        ..sort((a, b) {
          final aDate =
              a.updatedAt ??
              a.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bDate =
              b.updatedAt ??
              b.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
  return activeOrders.isEmpty ? null : activeOrders.first;
}

String? _cleanColorHex(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final clean = raw.startsWith('#') ? raw.substring(1) : raw;
  if (clean.length != 6 && clean.length != 8) return null;
  final parsed = int.tryParse(clean, radix: 16);
  if (parsed == null) return null;
  return '#${clean.toUpperCase()}';
}

const _supplierPaymentMethodLabels = {
  'cash': 'Efectivo',
  'transfer': 'Transferencia',
  'partner_contribution': 'Aportacion de socios',
};

String _normalizeSupplierPaymentMethod(String value) {
  return switch (value) {
    'business_cash' || 'cash' => 'cash',
    'business_transfer' || 'transfer' => 'transfer',
    'partner_cash' ||
    'partner_transfer' ||
    'partner_contribution' => 'partner_contribution',
    _ => value,
  };
}

int _compareNullableDate(DateTime? a, DateTime? b) {
  if (a != null && b != null) return a.compareTo(b);
  if (a != null) return -1;
  if (b != null) return 1;
  return 0;
}

const _defaultKitchenStockItems = [
  {
    'id': 'bistec',
    'name': 'Bistec',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 1,
  },
  {
    'id': 'adobada',
    'name': 'Adobada',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 2,
  },
  {
    'id': 'carnaza',
    'name': 'Carnaza',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 3,
  },
  {
    'id': 'arrachera',
    'name': 'Arrachera',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 4,
  },
  {
    'id': 'chorizo',
    'name': 'Chorizo',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 5,
  },
  {
    'id': 'higado',
    'name': 'Higado',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 6,
  },
  {
    'id': 'labio',
    'name': 'Labio',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 7,
  },
  {
    'id': 'tripa',
    'name': 'Tripa',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 8,
  },
  {
    'id': 'lengua',
    'name': 'Lengua',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 9,
  },
  {
    'id': 'tortilla_maiz',
    'name': 'Tortilla de maiz',
    'category': 'tortilla',
    'unit': 'kg',
    'sortOrder': 10,
  },
  {
    'id': 'tortilla_harina',
    'name': 'Tortilla de harina',
    'category': 'tortilla',
    'unit': 'kg',
    'sortOrder': 11,
  },
  {
    'id': 'queso',
    'name': 'Queso',
    'category': 'dairy',
    'unit': 'kg',
    'sortOrder': 12,
  },
  {
    'id': 'refresco_coca_cola',
    'name': 'Refresco Coca Cola',
    'category': 'drink',
    'unit': 'piece',
    'sortOrder': 13,
  },
  {
    'id': 'refrescos_surtidos',
    'name': 'Refrescos surtidos',
    'category': 'drink',
    'unit': 'piece',
    'sortOrder': 14,
  },
  {
    'id': 'agua_fresca',
    'name': 'Agua fresca',
    'category': 'water',
    'unit': 'liter',
    'sortOrder': 15,
  },
];
