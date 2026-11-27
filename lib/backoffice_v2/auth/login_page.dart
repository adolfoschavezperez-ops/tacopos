import 'package:flutter/material.dart';

import 'backoffice_auth_service.dart';
import 'backoffice_session.dart';
import 'widgets/login_showcase_panel.dart';
import 'widgets/tacopos_brand_mark.dart';

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
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _restaurantController;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restaurantController = TextEditingController(
      text: widget.session.config.defaultRestaurantId,
    );
  }

  @override
  void dispose() {
    _restaurantController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await widget.authService.signInWithEmail(
        restaurantId: _restaurantController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
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
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'Ocurrió un problema al iniciar sesión. Intenta de nuevo.',
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.session.isDarkMode;
    final width = MediaQuery.sizeOf(context).width;
    final showSplit = width >= 1024;

    final Color panelBg = isDark
        ? const Color(0xFF0D0F14)
        : const Color(0xFFFAFAF9);
    final Color cardBg = isDark
        ? const Color(0xFF161920)
        : const Color(0xFFFFFFFF);
    final Color borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE4E4E7);
    final Color titleColor = isDark
        ? const Color(0xFFFAFAF9)
        : const Color(0xFF111318);
    final Color subtitleColor = isDark
        ? const Color(0xFFA1A1AA)
        : const Color(0xFF71717A);

    return Scaffold(
      backgroundColor: panelBg,
      body: Row(
        children: [
          if (showSplit)
            const Expanded(
              flex: 55,
              child: LoginShowcasePanel(),
            ),
          Expanded(
            flex: 45,
            child: Container(
              color: panelBg,
              child: SafeArea(
                child: Column(
                  children: [
                    // Top bar with discreet env badge + theme toggle
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          if (!showSplit)
                            TacoPosBrandMark(
                              size: 30,
                              showWordmark: true,
                              lightText: isDark,
                            ),
                          const Spacer(),
                          _DiscreetEnvBadge(
                            isLocal: widget.session.config.isLocal,
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),
                          _ThemeToggleButton(
                            isDark: isDark,
                            onPressed: widget.session.toggleThemeMode,
                          ),
                        ],
                      ),
                    ),
                    // Centered commercial login form
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 430),
                            child: Container(
                              padding: EdgeInsets.all(width < 480 ? 24 : 32),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: borderColor),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isDark ? 0.35 : 0.05,
                                    ),
                                    blurRadius: isDark ? 32 : 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Form(
                                key: _formKey,
                                child: AutofillGroup(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Bienvenido de nuevo',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontFamilyFallback: const [
                                            'Segoe UI',
                                            'Roboto',
                                            'sans-serif',
                                          ],
                                          fontSize: 25,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.6,
                                          color: titleColor,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Inicia sesión para administrar tu negocio.',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: subtitleColor,
                                        ),
                                      ),
                                      const SizedBox(height: 26),
                                      _FieldLabel(
                                        label: 'Restaurante',
                                        color: titleColor,
                                      ),
                                      const SizedBox(height: 7),
                                      _StyledTextField(
                                        controller: _restaurantController,
                                        hintText: 'Nombre o clave de restaurante',
                                        prefixIcon: Icons.storefront_outlined,
                                        isDark: isDark,
                                        textInputAction: TextInputAction.next,
                                        onFieldSubmitted: (_) =>
                                            _emailFocus.requestFocus(),
                                        validator: (value) {
                                          if (value == null ||
                                              value.trim().isEmpty) {
                                            return 'Ingresa tu restaurante.';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 18),
                                      _FieldLabel(
                                        label: 'Correo electrónico',
                                        color: titleColor,
                                      ),
                                      const SizedBox(height: 7),
                                      _StyledTextField(
                                        controller: _emailController,
                                        focusNode: _emailFocus,
                                        hintText: 'nombre@restaurante.com',
                                        prefixIcon: Icons.mail_outline_rounded,
                                        isDark: isDark,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        autofillHints: const [
                                          AutofillHints.email,
                                        ],
                                        textInputAction: TextInputAction.next,
                                        onFieldSubmitted: (_) =>
                                            _passwordFocus.requestFocus(),
                                        validator: (value) {
                                          final text = value?.trim() ?? '';
                                          if (text.isEmpty) {
                                            return 'Ingresa tu correo electrónico.';
                                          }
                                          if (!text.contains('@') ||
                                              !text.contains('.')) {
                                            return 'Ingresa un correo electrónico válido.';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 18),
                                      _FieldLabel(
                                        label: 'Contraseña',
                                        color: titleColor,
                                      ),
                                      const SizedBox(height: 7),
                                      _StyledTextField(
                                        controller: _passwordController,
                                        focusNode: _passwordFocus,
                                        hintText: 'Ingresa tu contraseña',
                                        prefixIcon: Icons.lock_outline_rounded,
                                        isDark: isDark,
                                        obscureText: _obscurePassword,
                                        autofillHints: const [
                                          AutofillHints.password,
                                        ],
                                        textInputAction: TextInputAction.done,
                                        onFieldSubmitted: (_) => _submit(),
                                        suffixIcon: IconButton(
                                          onPressed: () => setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          ),
                                          tooltip: _obscurePassword
                                              ? 'Mostrar contraseña'
                                              : 'Ocultar contraseña',
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                            size: 18,
                                            color: subtitleColor,
                                          ),
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Ingresa tu contraseña.';
                                          }
                                          return null;
                                        },
                                      ),
                                      if (_error != null) ...[
                                        const SizedBox(height: 16),
                                        _ErrorBanner(
                                          message: _error!,
                                          isDark: isDark,
                                        ),
                                      ],
                                      const SizedBox(height: 22),
                                      _BrandSubmitButton(
                                        label: 'Iniciar sesión',
                                        loading: _submitting,
                                        onPressed: _submit,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Text(
                        'Desarrollado por RenovaDev.',
                        style: TextStyle(fontSize: 12, color: subtitleColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}

class _StyledTextField extends StatelessWidget {
  const _StyledTextField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    required this.isDark,
    this.focusNode,
    this.obscureText = false,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.onFieldSubmitted,
    this.suffixIcon,
    this.validator,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final bool isDark;
  final FocusNode? focusNode;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Widget? suffixIcon;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? const Color(0xFF1B1E25) : const Color(0xFFFAFAF9);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFE4E4E7);
    final textColor = isDark
        ? const Color(0xFFFAFAF9)
        : const Color(0xFF111318);
    final mutedColor = isDark
        ? const Color(0xFF71717A)
        : const Color(0xFFA1A1AA);

    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      style: TextStyle(fontSize: 14, color: textColor),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(fontSize: 13.5, color: mutedColor),
        filled: true,
        fillColor: fill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        constraints: const BoxConstraints(minHeight: 50),
        prefixIcon: Icon(prefixIcon, size: 18, color: mutedColor),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFF97316), width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
      ),
    );
  }
}

class _BrandSubmitButton extends StatefulWidget {
  const _BrandSubmitButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  State<_BrandSubmitButton> createState() => _BrandSubmitButtonState();
}

class _BrandSubmitButtonState extends State<_BrandSubmitButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: widget.loading
                ? const [Color(0xFFFB923C), Color(0xFFFBBF24)]
                : _hovered
                ? const [Color(0xFFEA580C), Color(0xFFD97706)]
                : const [Color(0xFFF97316), Color(0xFFF59E0B)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF97316).withValues(
                alpha: _hovered ? 0.36 : 0.24,
              ),
              blurRadius: _hovered ? 18 : 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.loading ? null : widget.onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Center(
              child: widget.loading
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      widget.label,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.1,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.isDark});

  final String message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);
    final bg = isDark
        ? const Color(0xFFEF4444).withValues(alpha: 0.12)
        : const Color(0xFFFEF2F2);
    final border = isDark
        ? const Color(0xFFEF4444).withValues(alpha: 0.30)
        : const Color(0xFFFECACA);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 17, color: fg),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscreetEnvBadge extends StatelessWidget {
  const _DiscreetEnvBadge({required this.isLocal, required this.isDark});

  final bool isLocal;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final label = isLocal ? 'LOCAL' : 'DEV';
    final fg = isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
    final bg = isDark
        ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
        : const Color(0xFFFEF3C7);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5.5,
            height: 5.5,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeToggleButton extends StatelessWidget {
  const _ThemeToggleButton({required this.isDark, required this.onPressed});

  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final border = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFE4E4E7);
    final bg = isDark ? const Color(0xFF161920) : const Color(0xFFFFFFFF);
    final fg = isDark ? const Color(0xFFD4D4D8) : const Color(0xFF3F3F46);

    return Tooltip(
      message: isDark ? 'Modo claro' : 'Modo oscuro',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: border),
          ),
          child: Icon(
            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            size: 17,
            color: fg,
          ),
        ),
      ),
    );
  }
}
