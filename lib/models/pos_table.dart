import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';

class PosTable {
  const PosTable({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.active,
    required this.sortOrder,
    this.currentOrderId,
    this.branchId = AppConstants.defaultBranchId,
    this.branchName = AppConstants.defaultBranchName,
  });

  final String id;
  final String name;
  final String type;
  final String status;
  final bool active;
  final int sortOrder;
  final String? currentOrderId;
  final String branchId;
  final String branchName;

  factory PosTable.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return PosTable(
      id: doc.id,
      name: data['name'] as String? ?? doc.id,
      type: data['type'] as String? ?? 'table',
      status: data['status'] as String? ?? 'available',
      active: data['active'] as bool? ?? true,
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
      currentOrderId: data['currentOrderId'] as String?,
      branchId: data['branchId'] as String? ?? AppConstants.defaultBranchId,
      branchName:
          data['branchName'] as String? ?? AppConstants.defaultBranchName,
    );
  }
}
