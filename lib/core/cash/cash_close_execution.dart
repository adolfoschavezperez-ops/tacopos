enum CashCloseProgressStage { validating, saving }

extension CashCloseProgressStageText on CashCloseProgressStage {
  String get title => switch (this) {
    CashCloseProgressStage.validating => 'Validando cierre de caja',
    CashCloseProgressStage.saving => 'Grabando corte',
  };

  String get message => switch (this) {
    CashCloseProgressStage.validating =>
      'Estamos revisando que no existan órdenes, comandas ni pendientes antes de grabar el corte.',
    CashCloseProgressStage.saving =>
      'Espera un momento. Estamos guardando el cierre de caja.',
  };

  String get buttonLabel => switch (this) {
    CashCloseProgressStage.validating => 'Validando...',
    CashCloseProgressStage.saving => 'Grabando...',
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
    _stage = CashCloseProgressStage.validating;
    return true;
  }

  void markSaving() {
    if (!_active) return;
    _stage = CashCloseProgressStage.saving;
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
