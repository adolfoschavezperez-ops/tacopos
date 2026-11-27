import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/kitchen_session.dart';
import '../../../models/kitchen_stock_item.dart';
import '../../../models/product.dart';
import '../../../services/taco_pos_repository.dart' show ProductStockOutRow;

class YieldProfileSummary {
  const YieldProfileSummary({
    required this.id,
    required this.name,
    required this.rawUnit,
    required this.yieldUnit,
    required this.yieldFactor,
  });

  final String id;
  final String name;
  final String rawUnit;
  final String yieldUnit;
  final double yieldFactor;

  factory YieldProfileSummary.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return YieldProfileSummary(
      id: doc.id,
      name: d['name'] as String? ?? d['ingredientName'] as String? ?? doc.id,
      rawUnit: d['rawUnit'] as String? ?? 'kg',
      yieldUnit: d['yieldUnit'] as String? ?? 'porcion',
      yieldFactor: (d['yieldFactor'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class InventoryDashboardData {
  const InventoryDashboardData({
    required this.stockItems,
    required this.sessions,
    required this.selectedSession,
    required this.sessionItems,
    required this.productsWithRecipes,
    required this.allProducts,
    required this.stockOuts,
    required this.yieldProfiles,
    required this.readCount,
  });

  final List<KitchenStockItem> stockItems;
  final List<KitchenSession> sessions;
  final KitchenSession? selectedSession;
  final List<KitchenSessionItem> sessionItems;
  final List<Product> productsWithRecipes;
  final List<Product> allProducts;
  final List<ProductStockOutRow> stockOuts;
  final List<YieldProfileSummary> yieldProfiles;
  final int readCount;

  int get activeStockOutsCount => stockOuts.where((s) => s.isActive).length;
}

class InventoryRepository {
  InventoryRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<InventoryDashboardData> loadInventory({
    required String restaurantId,
    required String startBusinessDate,
    required String endBusinessDate,
    String? branchId,
    String? selectedSessionId,
  }) async {
    final stockItemsQuery = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('kitchenStockItems')
        .orderBy('sortOrder')
        .limit(150);

    Query<Map<String, dynamic>> sessionsQuery = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('kitchenSessions')
        .where('businessDate', isGreaterThanOrEqualTo: startBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: endBusinessDate)
        .orderBy('businessDate', descending: true);

    Query<Map<String, dynamic>> stockOutsQuery = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('productStockOuts')
        .where('businessDate', isGreaterThanOrEqualTo: startBusinessDate)
        .where('businessDate', isLessThanOrEqualTo: endBusinessDate)
        .orderBy('businessDate', descending: true);

    if (branchId != null && branchId.isNotEmpty) {
      sessionsQuery = sessionsQuery.where('branchId', isEqualTo: branchId);
      stockOutsQuery = stockOutsQuery.where('branchId', isEqualTo: branchId);
    }

    final productsQuery = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('products')
        .limit(200);

    final yieldProfilesQuery = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('ingredientYieldProfiles')
        .limit(100);

    final results = await Future.wait([
      stockItemsQuery.get(),
      sessionsQuery.limit(60).get(),
      stockOutsQuery.limit(100).get(),
      productsQuery.get(),
      yieldProfilesQuery.get(),
    ]);

    final stockItems = results[0].docs
        .map(KitchenStockItem.fromDoc)
        .toList(growable: false);
    final sessions = results[1].docs
        .map(KitchenSession.fromDoc)
        .toList(growable: false);
    final stockOuts = results[2].docs
        .map(ProductStockOutRow.fromDoc)
        .toList(growable: false);
    final allProducts = results[3].docs
        .map(Product.fromDoc)
        .toList(growable: false);
    final products = allProducts
        .where((p) => p.affectsKitchenStock || p.recipeItems.isNotEmpty)
        .toList(growable: false);
    final yieldProfiles = results[4].docs
        .map(YieldProfileSummary.fromDoc)
        .toList(growable: false);

    KitchenSession? selectedSession;
    if (selectedSessionId != null && selectedSessionId.isNotEmpty) {
      for (final s in sessions) {
        if (s.id == selectedSessionId) {
          selectedSession = s;
          break;
        }
      }
    }
    selectedSession ??= sessions.isNotEmpty ? sessions.first : null;

    var sessionItems = const <KitchenSessionItem>[];
    var itemsRead = 0;
    if (selectedSession != null) {
      final itemsSnap = await _db
          .collection('restaurants')
          .doc(restaurantId)
          .collection('kitchenSessions')
          .doc(selectedSession.id)
          .collection('items')
          .limit(150)
          .get();
      itemsRead = itemsSnap.docs.length;
      sessionItems = itemsSnap.docs
          .map(KitchenSessionItem.fromDoc)
          .toList(growable: false);
    }

    final totalReads =
        results[0].docs.length +
        results[1].docs.length +
        results[2].docs.length +
        results[3].docs.length +
        results[4].docs.length +
        itemsRead;

    return InventoryDashboardData(
      stockItems: stockItems,
      sessions: sessions,
      selectedSession: selectedSession,
      sessionItems: sessionItems,
      productsWithRecipes: products,
      allProducts: allProducts,
      stockOuts: stockOuts,
      yieldProfiles: yieldProfiles,
      readCount: totalReads,
    );
  }

  Future<void> saveKitchenStockItem({
    required String restaurantId,
    String? itemId,
    required String name,
    required String category,
    required String unit,
    required bool active,
    required double optimalConsumptionPerSaleQty,
    String defaultSupplierName = '',
    String notes = '',
  }) async {
    final ref = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('kitchenStockItems');
    final isNew = itemId == null || itemId.trim().isEmpty;
    final docRef = isNew ? ref.doc() : ref.doc(itemId.trim());
    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'category': category.trim().isEmpty ? 'General' : category.trim(),
      'unit': unit.trim().isEmpty ? 'kg' : unit.trim(),
      'active': active,
      'optimalConsumptionPerSaleQty': optimalConsumptionPerSaleQty,
      'optimalConsumptionUnit': unit.trim().isEmpty ? 'kg' : unit.trim(),
      'affectsKitchenPerformance': true,
      'defaultSupplierName': defaultSupplierName.trim(),
      'notes': notes.trim(),
      if (isNew) 'sortOrder': 99,
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> registerAdditionalEntry({
    required String restaurantId,
    required String sessionId,
    required String itemId,
    required double addedQty,
  }) async {
    if (addedQty <= 0) {
      throw ArgumentError('Captura una cantidad adicional mayor a cero.');
    }
    final sessionRef = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('kitchenSessions')
        .doc(sessionId);
    final itemRef = sessionRef.collection('items').doc(itemId);

    await _db.runTransaction((tx) async {
      final sessionSnap = await tx.get(sessionRef);
      if (!sessionSnap.exists || !KitchenSession.fromDoc(sessionSnap).isOpen) {
        throw StateError('La sesión de cocina ya está cerrada.');
      }
      final itemSnap = await tx.get(itemRef);
      if (!itemSnap.exists) {
        throw StateError('El insumo no existe en esta sesión.');
      }
      final current = KitchenSessionItem.fromDoc(itemSnap);
      final nextAdditional = current.additionalEntriesQty + addedQty;
      final nextAvailable =
          current.previousRemainingQty + current.todayInputQty + nextAdditional;
      tx.update(itemRef, {
        'additionalEntriesQty': nextAdditional,
        'availableQty': nextAvailable,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> clearProductStockOut({
    required String restaurantId,
    required String stockOutId,
    required String reason,
    required String employeeId,
    required String employeeName,
  }) async {
    await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('productStockOuts')
        .doc(stockOutId)
        .update({
          'status': 'cleared',
          'clearedAt': FieldValue.serverTimestamp(),
          'clearedByEmployeeId': employeeId,
          'clearedByEmployeeName': employeeName,
          'clearedReason': reason.trim(),
        });
  }

  Future<void> saveYieldProfile({
    required String restaurantId,
    String? profileId,
    required String name,
    required String rawUnit,
    required String yieldUnit,
    required double yieldFactor,
  }) async {
    final ref = _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('ingredientYieldProfiles');
    final isNew = profileId == null || profileId.trim().isEmpty;
    final docRef = isNew ? ref.doc() : ref.doc(profileId.trim());
    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'rawUnit': rawUnit.trim(),
      'yieldUnit': yieldUnit.trim(),
      'yieldFactor': yieldFactor > 0 ? yieldFactor : 1.0,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
