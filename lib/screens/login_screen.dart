import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/backoffice/backoffice_version.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/brand_colors.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import '../services/app_session.dart';
import '../services/app_update_service.dart';
import '../services/backoffice_admin_auth_service.dart';
import '../services/operational_employee_session_service.dart';
import '../services/operational_diagnostics_service.dart';
import '../services/login_performance_trace.dart';
import '../services/taco_pos_repository.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_update_gate.dart';
import '../widgets/glass.dart';
import '../widgets/loading_panel.dart';
import 'home_screen.dart';

class LoginGate extends StatefulWidget {
  const LoginGate({super.key});

  @override
  State<LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends State<LoginGate> with WidgetsBindingObserver {
  Future<OperationalSessionRestoreResult>? _restoreFuture;
  Timer? _retryTimer;
  bool _showPinLogin = false;
  int _retrySeconds = 2;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
      _startRestore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (AppSession.instance.isLoggedIn) {
        unawaited(_revalidateSession());
      } else if (!_showPinLogin) {
        _startRestore();
      }
    }
  }

  void _startRestore() {
    _retryTimer?.cancel();
    setState(() {
      _restoreFuture = _restoreSession();
    });
  }

  Future<OperationalSessionRestoreResult> _restoreSession() async {
    final timer = LoginPerformanceTrace.start();
    final result = await LoginPerformanceTrace.measure(
      'employee_session_restore',
      OperationalEmployeeSessionService.instance.restore,
    );
    LoginPerformanceTrace.finish(
      'employee_session_restore_result',
      timer,
      result: result.status.name,
    );
    OperationalDiagnosticsService.instance.record(
      'session',
      'restore',
      result: result.status.name,
      duration: timer.elapsed,
    );
    return result;
  }

  Future<void> _revalidateSession() async {
    final timer = Stopwatch()..start();
    final result = await OperationalEmployeeSessionService.instance
        .revalidateCurrentSession();
    timer.stop();
    OperationalDiagnosticsService.instance.record(
      'session',
      'resume_revalidation',
      result: result.status.name,
      duration: timer.elapsed,
      employeeId: AppSession.instance.employee?.id,
      branchId: AppSession.instance.currentBranchId,
    );
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive == true) return;
    _retryTimer?.cancel();
    final delay = Duration(seconds: _retrySeconds);
    _retrySeconds = (_retrySeconds * 2).clamp(2, 60);
    _retryTimer = Timer(delay, () {
      if (mounted && !_showPinLogin && !AppSession.instance.isLoggedIn) {
        _startRestore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const BackofficePinLoginGate();
    }

    return FutureBuilder<OperationalSessionRestoreResult>(
      future: _restoreFuture,
      builder: (context, snapshot) {
        final restoreResult = snapshot.data;
        if (!_showPinLogin &&
            snapshot.connectionState != ConnectionState.done) {
          return const _SessionRestorePanel(
            title: 'Validando sesión',
            message: 'Comprobando empleado, sucursal y permisos vigentes.',
            busy: true,
          );
        }
        if (!_showPinLogin &&
            restoreResult?.status ==
                OperationalSessionRestoreStatus.waitingForValidation) {
          _scheduleRetry();
          return _SessionRestorePanel(
            title: 'Esperando validación segura',
            message:
                '${restoreResult?.message ?? 'Se conserva la sesión mientras vuelve la conexión.'}\n\n'
                'TacoPOS no habilitará operaciones hasta confirmar los permisos con el servidor.',
            onRetry: _startRestore,
            onUseAnotherEmployee: () => setState(() => _showPinLogin = true),
          );
        }

        final initialError =
            restoreResult?.status == OperationalSessionRestoreStatus.revoked
            ? restoreResult?.message ?? 'Vuelve a iniciar sesión.'
            : '';
        return AnimatedBuilder(
          animation: AppSession.instance,
          builder: (context, _) {
            return AppSession.instance.isLoggedIn
                ? const HomeScreen()
                : LoginScreen(initialError: initialError);
          },
        );
      },
    );
  }
}

class _SessionRestorePanel extends StatelessWidget {
  const _SessionRestorePanel({
    required this.title,
    required this.message,
    this.busy = false,
    this.onRetry,
    this.onUseAnotherEmployee,
  });

  final String title;
  final String message;
  final bool busy;
  final VoidCallback? onRetry;
  final VoidCallback? onUseAnotherEmployee;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PremiumBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy) const CircularProgressIndicator(),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFB8B8B8)),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                  if (onUseAnotherEmployee != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onUseAnotherEmployee,
                      child: const Text('Ingresar con otro empleado'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BackofficePinLoginGate extends StatefulWidget {
  const BackofficePinLoginGate({super.key});

  @override
  State<BackofficePinLoginGate> createState() => _BackofficePinLoginGateState();
}

class _BackofficePinLoginGateState extends State<BackofficePinLoginGate> {
  final _authService = BackofficeAdminAuthService();
  Future<void>? _sessionLoad;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null ||
            user.isAnonymous ||
            !_authService.hasExplicitOperatorSession) {
          unawaited(
            AppSession.instance.signOut(reason: 'backoffice_auth_missing'),
          );
          _sessionLoad = null;
          return LoginScreen(backofficeAuthService: _authService);
        }
        _sessionLoad ??= _authService.loadCurrentAdminSession();
        return FutureBuilder<void>(
          future: _sessionLoad,
          builder: (context, sessionSnapshot) {
            if (sessionSnapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: PremiumBackground(
                  child: Center(
                    child: LoadingPanel(message: 'Validando permisos...'),
                  ),
                ),
              );
            }
            if (sessionSnapshot.hasError) {
              return LoginScreen(
                backofficeAuthService: _authService,
                initialError: backofficeLoginErrorMessage(
                  sessionSnapshot.error,
                ),
              );
            }
            return const HomeScreen();
          },
        );
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.backofficeAuthService,
    this.initialError = '',
    this.backofficeUsersLoader,
    this.backofficePinLogin,
    this.forceBackofficeWebLogin,
  });

  final BackofficeAdminAuthService? backofficeAuthService;
  final String initialError;
  final Future<List<BackofficeLoginUser>> Function()? backofficeUsersLoader;
  final Future<void> Function({
    required String employeeId,
    required String pin,
  })?
  backofficePinLogin;
  final bool? forceBackofficeWebLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pinController = TextEditingController();
  final _pinFocusNode = FocusNode();
  late final TacoPosRepository _repository;
  BackofficeAdminAuthService? _backofficeAuthService;
  Stream<List<Employee>>? _employeesStream;
  Future<List<BackofficeLoginUser>>? _backofficeUsersFuture;
  BackofficeLoginUser? _selectedBackofficeUser;
  Employee? _selectedEmployee;
  bool _busy = false;
  String _error = '';

  bool get _isBackofficeWebLogin => widget.forceBackofficeWebLogin ?? kIsWeb;

  @override
  void initState() {
    super.initState();
    _backofficeAuthService = widget.backofficeAuthService;
    _error = widget.initialError;
    if (_isBackofficeWebLogin) {
      _backofficeUsersFuture = _loadBackofficeUsers();
    } else {
      _repository = TacoPosRepository();
      final employeeStreamTimer = LoginPerformanceTrace.start();
      var firstEmployeeSnapshot = true;
      _employeesStream = _repository.watchEmployees().map((employees) {
        if (firstEmployeeSnapshot) {
          firstEmployeeSnapshot = false;
          LoginPerformanceTrace.finish(
            'employee_list_first_snapshot',
            employeeStreamTimer,
            result: 'received',
          );
        }
        return employees;
      });
      unawaited(
        LoginPerformanceTrace.measure(
          'ensure_default_branch_screen_init',
          _repository.ensureDefaultBranch,
        ),
      );
      unawaited(
        LoginPerformanceTrace.measure(
          'ensure_initial_admin_employee',
          _repository.ensureInitialAdminEmployee,
        ),
      );
      LoginPerformanceTrace.mark('pin_login_screen_created');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        LoginPerformanceTrace.mark('pin_login_screen_first_frame');
      });
    }
  }

  @override
  void didUpdateWidget(covariant LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialError != oldWidget.initialError) {
      _error = widget.initialError;
    }
  }

  @override
  void dispose() {
    _pinFocusNode.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<List<BackofficeLoginUser>> _loadBackofficeUsers() {
    final loader = widget.backofficeUsersLoader;
    if (loader != null) {
      return loader();
    }
    final authService = _backofficeAuthService ??= BackofficeAdminAuthService();
    return authService.listBackofficeUsers();
  }

  void _retryBackofficeUsers() {
    setState(() {
      _selectedBackofficeUser = null;
      _error = '';
      _backofficeUsersFuture = _loadBackofficeUsers();
    });
  }

  Future<void> _login() async {
    if (_isBackofficeWebLogin) {
      final selectedUser = _selectedBackofficeUser;
      if (selectedUser == null) {
        setState(() {
          _error = 'Selecciona un usuario.';
        });
        return;
      }
      final pin = _pinController.text.trim();
      if (pin.isEmpty) {
        setState(() {
          _error = 'Ingresa tu PIN.';
        });
        return;
      }

      setState(() {
        _busy = true;
        _error = '';
      });

      try {
        final pinLogin = widget.backofficePinLogin;
        if (pinLogin != null) {
          await pinLogin(employeeId: selectedUser.id, pin: pin);
        } else {
          final authService = _backofficeAuthService ??=
              BackofficeAdminAuthService();
          await authService.signInWithPin(
            employeeId: selectedUser.id,
            pin: pin,
          );
        }
      } catch (error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _busy = false;
          _error = backofficeLoginErrorMessage(error);
        });
      }
      return;
    }

    final employee = _selectedEmployee;
    if (employee == null) {
      setState(() {
        _error = 'Selecciona un empleado.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
    });
    final loginTimer = LoginPerformanceTrace.start();

    try {
      final valid = await LoginPerformanceTrace.measure(
        'pin_employee_validation',
        () => _repository.validateEmployeePin(
          employeeId: employee.id,
          pin: _pinController.text.trim(),
        ),
      );
      if (!mounted) {
        return;
      }

      if (!valid) {
        setState(() {
          _busy = false;
          _error = 'PIN incorrecto o empleado inactivo.';
        });
        return;
      }

      final branches = await LoginPerformanceTrace.measure(
        'pin_accessible_branches',
        () => _repository.getAccessibleBranches(employee),
      );
      if (!mounted) {
        return;
      }
      final selectedBranch = branches.length > 1
          ? await _selectBranch(branches)
          : (branches.isEmpty ? null : branches.first);
      if (!mounted) {
        return;
      }
      if (branches.length > 1 && selectedBranch == null) {
        setState(() {
          _busy = false;
          _error = 'Selecciona una sucursal para continuar.';
        });
        return;
      }
      if (!kIsWeb) {
        final branchToPersist =
            selectedBranch ??
            (branches.isEmpty ? Branch.defaultBranch : branches.first);
        await LoginPerformanceTrace.measure(
          'pin_device_validation',
          () => OperationalEmployeeSessionService.instance
              .validateDeviceForOperationalLogin(branchToPersist.id),
        );
        await LoginPerformanceTrace.measure(
          'pin_secure_session_persist',
          () => OperationalEmployeeSessionService.instance.persistLogin(
            employee,
            branchToPersist,
          ),
        );
      }
      AppSession.instance.signIn(
        employee,
        branches: branches,
        initialBranch: selectedBranch,
      );
      LoginPerformanceTrace.finish('pin_to_employee_session', loginTimer);
    } catch (error) {
      LoginPerformanceTrace.finish(
        'pin_to_employee_session',
        loginTimer,
        result: 'failed',
        error: error,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = kIsWeb
            ? backofficeLoginErrorMessage(error)
            : 'No se pudo iniciar sesion: $error';
      });
    }
  }

  Future<Branch?> _selectBranch(List<Branch> branches) {
    return showDialog<Branch>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Selecciona sucursal'),
        content: SizedBox(
          width: 360,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: branches.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final branch = branches[index];
              return ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text(branch.name),
                subtitle: Text(branch.restaurantName),
                onTap: () => Navigator.pop(context, branch),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: PremiumBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + keyboardInset),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: _isBackofficeWebLogin
                          ? _buildBackofficeUserLogin()
                          : _buildEmployeeLogin(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBackofficeUserLogin() {
    return FutureBuilder<List<BackofficeLoginUser>>(
      future: _backofficeUsersFuture,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final hasError = snapshot.hasError;
        final users = snapshot.data ?? const <BackofficeLoginUser>[];
        final selectedId = _selectedBackofficeUser?.id;
        final selectedUser = selectedId == null
            ? null
            : users.where((user) => user.id == selectedId).firstOrNull;
        if (selectedUser == null && _selectedBackofficeUser != null) {
          _selectedBackofficeUser = null;
        }

        final selector = DropdownButtonFormField<BackofficeLoginUser>(
          key: const ValueKey('backoffice-user-dropdown'),
          initialValue: selectedUser,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Usuario'),
          hint: Text(
            loading
                ? 'Cargando usuarios...'
                : hasError
                ? 'No fue posible cargar usuarios'
                : 'Selecciona un usuario',
            overflow: TextOverflow.ellipsis,
          ),
          items: users
              .map(
                (user) => DropdownMenuItem(
                  value: user,
                  child: Text(
                    user.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: _busy || loading || hasError
              ? null
              : (user) {
                  setState(() {
                    _selectedBackofficeUser = user;
                    _error = '';
                  });
                },
        );

        return _buildLoginPanel(
          context,
          employeeSelector: selector,
          loadError: hasError
              ? 'No fue posible cargar los usuarios. Reintentar.'
              : null,
        );
      },
    );
  }

  Widget _buildEmployeeLogin() {
    return StreamBuilder<List<Employee>>(
      stream: _employeesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'No se pudieron cargar empleados',
            message: '${snapshot.error}',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPanel(message: 'Cargando acceso...');
        }

        final employees = snapshot.data ?? [];
        if (employees.isEmpty) {
          return const EmptyState(
            icon: Icons.badge_outlined,
            title: 'Sin empleados activos',
            message: 'Activa un empleado desde Admin.',
          );
        }

        final selectedId = _selectedEmployee?.id;
        final selectedEmployee = selectedId == null
            ? null
            : employees
                  .where((employee) => employee.id == selectedId)
                  .firstOrNull;

        return _buildLoginPanel(
          context,
          employeeSelector: DropdownButtonFormField<Employee>(
            key: ValueKey(selectedEmployee?.id ?? 'none'),
            initialValue: selectedEmployee,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Empleado'),
            items: employees
                .map(
                  (employee) => DropdownMenuItem(
                    value: employee,
                    child: Text(employee.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (employee) {
                    setState(() {
                      _selectedEmployee = employee;
                      _error = '';
                    });
                  },
          ),
        );
      },
    );
  }

  Widget _buildLoginPanel(
    BuildContext context, {
    Widget? employeeSelector,
    String? loadError,
  }) {
    return GlassPanel(
      borderRadius: 28,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox(
              width: 118,
              height: 118,
              child: Image.asset(AppConstants.logoAsset, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            _isBackofficeWebLogin
                ? 'TacoPOS Backoffice'
                : AppConstants.brandName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            _isBackofficeWebLogin
                ? 'Acceso administrativo'
                : 'Inicio de sesion operativo',
            textAlign: TextAlign.center,
            style: TextStyle(color: BrandColors.textMuted),
          ),
          const SizedBox(height: 22),
          ?employeeSelector,
          if (loadError != null) ...[
            const SizedBox(height: 10),
            Text(
              loadError,
              style: const TextStyle(
                color: BrandColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _retryBackofficeUsers,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _pinController,
            focusNode: _pinFocusNode,
            enabled: !_busy,
            obscureText: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'PIN'),
            onSubmitted: (_) => _login(),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _error,
              style: const TextStyle(
                color: BrandColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _login,
            icon: const Icon(Icons.login),
            label: Text(_busy ? 'Entrando...' : 'Entrar'),
          ),
          const SizedBox(height: 14),
          const _LoginVersionStatus(),
        ],
      ),
    );
  }
}

class _LoginVersionStatus extends StatelessWidget {
  const _LoginVersionStatus();

  @override
  Widget build(BuildContext context) {
    final updateScope = AppUpdateScope.maybeOf(context);
    final result = updateScope?.result;
    final versionName = result?.currentVersionName.trim();
    final versionCode = result?.currentVersionCode ?? 0;
    final displayVersion = kIsWeb
        ? BackofficeVersion.label
        : (versionName == null || versionName.isEmpty
              ? 'Version desconocida'
              : 'Version $versionName ($versionCode)');
    final status = kIsWeb
        ? const _VersionStatusView(
            icon: Icons.check_circle_outline,
            label: 'Backoffice actualizado',
            color: BrandColors.success,
          )
        : _status(result);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: kIsWeb ? null : updateScope?.onStatusTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                kIsWeb ? displayVersion : 'TacoPOS · $displayVersion',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: BrandColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(status.icon, color: status.color, size: 15),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      status.label,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: status.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (status.actionLabel != null &&
                      updateScope?.onStartFlexibleUpdate != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: updateScope!.onStartFlexibleUpdate,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                      ),
                      child: Text(status.actionLabel!),
                    ),
                  ],
                  if (updateScope?.flexibleReadyToInstall == true) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: updateScope!.onCompleteFlexibleUpdate,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                      ),
                      child: const Text('Reiniciar y actualizar'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  _VersionStatusView _status(AppUpdateCheckResult? result) {
    if (result == null || result.errorCode == 'APP_UPDATE_CONFIG_UNAVAILABLE') {
      return const _VersionStatusView(
        icon: Icons.help_outline,
        label: 'No se pudo verificar la version',
        color: BrandColors.textMuted,
      );
    }
    if (result.decision.isRequired) {
      return const _VersionStatusView(
        icon: Icons.warning_amber_outlined,
        label: 'Esta version ya no es compatible',
        actionLabel: 'Actualizar ahora',
        color: BrandColors.danger,
      );
    }
    if (result.decision.isRecommended && result.canStartFlexibleUpdate) {
      return const _VersionStatusView(
        icon: Icons.info_outline,
        label: 'Hay una actualizacion disponible',
        actionLabel: 'Actualizar',
        color: BrandColors.accentYellow,
      );
    }
    if (result.decision.isRecommended) {
      return const _VersionStatusView(
        icon: Icons.help_outline,
        label: 'No se pudo verificar la version',
        color: BrandColors.textMuted,
      );
    }
    return const _VersionStatusView(
      icon: Icons.check_circle_outline,
      label: 'Actualizado',
      color: BrandColors.success,
    );
  }
}

class _VersionStatusView {
  const _VersionStatusView({
    required this.icon,
    required this.label,
    required this.color,
    this.actionLabel,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String? actionLabel;
}

String backofficeLoginErrorMessage(Object? error) {
  if (error is BackofficeAdminAuthException) {
    return error.message;
  }
  if (error is FirebaseFunctionsException) {
    return switch (error.code) {
      'unauthenticated' => 'PIN incorrecto.',
      'permission-denied' => 'No tienes permisos para acceder al Backoffice.',
      'resource-exhausted' => 'Demasiados intentos. Intenta mas tarde.',
      _ => 'No fue posible iniciar sesion. Intenta nuevamente.',
    };
  }
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'No tienes permisos para acceder al Backoffice.';
  }
  return 'PIN incorrecto.';
}
