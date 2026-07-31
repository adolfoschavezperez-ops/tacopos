import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/theme/brand_colors.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import '../services/app_session.dart';
import '../services/app_update_service.dart';
import '../services/taco_pos_repository.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_update_gate.dart';
import '../widgets/commercial_branding.dart';
import '../widgets/glass.dart';
import '../widgets/loading_panel.dart';
import 'home_screen.dart';

class LoginGate extends StatelessWidget {
  const LoginGate({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSession.instance,
      builder: (context, _) {
        return AppSession.instance.isLoggedIn
            ? const HomeScreen()
            : const LoginScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _repository = TacoPosRepository();
  final _pinController = TextEditingController();
  final _pinFocusNode = FocusNode();
  late final Stream<List<Employee>> _employeesStream;
  Employee? _selectedEmployee;
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _employeesStream = _repository.watchEmployees();
    _repository.ensureDefaultBranch();
    _repository.ensureInitialAdminEmployee();
  }

  @override
  void dispose() {
    _pinFocusNode.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
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

    try {
      final valid = await _repository.validateEmployeePin(
        employeeId: employee.id,
        pin: _pinController.text.trim(),
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

      if (kIsWeb && !_canAccessBackoffice(employee)) {
        setState(() {
          _busy = false;
          _error = 'No tienes acceso al backoffice.';
        });
        return;
      }

      final branches = await _repository.getAccessibleBranches(employee);
      if (!mounted) {
        return;
      }
      final selectedBranch = !kIsWeb && branches.length > 1
          ? await _selectBranch(branches)
          : (branches.isEmpty ? null : branches.first);
      if (!mounted) {
        return;
      }
      if (!kIsWeb && branches.length > 1 && selectedBranch == null) {
        setState(() {
          _busy = false;
          _error = 'Selecciona una sucursal para continuar.';
        });
        return;
      }
      AppSession.instance.signIn(
        employee,
        branches: branches,
        initialBranch: selectedBranch,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = 'No se pudo iniciar sesion: $error';
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
                      child: StreamBuilder<List<Employee>>(
                        stream: _employeesStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return EmptyState(
                              icon: Icons.error_outline,
                              title: 'No se pudieron cargar empleados',
                              message: '${snapshot.error}',
                            );
                          }

                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const LoadingPanel(
                              message: 'Cargando acceso...',
                            );
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
                                    .where(
                                      (employee) => employee.id == selectedId,
                                    )
                                    .firstOrNull;

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
                                    child: const CommercialBrandLogo(
                                      size: 118,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                if (kIsWeb)
                                  Text(
                                    'TacoPOS Backoffice',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineMedium,
                                  )
                                else
                                  CommercialBrandName(
                                    textAlign: TextAlign.center,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineMedium,
                                  ),
                                const SizedBox(height: 6),
                                Text(
                                  kIsWeb
                                      ? 'Acceso administrativo'
                                      : 'Inicio de sesion operativo',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: BrandColors.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 22),
                                DropdownButtonFormField<Employee>(
                                  key: ValueKey(selectedEmployee?.id ?? 'none'),
                                  initialValue: selectedEmployee,
                                  decoration: const InputDecoration(
                                    labelText: 'Empleado',
                                  ),
                                  items: employees
                                      .map(
                                        (employee) => DropdownMenuItem(
                                          value: employee,
                                          child: Text(employee.name),
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
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _pinController,
                                  focusNode: _pinFocusNode,
                                  enabled: !_busy,
                                  obscureText: true,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  decoration: const InputDecoration(
                                    labelText: 'PIN',
                                  ),
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
                        },
                      ),
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
}

class _LoginVersionStatus extends StatelessWidget {
  const _LoginVersionStatus();

  @override
  Widget build(BuildContext context) {
    final updateScope = AppUpdateScope.maybeOf(context);
    final result = updateScope?.result;
    final versionName = result?.currentVersionName.trim();
    final versionCode = result?.currentVersionCode ?? 0;
    final displayVersion = versionName == null || versionName.isEmpty
        ? 'desconocida'
        : '$versionName ($versionCode)';
    final status = _status(result);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: updateScope?.onStatusTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'TacoPOS · Version $displayVersion',
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

bool _canAccessBackoffice(Employee employee) {
  // TODO: Antes de produccion real, migrar backoffice web a Firebase Auth
  // con email/password y reglas de Firestore mas estrictas. El PIN operativo
  // sirve para piloto, pero no debe ser la seguridad final de una app publica.
  return employee.hasAdminAccess ||
      employee.canManageCash ||
      employee.canViewKitchenReports ||
      employee.canAuthorizeCashWithdrawals ||
      employee.canViewLiveOperations;
}
