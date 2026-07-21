import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';

class PosOrder {
  const PosOrder({
    required this.id,
    required this.tableId,
    required this.tableName,
    required this.status,
    required this.kitchenStatus,
    required this.paymentStatus,
    required this.total,
    required this.paidTotal,
    required this.pendingTotal,
    required this.personNames,
    required this.orderType,
    this.platformId,
    this.platformName,
    this.takeoutNumber,
    this.customerName,
    this.createdAt,
    this.updatedAt,
    this.sentToKitchenAt,
    this.paidAt,
    this.cancelledAt,
    this.canceledAt,
    this.closedAt,
    this.cancelledByEmployeeId,
    this.cancelledByEmployeeName,
    this.cancelReason,
    this.explicitDiscount = 0,
    this.explicitDiscountFields = const {},
    this.discountType,
    this.discountName,
    this.discountReason,
    this.discountBeneficiaryEmployeeId,
    this.discountBeneficiaryEmployeeName,
    this.discountAuthorizedByEmployeeId,
    this.discountAuthorizedByEmployeeName,
    this.discountAppliedByEmployeeId,
    this.discountAppliedByEmployeeName,
    this.discountAppliedAt,
    this.restaurantId = AppConstants.restaurantId,
    this.restaurantName = AppConstants.restaurantName,
    this.branchId = AppConstants.defaultBranchId,
    this.branchName = AppConstants.defaultBranchName,
  });

  final String id;
  final String tableId;
  final String tableName;
  final String status;
  final String kitchenStatus;
  final String paymentStatus;
  final double total;
  final double paidTotal;
  final double pendingTotal;
  final Map<int, String> personNames;
  final String orderType;
  final String? platformId;
  final String? platformName;
  final int? takeoutNumber;
  final String? customerName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? sentToKitchenAt;
  final DateTime? paidAt;
  final DateTime? cancelledAt;
  final DateTime? canceledAt;
  final DateTime? closedAt;
  final String? cancelledByEmployeeId;
  final String? cancelledByEmployeeName;
  final String? cancelReason;
  final double explicitDiscount;
  final Map<String, double> explicitDiscountFields;
  final String? discountType;
  final String? discountName;
  final String? discountReason;
  final String? discountBeneficiaryEmployeeId;
  final String? discountBeneficiaryEmployeeName;
  final String? discountAuthorizedByEmployeeId;
  final String? discountAuthorizedByEmployeeName;
  final String? discountAppliedByEmployeeId;
  final String? discountAppliedByEmployeeName;
  final DateTime? discountAppliedAt;
  final String restaurantId;
  final String restaurantName;
  final String branchId;
  final String branchName;

  factory PosOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return PosOrder(
      id: doc.id,
      tableId: data['tableId'] as String? ?? '',
      tableName: data['tableName'] as String? ?? 'Mesa',
      status: data['status'] as String? ?? 'open',
      kitchenStatus: data['kitchenStatus'] as String? ?? 'pending',
      paymentStatus: data['paymentStatus'] as String? ?? 'pending',
      total: (data['total'] as num?)?.toDouble() ?? 0,
      paidTotal: (data['paidTotal'] as num?)?.toDouble() ?? 0,
      pendingTotal: (data['pendingTotal'] as num?)?.toDouble() ?? 0,
      personNames: _readPersonNames(data['personNames']),
      orderType: data['orderType'] as String? ?? 'dine_in',
      platformId: data['platformId'] as String?,
      platformName: data['platformName'] as String?,
      takeoutNumber: (data['takeoutNumber'] as num?)?.toInt(),
      customerName: data['customerName'] as String?,
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
      sentToKitchenAt: _toDate(data['sentToKitchenAt']),
      paidAt: _toDate(data['paidAt']),
      cancelledAt: _toDate(data['cancelledAt']),
      canceledAt: _toDate(data['canceledAt']),
      closedAt: _toDate(data['closedAt']),
      cancelledByEmployeeId: data['cancelledByEmployeeId'] as String?,
      cancelledByEmployeeName: data['cancelledByEmployeeName'] as String?,
      cancelReason: data['cancelReason'] as String?,
      explicitDiscount: _readExplicitDiscount(data),
      explicitDiscountFields: _readExplicitDiscountFields(data),
      discountType:
          _readOptionalString(data['discountType']) ??
          _readOptionalString(data['lastAppliedDiscountType']),
      discountName:
          _readOptionalString(data['discountName']) ??
          _readOptionalString(data['lastAppliedDiscountName']),
      discountReason:
          _readOptionalString(data['discountReason']) ??
          _readOptionalString(data['lastDiscountReason']),
      discountBeneficiaryEmployeeId: _readOptionalString(
        data['discountBeneficiaryEmployeeId'],
      ),
      discountBeneficiaryEmployeeName: _readOptionalString(
        data['discountBeneficiaryEmployeeName'],
      ),
      discountAuthorizedByEmployeeId: _readOptionalString(
        data['discountAuthorizedByEmployeeId'],
      ),
      discountAuthorizedByEmployeeName: _readOptionalString(
        data['discountAuthorizedByEmployeeName'],
      ),
      discountAppliedByEmployeeId: _readOptionalString(
        data['discountAppliedByEmployeeId'],
      ),
      discountAppliedByEmployeeName: _readOptionalString(
        data['discountAppliedByEmployeeName'],
      ),
      discountAppliedAt: _toDate(data['discountAppliedAt']),
      restaurantId:
          data['restaurantId'] as String? ?? AppConstants.restaurantId,
      restaurantName:
          data['restaurantName'] as String? ?? AppConstants.restaurantName,
      branchId: data['branchId'] as String? ?? AppConstants.defaultBranchId,
      branchName:
          data['branchName'] as String? ?? AppConstants.defaultBranchName,
    );
  }

  String personName(int personNumber) {
    final custom = personNames[personNumber]?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    return 'Persona $personNumber';
  }

  String get displayName {
    if (orderType == 'takeout') {
      final platform = platformName?.trim();
      final number = takeoutNumber == null ? '' : ' · #$takeoutNumber';
      if (platform != null && platform.isNotEmpty) {
        return 'Para llevar · $platform$number';
      }
      return 'Para llevar$number';
    }
    return tableName;
  }

  static Map<int, String> _readPersonNames(Object? value) {
    if (value is! Map) {
      return const {};
    }

    final names = <int, String>{};
    for (final entry in value.entries) {
      final key = int.tryParse(entry.key.toString());
      final name = entry.value?.toString().trim();
      if (key != null && name != null && name.isNotEmpty) {
        names[key] = name;
      }
    }
    return names;
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    return null;
  }

  static double _readExplicitDiscount(Map<String, dynamic> data) {
    final fields = _readExplicitDiscountFields(data);
    for (final key in const [
      'totalDiscountAmount',
      'totalDiscount',
      'discountTotal',
      'discountAmount',
      'appliedDiscount',
      'discount',
      'employeeDiscount',
      'partnerDiscount',
      'familyDiscount',
      'courtesyAmount',
      'complimentaryAmount',
      'promotionDiscount',
      'promoDiscount',
      'employeeConsumptionDiscount',
      'benefitAmount',
    ]) {
      final value = fields[key];
      if (value != null && value > 0) return value;
    }
    return 0;
  }

  static Map<String, double> _readExplicitDiscountFields(
    Map<String, dynamic> data,
  ) {
    final fields = <String, double>{};
    for (final key in const [
      'discount',
      'discountAmount',
      'totalDiscount',
      'discountTotal',
      'appliedDiscount',
      'employeeDiscount',
      'partnerDiscount',
      'familyDiscount',
      'percentageDiscount',
      'discountPercent',
      'discountPercentage',
      'appliedDiscountPercent',
      'promotionDiscount',
      'promoDiscount',
      'complimentaryAmount',
      'courtesyAmount',
      'employeeConsumptionDiscount',
      'netDiscount',
      'totalDiscountAmount',
      'benefitAmount',
    ]) {
      final value = _toDouble(data[key]);
      if (value > 0) fields[key] = value;
    }
    return fields;
  }

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.trim().replaceAll(',', '')) ?? 0;
    }
    return 0;
  }

  static String? _readOptionalString(Object? value) {
    final clean = value?.toString().trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}
