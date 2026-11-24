import 'package:cloud_firestore/cloud_firestore.dart';

import 'order_activity.dart';
import '../../models/order.dart';

/// Derived query fields. Keep this predicate aligned with isActiveOrderState.
/// Missing legacy branch IDs map to the configured default branch.
Map<String, Object?> operationalOrderFields(
  Map<String, dynamic> data, {
  required String defaultBranchId,
}) {
  // Build only the fields consumed by isActiveOrderState. Defaults match
  // PosOrder.fromDoc for old documents with missing status values.
  DateTime? date(String key) {
    final value = data[key];
    if (value is Timestamp) return value.toDate();
    return value is DateTime ? value : null;
  }

  final order = PosOrder(
    id: '',
    tableId: '',
    tableName: '',
    status: data['status'] as String? ?? 'open',
    kitchenStatus: data['kitchenStatus'] as String? ?? 'pending',
    paymentStatus: data['paymentStatus'] as String? ?? 'pending',
    total: 0,
    paidTotal: 0,
    pendingTotal: (data['pendingTotal'] as num?)?.toDouble() ?? 0,
    personNames: const {},
    orderType: 'dine_in',
    paidAt: date('paidAt'),
    cancelledAt: date('cancelledAt'),
    canceledAt: date('canceledAt'),
    closedAt: date('closedAt'),
  );
  final rawBranch = data['branchId'];
  final branch = rawBranch is String && rawBranch.trim().isNotEmpty
      ? rawBranch.trim()
      : defaultBranchId;
  return {
    'operationalActive': isActiveOrderState(order),
    'effectiveBranchId': branch,
  };
}
