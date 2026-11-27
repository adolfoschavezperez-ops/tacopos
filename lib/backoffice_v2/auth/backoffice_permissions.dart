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
          employee!.canViewPurchaseReports ||
          employee!.canManageSuppliers ||
          employee!.canRegisterPurchases ||
          employee!.canPaySuppliers ||
          employee!.canViewAdmin);

  bool get canManageSuppliers =>
      isAuthenticated &&
      (isSuperAdmin || employee!.canManageSuppliers || employee!.canViewAdmin);

  bool get canRegisterPurchases =>
      isAuthenticated &&
      (isSuperAdmin || employee!.canRegisterPurchases || employee!.canViewAdmin);

  bool get canPaySuppliers =>
      isAuthenticated &&
      (isSuperAdmin || employee!.canPaySuppliers || employee!.canViewAdmin);

  bool get canCancelSupplierPayments =>
      isAuthenticated &&
      (isSuperAdmin ||
          employee!.canCancelSupplierPayments ||
          employee!.canViewAdmin);

  bool get canViewAccountsPayable =>
      isAuthenticated &&
      (isSuperAdmin ||
          employee!.canViewAccountsPayable ||
          employee!.canPaySuppliers ||
          employee!.canViewAdmin);

  bool get canViewInventory =>
      isAuthenticated &&
      (isSuperAdmin ||
          employee!.canViewKitchenReports ||
          employee!.canManageKitchenStock ||
          employee!.canViewAdmin);

  bool get canViewFinance =>
      isAuthenticated &&
      (isSuperAdmin ||
          employee!.canViewAdmin ||
          employee!.canViewPurchases ||
          employee!.canPaySuppliers ||
          employee!.canViewAccountsPayable ||
          employee!.canViewPurchaseReports);

  bool get canManageExpensePolicies =>
      isAuthenticated &&
      (isSuperAdmin ||
          employee!.canAuthorizeCashWithdrawals ||
          employee!.canViewAdmin);

  bool get canManagePartners =>
      isAuthenticated &&
      (isSuperAdmin ||
          employee!.canManageSuppliers ||
          employee!.canViewPurchases ||
          employee!.canViewAdmin);

  bool get canManageFinanceBudgets =>
      isAuthenticated &&
      (isSuperAdmin ||
          employee!.canManageSuppliers ||
          employee!.canViewAdmin);

  bool get canCreateHistoricalCashExpense =>
      isAuthenticated &&
      (isSuperAdmin || employee!.canManageCash || employee!.canViewAdmin);

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
