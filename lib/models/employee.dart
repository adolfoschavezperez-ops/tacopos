import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';

class Employee {
  const Employee({
    required this.id,
    required this.name,
    required this.active,
    required this.pin,
    required this.canTakeOrders,
    required this.canCharge,
    required this.canViewKitchen,
    required this.canViewAdmin,
    required this.canManageProducts,
    required this.canManageTables,
    required this.canManagePlatforms,
    required this.canManageEmployees,
    required this.canManageCash,
    required this.canAuthorizeCashWithdrawals,
    required this.canOpenKitchen,
    required this.canCloseKitchen,
    required this.canViewKitchenReports,
    required this.canManageKitchenStock,
    required this.canCancelOrders,
    required this.canCancelPayments,
    required this.canCancelItems,
    required this.canApproveKitchenCancellations,
    required this.canViewLiveOperations,
    required this.canControlLiveOperations,
    this.isSuperAdmin = false,
    this.defaultRestaurantId,
    this.defaultBranchId,
    this.restaurantAccess = const [],
    this.branchAccess = const [],
  });

  final String id;
  final String name;
  final bool active;
  final String pin;
  final bool canTakeOrders;
  final bool canCharge;
  final bool canViewKitchen;
  final bool canViewAdmin;
  final bool canManageProducts;
  final bool canManageTables;
  final bool canManagePlatforms;
  final bool canManageEmployees;
  final bool canManageCash;
  final bool canAuthorizeCashWithdrawals;
  final bool canOpenKitchen;
  final bool canCloseKitchen;
  final bool canViewKitchenReports;
  final bool canManageKitchenStock;
  final bool canCancelOrders;
  final bool canCancelPayments;
  final bool canCancelItems;
  final bool canApproveKitchenCancellations;
  final bool canViewLiveOperations;
  final bool canControlLiveOperations;
  final bool isSuperAdmin;
  final String? defaultRestaurantId;
  final String? defaultBranchId;
  final List<String> restaurantAccess;
  final List<EmployeeBranchAccess> branchAccess;

  List<EmployeeBranchAccess> get effectiveBranchAccess {
    if (branchAccess.isNotEmpty) {
      return branchAccess.where((access) => access.active).toList();
    }
    return [
      EmployeeBranchAccess(
        restaurantId: defaultRestaurantId ?? AppConstants.restaurantId,
        branchId: defaultBranchId ?? AppConstants.defaultBranchId,
        branchName: AppConstants.defaultBranchName,
        active: true,
        permissions: currentPermissionsMap,
      ),
    ];
  }

  Map<String, bool> get currentPermissionsMap => {
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
    'canManageKitchenStock': canManageKitchenStock,
    'canCancelOrders': canCancelOrders,
    'canCancelPayments': canCancelPayments,
    'canCancelItems': canCancelItems,
    'canApproveKitchenCancellations': canApproveKitchenCancellations,
    'canViewLiveOperations': canViewLiveOperations,
    'canControlLiveOperations': canControlLiveOperations,
  };

  Employee withBranchPermissions(String branchId) {
    final access = effectiveBranchAccess.where(
      (item) => item.active && item.branchId == branchId,
    );
    if (isSuperAdmin || access.isEmpty || access.first.permissions.isEmpty) {
      return this;
    }
    final permissions = access.first.permissions;
    bool read(String key, bool fallback) => permissions[key] ?? fallback;
    return Employee(
      id: id,
      name: name,
      active: active,
      pin: pin,
      canTakeOrders: read('canTakeOrders', canTakeOrders),
      canCharge: read('canCharge', canCharge),
      canViewKitchen: read('canViewKitchen', canViewKitchen),
      canViewAdmin: read('canViewAdmin', canViewAdmin),
      canManageProducts: read('canManageProducts', canManageProducts),
      canManageTables: read('canManageTables', canManageTables),
      canManagePlatforms: read('canManagePlatforms', canManagePlatforms),
      canManageEmployees: read('canManageEmployees', canManageEmployees),
      canManageCash: read('canManageCash', canManageCash),
      canAuthorizeCashWithdrawals: read(
        'canAuthorizeCashWithdrawals',
        canAuthorizeCashWithdrawals,
      ),
      canOpenKitchen: read('canOpenKitchen', canOpenKitchen),
      canCloseKitchen: read('canCloseKitchen', canCloseKitchen),
      canViewKitchenReports: read(
        'canViewKitchenReports',
        canViewKitchenReports,
      ),
      canManageKitchenStock: read(
        'canManageKitchenStock',
        canManageKitchenStock,
      ),
      canCancelOrders: read('canCancelOrders', canCancelOrders),
      canCancelPayments: read('canCancelPayments', canCancelPayments),
      canCancelItems: read('canCancelItems', canCancelItems),
      canApproveKitchenCancellations: read(
        'canApproveKitchenCancellations',
        canApproveKitchenCancellations,
      ),
      canViewLiveOperations: read(
        'canViewLiveOperations',
        canViewLiveOperations,
      ),
      canControlLiveOperations: read(
        'canControlLiveOperations',
        canControlLiveOperations,
      ),
      isSuperAdmin: isSuperAdmin,
      defaultRestaurantId: defaultRestaurantId,
      defaultBranchId: defaultBranchId,
      restaurantAccess: restaurantAccess,
      branchAccess: branchAccess,
    );
  }

  factory Employee.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return Employee(
      id: doc.id,
      name: data['name'] as String? ?? doc.id,
      active: data['active'] as bool? ?? true,
      pin: data['pin'] as String? ?? '',
      canTakeOrders: data['canTakeOrders'] as bool? ?? false,
      canCharge: data['canCharge'] as bool? ?? false,
      canViewKitchen: data['canViewKitchen'] as bool? ?? false,
      canViewAdmin: data['canViewAdmin'] as bool? ?? false,
      canManageProducts: data['canManageProducts'] as bool? ?? false,
      canManageTables: data['canManageTables'] as bool? ?? false,
      canManagePlatforms: data['canManagePlatforms'] as bool? ?? false,
      canManageEmployees: data['canManageEmployees'] as bool? ?? false,
      canManageCash: data['canManageCash'] as bool? ?? false,
      canAuthorizeCashWithdrawals:
          data['canAuthorizeCashWithdrawals'] as bool? ?? false,
      canOpenKitchen: data['canOpenKitchen'] as bool? ?? false,
      canCloseKitchen: data['canCloseKitchen'] as bool? ?? false,
      canViewKitchenReports: data['canViewKitchenReports'] as bool? ?? false,
      canManageKitchenStock: data['canManageKitchenStock'] as bool? ?? false,
      canCancelOrders:
          data['canCancelOrders'] as bool? ??
          data['canViewAdmin'] as bool? ??
          false,
      canCancelPayments:
          data['canCancelPayments'] as bool? ??
          data['canViewAdmin'] as bool? ??
          false,
      canCancelItems:
          data['canCancelItems'] as bool? ??
          data['canCancelOrders'] as bool? ??
          data['canViewAdmin'] as bool? ??
          false,
      canApproveKitchenCancellations:
          data['canApproveKitchenCancellations'] as bool? ??
          data['canViewKitchen'] as bool? ??
          data['canViewAdmin'] as bool? ??
          false,
      canViewLiveOperations:
          data['canViewLiveOperations'] as bool? ??
          data['canViewAdmin'] as bool? ??
          false,
      canControlLiveOperations:
          data['canControlLiveOperations'] as bool? ??
          data['canViewAdmin'] as bool? ??
          false,
      isSuperAdmin:
          data['isSuperAdmin'] as bool? ??
          data['canViewAdmin'] as bool? ??
          false,
      defaultRestaurantId: data['defaultRestaurantId'] as String?,
      defaultBranchId: data['defaultBranchId'] as String?,
      restaurantAccess: _readStringList(data['restaurantAccess']),
      branchAccess: _readBranchAccess(data['branchAccess']),
    );
  }

  static List<String> _readStringList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static List<EmployeeBranchAccess> _readBranchAccess(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => EmployeeBranchAccess.fromMap(item))
        .where((item) => item.branchId.trim().isNotEmpty)
        .toList();
  }
}

class EmployeeBranchAccess {
  const EmployeeBranchAccess({
    required this.restaurantId,
    required this.branchId,
    required this.branchName,
    required this.active,
    this.permissions = const {},
  });

  final String restaurantId;
  final String branchId;
  final String branchName;
  final bool active;
  final Map<String, bool> permissions;

  factory EmployeeBranchAccess.fromMap(Map<Object?, Object?> data) {
    return EmployeeBranchAccess(
      restaurantId: data['restaurantId']?.toString().trim().isNotEmpty == true
          ? data['restaurantId'].toString()
          : AppConstants.restaurantId,
      branchId: data['branchId']?.toString() ?? '',
      branchName: data['branchName']?.toString() ?? '',
      active: data['active'] as bool? ?? true,
      permissions: _readPermissions(data['permissions']),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'restaurantId': restaurantId,
      'branchId': branchId,
      'branchName': branchName,
      'active': active,
      'permissions': permissions,
    };
  }

  static Map<String, bool> _readPermissions(Object? value) {
    if (value is! Map) return const {};
    return value.map(
      (key, value) => MapEntry(key.toString(), value as bool? ?? false),
    );
  }
}
