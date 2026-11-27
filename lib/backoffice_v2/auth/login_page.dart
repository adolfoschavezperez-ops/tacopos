import 'package:flutter/material.dart';

import '../../services/backoffice_admin_auth_service.dart';
import '../core/design/design_tokens.dart';
import '../core/env/backoffice_env.dart';
import '../widgets/environment_banner.dart';
import '../widgets/saas_card.dart';
import 'backoffice_auth_service.dart';
import 'backoffice_session.dart';

class BackofficeLoginPage extends StatefulWidget {
  const BackofficeLoginPage({
    super.key,
    required this.session,
    required this.authService,
  });

  final BackofficeSession session;
  final BackofficeV2AuthService authService;

  @override
  State<BackofficeLoginPage> createState() => _BackofficeLoginPageState();
}

class _BackofficeLoginPageState extends State<BackofficeLoginPage> {
  late final TextEditingController _restaurantController;
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _useEmailMode = false;
  bool _loadingUsers = false;
  bool _submitting = false;
  bool _functionsUnavailableInSpark = false;
  String? _error;
  List<BackofficeLoginUser> _users = const [];
  String? _selectedUserId;

  @override
  void initState() {
    super.initState();
    _restaurantController = TextEditingController(
      text: widget.session.config.defaultRestaurantId,
    );
    _useEmailMode = true;
  }

  @override
  void dispose() {
    _restaurantController.dispose();
    _pinController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    final restaurantId = _restaurantController.text.trim();
    if (restaurantId.isEmpty) return;
    setState(() {
      _loadingUsers = true;
      _error = null;
    });
    try {
      final users = await widget.authService.listUsers(
        restaurantId: restaurantId,
      );
      if (!mounted) return;
      setState(() {
        _users = users;
        _selectedUserId = users.isNotEmpty ? users.first.id : null;
        _functionsUnavailableInSpark = false;
      });
    } on BackofficeAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _users = const [];
        _selectedUserId = null;
        _functionsUnavailableInSpark = e.functionsUnavailableInSpark;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo conectar al servicio de usuarios: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loadingUsers = false);
      }
    }
  }

  Future<void> _submitPin() async {
    final restaurantId = _restaurantController.text.trim();
    final userId = _selectedUserId ?? '';
    final pin = _pinController.text.trim();
    if (userId.isEmpty || pin.isEmpty) {
      setState(() => _error = 'Selecciona un usuario e ingresa tu PIN.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.authService.signInWithPin(
        restaurantId: restaurantId,
        employeeId: userId,
        pin: pin,
      );
      if (!mounted) return;
      widget.session.signIn(
        employee: result.employee,
        restaurantId: result.restaurantId,
        restaurantName: result.restaurantName,
        branches: result.branches,
      );
    } on BackofficeAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _functionsUnavailableInSpark = e.functionsUnavailableInSpark;
        _error = e.message;
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _submitEmail() async {
    final restaurantId = _restaurantController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (restaurantId.isEmpty || email.isEmpty || password.isEmpty) {
      setState(
        () => _error = 'Completa restaurante, correo electrónico y contraseña.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.authService.signInWithEmail(
        restaurantId: restaurantId,
        email: email,
        password: password,
      );
      if (!mounted) return;
      widget.session.signIn(
        employee: result.employee,
        restaurantId: result.restaurantId,
        restaurantName: result.restaurantName,
        branches: result.branches,
      );
    } on BackofficeAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final showSplit = width >= 960;

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: Row(
        children: [
          if (showSplit)
            Expanded(
              flex: 5,
              child: _BrandShowcasePanel(config: widget.session.config),
            ),
          Expanded(
            flex: 6,
            child: Stack(
              children: [
                Positioned(
                  top: 16,
                  right: 20,
                  child: Row(
                    children: [
                      EnvironmentIndicatorPill(config: widget.session.config),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: widget.session.toggleThemeMode,
                        tooltip: widget.session.isDarkMode
                            ? 'Modo claro'
                            : 'Modo oscuro',
                        icon: Icon(
                          widget.session.isDarkMode
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          size: 18,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: SaasCard(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: tokens.brandAccent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'T',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: tokens.brandOnAccent,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'TacoPOS Backoffice 2.0',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    Text(
                                      'Acceso administrativo SaaS • RenovaDev',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _AuthModeSwitcher(
                              useEmailMode: _useEmailMode,
                              onChanged: (val) => setState(() {
                                _useEmailMode = val;
                                _error = null;
                              }),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'ID de Restaurante (Tenant)',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _restaurantController,
                                    style: const TextStyle(fontSize: 13),
                                    decoration: const InputDecoration(
                                      hintText: 'ej. rest_alpha',
                                      prefixIcon: Icon(
                                        Icons.storefront_outlined,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                if (!_useEmailMode) ...[
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: _loadingUsers ? null : _loadUsers,
                                    child: _loadingUsers
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Cargar'),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (!_useEmailMode) ...[
                              Text(
                                'Usuario administrativo',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedUserId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(
                                    Icons.person_outline,
                                    size: 16,
                                  ),
                                ),
                                hint: const Text('Selecciona un administrador'),
                                items: _users
                                    .map(
                                      (u) => DropdownMenuItem<String>(
                                        value: u.id,
                                        child: Text(
                                          u.displayName,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) =>
                                    setState(() => _selectedUserId = val),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'PIN operativo',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _pinController,
                                obscureText: true,
                                keyboardType: TextInputType.number,
                                onSubmitted: (_) => _submitPin(),
                                decoration: const InputDecoration(
                                  hintText: '••••',
                                  prefixIcon: Icon(
                                    Icons.lock_outline,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ] else ...[
                              Text(
                                'Correo electrónico',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  hintText: 'correo@ejemplo.com',
                                  prefixIcon: Icon(
                                    Icons.email_outlined,
                                    size: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Contraseña',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _passwordController,
                                obscureText: true,
                                onSubmitted: (_) => _submitEmail(),
                                decoration: const InputDecoration(
                                  hintText: '••••••••',
                                  prefixIcon: Icon(
                                    Icons.lock_outline,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _functionsUnavailableInSpark
                                      ? tokens.warningSoft
                                      : tokens.dangerSoft,
                                  borderRadius: BorderRadius.circular(
                                    BackofficeSpacing.radiusMd,
                                  ),
                                  border: Border.all(
                                    color:
                                        (_functionsUnavailableInSpark
                                                ? tokens.warning
                                                : tokens.danger)
                                            .withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _functionsUnavailableInSpark
                                        ? tokens.warning
                                        : tokens.danger,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: _submitting
                                  ? null
                                  : (_useEmailMode ? _submitEmail : _submitPin),
                              child: _submitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Iniciar sesión'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthModeSwitcher extends StatelessWidget {
  const _AuthModeSwitcher({
    required this.useEmailMode,
    required this.onChanged,
  });

  final bool useEmailMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.surfaceSubtle,
        borderRadius: BorderRadius.circular(BackofficeSpacing.radiusMd),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeTab(
              label: 'PIN (Functions)',
              selected: !useEmailMode,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _ModeTab(
              label: 'Email / Auth DEV',
              selected: useEmailMode,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selected ? tokens.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: selected ? Border.all(color: tokens.border) : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? tokens.textPrimary : tokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandShowcasePanel extends StatelessWidget {
  const _BrandShowcasePanel({required this.config});

  final BackofficeConfig config;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);

    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: tokens.sidebarBg,
        border: Border(right: BorderSide(color: tokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tokens.brandAccent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  child: Text(
                    'R',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: tokens.brandOnAccent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'RenovaDev  •  TacoPOS',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Control operativo y financiero multi-sucursal.',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    height: 1.15,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Nueva generación de TacoPOS Backoffice diseñada para escalar en múltiples restaurantes y sucursales con consultas acotadas, paginación por cursores y consistencia financiera canónica.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 28),
                const _FeatureBullet(
                  icon: Icons.shield_outlined,
                  title: 'Aislamiento por ambiente y tenant',
                  subtitle:
                      'Protección estricta contra conexiones accidentales a producción.',
                ),
                const SizedBox(height: 14),
                const _FeatureBullet(
                  icon: Icons.bolt_outlined,
                  title: 'Consultas acotadas y paginadas',
                  subtitle:
                      'Filtros de fechas en Firestore y cursores para grandes volúmenes.',
                ),
                const SizedBox(height: 14),
                const _FeatureBullet(
                  icon: Icons.account_balance_outlined,
                  title: 'Compatibilidad total con Android POS',
                  subtitle:
                      'Reutiliza CanonicalSalesSummary y contratos documentales vigentes.',
                ),
              ],
            ),
          ),
          Text(
            'Proyecto activo: ${config.projectId}',
            style: TextStyle(fontSize: 12, color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = BackofficeTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: tokens.surfaceSubtle,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: tokens.border),
          ),
          child: Icon(icon, size: 15, color: tokens.brandAccent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
