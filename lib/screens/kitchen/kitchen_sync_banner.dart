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
