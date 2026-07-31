class SaleFolioConfig {
  const SaleFolioConfig({
    this.enabled = true,
    this.enabledFromBusinessDate,
    this.digits = 4,
    this.prefixMode = 'branch',
    this.blockHardDeletePaidSales = true,
    this.requireVoidReason = true,
    this.requireVoidAuthorization = true,
  });

  final bool enabled;
  final String? enabledFromBusinessDate;
  final int digits;
  final String prefixMode;
  final bool blockHardDeletePaidSales;
  final bool requireVoidReason;
  final bool requireVoidAuthorization;

  factory SaleFolioConfig.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const SaleFolioConfig();
    return SaleFolioConfig(
      enabled: data['saleFolioControlEnabled'] as bool? ?? true,
      enabledFromBusinessDate: _cleanString(
        data['saleFolioControlEnabledFromBusinessDate'],
      ),
      digits: _readDigits(data['saleFolioDigits']),
      prefixMode: _cleanString(data['saleFolioPrefixMode']) ?? 'branch',
      blockHardDeletePaidSales:
          data['blockHardDeletePaidSales'] as bool? ?? true,
      requireVoidReason: data['requireVoidReason'] as bool? ?? true,
      requireVoidAuthorization:
          data['requireVoidAuthorization'] as bool? ?? true,
    );
  }

  bool appliesToBusinessDate(String businessDate) {
    if (!enabled) return false;
    final from = enabledFromBusinessDate?.trim();
    if (from == null || from.isEmpty) return true;
    return businessDate.compareTo(from) >= 0;
  }

  int get resolvedDigits => digits < 1 ? 4 : digits;
}

class SaleFolioAssignment {
  const SaleFolioAssignment({
    required this.sequence,
    required this.display,
    required this.full,
    required this.businessDate,
    required this.branchId,
    required this.restaurantId,
  });

  final int sequence;
  final String display;
  final String full;
  final String businessDate;
  final String branchId;
  final String restaurantId;
}

class SaleFolioAuditRow {
  const SaleFolioAuditRow({
    required this.businessDate,
    required this.sequenceLabel,
    required this.fullFolio,
    required this.orderId,
    required this.customerLabel,
    required this.status,
    required this.amount,
    required this.incidence,
    required this.eventType,
  });

  final String businessDate;
  final String sequenceLabel;
  final String fullFolio;
  final String orderId;
  final String customerLabel;
  final String status;
  final double amount;
  final String incidence;
  final String eventType;

  bool get isMissing => incidence == saleFolioMissingIncidence;
}

const saleFolioMissingIncidence = 'FOLIO FALTANTE';
const saleFolioHistoricalIncidence = 'SIN FOLIO - VENTA HISTORICA';
const saleFolioVersion = 1;

const _auditPaymentSnapshotFields = [
  'type',
  'paymentType',
  'method',
  'status',
  'baseAmount',
  'amount',
  'chargedAmount',
  'appliedAmount',
  'cashSessionId',
  'businessDate',
  'employeeId',
  'employeeName',
  'platformId',
  'platformName',
  'cashReceivedAmount',
  'cashChangeAmount',
  'discountAmount',
  'totalAfterDiscount',
  'appliedDiscountType',
  'appliedDiscountName',
  'discountSource',
];

Map<String, Object?> buildSaleAuditPaymentSnapshot({
  required String paymentId,
  required Map<String, Object?> paymentData,
  required SaleFolioAssignment assignment,
}) {
  final snapshot = <String, Object?>{
    'paymentId': paymentId,
    'saleFolioSequence': assignment.sequence,
    'saleFolioDisplay': assignment.display,
    'saleFolioFull': assignment.full,
  };
  for (final field in _auditPaymentSnapshotFields) {
    final value = paymentData[field];
    if (_isAuditSnapshotScalar(value)) {
      snapshot[field] = value;
    }
  }
  return snapshot;
}

SaleFolioAssignment buildSaleFolioAssignment({
  required int sequence,
  required String businessDate,
  required String branchId,
  required String branchName,
  required String restaurantId,
  SaleFolioConfig config = const SaleFolioConfig(),
}) {
  final display = formatSaleFolioDisplay(sequence, config.resolvedDigits);
  final prefix = saleFolioPrefixForBranch(branchId: branchId, name: branchName);
  return SaleFolioAssignment(
    sequence: sequence,
    display: display,
    full: '$prefix-$businessDate-$display',
    businessDate: businessDate,
    branchId: branchId,
    restaurantId: restaurantId,
  );
}

String formatSaleFolioDisplay(int sequence, int digits) {
  if (sequence <= 0) return ''.padLeft(digits, '0');
  final raw = sequence.toString();
  if (raw.length >= digits) return raw;
  return raw.padLeft(digits, '0');
}

String saleFolioPrefixForBranch({
  required String branchId,
  required String name,
}) {
  final cleanId = _normalize(branchId);
  final cleanName = _normalize(name);
  if (cleanId.contains('AVI') || cleanName.contains('AVIACION')) {
    return 'AVI';
  }
  final source = cleanId.isNotEmpty ? cleanId : cleanName;
  if (source.isEmpty) return 'TAC';
  return source.length <= 3 ? source.padRight(3, 'X') : source.substring(0, 3);
}

List<int> missingSaleFolioSequences({
  required int lastSequence,
  required Iterable<int> issuedSequences,
}) {
  if (lastSequence <= 0) return const [];
  final issued = issuedSequences.where((value) => value > 0).toSet();
  return [
    for (var sequence = 1; sequence <= lastSequence; sequence++)
      if (!issued.contains(sequence)) sequence,
  ];
}

String saleFolioFailureMessage(Object error) {
  final text = error.toString();
  if (text.contains('unavailable') ||
      text.contains('deadline-exceeded') ||
      text.contains('network') ||
      text.contains('No se pudo generar el folio de venta')) {
    return 'No se pudo generar el folio de venta. Revisa la conexion e intentalo nuevamente. No se realizo un cobro duplicado.';
  }
  return text.replaceFirst('Bad state: ', '');
}

String? _cleanString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _readDigits(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 4;
}

bool _isAuditSnapshotScalar(Object? value) {
  return value is String || value is num || value is bool;
}

String _normalize(String value) {
  const replacements = {
    'Á': 'A',
    'É': 'E',
    'Í': 'I',
    'Ó': 'O',
    'Ú': 'U',
    'Ü': 'U',
    'Ñ': 'N',
  };
  var normalized = value.trim().toUpperCase();
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized.replaceAll(RegExp('[^A-Z0-9]'), '');
}
