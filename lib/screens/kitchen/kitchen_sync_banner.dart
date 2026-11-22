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
    required this.onRetry,
  });

  final ValueListenable<String?> error;
  final bool isConfirmed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: error,
    builder: (context, message, child) {
      if (message == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.withValues(alpha: 0.45)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.sync_problem, color: Colors.redAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No se pudieron habilitar las acciones de Cocina: $message',
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
  );
}
