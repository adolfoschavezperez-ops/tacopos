import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/kitchen_session.dart';
import '../../../models/kitchen_stock_item.dart';
import '../../../models/product.dart';
import '../../../services/taco_pos_repository.dart' show ProductStockOutRow;

class InventoryDashboardData {
  const InventoryDashboardData({
    required this.stockItems,
    required this.sessions,
    required this.selectedSession,
    required this.sessionItems,
    required this.productsWithRecipes,
    required this.stockOuts,
    required this.readCount,
  });

  final List<KitchenStockItem> stockItems;
  final List<KitchenSession> sessions;
  final KitchenSession? selectedSession;
  final List<KitchenSessionItem> sessionItems;
  final List<Product> productsWithRecipes;
  final List<ProductStockOutRow> stockOuts;
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

    final results = await Future.wait([
      stockItemsQuery.get(),
      sessionsQuery.limit(60).get(),
      stockOutsQuery.limit(100).get(),
      productsQuery.get(),
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
    final products = results[3].docs
        .map(Product.fromDoc)
        .where((p) => p.affectsKitchenStock || p.recipeItems.isNotEmpty)
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
        itemsRead;

    return InventoryDashboardData(
      stockItems: stockItems,
      sessions: sessions,
      selectedSession: selectedSession,
      sessionItems: sessionItems,
      productsWithRecipes: products,
      stockOuts: stockOuts,
      readCount: totalReads,
    );
  }
}
