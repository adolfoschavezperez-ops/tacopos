import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/activity_event.dart';
import '../../../models/branch.dart';
import '../../../models/employee.dart';
import '../../../models/order.dart';
import '../../core/adapters/sales_adapter.dart';
import '../../core/read_only_guard.dart';

class DeviceSummaryRow {
  const DeviceSummaryRow({
    required this.deviceId,
    required this.deviceName,
    required this.branchName,
    required this.role,
    required this.platform,
    required this.appVersionName,
    required this.appVersionCode,
    required this.employeeId,
    required this.employeeName,
    required this.updateStatus,
    required this.active,
    required this.lastSeenAt,
  });

  final String deviceId;
  final String deviceName;
  final String branchName;
  final String role;
  final String platform;
  final String appVersionName;
  final int appVersionCode;
  final String employeeId;
  final String employeeName;
  final String updateStatus;
  final bool active;
  final DateTime? lastSeenAt;

  factory DeviceSummaryRow.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final ts = d['lastSeenAt'];
    return DeviceSummaryRow(
      deviceId: (d['deviceId'] ?? doc.id).toString(),
      deviceName: (d['deviceName'] ?? doc.id).toString(),
      branchName: (d['branchName'] ?? '').toString(),
      role: (d['role'] ?? 'unknown').toString(),
      platform: (d['platform'] ?? '').toString(),
      appVersionName: (d['appVersionName'] ?? '').toString(),
      appVersionCode: (d['appVersionCode'] as num?)?.toInt() ?? 0,
      employeeId: (d['employeeId'] ?? '').toString(),
      employeeName: (d['employeeName'] ?? '').toString(),
      updateStatus: (d['updateStatus'] ?? 'unknown').toString(),
      active: d['active'] as bool? ?? true,
      lastSeenAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class EmployeeDiscountUsageRow {
  const EmployeeDiscountUsageRow({
    required this.id,
    required this.businessDate,
    required this.discountType,
    required this.discountName,
    required this.discountAmount,
    required this.totalAfterDiscount,
    required this.orderId,
  });

  final String id;
  final String businessDate;
  final String discountType;
  final String discountName;
  final double discountAmount;
  final double totalAfterDiscount;
  final String? orderId;

  factory EmployeeDiscountUsageRow.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return EmployeeDiscountUsageRow(
      id: doc.id,
      businessDate: (d['businessDate'] ?? '').toString(),
      discountType: (d['discountType'] ?? '').toString(),
      discountName: (d['discountName'] ?? '').toString(),
      discountAmount: (d['discountAmount'] as num?)?.toDouble() ?? 0.0,
      totalAfterDiscount: (d['totalAfterDiscount'] as num?)?.toDouble() ?? 0.0,
      orderId: d['orderId'] as String?,
    );
  }
}

class EmployeeProfileBundle {
  const EmployeeProfileBundle({
    required this.employee,
    required this.recentEvents,
    required this.devices,
    required this.discountUsages,
    required this.ordersCount,
    required this.salesTotal,
  });

  final Employee employee;
  final List<ActivityEvent> recentEvents;
  final List<DeviceSummaryRow> devices;
  final List<EmployeeDiscountUsageRow> discountUsages;
  final int ordersCount;
  final double salesTotal;
}

class EmployeesDashboardData {
  const EmployeesDashboardData({
    required this.employees,
    required this.devices,
    required this.readCount,
  });

  final List<Employee> employees;
  final List<DeviceSummaryRow> devices;
  final int readCount;
}

class EmployeesRestrictedException implements Exception {
  const EmployeesRestrictedException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Secure repository for Employee & Permissions administration.
///
/// Security guarantees:
/// - Never displays or pre-fills existing plaintext PINs.
/// - Never writes plaintext PINs from Backoffice 2.0.
/// - Prevents self-privilege-escalation and granting permissions above actor's.
/// - Preserves existing roles/privileges when editing only non-privilege fields.
/// - Logs all administrative modifications in `activityLog`.
class EmployeesRepository {
  EmployeesRepository({
    FirebaseFirestore? firestore,
    this.isReadOnly = false,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final bool isReadOnly;

  Future<EmployeesDashboardData> loadEmployees({
    required String restaurantId,
  }) async {
    final restRef = _db.collection('restaurants').doc(restaurantId);
    try {
      final snaps = await Future.wait([
        restRef.collection('employees').limit(200).get(),
        restRef.collection('devices').limit(100).get(),
      ]);
      final employees = snaps[0].docs.map(Employee.fromDoc).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final devices = snaps[1].docs
          .map(DeviceSummaryRow.fromDoc)
          .toList(growable: false);

      return EmployeesDashboardData(
        employees: employees,
        devices: devices,
        readCount: snaps[0].docs.length + snaps[1].docs.length,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const EmployeesRestrictedException(
          'Lectura del catálogo de empleados restringida temporalmente en DEV '
          'por contención de seguridad (P0-4: documentos con PIN heredado). '
          'Pendiente de proyección pública sin credenciales en coordinación con Android.',
        );
      }
      rethrow;
    }
  }

  Future<EmployeeProfileBundle> loadEmployeeProfile({
    required String restaurantId,
    required Employee employee,
    required List<DeviceSummaryRow> allDevices,
  }) async {
    final restRef = _db.collection('restaurants').doc(restaurantId);
    final now = DateTime.now();
    final startStr = BackofficeSalesAdapter.formatBusinessDate(
      now.subtract(const Duration(days: 29)),
    );
    final endStr = BackofficeSalesAdapter.formatBusinessDate(now);

    final snaps = await Future.wait([
      restRef
          .collection('activityLog')
          .orderBy('createdAt', descending: true)
          .limit(150)
          .get(),
      restRef
          .collection('orders')
          .where('businessDate', isGreaterThanOrEqualTo: startStr)
          .where('businessDate', isLessThanOrEqualTo: endStr)
          .limit(300)
          .get(),
      restRef
          .collection('discountUsage')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get(),
    ]);

    final empNameLower = employee.name.trim().toLowerCase();
    final events = snaps[0].docs
        .map(ActivityEvent.fromDoc)
        .where(
          (e) => e.employeeName.trim().toLowerCase() == empNameLower,
        )
        .take(30)
        .toList(growable: false);

    final empOrders = snaps[1].docs.map(PosOrder.fromDoc).where((o) {
      final isCancelled = o.status.trim().toLowerCase() == 'cancelled';
      if (isCancelled) return false;
      return o.discountAppliedByEmployeeId == employee.id ||
          o.discountBeneficiaryEmployeeId == employee.id ||
          o.discountAuthorizedByEmployeeId == employee.id;
    }).toList(growable: false);

    final usages = snaps[2].docs
        .where((d) {
          final data = d.data();
          final linkedId = (data['linkedEmployeeId'] ?? '').toString();
          final empName = (data['employeeName'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          return linkedId == employee.id || empName == empNameLower;
        })
        .map(EmployeeDiscountUsageRow.fromDoc)
        .toList(growable: false);

    final devices = allDevices
        .where(
          (d) =>
              d.employeeId == employee.id ||
              d.employeeName.trim().toLowerCase() == empNameLower,
        )
        .toList(growable: false);

    return EmployeeProfileBundle(
      employee: employee,
      recentEvents: events,
      devices: devices,
      discountUsages: usages,
      ordersCount: empOrders.length,
      salesTotal: empOrders.fold<double>(0.0, (a, o) => a + o.total),
    );
  }

  /// Creates or updates an employee's profile, branch access, and permissions.
  ///
  /// NEVER writes or exposes plaintext PINs, enforces least privilege,
  /// blocks self-escalation, and never overwrites roles when editing only name.
  Future<void> saveEmployee({
    required String restaurantId,
    required String? existingEmployeeId,
    Employee? existingEmployee,
    required String name,
    required bool active,
    required bool isSuperAdmin,
    required Map<String, bool> permissions,
    required List<Branch> assignedBranches,
    required String actorEmployeeId,
    required String actorEmployeeName,
    required bool actorIsSuperAdmin,
    Map<String, bool> actorPermissions = const {},
  }) async {
    BackofficeReadOnlyGuard.assertWritable(
      isReadOnly: isReadOnly,
      action: 'Guardar empleado',
    );
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError('El nombre del empleado es obligatorio.');
    }
    final isNew = existingEmployeeId == null || existingEmployeeId.trim().isEmpty;
    final isSelfEdit =
        !isNew && existingEmployeeId.trim() == actorEmployeeId.trim();

    if (!isNew && !actorIsSuperAdmin && (existingEmployee?.isSuperAdmin ?? false)) {
      throw StateError(
        'Solo un Super Administrador puede modificar la cuenta de otro Super Administrador.',
      );
    }
    if (!actorIsSuperAdmin && isSuperAdmin) {
      throw StateError('No tienes autorización para asignar rol de Super Administrador.');
    }

    final restRef = _db.collection('restaurants').doc(restaurantId);
    final col = restRef.collection('employees');
    final ref = isNew ? col.doc() : col.doc(existingEmployeeId.trim());

    final payload = <String, dynamic>{
      'name': cleanName,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmployeeId': actorEmployeeId,
      'updatedByEmployeeName': actorEmployeeName,
    };

    if (isSelfEdit) {
      // Self-edit: strictly update display name only; never overwrite roles, permissions, active, or branches.
    } else if (isNew) {
      if (!actorIsSuperAdmin) {
        for (final entry in permissions.entries) {
          if (entry.value && actorPermissions[entry.key] != true) {
            throw StateError(
              'No puedes asignar el permiso ${entry.key} porque no lo posees.',
            );
          }
        }
      }
      final branchAccessList = assignedBranches
          .map(
            (b) => {
              'restaurantId': restaurantId,
              'branchId': b.id,
              'branchName': b.name,
              'active': true,
              'permissions': permissions,
            },
          )
          .toList(growable: false);
      payload.addAll({
        'id': ref.id,
        'restaurantId': restaurantId,
        'active': active,
        'isSuperAdmin': actorIsSuperAdmin ? isSuperAdmin : false,
        ...permissions,
        'restaurantAccess': [restaurantId],
        'branchAccess': branchAccessList,
        if (assignedBranches.isNotEmpty) ...{
          'defaultRestaurantId': restaurantId,
          'defaultBranchId': assignedBranches.first.id,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Updating another existing employee: only include changed privilege/branch fields
      final prevPerms = existingEmployee?.currentPermissionsMap ?? const <String, bool>{};
      final changedPerms = <String, bool>{};
      for (final entry in permissions.entries) {
        if (existingEmployee == null || prevPerms[entry.key] != entry.value) {
          if (!actorIsSuperAdmin && actorPermissions[entry.key] != true) {
            throw StateError(
              'No puedes modificar el permiso ${entry.key} porque excede tus privilegios.',
            );
          }
          changedPerms[entry.key] = entry.value;
        }
      }
      if (existingEmployee == null || existingEmployee.active != active) {
        payload['active'] = active;
      }
      if (actorIsSuperAdmin &&
          (existingEmployee == null ||
              existingEmployee.isSuperAdmin != isSuperAdmin)) {
        payload['isSuperAdmin'] = isSuperAdmin;
      }
      payload.addAll(changedPerms);

      final prevBranchIds =
          existingEmployee?.branchAccess.map((b) => b.branchId).toSet() ?? const <String>{};
      final nextBranchIds = assignedBranches.map((b) => b.id).toSet();
      if (existingEmployee == null ||
          prevBranchIds.length != nextBranchIds.length ||
          !prevBranchIds.containsAll(nextBranchIds)) {
        payload['branchAccess'] = assignedBranches
            .map(
              (b) => {
                'restaurantId': restaurantId,
                'branchId': b.id,
                'branchName': b.name,
                'active': true,
                'permissions': permissions,
              },
            )
            .toList(growable: false);
        if (assignedBranches.isNotEmpty) {
          payload['defaultRestaurantId'] = restaurantId;
          payload['defaultBranchId'] = assignedBranches.first.id;
        }
      }
    }

    final batch = _db.batch();
    batch.set(ref, payload, SetOptions(merge: true));
    batch.set(restRef.collection('activityLog').doc(), {
      'type': isNew ? 'employee_created' : 'employee_updated',
      'restaurantId': restaurantId,
      'targetId': ref.id,
      'note': 'Empleado: $cleanName · Activo: $active',
      'employeeId': actorEmployeeId,
      'employeeName': actorEmployeeName,
      'actionSource': 'backoffice_v2',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> toggleEmployeeActive({
    required String restaurantId,
    required Employee employee,
    required String actorEmployeeId,
    required String actorEmployeeName,
  }) async {
    BackofficeReadOnlyGuard.assertWritable(
      isReadOnly: isReadOnly,
      action: 'Cambiar estado de empleado',
    );
    if (employee.id == actorEmployeeId) {
      throw StateError('No puedes desactivar tu propia cuenta.');
    }
    final nextActive = !employee.active;
    final restRef = _db.collection('restaurants').doc(restaurantId);
    final batch = _db.batch();
    batch.update(restRef.collection('employees').doc(employee.id), {
      'active': nextActive,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmployeeId': actorEmployeeId,
      'updatedByEmployeeName': actorEmployeeName,
    });
    batch.set(restRef.collection('activityLog').doc(), {
      'type': nextActive ? 'employee_activated' : 'employee_deactivated',
      'restaurantId': restaurantId,
      'targetId': employee.id,
      'note': 'Empleado: ${employee.name}',
      'employeeId': actorEmployeeId,
      'employeeName': actorEmployeeName,
      'actionSource': 'backoffice_v2',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
