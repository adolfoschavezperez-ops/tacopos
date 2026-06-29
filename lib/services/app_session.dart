import 'package:flutter/foundation.dart';

import '../models/employee.dart';

class AppSession extends ChangeNotifier {
  AppSession._();

  static final AppSession instance = AppSession._();

  Employee? _employee;

  Employee? get employee => _employee;
  bool get isLoggedIn => _employee != null;

  void signIn(Employee employee) {
    _employee = employee;
    notifyListeners();
  }

  void signOut() {
    _employee = null;
    notifyListeners();
  }
}
