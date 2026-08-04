import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_update_service.dart';

abstract class MandatoryUpdateClient {
  Future<AppUpdateCheckResult> checkForUpdate();
  Future<void> openGooglePlay();
}

class AppUpdateMandatoryClient implements MandatoryUpdateClient {
  AppUpdateMandatoryClient({AppUpdateService? updateService})
    : _updateService = updateService ?? AppUpdateService();

  final AppUpdateService _updateService;

  @override
  Future<AppUpdateCheckResult> checkForUpdate() {
    return _updateService.checkForUpdate();
  }

  @override
  Future<void> openGooglePlay() {
    return _updateService.openGooglePlay();
  }
}

class MandatoryUpdateGate extends StatefulWidget {
  const MandatoryUpdateGate({
    super.key,
    required this.child,
    this.screenName = '',
    this.checkInterval = const Duration(minutes: 5),
    MandatoryUpdateClient? updateClient,
  }) : _updateClient = updateClient;

  final Widget child;
  final String screenName;
  final Duration checkInterval;
  final MandatoryUpdateClient? _updateClient;

  @override
  State<MandatoryUpdateGate> createState() => _MandatoryUpdateGateState();
}

class _MandatoryUpdateGateState extends State<MandatoryUpdateGate>
    with WidgetsBindingObserver {
  late final MandatoryUpdateClient _updateClient;
  Timer? _timer;
  AppUpdateCheckResult? _lastResult;
  Object? _lastError;
  bool _checking = false;
  bool _openingStore = false;
  int _requestGeneration = 0;

  bool get _blocked => _lastResult?.decision.isRequired == true;

  @override
  void initState() {
    super.initState();
    _updateClient = widget._updateClient ?? AppUpdateMandatoryClient();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    unawaited(_checkForUpdate(reason: 'screen_open'));
  }

  @override
  void didUpdateWidget(covariant MandatoryUpdateGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checkInterval != widget.checkInterval) {
      _startTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkForUpdate(reason: 'lifecycle_resumed'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.checkInterval <= Duration.zero) return;
    _timer = Timer.periodic(widget.checkInterval, (_) {
      unawaited(_checkForUpdate(reason: 'periodic'));
    });
  }

  Future<void> _checkForUpdate({required String reason}) async {
    if (_checking) {
      debugPrint(
        'MANDATORY_UPDATE_CHECK_SKIPPED '
        'screen=${widget.screenName} reason=$reason checkInProgress=true',
      );
      return;
    }
    final generation = ++_requestGeneration;
    setState(() {
      _checking = true;
      _lastError = null;
    });
    try {
      final result = await _updateClient.checkForUpdate();
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _lastResult = result;
        _lastError = null;
      });
      debugPrint(
        'MANDATORY_UPDATE_CHECK '
        'screen=${widget.screenName} '
        'reason=$reason '
        'currentVersionCode=${result.currentVersionCode} '
        'minimumSupportedVersionCode=${result.minimumSupportedVersionCode} '
        'recommendedVersionCode=${result.recommendedVersionCode} '
        'forceUpdate=${result.forceUpdate} '
        'result=${result.decision.isRequired ? 'blocked' : 'allowed'}',
      );
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _lastError = error);
      debugPrint(
        'MANDATORY_UPDATE_CHECK_ERROR '
        'screen=${widget.screenName} reason=$reason error=$error',
      );
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _openGooglePlay() async {
    if (_openingStore) return;
    setState(() => _openingStore = true);
    try {
      await _updateClient.openGooglePlay();
    } catch (error) {
      if (!mounted) return;
      setState(() => _lastError = error);
    } finally {
      if (mounted) {
        setState(() => _openingStore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_blocked,
      child: Stack(
        children: [
          widget.child,
          if (_blocked)
            Positioned.fill(
              child: _MandatoryUpdateOverlay(
                result: _lastResult!,
                checking: _checking,
                openingStore: _openingStore,
                error: _lastError,
                onUpdateNow: () => unawaited(_openGooglePlay()),
                onRetry: () =>
                    unawaited(_checkForUpdate(reason: 'manual_retry')),
              ),
            ),
        ],
      ),
    );
  }
}

class _MandatoryUpdateOverlay extends StatelessWidget {
  const _MandatoryUpdateOverlay({
    required this.result,
    required this.checking,
    required this.openingStore,
    required this.error,
    required this.onUpdateNow,
    required this.onRetry,
  });

  final AppUpdateCheckResult result;
  final bool checking;
  final bool openingStore;
  final Object? error;
  final VoidCallback onUpdateNow;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final busy = checking || openingStore;
    return Material(
      color: const Color(0xF5090909),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
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
                      size: 46,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Actualización obligatoria',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Hay una nueva versión de TacoPOS que debes instalar para continuar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFE0E0E0)),
                    ),
                    const SizedBox(height: 18),
                    _VersionLine(
                      label: 'Versión instalada:',
                      value:
                          '${result.currentVersionName} (${result.currentVersionCode})',
                    ),
                    _VersionLine(
                      label: 'Versión requerida:',
                      value: 'Código ${result.minimumSupportedVersionCode}',
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _friendlyError(error!),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFFFB4AB)),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: busy ? null : onUpdateNow,
                      icon: const Icon(Icons.system_update_alt),
                      label: const Text('Actualizar ahora'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: busy ? null : onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Volver a verificar'),
                    ),
                    if (busy) ...[
                      const SizedBox(height: 18),
                      const LinearProgressIndicator(
                        color: Color(0xFFFFC928),
                        backgroundColor: Color(0xFF3A3A3A),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('APP_UPDATE_NOT_AVAILABLE')) {
      return 'Google Play todavía no muestra la actualización para este dispositivo.';
    }
    return 'No se pudo abrir o consultar Google Play. Vuelve a verificar en unos segundos.';
  }
}

class _VersionLine extends StatelessWidget {
  const _VersionLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFB8B8B8),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
