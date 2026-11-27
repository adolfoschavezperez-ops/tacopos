import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/branch.dart';
import '../../../models/kitchen_stock_item.dart';
import '../../../models/order_platform.dart';
import '../../../models/pos_table.dart';
import '../../../models/product.dart';
import '../../../models/product_category.dart';
import '../../../models/product_recipe_item.dart';
import '../employees/employees_repository.dart';

class GeneralDiscountConfig {
  const GeneralDiscountConfig({
    this.active = false,
    this.name = 'Descuento general',
    this.percent = 0.0,
    this.description = '',
    this.branchId = 'all',
  });

  final bool active;
  final String name;
  final double percent;
  final String description;
  final String branchId;

  factory GeneralDiscountConfig.fromMap(Map<String, dynamic>? d) {
    return GeneralDiscountConfig(
      active: d?['active'] as bool? ?? false,
      name: (d?['name'] ?? 'Descuento general').toString(),
      percent: (d?['percent'] as num?)?.toDouble() ?? 0.0,
      description: (d?['description'] ?? '').toString(),
      branchId: (d?['branchId'] ?? 'all').toString(),
    );
  }
}

class AppUpdateConfig {
  const AppUpdateConfig({
    this.active = false,
    this.minimumSupportedVersionCode = 1,
    this.recommendedVersionCode = 1,
    this.forceUpdate = false,
    this.updateMessage = '',
  });

  final bool active;
  final int minimumSupportedVersionCode;
  final int recommendedVersionCode;
  final bool forceUpdate;
  final String updateMessage;

  factory AppUpdateConfig.fromMap(Map<String, dynamic>? d) {
    return AppUpdateConfig(
      active: d?['active'] as bool? ?? false,
      minimumSupportedVersionCode:
          (d?['minimumSupportedVersionCode'] as num?)?.toInt() ?? 1,
      recommendedVersionCode:
          (d?['recommendedVersionCode'] as num?)?.toInt() ?? 1,
      forceUpdate: d?['forceUpdate'] as bool? ?? false,
      updateMessage: (d?['updateMessage'] ?? '').toString(),
    );
  }
}

class SettingsBundle {
  const SettingsBundle({
    required this.restaurantName,
    required this.products,
    required this.categories,
    required this.branches,
    required this.tables,
    required this.platforms,
    required this.stockItems,
    required this.devices,
    required this.discountConfig,
    required this.appUpdateConfig,
    required this.discountUsages,
    required this.readCount,
  });

  final String restaurantName;
  final List<Product> products;
  final List<ProductCategory> categories;
  final List<Branch> branches;
  final List<PosTable> tables;
  final List<OrderPlatform> platforms;
  final List<KitchenStockItem> stockItems;
  final List<DeviceSummaryRow> devices;
  final GeneralDiscountConfig discountConfig;
  final AppUpdateConfig appUpdateConfig;
  final List<EmployeeDiscountUsageRow> discountUsages;
  final int readCount;
}

class SettingsRepository {
  SettingsRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<SettingsBundle> loadAll({
    required String restaurantId,
    String? branchId,
  }) async {
    final restRef = _db.collection('restaurants').doc(restaurantId);
    final snaps = await Future.wait([
      restRef.get(),
      restRef.collection('products').limit(300).get(),
      restRef.collection('productCategories').orderBy('sortOrder').limit(100).get(),
      restRef.collection('branches').orderBy('sortOrder').limit(50).get(),
      restRef.collection('tables').orderBy('sortOrder').limit(200).get(),
      restRef.collection('orderPlatforms').orderBy('sortOrder').limit(50).get(),
      restRef.collection('kitchenStockItems').orderBy('sortOrder').limit(150).get(),
      restRef.collection('devices').limit(100).get(),
      restRef.collection('settings').doc('discounts').get(),
      restRef.collection('settings').doc('appUpdates').get(),
      restRef
          .collection('discountUsage')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get(),
    ]);

    var readCount = 0;
    for (final s in snaps) {
      readCount += s is QuerySnapshot ? s.docs.length : 1;
    }

    final restDoc = snaps[0] as DocumentSnapshot<Map<String, dynamic>>;
    final restaurantName =
        (restDoc.data()?['name'] ?? restaurantId).toString();

    final products = (snaps[1] as QuerySnapshot<Map<String, dynamic>>).docs
        .map(Product.fromDoc)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final categories = (snaps[2] as QuerySnapshot<Map<String, dynamic>>).docs
        .map(ProductCategory.fromDoc)
        .toList(growable: false);

    final branches = (snaps[3] as QuerySnapshot<Map<String, dynamic>>).docs
        .map(Branch.fromDoc)
        .toList(growable: false);

    final tables = (snaps[4] as QuerySnapshot<Map<String, dynamic>>).docs
        .map(PosTable.fromDoc)
        .where((t) => branchId == null || branchId.isEmpty || t.branchId == branchId)
        .toList(growable: false);

    final platforms = (snaps[5] as QuerySnapshot<Map<String, dynamic>>).docs
        .map(OrderPlatform.fromDoc)
        .toList(growable: false);

    final stockItems = (snaps[6] as QuerySnapshot<Map<String, dynamic>>).docs
        .map(KitchenStockItem.fromDoc)
        .toList(growable: false);

    final devices = (snaps[7] as QuerySnapshot<Map<String, dynamic>>).docs
        .map(DeviceSummaryRow.fromDoc)
        .where((d) => branchId == null || branchId.isEmpty || d.branchName.isEmpty || true)
        .toList(growable: false);

    final discSnap = snaps[8] as DocumentSnapshot<Map<String, dynamic>>;
    final appSnap = snaps[9] as DocumentSnapshot<Map<String, dynamic>>;
    final usages = (snaps[10] as QuerySnapshot<Map<String, dynamic>>).docs
        .map(EmployeeDiscountUsageRow.fromDoc)
        .toList(growable: false);

    return SettingsBundle(
      restaurantName: restaurantName,
      products: products,
      categories: categories,
      branches: branches,
      tables: tables,
      platforms: platforms,
      stockItems: stockItems,
      devices: devices,
      discountConfig: GeneralDiscountConfig.fromMap(discSnap.data()),
      appUpdateConfig: AppUpdateConfig.fromMap(appSnap.data()),
      discountUsages: usages,
      readCount: readCount,
    );
  }

  String _slug(String raw) => raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  Future<void> _log({
    required DocumentReference<Map<String, dynamic>> restRef,
    required String type,
    required String targetId,
    required String note,
    required String employeeId,
    required String employeeName,
    String branchId = '',
  }) async {
    await restRef.collection('activityLog').add({
      'type': type,
      'restaurantId': restRef.id,
      if (branchId.isNotEmpty) 'branchId': branchId,
      'targetId': targetId,
      'note': note,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'actionSource': 'backoffice_v2',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Preserves 100% of Android's `Product` fields and legacy stock-link fields.
  Future<void> saveProduct({
    required String restaurantId,
    String? productId,
    required String name,
    required String categoryId,
    required String categoryName,
    required double price,
    double? unitCost,
    required Map<String, double> platformPrices,
    required bool active,
    required bool sendToKitchen,
    required bool affectsKitchenStock,
    required List<ProductRecipeItem> recipeItems,
    required int sortOrder,
    required String actorId,
    required String actorName,
  }) async {
    final restRef = _db.collection('restaurants').doc(restaurantId);
    final col = restRef.collection('products');
    final isNew = productId == null || productId.trim().isEmpty;
    final ref = isNew ? col.doc() : col.doc(productId.trim());
    final cleanPlatforms = <String, double>{
      for (final e in platformPrices.entries)
        if (e.key != 'en_persona' && e.value > 0) e.key: e.value,
    };
    final primary = affectsKitchenStock && recipeItems.isNotEmpty
        ? recipeItems.first
        : null;

    await ref.set({
      'id': ref.id,
      'name': name.trim(),
      'categoryId': categoryId.isNotEmpty ? categoryId : _slug(categoryName),
      'categoryName': categoryName.trim(),
      'category': categoryName.trim(),
      'price': price,
      'unitCost': unitCost,
      'platformPrices': cleanPlatforms,
      'active': active,
      'sendToKitchen': sendToKitchen,
      'affectsKitchenStock': affectsKitchenStock,
      'recipeItems': affectsKitchenStock
          ? recipeItems.map((r) => r.toMap()).toList(growable: false)
          : const <Map<String, dynamic>>[],
      'kitchenStockItemId': primary?.kitchenStockItemId,
      'kitchenStockItemName': primary?.kitchenStockItemName,
      'kitchenStockUnit': primary?.kitchenStockUnit,
      'stockConsumptionQty': primary?.consumptionFactor,
      'kitchenConsumptionFactor': primary?.consumptionFactor,
      'sortOrder': sortOrder,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _log(
      restRef: restRef,
      type: isNew ? 'product_created' : 'product_updated',
      targetId: ref.id,
      note: 'Producto: ${name.trim()} · Precio: \$$price · Activo: $active',
      employeeId: actorId,
      employeeName: actorName,
    );
  }

  Future<void> toggleProduct({
    required String restaurantId,
    required Product product,
    required String actorId,
    required String actorName,
  }) async {
    final restRef = _db.collection('restaurants').doc(restaurantId);
    final next = !product.active;
    await restRef.collection('products').doc(product.id).update({
      'active': next,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _log(
      restRef: restRef,
      type: 'product_toggled',
      targetId: product.id,
      note: 'Producto: ${product.name} · Activo: $next',
      employeeId: actorId,
      employeeName: actorName,
    );
  }

  Future<void> saveProductCategory({
    required String restaurantId,
    String? categoryId,
    required String name,
    required int sortOrder,
    required String colorHex,
    required bool active,
    required String actorId,
    required String actorName,
  }) async {
    final restRef = _db.collection('restaurants').doc(restaurantId);
    final isNew = categoryId == null || categoryId.trim().isEmpty;
    final id = isNew ? _slug(name) : categoryId.trim();
    await restRef.collection('productCategories').doc(id).set({
      'id': id,
      'name': name.trim(),
      'normalizedName': name.trim().toLowerCase(),
      'active': active,
      'sortOrder': sortOrder,
      'colorHex': colorHex.trim(),
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _log(
      restRef: restRef,
      type: isNew ? 'category_created' : 'category_updated',
      targetId: id,
      note: 'Categoría: ${name.trim()}',
      employeeId: actorId,
      employeeName: actorName,
    );
  }

  Future<void> saveBranch({
    required String restaurantId,
    required String restaurantName,
    String? branchId,
    required String name,
    required String address,
    required String phone,
    required String timezone,
    required int sortOrder,
    required bool active,
    required String actorId,
    required String actorName,
  }) async {
    final restRef = _db.collection('restaurants').doc(restaurantId);
    final isNew = branchId == null || branchId.trim().isEmpty;
    final id = isNew ? _slug(name) : branchId.trim();
    await restRef.collection('branches').doc(id).set({
      'id': id,
      'restaurantId': restaurantId,
      'restaurantName': restaurantName,
      'name': name.trim(),
      'normalizedName': name.trim().toLowerCase(),
      'address': address.trim(),
      'phone': phone.trim(),
      'timezone': timezone.trim().isNotEmpty
          ? timezone.trim()
          : 'America/Mexico_City',
      'sortOrder': sortOrder,
      'active': active,
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _log(
      restRef: restRef,
      type: isNew ? 'branch_created' : 'branch_updated',
      targetId: id,
      branchId: id,
      note: 'Sucursal: ${name.trim()} · Activa: $active',
      employeeId: actorId,
      employeeName: actorName,
    );
  }

  Future<void> saveTable({
    required String restaurantId,
    required String restaurantName,
    required String branchId,
    required String branchName,
    String? tableId,
    required String name,
    required String type,
    required int sortOrder,
    required bool active,
    required String actorId,
    required String actorName,
  }) async {
    final restRef = _db.collection('restaurants').doc(restaurantId);
    final col = restRef.collection('tables');
    final isNew = tableId == null || tableId.trim().isEmpty;
    final ref = isNew ? col.doc() : col.doc(tableId.trim());
    await ref.set({
      'id': ref.id,
      'name': name.trim(),
      'type': type == 'takeout_entry' ? 'takeout_entry' : 'table',
      'restaurantId': restaurantId,
      'restaurantName': restaurantName,
      'branchId': branchId,
      'branchName': branchName,
      'active': active,
      'sortOrder': sortOrder,
      if (isNew) 'status': 'available',
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _log(
      restRef: restRef,
      type: isNew ? 'table_created' : 'table_updated',
      targetId: ref.id,
      branchId: branchId,
      note: 'Mesa: ${name.trim()} · Sucursal: $branchName',
      employeeId: actorId,
      employeeName: actorName,
    );
  }

  Future<void> saveOrderPlatform({
    required String restaurantId,
    String? platformId,
    required String name,
    required int sortOrder,
    required bool active,
    required String actorId,
    required String actorName,
  }) async {
    final restRef = _db.collection('restaurants').doc(restaurantId);
    final isNew = platformId == null || platformId.trim().isEmpty;
    final id = isNew ? _slug(name) : platformId.trim();
    await restRef.collection('orderPlatforms').doc(id).set({
      'id': id,
      'name': name.trim(),
      'active': active,
      'sortOrder': sortOrder,
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _log(
      restRef: restRef,
      type: isNew ? 'platform_created' : 'platform_updated',
      targetId: id,
      note: 'Plataforma: ${name.trim()} · Activa: $active',
      employeeId: actorId,
      employeeName: actorName,
    );
  }

  Future<void> saveDiscountSettings({
    required String restaurantId,
    required GeneralDiscountConfig config,
    required String actorId,
    required String actorName,
  }) async {
    final restRef = _db.collection('restaurants').doc(restaurantId);
    await restRef.collection('settings').doc('discounts').set({
      'active': config.active,
      'name': config.name.trim(),
      'percent': config.percent.clamp(0.0, 100.0),
      'description': config.description.trim(),
      'branchId': config.branchId,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmployeeId': actorId,
      'updatedByEmployeeName': actorName,
    }, SetOptions(merge: true));
    await _log(
      restRef: restRef,
      type: 'discount_settings_updated',
      targetId: 'discounts',
      note:
          'Descuento general: ${config.name} (${config.percent}%) · Activo: ${config.active}',
      employeeId: actorId,
      employeeName: actorName,
    );
  }

  /// Saves remote Android app update thresholds (`settings/appUpdates`).
  /// Restricted to SuperAdmin with explicit confirmation and audit logging.
  Future<void> saveAppUpdateSettings({
    required String restaurantId,
    required AppUpdateConfig config,
    required String actorId,
    required String actorName,
  }) async {
    final restRef = _db.collection('restaurants').doc(restaurantId);
    await restRef.collection('settings').doc('appUpdates').set({
      'active': config.active,
      'minimumSupportedVersionCode': config.minimumSupportedVersionCode,
      'recommendedVersionCode': config.recommendedVersionCode,
      'forceUpdate': config.forceUpdate,
      'updateMessage': config.updateMessage.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmployeeId': actorId,
      'updatedByEmployeeName': actorName,
    }, SetOptions(merge: true));
    await _log(
      restRef: restRef,
      type: 'app_updates_settings_updated',
      targetId: 'appUpdates',
      note:
          'Versión min: ${config.minimumSupportedVersionCode} · Forzar: ${config.forceUpdate}',
      employeeId: actorId,
      employeeName: actorName,
    );
  }
}
