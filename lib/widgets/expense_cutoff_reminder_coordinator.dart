import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/expenses/expense_cutoff_reminder.dart';
import '../models/cash_session.dart';
import '../screens/cash/cash_session_screen.dart';
import '../services/app_session.dart';
import '../services/local_string_set_store.dart';
import '../services/taco_pos_repository.dart';

class ExpenseCutoffReminderCoordinator extends StatefulWidget {
  const ExpenseCutoffReminderCoordinator({required this.child, super.key});

  final Widget child;

  @override
  State<ExpenseCutoffReminderCoordinator> createState() =>
      _ExpenseCutoffReminderCoordinatorState();
}

class _ExpenseCutoffReminderCoordinatorState
    extends State<ExpenseCutoffReminderCoordinator>
    with WidgetsBindingObserver {
  final _repository = TacoPosRepository();
  final _store = const LocalStringSetStore(
    namespace: 'expense_cutoff_reminders',
  );
  Timer? _timer;
  bool _checking = false;
  bool _reminderVisible = false;
  bool _prefsReady = false;
  Set<String> _shownKeys = {};
  Set<String> _suppressedKeys = {};

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
      AppSession.instance.addListener(_checkSoon);
      _loadPrefs();
      _timer = Timer.periodic(const Duration(seconds: 60), (_) => _check());
      _checkSoon();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!kIsWeb) {
      AppSession.instance.removeListener(_checkSoon);
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSoon();
    }
  }

  Future<void> _loadPrefs() async {
    _shownKeys = await _store.readStringSet(_shownPrefsKey);
    _suppressedKeys = await _store.readStringSet(_suppressedPrefsKey);
    _prefsReady = true;
    await _check();
  }

  void _checkSoon() {
    unawaited(Future<void>.delayed(Duration.zero, _check));
  }

  Future<void> _check() async {
    if (!mounted || kIsWeb || _checking || _reminderVisible || !_prefsReady) {
      return;
    }
    final employee = AppSession.instance.employee;
    final hasCashPermission =
        employee?.canCharge == true || employee?.canManageCash == true;
    if (employee == null || !hasCashPermission) return;

    _checking = true;
    try {
      final settings = await _repository.getExpensePolicySettingsOnce();
      if (!settings.manualApprovalCutoffEnabled ||
          settings.manualApprovalCutoffTime.trim().isEmpty) {
        return;
      }
      final cashSession = await _repository.getOpenCashSession();
      if (cashSession == null) return;
      final decision = nextExpenseCutoffReminder(
        ExpenseCutoffReminderInput(
          restaurantId: AppSession.instance.currentRestaurantId,
          branchId: AppSession.instance.currentBranchId,
          employeeId: employee.id,
          businessDate: cashSession.businessDate,
          cutoffTime: settings.manualApprovalCutoffTime,
          now: DateTime.now(),
          cutoffEnabled: settings.manualApprovalCutoffEnabled,
          hasCashPermission: hasCashPermission,
          shownKeys: _shownKeys,
          suppressedKeys: _suppressedKeys,
        ),
      );
      if (decision == null || !mounted) return;
      await _showReminder(decision, cashSession);
    } finally {
      _checking = false;
    }
  }

  Future<void> _showReminder(
    ExpenseCutoffReminderDecision decision,
    CashSession cashSession,
  ) async {
    _reminderVisible = true;
    final action = await showDialog<_ExpenseReminderAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Horario de gastos por vencer'),
        content: Text(
          'Faltan ${decision.thresholdMinutes} minutos para que termine el '
          'horario de registro de gastos manuales '
          '(${_friendlyTime(decision.cutoffAt)}).',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _ExpenseReminderAction.ok),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _ExpenseReminderAction.openExpense,
            ),
            child: const Text('Levantar gasto'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _ExpenseReminderAction.suppressToday,
            ),
            child: const Text('No volverme a recordar'),
          ),
        ],
      ),
    );
    _reminderVisible = false;
    if (!mounted || action == null) return;
    await _markShown(decision.storageKey);
    if (action == _ExpenseReminderAction.suppressToday) {
      await _suppress(decision.storageKey);
      return;
    }
    if (action == _ExpenseReminderAction.openExpense) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await showWithdrawalRequestDialog(
        context,
        repository: _repository,
        session: cashSession,
      );
    }
  }

  Future<void> _markShown(String key) async {
    _shownKeys = {..._shownKeys, key};
    await _store.writeStringSet(_shownPrefsKey, _shownKeys);
  }

  Future<void> _suppress(String thresholdKey) async {
    final splitAt = thresholdKey.lastIndexOf('|');
    final baseKey = splitAt < 0
        ? thresholdKey
        : thresholdKey.substring(0, splitAt);
    _suppressedKeys = {..._suppressedKeys, baseKey};
    await _store.writeStringSet(_suppressedPrefsKey, _suppressedKeys);
  }

  String _friendlyTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour < 12 ? 'a. m.' : 'p. m.';
    return '$hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum _ExpenseReminderAction { ok, openExpense, suppressToday }

const _shownPrefsKey = 'expense_cutoff_reminder_shown_keys';
const _suppressedPrefsKey = 'expense_cutoff_reminder_suppressed_keys';
