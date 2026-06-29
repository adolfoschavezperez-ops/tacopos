import 'package:flutter/material.dart';

import 'brand_colors.dart';

class StatusStyle {
  const StatusStyle({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;
}

StatusStyle tableStatusStyle(String status) {
  switch (status) {
    case 'occupied':
      return const StatusStyle(
        label: 'Abierta',
        color: BrandColors.accentYellow,
        background: Color(0x1FFFD54A),
      );
    case 'sent':
      return const StatusStyle(
        label: 'En cocina',
        color: BrandColors.accentOrange,
        background: Color(0x1FF59A23),
      );
    case 'ready':
      return const StatusStyle(
        label: 'Lista',
        color: BrandColors.success,
        background: Color(0x1F55D98B),
      );
    case 'paid':
      return const StatusStyle(
        label: 'Pagada',
        color: BrandColors.info,
        background: Color(0x1F7AB8FF),
      );
    default:
      return const StatusStyle(
        label: 'Disponible',
        color: BrandColors.textMuted,
        background: Color(0x12FFFFFF),
      );
  }
}

StatusStyle kitchenStatusStyle(String status) {
  switch (status) {
    case 'sent':
      return const StatusStyle(
        label: 'Nueva',
        color: BrandColors.accentYellow,
        background: Color(0x1FFFD54A),
      );
    case 'preparing':
    case 'cooking':
      return const StatusStyle(
        label: 'En preparacion',
        color: BrandColors.accentOrange,
        background: Color(0x1FF59A23),
      );
    case 'ready':
      return const StatusStyle(
        label: 'Lista',
        color: BrandColors.success,
        background: Color(0x1F55D98B),
      );
    default:
      return const StatusStyle(
        label: 'Pendiente',
        color: BrandColors.textMuted,
        background: Color(0x12FFFFFF),
      );
  }
}
