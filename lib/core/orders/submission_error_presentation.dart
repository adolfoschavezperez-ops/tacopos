import 'package:cloud_functions/cloud_functions.dart';

import 'local_order_capture.dart';

class SubmissionErrorPresentation {
  const SubmissionErrorPresentation({
    required this.message,
    required this.isConnectivityFailure,
    required this.canRetry,
  });

  final String message;
  final bool isConnectivityFailure;
  final bool canRetry;

  factory SubmissionErrorPresentation.from(Object error) {
    if (error is LocalOrderCaptureConfirmationPending) {
      return const SubmissionErrorPresentation(
        message:
            'El servidor no confirmó si la comanda se envió. Tu captura sigue guardada; reintenta el envío sin volver a capturar.',
        isConnectivityFailure: false,
        canRetry: true,
      );
    }
    final cause = _unwrap(error);
    if (cause is! FirebaseFunctionsException) {
      return const SubmissionErrorPresentation(
        message: 'No se pudo confirmar el envío. Tu pedido sigue guardado.',
        isConnectivityFailure: false,
        canRetry: true,
      );
    }

    final code = cause.code.toLowerCase();
    final original = cause.message?.trim();
    final details = cause.details;
    final detailsText = details is Map
        ? '${details['reason'] ?? ''} ${details['message'] ?? ''}'
        : details?.toString() ?? '';
    final lowerError = '${original ?? ''} $detailsText'.toLowerCase();
    final hasOriginal = original != null && original.isNotEmpty;
    if (code == 'unavailable' || code == 'deadline-exceeded') {
      return SubmissionErrorPresentation(
        message: hasOriginal
            ? original
            : 'Conexión inestable. Tu pedido está guardado.',
        isConnectivityFailure: true,
        canRetry: true,
      );
    }
    if (code == 'unauthenticated') {
      final appCheck =
          lowerError.contains('app check') ||
          lowerError.contains('appcheck') ||
          lowerError.contains('app_check');
      return SubmissionErrorPresentation(
        message: appCheck
            ? 'No se pudo validar esta instalación. Tu pedido sigue guardado.'
            : 'Tu sesión requiere validación. Inicia sesión y reintenta.',
        isConnectivityFailure: false,
        canRetry: appCheck,
      );
    }
    if (code == 'permission-denied') {
      final appCheck =
          lowerError.contains('app check') ||
          lowerError.contains('appcheck') ||
          lowerError.contains('app_check');
      if (appCheck) {
        return const SubmissionErrorPresentation(
          message:
              'No se pudo validar la seguridad de esta instalación. Tu pedido sigue guardado.',
          isConnectivityFailure: false,
          canRetry: true,
        );
      }
      return SubmissionErrorPresentation(
        message: hasOriginal
            ? original
            : 'No tienes permiso para enviar esta comanda.',
        isConnectivityFailure: false,
        canRetry: false,
      );
    }
    if (code == 'not-found' &&
        (original ?? '').toLowerCase().contains('servicio')) {
      return const SubmissionErrorPresentation(
        message:
            'El servicio seguro de envío aún no está habilitado. Tu pedido está guardado.',
        isConnectivityFailure: false,
        canRetry: false,
      );
    }
    return SubmissionErrorPresentation(
      message: hasOriginal
          ? original
          : code == 'not-found'
          ? 'La orden ya no existe. Tu borrador permanece guardado en esta tablet.'
          : 'No se pudo confirmar el envío. Tu pedido sigue guardado.',
      isConnectivityFailure: false,
      canRetry: !const {
        'not-found',
        'permission-denied',
        'unauthenticated',
        'failed-precondition',
        'invalid-argument',
        'resource-exhausted',
        'already-exists',
      }.contains(code),
    );
  }

  static Object _unwrap(Object error) {
    var current = error;
    final seen = <Object>{};
    while (current is LocalOrderCaptureSafelyAborted &&
        seen.add(current) &&
        !identical(current.cause, current)) {
      current = current.cause;
    }
    return current;
  }
}
