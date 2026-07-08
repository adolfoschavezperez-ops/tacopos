import 'package:cloud_firestore/cloud_firestore.dart';

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
    );
  }
}
