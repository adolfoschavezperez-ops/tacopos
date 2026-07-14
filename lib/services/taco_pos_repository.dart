import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/constants/app_constants.dart';
import '../models/cash_session.dart';
import '../models/cash_withdrawal_request.dart';
import '../models/active_session.dart';
import '../models/activity_event.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import '../models/kitchen_session.dart';
import '../models/kitchen_stock_item.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../models/order_platform.dart';
import '../models/payment.dart';
import '../models/pos_table.dart';
import '../models/product.dart';
import '../models/product_category.dart';
import '../models/product_recipe_item.dart';
import '../models/restaurant.dart';
import '../utils/category_utils.dart';
import 'app_session.dart';

class KitchenOrderBundle {
  const KitchenOrderBundle({required this.order, required this.items});

  final PosOrder order;
  final List<OrderItem> items;

  int get personCount => items.map((item) => item.personNumber).toSet().length;

  String get personLabel {
    final namesByPerson = <int, String>{};
    for (final item in items) {
      namesByPerson.putIfAbsent(item.personNumber, () => item.personName);
    }
    final names = namesByPerson.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return names.map((entry) => entry.value).join(', ');
  }

  DateTime? get firstSentToKitchenAt {
    return items
        .map((item) => item.sentToKitchenAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (min, date) => min == null || date.isBefore(min) ? date : min,
        );
  }

  String get shortSummary {
    final counts = <String, int>{};
    for (final item in items) {
      counts[item.productName] = (counts[item.productName] ?? 0) + item.qty;
    }

    return counts.entries
        .take(3)
        .map((entry) => '${entry.value} ${entry.key}')
        .join(' · ');
  }

  List<MapEntry<String, double>> get ingredientSummary {
    final counts = <String, double>{};
    for (final item in items) {
      if (item.recipeItems.isNotEmpty) {
        final recipeItem = item.recipeItems.first;
        final key = recipeItem.kitchenStockItemName.trim().isNotEmpty
            ? recipeItem.kitchenStockItemName.trim()
            : recipeItem.kitchenStockItemId;
        counts[key] =
            (counts[key] ?? 0) + item.qty * recipeItem.consumptionFactor;
        continue;
      }
      final key =
          (item.kitchenStockItemName?.trim().isNotEmpty == true
                  ? item.kitchenStockItemName
                  : item.productName)!
              .trim();
      counts[key] = (counts[key] ?? 0) + item.qty;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }
}

class PaymentResult {
  const PaymentResult({required this.allPaid});

  final bool allPaid;
}

class BranchSummary {
  const BranchSummary({
    required this.tableCount,
    required this.openOrderCount,
    required this.cashOpen,
    required this.employeeAccessCount,
  });

  final int tableCount;
  final int openOrderCount;
  final bool cashOpen;
  final int employeeAccessCount;
}

class CashPaymentDetails {
  const CashPaymentDetails({
    required this.receivedAmount,
    required this.changeAmount,
  });

  final double receivedAmount;
  final double changeAmount;
}

class KitchenCloseInput {
  const KitchenCloseInput({
    required this.finalRemainingQty,
    required this.wasteQty,
    required this.notes,
  });

  final double finalRemainingQty;
  final double wasteQty;
  final String notes;
}

class KitchenOpeningInput {
  const KitchenOpeningInput({
    required this.item,
    required this.previousRemainingQty,
    required this.todayInputQty,
  });

  final KitchenStockItem item;
  final double previousRemainingQty;
  final double todayInputQty;
}

class CashCloseBlockers {
  const CashCloseBlockers({
    required this.openTableCount,
    required this.openTakeoutCount,
    required this.pendingKitchenItemCount,
    required this.pendingPaymentCount,
    required this.kitchenNotClosed,
    required this.kitchenCloseIncomplete,
  });

  final int openTableCount;
  final int openTakeoutCount;
  final int pendingKitchenItemCount;
  final int pendingPaymentCount;
  final bool kitchenNotClosed;
  final bool kitchenCloseIncomplete;

  bool get canClose =>
      openTableCount == 0 &&
      openTakeoutCount == 0 &&
      pendingKitchenItemCount == 0 &&
      pendingPaymentCount == 0 &&
      !kitchenNotClosed &&
      !kitchenCloseIncomplete;

  String get message {
    if (kitchenNotClosed) {
      return 'No puedes cerrar caja. Primero debes cerrar cocina.';
    }
    if (kitchenCloseIncomplete) {
      return 'No puedes cerrar caja. El cierre de cocina esta incompleto.';
    }
    return 'No puedes cerrar caja. Hay mesas, pedidos o cocina pendientes.';
  }

  String get detail {
    return [
      '$openTableCount mesas abiertas',
      '$openTakeoutCount pedidos para llevar abiertos',
      '$pendingKitchenItemCount productos pendientes en cocina',
      '$pendingPaymentCount cuentas pendientes de cobrar',
    ].join('\n');
  }
}

class KitchenYieldReportRow {
  const KitchenYieldReportRow({
    required this.item,
    required this.currentItem,
    required this.previousRemainingQty,
    required this.initialInputQty,
    required this.additionalEntriesQty,
    required this.availableQty,
    required this.finalRemainingQty,
    required this.wasteQty,
    required this.usedQty,
    required this.usefulConsumedQty,
    required this.soldQty,
    required this.currentYield,
    required this.averageYield,
  });

  final KitchenStockItem item;
  final KitchenSessionItem? currentItem;
  final double previousRemainingQty;
  final double initialInputQty;
  final double additionalEntriesQty;
  final double availableQty;
  final double finalRemainingQty;
  final double wasteQty;
  final double usedQty;
  final double usefulConsumedQty;
  final double soldQty;
  final double currentYield;
  final double averageYield;

  double get optimalYield => item.optimalConsumptionPerSaleQty;
  bool get hasSales => soldQty > 0;
  bool get hasConsumption => usefulConsumedQty > 0;
}

class TacoPosRepository {
  TacoPosRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  static const cardSurchargeRate = 0.04;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> get _restaurantRef =>
      _db.collection('restaurants').doc(AppConstants.restaurantId);

  CollectionReference<Map<String, dynamic>> get _tablesRef =>
      _restaurantRef.collection('tables');

  CollectionReference<Map<String, dynamic>> get _productsRef =>
      _restaurantRef.collection('products');

  CollectionReference<Map<String, dynamic>> get _productCategoriesRef =>
      _restaurantRef.collection('productCategories');

  CollectionReference<Map<String, dynamic>> get _employeesRef =>
      _restaurantRef.collection('employees');
  CollectionReference<Map<String, dynamic>> get _activeSessionsRef =>
      _restaurantRef.collection('activeSessions');

  CollectionReference<Map<String, dynamic>> get _platformsRef =>
      _restaurantRef.collection('orderPlatforms');

  CollectionReference<Map<String, dynamic>> get _ordersRef =>
      _restaurantRef.collection('orders');

  CollectionReference<Map<String, dynamic>> get _cashSessionsRef =>
      _restaurantRef.collection('cashSessions');

  CollectionReference<Map<String, dynamic>> get _cashWithdrawalRequestsRef =>
      _restaurantRef.collection('cashWithdrawalRequests');

  CollectionReference<Map<String, dynamic>> get _kitchenStockItemsRef =>
      _restaurantRef.collection('kitchenStockItems');

  CollectionReference<Map<String, dynamic>> get _kitchenSessionsRef =>
      _restaurantRef.collection('kitchenSessions');

  CollectionReference<Map<String, dynamic>> get _branchesRef =>
      _restaurantRef.collection('branches');

  Map<String, Object?> get _currentBranchFields {
    final session = AppSession.instance;
    return {
      'restaurantId': session.currentRestaurantId,
      'restaurantName': session.currentRestaurantName,
      'branchId': session.currentBranchId,
      'branchName': session.currentBranchName,
    };
  }

  bool _matchesCurrentBranch(String? branchId) {
    return _matchesBranch(branchId, AppSession.instance.currentBranchId);
  }

  bool _matchesBranch(String? branchId, String selectedBranchId) {
    final cleanBranchId = branchId?.trim();
    if (cleanBranchId == null || cleanBranchId.isEmpty) {
      return selectedBranchId == AppConstants.defaultBranchId;
    }
    return cleanBranchId == selectedBranchId;
  }

  List<T> _filterCurrentBranch<T>(
    Iterable<T> items,
    String? Function(T item) branchId,
  ) {
    return items
        .where((item) => _matchesCurrentBranch(branchId(item)))
        .toList();
  }

  Stream<List<Restaurant>> watchRestaurants({bool activeOnly = true}) {
    return _db.collection('restaurants').snapshots().map((snapshot) {
      final restaurants = snapshot.docs.map(Restaurant.fromDoc).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return activeOnly
          ? restaurants.where((restaurant) => restaurant.active).toList()
          : restaurants;
    });
  }

  Stream<List<Branch>> watchBranches({bool activeOnly = false}) {
    return _branchesRef.snapshots().map((snapshot) {
      final branches =
          snapshot.docs
              .map(
                (doc) => Branch.fromDoc(
                  doc,
                  restaurantId: AppConstants.restaurantId,
                  restaurantName: AppConstants.restaurantName,
                ),
              )
              .toList()
            ..sort((a, b) {
              final sortCompare = a.sortOrder.compareTo(b.sortOrder);
              return sortCompare != 0 ? sortCompare : a.name.compareTo(b.name);
            });
      return activeOnly
          ? branches.where((branch) => branch.active).toList()
          : branches;
    });
  }

  Future<List<Branch>> getBranchesOnce({bool activeOnly = true}) async {
    final snapshot = await _branchesRef.get();
    final branches =
        snapshot.docs
            .map(
              (doc) => Branch.fromDoc(
                doc,
                restaurantId: AppConstants.restaurantId,
                restaurantName: AppConstants.restaurantName,
              ),
            )
            .toList()
          ..sort((a, b) {
            final sortCompare = a.sortOrder.compareTo(b.sortOrder);
            return sortCompare != 0 ? sortCompare : a.name.compareTo(b.name);
          });
    return activeOnly
        ? branches.where((branch) => branch.active).toList()
        : branches;
  }

  Future<List<Branch>> getAccessibleBranches(Employee employee) async {
    await ensureDefaultBranch();
    final branches = await getBranchesOnce(activeOnly: true);
    if (employee.hasAdminAccess) {
      return branches.isEmpty ? const [Branch.defaultBranch] : branches;
    }
    final allowedIds = employee.effectiveBranchAccess
        .where((access) => access.active)
        .map((access) => access.branchId)
        .toSet();
    final allowed = branches
        .where((branch) => allowedIds.contains(branch.id))
        .toList();
    return allowed.isEmpty ? const [Branch.defaultBranch] : allowed;
  }

  Future<void> ensureDefaultBranch() async {
    final batch = _db.batch();
    batch.set(_restaurantRef, {
      'name': AppConstants.restaurantName,
      'active': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(_branchesRef.doc(AppConstants.defaultBranchId), {
      'id': AppConstants.defaultBranchId,
      'restaurantId': AppConstants.restaurantId,
      'restaurantName': AppConstants.restaurantName,
      'name': AppConstants.defaultBranchName,
      'normalizedName': AppConstants.defaultBranchId,
      'active': true,
      'sortOrder': 1,
      'timezone': AppConstants.defaultTimezone,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> saveBranch({
    String? branchId,
    required String name,
    required bool active,
    required int sortOrder,
    String address = '',
    String phone = '',
  }) async {
    _requireAdminPermission(
      _canManageBranches(),
      'No tienes permiso para administrar sucursales.',
    );
    final normalized = normalizeBranchName(name);
    final id = (branchId == null || branchId.trim().isEmpty)
        ? normalized
        : branchId.trim();
    final docRef = _branchesRef.doc(id);
    await docRef.set({
      'id': id,
      'restaurantId': AppConstants.restaurantId,
      'restaurantName': AppConstants.restaurantName,
      'name': name.trim(),
      'normalizedName': normalized,
      'active': active,
      'sortOrder': sortOrder,
      'address': address.trim(),
      'phone': phone.trim(),
      'timezone': AppConstants.defaultTimezone,
      if (branchId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleBranch(Branch branch) async {
    _requireAdminPermission(
      _canManageBranches(),
      'No tienes permiso para administrar sucursales.',
    );
    await _branchesRef.doc(branch.id).update({
      'active': !branch.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<BranchSummary> branchSummary(Branch branch) async {
    final tablesSnapshot = await _tablesRef.get();
    final ordersSnapshot = await _ordersRef.get();
    final cashSnapshot = await _cashSessionsRef.get();
    final employeesSnapshot = await _employeesRef.get();
    final tableCount = tablesSnapshot.docs
        .map(PosTable.fromDoc)
        .where((table) => _matchesBranch(table.branchId, branch.id))
        .length;
    final openOrderCount = ordersSnapshot.docs
        .map(PosOrder.fromDoc)
        .where(
          (order) =>
              _matchesBranch(order.branchId, branch.id) && isActiveOrder(order),
        )
        .length;
    final cashOpen = cashSnapshot.docs
        .map(CashSession.fromDoc)
        .any(
          (session) =>
              _matchesBranch(session.branchId, branch.id) && session.isOpen,
        );
    final employeeAccessCount = employeesSnapshot.docs
        .map(Employee.fromDoc)
        .where(
          (employee) =>
              employee.isSuperAdmin ||
              employee.effectiveBranchAccess.any(
                (access) => access.active && access.branchId == branch.id,
              ),
        )
        .length;
    return BranchSummary(
      tableCount: tableCount,
      openOrderCount: openOrderCount,
      cashOpen: cashOpen,
      employeeAccessCount: employeeAccessCount,
    );
  }

  Future<int> countDefaultBranchBackfillPending() async {
    _requireAdminPermission(
      _canManageBranches(),
      'No tienes permiso para revisar datos de sucursales.',
    );
    var pending = 0;

    bool needsBranch(DocumentSnapshot<Map<String, dynamic>> doc) {
      final data = doc.data() ?? {};
      final branchId = data['branchId']?.toString().trim();
      return branchId == null || branchId.isEmpty;
    }

    for (final collectionName in [
      'tables',
      'cashSessions',
      'cashWithdrawalRequests',
      'kitchenSessions',
      'activeSessions',
      'activityLog',
    ]) {
      final snapshot = await _restaurantRef.collection(collectionName).get();
      pending += snapshot.docs.where(needsBranch).length;
    }

    final ordersSnapshot = await _ordersRef.get();
    for (final orderDoc in ordersSnapshot.docs) {
      if (needsBranch(orderDoc)) pending++;

      final itemSnapshot = await orderDoc.reference.collection('items').get();
      pending += itemSnapshot.docs.where(needsBranch).length;

      final paymentSnapshot = await orderDoc.reference
          .collection('payments')
          .get();
      pending += paymentSnapshot.docs.where(needsBranch).length;
    }

    return pending;
  }

  Future<int> backfillDefaultBranch() async {
    _requireAdminPermission(
      _canManageBranches(),
      'No tienes permiso para preparar datos de sucursales.',
    );
    await ensureDefaultBranch();
    var updated = 0;
    var batch = _db.batch();
    var batchWrites = 0;

    Future<void> commitIfNeeded({bool force = false}) async {
      if (batchWrites == 0 || (!force && batchWrites < 450)) return;
      await batch.commit();
      batch = _db.batch();
      batchWrites = 0;
    }

    void setBranchIfMissing(
      DocumentSnapshot<Map<String, dynamic>> doc, {
      Map<String, Object?> extra = const {},
    }) {
      final data = doc.data() ?? {};
      final branchId = data['branchId']?.toString().trim();
      if (branchId != null && branchId.isNotEmpty) {
        return;
      }
      batch.set(doc.reference, {
        'restaurantId': AppConstants.restaurantId,
        'restaurantName': AppConstants.restaurantName,
        'branchId': AppConstants.defaultBranchId,
        'branchName': AppConstants.defaultBranchName,
        ...extra,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      updated++;
      batchWrites++;
    }

    for (final collectionName in [
      'tables',
      'cashSessions',
      'cashWithdrawalRequests',
      'kitchenSessions',
      'activeSessions',
      'activityLog',
    ]) {
      final snapshot = await _restaurantRef.collection(collectionName).get();
      for (final doc in snapshot.docs) {
        setBranchIfMissing(doc);
        await commitIfNeeded();
      }
    }

    final ordersSnapshot = await _ordersRef.get();
    for (final orderDoc in ordersSnapshot.docs) {
      setBranchIfMissing(orderDoc);
      await commitIfNeeded();

      final itemSnapshot = await orderDoc.reference.collection('items').get();
      for (final itemDoc in itemSnapshot.docs) {
        setBranchIfMissing(itemDoc);
        await commitIfNeeded();
      }

      final paymentSnapshot = await orderDoc.reference
          .collection('payments')
          .get();
      for (final paymentDoc in paymentSnapshot.docs) {
        setBranchIfMissing(paymentDoc);
        await commitIfNeeded();
      }
    }

    await commitIfNeeded(force: true);
    return updated;
  }

  Stream<List<PosTable>> watchTables({bool activeOnly = true}) {
    return _tablesRef.snapshots().map((snapshot) {
      final tables = _filterCurrentBranch(
        snapshot.docs.map(PosTable.fromDoc),
        (table) => table.branchId,
      )..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return activeOnly
          ? tables.where((table) => table.active).toList()
          : tables;
    });
  }

  Stream<List<OrderPlatform>> watchOrderPlatforms({bool activeOnly = true}) {
    return _platformsRef.snapshots().map((snapshot) {
      final platforms = snapshot.docs.map(OrderPlatform.fromDoc).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return activeOnly
          ? platforms.where((platform) => platform.active).toList()
          : platforms;
    });
  }

  Future<void> ensureDefaultOrderPlatforms() async {
    final snapshot = await _platformsRef.limit(1).get();
    if (snapshot.docs.isNotEmpty) {
      return;
    }

    final batch = _db.batch();
    const defaults = [
      {'id': 'en_persona', 'name': 'En persona', 'sortOrder': 1},
      {'id': 'didi', 'name': 'DiDi', 'sortOrder': 2},
      {'id': 'uber', 'name': 'Uber', 'sortOrder': 3},
      {'id': 'rappi', 'name': 'Rappi', 'sortOrder': 4},
    ];

    for (final platform in defaults) {
      final id = platform['id']! as String;
      batch.set(_platformsRef.doc(id), {
        ...platform,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Stream<List<ProductCategory>> watchProductCategories({
    bool activeOnly = false,
  }) {
    return _productCategoriesRef.snapshots().map((snapshot) {
      final categories = snapshot.docs.map(ProductCategory.fromDoc).toList()
        ..sort((a, b) {
          final sortCompare = a.sortOrder.compareTo(b.sortOrder);
          return sortCompare != 0 ? sortCompare : a.name.compareTo(b.name);
        });
      return activeOnly
          ? categories.where((category) => category.active).toList()
          : categories;
    });
  }

  Future<List<ProductCategory>> getProductCategoriesOnce({
    bool activeOnly = false,
  }) async {
    final snapshot = await _productCategoriesRef.get();
    final categories = snapshot.docs.map(ProductCategory.fromDoc).toList()
      ..sort((a, b) {
        final sortCompare = a.sortOrder.compareTo(b.sortOrder);
        return sortCompare != 0 ? sortCompare : a.name.compareTo(b.name);
      });
    return activeOnly
        ? categories.where((category) => category.active).toList()
        : categories;
  }

  Future<void> ensureDefaultProductCategories() async {
    await seedDefaultProductCategoriesIfNeeded();
  }

  Future<void> seedDefaultProductCategoriesIfNeeded() async {
    const defaults = [
      _DefaultProductCategory('Tacos', 1, '#F59A23'),
      _DefaultProductCategory('Gringas', 2, '#BFA7FF'),
      _DefaultProductCategory('Bebidas', 3, '#72B7D2'),
      _DefaultProductCategory('Quesadillas', 4, '#55D98B'),
      _DefaultProductCategory('Extras', 5, '#D986A1'),
      _DefaultProductCategory('Otros', 99, '#8A8F98'),
    ];

    final existing = await _productCategoriesRef.get();
    final existingIds = existing.docs.map((doc) => doc.id).toSet();
    final existingNormalizedNames = existing.docs
        .map((doc) => ProductCategory.fromDoc(doc).normalizedName)
        .toSet();
    final batch = _db.batch();
    var writes = 0;
    for (final category in defaults) {
      final id = categoryIdForName(category.name);
      final normalizedName = normalizeCategory(category.name);
      if (existingIds.contains(id) ||
          existingNormalizedNames.contains(normalizedName)) {
        continue;
      }
      batch.set(_productCategoriesRef.doc(id), {
        'id': id,
        'name': category.name,
        'normalizedName': normalizedName,
        'active': true,
        'sortOrder': category.sortOrder,
        'colorHex': category.colorHex,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      writes++;
    }
    if (writes > 0) {
      await batch.commit();
    }
  }

  Future<ProductCategory?> findCategoryByNormalizedName(
    String normalizedName,
  ) async {
    final snapshot = await _productCategoriesRef
        .where('normalizedName', isEqualTo: normalizeCategory(normalizedName))
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return ProductCategory.fromDoc(snapshot.docs.first);
  }

  Future<void> normalizeProductCategories() async {
    await normalizeProductCategoriesAndProducts();
  }

  Future<void> normalizeProductCategoriesAndProducts() async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageProducts == true,
      'No tienes permiso para administrar productos.',
    );
    await seedDefaultProductCategoriesIfNeeded();
    final categoriesSnapshot = await _productCategoriesRef.get();
    final categoriesByName = <String, ProductCategory>{
      for (final doc in categoriesSnapshot.docs)
        ProductCategory.fromDoc(doc).normalizedName: ProductCategory.fromDoc(
          doc,
        ),
    };
    final productsSnapshot = await _productsRef.get();
    final batch = _db.batch();
    var writes = 0;

    for (final productDoc in productsSnapshot.docs) {
      final data = productDoc.data();
      final legacyName = _readText(data['category'], 'Otros');
      final categoryName = _readText(data['categoryName'], legacyName);
      final normalizedName = normalizeCategory(categoryName);
      var category = categoriesByName[normalizedName];
      if (category == null) {
        final categoryId = categoryIdForName(categoryName);
        batch.set(_productCategoriesRef.doc(categoryId), {
          'id': categoryId,
          'name': categoryName,
          'normalizedName': normalizedName,
          'active': true,
          'sortOrder': 90,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        writes++;
        category = ProductCategory(
          id: categoryId,
          name: categoryName,
          normalizedName: normalizedName,
          active: true,
          sortOrder: 90,
        );
        categoriesByName[normalizedName] = category;
      }

      if (data['categoryId'] != category.id ||
          data['categoryName'] != category.name ||
          data['category'] != category.name) {
        batch.set(productDoc.reference, {
          'categoryId': category.id,
          'categoryName': category.name,
          'category': category.name,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        writes++;
      }
    }

    if (writes > 0) {
      await batch.commit();
    }
  }

  Future<void> createProductCategory({
    required String name,
    required int sortOrder,
    bool active = true,
    String? colorHex,
  }) async {
    await saveProductCategory(
      name: name,
      active: active,
      sortOrder: sortOrder,
      colorHex: colorHex,
    );
  }

  Future<void> updateProductCategory({
    required String categoryId,
    required String name,
    required bool active,
    required int sortOrder,
    String? colorHex,
  }) async {
    await saveProductCategory(
      categoryId: categoryId,
      name: name,
      active: active,
      sortOrder: sortOrder,
      colorHex: colorHex,
    );
  }

  Future<void> saveProductCategory({
    String? categoryId,
    required String name,
    required bool active,
    required int sortOrder,
    String? colorHex,
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageProducts == true,
      'No tienes permiso para administrar productos.',
    );
    final cleanName = _cleanCategoryDisplayName(name);
    if (cleanName.isEmpty) {
      throw ArgumentError('Captura el nombre de la categoria.');
    }
    final existing = categoryId == null
        ? await findCategoryByNormalizedName(cleanName)
        : null;
    final id = (categoryId ?? existing?.id ?? categoryIdForName(cleanName))
        .trim();
    await _productCategoriesRef.doc(id).set({
      'id': id,
      'name': cleanName,
      'normalizedName': normalizeCategory(cleanName),
      'active': active,
      'sortOrder': sortOrder,
      'colorHex': _cleanColorHex(colorHex),
      if (categoryId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setActive(ProductCategory category, bool active) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageProducts == true,
      'No tienes permiso para administrar productos.',
    );
    await _productCategoriesRef.doc(category.id).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> toggleProductCategory(ProductCategory category) async {
    await setActive(category, !category.active);
  }

  Stream<List<Product>> watchProducts({bool activeOnly = false}) {
    return _productsRef.snapshots().map((snapshot) {
      final products = snapshot.docs.map(Product.fromDoc).toList()
        ..sort((a, b) {
          final categoryCompare = compareCategories(a.category, b.category);
          return categoryCompare != 0
              ? categoryCompare
              : a.sortOrder.compareTo(b.sortOrder);
        });
      return activeOnly
          ? products.where((product) => product.active).toList()
          : products;
    });
  }

  Stream<List<Employee>> watchEmployees({bool activeOnly = true}) {
    return _employeesRef.snapshots().map((snapshot) {
      final employees = snapshot.docs.map(Employee.fromDoc).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return activeOnly
          ? employees.where((employee) => employee.active).toList()
          : employees;
    });
  }

  Stream<List<ActiveSession>> watchActiveSessions() {
    return _activeSessionsRef
        .orderBy('lastSeenAt', descending: true)
        .limit(60)
        .snapshots()
        .map((snapshot) {
          final latestByUser = <String, ActiveSession>{};
          for (final session in snapshot.docs.map(ActiveSession.fromDoc)) {
            if (!session.isVisibleInLiveViewer ||
                !_matchesCurrentBranch(session.branchId)) {
              continue;
            }
            final key = _activeSessionGroupKey(session);
            final current = latestByUser[key];
            if (current == null || _sessionIsNewer(session, current)) {
              latestByUser[key] = session;
            }
          }
          return latestByUser.values.toList()..sort((a, b) {
            final aSeen = a.lastSeenAt ?? a.updatedAt ?? DateTime(1970);
            final bSeen = b.lastSeenAt ?? b.updatedAt ?? DateTime(1970);
            return bSeen.compareTo(aSeen);
          });
        });
  }

  Future<int> cleanupInactiveActiveSessions() async {
    _requireAdminPermission(
      AppSession.instance.employee?.canViewAdmin == true ||
          AppSession.instance.employee?.canControlLiveOperations == true,
      'No tienes permiso para limpiar sesiones operativas.',
    );
    final snapshot = await _activeSessionsRef.limit(200).get();
    final cutoff = DateTime.now().subtract(const Duration(seconds: 180));
    final latestByUser = <String, ActiveSession>{};
    final sessions = snapshot.docs.map(ActiveSession.fromDoc).toList();
    for (final session in sessions.where(
      (session) => !session.isBackofficeSession,
    )) {
      final key = _activeSessionGroupKey(session);
      final current = latestByUser[key];
      if (current == null || _sessionIsNewer(session, current)) {
        latestByUser[key] = session;
      }
    }

    final batch = _db.batch();
    var count = 0;
    for (final session in sessions) {
      final seen = session.lastSeenAt ?? session.updatedAt;
      final key = _activeSessionGroupKey(session);
      final isDuplicate = latestByUser[key]?.id != session.id;
      final isOld = seen == null || seen.isBefore(cutoff);
      final shouldArchive =
          session.isBackofficeSession ||
          isDuplicate ||
          isOld ||
          !session.isOnline;
      if (session.archived || !shouldArchive) {
        continue;
      }
      batch.set(_activeSessionsRef.doc(session.id), {
        'archived': true,
        'isOnline': false,
        'currentOrderId': null,
        'currentTableId': null,
        'currentTableName': null,
        'currentTakeoutOrderId': null,
        'currentKitchenBundleId': null,
        'currentPersonNumber': null,
        'archivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      count++;
    }
    if (count > 0) {
      await batch.commit();
    }
    return count;
  }

  Stream<List<ActivityEvent>> watchRecentActivityEvents({int limit = 50}) {
    return _restaurantRef
        .collection('activityLog')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(ActivityEvent.fromDoc)
              .where((event) => _matchesCurrentBranch(event.branchId))
              .toList(),
        );
  }

  Future<void> logBackofficeIntervention({
    required String type,
    String? orderId,
    String? targetId,
    String? note,
  }) async {
    final employee = AppSession.instance.employee;
    await _restaurantRef.collection('activityLog').add({
      'type': type,
      ..._currentBranchFields,
      'orderId': orderId,
      'targetId': targetId,
      'note': note,
      'adminEmployeeId': employee?.id,
      'adminEmployeeName': employee?.name,
      'employeeId': employee?.id,
      'employeeName': employee?.name,
      'actionSource': 'backoffice_live_viewer',
      'createdAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> ensureInitialAdminEmployee() async {
    final adminRef = _employeesRef.doc('admin');
    final doc = await adminRef.get();
    if (doc.exists) {
      final data = doc.data() ?? {};
      if (data['canManageCash'] != true ||
          data['canAuthorizeCashWithdrawals'] != true ||
          data['canOpenKitchen'] != true ||
          data['canCloseKitchen'] != true ||
          data['canViewKitchenReports'] != true ||
          data['canManageKitchenStock'] != true ||
          data['canCancelOrders'] != true ||
          data['canCancelPayments'] != true ||
          data['canCancelItems'] != true ||
          data['canApproveKitchenCancellations'] != true ||
          data['canViewLiveOperations'] != true ||
          data['canControlLiveOperations'] != true) {
        await adminRef.set({
          'canManageCash': true,
          'canAuthorizeCashWithdrawals': true,
          'canOpenKitchen': true,
          'canCloseKitchen': true,
          'canViewKitchenReports': true,
          'canManageKitchenStock': true,
          'canCancelOrders': true,
          'canCancelPayments': true,
          'canCancelItems': true,
          'canApproveKitchenCancellations': true,
          'canViewLiveOperations': true,
          'canControlLiveOperations': true,
          'isSuperAdmin': true,
          'defaultRestaurantId': AppConstants.restaurantId,
          'defaultBranchId': AppConstants.defaultBranchId,
          'restaurantAccess': [AppConstants.restaurantId],
          'branchAccess': [
            {
              'restaurantId': AppConstants.restaurantId,
              'branchId': AppConstants.defaultBranchId,
              'branchName': AppConstants.defaultBranchName,
              'active': true,
              'permissions': {
                'canTakeOrders': true,
                'canCharge': true,
                'canViewKitchen': true,
                'canViewAdmin': true,
                'canManageProducts': true,
                'canManageTables': true,
                'canManagePlatforms': true,
                'canManageEmployees': true,
                'canManageCash': true,
                'canAuthorizeCashWithdrawals': true,
                'canOpenKitchen': true,
                'canCloseKitchen': true,
                'canViewKitchenReports': true,
                'canManageKitchenStock': true,
                'canCancelOrders': true,
                'canCancelPayments': true,
                'canCancelItems': true,
                'canApproveKitchenCancellations': true,
                'canViewLiveOperations': true,
                'canControlLiveOperations': true,
              },
            },
          ],
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      return;
    }

    await adminRef.set({
      'id': 'admin',
      'name': 'Admin',
      // TODO: Replace plain PIN storage with a salted hash before production.
      'pin': '1234',
      'active': true,
      'canTakeOrders': true,
      'canCharge': true,
      'canViewKitchen': true,
      'canViewAdmin': true,
      'canManageProducts': true,
      'canManageTables': true,
      'canManagePlatforms': true,
      'canManageEmployees': true,
      'canManageCash': true,
      'canAuthorizeCashWithdrawals': true,
      'canOpenKitchen': true,
      'canCloseKitchen': true,
      'canViewKitchenReports': true,
      'canManageKitchenStock': true,
      'canCancelOrders': true,
      'canCancelPayments': true,
      'canCancelItems': true,
      'canApproveKitchenCancellations': true,
      'canViewLiveOperations': true,
      'canControlLiveOperations': true,
      'isSuperAdmin': true,
      'defaultRestaurantId': AppConstants.restaurantId,
      'defaultBranchId': AppConstants.defaultBranchId,
      'restaurantAccess': [AppConstants.restaurantId],
      'branchAccess': [
        {
          'restaurantId': AppConstants.restaurantId,
          'branchId': AppConstants.defaultBranchId,
          'branchName': AppConstants.defaultBranchName,
          'active': true,
          'permissions': {
            'canTakeOrders': true,
            'canCharge': true,
            'canViewKitchen': true,
            'canViewAdmin': true,
            'canManageProducts': true,
            'canManageTables': true,
            'canManagePlatforms': true,
            'canManageEmployees': true,
            'canManageCash': true,
            'canAuthorizeCashWithdrawals': true,
            'canOpenKitchen': true,
            'canCloseKitchen': true,
            'canViewKitchenReports': true,
            'canManageKitchenStock': true,
            'canCancelOrders': true,
            'canCancelPayments': true,
            'canCancelItems': true,
            'canApproveKitchenCancellations': true,
            'canViewLiveOperations': true,
            'canControlLiveOperations': true,
          },
        },
      ],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> validateEmployeePin({
    required String employeeId,
    required String pin,
  }) async {
    final doc = await _employeesRef.doc(employeeId).get();
    if (!doc.exists) {
      return false;
    }

    final employee = Employee.fromDoc(doc);
    return employee.active && employee.pin == pin;
  }

  Stream<List<PosOrder>> watchOpenOrders() {
    return _ordersRef.snapshots().map((snapshot) {
      final orders =
          _filterCurrentBranch(
            snapshot.docs.map(PosOrder.fromDoc).where(isActiveOrder),
            (order) => order.branchId,
          )..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
      return orders;
    });
  }

  Stream<List<PosOrder>> watchOpenTakeoutOrders() {
    return _ordersRef.snapshots().map((snapshot) {
      final orders =
          _filterCurrentBranch(
            snapshot.docs
                .map(PosOrder.fromDoc)
                .where(
                  (order) =>
                      order.orderType == 'takeout' && isActiveOrder(order),
                ),
            (order) => order.branchId,
          )..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
      return orders;
    });
  }

  Stream<List<PosOrder>> watchAllOrders() {
    return _ordersRef.snapshots().map((snapshot) {
      final orders =
          _filterCurrentBranch(
            snapshot.docs.map(PosOrder.fromDoc),
            (order) => order.branchId,
          )..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
      return orders;
    });
  }

  Stream<List<KitchenOrderBundle>> watchKitchenOrderBundles() {
    return _ordersRef.snapshots().asyncMap((snapshot) async {
      final orders = _filterCurrentBranch(
        snapshot.docs.map(PosOrder.fromDoc).where(isActiveOrder),
        (order) => order.branchId,
      );

      final bundles = <KitchenOrderBundle>[];
      for (final order in orders) {
        final items = await getActiveKitchenItems(order.id);
        if (items.isNotEmpty) {
          bundles.add(KitchenOrderBundle(order: order, items: items));
        }
      }

      bundles.sort((a, b) {
        final aDate =
            a.items
                .map((item) => item.sentToKitchenAt)
                .whereType<DateTime>()
                .fold<DateTime?>(
                  null,
                  (min, date) => min == null || date.isBefore(min) ? date : min,
                ) ??
            a.order.updatedAt ??
            a.order.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            b.items
                .map((item) => item.sentToKitchenAt)
                .whereType<DateTime>()
                .fold<DateTime?>(
                  null,
                  (min, date) => min == null || date.isBefore(min) ? date : min,
                ) ??
            b.order.updatedAt ??
            b.order.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return aDate.compareTo(bDate);
      });

      return bundles;
    });
  }

  Stream<PosOrder?> watchOrder(String orderId) {
    return _ordersRef.doc(orderId).snapshots().map((doc) {
      if (!doc.exists) {
        return null;
      }
      return PosOrder.fromDoc(doc);
    });
  }

  Stream<List<OrderItem>> watchOrderItems(String orderId) {
    final cleanOrderId = orderId.trim();
    if (cleanOrderId.isEmpty) {
      return Stream.error(StateError('OrderId vacio al cargar articulos.'));
    }
    final path =
        'restaurants/${AppConstants.restaurantId}/orders/$cleanOrderId/items';
    developer.log(
      '[TacoPOS][itemsStream] watch path=$path orderId=$cleanOrderId',
    );

    return _ordersRef.doc(cleanOrderId).collection('items').snapshots().map((
      snapshot,
    ) {
      final items = _sortedOrderItems(snapshot.docs.map(OrderItem.fromDoc));
      final preview = items
          .take(5)
          .map((item) => '${item.id}:${item.productName}')
          .join(', ');
      developer.log(
        '[TacoPOS][itemsStream] orderId=$cleanOrderId path=$path '
        'itemCount=${items.length} firstItems=[$preview]',
      );
      return items;
    });
  }

  Future<List<OrderItem>> getOrderItemsOnce(String orderId) async {
    final cleanOrderId = orderId.trim();
    if (cleanOrderId.isEmpty) {
      throw StateError('OrderId vacio al cargar articulos.');
    }
    final snapshot = await _ordersRef
        .doc(cleanOrderId)
        .collection('items')
        .get();
    return _sortedOrderItems(snapshot.docs.map(OrderItem.fromDoc));
  }

  List<OrderItem> _sortedOrderItems(Iterable<OrderItem> source) {
    return source.toList()..sort((a, b) {
      final aDate =
          a.createdAt ?? a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          b.createdAt ?? b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dateCompare = aDate.compareTo(bDate);
      if (dateCompare != 0) {
        return dateCompare;
      }
      final personCompare = a.personNumber.compareTo(b.personNumber);
      if (personCompare != 0) {
        return personCompare;
      }
      return a.productName.compareTo(b.productName);
    });
  }

  Stream<List<OrderItem>> watchKitchenItems(String orderId) {
    return watchOrderItems(orderId).map(_activeKitchenItems);
  }

  Future<List<OrderItem>> getActiveKitchenItems(String orderId) async {
    final snapshot = await _ordersRef.doc(orderId).collection('items').get();
    return _activeKitchenItems(snapshot.docs.map(OrderItem.fromDoc).toList());
  }

  List<OrderItem> _activeKitchenItems(List<OrderItem> items) {
    return items
        .where(
          (item) =>
              item.sendToKitchen &&
              [
                'sent',
                'cooking',
                'cancel_requested',
              ].contains(item.kitchenStatus) &&
              !item.isCancelled,
        )
        .toList()
      ..sort((a, b) {
        final personCompare = a.personNumber.compareTo(b.personNumber);
        return personCompare != 0
            ? personCompare
            : a.productName.compareTo(b.productName);
      });
  }

  Stream<List<Payment>> watchPayments({
    String? startBusinessDate,
    String? endBusinessDate,
  }) {
    Query<Map<String, dynamic>> query = _db.collectionGroup('payments');
    if (startBusinessDate != null) {
      query = query.where(
        'businessDate',
        isGreaterThanOrEqualTo: startBusinessDate,
      );
    }
    if (endBusinessDate != null) {
      query = query.where('businessDate', isLessThanOrEqualTo: endBusinessDate);
    }

    return query.snapshots().map((snapshot) {
      final payments =
          _filterCurrentBranch(
            snapshot.docs.map(Payment.fromDoc),
            (payment) => payment.branchId,
          )..sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
      return payments;
    });
  }

  Stream<List<Payment>> watchDashboardPayments({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return watchAllOrders().asyncMap((orders) async {
      final matchingOrders = orders.where((order) {
        return _dateInRange(order.paidAt, startDate, endDate) ||
            _dateInRange(order.createdAt, startDate, endDate) ||
            _dateInRange(order.updatedAt, startDate, endDate);
      });
      final payments = <Payment>[];
      for (final order in matchingOrders) {
        final snapshot = await _ordersRef
            .doc(order.id)
            .collection('payments')
            .get();
        payments.addAll(
          snapshot.docs.map(Payment.fromDoc).where((payment) {
            final businessDate = payment.businessDate;
            if (businessDate != null && businessDate.isNotEmpty) {
              return businessDate.compareTo(_businessDateFor(startDate)) >= 0 &&
                  businessDate.compareTo(_businessDateFor(endDate)) <= 0;
            }
            return _dateInRange(payment.createdAt, startDate, endDate);
          }),
        );
      }
      payments.sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      return payments;
    });
  }

  Stream<List<Payment>> watchOrderPayments(String orderId) {
    return _ordersRef.doc(orderId).collection('payments').snapshots().map((
      snapshot,
    ) {
      final payments = snapshot.docs.map(Payment.fromDoc).toList()
        ..sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
      return payments;
    });
  }

  Future<List<Payment>> getOrderPaymentsOnce(String orderId) async {
    final snapshot = await _ordersRef.doc(orderId).collection('payments').get();
    final payments = snapshot.docs.map(Payment.fromDoc).toList()
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    return payments;
  }

  Stream<List<CashSession>> watchCashSessions({
    String? startBusinessDate,
    String? endBusinessDate,
  }) {
    Query<Map<String, dynamic>> query = _cashSessionsRef;
    if (startBusinessDate != null) {
      query = query.where(
        'businessDate',
        isGreaterThanOrEqualTo: startBusinessDate,
      );
    }
    if (endBusinessDate != null) {
      query = query.where('businessDate', isLessThanOrEqualTo: endBusinessDate);
    }

    return query.snapshots().map((snapshot) {
      final sessions =
          _filterCurrentBranch(
            snapshot.docs.map(CashSession.fromDoc),
            (session) => session.branchId,
          )..sort((a, b) {
            final aDate = a.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
      return sessions;
    });
  }

  Stream<CashSession?> watchOpenCashSession() {
    return watchCashSessions().map((sessions) {
      final openSessions = sessions
          .where((session) => session.status == 'open')
          .toList();
      if (openSessions.isEmpty) {
        return null;
      }
      return openSessions.first;
    });
  }

  Stream<CashSessionTotals> watchCashSessionTotals(String cashSessionId) {
    return watchPayments().asyncMap((payments) async {
      final sessionDoc = await _cashSessionsRef.doc(cashSessionId).get();
      final session = sessionDoc.exists
          ? CashSession.fromDoc(sessionDoc)
          : null;
      final withdrawals = await _cashWithdrawalRequestsForSessionOnce(
        cashSessionId,
      );
      return _totalsForPayments(
        payments
            .where((payment) => payment.cashSessionId == cashSessionId)
            .where((payment) => payment.isActive)
            .toList(),
        openingCashAmount: session?.openingCashAmount ?? 0,
        withdrawals: withdrawals,
      );
    });
  }

  Stream<List<CashWithdrawalRequest>> watchCashWithdrawalRequests({
    String? cashSessionId,
    String? businessDate,
    String? startBusinessDate,
    String? endBusinessDate,
    String? status,
    String? requestedByEmployeeId,
  }) {
    Query<Map<String, dynamic>> query = _cashWithdrawalRequestsRef;
    if (cashSessionId != null) {
      query = query.where('cashSessionId', isEqualTo: cashSessionId);
    }
    if (businessDate != null) {
      query = query.where('businessDate', isEqualTo: businessDate);
    }
    if (startBusinessDate != null) {
      query = query.where(
        'businessDate',
        isGreaterThanOrEqualTo: startBusinessDate,
      );
    }
    if (endBusinessDate != null) {
      query = query.where('businessDate', isLessThanOrEqualTo: endBusinessDate);
    }
    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }
    if (requestedByEmployeeId != null) {
      query = query.where(
        'requestedByEmployeeId',
        isEqualTo: requestedByEmployeeId,
      );
    }

    return query.snapshots().map((snapshot) {
      final requests =
          snapshot.docs.map(CashWithdrawalRequest.fromDoc).where((request) {
            if (!_matchesCurrentBranch(request.branchId)) {
              return false;
            }
            if (cashSessionId != null &&
                request.cashSessionId != cashSessionId) {
              return false;
            }
            if (businessDate != null && request.businessDate != businessDate) {
              return false;
            }
            if (startBusinessDate != null &&
                request.businessDate.compareTo(startBusinessDate) < 0) {
              return false;
            }
            if (endBusinessDate != null &&
                request.businessDate.compareTo(endBusinessDate) > 0) {
              return false;
            }
            if (status != null && request.status != status) {
              return false;
            }
            if (requestedByEmployeeId != null &&
                request.requestedByEmployeeId != requestedByEmployeeId) {
              return false;
            }
            return true;
          }).toList()..sort((a, b) {
            final aDate =
                a.requestedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate =
                b.requestedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
      return requests;
    });
  }

  Future<CashSession?> getOpenCashSession() async {
    final snapshot = await _cashSessionsRef.get();
    final sessions =
        snapshot.docs
            .map(CashSession.fromDoc)
            .where(
              (session) =>
                  session.status == 'open' &&
                  _matchesCurrentBranch(session.branchId),
            )
            .toList()
          ..sort((a, b) {
            final aDate = a.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });

    return sessions.isEmpty ? null : sessions.first;
  }

  Stream<List<KitchenStockItem>> watchKitchenStockItems({
    bool activeOnly = false,
  }) {
    return _kitchenStockItemsRef.snapshots().map((snapshot) {
      final items = snapshot.docs.map(KitchenStockItem.fromDoc).toList()
        ..sort((a, b) {
          final orderCompare = a.sortOrder.compareTo(b.sortOrder);
          return orderCompare != 0 ? orderCompare : a.name.compareTo(b.name);
        });
      return activeOnly ? items.where((item) => item.active).toList() : items;
    });
  }

  Future<void> ensureDefaultKitchenStockItems() async {
    final snapshot = await _kitchenStockItemsRef.get();
    final existingIds = snapshot.docs.map((doc) => doc.id).toSet();

    final batch = _db.batch();
    var hasUpdates = false;
    for (final item in _defaultKitchenStockItems) {
      final id = item['id']! as String;
      if (existingIds.contains(id)) {
        continue;
      }
      batch.set(_kitchenStockItemsRef.doc(id), {
        ...item,
        'active': true,
        'optimalConsumptionPerSaleQty': item['unit'] == 'piece' ? 1 : 50,
        'optimalConsumptionUnit': item['unit'] == 'piece'
            ? 'piece_per_item'
            : 'g_per_item',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      hasUpdates = true;
    }
    if (hasUpdates) {
      await batch.commit();
    }
  }

  Future<void> ensureKitchenStockLinksForProducts() async {
    await ensureDefaultKitchenStockItems();
    final productsSnapshot = await _productsRef.get();
    final stockItemsSnapshot = await _kitchenStockItemsRef.get();
    final stockById = {
      for (final item in stockItemsSnapshot.docs.map(KitchenStockItem.fromDoc))
        item.id: item,
    };
    final batch = _db.batch();
    var hasUpdates = false;

    for (final doc in productsSnapshot.docs) {
      final data = doc.data();
      final hasExplicitRecipe = ProductRecipeItem.readList(
        data['recipeItems'],
      ).isNotEmpty;
      final product = Product.fromDoc(doc);
      if (hasExplicitRecipe ||
          (!_defaultProductAffectsKitchenStock(product) &&
              product.recipeItems.isEmpty)) {
        continue;
      }
      var recipeItems = _defaultRecipeItemsForProduct(product, stockById);
      if (recipeItems.isEmpty && product.recipeItems.isNotEmpty) {
        recipeItems = product.recipeItems;
      }
      if (recipeItems.isEmpty) {
        continue;
      }
      for (final recipeItem in recipeItems) {
        if (stockById.containsKey(recipeItem.kitchenStockItemId)) {
          continue;
        }
        final stockItem = _fallbackStockItemForRecipeItem(recipeItem, product);
        batch.set(_kitchenStockItemsRef.doc(stockItem.id), {
          'id': stockItem.id,
          'name': stockItem.name,
          'category': stockItem.category,
          'unit': stockItem.unit,
          'active': true,
          'sortOrder': stockItem.sortOrder,
          'optimalConsumptionPerSaleQty':
              stockItem.optimalConsumptionPerSaleQty,
          'optimalConsumptionUnit': stockItem.optimalConsumptionUnit,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        stockById[stockItem.id] = stockItem;
      }
      final primary = recipeItems.first;
      batch.set(doc.reference, {
        'affectsKitchenStock': true,
        'recipeItems': ProductRecipeItem.toMapList(recipeItems),
        'kitchenStockItemId': primary.kitchenStockItemId,
        'kitchenStockItemName': primary.kitchenStockItemName,
        'kitchenStockUnit': primary.kitchenStockUnit,
        'stockConsumptionQty': primary.consumptionFactor,
        'kitchenConsumptionFactor': primary.consumptionFactor,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      hasUpdates = true;
    }

    if (hasUpdates) {
      await batch.commit();
    }
  }

  Future<List<KitchenStockItem>> _activeControlledKitchenStockItems() async {
    final stockSnapshot = await _kitchenStockItemsRef.get();
    final productSnapshot = await _productsRef.get();
    final linkedStockIds = <String>{};
    for (final product in productSnapshot.docs.map(Product.fromDoc)) {
      if (!product.active || !product.affectsKitchenStock) {
        continue;
      }
      if (product.recipeItems.isNotEmpty) {
        linkedStockIds.add(product.recipeItems.first.kitchenStockItemId);
      }
      final legacyId = product.kitchenStockItemId;
      if (legacyId != null && legacyId.trim().isNotEmpty) {
        linkedStockIds.add(legacyId);
      }
    }

    return stockSnapshot.docs
        .map(KitchenStockItem.fromDoc)
        .where(
          (item) =>
              item.active &&
              (linkedStockIds.contains(item.id) || item.id == 'tortilla_maiz'),
        )
        .toList()
      ..sort((a, b) {
        final categoryCompare = a.category.compareTo(b.category);
        if (categoryCompare != 0) {
          return categoryCompare;
        }
        final sortCompare = a.sortOrder.compareTo(b.sortOrder);
        return sortCompare != 0 ? sortCompare : a.name.compareTo(b.name);
      });
  }

  Future<void> saveKitchenStockItem({
    String? itemId,
    required String name,
    required String category,
    required String unit,
    required bool active,
    required int sortOrder,
    double optimalConsumptionPerSaleQty = 0,
    String optimalConsumptionUnit = '',
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageKitchenStock == true,
      'No tienes permiso para administrar insumos de cocina.',
    );
    final docRef = itemId == null
        ? _kitchenStockItemsRef.doc()
        : _kitchenStockItemsRef.doc(itemId);
    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'category': category,
      'unit': unit,
      'active': active,
      'sortOrder': sortOrder,
      'optimalConsumptionPerSaleQty': optimalConsumptionPerSaleQty,
      'optimalConsumptionUnit': optimalConsumptionUnit,
      if (itemId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    // TODO: Registrar kitchen_stock_item_created/updated en activityLog.
  }

  Future<void> toggleKitchenStockItem(KitchenStockItem item) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageKitchenStock == true,
      'No tienes permiso para administrar insumos de cocina.',
    );
    await _kitchenStockItemsRef.doc(item.id).update({
      'active': !item.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // TODO: Registrar kitchen_stock_item_disabled en activityLog.
  }

  Stream<KitchenSession?> watchOpenKitchenSession() {
    return _kitchenSessionsRef
        .where('status', isEqualTo: 'open')
        .snapshots()
        .map((snapshot) {
          final sessions = _filterCurrentBranch(
            snapshot.docs.map(KitchenSession.fromDoc),
            (session) => session.branchId,
          )..sort((a, b) => b.businessDate.compareTo(a.businessDate));
          return sessions.isEmpty ? null : sessions.first;
        });
  }

  Future<String> currentKitchenBusinessDate() async {
    final openCash = await getOpenCashSession();
    return openCash?.businessDate ?? _businessDateFor(DateTime.now());
  }

  Future<KitchenSession?> getOpenKitchenSessionForCurrentBusinessDate() async {
    final businessDate = await currentKitchenBusinessDate();
    final snapshot = await _kitchenSessionsRef
        .where('businessDate', isEqualTo: businessDate)
        .get();
    final sessions = snapshot.docs
        .map(KitchenSession.fromDoc)
        .where(
          (session) =>
              session.isOpen && _matchesCurrentBranch(session.branchId),
        )
        .toList();
    return sessions.isEmpty ? null : sessions.first;
  }

  Future<bool> hasCompletedOpenKitchenForCurrentBusinessDate() async {
    final session = await getOpenKitchenSessionForCurrentBusinessDate();
    if (session == null) {
      return false;
    }
    final itemsSnapshot = await _kitchenSessionsRef
        .doc(session.id)
        .collection('items')
        .limit(1)
        .get();
    return itemsSnapshot.docs.isNotEmpty;
  }

  Future<List<KitchenYieldReportRow>> kitchenYieldReport({
    required String startBusinessDate,
    required String endBusinessDate,
  }) async {
    final sessionsSnapshot = await _kitchenSessionsRef.get();
    final sessions =
        sessionsSnapshot.docs
            .map(KitchenSession.fromDoc)
            .where(
              (session) =>
                  session.businessDate.compareTo(startBusinessDate) >= 0 &&
                  session.businessDate.compareTo(endBusinessDate) <= 0 &&
                  _matchesCurrentBranch(session.branchId),
            )
            .toList()
          ..sort((a, b) => b.businessDate.compareTo(a.businessDate));

    final stockSnapshot = await _kitchenStockItemsRef.get();
    final stockById = {
      for (final item in stockSnapshot.docs.map(KitchenStockItem.fromDoc))
        item.id: item,
    };
    final totalsConsumed = <String, double>{};
    final totalsSold = <String, double>{};
    final currentByStockId = <String, KitchenSessionItem>{};

    for (final session in sessions) {
      final itemsSnapshot = await _kitchenSessionsRef
          .doc(session.id)
          .collection('items')
          .get();
      final items = itemsSnapshot.docs.map(KitchenSessionItem.fromDoc).toList();
      for (final item in items) {
        currentByStockId.putIfAbsent(item.kitchenStockItemId, () => item);
        totalsConsumed[item.kitchenStockItemId] =
            (totalsConsumed[item.kitchenStockItemId] ?? 0) +
            item.usefulConsumedQty;
        totalsSold[item.kitchenStockItemId] =
            (totalsSold[item.kitchenStockItemId] ?? 0) + item.soldQty;
        stockById.putIfAbsent(
          item.kitchenStockItemId,
          () => KitchenStockItem(
            id: item.kitchenStockItemId,
            name: item.name,
            category: item.category,
            unit: item.unit,
            active: true,
            sortOrder: 999,
            optimalConsumptionPerSaleQty: item.unit == 'piece' ? 1 : 50,
            optimalConsumptionUnit: item.unit == 'piece'
                ? 'piece_per_item'
                : 'g_per_item',
          ),
        );
      }
    }

    final rows = <KitchenYieldReportRow>[];
    for (final entry in stockById.entries) {
      final current = currentByStockId[entry.key];
      if (current == null) {
        continue;
      }
      final totalConsumed = totalsConsumed[entry.key] ?? 0;
      final totalSold = totalsSold[entry.key] ?? 0;
      rows.add(
        KitchenYieldReportRow(
          item: entry.value,
          currentItem: current,
          previousRemainingQty: current.previousRemainingQty,
          initialInputQty: current.todayInputQty,
          additionalEntriesQty: current.additionalEntriesQty,
          availableQty: current.availableQty,
          finalRemainingQty: current.finalRemainingQty,
          wasteQty: current.wasteQty,
          usedQty: current.usedQty,
          usefulConsumedQty: current.usefulConsumedQty,
          soldQty: current.soldQty,
          currentYield: _yieldPerSale(
            unit: current.unit,
            usefulConsumedQty: current.usefulConsumedQty,
            soldQty: current.soldQty,
          ),
          averageYield: _yieldPerSale(
            unit: current.unit,
            usefulConsumedQty: totalConsumed,
            soldQty: totalSold,
          ),
        ),
      );
    }
    rows.sort((a, b) {
      final categoryCompare = a.item.category.compareTo(b.item.category);
      if (categoryCompare != 0) return categoryCompare;
      final sortCompare = a.item.sortOrder.compareTo(b.item.sortOrder);
      return sortCompare != 0
          ? sortCompare
          : a.item.name.compareTo(b.item.name);
    });
    return rows;
  }

  Stream<List<KitchenSession>> watchKitchenSessions({
    String? startBusinessDate,
    String? endBusinessDate,
  }) {
    Query<Map<String, dynamic>> query = _kitchenSessionsRef;
    if (startBusinessDate != null) {
      query = query.where(
        'businessDate',
        isGreaterThanOrEqualTo: startBusinessDate,
      );
    }
    if (endBusinessDate != null) {
      query = query.where('businessDate', isLessThanOrEqualTo: endBusinessDate);
    }
    return query.snapshots().map((snapshot) {
      final sessions = _filterCurrentBranch(
        snapshot.docs.map(KitchenSession.fromDoc),
        (session) => session.branchId,
      )..sort((a, b) => b.businessDate.compareTo(a.businessDate));
      return sessions;
    });
  }

  Stream<List<KitchenSessionItem>> watchKitchenSessionItems(
    String kitchenSessionId,
  ) {
    return _kitchenSessionsRef
        .doc(kitchenSessionId)
        .collection('items')
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs.map(KitchenSessionItem.fromDoc).toList()
            ..sort((a, b) {
              final categoryCompare = a.category.compareTo(b.category);
              return categoryCompare != 0
                  ? categoryCompare
                  : a.name.compareTo(b.name);
            });
          return items;
        });
  }

  Stream<List<KitchenAdditionalEntry>> watchKitchenAdditionalEntries(
    String kitchenSessionId,
  ) {
    return _kitchenSessionsRef
        .doc(kitchenSessionId)
        .collection('additionalEntries')
        .snapshots()
        .map((snapshot) {
          final entries =
              snapshot.docs.map(KitchenAdditionalEntry.fromDoc).toList()
                ..sort((a, b) {
                  final aDate =
                      a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final bDate =
                      b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return bDate.compareTo(aDate);
                });
          return entries;
        });
  }

  Future<KitchenSession?> getKitchenSessionForBusinessDate(
    String businessDate,
  ) async {
    final sessions = await _kitchenSessionsForBusinessDate(businessDate);
    if (sessions.isEmpty) {
      return null;
    }
    final validClosed = <KitchenSession>[];
    for (final session in sessions.where((session) => session.isClosed)) {
      if (await _kitchenCloseIsComplete(session.id)) {
        validClosed.add(session);
      }
    }
    if (validClosed.isNotEmpty) {
      return validClosed.first;
    }
    final openSessions = sessions.where((session) => session.isOpen).toList();
    if (openSessions.isNotEmpty) {
      return openSessions.first;
    }
    return sessions.first;
  }

  Future<List<KitchenSession>> _kitchenSessionsForBusinessDate(
    String businessDate,
  ) async {
    final snapshot = await _kitchenSessionsRef
        .where('businessDate', isEqualTo: businessDate)
        .get();
    final sessions =
        _filterCurrentBranch(
          snapshot.docs.map(KitchenSession.fromDoc),
          (session) => session.branchId,
        )..sort((a, b) {
          final statusCompare = _kitchenSessionStatusRank(
            a,
          ).compareTo(_kitchenSessionStatusRank(b));
          if (statusCompare != 0) return statusCompare;
          final aDate = a.closedAt ?? a.openedAt ?? DateTime(0);
          final bDate = b.closedAt ?? b.openedAt ?? DateTime(0);
          return bDate.compareTo(aDate);
        });
    return sessions;
  }

  int _kitchenSessionStatusRank(KitchenSession session) {
    if (session.isClosed) return 0;
    if (session.isOpen) return 1;
    return 2;
  }

  Future<List<KitchenOpeningInput>> buildKitchenOpeningInputs() async {
    await ensureDefaultKitchenStockItems();
    await ensureKitchenStockLinksForProducts();
    final openCash = await getOpenCashSession();
    final businessDate =
        openCash?.businessDate ?? _businessDateFor(DateTime.now());
    final existingSessions = await _kitchenSessionsForBusinessDate(
      businessDate,
    );
    if (existingSessions.any((session) => session.isOpen)) {
      throw StateError(
        'La cocina ya fue abierta para esta fecha de operacion.',
      );
    }
    if (existingSessions.any((session) => session.isClosed)) {
      throw StateError(
        'La cocina ya fue cerrada para esta fecha. Abre una nueva caja con otra fecha de operacion.',
      );
    }
    final previousRemaining = await _previousKitchenRemainingByItem(
      businessDate,
    );
    final items = await _activeControlledKitchenStockItems();
    return items
        .map(
          (item) => KitchenOpeningInput(
            item: item,
            previousRemainingQty: previousRemaining[item.id] ?? 0,
            todayInputQty: 0,
          ),
        )
        .toList();
  }

  Future<KitchenSession> openKitchenSessionWithInputs({
    required Map<String, double> todayInputByItemId,
  }) async {
    _requireOpenKitchen();
    await ensureDefaultKitchenStockItems();
    await ensureKitchenStockLinksForProducts();
    final openCash = await getOpenCashSession();
    final businessDate =
        openCash?.businessDate ?? _businessDateFor(DateTime.now());
    final existingSessions = await _kitchenSessionsForBusinessDate(
      businessDate,
    );
    if (existingSessions.any((session) => session.isOpen)) {
      throw StateError(
        'La cocina ya fue abierta para esta fecha de operacion.',
      );
    }
    if (existingSessions.any((session) => session.isClosed)) {
      throw StateError(
        'La cocina ya fue cerrada para esta fecha. Abre una nueva caja con otra fecha de operacion.',
      );
    }

    final activeItems = await _activeControlledKitchenStockItems();
    if (activeItems.isEmpty) {
      throw StateError('No hay insumos activos para abrir cocina.');
    }
    if (todayInputByItemId.length < activeItems.length) {
      throw ArgumentError(
        'Captura las entradas del dia antes de abrir cocina.',
      );
    }

    final previousRemaining = await _previousKitchenRemainingByItem(
      businessDate,
    );
    final employee = AppSession.instance.employee;
    final docRef = _kitchenSessionsRef.doc();
    final batch = _db.batch();
    batch.set(docRef, {
      'id': docRef.id,
      'businessDate': businessDate,
      'cashSessionId': openCash?.id,
      ..._currentBranchFields,
      'status': 'open',
      'openedAt': FieldValue.serverTimestamp(),
      'openedByEmployeeId': employee?.id ?? '',
      'openedByEmployeeName': employee?.name ?? '',
      'closedAt': null,
      'closedByEmployeeId': null,
      'closedByEmployeeName': null,
      'notes': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final item in activeItems) {
      final todayInputQty = todayInputByItemId[item.id];
      if (todayInputQty == null || todayInputQty < 0) {
        throw ArgumentError(
          'Captura las entradas del dia antes de abrir cocina.',
        );
      }
      if (item.unit == 'piece' &&
          todayInputQty != todayInputQty.roundToDouble()) {
        throw ArgumentError('${item.name} debe capturarse en piezas enteras.');
      }
      final previousQty = previousRemaining[item.id] ?? 0;
      final availableQty = previousQty + todayInputQty;
      batch.set(docRef.collection('items').doc(item.id), {
        'kitchenStockItemId': item.id,
        ..._currentBranchFields,
        'name': item.name,
        'category': item.category,
        'unit': item.unit,
        'previousRemainingQty': previousQty,
        'todayInputQty': todayInputQty,
        'additionalEntriesQty': 0.0,
        'availableQty': availableQty,
        'finalRemainingQty': null,
        'wasteQty': null,
        'usedQty': null,
        'usefulConsumedQty': null,
        'soldQty': null,
        'yieldQtyPerUnit': null,
        'notes': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    // TODO: Registrar kitchen_session_opened en activityLog.
    final updated = await docRef.get();
    return KitchenSession.fromDoc(updated);
  }

  Future<void> updateKitchenSessionItemInput({
    required String kitchenSessionId,
    required KitchenSessionItem item,
    required double todayInputQty,
  }) async {
    throw StateError(
      'La apertura ya esta bloqueada. Usa Agregar entrada del dia.',
    );
  }

  Future<void> addKitchenAdditionalEntry({
    required String kitchenSessionId,
    required KitchenSessionItem item,
    required double qty,
    required String reason,
    required String notes,
  }) async {
    _requireOpenKitchen();
    if (qty <= 0) {
      throw ArgumentError('La entrada adicional debe ser mayor a cero.');
    }
    if (item.unit == 'piece' && qty != qty.roundToDouble()) {
      throw ArgumentError('${item.name} debe capturarse en piezas enteras.');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('Captura el motivo de la entrada.');
    }

    final sessionRef = _kitchenSessionsRef.doc(kitchenSessionId);
    final sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) {
      throw StateError('La cocina ya no existe.');
    }
    final session = KitchenSession.fromDoc(sessionDoc);
    if (!session.isOpen) {
      throw StateError('Solo puedes agregar entradas con cocina abierta.');
    }

    final employee = AppSession.instance.employee;
    final entryRef = sessionRef.collection('additionalEntries').doc();
    final newAdditionalQty = item.additionalEntriesQty + qty;
    final newAvailableQty =
        item.previousRemainingQty + item.todayInputQty + newAdditionalQty;
    final batch = _db.batch();
    batch.set(entryRef, {
      'id': entryRef.id,
      'kitchenSessionId': kitchenSessionId,
      'businessDate': session.businessDate,
      'restaurantId': session.restaurantId,
      'restaurantName': session.restaurantName,
      'branchId': session.branchId,
      'branchName': session.branchName,
      'kitchenStockItemId': item.kitchenStockItemId,
      'name': item.name,
      'qty': qty,
      'reason': reason.trim(),
      'notes': notes.trim(),
      'createdByEmployeeId': employee?.id ?? '',
      'createdByEmployeeName': employee?.name ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(sessionRef.collection('items').doc(item.id), {
      'additionalEntriesQty': newAdditionalQty,
      'availableQty': newAvailableQty,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(sessionRef, {'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  Future<KitchenSession> closeKitchenSession({
    required String kitchenSessionId,
    required Map<String, KitchenCloseInput> closeInputs,
    required String notes,
  }) async {
    _requireCloseKitchen();
    final docRef = _kitchenSessionsRef.doc(kitchenSessionId);
    final doc = await docRef.get();
    if (!doc.exists) {
      throw StateError('La apertura de cocina ya no existe.');
    }
    final session = KitchenSession.fromDoc(doc);
    if (!session.isOpen) {
      throw StateError('Esta cocina ya esta cerrada.');
    }
    final existingForDate = await _kitchenSessionsForBusinessDate(
      session.businessDate,
    );
    if (existingForDate.any(
      (existing) => existing.id != session.id && existing.isClosed,
    )) {
      throw StateError('Ya existe cierre de cocina para esta fecha.');
    }

    final itemsSnapshot = await docRef.collection('items').get();
    final items = itemsSnapshot.docs.map(KitchenSessionItem.fromDoc).toList();
    final soldByStockItem = await _soldQtyByKitchenStockItem(
      session.businessDate,
    );
    final employee = AppSession.instance.employee;
    final batch = _db.batch();

    for (final item in items) {
      final input = closeInputs[item.id];
      if (input == null) {
        throw ArgumentError('Captura cierre para ${item.name}.');
      }
      if (input.finalRemainingQty < 0 || input.wasteQty < 0) {
        throw ArgumentError('Los montos de cierre no pueden ser negativos.');
      }
      if (item.unit == 'piece' &&
          (input.finalRemainingQty != input.finalRemainingQty.roundToDouble() ||
              input.wasteQty != input.wasteQty.roundToDouble())) {
        throw ArgumentError('${item.name} debe capturarse en piezas enteras.');
      }
      final usedQty = item.availableQty - input.finalRemainingQty;
      final usefulConsumedQty = usedQty - input.wasteQty;
      if (usefulConsumedQty < 0) {
        throw ArgumentError(
          'El consumo util de ${item.name} no puede ser negativo.',
        );
      }
      final soldQty = soldByStockItem[item.kitchenStockItemId] ?? 0;
      final yieldQtyPerUnit = _yieldPerSale(
        unit: item.unit,
        usefulConsumedQty: usefulConsumedQty,
        soldQty: soldQty,
      );

      batch.update(docRef.collection('items').doc(item.id), {
        'finalRemainingQty': input.finalRemainingQty,
        'wasteQty': input.wasteQty,
        'usedQty': usedQty,
        'usefulConsumedQty': usefulConsumedQty,
        'soldQty': soldQty,
        'yieldQtyPerUnit': yieldQtyPerUnit,
        'notes': input.notes.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    batch.update(docRef, {
      'status': 'closed',
      'closedAt': FieldValue.serverTimestamp(),
      'closedByEmployeeId': employee?.id ?? '',
      'closedByEmployeeName': employee?.name ?? '',
      'notes': notes.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    // TODO: Registrar kitchen_session_closed en activityLog.
    final updated = await docRef.get();
    return KitchenSession.fromDoc(updated);
  }

  Future<void> openCashSession({
    required String businessDate,
    required double openingCashAmount,
  }) async {
    _requireCashOpenPermission();
    if (businessDate.trim().isEmpty) {
      throw ArgumentError('Selecciona la fecha operativa.');
    }
    if (openingCashAmount < 0) {
      throw ArgumentError('El fondo inicial no puede ser negativo.');
    }

    final openSession = await getOpenCashSession();
    if (openSession != null) {
      if (openSession.businessDate == businessDate) {
        return;
      }
      throw StateError(
        'Ya existe una caja abierta para ${openSession.businessDate}.',
      );
    }

    final existingForDate = await _cashSessionsRef
        .where('businessDate', isEqualTo: businessDate)
        .get();
    final hasClosed = existingForDate.docs
        .map(CashSession.fromDoc)
        .any(
          (session) =>
              session.status == 'closed' &&
              _matchesCurrentBranch(session.branchId),
        );
    if (hasClosed) {
      throw StateError('La fecha $businessDate ya tiene corte cerrado.');
    }

    final employee = AppSession.instance.employee;
    final docRef = _cashSessionsRef.doc();
    await docRef.set({
      'id': docRef.id,
      'businessDate': businessDate,
      ..._currentBranchFields,
      'status': 'open',
      'openingCashAmount': openingCashAmount,
      'openedAt': FieldValue.serverTimestamp(),
      'openedByEmployeeId': employee?.id ?? '',
      'openedByEmployeeName': employee?.name ?? '',
      'countedCashAmount': 0.0,
      'terminalReportedAmount': 0.0,
      'expectedCashAmount': 0.0,
      'expectedCardChargedAmount': 0.0,
      'expectedCardBaseAmount': 0.0,
      'expectedCardSurchargeAmount': 0.0,
      'expectedCardFeeAbsorbedAmount': 0.0,
      'expectedPlatformAmount': 0.0,
      'expectedEmployeeConsumptionAmount': 0.0,
      'totalExpectedRealMoney': 0.0,
      'totalCountedRealMoney': 0.0,
      'cashDifference': 0.0,
      'cardDifference': 0.0,
      'netDifference': 0.0,
      'shortageAmount': 0.0,
      'overAmount': 0.0,
      'approvedWithdrawalsTotal': 0.0,
      'pendingWithdrawalsTotal': 0.0,
      'withdrawalRequestCount': 0,
      'notes': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> requestCashWithdrawal({
    required String cashSessionId,
    required double amount,
    required String reason,
  }) async {
    _requireCashWithdrawalRequester();
    if (amount <= 0) {
      throw ArgumentError('Captura un monto de retiro valido.');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('Captura el motivo del retiro.');
    }

    final sessionDoc = await _cashSessionsRef.doc(cashSessionId).get();
    if (!sessionDoc.exists) {
      throw StateError('La caja ya no existe.');
    }
    final session = CashSession.fromDoc(sessionDoc);
    if (!session.isOpen) {
      throw StateError('La caja ya esta cerrada.');
    }

    final employee = AppSession.instance.employee;
    final docRef = _cashWithdrawalRequestsRef.doc();
    await docRef.set({
      'id': docRef.id,
      'cashSessionId': cashSessionId,
      'businessDate': session.businessDate,
      ..._currentBranchFields,
      'amount': amount,
      'reason': reason.trim(),
      'requestedByEmployeeId': employee?.id ?? '',
      'requestedByEmployeeName': employee?.name ?? '',
      'requestedAt': FieldValue.serverTimestamp(),
      'status': 'pending',
      'authorizedByEmployeeId': null,
      'authorizedByEmployeeName': null,
      'authorizedAt': null,
      'adminNotes': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> authorizeCashWithdrawal({
    required String requestId,
    required bool approved,
    String adminNotes = '',
  }) async {
    _requireCashWithdrawalAuthorizer();
    final docRef = _cashWithdrawalRequestsRef.doc(requestId);
    final doc = await docRef.get();
    if (!doc.exists) {
      throw StateError('La solicitud ya no existe.');
    }
    final request = CashWithdrawalRequest.fromDoc(doc);
    if (!request.isPending) {
      throw StateError('La solicitud ya fue atendida.');
    }

    final employee = AppSession.instance.employee;
    await docRef.update({
      'status': approved ? 'approved' : 'rejected',
      'authorizedByEmployeeId': employee?.id ?? '',
      'authorizedByEmployeeName': employee?.name ?? '',
      'authorizedAt': FieldValue.serverTimestamp(),
      'adminNotes': adminNotes.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<CashCloseBlockers> cashCloseBlockers(String cashSessionId) async {
    final sessionDoc = await _cashSessionsRef.doc(cashSessionId).get();
    if (!sessionDoc.exists) {
      throw StateError('La caja ya no existe.');
    }
    final session = CashSession.fromDoc(sessionDoc);
    return _cashCloseBlockersForSession(session);
  }

  Future<CashCloseBlockers> _cashCloseBlockersForSession(
    CashSession session,
  ) async {
    var openTableCount = 0;
    var openTakeoutCount = 0;
    var pendingKitchenItemCount = 0;
    var pendingPaymentCount = 0;

    final ordersSnapshot = await _ordersRef.get();
    final orders = ordersSnapshot.docs.map(PosOrder.fromDoc).where((order) {
      return _matchesCurrentBranch(order.branchId) &&
          _orderBelongsToBusinessDate(order, session.businessDate);
    }).toList();

    for (final order in orders) {
      final finalStatus = _isFinalOrderStatus(order.status);
      final paymentPending =
          ['pending', 'partial'].contains(order.paymentStatus) &&
          !['paid', 'cancelled', 'voided'].contains(order.status);
      final operationalOpen = !finalStatus || paymentPending;

      if (operationalOpen && order.orderType == 'takeout') {
        openTakeoutCount++;
      } else if (operationalOpen && order.orderType != 'takeout') {
        openTableCount++;
      }
      if (paymentPending) {
        pendingPaymentCount++;
      }

      final itemsSnapshot = await _ordersRef
          .doc(order.id)
          .collection('items')
          .get();
      for (final item in itemsSnapshot.docs.map(OrderItem.fromDoc)) {
        if (_isPendingKitchenStatus(item.kitchenStatus)) {
          pendingKitchenItemCount += item.qty;
        }
      }
    }

    final kitchenSessions = await _kitchenSessionsForBusinessDate(
      session.businessDate,
    );
    var hasValidClosedKitchen = false;
    var hasIncompleteClosedKitchen = false;
    for (final kitchenSession in kitchenSessions) {
      if (!kitchenSession.isClosed) {
        continue;
      }
      if (await _kitchenCloseIsComplete(kitchenSession.id)) {
        hasValidClosedKitchen = true;
        break;
      }
      hasIncompleteClosedKitchen = true;
    }
    final kitchenNotClosed =
        !hasValidClosedKitchen && !hasIncompleteClosedKitchen;
    final kitchenCloseIncomplete =
        !hasValidClosedKitchen && hasIncompleteClosedKitchen;

    return CashCloseBlockers(
      openTableCount: openTableCount,
      openTakeoutCount: openTakeoutCount,
      pendingKitchenItemCount: pendingKitchenItemCount,
      pendingPaymentCount: pendingPaymentCount,
      kitchenNotClosed: kitchenNotClosed,
      kitchenCloseIncomplete: kitchenCloseIncomplete,
    );
  }

  Future<CashSession> closeCashSession({
    required String cashSessionId,
    required double countedCashAmount,
    required double terminalReportedAmount,
    required String notes,
  }) async {
    _requireCashManager();
    if (countedCashAmount < 0 || terminalReportedAmount < 0) {
      throw ArgumentError('Los montos de cierre no pueden ser negativos.');
    }

    final docRef = _cashSessionsRef.doc(cashSessionId);
    final doc = await docRef.get();
    if (!doc.exists) {
      throw StateError('La caja ya no existe.');
    }

    final session = CashSession.fromDoc(doc);
    if (session.status != 'open') {
      throw StateError('Esta caja ya esta cerrada.');
    }

    final blockers = await _cashCloseBlockersForSession(session);
    if (!blockers.canClose) {
      throw StateError('${blockers.message}\n${blockers.detail}');
    }

    final pendingWithdrawals = await _pendingCashWithdrawalRequestsForClose(
      cashSessionId: cashSessionId,
      businessDate: session.businessDate,
    );
    if (pendingWithdrawals.isNotEmpty) {
      throw StateError(
        'No puedes cerrar caja. Hay solicitudes de gasto pendientes de autorizacion.',
      );
    }

    final totals = await _cashSessionTotalsOnce(cashSessionId);
    final totalCountedRealMoney = totals.totalCountedRealMoney(
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
    );
    final cashDifference = totals.cashDifference(countedCashAmount);
    final cardDifference = totals.cardDifference(terminalReportedAmount);
    final netDifference = totals.netDifference(
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
    );
    final shortageAmount = totals.shortageAmount(
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
    );
    final overAmount = totals.overAmount(
      countedCashAmount: countedCashAmount,
      terminalReportedAmount: terminalReportedAmount,
    );
    final employee = AppSession.instance.employee;

    await docRef.update({
      'status': 'closed',
      'closedAt': FieldValue.serverTimestamp(),
      'closedByEmployeeId': employee?.id ?? '',
      'closedByEmployeeName': employee?.name ?? '',
      'countedCashAmount': countedCashAmount,
      'terminalReportedAmount': terminalReportedAmount,
      'expectedCashAmount': totals.expectedCashAmount,
      'expectedCardChargedAmount': totals.expectedCardChargedAmount,
      'expectedCardBaseAmount': totals.expectedCardBaseAmount,
      'expectedCardSurchargeAmount': totals.expectedCardSurchargeAmount,
      'expectedCardFeeAbsorbedAmount': totals.expectedCardFeeAbsorbedAmount,
      'expectedPlatformAmount': totals.expectedPlatformAmount,
      'expectedEmployeeConsumptionAmount':
          totals.expectedEmployeeConsumptionAmount,
      'approvedWithdrawalsTotal': totals.approvedWithdrawalsTotal,
      'pendingWithdrawalsTotal': totals.pendingWithdrawalsTotal,
      'withdrawalRequestCount': totals.withdrawalRequestCount,
      'totalExpectedRealMoney': totals.totalExpectedRealMoney,
      'totalCountedRealMoney': totalCountedRealMoney,
      'cashDifference': cashDifference,
      'cardDifference': cardDifference,
      'netDifference': netDifference,
      'shortageAmount': shortageAmount,
      'overAmount': overAmount,
      'notes': notes.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (netDifference < 0) {
      await _restaurantRef.collection('activityLog').add({
        'type': 'cash_close_shortage',
        ..._currentBranchFields,
        'cashSessionId': cashSessionId,
        'businessDate': session.businessDate,
        'shortageAmount': shortageAmount,
        'netDifference': netDifference,
        ..._employeeAuditFields(prefix: 'createdBy'),
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      });
    }

    final updatedDoc = await docRef.get();
    return CashSession.fromDoc(updatedDoc);
  }

  Future<CashSessionTotals> _cashSessionTotalsOnce(String cashSessionId) async {
    final snapshot = await _db.collectionGroup('payments').get();
    final sessionDoc = await _cashSessionsRef.doc(cashSessionId).get();
    final session = sessionDoc.exists ? CashSession.fromDoc(sessionDoc) : null;
    final withdrawals = await _cashWithdrawalRequestsForSessionOnce(
      cashSessionId,
    );
    return _totalsForPayments(
      snapshot.docs
          .map(Payment.fromDoc)
          .where((payment) => payment.cashSessionId == cashSessionId)
          .where((payment) => payment.isActive)
          .toList(),
      openingCashAmount: session?.openingCashAmount ?? 0,
      withdrawals: withdrawals,
    );
  }

  Future<List<CashWithdrawalRequest>> _cashWithdrawalRequestsForSessionOnce(
    String cashSessionId,
  ) async {
    final snapshot = await _cashWithdrawalRequestsRef
        .where('cashSessionId', isEqualTo: cashSessionId)
        .get();
    return snapshot.docs.map(CashWithdrawalRequest.fromDoc).toList();
  }

  Future<List<CashWithdrawalRequest>> _pendingCashWithdrawalRequestsForClose({
    required String cashSessionId,
    required String businessDate,
  }) async {
    final bySession = await _cashWithdrawalRequestsRef
        .where('cashSessionId', isEqualTo: cashSessionId)
        .get();
    final byDate = await _cashWithdrawalRequestsRef
        .where('businessDate', isEqualTo: businessDate)
        .get();

    final requestsById = <String, CashWithdrawalRequest>{};
    for (final doc in [...bySession.docs, ...byDate.docs]) {
      final request = CashWithdrawalRequest.fromDoc(doc);
      if (request.isPending && _matchesCurrentBranch(request.branchId)) {
        requestsById[doc.id] = request;
      }
    }
    return requestsById.values.toList();
  }

  CashSessionTotals _totalsForPayments(
    List<Payment> payments, {
    required double openingCashAmount,
    required List<CashWithdrawalRequest> withdrawals,
  }) {
    double cash = 0;
    double cardCharged = 0;
    double cardBase = 0;
    double cardSurcharge = 0;
    double cardFeeAbsorbed = 0;
    double platform = 0;
    double employeeConsumption = 0;

    for (final payment in payments.where((payment) => payment.isActive)) {
      switch (payment.method) {
        case 'cash':
          cash += payment.chargedAmount;
          break;
        case 'card':
          cardCharged += payment.chargedAmount;
          cardBase += payment.baseAmount;
          cardSurcharge += payment.surchargeAmount;
          cardFeeAbsorbed += payment.cardFeeAbsorbedAmount;
          break;
        case 'platform_paid':
          platform += payment.baseAmount;
          break;
        case 'employee_consumption':
          employeeConsumption += payment.baseAmount;
          break;
      }
    }

    final approvedWithdrawals = withdrawals
        .where((request) => request.isApproved)
        .fold<double>(0, (total, request) => total + request.amount);
    final pendingWithdrawals = withdrawals
        .where((request) => request.isPending)
        .fold<double>(0, (total, request) => total + request.amount);

    return CashSessionTotals(
      expectedCashAmount: cash + openingCashAmount - approvedWithdrawals,
      expectedCardChargedAmount: cardCharged,
      expectedCardBaseAmount: cardBase,
      expectedCardSurchargeAmount: cardSurcharge,
      expectedCardFeeAbsorbedAmount: cardFeeAbsorbed,
      expectedPlatformAmount: platform,
      expectedEmployeeConsumptionAmount: employeeConsumption,
      approvedWithdrawalsTotal: approvedWithdrawals,
      pendingWithdrawalsTotal: pendingWithdrawals,
      withdrawalRequestCount: withdrawals.length,
    );
  }

  Future<Map<String, double>> _previousKitchenRemainingByItem(
    String businessDate,
  ) async {
    final snapshot = await _kitchenSessionsRef
        .where('status', isEqualTo: 'closed')
        .get();
    final previousSessions =
        snapshot.docs
            .map(KitchenSession.fromDoc)
            .where(
              (session) =>
                  session.businessDate.compareTo(businessDate) < 0 &&
                  _matchesCurrentBranch(session.branchId),
            )
            .toList()
          ..sort((a, b) => b.businessDate.compareTo(a.businessDate));
    if (previousSessions.isEmpty) {
      return const {};
    }

    final itemsSnapshot = await _kitchenSessionsRef
        .doc(previousSessions.first.id)
        .collection('items')
        .get();
    return {
      for (final item in itemsSnapshot.docs.map(KitchenSessionItem.fromDoc))
        item.kitchenStockItemId: item.finalRemainingQty,
    };
  }

  Future<Map<String, double>> _soldQtyByKitchenStockItem(
    String businessDate,
  ) async {
    final ordersSnapshot = await _ordersRef.get();
    final orders = ordersSnapshot.docs.map(PosOrder.fromDoc).where((order) {
      if (['cancelled', 'voided'].contains(order.status)) {
        return false;
      }
      if (!_matchesCurrentBranch(order.branchId)) {
        return false;
      }
      if (['pending', 'partial'].contains(order.paymentStatus) &&
          order.status != 'paid') {
        return false;
      }
      final date = order.paidAt ?? order.createdAt;
      return _businessDateFor(date ?? DateTime.fromMillisecondsSinceEpoch(0)) ==
          businessDate;
    }).toList();

    final sold = <String, double>{};
    for (final order in orders) {
      final itemsSnapshot = await _ordersRef
          .doc(order.id)
          .collection('items')
          .get();
      for (final item in itemsSnapshot.docs.map(OrderItem.fromDoc)) {
        if (['cancelled', 'voided'].contains(item.kitchenStatus) ||
            ['cancelled', 'voided'].contains(item.paymentStatus)) {
          continue;
        }
        if (item.recipeItems.isNotEmpty) {
          final recipeItem = item.recipeItems.first;
          sold[recipeItem.kitchenStockItemId] =
              (sold[recipeItem.kitchenStockItemId] ?? 0) +
              item.qty * recipeItem.consumptionFactor;
          continue;
        }
        final stockItemId =
            item.kitchenStockItemId ??
            _stockItemIdForProductName(item.productName);
        if (stockItemId == null) {
          continue;
        }
        sold[stockItemId] = (sold[stockItemId] ?? 0) + item.qty;
      }
    }
    return sold;
  }

  String? _stockItemIdForProductName(String productName) {
    final normalized = _normalizeName(productName);
    if (normalized.contains('bistec')) return 'bistec';
    if (normalized.contains('adobada')) return 'adobada';
    if (normalized.contains('carnaza')) return 'carnaza';
    if (normalized.contains('arrachera')) return 'arrachera';
    if (normalized.contains('chorizo')) return 'chorizo';
    if (normalized.contains('higado')) return 'higado';
    if (normalized.contains('labio')) return 'labio';
    if (normalized.contains('tripa')) return 'tripa';
    if (normalized.contains('lengua')) return 'lengua';
    if (normalized.contains('coca') || normalized.contains('refresco')) {
      return 'refresco_coca_cola';
    }
    return null;
  }

  List<ProductRecipeItem> _defaultRecipeItemsForProduct(
    Product product,
    Map<String, KitchenStockItem> stockById,
  ) {
    final normalizedName = _normalizeName(product.name);
    final normalizedCategory = _normalizeName(product.category);
    final meatId = _stockItemIdForProductName(product.name);
    final isDrink =
        normalizedCategory == 'bebidas' ||
        normalizedName.contains('refresco') ||
        normalizedName.contains('coca');
    if (isDrink) {
      return [
        _recipeItemForStockId(
          'refresco_coca_cola',
          stockById,
          fallbackName: 'Refresco Coca Cola',
          fallbackUnit: 'piece',
          factor: 1,
        ),
      ];
    }

    if (meatId == null) {
      return const [];
    }

    if (normalizedName.contains('gringa')) {
      final isGrande =
          normalizedName.contains('grande') ||
          normalizedName.contains('gde') ||
          normalizedName.contains('gringa grande');
      return [
        _recipeItemForStockId(
          meatId,
          stockById,
          fallbackName: _titleFromId(meatId),
          fallbackUnit: 'kg',
          factor: isGrande ? 3.5 : 2.5,
        ),
      ];
    }

    if (normalizedCategory == 'tacos' || normalizedName.contains('taco')) {
      return [
        _recipeItemForStockId(
          meatId,
          stockById,
          fallbackName: _titleFromId(meatId),
          fallbackUnit: 'kg',
          factor: 1,
        ),
      ];
    }

    return [
      _recipeItemForStockId(
        meatId,
        stockById,
        fallbackName: _titleFromId(meatId),
        fallbackUnit: 'kg',
        factor: 1,
      ),
    ];
  }

  ProductRecipeItem _recipeItemForStockId(
    String stockItemId,
    Map<String, KitchenStockItem> stockById, {
    required String fallbackName,
    required String fallbackUnit,
    required double factor,
  }) {
    final stockItem = stockById[stockItemId];
    return ProductRecipeItem(
      kitchenStockItemId: stockItemId,
      kitchenStockItemName: stockItem?.name ?? fallbackName,
      kitchenStockUnit: stockItem?.unit ?? fallbackUnit,
      consumptionFactor: factor,
    );
  }

  String _titleFromId(String id) {
    return id
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  bool _defaultProductAffectsKitchenStock(Product product) {
    final category = _normalizeName(product.category);
    final name = _normalizeName(product.name);
    if (category == 'tacos' ||
        name.contains('taco') ||
        name.contains('gringa')) {
      return true;
    }
    if (category == 'bebidas' || name.contains('refresco')) {
      return true;
    }
    return false;
  }

  KitchenStockItem _fallbackStockItemForRecipeItem(
    ProductRecipeItem recipeItem,
    Product product,
  ) {
    final id = recipeItem.kitchenStockItemId;
    final category = _normalizeName(product.category);
    final isDrink =
        recipeItem.kitchenStockUnit == 'piece' ||
        category == 'bebidas' ||
        id.contains('refresco');
    final isTortilla = id.contains('tortilla');
    return KitchenStockItem(
      id: id,
      name: recipeItem.kitchenStockItemName,
      category: isDrink
          ? 'drink'
          : isTortilla
          ? 'tortilla'
          : id == 'queso'
          ? 'dairy'
          : 'meat',
      unit: recipeItem.kitchenStockUnit,
      active: true,
      sortOrder: isDrink
          ? 50
          : isTortilla
          ? 15
          : id == 'queso'
          ? 14
          : 20,
      optimalConsumptionPerSaleQty: recipeItem.kitchenStockUnit == 'piece'
          ? 1
          : 50,
      optimalConsumptionUnit: recipeItem.kitchenStockUnit == 'piece'
          ? 'piece_per_item'
          : 'g_per_item',
    );
  }

  String _normalizeName(String value) {
    return value
        .toLowerCase()
        .replaceAll('í', 'i')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
  }

  String _businessDateFor(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  bool _dateInRange(DateTime? date, DateTime startDate, DateTime endDate) {
    if (date == null) {
      return false;
    }
    final day = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  bool _orderBelongsToBusinessDate(PosOrder order, String businessDate) {
    final candidates = [order.paidAt, order.createdAt, order.updatedAt];
    return candidates.whereType<DateTime>().any(
      (date) => _businessDateFor(date) == businessDate,
    );
  }

  bool _isFinalOrderStatus(String status) {
    return ['paid', 'cancelled', 'voided'].contains(status);
  }

  bool _isPendingKitchenStatus(String status) {
    return ['pending', 'sent', 'cooking', 'cancel_requested'].contains(status);
  }

  Future<bool> _kitchenCloseIsComplete(String kitchenSessionId) async {
    final itemsSnapshot = await _kitchenSessionsRef
        .doc(kitchenSessionId)
        .collection('items')
        .get();
    if (itemsSnapshot.docs.isEmpty) {
      return false;
    }
    for (final doc in itemsSnapshot.docs) {
      final data = doc.data();
      if (data['finalRemainingQty'] == null ||
          data['usedQty'] == null ||
          data['usefulConsumedQty'] == null) {
        return false;
      }
    }
    return true;
  }

  double _yieldPerSale({
    required String unit,
    required double usefulConsumedQty,
    required double soldQty,
  }) {
    if (soldQty <= 0 || usefulConsumedQty <= 0) {
      return 0;
    }
    if (unit == 'kg') {
      return (usefulConsumedQty * 1000) / soldQty;
    }
    return usefulConsumedQty / soldQty;
  }

  Future<PosOrder> createOrGetOpenOrder(PosTable table) async {
    developer.log(
      '[TacoPOS][openTable] tableId=${table.id} tableName=${table.name} '
      'currentOrderId=${table.currentOrderId ?? '-'} tableStatus=${table.status}',
    );

    final activeOrdersById = <String, PosOrder>{};
    final currentOrderId = table.currentOrderId?.trim();
    if (currentOrderId != null && currentOrderId.isNotEmpty) {
      final currentDoc = await _ordersRef.doc(currentOrderId).get();
      if (currentDoc.exists) {
        final currentOrder = PosOrder.fromDoc(currentDoc);
        if (_isActiveDineInOrderForTable(currentOrder, table.id) &&
            _matchesCurrentBranch(currentOrder.branchId)) {
          activeOrdersById[currentOrder.id] = currentOrder;
        } else {
          developer.log(
            '[TacoPOS][openTable] currentOrderId stale: $currentOrderId '
            'orderStatus=${currentOrder.status} paymentStatus=${currentOrder.paymentStatus} '
            'orderTableId=${currentOrder.tableId}',
          );
        }
      } else {
        developer.log(
          '[TacoPOS][openTable] currentOrderId missing in Firestore: '
          '$currentOrderId',
        );
      }
    }

    final snapshot = await _ordersRef
        .where('tableId', isEqualTo: table.id)
        .get();
    for (final doc in snapshot.docs) {
      final order = PosOrder.fromDoc(doc);
      if (_isActiveDineInOrderForTable(order, table.id) &&
          _matchesCurrentBranch(order.branchId)) {
        activeOrdersById[order.id] = order;
      }
    }

    if (activeOrdersById.isNotEmpty) {
      _requireAnyPermission(
        takeOrders: true,
        charge: true,
        message: 'No tienes permiso para abrir ordenes.',
      );
      final order = await _bestActiveOrder(activeOrdersById.values.toList());
      await _tablesRef.doc(table.id).set({
        'status': order.status == 'open' ? 'occupied' : order.status,
        'currentOrderId': order.id,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final itemCount = await _orderItemCount(order.id);
      developer.log(
        '[TacoPOS][openTable] using existing orderId=${order.id} '
        'tableId=${order.tableId} total=${order.total} itemCount=$itemCount '
        'status=${order.status} paymentStatus=${order.paymentStatus}',
      );
      return order;
    }

    _requireTakeOrders();
    final orderRef = _ordersRef.doc();
    final data = {
      'tableId': table.id,
      'tableName': table.name,
      'orderType': 'dine_in',
      'status': 'open',
      'kitchenStatus': 'pending',
      'paymentStatus': 'pending',
      'total': 0.0,
      'paidTotal': 0.0,
      'pendingTotal': 0.0,
      'personNames': {'1': 'Persona 1'},
      ..._currentBranchFields,
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      ..._employeeAuditFields(prefix: 'createdBy'),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = _db.batch();
    batch.set(orderRef, data);
    batch.set(_tablesRef.doc(table.id), {
      'status': 'occupied',
      'currentOrderId': orderRef.id,
      ..._currentBranchFields,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();

    final doc = await orderRef.get();
    final order = PosOrder.fromDoc(doc);
    developer.log(
      '[TacoPOS][openTable] created new orderId=${order.id} '
      'tableId=${order.tableId} path=restaurants/${AppConstants.restaurantId}/orders/${order.id}',
    );
    return order;
  }

  bool _isActiveDineInOrderForTable(PosOrder order, String tableId) {
    return order.tableId == tableId &&
        order.orderType == 'dine_in' &&
        ['open', 'sent', 'ready', 'cooking'].contains(order.status) &&
        ['pending', 'partial'].contains(order.paymentStatus);
  }

  Future<PosOrder> _bestActiveOrder(List<PosOrder> orders) async {
    final scored = <({PosOrder order, int itemCount})>[];
    for (final order in orders) {
      scored.add((order: order, itemCount: await _orderItemCount(order.id)));
    }
    scored.sort((a, b) {
      final aHasContent = a.itemCount > 0 || a.order.total > 0;
      final bHasContent = b.itemCount > 0 || b.order.total > 0;
      if (aHasContent != bHasContent) {
        return bHasContent ? 1 : -1;
      }
      if (a.itemCount != b.itemCount) {
        return b.itemCount.compareTo(a.itemCount);
      }
      if (a.order.total != b.order.total) {
        return b.order.total.compareTo(a.order.total);
      }
      final aDate =
          a.order.updatedAt ??
          a.order.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          b.order.updatedAt ??
          b.order.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return scored.first.order;
  }

  Future<int> _orderItemCount(String orderId) async {
    final snapshot = await _ordersRef.doc(orderId).collection('items').get();
    return snapshot.docs.length;
  }

  Future<PosOrder> createTakeoutOrder({
    required OrderPlatform platform,
    String? customerName,
  }) async {
    _requireTakeOrders();
    final orderRef = _ordersRef.doc();
    final takeoutNumber = await _nextTakeoutNumber();
    final cleanCustomer = customerName?.trim();
    final data = {
      'tableId': 'takeout',
      'tableName': 'Para llevar',
      'orderType': 'takeout',
      'platformId': platform.id,
      'platformName': platform.name,
      'takeoutNumber': takeoutNumber,
      if (cleanCustomer != null && cleanCustomer.isNotEmpty)
        'customerName': cleanCustomer,
      'status': 'open',
      'kitchenStatus': 'pending',
      'paymentStatus': 'pending',
      'total': 0.0,
      'paidTotal': 0.0,
      'pendingTotal': 0.0,
      'personNames': {'1': 'Persona 1'},
      ..._currentBranchFields,
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      ..._employeeAuditFields(prefix: 'createdBy'),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await orderRef.set(data);
    final doc = await orderRef.get();
    return PosOrder.fromDoc(doc);
  }

  Future<int> _nextTakeoutNumber() async {
    final snapshot = await _ordersRef.get();
    var maxNumber = 0;
    for (final doc in snapshot.docs) {
      final order = PosOrder.fromDoc(doc);
      if (!_matchesCurrentBranch(order.branchId)) {
        continue;
      }
      final number = (doc.data()['takeoutNumber'] as num?)?.toInt() ?? 0;
      if (number > maxNumber) {
        maxNumber = number;
      }
    }
    return maxNumber + 1;
  }

  Future<void> addProductToOrder({
    required String orderId,
    required Product product,
    required int personNumber,
  }) async {
    _requireTakeOrders();
    final cleanOrderId = orderId.trim();
    final itemsPath =
        'restaurants/${AppConstants.restaurantId}/orders/$cleanOrderId/items';
    developer.log(
      '[TacoPOS][addProduct] orderId=$cleanOrderId path=$itemsPath '
      'productName=${product.name} qty=1',
    );
    final orderDoc = await _ordersRef.doc(cleanOrderId).get();
    final order = orderDoc.exists ? PosOrder.fromDoc(orderDoc) : null;
    final personName =
        order?.personName(personNumber) ?? 'Persona $personNumber';
    final platformId = order?.orderType == 'takeout' ? order?.platformId : null;
    final platformName = order?.orderType == 'takeout'
        ? order?.platformName
        : null;
    final usePlatformPrice = platformId != null && platformId != 'en_persona';
    final appliedPrice = usePlatformPrice
        ? product.priceForPlatform(platformId)
        : product.price;
    final existingItem = await _findMatchingPendingItem(
      orderId: cleanOrderId,
      productId: product.id,
      personNumber: personNumber,
      appliedPlatformId: usePlatformPrice ? platformId : null,
    );

    if (existingItem != null) {
      developer.log(
        '[TacoPOS][addProduct] updating existing itemId=${existingItem.id} '
        'path=$itemsPath/${existingItem.id} productName=${product.name} '
        'qty=${existingItem.qty + 1}',
      );
      await updateItemQty(
        orderId: cleanOrderId,
        item: existingItem,
        qty: existingItem.qty + 1,
      );
      return;
    }

    final primaryRecipe = product.recipeItems.isNotEmpty
        ? product.recipeItems.first
        : null;
    final itemRef = _ordersRef.doc(cleanOrderId).collection('items').doc();
    await itemRef.set({
      'personNumber': personNumber,
      'personName': personName,
      'productId': product.id,
      'productName': product.name,
      'categoryId': product.categoryId,
      'categoryName': product.categoryName,
      'category': product.category,
      'qty': 1,
      'unitPrice': appliedPrice,
      'total': appliedPrice,
      'appliedPlatformId': usePlatformPrice ? platformId : null,
      'appliedPlatformName': usePlatformPrice ? platformName : null,
      'priceSource': usePlatformPrice ? 'platform' : 'store',
      'notes': '',
      ..._currentBranchFields,
      ..._employeeAuditFields(prefix: 'createdBy'),
      'sendToKitchen': product.sendToKitchen,
      'affectsKitchenStock': product.affectsKitchenStock,
      'recipeItems': product.affectsKitchenStock
          ? ProductRecipeItem.toMapList(product.recipeItems.take(1).toList())
          : const [],
      'kitchenStockItemId': product.affectsKitchenStock
          ? primaryRecipe?.kitchenStockItemId ?? product.kitchenStockItemId
          : null,
      'kitchenStockItemName': product.affectsKitchenStock
          ? primaryRecipe?.kitchenStockItemName ?? product.kitchenStockItemName
          : null,
      'kitchenStockUnit': product.affectsKitchenStock
          ? primaryRecipe?.kitchenStockUnit ?? product.kitchenStockUnit
          : null,
      'stockConsumptionQty': product.affectsKitchenStock
          ? primaryRecipe?.consumptionFactor ?? product.stockConsumptionQty
          : null,
      'kitchenConsumptionFactor': product.affectsKitchenStock
          ? primaryRecipe?.consumptionFactor ?? product.stockConsumptionQty
          : null,
      'kitchenStatus': product.sendToKitchen ? 'pending' : 'not_required',
      'kitchenBatchId': null,
      'paymentStatus': 'pending',
      'status': 'active',
      'cancelStatus': 'none',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    developer.log(
      '[TacoPOS][addProduct] saved itemId=${itemRef.id} '
      'path=$itemsPath/${itemRef.id} productName=${product.name} qty=1',
    );
    await recalculateOrderTotal(cleanOrderId);
  }

  Future<void> renamePerson({
    required String orderId,
    required int personNumber,
    required String name,
  }) async {
    _requireTakeOrders();
    final cleanName = name.trim().isEmpty
        ? 'Persona $personNumber'
        : name.trim();
    final orderRef = _ordersRef.doc(orderId);
    final itemsSnapshot = await orderRef.collection('items').get();
    final batch = _db.batch();

    batch.update(orderRef, {
      'personNames.$personNumber': cleanName,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.personNumber == personNumber) {
        batch.update(doc.reference, {
          'personName': cleanName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();
  }

  Future<OrderItem?> _findMatchingPendingItem({
    required String orderId,
    required String productId,
    required int personNumber,
    String? appliedPlatformId,
  }) async {
    final snapshot = await _ordersRef.doc(orderId).collection('items').get();

    for (final doc in snapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.productId == productId &&
          item.personNumber == personNumber &&
          item.appliedPlatformId == appliedPlatformId &&
          item.kitchenStatus == 'pending' &&
          item.paymentStatus == 'pending') {
        return item;
      }
    }
    return null;
  }

  Future<void> updateItemQty({
    required String orderId,
    required OrderItem item,
    required int qty,
  }) async {
    _requireTakeOrders();
    _ensureItemEditable(item);
    if (qty <= 0) {
      await deleteItem(orderId: orderId, itemId: item.id);
      return;
    }

    await _ordersRef.doc(orderId).collection('items').doc(item.id).update({
      'qty': qty,
      'total': qty * item.unitPrice,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await recalculateOrderTotal(orderId);
  }

  Future<void> deleteItem({
    required String orderId,
    required String itemId,
    String reason = 'Cancelado desde orden',
  }) async {
    await cancelOrderItem(orderId: orderId, itemId: itemId, reason: reason);
  }

  Future<void> cancelOrderItem({
    required String orderId,
    required String itemId,
    required String reason,
  }) async {
    _requireCancelItems();
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Captura el motivo de cancelacion.');
    }
    final itemDoc = await _ordersRef
        .doc(orderId)
        .collection('items')
        .doc(itemId)
        .get();
    if (!itemDoc.exists) {
      throw StateError('El articulo ya no existe.');
    }
    final item = OrderItem.fromDoc(itemDoc);
    if (item.kitchenStatus == 'ready') {
      throw StateError(
        'Este producto ya fue servido por cocina y no puede cancelarse.',
      );
    }
    if (['sent', 'cooking', 'cancel_requested'].contains(item.kitchenStatus)) {
      throw StateError(
        'Este producto ya esta en cocina. Solicita cancelacion a cocina.',
      );
    }
    if (item.paymentStatus == 'paid') {
      throw StateError('Este producto ya fue pagado y no puede cancelarse.');
    }
    await _ensureCancellationKeepsPaymentsValid(orderId, item);
    await itemDoc.reference.update({
      'status': 'cancelled',
      'kitchenStatus': 'cancelled',
      'paymentStatus': 'cancelled',
      'cancelStatus': 'accepted',
      'cancelReason': cleanReason,
      'cancelledAt': FieldValue.serverTimestamp(),
      ..._employeeAuditFields(prefix: 'cancelledBy'),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await recalculateOrderTotal(orderId);
    await _restaurantRef.collection('activityLog').add({
      'type': 'order_item_cancelled',
      ..._currentBranchFields,
      'orderId': orderId,
      'itemId': item.id,
      'productName': item.productName,
      'qty': item.qty,
      'reason': cleanReason,
      'employeeId': AppSession.instance.employee?.id ?? '',
      'employeeName': AppSession.instance.employee?.name ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
    });
  }

  Future<void> requestOrderItemCancellation({
    required String orderId,
    required String itemId,
    required String reason,
  }) async {
    _requireCancelItems();
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Captura el motivo de cancelacion.');
    }
    final itemRef = _ordersRef.doc(orderId).collection('items').doc(itemId);
    final itemDoc = await itemRef.get();
    if (!itemDoc.exists) {
      throw StateError('El articulo ya no existe.');
    }
    final item = OrderItem.fromDoc(itemDoc);
    if (item.kitchenStatus == 'ready') {
      throw StateError(
        'Este producto ya fue servido por cocina y no puede cancelarse.',
      );
    }
    if (!['sent', 'cooking', 'cancel_requested'].contains(item.kitchenStatus)) {
      throw StateError('Solo se solicita cancelacion de articulos en cocina.');
    }
    if (item.hasCancellationRequested) {
      throw StateError('La cancelacion ya fue solicitada a cocina.');
    }
    await itemRef.update({
      'cancelStatus': 'requested',
      'kitchenStatus': 'cancel_requested',
      'cancelReason': cleanReason,
      'cancelRequestedAt': FieldValue.serverTimestamp(),
      ..._employeeAuditFields(prefix: 'cancelRequestedBy'),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _ordersRef.doc(orderId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resolveKitchenCancellation({
    required String orderId,
    required String itemId,
    required bool accepted,
    String rejectReason = '',
  }) async {
    _requireKitchenCancellationApprover();
    final itemRef = _ordersRef.doc(orderId).collection('items').doc(itemId);
    final itemDoc = await itemRef.get();
    if (!itemDoc.exists) {
      throw StateError('El articulo ya no existe.');
    }
    final item = OrderItem.fromDoc(itemDoc);
    if (!item.hasCancellationRequested) {
      throw StateError('Este articulo no tiene cancelacion solicitada.');
    }
    if (accepted) {
      await _ensureCancellationKeepsPaymentsValid(orderId, item);
      await itemRef.update({
        'status': 'cancelled',
        'kitchenStatus': 'cancelled',
        'paymentStatus': 'cancelled',
        'cancelStatus': 'accepted',
        'cancelAcceptedAt': FieldValue.serverTimestamp(),
        'cancelledAt': FieldValue.serverTimestamp(),
        ..._employeeAuditFields(prefix: 'cancelAcceptedBy'),
        ..._employeeAuditFields(prefix: 'cancelledBy'),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await recalculateOrderTotal(orderId);
      return;
    }

    final restoredKitchenStatus = item.cookingAt != null ? 'cooking' : 'sent';
    await itemRef.update({
      'cancelStatus': 'rejected',
      'kitchenStatus': restoredKitchenStatus,
      'cancelRejectedAt': FieldValue.serverTimestamp(),
      'cancelRejectReason': rejectReason.trim(),
      ..._employeeAuditFields(prefix: 'cancelRejectedBy'),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _ordersRef.doc(orderId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancelOrder({
    required String orderId,
    required String reason,
  }) async {
    _requireCancelOrders();
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Captura el motivo de cancelacion.');
    }

    final orderRef = _ordersRef.doc(orderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists) {
      throw StateError('La orden ya no existe.');
    }
    final order = PosOrder.fromDoc(orderDoc);
    if (_isPaidStatus(order.paymentStatus) ||
        (order.paidAt != null && order.paidTotal > 0.01)) {
      throw StateError('No se puede cancelar una orden pagada al 100%.');
    }

    final itemsSnapshot = await orderRef.collection('items').get();
    final items = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
    final activeItems = items.where(isActiveOrderItem).toList();
    if (activeItems.any((item) => item.kitchenStatus == 'ready')) {
      throw StateError(
        'No se puede cancelar: hay productos servidos por cocina.',
      );
    }

    final paymentsSnapshot = await orderRef.collection('payments').get();
    final activePayments = paymentsSnapshot.docs
        .map(Payment.fromDoc)
        .where(isActivePayment)
        .toList();
    final activePaidTotal = activePayments.fold<double>(
      0,
      (total, payment) => total + payment.baseAmount,
    );
    if (activePayments.isNotEmpty && activePaidTotal > 0.01) {
      throw StateError('No se puede cancelar: los pagos cierran la orden.');
    }

    final batch = _db.batch();
    final audit = _employeeAuditFields(prefix: 'cancelledBy');
    batch.update(orderRef, {
      'status': 'cancelled',
      'kitchenStatus': 'cancelled',
      'paymentStatus': 'cancelled',
      'total': 0.0,
      'paidTotal': 0.0,
      'pendingTotal': 0.0,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelReason': cleanReason,
      ...audit,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.isCancelled) {
        continue;
      }
      batch.update(doc.reference, {
        'kitchenStatus': 'cancelled',
        'paymentStatus': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelReason': cleanReason,
        ...audit,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _logActivityInBatch(
        batch,
        type: 'order_item_cancelled',
        orderId: order.id,
        data: {
          'itemId': item.id,
          'productName': item.productName,
          'qty': item.qty,
          'reason': cleanReason,
        },
      );
    }

    if (order.orderType != 'takeout') {
      batch.set(_tablesRef.doc(order.tableId), {
        'status': 'available',
        'currentOrderId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    _logActivityInBatch(
      batch,
      type: 'order_cancelled',
      orderId: order.id,
      data: {'reason': cleanReason, 'total': order.total},
    );
    await batch.commit();
  }

  Future<void> cancelEmptyOrder(String orderId) async {
    final orderDoc = await _ordersRef.doc(orderId).get();
    if (!orderDoc.exists) {
      throw StateError('La orden ya no existe.');
    }
    final order = PosOrder.fromDoc(orderDoc);
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final paymentsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('payments')
        .get();

    if (itemsSnapshot.docs.isNotEmpty) {
      throw StateError('No se puede cerrar: la orden ya tiene articulos.');
    }
    if (paymentsSnapshot.docs.isNotEmpty) {
      throw StateError('No se puede cerrar: la orden ya tiene pagos.');
    }
    if (order.status != 'open' ||
        order.sentToKitchenAt != null ||
        ['sent', 'cooking', 'ready'].contains(order.kitchenStatus)) {
      throw StateError('No se puede cerrar: la orden ya fue enviada a cocina.');
    }

    final batch = _db.batch();
    batch.update(_ordersRef.doc(orderId), {
      'status': 'cancelled',
      'kitchenStatus': 'cancelled',
      'paymentStatus': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      ..._employeeAuditFields(prefix: 'cancelledBy'),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (order.orderType != 'takeout') {
      batch.set(_tablesRef.doc(order.tableId), {
        'status': 'available',
        'currentOrderId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<int> sendOrderToKitchen(String orderId) async {
    _requireTakeOrders();
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final batch = _db.batch();
    final kitchenBatchId = _ordersRef
        .doc(orderId)
        .collection('kitchenBatches')
        .doc()
        .id;
    var sentCount = 0;

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      final shouldAttachToBatch =
          item.kitchenBatchId == null &&
          item.paymentStatus == 'pending' &&
          (item.kitchenStatus == 'pending' ||
              item.kitchenStatus == 'not_required');
      if (item.sendToKitchen && item.kitchenStatus == 'pending') {
        sentCount += 1;
        batch.update(doc.reference, {
          'kitchenStatus': 'sent',
          'kitchenBatchId': kitchenBatchId,
          'sentToKitchenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (shouldAttachToBatch) {
        batch.update(doc.reference, {
          'kitchenBatchId': kitchenBatchId,
          'sentToKitchenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    if (sentCount == 0) {
      return 0;
    }

    final orderDoc = await _ordersRef.doc(orderId).get();
    final orderData = orderDoc.data();
    final tableId = orderData?['tableId'] as String?;
    final orderType = orderData?['orderType'] as String? ?? 'dine_in';
    batch.update(_ordersRef.doc(orderId), {
      'status': 'sent',
      'kitchenStatus': 'sent',
      'sentToKitchenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (tableId != null && orderType != 'takeout') {
      batch.set(_tablesRef.doc(tableId), {
        'status': 'sent',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
    return sentCount;
  }

  Future<void> updateKitchenStatus({
    required String orderId,
    required String status,
  }) async {
    final normalizedStatus = status == 'preparing' ? 'cooking' : status;
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final batch = _db.batch();
    var changed = 0;

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.sendToKitchen &&
          ['sent', 'cooking'].contains(item.kitchenStatus)) {
        changed += 1;
        batch.update(doc.reference, {
          'kitchenStatus': normalizedStatus,
          if (normalizedStatus == 'cooking' && item.cookingAt == null)
            'cookingAt': FieldValue.serverTimestamp(),
          if (normalizedStatus == 'ready')
            'readyAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    if (changed == 0) {
      return;
    }

    final orderDoc = await _ordersRef.doc(orderId).get();
    final orderData = orderDoc.data();
    final tableId = orderData?['tableId'] as String?;
    final orderType = orderData?['orderType'] as String? ?? 'dine_in';
    final orderStatus = normalizedStatus == 'ready'
        ? 'ready'
        : normalizedStatus == 'cooking'
        ? 'cooking'
        : 'sent';

    batch.update(_ordersRef.doc(orderId), {
      'status': orderStatus,
      'kitchenStatus': normalizedStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _logActivityInBatch(
      batch,
      type: 'kitchen_status_changed',
      orderId: orderId,
      data: {'kitchenStatus': normalizedStatus},
    );

    if (tableId != null && orderType != 'takeout') {
      batch.set(_tablesRef.doc(tableId), {
        'status': orderStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<void> updateKitchenItemsStatus({
    required String orderId,
    required Iterable<String> itemIds,
    required String status,
  }) async {
    final normalizedStatus = status == 'preparing' ? 'cooking' : status;
    final targetIds = itemIds.toSet();
    if (targetIds.isEmpty) {
      return;
    }

    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final allItems = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
    final batch = _db.batch();
    final changedIds = <String>{};

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (targetIds.contains(item.id) &&
          item.sendToKitchen &&
          ['sent', 'cooking'].contains(item.kitchenStatus)) {
        changedIds.add(item.id);
        batch.update(doc.reference, {
          'kitchenStatus': normalizedStatus,
          if (normalizedStatus == 'cooking' && item.cookingAt == null)
            'cookingAt': FieldValue.serverTimestamp(),
          if (normalizedStatus == 'ready')
            'readyAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    if (changedIds.isEmpty) {
      return;
    }

    final orderDoc = await _ordersRef.doc(orderId).get();
    final orderData = orderDoc.data();
    final tableId = orderData?['tableId'] as String?;
    final orderType = orderData?['orderType'] as String? ?? 'dine_in';
    final kitchenStatus = _aggregateKitchenStatus(
      allItems: allItems,
      changedIds: changedIds,
      changedStatus: normalizedStatus,
    );
    final orderStatus = ['ready', 'not_required'].contains(kitchenStatus)
        ? 'ready'
        : kitchenStatus == 'cooking'
        ? 'cooking'
        : 'sent';

    batch.update(_ordersRef.doc(orderId), {
      'status': orderStatus,
      'kitchenStatus': kitchenStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _logActivityInBatch(
      batch,
      type: 'kitchen_status_changed',
      orderId: orderId,
      data: {'kitchenStatus': kitchenStatus},
    );

    if (tableId != null && orderType != 'takeout') {
      batch.set(_tablesRef.doc(tableId), {
        'status': orderStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  String _aggregateKitchenStatus({
    required List<OrderItem> allItems,
    required Set<String> changedIds,
    required String changedStatus,
  }) {
    var hasPending = false;
    var hasSent = false;
    var hasCooking = false;
    var hasReady = false;

    for (final item in allItems.where((item) => item.sendToKitchen)) {
      final status = changedIds.contains(item.id)
          ? changedStatus
          : item.kitchenStatus;

      switch (status) {
        case 'cooking':
          hasCooking = true;
        case 'sent':
          hasSent = true;
        case 'pending':
          hasPending = true;
        case 'ready':
          hasReady = true;
      }
    }

    if (hasCooking) {
      return 'cooking';
    }
    if (hasSent) {
      return 'sent';
    }
    if (hasPending) {
      return 'pending';
    }
    if (hasReady) {
      return 'ready';
    }
    return 'not_required';
  }

  Future<void> markActiveKitchenItemsCooking(String orderId) {
    return updateKitchenStatus(orderId: orderId, status: 'cooking');
  }

  Future<PaymentResult> payFullTable({
    required String orderId,
    required String method,
    String? employeeId,
    String? employeeName,
    CashPaymentDetails? cashDetails,
  }) async {
    _requireCharge();
    final cashSession = await _requireOpenCashSessionForPayment();
    await _ensureNoPaymentType(orderId, blockedType: 'person');
    await _ensureEmployeeConsumptionAllowed(orderId, method);
    await _ensureKitchenReadyForPayment(orderId);
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = PosOrder.fromDoc(orderDoc);
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final pendingItems = itemsSnapshot.docs
        .map(OrderItem.fromDoc)
        .where((item) => item.paymentStatus != 'paid' && !item.isCancelled)
        .toList();
    final baseAmount = pendingItems.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.total,
    );

    if (baseAmount <= 0) {
      return const PaymentResult(allPaid: true);
    }

    final paymentRef = _ordersRef.doc(orderId).collection('payments').doc();
    final batch = _db.batch();
    _setPayment(
      batch: batch,
      paymentRef: paymentRef,
      order: order,
      cashSession: cashSession,
      type: 'full_table',
      method: method,
      baseAmount: baseAmount,
      employeeId: employeeId,
      employeeName: employeeName,
      cashDetails: cashDetails,
    );

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.paymentStatus != 'paid' && !item.isCancelled) {
        batch.update(doc.reference, {
          'paymentStatus': 'paid',
          'paidAt': FieldValue.serverTimestamp(),
          'paymentId': paymentRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    _closeOrderInBatch(batch, order, paidTotal: order.total);
    await batch.commit();
    return const PaymentResult(allPaid: true);
  }

  Future<PaymentResult> payPerson({
    required String orderId,
    required int personNumber,
    required String method,
    String? employeeId,
    String? employeeName,
    CashPaymentDetails? cashDetails,
  }) async {
    _requireCharge();
    final cashSession = await _requireOpenCashSessionForPayment();
    await _ensureNoPaymentType(orderId, blockedType: 'partial');
    await _ensureEmployeeConsumptionAllowed(orderId, method);
    await _ensureKitchenReadyForPayment(orderId);
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = PosOrder.fromDoc(orderDoc);
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final items = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
    final personItems = items
        .where(
          (item) =>
              item.personNumber == personNumber &&
              item.paymentStatus != 'paid' &&
              !item.isCancelled,
        )
        .toList();
    final personName = personItems.isEmpty
        ? 'Persona $personNumber'
        : personItems.first.personName;
    final baseAmount = personItems.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.total,
    );

    if (baseAmount <= 0) {
      return PaymentResult(allPaid: order.pendingTotal <= 0.01);
    }

    final paymentRef = _ordersRef.doc(orderId).collection('payments').doc();
    final batch = _db.batch();
    _setPayment(
      batch: batch,
      paymentRef: paymentRef,
      order: order,
      cashSession: cashSession,
      type: 'person',
      method: method,
      baseAmount: baseAmount,
      personNumber: personNumber,
      personName: personName,
      employeeId: employeeId,
      employeeName: employeeName,
      cashDetails: cashDetails,
    );

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.personNumber == personNumber &&
          item.paymentStatus != 'paid' &&
          !item.isCancelled) {
        batch.update(doc.reference, {
          'paymentStatus': 'paid',
          'paidAt': FieldValue.serverTimestamp(),
          'paymentId': paymentRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    final allPaid = _updateOrderPaymentTotalsInBatch(
      batch,
      order,
      baseAmount: baseAmount,
      closeItemsSnapshot: itemsSnapshot,
    );
    await batch.commit();
    return PaymentResult(allPaid: allPaid);
  }

  Future<PaymentResult> payPartialAmount({
    required String orderId,
    required double baseAmount,
    required String method,
    String? employeeId,
    String? employeeName,
    CashPaymentDetails? cashDetails,
  }) async {
    _requireCharge();
    final cashSession = await _requireOpenCashSessionForPayment();
    await _ensureNoPaymentType(orderId, blockedType: 'person');
    await _ensureEmployeeConsumptionAllowed(orderId, method);
    await _ensureKitchenReadyForPayment(orderId);
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = PosOrder.fromDoc(orderDoc);

    if (baseAmount <= 0 || baseAmount > order.pendingTotal + 0.01) {
      throw ArgumentError('Monto parcial invalido.');
    }

    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final paymentRef = _ordersRef.doc(orderId).collection('payments').doc();
    final batch = _db.batch();
    _setPayment(
      batch: batch,
      paymentRef: paymentRef,
      order: order,
      cashSession: cashSession,
      type: 'partial',
      method: method,
      baseAmount: baseAmount,
      employeeId: employeeId,
      employeeName: employeeName,
      cashDetails: cashDetails,
    );

    final allPaid = _updateOrderPaymentTotalsInBatch(
      batch,
      order,
      baseAmount: baseAmount,
      closeItemsSnapshot: itemsSnapshot,
      markItemsOnlyIfClosed: true,
    );
    await batch.commit();
    return PaymentResult(allPaid: allPaid);
  }

  Future<PaymentResult> payPlatformOrder({required String orderId}) async {
    _requireCharge();
    final cashSession = await _requireOpenCashSessionForPayment();
    await _ensureKitchenReadyForPayment(orderId);
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = PosOrder.fromDoc(orderDoc);
    if (order.orderType != 'takeout' || order.platformId == 'en_persona') {
      throw StateError('Este pedido no aplica para pago en plataforma.');
    }

    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final pendingItems = itemsSnapshot.docs
        .map(OrderItem.fromDoc)
        .where((item) => item.paymentStatus != 'paid' && !item.isCancelled)
        .toList();
    final baseAmount = pendingItems.fold<double>(
      0,
      (runningTotal, item) => runningTotal + item.total,
    );

    if (baseAmount <= 0) {
      return const PaymentResult(allPaid: true);
    }

    final paymentRef = _ordersRef.doc(orderId).collection('payments').doc();
    final batch = _db.batch();
    _setPayment(
      batch: batch,
      paymentRef: paymentRef,
      order: order,
      cashSession: cashSession,
      type: 'platform',
      method: 'platform_paid',
      baseAmount: baseAmount,
      platformId: order.platformId,
      platformName: order.platformName,
    );

    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.paymentStatus != 'paid' && !item.isCancelled) {
        batch.update(doc.reference, {
          'paymentStatus': 'paid',
          'paidAt': FieldValue.serverTimestamp(),
          'paymentId': paymentRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    _closeOrderInBatch(batch, order, paidTotal: order.total);
    await batch.commit();
    return const PaymentResult(allPaid: true);
  }

  bool _updateOrderPaymentTotalsInBatch(
    WriteBatch batch,
    PosOrder order, {
    required double baseAmount,
    required QuerySnapshot<Map<String, dynamic>> closeItemsSnapshot,
    bool markItemsOnlyIfClosed = false,
  }) {
    final paidTotal = (order.paidTotal + baseAmount).clamp(0, order.total);
    final pendingTotal = (order.total - paidTotal).clamp(0, double.infinity);
    final allPaid = pendingTotal <= 0.01;

    if (allPaid) {
      for (final doc in closeItemsSnapshot.docs) {
        batch.update(doc.reference, {
          'paymentStatus': 'paid',
          'paidAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      _closeOrderInBatch(batch, order, paidTotal: order.total);
    } else {
      batch.update(_ordersRef.doc(order.id), {
        'paymentStatus': 'partial',
        'paidTotal': paidTotal,
        'pendingTotal': pendingTotal,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!markItemsOnlyIfClosed) {
        // Person payments already updated their own items before this method.
      }
    }

    return allPaid;
  }

  void _closeOrderInBatch(
    WriteBatch batch,
    PosOrder order, {
    required double paidTotal,
  }) {
    batch.update(_ordersRef.doc(order.id), {
      'status': 'paid',
      'paymentStatus': 'paid',
      'paidTotal': paidTotal,
      'pendingTotal': 0.0,
      'paidAt': FieldValue.serverTimestamp(),
      ..._currentBranchFields,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (order.orderType != 'takeout') {
      batch.set(_tablesRef.doc(order.tableId), {
        'status': 'available',
        'currentOrderId': FieldValue.delete(),
        ..._currentBranchFields,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  void _setPayment({
    required WriteBatch batch,
    required DocumentReference<Map<String, dynamic>> paymentRef,
    required PosOrder order,
    required CashSession cashSession,
    required String type,
    required String method,
    required double baseAmount,
    int? personNumber,
    String? personName,
    String? employeeId,
    String? employeeName,
    String? platformId,
    String? platformName,
    CashPaymentDetails? cashDetails,
  }) {
    if (method == 'employee_consumption' &&
        (employeeId == null || employeeName == null)) {
      throw ArgumentError('Selecciona un empleado.');
    }

    final cardFeeRate = method == 'card' ? cardSurchargeRate : 0.0;
    final cardFeeAbsorbedAmount = baseAmount * cardFeeRate;
    final surchargeRate = 0.0;
    final surchargeAmount = 0.0;
    final chargedAmount = baseAmount;
    if (method == 'cash' &&
        cashDetails != null &&
        cashDetails.receivedAmount + 0.01 < chargedAmount) {
      throw ArgumentError('El efectivo recibido no cubre el total.');
    }

    batch.set(paymentRef, {
      'orderId': order.id,
      'tableId': order.tableId,
      'tableName': order.tableName,
      'restaurantId': order.restaurantId,
      'restaurantName': order.restaurantName,
      'branchId': order.branchId,
      'branchName': order.branchName,
      'type': type,
      'personNumber': personNumber,
      'personName': personName,
      'method': method,
      'status': 'active',
      'baseAmount': baseAmount,
      'amount': baseAmount,
      'surchargeRate': surchargeRate,
      'surchargeAmount': surchargeAmount,
      'chargedAmount': chargedAmount,
      'cardFeeRate': cardFeeRate,
      'cardFeeAbsorbedAmount': cardFeeAbsorbedAmount,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'platformId': platformId,
      'platformName': platformName,
      if (method == 'cash' && cashDetails != null) ...{
        'cashReceivedAmount': cashDetails.receivedAmount,
        'cashChangeAmount': cashDetails.changeAmount,
      },
      'cashSessionId': cashSession.id,
      'businessDate': cashSession.businessDate,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
      ..._employeeAuditFields(prefix: 'createdBy'),
    });
  }

  Future<void> cancelPayment({
    required String orderId,
    required String paymentId,
    required String reason,
  }) async {
    _requireCancelPayments();
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('Captura el motivo de cancelacion.');
    }

    final orderRef = _ordersRef.doc(orderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists) {
      throw StateError('La orden ya no existe.');
    }
    final order = PosOrder.fromDoc(orderDoc);
    if (order.status == 'paid' || order.paymentStatus == 'paid') {
      throw StateError('No se puede cancelar pagos de una orden cerrada.');
    }

    final paymentRef = orderRef.collection('payments').doc(paymentId);
    final paymentDoc = await paymentRef.get();
    if (!paymentDoc.exists) {
      throw StateError('El pago ya no existe.');
    }
    final payment = Payment.fromDoc(paymentDoc);
    if (!payment.isActive) {
      throw StateError('El pago ya esta cancelado.');
    }

    final paymentsSnapshot = await orderRef.collection('payments').get();
    final paidTotal = paymentsSnapshot.docs
        .map(Payment.fromDoc)
        .where((item) => item.isActive && item.id != paymentId)
        .fold<double>(0, (total, item) => total + item.baseAmount);
    final pendingTotal = (order.total - paidTotal).clamp(0, double.infinity);
    final paymentStatus = paidTotal <= 0.01 ? 'pending' : 'partial';
    final itemsSnapshot = await orderRef.collection('items').get();
    final batch = _db.batch();

    batch.update(paymentRef, {
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelReason': cleanReason,
      ..._employeeAuditFields(prefix: 'cancelledBy'),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    for (final doc in itemsSnapshot.docs) {
      final item = OrderItem.fromDoc(doc);
      if (item.paymentId == paymentId) {
        batch.update(doc.reference, {
          'paymentStatus': 'pending',
          'paymentId': FieldValue.delete(),
          'paidAt': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    batch.update(orderRef, {
      'paymentStatus': paymentStatus,
      'paidTotal': paidTotal,
      'pendingTotal': pendingTotal,
      'paidAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _logActivityInBatch(
      batch,
      type: 'payment_cancelled',
      orderId: order.id,
      data: {
        'paymentId': paymentId,
        'reason': cleanReason,
        'baseAmount': payment.baseAmount,
        'chargedAmount': payment.chargedAmount,
      },
    );
    await batch.commit();
  }

  Map<String, Object> _employeeAuditFields({required String prefix}) {
    final employee = AppSession.instance.employee;
    if (employee == null) {
      return const {};
    }
    return {
      '${prefix}EmployeeId': employee.id,
      '${prefix}EmployeeName': employee.name,
    };
  }

  void _requireTakeOrders() {
    final employee = AppSession.instance.employee;
    if (employee?.canTakeOrders == true ||
        employee?.canControlLiveOperations == true) {
      return;
    }
    throw StateError('No tienes permiso para levantar pedidos');
  }

  void _requireCharge() {
    final employee = AppSession.instance.employee;
    if (employee?.canCharge == true ||
        employee?.canControlLiveOperations == true) {
      return;
    }
    throw StateError('No tienes permiso para cobrar');
  }

  void _requireCancelOrders() {
    final employee = AppSession.instance.employee;
    if (employee?.canCancelOrders == true ||
        employee?.canViewAdmin == true ||
        employee?.canControlLiveOperations == true) {
      return;
    }
    throw StateError('No tienes permiso para cancelar tickets.');
  }

  void _requireCancelPayments() {
    final employee = AppSession.instance.employee;
    if (employee?.canCancelPayments == true ||
        employee?.canViewAdmin == true ||
        employee?.canControlLiveOperations == true) {
      return;
    }
    throw StateError('No tienes permiso para cancelar pagos.');
  }

  void _requireCancelItems() {
    final employee = AppSession.instance.employee;
    if (employee?.canCancelItems == true ||
        employee?.canCancelOrders == true ||
        employee?.canViewAdmin == true ||
        employee?.canControlLiveOperations == true) {
      return;
    }
    throw StateError('No tienes permiso para cancelar articulos.');
  }

  void _requireKitchenCancellationApprover() {
    final employee = AppSession.instance.employee;
    if (employee?.canApproveKitchenCancellations == true ||
        employee?.canViewKitchen == true ||
        employee?.canViewAdmin == true ||
        employee?.canControlLiveOperations == true) {
      return;
    }
    throw StateError('No tienes permiso para resolver cancelaciones.');
  }

  void _ensureItemEditable(OrderItem item) {
    if (item.kitchenStatus == 'ready') {
      throw StateError(
        'Este producto ya fue servido por cocina y no puede modificarse.',
      );
    }
    if (['sent', 'cooking'].contains(item.kitchenStatus)) {
      throw StateError(
        'Este producto ya esta en cocina y no puede modificarse libremente.',
      );
    }
    if (item.paymentStatus == 'paid') {
      throw StateError('Este producto ya fue pagado y no puede modificarse.');
    }
  }

  Future<void> _ensureCancellationKeepsPaymentsValid(
    String orderId,
    OrderItem cancellingItem,
  ) async {
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = orderDoc.exists ? PosOrder.fromDoc(orderDoc) : null;
    if (order == null) {
      return;
    }
    final newTotal = (order.total - cancellingItem.total).clamp(
      0,
      double.infinity,
    );
    final payments = await getOrderPaymentsOnce(orderId);
    final paidTotal = payments
        .where((payment) => payment.isActive)
        .fold<double>(0, (total, payment) => total + payment.baseAmount);
    if (newTotal + 0.01 < paidTotal) {
      throw StateError(
        'No se puede cancelar porque la orden ya tiene pagos que superan el nuevo total.',
      );
    }
  }

  void _requireCashManager() {
    if (AppSession.instance.employee?.canManageCash == true) {
      return;
    }
    throw StateError('No tienes permiso para cerrar caja.');
  }

  void _requireCashWithdrawalRequester() {
    final employee = AppSession.instance.employee;
    if (employee?.canCharge == true || employee?.canManageCash == true) {
      return;
    }
    throw StateError('No tienes permiso para solicitar retiros.');
  }

  void _requireCashWithdrawalAuthorizer() {
    if (AppSession.instance.employee?.canAuthorizeCashWithdrawals == true) {
      return;
    }
    throw StateError('No tienes permiso para autorizar retiros.');
  }

  void _requireOpenKitchen() {
    final employee = AppSession.instance.employee;
    if (employee?.canOpenKitchen == true ||
        employee?.canManageKitchenStock == true ||
        employee?.canViewAdmin == true) {
      return;
    }
    throw StateError('No tienes permiso para abrir cocina.');
  }

  void _requireCloseKitchen() {
    final employee = AppSession.instance.employee;
    if (employee?.canCloseKitchen == true || employee?.canViewAdmin == true) {
      return;
    }
    throw StateError('No tienes permiso para cerrar cocina.');
  }

  void _requireCashOpenPermission() {
    final employee = AppSession.instance.employee;
    if (employee?.canManageCash == true || employee?.canCharge == true) {
      return;
    }
    throw StateError('No tienes permiso para abrir caja.');
  }

  Future<CashSession> _requireOpenCashSessionForPayment() async {
    final session = await getOpenCashSession();
    if (session == null) {
      throw StateError('Debes abrir caja antes de cobrar.');
    }
    return session;
  }

  void _logActivityInBatch(
    WriteBatch batch, {
    required String type,
    String? orderId,
    Map<String, Object?> data = const {},
  }) {
    final employee = AppSession.instance.employee;
    final logData = <String, Object?>{
      'type': type,
      ..._currentBranchFields,
      ...data,
      'employeeId': employee?.id ?? '',
      'employeeName': employee?.name ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid ?? 'anonymous',
    };
    if (orderId != null) {
      logData['orderId'] = orderId;
    }
    batch.set(_restaurantRef.collection('activityLog').doc(), logData);
  }

  void _requireAnyPermission({
    required bool takeOrders,
    required bool charge,
    required String message,
  }) {
    final employee = AppSession.instance.employee;
    final allowed =
        (takeOrders && employee?.canTakeOrders == true) ||
        (charge && employee?.canCharge == true);
    if (!allowed) {
      throw StateError(message);
    }
  }

  Future<void> _ensureKitchenReadyForPayment(String orderId) async {
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final hasKitchenPending = itemsSnapshot.docs
        .map(OrderItem.fromDoc)
        .any(
          (item) =>
              item.sendToKitchen &&
              ['pending', 'sent', 'cooking'].contains(item.kitchenStatus),
        );

    if (hasKitchenPending) {
      throw StateError(
        'No puedes cobrar hasta que cocina marque todo como listo.',
      );
    }
  }

  Future<void> _ensureNoPaymentType(
    String orderId, {
    required String blockedType,
  }) async {
    final paymentsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('payments')
        .get();
    final hasBlockedType = paymentsSnapshot.docs
        .map(Payment.fromDoc)
        .any((payment) => payment.isActive && payment.type == blockedType);

    if (hasBlockedType) {
      final message = blockedType == 'partial'
          ? 'Esta cuenta ya tiene pagos parciales. Termina el cobro por parcialidades.'
          : 'Esta cuenta ya inicio cobro por persona. Termina el cobro por persona.';
      throw StateError(message);
    }
  }

  Future<void> _ensureEmployeeConsumptionAllowed(
    String orderId,
    String method,
  ) async {
    if (method != 'employee_consumption') {
      return;
    }

    final paymentsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('payments')
        .get();
    final hasClientPayment = paymentsSnapshot.docs
        .map(Payment.fromDoc)
        .any(
          (payment) =>
              payment.isActive && ['cash', 'card'].contains(payment.method),
        );

    if (hasClientPayment) {
      throw StateError(
        'Consumo empleado no disponible porque ya existe un pago de cliente.',
      );
    }
  }

  Future<void> recalculateOrderTotal(String orderId) async {
    final itemsSnapshot = await _ordersRef
        .doc(orderId)
        .collection('items')
        .get();
    final items = itemsSnapshot.docs.map(OrderItem.fromDoc).toList();
    final total = items
        .where((item) => !item.isCancelled)
        .fold<double>(0, (runningTotal, item) => runningTotal + item.total);
    final orderDoc = await _ordersRef.doc(orderId).get();
    final order = orderDoc.exists ? PosOrder.fromDoc(orderDoc) : null;
    final payments = await getOrderPaymentsOnce(orderId);
    final paidTotal = payments
        .where((payment) => payment.isActive)
        .fold<double>(0, (total, payment) => total + payment.baseAmount);
    final adjustedPending = (total - paidTotal).clamp(0, double.infinity);

    await _ordersRef.doc(orderId).update({
      'total': total,
      'paidTotal': paidTotal,
      'pendingTotal': adjustedPending,
      'paymentStatus': paidTotal <= 0
          ? 'pending'
          : adjustedPending <= 0.01
          ? 'paid'
          : 'partial',
      if (order?.status == 'paid' && adjustedPending > 0.01) 'status': 'ready',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveProduct({
    String? productId,
    required String name,
    required String categoryId,
    required String categoryName,
    required String category,
    required double price,
    required Map<String, double> platformPrices,
    required bool active,
    required bool sendToKitchen,
    required bool affectsKitchenStock,
    required List<ProductRecipeItem> recipeItems,
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageProducts == true,
      'No tienes permiso para administrar productos.',
    );
    final docRef = productId == null
        ? _productsRef.doc()
        : _productsRef.doc(productId);
    final current = await _productsRef.get();
    final cleanCategoryName = categoryName.trim().isNotEmpty
        ? categoryName.trim()
        : category.trim();
    final cleanCategoryId = categoryId.trim().isNotEmpty
        ? categoryId.trim()
        : categoryIdForName(cleanCategoryName);
    final cleanRecipeItems = affectsKitchenStock
        ? recipeItems.where((item) => item.isValid).take(1).toList()
        : <ProductRecipeItem>[];
    if (affectsKitchenStock && cleanRecipeItems.isEmpty) {
      throw ArgumentError('Selecciona un insumo principal para rendimiento.');
    }
    final recipeIds = <String>{};
    for (final item in cleanRecipeItems) {
      if (item.consumptionFactor <= 0) {
        throw ArgumentError('El factor de equivalencia debe ser mayor a cero.');
      }
      if (!recipeIds.add(item.kitchenStockItemId)) {
        throw ArgumentError('No repitas insumos de rendimiento.');
      }
    }
    final primary = cleanRecipeItems.isEmpty ? null : cleanRecipeItems.first;

    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'categoryId': cleanCategoryId,
      'categoryName': cleanCategoryName,
      'category': cleanCategoryName,
      'price': price,
      'platformPrices': platformPrices,
      'active': active,
      'sendToKitchen': sendToKitchen,
      'affectsKitchenStock': affectsKitchenStock,
      'recipeItems': ProductRecipeItem.toMapList(cleanRecipeItems),
      'kitchenStockItemId': primary?.kitchenStockItemId,
      'kitchenStockItemName': primary?.kitchenStockItemName,
      'kitchenStockUnit': primary?.kitchenStockUnit,
      'stockConsumptionQty': primary?.consumptionFactor,
      'kitchenConsumptionFactor': primary?.consumptionFactor,
      'sortOrder': current.docs.length + 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveTable({
    String? tableId,
    required String name,
    required String type,
    required bool active,
    required int sortOrder,
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageTables == true,
      'No tienes permiso para administrar mesas.',
    );
    final docRef = tableId == null ? _tablesRef.doc() : _tablesRef.doc(tableId);

    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'type': type,
      ..._currentBranchFields,
      'active': active,
      'sortOrder': sortOrder,
      if (tableId == null) 'status': 'available',
      if (tableId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleTable(PosTable table) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageTables == true,
      'No tienes permiso para administrar mesas.',
    );
    await _tablesRef.doc(table.id).update({
      'active': !table.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveOrderPlatform({
    String? platformId,
    required String name,
    required bool active,
    required int sortOrder,
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManagePlatforms == true,
      'No tienes permiso para administrar plataformas.',
    );
    final docRef = platformId == null
        ? _platformsRef.doc()
        : _platformsRef.doc(platformId);

    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'active': active,
      'sortOrder': sortOrder,
      if (platformId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleOrderPlatform(OrderPlatform platform) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManagePlatforms == true,
      'No tienes permiso para administrar plataformas.',
    );
    await _platformsRef.doc(platform.id).update({
      'active': !platform.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> toggleProduct(Product product) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageProducts == true,
      'No tienes permiso para administrar productos.',
    );
    await _productsRef.doc(product.id).update({
      'active': !product.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveEmployee({
    String? employeeId,
    required String name,
    required bool active,
    required String pin,
    required bool canTakeOrders,
    required bool canCharge,
    required bool canViewKitchen,
    required bool canViewAdmin,
    required bool canManageProducts,
    required bool canManageTables,
    required bool canManagePlatforms,
    required bool canManageEmployees,
    required bool canManageCash,
    required bool canAuthorizeCashWithdrawals,
    required bool canOpenKitchen,
    required bool canCloseKitchen,
    required bool canViewKitchenReports,
    required bool canManageKitchenStock,
    required bool canCancelOrders,
    required bool canCancelPayments,
    required bool canCancelItems,
    required bool canApproveKitchenCancellations,
    required bool canViewLiveOperations,
    required bool canControlLiveOperations,
    List<EmployeeBranchAccess>? branchAccess,
    String? defaultBranchId,
  }) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageEmployees == true ||
          _canManageBranches(),
      'No tienes permiso para administrar empleados.',
    );
    final docRef = employeeId == null
        ? _employeesRef.doc()
        : _employeesRef.doc(employeeId);
    final permissions = {
      'canTakeOrders': canTakeOrders,
      'canCharge': canCharge,
      'canViewKitchen': canViewKitchen,
      'canViewAdmin': canViewAdmin,
      'canManageProducts': canManageProducts,
      'canManageTables': canManageTables,
      'canManagePlatforms': canManagePlatforms,
      'canManageEmployees': canManageEmployees,
      'canManageCash': canManageCash,
      'canAuthorizeCashWithdrawals': canAuthorizeCashWithdrawals,
      'canOpenKitchen': canOpenKitchen,
      'canCloseKitchen': canCloseKitchen,
      'canViewKitchenReports': canViewKitchenReports,
      'canManageKitchenStock': canManageKitchenStock,
      'canCancelOrders': canCancelOrders,
      'canCancelPayments': canCancelPayments,
      'canCancelItems': canCancelItems,
      'canApproveKitchenCancellations': canApproveKitchenCancellations,
      'canViewLiveOperations': canViewLiveOperations,
      'canControlLiveOperations': canControlLiveOperations,
    };
    final access = branchAccess == null || branchAccess.isEmpty
        ? [
            EmployeeBranchAccess(
              restaurantId: AppConstants.restaurantId,
              branchId: AppConstants.defaultBranchId,
              branchName: AppConstants.defaultBranchName,
              active: true,
              permissions: permissions,
            ),
          ]
        : branchAccess;

    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      // TODO: Replace plain PIN storage with a salted hash before production.
      'pin': pin.trim(),
      'active': active,
      'canTakeOrders': canTakeOrders,
      'canCharge': canCharge,
      'canViewKitchen': canViewKitchen,
      'canViewAdmin': canViewAdmin,
      'canManageProducts': canManageProducts,
      'canManageTables': canManageTables,
      'canManagePlatforms': canManagePlatforms,
      'canManageEmployees': canManageEmployees,
      'canManageCash': canManageCash,
      'canAuthorizeCashWithdrawals': canAuthorizeCashWithdrawals,
      'canOpenKitchen': canOpenKitchen,
      'canCloseKitchen': canCloseKitchen,
      'canViewKitchenReports': canViewKitchenReports,
      'canManageKitchenStock': canManageKitchenStock,
      'canCancelOrders': canCancelOrders,
      'canCancelPayments': canCancelPayments,
      'canCancelItems': canCancelItems,
      'canApproveKitchenCancellations': canApproveKitchenCancellations,
      'canViewLiveOperations': canViewLiveOperations,
      'canControlLiveOperations': canControlLiveOperations,
      'isSuperAdmin': canViewAdmin,
      'defaultRestaurantId': AppConstants.restaurantId,
      'defaultBranchId': defaultBranchId ?? access.first.branchId,
      'restaurantAccess': [AppConstants.restaurantId],
      'branchAccess': access.map((item) => item.toMap()).toList(),
      if (employeeId == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleEmployee(Employee employee) async {
    _requireAdminPermission(
      AppSession.instance.employee?.canManageEmployees == true ||
          _canManageBranches(),
      'No tienes permiso para administrar empleados.',
    );
    await _employeesRef.doc(employee.id).update({
      'active': !employee.active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  void _requireAdminPermission(bool allowed, String message) {
    if (allowed) {
      return;
    }
    throw StateError(message);
  }

  bool _canManageBranches() {
    return AppSession.instance.employee?.hasAdminAccess == true;
  }
}

class _DefaultProductCategory {
  const _DefaultProductCategory(this.name, this.sortOrder, this.colorHex);

  final String name;
  final int sortOrder;
  final String colorHex;
}

String _readText(Object? value, String fallback) {
  if (value is String && value.trim().isNotEmpty) {
    return _cleanCategoryDisplayName(value);
  }
  return fallback;
}

String _cleanCategoryDisplayName(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

bool _sessionIsNewer(ActiveSession a, ActiveSession b) {
  final aSeen = a.lastSeenAt ?? a.updatedAt ?? DateTime(1970);
  final bSeen = b.lastSeenAt ?? b.updatedAt ?? DateTime(1970);
  return aSeen.isAfter(bSeen);
}

String _activeSessionGroupKey(ActiveSession session) {
  final employeeId = session.employeeId.trim();
  if (employeeId.isNotEmpty) return employeeId;
  final deviceId = session.deviceId.trim();
  if (deviceId.isNotEmpty) return deviceId;
  return session.id;
}

String normalizeStatus(Object? value) {
  return value
      .toString()
      .toLowerCase()
      .trim()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll('Ã¡', 'a')
      .replaceAll('Ã©', 'e')
      .replaceAll('Ã­', 'i')
      .replaceAll('Ã³', 'o')
      .replaceAll('Ãº', 'u')
      .replaceAll('Ã±', 'n');
}

bool isActiveOrderForLiveTables(PosOrder order) {
  final status = normalizeStatus(order.status);
  final kitchenStatus = normalizeStatus(order.kitchenStatus);
  final paymentStatus = normalizeStatus(order.paymentStatus);
  const inactiveStatuses = {
    'cancelled',
    'canceled',
    'cancelada',
    'cancelado',
    'paid',
    'pagada',
    'pagado',
    'closed',
    'cerrada',
    'cerrado',
    'voided',
  };
  const inactivePaymentStatuses = {
    'paid',
    'pagado',
    'cancelled',
    'canceled',
    'cancelado',
    'cancelada',
  };
  if (inactiveStatuses.contains(status) ||
      inactiveStatuses.contains(kitchenStatus) ||
      inactivePaymentStatuses.contains(paymentStatus)) {
    return false;
  }
  if (order.cancelledAt != null ||
      order.canceledAt != null ||
      order.closedAt != null) {
    return false;
  }
  if (order.paidAt != null && order.pendingTotal <= 0.01) {
    return false;
  }
  return true;
}

bool isActiveOrder(PosOrder order) => isActiveOrderForLiveTables(order);

bool _isPaidStatus(String status) {
  final normalized = normalizeStatus(status);
  return normalized == 'paid' ||
      normalized == 'pagado' ||
      normalized == 'pagada';
}

bool isActivePayment(Payment payment) {
  final status = normalizeStatus(payment.status);
  const inactiveStatuses = {
    'cancelled',
    'canceled',
    'cancelado',
    'cancelada',
    'voided',
    'anulado',
    'anulada',
  };
  return !inactiveStatuses.contains(status) && payment.cancelledAt == null;
}

bool isActiveOrderItem(OrderItem item) {
  final status = normalizeStatus(item.status);
  final kitchenStatus = normalizeStatus(item.kitchenStatus);
  final paymentStatus = normalizeStatus(item.paymentStatus);
  final cancelStatus = normalizeStatus(item.cancelStatus);
  const inactiveStatuses = {
    'cancelled',
    'canceled',
    'cancelado',
    'cancelada',
    'voided',
    'anulado',
    'anulada',
  };
  return !inactiveStatuses.contains(status) &&
      !inactiveStatuses.contains(kitchenStatus) &&
      !inactiveStatuses.contains(paymentStatus) &&
      !inactiveStatuses.contains(cancelStatus) &&
      cancelStatus != 'accepted' &&
      item.cancelledAt == null;
}

PosOrder? getActiveOrderForTable(String tableId, List<PosOrder> orders) {
  final cleanTableId = tableId.trim();
  final activeOrders =
      orders
          .where((order) => order.tableId.trim() == cleanTableId)
          .where(isActiveOrderForLiveTables)
          .toList()
        ..sort((a, b) {
          final aDate =
              a.updatedAt ??
              a.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bDate =
              b.updatedAt ??
              b.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
  return activeOrders.isEmpty ? null : activeOrders.first;
}

String? _cleanColorHex(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final clean = raw.startsWith('#') ? raw.substring(1) : raw;
  if (clean.length != 6 && clean.length != 8) return null;
  final parsed = int.tryParse(clean, radix: 16);
  if (parsed == null) return null;
  return '#${clean.toUpperCase()}';
}

const _defaultKitchenStockItems = [
  {
    'id': 'bistec',
    'name': 'Bistec',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 1,
  },
  {
    'id': 'adobada',
    'name': 'Adobada',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 2,
  },
  {
    'id': 'carnaza',
    'name': 'Carnaza',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 3,
  },
  {
    'id': 'arrachera',
    'name': 'Arrachera',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 4,
  },
  {
    'id': 'chorizo',
    'name': 'Chorizo',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 5,
  },
  {
    'id': 'higado',
    'name': 'Higado',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 6,
  },
  {
    'id': 'labio',
    'name': 'Labio',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 7,
  },
  {
    'id': 'tripa',
    'name': 'Tripa',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 8,
  },
  {
    'id': 'lengua',
    'name': 'Lengua',
    'category': 'meat',
    'unit': 'kg',
    'sortOrder': 9,
  },
  {
    'id': 'tortilla_maiz',
    'name': 'Tortilla de maiz',
    'category': 'tortilla',
    'unit': 'kg',
    'sortOrder': 10,
  },
  {
    'id': 'tortilla_harina',
    'name': 'Tortilla de harina',
    'category': 'tortilla',
    'unit': 'kg',
    'sortOrder': 11,
  },
  {
    'id': 'queso',
    'name': 'Queso',
    'category': 'dairy',
    'unit': 'kg',
    'sortOrder': 12,
  },
  {
    'id': 'refresco_coca_cola',
    'name': 'Refresco Coca Cola',
    'category': 'drink',
    'unit': 'piece',
    'sortOrder': 13,
  },
  {
    'id': 'refrescos_surtidos',
    'name': 'Refrescos surtidos',
    'category': 'drink',
    'unit': 'piece',
    'sortOrder': 14,
  },
  {
    'id': 'agua_fresca',
    'name': 'Agua fresca',
    'category': 'water',
    'unit': 'liter',
    'sortOrder': 15,
  },
];
