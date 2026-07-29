import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

enum CashCloseProgressStage {
  validatingOrders,
  validatingKitchen,
  calculating,
  updatingCashSession,
  registeringActivityLog,
}

extension CashCloseProgressStageText on CashCloseProgressStage {
  String get title => switch (this) {
    CashCloseProgressStage.validatingOrders => 'Validando ordenes abiertas',
    CashCloseProgressStage.validatingKitchen => 'Validando Cocina',
    CashCloseProgressStage.calculating => 'Calculando corte',
    CashCloseProgressStage.updatingCashSession => 'Grabando sesion de caja',
    CashCloseProgressStage.registeringActivityLog => 'Registrando cierre',
  };

  String get message => switch (this) {
    CashCloseProgressStage.validatingOrders => 'Validando ordenes abiertas...',
    CashCloseProgressStage.validatingKitchen => 'Validando Cocina...',
    CashCloseProgressStage.calculating => 'Calculando corte...',
    CashCloseProgressStage.updatingCashSession => 'Grabando sesion de caja...',
    CashCloseProgressStage.registeringActivityLog => 'Registrando cierre...',
  };

  String get buttonLabel => switch (this) {
    CashCloseProgressStage.validatingOrders => 'Validando...',
    CashCloseProgressStage.validatingKitchen => 'Validando...',
    CashCloseProgressStage.calculating => 'Calculando...',
    CashCloseProgressStage.updatingCashSession => 'Grabando...',
    CashCloseProgressStage.registeringActivityLog => 'Registrando...',
  };

  String get diagnosticName => switch (this) {
    CashCloseProgressStage.validatingOrders => 'validate_open_orders',
    CashCloseProgressStage.validatingKitchen => 'validate_kitchen',
    CashCloseProgressStage.calculating => 'calculate_close',
    CashCloseProgressStage.updatingCashSession => 'update_cash_session',
    CashCloseProgressStage.registeringActivityLog => 'register_activity_log',
  };
}

class CashCloseExecutionGuard {
  bool _active = false;
  CashCloseProgressStage? _stage;

  bool get isActive => _active;
  CashCloseProgressStage? get stage => _stage;

  bool tryStart() {
    if (_active) return false;
    _active = true;
    _stage = CashCloseProgressStage.validatingOrders;
    return true;
  }

  void markStage(CashCloseProgressStage stage) {
    if (!_active) return;
    _stage = stage;
  }

  void markSaving() {
    markStage(CashCloseProgressStage.updatingCashSession);
  }

  void release() {
    _active = false;
    _stage = null;
  }
}

bool canFinalizeCashSessionClose({
  required String status,
  required bool hasClosedAt,
}) {
  return status.trim().toLowerCase() == 'open' && !hasClosedAt;
}

bool isValidCashCloseAmount(double value) {
  return value >= 0 && value.isFinite && !value.isNaN;
}

class CashCloseException implements Exception {
  const CashCloseException({
    required this.stage,
    required this.operation,
    required this.documentPath,
    required this.cause,
    required this.stackTrace,
  });

  final CashCloseProgressStage stage;
  final String operation;
  final String documentPath;
  final Object cause;
  final StackTrace stackTrace;

  String? get firebaseCode {
    final error = cause;
    return error is FirebaseException ? error.code : null;
  }

  @override
  String toString() {
    final code = firebaseCode;
    return 'CashCloseException(stage=${stage.diagnosticName}, '
        'operation=$operation, documentPath=$documentPath'
        '${code == null ? '' : ', firebaseCode=$code'}, cause=$cause)';
  }
}

String cashCloseErrorMessage(Object error) {
  if (error is CashCloseException) {
    return cashCloseErrorMessage(error.cause);
  }
  if (error is StateError || error is ArgumentError) {
    return _cleanErrorText(error);
  }
  if (error is TimeoutException) {
    return 'No hay conexion con Firebase. Verifica internet e intentalo nuevamente.';
  }
  if (error is FirebaseException) {
    final code = error.code.trim().isEmpty ? 'unknown' : error.code.trim();
    return switch (code) {
      'permission-denied' =>
        'No tienes permiso para grabar el corte. Se requiere actualizar el acceso de Firebase.',
      'failed-precondition' =>
        'No se pudo grabar el corte porque falta una configuracion o indice requerido.',
      'not-found' => 'No se encontro la sesion de caja que se intento cerrar.',
      'already-exists' => 'Este corte ya fue grabado.',
      'aborted' =>
        'El cierre cambio mientras se procesaba. Actualiza e intentalo nuevamente.',
      'invalid-argument' => 'Existe informacion invalida en el corte.',
      'unavailable' || 'network-request-failed' =>
        'No hay conexion con Firebase. Verifica internet e intentalo nuevamente.',
      _ => 'No se pudo grabar el corte. Codigo: $code.',
    };
  }
  return 'No se pudo grabar el corte. Codigo: unknown.';
}

void debugPrintCashCloseFailure({
  required Object error,
  required StackTrace stackTrace,
  required String businessDate,
  required String cashSessionId,
  double? countedCashAmount,
  double? terminalReportedAmount,
}) {
  final wrapped = error is CashCloseException ? error : null;
  final cause = wrapped?.cause ?? error;
  final firebaseError = cause is FirebaseException ? cause : null;
  final effectiveStackTrace = wrapped?.stackTrace ?? stackTrace;
  debugPrint(
    'CASH_CLOSE_FAILURE\n'
    'stage=${wrapped?.stage.diagnosticName ?? 'unknown'}\n'
    'operation=${wrapped?.operation ?? 'unknown'}\n'
    'documentPath=${wrapped?.documentPath ?? 'unknown'}\n'
    'businessDate=$businessDate\n'
    'cashSessionId=$cashSessionId\n'
    'countedCash=$countedCashAmount\n'
    'terminalReported=$terminalReportedAmount\n'
    'exceptionType=${cause.runtimeType}\n'
    'firebaseCode=${firebaseError?.code ?? 'none'}\n'
    'message=${firebaseError?.message ?? cause}\n'
    '$effectiveStackTrace',
  );
}

String _cleanErrorText(Object error) {
  return error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Invalid argument(s): ', '');
}
