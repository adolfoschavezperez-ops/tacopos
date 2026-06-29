import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';

class DemoSeedService {
  DemoSeedService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<void> createDemoData() async {
    final batch = _db.batch();
    final restaurantRef = _db
        .collection('restaurants')
        .doc(AppConstants.restaurantId);

    batch.set(restaurantRef, {
      'name': AppConstants.brandName,
      'brand': AppConstants.appName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    for (final table in _tables) {
      final id = table['id'] as String;
      batch.set(restaurantRef.collection('tables').doc(id), {
        ...table,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    for (final product in _products) {
      final id = product['id'] as String;
      batch.set(restaurantRef.collection('products').doc(id), {
        ...product,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    for (final employee in _employees) {
      final id = employee['id'] as String;
      batch.set(restaurantRef.collection('employees').doc(id), {
        ...employee,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    for (final platform in _orderPlatforms) {
      final id = platform['id'] as String;
      batch.set(
        restaurantRef.collection('orderPlatforms').doc(id),
        {
          ...platform,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }
}

const _tables = [
  {
    'id': 'mesa_1',
    'name': 'Mesa 1',
    'type': 'table',
    'status': 'available',
    'active': true,
    'sortOrder': 1,
  },
  {
    'id': 'mesa_2',
    'name': 'Mesa 2',
    'type': 'table',
    'status': 'available',
    'active': true,
    'sortOrder': 2,
  },
  {
    'id': 'mesa_3',
    'name': 'Mesa 3',
    'type': 'table',
    'status': 'available',
    'active': true,
    'sortOrder': 3,
  },
  {
    'id': 'mesa_4',
    'name': 'Mesa 4',
    'type': 'table',
    'status': 'available',
    'active': false,
    'sortOrder': 4,
  },
  {
    'id': 'para_llevar',
    'name': 'Para llevar',
    'type': 'takeout_entry',
    'status': 'available',
    'active': true,
    'sortOrder': 99,
  },
];

const _employees = [
  {'id': 'ricardo_bernal', 'name': 'Ricardo Bernal', 'active': true},
  {'id': 'gael', 'name': 'Gael', 'active': true},
];

const _orderPlatforms = [
  {'id': 'en_persona', 'name': 'En persona', 'active': true, 'sortOrder': 1},
  {'id': 'didi', 'name': 'DiDi', 'active': true, 'sortOrder': 2},
  {'id': 'uber', 'name': 'Uber', 'active': true, 'sortOrder': 3},
  {'id': 'rappi', 'name': 'Rappi', 'active': true, 'sortOrder': 4},
];

const _products = [
  {
    'id': 'taco_bistec',
    'name': 'Bistec',
    'category': 'Tacos',
    'price': 24.0,
    'active': true,
    'sendToKitchen': true,
    'sortOrder': 1,
  },
  {
    'id': 'taco_adobada',
    'name': 'Adobada',
    'category': 'Tacos',
    'price': 24.0,
    'active': true,
    'sendToKitchen': true,
    'sortOrder': 2,
  },
  {
    'id': 'taco_carnaza',
    'name': 'Carnaza',
    'category': 'Tacos',
    'price': 24.0,
    'active': true,
    'sendToKitchen': true,
    'sortOrder': 3,
  },
  {
    'id': 'taco_arrachera',
    'name': 'Arrachera',
    'category': 'Tacos',
    'price': 32.0,
    'active': true,
    'sendToKitchen': true,
    'sortOrder': 4,
  },
  {
    'id': 'taco_chorizo',
    'name': 'Chorizo',
    'category': 'Tacos',
    'price': 24.0,
    'active': true,
    'sendToKitchen': true,
    'sortOrder': 5,
  },
  {
    'id': 'taco_higado',
    'name': 'Higado',
    'category': 'Tacos',
    'price': 24.0,
    'active': true,
    'sendToKitchen': true,
    'sortOrder': 6,
  },
  {
    'id': 'taco_labio',
    'name': 'Labio',
    'category': 'Tacos',
    'price': 28.0,
    'active': true,
    'sendToKitchen': true,
    'sortOrder': 7,
  },
  {
    'id': 'taco_tripa',
    'name': 'Tripa',
    'category': 'Tacos',
    'price': 28.0,
    'active': true,
    'sendToKitchen': true,
    'sortOrder': 8,
  },
  {
    'id': 'taco_lengua',
    'name': 'Lengua',
    'category': 'Tacos',
    'price': 30.0,
    'active': true,
    'sendToKitchen': true,
    'sortOrder': 9,
  },
  {
    'id': 'gringa_chica',
    'name': 'Gringa chica',
    'category': 'Gringas',
    'price': 58.0,
    'active': true,
    'sendToKitchen': true,
    'sortOrder': 10,
  },
  {
    'id': 'gringa_grande',
    'name': 'Gringa grande',
    'category': 'Gringas',
    'price': 88.0,
    'active': true,
    'sendToKitchen': true,
    'sortOrder': 11,
  },
  {
    'id': 'gringa_especial_chica',
    'name': 'Gringa especial chica',
    'category': 'Gringas',
    'price': 72.0,
    'active': true,
    'sendToKitchen': true,
    'sortOrder': 12,
  },
  {
    'id': 'gringa_especial_grande',
    'name': 'Gringa especial grande',
    'category': 'Gringas',
    'price': 105.0,
    'active': true,
    'sendToKitchen': true,
    'sortOrder': 13,
  },
  {
    'id': 'refresco_coca_cola',
    'name': 'Refresco Coca Cola',
    'category': 'Bebidas',
    'price': 28.0,
    'active': true,
    'sendToKitchen': false,
    'sortOrder': 14,
  },
];
