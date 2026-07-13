import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/brand_colors.dart';
import '../models/employee.dart';
import '../services/app_session.dart';
import '../services/taco_pos_repository.dart';
import '../widgets/empty_state.dart';
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

      AppSession.instance.signIn(employee);
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
                                    child: Image.asset(
                                      AppConstants.logoAsset,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                Text(
                                  kIsWeb
                                      ? 'TacoPOS Backoffice'
                                      : AppConstants.brandName,
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

bool _canAccessBackoffice(Employee employee) {
  // TODO: Antes de produccion real, migrar backoffice web a Firebase Auth
  // con email/password y reglas de Firestore mas estrictas. El PIN operativo
  // sirve para piloto, pero no debe ser la seguridad final de una app publica.
  return employee.canViewAdmin ||
      employee.canManageCash ||
      employee.canViewKitchenReports ||
      employee.canAuthorizeCashWithdrawals ||
      employee.canViewLiveOperations;
}
