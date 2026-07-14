import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';

class Branch {
  const Branch({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.active,
    required this.sortOrder,
    this.restaurantId = AppConstants.restaurantId,
    this.restaurantName = AppConstants.restaurantName,
    this.address,
    this.phone,
    this.timezone = AppConstants.defaultTimezone,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String name;
  final String normalizedName;
  final bool active;
  final int sortOrder;
  final String? address;
  final String? phone;
  final String timezone;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const defaultBranch = Branch(
    id: 'aviacion',
    name: 'Aviacion',
    normalizedName: 'aviacion',
    active: true,
    sortOrder: 1,
  );

  factory Branch.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    String restaurantId = AppConstants.restaurantId,
    String restaurantName = AppConstants.restaurantName,
  }) {
    final data = doc.data() ?? {};
    final name = data['name'] as String? ?? doc.id;
    return Branch(
      id: data['id'] as String? ?? doc.id,
      restaurantId: data['restaurantId'] as String? ?? restaurantId,
      restaurantName: data['restaurantName'] as String? ?? restaurantName,
      name: name,
      normalizedName:
          data['normalizedName'] as String? ?? normalizeBranchName(name),
      active: data['active'] as bool? ?? true,
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
      address: data['address'] as String?,
      phone: data['phone'] as String?,
      timezone: data['timezone'] as String? ?? AppConstants.defaultTimezone,
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }

  static DateTime? _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}

String normalizeBranchName(String value) {
  final lower = value.trim().toLowerCase();
  const replacements = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  var normalized = lower;
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  normalized = normalized.replaceAll(RegExp(r'_+'), '_');
  normalized = normalized.replaceAll(RegExp(r'^_|_$'), '');
  return normalized.isEmpty ? 'sucursal' : normalized;
}
