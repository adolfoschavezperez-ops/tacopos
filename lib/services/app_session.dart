import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import 'live_presence_service.dart';

class AppSession extends ChangeNotifier {
  AppSession._();

  static final AppSession instance = AppSession._();

  Employee? _employee;
  Employee? _baseEmployee;
  List<Branch> _accessibleBranches = const [];
  Branch _selectedBranch = Branch.defaultBranch;

  Employee? get employee => _employee;
  bool get isLoggedIn => _employee != null;
  List<Branch> get accessibleBranches => _accessibleBranches;
  Branch get selectedBranch => _selectedBranch;
  String get currentRestaurantId => _selectedBranch.restaurantId;
  String get currentRestaurantName => _selectedBranch.restaurantName;
  String get currentBranchId => _selectedBranch.id;
  String get currentBranchName => _selectedBranch.name;
  bool get canChangeBranch => _accessibleBranches.length > 1;

  void signIn(Employee employee, {List<Branch> branches = const []}) {
    _accessibleBranches = branches.isEmpty
        ? const [Branch.defaultBranch]
        : branches;
    _selectedBranch = _resolveInitialBranch(employee, _accessibleBranches);
    _baseEmployee = employee;
    _employee = employee.withBranchPermissions(_selectedBranch.id);
    LivePresenceService.instance.start(_employee!, _selectedBranch);
    notifyListeners();
  }

  void selectBranch(Branch branch) {
    if (_selectedBranch.id == branch.id &&
        _selectedBranch.restaurantId == branch.restaurantId) {
      return;
    }
    _selectedBranch = branch;
    final baseEmployee = _baseEmployee;
    if (baseEmployee != null) {
      _employee = baseEmployee.withBranchPermissions(branch.id);
    }
    LivePresenceService.instance.updateBranch(branch);
    notifyListeners();
  }

  void signOut() {
    LivePresenceService.instance.stop();
    _employee = null;
    _baseEmployee = null;
    _accessibleBranches = const [];
    _selectedBranch = Branch.defaultBranch;
    notifyListeners();
  }

  Branch _resolveInitialBranch(Employee employee, List<Branch> branches) {
    final defaultBranchId = employee.defaultBranchId?.trim();
    if (defaultBranchId != null && defaultBranchId.isNotEmpty) {
      for (final branch in branches) {
        if (branch.id == defaultBranchId) {
          return branch;
        }
      }
    }
    final fallback = branches.isEmpty ? Branch.defaultBranch : branches.first;
    return Branch(
      id: fallback.id.isEmpty ? AppConstants.defaultBranchId : fallback.id,
      restaurantId: fallback.restaurantId.isEmpty
          ? AppConstants.restaurantId
          : fallback.restaurantId,
      restaurantName: fallback.restaurantName.isEmpty
          ? AppConstants.restaurantName
          : fallback.restaurantName,
      name: fallback.name.isEmpty
          ? AppConstants.defaultBranchName
          : fallback.name,
      normalizedName: fallback.normalizedName.isEmpty
          ? AppConstants.defaultBranchId
          : fallback.normalizedName,
      active: fallback.active,
      sortOrder: fallback.sortOrder,
      address: fallback.address,
      phone: fallback.phone,
      timezone: fallback.timezone,
      createdAt: fallback.createdAt,
      updatedAt: fallback.updatedAt,
    );
  }
}
