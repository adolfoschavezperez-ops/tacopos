import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';
import '../models/product_category.dart';

String normalizeCategory(String value) {
  return value
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
      .replaceAll('Ã±', 'n')
      .replaceAll('ÃƒÂ¡', 'a')
      .replaceAll('ÃƒÂ©', 'e')
      .replaceAll('ÃƒÂ­', 'i')
      .replaceAll('ÃƒÂ³', 'o')
      .replaceAll('ÃƒÂº', 'u')
      .replaceAll('ÃƒÂ±', 'n');
}

String categoryIdForName(String value) {
  final normalized = normalizeCategory(value);
  final buffer = StringBuffer();
  var lastWasSeparator = false;
  for (final codeUnit in normalized.codeUnits) {
    final isLetterOrNumber =
        (codeUnit >= 97 && codeUnit <= 122) ||
        (codeUnit >= 48 && codeUnit <= 57);
    if (isLetterOrNumber) {
      buffer.writeCharCode(codeUnit);
      lastWasSeparator = false;
    } else if (!lastWasSeparator && buffer.isNotEmpty) {
      buffer.write('_');
      lastWasSeparator = true;
    }
  }
  final id = buffer.toString().replaceAll(RegExp(r'_+$'), '');
  return id.isEmpty ? 'otros' : id;
}

Color categoryColor(String category) {
  final normalized = normalizeCategory(category);
  const fixedColors = <String, Color>{
    'todos': BrandColors.accentYellow,
    'tacos': Color(0xFFF59A23),
    'gringas': Color(0xFFBFA7FF),
    'bebidas': Color(0xFF72B7D2),
    'quesadillas': Color(0xFF55D98B),
    'extras': Color(0xFFD986A1),
    'otros': Color(0xFF8A8F98),
    'otro': Color(0xFF8A8F98),
  };
  final fixed = fixedColors[normalized];
  if (fixed != null) {
    return fixed;
  }

  const fallbackPalette = <Color>[
    Color(0xFFE28B6D),
    Color(0xFF6FC7B3),
    Color(0xFF8EA7FF),
    Color(0xFFD7A7F9),
    Color(0xFFE7BA63),
    Color(0xFF72B7D2),
    Color(0xFFD986A1),
  ];
  var hash = 0;
  for (final codeUnit in normalized.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return fallbackPalette[hash % fallbackPalette.length];
}

Color categoryAccent({
  String? categoryId,
  String? categoryName,
  String? colorHex,
}) {
  final parsedHex = _colorFromHex(colorHex);
  if (parsedHex != null) {
    return parsedHex;
  }
  final key = (categoryId ?? '').trim().isNotEmpty
      ? categoryId!.trim()
      : categoryName ?? '';
  return categoryColor(key);
}

Color categoryColorFromModel(ProductCategory category) {
  return categoryAccent(
    categoryId: category.id,
    categoryName: category.name,
    colorHex: category.colorHex,
  );
}

int categoryRank(String category) {
  return switch (normalizeCategory(category)) {
    'tacos' => 0,
    'gringas' => 1,
    'bebidas' => 2,
    'quesadillas' => 3,
    'extras' => 4,
    'otros' || 'otro' => 5,
    _ => 100,
  };
}

int compareCategories(String a, String b) {
  final rankCompare = categoryRank(a).compareTo(categoryRank(b));
  if (rankCompare != 0) {
    return rankCompare;
  }
  return normalizeCategory(a).compareTo(normalizeCategory(b));
}

List<String> orderedCategories(Iterable<String> categories) {
  final unique = <String, String>{};
  for (final category in categories) {
    final clean = category.trim();
    if (clean.isEmpty) {
      continue;
    }
    unique.putIfAbsent(normalizeCategory(clean), () => clean);
  }
  return unique.values.toList()..sort(compareCategories);
}

ProductCategory? findCategoryById(
  List<ProductCategory> categories,
  String? id,
) {
  if (id == null || id.trim().isEmpty) return null;
  for (final category in categories) {
    if (category.id == id) return category;
  }
  return null;
}

ProductCategory? findCategoryByName(
  List<ProductCategory> categories,
  String name,
) {
  final normalized = normalizeCategory(name);
  for (final category in categories) {
    if (normalizeCategory(category.name) == normalized ||
        category.normalizedName == normalized) {
      return category;
    }
  }
  return null;
}

Color? _colorFromHex(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final clean = raw.startsWith('#') ? raw.substring(1) : raw;
  if (clean.length != 6 && clean.length != 8) return null;
  final parsed = int.tryParse(clean, radix: 16);
  if (parsed == null) return null;
  return Color(clean.length == 6 ? 0xFF000000 | parsed : parsed);
}
