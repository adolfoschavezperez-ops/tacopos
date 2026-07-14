import 'package:cloud_firestore/cloud_firestore.dart';

class Restaurant {
  const Restaurant({
    required this.id,
    required this.name,
    required this.active,
    this.legalName,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final bool active;
  final String? legalName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Restaurant.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Restaurant(
      id: doc.id,
      name: data['name'] as String? ?? doc.id,
      legalName: data['legalName'] as String?,
      active: data['active'] as bool? ?? true,
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}
