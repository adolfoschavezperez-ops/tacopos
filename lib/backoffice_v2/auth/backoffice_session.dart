import 'package:flutter/material.dart';

import '../../models/branch.dart';
import '../../models/employee.dart';
import '../core/env/backoffice_env.dart';

class BackofficeSession extends ChangeNotifier {
  BackofficeSession({required this.config})
    : _restaurantId = config.defaultRestaurantId;

  final BackofficeConfig config;

  Employee? _employee;
  String _restaurantId;
  String _restaurantName = 'TacoPOS SaaS';
  List<Branch> _branches = const [];
  String? _selectedBranchId; // null => Todas las sucursales
  ThemeMode _themeMode = ThemeMode.light;

  Employee? get employee => _employee;
  bool get isAuthenticated => _employee != null;
  String get restaurantId => _restaurantId;
  String get restaurantName => _restaurantName;
  List<Branch> get branches => _branches;
  String? get selectedBranchId => _selectedBranchId;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

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

  void signIn({
    required Employee employee,
    required String restaurantId,
    required String restaurantName,
    required List<Branch> branches,
    String? initialBranchId,
  }) {
    _employee = employee;
    _restaurantId = restaurantId;
    _restaurantName = restaurantName;
    _branches = List.unmodifiable(branches);
    _selectedBranchId = initialBranchId;
    notifyListeners();
  }

  void selectBranch(String? branchId) {
    if (_selectedBranchId == branchId) return;
    _selectedBranchId = branchId;
    notifyListeners();
  }

  void signOut() {
    _employee = null;
    _branches = const [];
    _selectedBranchId = null;
    notifyListeners();
  }
}
