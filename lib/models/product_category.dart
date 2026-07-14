import 'package:cloud_firestore/cloud_firestore.dart';

class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.active,
    required this.sortOrder,
    this.colorKey,
    this.colorHex,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String normalizedName;
  final bool active;
  final int sortOrder;
  final String? colorKey;
  final String? colorHex;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ProductCategory.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final name = _readString(data['name'], doc.id);
    return ProductCategory(
      id: doc.id,
      name: name,
      normalizedName: _readString(data['normalizedName'], _normalize(name)),
      active: _readBool(data['active'], fallback: true),
      sortOrder: _readInt(data['sortOrder'], fallback: 99),
      colorKey: data['colorKey'] as String?,
      colorHex: data['colorHex'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  static String _readString(Object? value, String fallback) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  static int _readInt(Object? value, {required int fallback}) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static bool _readBool(Object? value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      if (['true', '1', 'yes', 'si'].contains(normalized)) return true;
      if (['false', '0', 'no'].contains(normalized)) return false;
    }
    return fallback;
  }

  static String _normalize(String value) {
    final normalized = value
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
    return normalized.replaceAll(RegExp(r'\s+'), ' ');
  }
}
