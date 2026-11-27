/// Thrown whenever a write/mutation is attempted while Backoffice 2.0 is
/// running in Preview (read-only) mode.
class BackofficeReadOnlyException implements Exception {
  const BackofficeReadOnlyException(this.action);

  final String action;

  @override
  String toString() =>
      'Operación "$action" no disponible: Backoffice 2.0 Preview es exclusivamente de consulta.';
}

/// Centralized data-layer guard that blocks all administrative writes in Preview.
class BackofficeReadOnlyGuard {
  const BackofficeReadOnlyGuard._();

  static void assertWritable({
    required bool isReadOnly,
    required String action,
  }) {
    if (isReadOnly) {
      throw BackofficeReadOnlyException(action);
    }
  }
}
