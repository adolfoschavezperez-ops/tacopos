import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/order_item.dart';
import '../../models/product_recipe_item.dart';

const localOrderCaptureSchemaVersion = 1;

class LocalOrderCaptureLine {
  const LocalOrderCaptureLine({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.branchId,
    required this.branchName,
    required this.orderId,
    required this.tableId,
    required this.tableName,
    required this.tableIds,
    required this.tableNames,
    required this.tableGroupLabel,
    required this.deviceUid,
    required this.employeeId,
    required this.employeeName,
    required this.personNumber,
    required this.personName,
    required this.productId,
    required this.productName,
    required this.categoryId,
    required this.categoryName,
    required this.qty,
    required this.unitPrice,
    required this.notes,
    required this.sendToKitchen,
    required this.affectsKitchenStock,
    required this.kitchenStockItemId,
    required this.kitchenStockItemName,
    required this.kitchenStockUnit,
    required this.stockConsumptionQty,
    required this.recipeItems,
    required this.appliedPlatformId,
    required this.appliedPlatformName,
    required this.priceSource,
    required this.capturedAtMicros,
    this.schemaVersion = localOrderCaptureSchemaVersion,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String branchId;
  final String branchName;
  final String orderId;
  final String tableId;
  final String tableName;
  final List<String> tableIds;
  final List<String> tableNames;
  final String tableGroupLabel;
  final String deviceUid;
  final String employeeId;
  final String employeeName;
  final int personNumber;
  final String personName;
  final String productId;
  final String productName;
  final String categoryId;
  final String categoryName;
  final int qty;
  final double unitPrice;
  final String notes;
  final bool sendToKitchen;
  final bool affectsKitchenStock;
  final String? kitchenStockItemId;
  final String? kitchenStockItemName;
  final String? kitchenStockUnit;
  final double? stockConsumptionQty;
  final List<Map<String, dynamic>> recipeItems;
  final String? appliedPlatformId;
  final String? appliedPlatformName;
  final String priceSource;
  final int capturedAtMicros;
  final int schemaVersion;

  double get total => qty * unitPrice;

  LocalOrderCaptureLine withQty(int value) => LocalOrderCaptureLine(
    id: id,
    restaurantId: restaurantId,
    restaurantName: restaurantName,
    branchId: branchId,
    branchName: branchName,
    orderId: orderId,
    tableId: tableId,
    tableName: tableName,
    tableIds: tableIds,
    tableNames: tableNames,
    tableGroupLabel: tableGroupLabel,
    deviceUid: deviceUid,
    employeeId: employeeId,
    employeeName: employeeName,
    personNumber: personNumber,
    personName: personName,
    productId: productId,
    productName: productName,
    categoryId: categoryId,
    categoryName: categoryName,
    qty: value,
    unitPrice: unitPrice,
    notes: notes,
    sendToKitchen: sendToKitchen,
    affectsKitchenStock: affectsKitchenStock,
    kitchenStockItemId: kitchenStockItemId,
    kitchenStockItemName: kitchenStockItemName,
    kitchenStockUnit: kitchenStockUnit,
    stockConsumptionQty: stockConsumptionQty,
    recipeItems: recipeItems,
    appliedPlatformId: appliedPlatformId,
    appliedPlatformName: appliedPlatformName,
    priceSource: priceSource,
    capturedAtMicros: capturedAtMicros,
    schemaVersion: schemaVersion,
  );

  OrderItem toOrderItem() => OrderItem(
    id: id,
    personNumber: personNumber,
    personName: personName,
    productId: productId,
    productName: productName,
    category: categoryName,
    qty: qty,
    unitPrice: unitPrice,
    total: total,
    notes: notes,
    sendToKitchen: sendToKitchen,
    kitchenStatus: sendToKitchen ? 'pending' : 'not_required',
    paymentStatus: 'pending',
    affectsKitchenStock: affectsKitchenStock,
    kitchenStockItemId: kitchenStockItemId,
    kitchenStockItemName: kitchenStockItemName,
    kitchenStockUnit: kitchenStockUnit,
    recipeItems: ProductRecipeItem.readList(recipeItems),
    appliedPlatformId: appliedPlatformId,
    appliedPlatformName: appliedPlatformName,
    priceSource: priceSource,
    status: 'active',
    cancelStatus: 'none',
    restaurantId: restaurantId,
    restaurantName: restaurantName,
    branchId: branchId,
    branchName: branchName,
    createdAt: DateTime.fromMicrosecondsSinceEpoch(capturedAtMicros),
  );

  Map<String, dynamic> toMap() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'restaurantId': restaurantId,
    'restaurantName': restaurantName,
    'branchId': branchId,
    'branchName': branchName,
    'orderId': orderId,
    'tableId': tableId,
    'tableName': tableName,
    'tableIds': tableIds,
    'tableNames': tableNames,
    'tableGroupLabel': tableGroupLabel,
    'deviceUid': deviceUid,
    'employeeId': employeeId,
    'employeeName': employeeName,
    'personNumber': personNumber,
    'personName': personName,
    'productId': productId,
    'productName': productName,
    'categoryId': categoryId,
    'categoryName': categoryName,
    'qty': qty,
    'unitPrice': unitPrice,
    'notes': notes,
    'sendToKitchen': sendToKitchen,
    'affectsKitchenStock': affectsKitchenStock,
    'kitchenStockItemId': kitchenStockItemId,
    'kitchenStockItemName': kitchenStockItemName,
    'kitchenStockUnit': kitchenStockUnit,
    'stockConsumptionQty': stockConsumptionQty,
    'recipeItems': recipeItems,
    'appliedPlatformId': appliedPlatformId,
    'appliedPlatformName': appliedPlatformName,
    'priceSource': priceSource,
    'capturedAtMicros': capturedAtMicros,
  };

  factory LocalOrderCaptureLine.fromMap(Map<String, dynamic> data) {
    final schemaVersion = (data['schemaVersion'] as num?)?.toInt() ?? 0;
    if (schemaVersion != localOrderCaptureSchemaVersion) {
      throw FormatException('Unsupported local capture schema: $schemaVersion');
    }
    return LocalOrderCaptureLine(
      id: _string(data['id']),
      restaurantId: _string(data['restaurantId']),
      restaurantName: _string(data['restaurantName']),
      branchId: _string(data['branchId']),
      branchName: _string(data['branchName']),
      orderId: _string(data['orderId']),
      tableId: _string(data['tableId']),
      tableName: _string(data['tableName']),
      tableIds: _strings(data['tableIds']),
      tableNames: _strings(data['tableNames']),
      tableGroupLabel: _string(data['tableGroupLabel']),
      deviceUid: _string(data['deviceUid']),
      employeeId: _string(data['employeeId']),
      employeeName: _string(data['employeeName']),
      personNumber: _int(data['personNumber'], fallback: 1),
      personName: _string(data['personName']),
      productId: _string(data['productId']),
      productName: _string(data['productName']),
      categoryId: _string(data['categoryId']),
      categoryName: _string(data['categoryName'], fallback: 'General'),
      qty: _int(data['qty'], fallback: 1),
      unitPrice: _double(data['unitPrice']),
      notes: _string(data['notes']),
      sendToKitchen: data['sendToKitchen'] == true,
      affectsKitchenStock: data['affectsKitchenStock'] == true,
      kitchenStockItemId: _optionalString(data['kitchenStockItemId']),
      kitchenStockItemName: _optionalString(data['kitchenStockItemName']),
      kitchenStockUnit: _optionalString(data['kitchenStockUnit']),
      stockConsumptionQty: _optionalDouble(data['stockConsumptionQty']),
      recipeItems: _maps(data['recipeItems']),
      appliedPlatformId: _optionalString(data['appliedPlatformId']),
      appliedPlatformName: _optionalString(data['appliedPlatformName']),
      priceSource: _string(data['priceSource'], fallback: 'store'),
      capturedAtMicros: _int(data['capturedAtMicros']),
      schemaVersion: schemaVersion,
    );
  }

  String canonicalJson() => jsonEncode(toMap());
}

class LocalOrderCaptureSubmission {
  const LocalOrderCaptureSubmission({
    required this.id,
    required this.restaurantId,
    required this.branchId,
    required this.orderId,
    required this.payloadHash,
    required this.payloadJson,
    required this.lineIds,
    required this.sendToKitchen,
    required this.createdAtMicros,
    this.schemaVersion = localOrderCaptureSchemaVersion,
  });

  final String id;
  final String restaurantId;
  final String branchId;
  final String orderId;
  final String payloadHash;
  final String payloadJson;
  final List<String> lineIds;
  final bool sendToKitchen;
  final int createdAtMicros;
  final int schemaVersion;

  List<LocalOrderCaptureLine> get lines =>
      (_jsonDecode(payloadJson) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(LocalOrderCaptureLine.fromMap)
          .toList(growable: false);

  Map<String, dynamic> toMap() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'restaurantId': restaurantId,
    'branchId': branchId,
    'orderId': orderId,
    'payloadHash': payloadHash,
    'payloadJson': payloadJson,
    'lineIds': lineIds,
    'sendToKitchen': sendToKitchen,
    'createdAtMicros': createdAtMicros,
    'state': 'pending',
  };

  factory LocalOrderCaptureSubmission.fromMap(Map<String, dynamic> data) {
    final schemaVersion = (data['schemaVersion'] as num?)?.toInt() ?? 0;
    if (schemaVersion != localOrderCaptureSchemaVersion) {
      throw FormatException(
        'Unsupported local submission schema: $schemaVersion',
      );
    }
    return LocalOrderCaptureSubmission(
      id: _string(data['id']),
      restaurantId: _string(data['restaurantId']),
      branchId: _string(data['branchId']),
      orderId: _string(data['orderId']),
      payloadHash: _string(data['payloadHash']),
      payloadJson: _string(data['payloadJson']),
      lineIds: _strings(data['lineIds']),
      sendToKitchen: data['sendToKitchen'] == true,
      createdAtMicros: _int(data['createdAtMicros']),
      schemaVersion: schemaVersion,
    );
  }
}

String localCaptureLineId({
  required String restaurantId,
  required String branchId,
  required String orderId,
  required String deviceUid,
  required String employeeId,
  required int personNumber,
  required String productId,
  required String? appliedPlatformId,
}) {
  final identity = jsonEncode([
    restaurantId,
    branchId,
    orderId,
    deviceUid,
    employeeId,
    personNumber,
    productId,
    appliedPlatformId ?? '',
  ]);
  return 'lc_${sha256.convert(utf8.encode(identity))}';
}

String localCapturePayloadHash(Iterable<LocalOrderCaptureLine> lines) {
  final sorted = lines.toList()
    ..sort((a, b) {
      final time = a.capturedAtMicros.compareTo(b.capturedAtMicros);
      return time != 0 ? time : a.id.compareTo(b.id);
    });
  return sha256
      .convert(utf8.encode(jsonEncode(sorted.map((e) => e.toMap()).toList())))
      .toString();
}

Object? _jsonDecode(String value) => jsonDecode(value);
String _string(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;
String? _optionalString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
int _int(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : fallback;
double _double(Object? value) => value is num ? value.toDouble() : 0;
double? _optionalDouble(Object? value) =>
    value is num ? value.toDouble() : null;
List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];
List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];
