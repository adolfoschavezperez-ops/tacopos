import 'taco_pos_repository.dart' show KitchenOrderBundle;
import '../models/order_item.dart';

enum KitchenSyncStatus {
  loading,
  cache,
  pendingWrites,
  partial,
  confirmed,
  reconnecting,
  transientError,
  permanentError,
}

class KitchenSyncIssue {
  const KitchenSyncIssue(
    this.error, {
    required this.recoverable,
    this.retryAttempt = 0,
    this.retryScheduled = false,
  });
  final Object error;
  final bool recoverable;
  final int retryAttempt;
  final bool retryScheduled;
}

/// Display availability is separate from server confirmation/action readiness.
/// An empty cache snapshot cannot certify an empty kitchen.
class KitchenBundlesState {
  const KitchenBundlesState({
    this.bundles = const [],
    this.hasOrders = false,
    this.ordersFromCache = false,
    this.ordersPendingWrites = false,
    this.activeOrderIds = const {},
    this.loadingItemOrderIds = const {},
    this.cachedItemOrderIds = const {},
    this.pendingWriteItemOrderIds = const {},
    this.issues = const [],
    this.detailItemsByKitchenKey = const {},
  });

  final List<KitchenOrderBundle> bundles;
  final bool hasOrders;
  final bool ordersFromCache;
  final bool ordersPendingWrites;
  final Set<String> activeOrderIds;
  final Set<String> loadingItemOrderIds;
  final Set<String> cachedItemOrderIds;
  final Set<String> pendingWriteItemOrderIds;
  final List<KitchenSyncIssue> issues;
  final Map<String, List<OrderItem>> detailItemsByKitchenKey;

  factory KitchenBundlesState.confirmed(List<KitchenOrderBundle> bundles) =>
      KitchenBundlesState(
        bundles: bundles,
        hasOrders: true,
        activeOrderIds: bundles.map((bundle) => bundle.order.id).toSet(),
      );

  KitchenBundlesState withIssue(KitchenSyncIssue issue) => KitchenBundlesState(
    bundles: bundles,
    hasOrders: hasOrders,
    ordersFromCache: ordersFromCache,
    ordersPendingWrites: ordersPendingWrites,
    activeOrderIds: activeOrderIds,
    loadingItemOrderIds: loadingItemOrderIds,
    cachedItemOrderIds: cachedItemOrderIds,
    pendingWriteItemOrderIds: pendingWriteItemOrderIds,
    issues: [issue],
    detailItemsByKitchenKey: detailItemsByKitchenKey,
  );

  bool get hasData => bundles.isNotEmpty || isConfirmed;
  bool get isPartial => loadingItemOrderIds.isNotEmpty;
  bool get hasCache => ordersFromCache || cachedItemOrderIds.isNotEmpty;
  bool get hasPendingWrites =>
      ordersPendingWrites || pendingWriteItemOrderIds.isNotEmpty;
  bool get isConfirmed =>
      hasOrders &&
      !hasCache &&
      !hasPendingWrites &&
      !isPartial &&
      issues.isEmpty;
  KitchenSyncStatus get status {
    if (issues.any((issue) => !issue.recoverable)) {
      return KitchenSyncStatus.permanentError;
    }
    if (issues.any((issue) => issue.retryScheduled)) {
      return KitchenSyncStatus.reconnecting;
    }
    if (issues.isNotEmpty) return KitchenSyncStatus.transientError;
    if (!hasOrders) return KitchenSyncStatus.loading;
    if (hasPendingWrites) return KitchenSyncStatus.pendingWrites;
    if (isPartial) return KitchenSyncStatus.partial;
    if (hasCache) return KitchenSyncStatus.cache;
    return KitchenSyncStatus.confirmed;
  }
}
