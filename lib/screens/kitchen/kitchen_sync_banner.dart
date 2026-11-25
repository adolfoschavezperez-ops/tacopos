import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/kitchen_sync_state.dart';

class KitchenSyncBanner extends StatelessWidget {
  const KitchenSyncBanner({super.key, required this.state});
  final KitchenBundlesState state;

  @override
  Widget build(BuildContext context) {
    final String message;
    switch (state.status) {
      case KitchenSyncStatus.loading:
        message = 'Cargando comandas; esperando información de Cocina.';
      case KitchenSyncStatus.confirmed:
        message = 'Sincronizado con el servidor';
      case KitchenSyncStatus.cache:
        message = state.hasData
            ? 'Comandas guardadas en caché, sin confirmar. Esperando sincronización.'
            : 'Sin confirmación del servidor y sin comandas guardadas disponibles. Esperando conexión.';
      case KitchenSyncStatus.pendingWrites:
        message =
            'Cambios locales pendientes de sincronizar. Información provisional.';
      case KitchenSyncStatus.partial:
        message =
            'Sincronización parcial: artículos pendientes de cargar. ${state.hasCache ? 'Caché sin confirmar.' : 'Esperando información.'}';
      case KitchenSyncStatus.reconnecting:
        message =
            'Reconexión pendiente. Conservando las comandas disponibles. Reintento ${state.issues.first.retryAttempt}/3.';
      case KitchenSyncStatus.transientError:
        message =
            'No se pudo recuperar la sincronización. Reintentos agotados; vuelve a entrar a Cocina. ${state.issues.first.error}';
      case KitchenSyncStatus.permanentError:
        message =
            'Error de sincronización: ${state.issues.first.error}. No se reintentará automáticamente.';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Tooltip(
        message: message,
        child: Text(
          message,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: state.isConfirmed ? Colors.green : Colors.orange,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class KitchenActionRecoveryBanner extends StatelessWidget {
  const KitchenActionRecoveryBanner({
    super.key,
    required this.error,
    required this.isConfirmed,
    required this.actionsReady,
    required this.onRetry,
  });

  final ValueListenable<String?> error;
  final bool isConfirmed;
  final ValueListenable<bool> actionsReady;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: actionsReady,
    builder: (context, ready, child) => ValueListenableBuilder<String?>(
      valueListenable: error,
      builder: (context, message, child) {
        if (!isConfirmed || (ready && message == null)) {
          return const SizedBox.shrink();
        }
        final hasError = message != null;
        final displayMessage =
            message ??
            'Acciones pausadas hasta confirmar la apertura de Cocina y sus insumos iniciales para el día operativo.';
        final accent = hasError ? Colors.redAccent : Colors.orange;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    hasError ? Icons.sync_problem : Icons.lock_clock,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      displayMessage,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: isConfirmed ? onRetry : null,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
