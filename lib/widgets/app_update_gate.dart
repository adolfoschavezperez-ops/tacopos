import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_session.dart';
import '../services/app_update_service.dart';
import '../services/device_registry_service.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.child,
    AppUpdateService? updateService,
    DeviceRegistryService? deviceRegistryService,
  }) : _updateService = updateService,
       _deviceRegistryService = deviceRegistryService;

  final Widget child;
  final AppUpdateService? _updateService;
  final DeviceRegistryService? _deviceRegistryService;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  late final AppUpdateService _updateService;
  late final DeviceRegistryService _deviceRegistryService;
  late final StreamSubscription<void> _downloadedSubscription;
  late final StreamSubscription<void> _immediateSubscription;
  late final StreamSubscription<AppUpdateInstallProgress> _progressSubscription;
  AppUpdateCheckResult? _lastResult;
  AppUpdateCheckResult? _requiredUpdate;
  AppUpdateInstallProgress? _progress;
  String? _requiredError;
  bool _checking = true;
  bool _updating = false;
  bool _recommendedShown = false;
  bool _flexibleReadyToInstall = false;

  @override
  void initState() {
    super.initState();
    _updateService = widget._updateService ?? AppUpdateService();
    _deviceRegistryService =
        widget._deviceRegistryService ?? DeviceRegistryService.instance;
    _downloadedSubscription = _updateService.flexibleUpdateDownloaded.listen(
      (_) => _onFlexibleUpdateDownloaded(),
    );
    _immediateSubscription = _updateService.immediateUpdateInProgress.listen((
      _,
    ) {
      if (mounted) setState(() => _updating = true);
    });
    _progressSubscription = _updateService.flexibleUpdateProgress.listen((
      progress,
    ) {
      if (mounted) setState(() => _progress = progress);
    });
    AppSession.instance.addListener(_onSessionChanged);
    unawaited(_checkForUpdate());
  }

  @override
  void dispose() {
    AppSession.instance.removeListener(_onSessionChanged);
    _downloadedSubscription.cancel();
    _immediateSubscription.cancel();
    _progressSubscription.cancel();
    super.dispose();
  }

  void _onSessionChanged() {
    unawaited(
      _deviceRegistryService.recordHeartbeat(
        updateResult: _lastResult,
        force: true,
      ),
    );
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _checking = true;
      _requiredError = null;
    });
    final result = await _updateService.checkForUpdate();
    await _deviceRegistryService.recordHeartbeat(updateResult: result);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _lastResult = result;
      _requiredUpdate = result.decision.isRequired ? result : null;
    });
    if (result.decision.isRequired) {
      if (result.canStartImmediateUpdate) {
        unawaited(_runImmediateUpdate(result));
      }
      return;
    }
    if (result.decision.isRecommended &&
        result.canStartFlexibleUpdate &&
        !_recommendedShown) {
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
        _requiredError = _friendlyUpdateError(error);
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
    setState(() {
      _updating = true;
      _progress = null;
    });
    try {
      await _updateService.startFlexibleUpdate();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyUpdateError(error))));
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  void _onFlexibleUpdateDownloaded() {
    if (!mounted || _flexibleReadyToInstall) return;
    setState(() {
      _flexibleReadyToInstall = true;
      _updating = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(days: 1),
        content: const Text('Actualizacion lista para instalar'),
        action: SnackBarAction(
          label: 'Reiniciar y actualizar',
          onPressed: () => unawaited(_updateService.completeFlexibleUpdate()),
        ),
      ),
    );
  }

  Future<void> _openGooglePlay() async {
    try {
      await _updateService.openGooglePlay();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyUpdateError(error))));
    }
  }

  Future<void> _handleVersionStatusTap() async {
    final result = _lastResult;
    if (result == null) return;
    if (result.decision.isRecommended) {
      await _showRecommendedUpdate(result);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Version instalada'),
        content: Text(
          'TacoPOS\nVersion ${result.currentVersionName} '
          '(${result.currentVersionCode})',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  String _friendlyUpdateError(Object error) {
    final text = error.toString();
    if (text.contains('APP_UPDATE_NOT_PLAY_INSTALLED')) {
      return 'APP_UPDATE_NOT_PLAY_INSTALLED: instala TacoPOS desde el enlace privado de Prueba interna de Google Play.';
    }
    if (text.contains('APP_UPDATE_CHECK_FAILED') ||
        text.contains('APP_UPDATE_START_FAILED') ||
        text.contains('APP_UPDATE_MANAGER_UNAVAILABLE')) {
      return 'No se pudo consultar la actualizacion en Google Play.';
    }
    return 'No se pudo iniciar la actualizacion en Google Play.';
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
        onUpdate: requiredUpdate.canStartImmediateUpdate
            ? () => _runImmediateUpdate(requiredUpdate)
            : null,
        onOpenGooglePlay: _openGooglePlay,
      );
    }

    if (_checking && _lastResult == null) {
      return const _CheckingVersionScreen();
    }

    return AppUpdateScope(
      result: _lastResult,
      checking: _checking,
      flexibleReadyToInstall: _flexibleReadyToInstall,
      onStatusTap: _handleVersionStatusTap,
      onStartFlexibleUpdate: _lastResult?.canStartFlexibleUpdate == true
          ? _runFlexibleUpdate
          : null,
      onCompleteFlexibleUpdate: _updateService.completeFlexibleUpdate,
      child: Stack(
        children: [
          widget.child,
          if (_updating)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0xAA000000),
                child: Center(
                  child: _UpdateProgressCard(
                    title: 'Actualizando TacoPOS',
                    message:
                        'Google Play esta descargando la actualizacion flexible.',
                    progress: _progress?.progress,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AppUpdateScope extends InheritedWidget {
  const AppUpdateScope({
    super.key,
    required super.child,
    required this.result,
    required this.checking,
    required this.flexibleReadyToInstall,
    required this.onStatusTap,
    required this.onCompleteFlexibleUpdate,
    this.onStartFlexibleUpdate,
  });

  final AppUpdateCheckResult? result;
  final bool checking;
  final bool flexibleReadyToInstall;
  final Future<void> Function() onStatusTap;
  final Future<void> Function()? onStartFlexibleUpdate;
  final Future<void> Function() onCompleteFlexibleUpdate;

  static AppUpdateScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppUpdateScope>();
  }

  @override
  bool updateShouldNotify(AppUpdateScope oldWidget) {
    return result != oldWidget.result ||
        checking != oldWidget.checking ||
        flexibleReadyToInstall != oldWidget.flexibleReadyToInstall;
  }
}

class _CheckingVersionScreen extends StatelessWidget {
  const _CheckingVersionScreen();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'TacoPOS',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF090909),
        body: SafeArea(
          child: Center(
            child: _UpdateProgressCard(
              title: 'Verificando version...',
              message: 'Preparando TacoPOS.',
            ),
          ),
        ),
      ),
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
    final canUpdate = result.canStartFlexibleUpdate;
    return AlertDialog(
      title: const Text('Actualizacion disponible'),
      content: Text(
        '${result.decision.message}\n\n'
        'Version instalada: ${result.currentVersionName} '
        '(${result.currentVersionCode})\n'
        'Version disponible: '
        '${result.playUpdateAvailability.availableVersionCode ?? result.recommendedVersionCode}'
        '${result.releaseNotes == null || result.releaseNotes!.trim().isEmpty ? '' : '\n\n${result.releaseNotes}'}'
        '${canUpdate ? '' : '\n\nNo se pudo consultar la actualizacion en Google Play.'}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Recordarme despues'),
        ),
        FilledButton(
          onPressed: canUpdate ? () => onUpdate() : null,
          child: const Text('Actualizar ahora'),
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
    required this.onOpenGooglePlay,
  });

  final AppUpdateCheckResult result;
  final bool checking;
  final bool updating;
  final String? errorMessage;
  final VoidCallback onRetry;
  final VoidCallback? onUpdate;
  final VoidCallback onOpenGooglePlay;

  @override
  Widget build(BuildContext context) {
    final busy = checking || updating;
    final supportMessage =
        result.errorCode == 'APP_UPDATE_REQUIRED_NOT_AVAILABLE'
        ? 'La actualizacion ya fue publicada, pero Google Play todavia no la muestra para este dispositivo. Espera unos minutos y vuelve a intentarlo.'
        : result.errorCode == 'APP_UPDATE_NOT_PLAY_INSTALLED'
        ? 'Esta tablet debe instalar TacoPOS desde el enlace privado de Prueba interna de Google Play.'
        : 'Esta version de TacoPOS ya no puede continuar operando. Actualiza para seguir utilizando el sistema.';
    return MaterialApp(
      title: 'TacoPOS',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF090909),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
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
                        'Actualizacion necesaria',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        supportMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFE0E0E0)),
                      ),
                      if (result.decision.message.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          result.decision.message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFB8B8B8)),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'Version instalada: ${result.currentVersionName} '
                        '(${result.currentVersionCode})\n'
                        'Version requerida: ${result.minimumSupportedVersionCode}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFB8B8B8)),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorMessage!,
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
                          onPressed: onOpenGooglePlay,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Abrir Google Play'),
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
  const _UpdateProgressCard({
    required this.title,
    required this.message,
    this.progress,
  });

  final String title;
  final String message;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF242424),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: const Color(0xFFFFC928),
              value: progress,
            ),
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
            if (progress != null) ...[
              const SizedBox(height: 6),
              Text(
                '${(progress! * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Color(0xFFB8B8B8)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
