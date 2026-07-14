import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';

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
    required this.expectedCardFeeAbsorbedAmount,
    required this.expectedPlatformAmount,
    required this.expectedEmployeeConsumptionAmount,
    required this.totalExpectedRealMoney,
    required this.totalCountedRealMoney,
    required this.cashDifference,
    required this.cardDifference,
    required this.netDifference,
    required this.shortageAmount,
    required this.overAmount,
    required this.approvedWithdrawalsTotal,
    required this.pendingWithdrawalsTotal,
    required this.withdrawalRequestCount,
    required this.notes,
    this.openedAt,
    this.closedAt,
    this.closedByEmployeeId,
    this.closedByEmployeeName,
    this.restaurantId = AppConstants.restaurantId,
    this.restaurantName = AppConstants.restaurantName,
    this.branchId = AppConstants.defaultBranchId,
    this.branchName = AppConstants.defaultBranchName,
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
  final String restaurantId;
  final String restaurantName;
  final String branchId;
  final String branchName;
  final double countedCashAmount;
  final double terminalReportedAmount;
  final double expectedCashAmount;
  final double expectedCardChargedAmount;
  final double expectedCardBaseAmount;
  final double expectedCardSurchargeAmount;
  final double expectedCardFeeAbsorbedAmount;
  final double expectedPlatformAmount;
  final double expectedEmployeeConsumptionAmount;
  final double totalExpectedRealMoney;
  final double totalCountedRealMoney;
  final double cashDifference;
  final double cardDifference;
  final double netDifference;
  final double shortageAmount;
  final double overAmount;
  final double approvedWithdrawalsTotal;
  final double pendingWithdrawalsTotal;
  final int withdrawalRequestCount;
  final String notes;

  bool get isOpen => status == 'open';
  double get estimatedCardNetAmount =>
      expectedCardChargedAmount - expectedCardFeeAbsorbedAmount;

  factory CashSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final legacyCardSurcharge = _toDouble(data['expectedCardSurchargeAmount']);
    final cardFeeAbsorbed = _toDouble(data['expectedCardFeeAbsorbedAmount']) > 0
        ? _toDouble(data['expectedCardFeeAbsorbedAmount'])
        : legacyCardSurcharge;

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
      restaurantId:
          data['restaurantId'] as String? ?? AppConstants.restaurantId,
      restaurantName:
          data['restaurantName'] as String? ?? AppConstants.restaurantName,
      branchId: data['branchId'] as String? ?? AppConstants.defaultBranchId,
      branchName:
          data['branchName'] as String? ?? AppConstants.defaultBranchName,
      countedCashAmount: _toDouble(data['countedCashAmount']),
      terminalReportedAmount: _toDouble(data['terminalReportedAmount']),
      expectedCashAmount: _toDouble(data['expectedCashAmount']),
      expectedCardChargedAmount: _toDouble(data['expectedCardChargedAmount']),
      expectedCardBaseAmount: _toDouble(data['expectedCardBaseAmount']),
      expectedCardSurchargeAmount: legacyCardSurcharge,
      expectedCardFeeAbsorbedAmount: cardFeeAbsorbed,
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
      approvedWithdrawalsTotal: _toDouble(data['approvedWithdrawalsTotal']),
      pendingWithdrawalsTotal: _toDouble(data['pendingWithdrawalsTotal']),
      withdrawalRequestCount:
          (data['withdrawalRequestCount'] as num?)?.toInt() ?? 0,
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
    this.expectedCardFeeAbsorbedAmount = 0,
    this.expectedPlatformAmount = 0,
    this.expectedEmployeeConsumptionAmount = 0,
    this.approvedWithdrawalsTotal = 0,
    this.pendingWithdrawalsTotal = 0,
    this.withdrawalRequestCount = 0,
  });

  final double expectedCashAmount;
  final double expectedCardChargedAmount;
  final double expectedCardBaseAmount;
  final double expectedCardSurchargeAmount;
  final double expectedCardFeeAbsorbedAmount;

  double get estimatedCardNetAmount =>
      expectedCardChargedAmount - expectedCardFeeAbsorbedAmount;
  final double expectedPlatformAmount;
  final double expectedEmployeeConsumptionAmount;
  final double approvedWithdrawalsTotal;
  final double pendingWithdrawalsTotal;
  final int withdrawalRequestCount;

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
