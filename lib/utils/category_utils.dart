import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';

String normalizeCategory(String value) {
  return value
      .toLowerCase()
      .trim()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('Ã¡', 'a')
      .replaceAll('Ã©', 'e')
      .replaceAll('Ã­', 'i')
      .replaceAll('Ã³', 'o')
      .replaceAll('Ãº', 'u');
}

Color categoryColor(String category) {
  final normalized = normalizeCategory(category);
  const fixedColors = <String, Color>{
    'todos': BrandColors.accentYellow,
    'tacos': Color(0xFFF59A23),
    'gringas': Color(0xFF7AB8FF),
    'bebidas': Color(0xFF55D98B),
    'quesadillas': Color(0xFFE8C36A),
    'otros': Color(0xFFBFA7FF),
    'otro': Color(0xFFBFA7FF),
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

int categoryRank(String category) {
  return switch (normalizeCategory(category)) {
    'tacos' => 0,
    'gringas' => 1,
    'bebidas' => 2,
    'quesadillas' => 3,
    'otros' || 'otro' => 4,
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
