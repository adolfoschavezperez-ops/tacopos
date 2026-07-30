import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_update_service.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.child,
    AppUpdateService? updateService,
  }) : _updateService = updateService;

  final Widget child;
  final AppUpdateService? _updateService;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  late final AppUpdateService _updateService;
  AppUpdateCheckResult? _requiredUpdate;
  String? _requiredError;
  bool _checking = true;
  bool _updating = false;
  bool _recommendedShown = false;

  @override
  void initState() {
    super.initState();
    _updateService = widget._updateService ?? AppUpdateService();
    unawaited(_checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _checking = true;
      _requiredError = null;
    });
    final result = await _updateService.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _requiredUpdate = result.decision.isRequired ? result : null;
    });
    if (result.decision.isRequired) {
      if (result.playUpdateAvailable) {
        unawaited(_runImmediateUpdate(result));
      }
      return;
    }
    if (result.decision.isRecommended && !_recommendedShown) {
      _recommendedShown = true;
      unawaited(_showRecommendedUpdate(result));
    }
  }

  Future<void> _runImmediateUpdate(AppUpdateCheckResult result) async {
    setState(() {
      _updating = true;
      _requiredError = null;
    });
    try {
      await _updateService.startImmediateUpdate();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _requiredError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  Future<void> _showRecommendedUpdate(AppUpdateCheckResult result) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RecommendedUpdateDialog(
        result: result,
        onUpdate: () async {
          Navigator.pop(context);
          await _runFlexibleUpdate();
        },
      ),
    );
  }

  Future<void> _runFlexibleUpdate() async {
    setState(() => _updating = true);
    try {
      await _updateService.startFlexibleUpdate();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo iniciar la actualizacion. Puedes continuar operando.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final requiredUpdate = _requiredUpdate;
    if (requiredUpdate != null) {
      return _RequiredUpdateScreen(
        result: requiredUpdate,
        checking: _checking,
        updating: _updating,
        errorMessage: _requiredError,
        onRetry: _checkForUpdate,
        onUpdate: requiredUpdate.playUpdateAvailable
            ? () => _runImmediateUpdate(requiredUpdate)
            : null,
      );
    }

    return Stack(
      children: [
        widget.child,
        if (_updating)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xAA000000),
              child: Center(
                child: _UpdateProgressCard(
                  title: 'Actualizando TacoPOS',
                  message: 'Google Play esta preparando la actualizacion.',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RecommendedUpdateDialog extends StatelessWidget {
  const _RecommendedUpdateDialog({
    required this.result,
    required this.onUpdate,
  });

  final AppUpdateCheckResult result;
  final Future<void> Function() onUpdate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Actualizacion disponible'),
      content: Text(
        '${result.decision.message}\n\n'
        'Version instalada: ${result.currentVersionCode}\n'
        'Version recomendada: ${result.recommendedVersionCode}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Continuar por ahora'),
        ),
        FilledButton(
          onPressed: result.playUpdateAvailable ? () => onUpdate() : null,
          child: const Text('Actualizar'),
        ),
      ],
    );
  }
}

class _RequiredUpdateScreen extends StatelessWidget {
  const _RequiredUpdateScreen({
    required this.result,
    required this.checking,
    required this.updating,
    required this.errorMessage,
    required this.onRetry,
    required this.onUpdate,
  });

  final AppUpdateCheckResult result;
  final bool checking;
  final bool updating;
  final String? errorMessage;
  final VoidCallback onRetry;
  final VoidCallback? onUpdate;

  @override
  Widget build(BuildContext context) {
    final busy = checking || updating;
    return MaterialApp(
      title: 'TacoPOS',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF090909),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                color: const Color(0xFF1E1E1E),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.system_update_alt,
                        color: Color(0xFFFFC928),
                        size: 44,
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Actualizacion requerida',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        result.decision.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFE0E0E0)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Version instalada: ${result.currentVersionCode}\n'
                        'Version minima: ${result.minimumSupportedVersionCode}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFB8B8B8)),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'No se pudo iniciar desde Google Play. Revisa conexion o que la app este instalada desde Play.\n$errorMessage',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFFB4AB)),
                        ),
                      ],
                      const SizedBox(height: 22),
                      if (busy)
                        const _UpdateProgressCard(
                          title: 'Buscando actualizacion',
                          message: 'Conectando con Google Play.',
                        )
                      else ...[
                        FilledButton.icon(
                          onPressed: onUpdate,
                          icon: const Icon(Icons.system_update_alt),
                          label: const Text('Actualizar ahora'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateProgressCard extends StatelessWidget {
  const _UpdateProgressCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF242424),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFFFFC928)),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFCFCFCF)),
            ),
          ],
        ),
      ),
    );
  }
}
