import '../../models/employee.dart';
import '../navigation/backoffice_route.dart';

/// Granular permission evaluator for TacoPOS Backoffice 2.0.
class BackofficePermissions {
  const BackofficePermissions({
    required this.employee,
    this.isSuperAdmin = false,
  });

  final Employee? employee;
  final bool isSuperAdmin;

  bool get isAuthenticated => employee != null && employee!.active;

  bool get canViewDashboard =>
      isAuthenticated && (isSuperAdmin || employee!.canViewAdmin);

  bool get canViewSales =>
      isAuthenticated && (isSuperAdmin || employee!.canViewAdmin);

  bool get canExportData =>
      isAuthenticated && (isSuperAdmin || employee!.canViewAdmin);

  bool get canCancelOrders =>
      isAuthenticated &&
      (isSuperAdmin || employee!.canCancelOrders || employee!.canViewAdmin);

  bool get canCancelPayments =>
      isAuthenticated &&
      (isSuperAdmin || employee!.canCancelPayments || employee!.canViewAdmin);

  bool get canManageCash =>
      isAuthenticated &&
      (isSuperAdmin ||
          employee!.canManageCash ||
          employee!.canAuthorizeCashWithdrawals ||
          employee!.canViewAdmin);

  bool get canViewAuthorizations =>
      isAuthenticated &&
      (isSuperAdmin ||
          employee!.canAuthorizeCashWithdrawals ||
          employee!.canViewAdmin);

  bool get canViewPurchases =>
      isAuthenticated &&
      (isSuperAdmin ||
          employee!.canViewPurchases ||
          employee!.canViewAccountsPayable ||
          employee!.canViewPurchaseReports);

  bool get canViewInventory =>
      isAuthenticated &&
      (isSuperAdmin ||
          employee!.canViewKitchenReports ||
          employee!.canManageKitchenStock ||
          employee!.canViewAdmin);

  bool get canViewFinance =>
      isAuthenticated && (isSuperAdmin || employee!.canViewAdmin);

  bool get canViewReports =>
      isAuthenticated &&
      (isSuperAdmin ||
          employee!.canViewAdmin ||
          employee!.canViewKitchenReports ||
          employee!.canViewPurchaseReports);

  bool get canManageEmployees =>
      isAuthenticated && (isSuperAdmin || employee!.canManageEmployees);

  bool get canViewAudit =>
      isAuthenticated && (isSuperAdmin || employee!.canViewAdmin);

  bool get canManageSettings =>
      isAuthenticated &&
      (isSuperAdmin ||
          employee!.canViewAdmin ||
          employee!.canManageProducts ||
          employee!.canManageTables ||
          employee!.canManagePlatforms);

  bool canViewSection(BackofficeSection section) {
    return switch (section) {
      BackofficeSection.dashboard => canViewDashboard,
      BackofficeSection.sales => canViewSales,
      BackofficeSection.cash => canManageCash,
      BackofficeSection.authorizations => canViewAuthorizations,
      BackofficeSection.purchases => canViewPurchases,
      BackofficeSection.inventory => canViewInventory,
      BackofficeSection.finance => canViewFinance,
      BackofficeSection.reports => canViewReports,
      BackofficeSection.employees => canManageEmployees,
      BackofficeSection.audit => canViewAudit,
      BackofficeSection.settings => canManageSettings,
    };
  }
}
