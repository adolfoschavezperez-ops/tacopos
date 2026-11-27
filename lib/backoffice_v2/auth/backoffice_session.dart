import 'package:flutter/material.dart';

import '../../models/branch.dart';
import '../../models/employee.dart';
import '../core/env/backoffice_env.dart';
import 'backoffice_permissions.dart';

class BackofficeSession extends ChangeNotifier {
  BackofficeSession({required this.config})
    : _restaurantId = config.defaultRestaurantId;

  final BackofficeConfig config;

  Employee? _employee;
  bool _isSuperAdmin = false;
  String _restaurantId;
  String _restaurantName = 'TacoPOS';
  List<Branch> _branches = const [];
  String? _selectedBranchId; // null => Todas las sucursales
  ThemeMode _themeMode = ThemeMode.light;
  String? _sessionNotice;

  Employee? get employee => _employee;
  bool get isSuperAdmin => _isSuperAdmin;
  bool get isAuthenticated => _employee != null;
  BackofficePermissions get permissions =>
      BackofficePermissions(employee: _employee, isSuperAdmin: _isSuperAdmin);
  String get restaurantId => _restaurantId;
  String get restaurantName => _restaurantName;
  List<Branch> get branches => _branches;
  String? get selectedBranchId => _selectedBranchId;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  String? get sessionNotice => _sessionNotice;

  Branch? get selectedBranch {
    final id = _selectedBranchId;
    if (id == null) return null;
    for (final b in _branches) {
      if (b.id == id) return b;
    }
    return null;
  }

  String get selectedBranchLabel =>
      selectedBranch?.name ?? 'Todas las sucursales';

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }

  void toggleThemeMode() {
    setThemeMode(
      _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }

  String? consumeNotice() {
    final notice = _sessionNotice;
    _sessionNotice = null;
    return notice;
  }

  void signIn({
    required Employee employee,
    bool isSuperAdmin = false,
    required String restaurantId,
    required String restaurantName,
    required List<Branch> branches,
    String? initialBranchId,
  }) {
    _employee = employee;
    _isSuperAdmin = isSuperAdmin;
    _restaurantId = restaurantId;
    _restaurantName = restaurantName;
    _branches = List.unmodifiable(branches);
    _selectedBranchId = initialBranchId;
    _sessionNotice = null;
    notifyListeners();
  }

  void selectBranch(String? branchId) {
    if (_selectedBranchId == branchId) return;
    _selectedBranchId = branchId;
    notifyListeners();
  }

  void signOut({String? notice}) {
    _employee = null;
    _isSuperAdmin = false;
    _branches = const [];
    _selectedBranchId = null;
    _sessionNotice = notice;
    notifyListeners();
  }
}
