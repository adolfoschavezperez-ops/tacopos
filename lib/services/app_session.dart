import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import 'live_presence_service.dart';
import 'operational_employee_session_store.dart';
import 'operational_diagnostics_service.dart';

class AppSession extends ChangeNotifier {
  AppSession._();

  static final AppSession instance = AppSession._();

  static OperationalEmployeeSessionStore _employeeSessionStore =
      SecureOperationalEmployeeSessionStore.instance;

  @visibleForTesting
  static bool disablePresenceForTesting = false;

  @visibleForTesting
  static set employeeSessionStoreForTesting(
    OperationalEmployeeSessionStore store,
  ) {
    _employeeSessionStore = store;
  }

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
  int get sessionRevision => _sessionRevision;

  int _sessionRevision = 0;

  void signIn(
    Employee employee, {
    List<Branch> branches = const [],
    Branch? initialBranch,
  }) {
    _sessionRevision++;
    _accessibleBranches = branches.isEmpty
        ? const [Branch.defaultBranch]
        : branches;
    _selectedBranch =
        initialBranch ?? _resolveInitialBranch(employee, _accessibleBranches);
    _baseEmployee = employee;
    _employee = employee.withBranchPermissions(_selectedBranch.id);
    OperationalDiagnosticsService.instance.record(
      'session',
      'employee_sign_in',
      employeeId: employee.id,
      branchId: _selectedBranch.id,
    );
    if (!disablePresenceForTesting) {
      LivePresenceService.instance.start(_employee!, _selectedBranch);
    }
    notifyListeners();
  }

  void selectBranch(Branch branch) {
    if (_selectedBranch.id == branch.id &&
        _selectedBranch.restaurantId == branch.restaurantId) {
      return;
    }
    _sessionRevision++;
    _selectedBranch = branch;
    final baseEmployee = _baseEmployee;
    if (baseEmployee != null) {
      _employee = baseEmployee.withBranchPermissions(branch.id);
    }
    if (!disablePresenceForTesting) {
      LivePresenceService.instance.updateBranch(branch);
    }
    OperationalDiagnosticsService.instance.record(
      'session',
      'branch_changed',
      employeeId: _employee?.id,
      branchId: branch.id,
    );
    notifyListeners();
  }

  void refreshEmployee(
    Employee employee, {
    required List<Branch> branches,
    required Branch selectedBranch,
  }) {
    if (_employee?.id != employee.id) return;
    _sessionRevision++;
    _accessibleBranches = branches;
    _selectedBranch = selectedBranch;
    _baseEmployee = employee;
    _employee = employee.withBranchPermissions(selectedBranch.id);
    notifyListeners();
  }

  Future<void> signOut({String reason = 'user_requested'}) async {
    _sessionRevision++;
    if (!kIsWeb) {
      try {
        await _employeeSessionStore.clear();
      } catch (error) {
        developer.log(
          'employee-session-clear-failed reason=$reason',
          name: 'AppSession',
          error: error.runtimeType.toString(),
        );
      }
    }
    developer.log('employee-session-ended reason=$reason', name: 'AppSession');
    OperationalDiagnosticsService.instance.record(
      'session',
      'employee_sign_out',
      result: reason,
      employeeId: _employee?.id,
      branchId: _selectedBranch.id,
    );
    if (!disablePresenceForTesting) {
      unawaited(
        LivePresenceService.instance.stop().catchError((Object error) {
          developer.log(
            'employee-session-presence-stop-failed reason=$reason',
            name: 'AppSession',
            error: error.runtimeType.toString(),
          );
        }),
      );
    }
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
