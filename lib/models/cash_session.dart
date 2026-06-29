import 'package:cloud_firestore/cloud_firestore.dart';

class CashSession {
  const CashSession({
    required this.id,
    required this.businessDate,
    required this.status,
    required this.openingCashAmount,
    required this.openedByEmployeeId,
    required this.openedByEmployeeName,
    required this.countedCashAmount,
    required this.terminalReportedAmount,
    required this.expectedCashAmount,
    required this.expectedCardChargedAmount,
    required this.expectedCardBaseAmount,
    required this.expectedCardSurchargeAmount,
    required this.expectedPlatformAmount,
    required this.expectedEmployeeConsumptionAmount,
    required this.totalExpectedRealMoney,
    required this.totalCountedRealMoney,
    required this.cashDifference,
    required this.cardDifference,
    required this.netDifference,
    required this.shortageAmount,
    required this.overAmount,
    required this.notes,
    this.openedAt,
    this.closedAt,
    this.closedByEmployeeId,
    this.closedByEmployeeName,
  });

  final String id;
  final String businessDate;
  final String status;
  final double openingCashAmount;
  final DateTime? openedAt;
  final String openedByEmployeeId;
  final String openedByEmployeeName;
  final DateTime? closedAt;
  final String? closedByEmployeeId;
  final String? closedByEmployeeName;
  final double countedCashAmount;
  final double terminalReportedAmount;
  final double expectedCashAmount;
  final double expectedCardChargedAmount;
  final double expectedCardBaseAmount;
  final double expectedCardSurchargeAmount;
  final double expectedPlatformAmount;
  final double expectedEmployeeConsumptionAmount;
  final double totalExpectedRealMoney;
  final double totalCountedRealMoney;
  final double cashDifference;
  final double cardDifference;
  final double netDifference;
  final double shortageAmount;
  final double overAmount;
  final String notes;

  bool get isOpen => status == 'open';

  factory CashSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return CashSession(
      id: doc.id,
      businessDate: data['businessDate'] as String? ?? doc.id,
      status: data['status'] as String? ?? 'open',
      openingCashAmount: _toDouble(data['openingCashAmount']),
      openedAt: _toDate(data['openedAt']),
      openedByEmployeeId: data['openedByEmployeeId'] as String? ?? '',
      openedByEmployeeName: data['openedByEmployeeName'] as String? ?? '',
      closedAt: _toDate(data['closedAt']),
      closedByEmployeeId: data['closedByEmployeeId'] as String?,
      closedByEmployeeName: data['closedByEmployeeName'] as String?,
      countedCashAmount: _toDouble(data['countedCashAmount']),
      terminalReportedAmount: _toDouble(data['terminalReportedAmount']),
      expectedCashAmount: _toDouble(data['expectedCashAmount']),
      expectedCardChargedAmount: _toDouble(data['expectedCardChargedAmount']),
      expectedCardBaseAmount: _toDouble(data['expectedCardBaseAmount']),
      expectedCardSurchargeAmount: _toDouble(
        data['expectedCardSurchargeAmount'],
      ),
      expectedPlatformAmount: _toDouble(data['expectedPlatformAmount']),
      expectedEmployeeConsumptionAmount: _toDouble(
        data['expectedEmployeeConsumptionAmount'],
      ),
      totalExpectedRealMoney: _toDouble(data['totalExpectedRealMoney']),
      totalCountedRealMoney: _toDouble(data['totalCountedRealMoney']),
      cashDifference: _toDouble(data['cashDifference']),
      cardDifference: _toDouble(data['cardDifference']),
      netDifference: _toDouble(data['netDifference']),
      shortageAmount: _toDouble(data['shortageAmount']),
      overAmount: _toDouble(data['overAmount']),
      notes: data['notes'] as String? ?? '',
    );
  }

  static double _toDouble(Object? value) {
    return value is num ? value.toDouble() : 0;
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }
}

class CashSessionTotals {
  const CashSessionTotals({
    this.expectedCashAmount = 0,
    this.expectedCardChargedAmount = 0,
    this.expectedCardBaseAmount = 0,
    this.expectedCardSurchargeAmount = 0,
    this.expectedPlatformAmount = 0,
    this.expectedEmployeeConsumptionAmount = 0,
  });

  final double expectedCashAmount;
  final double expectedCardChargedAmount;
  final double expectedCardBaseAmount;
  final double expectedCardSurchargeAmount;
  final double expectedPlatformAmount;
  final double expectedEmployeeConsumptionAmount;

  double get totalExpectedRealMoney =>
      expectedCashAmount + expectedCardChargedAmount;

  double totalCountedRealMoney({
    required double countedCashAmount,
    required double terminalReportedAmount,
  }) {
    return countedCashAmount + terminalReportedAmount;
  }

  double cashDifference(double countedCashAmount) {
    return countedCashAmount - expectedCashAmount;
  }

  double cardDifference(double terminalReportedAmount) {
    return terminalReportedAmount - expectedCardChargedAmount;
  }

  double netDifference({
    required double countedCashAmount,
    required double terminalReportedAmount,
  }) {
    return totalCountedRealMoney(
          countedCashAmount: countedCashAmount,
          terminalReportedAmount: terminalReportedAmount,
        ) -
        totalExpectedRealMoney;
  }

  double shortageAmount({
    required double countedCashAmount,
    required double terminalReportedAmount,
  }) {
    final difference = netDifference(
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
    );
    return difference < 0 ? difference.abs() : 0;
  }

  double overAmount({
    required double countedCashAmount,
    required double terminalReportedAmount,
  }) {
    final difference = netDifference(
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
    );
    return difference > 0 ? difference : 0;
  }
}
