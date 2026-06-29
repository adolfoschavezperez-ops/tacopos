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
        color: BrandColors.yellow,
        background: Color(0x33FFD400),
      );
    case 'sent':
      return const StatusStyle(
        label: 'En cocina',
        color: BrandColors.orange,
        background: Color(0x33F58A07),
      );
    case 'ready':
      return const StatusStyle(
        label: 'Lista',
        color: BrandColors.success,
        background: Color(0x3329C56B),
      );
    case 'paid':
      return const StatusStyle(
        label: 'Pagada',
        color: BrandColors.info,
        background: Color(0x3342A5F5),
      );
    default:
      return const StatusStyle(
        label: 'Disponible',
        color: BrandColors.muted,
        background: Color(0x22BDBDBD),
      );
  }
}

StatusStyle kitchenStatusStyle(String status) {
  switch (status) {
    case 'sent':
      return const StatusStyle(
        label: 'Nueva',
        color: BrandColors.yellow,
        background: Color(0x33FFD400),
      );
    case 'preparing':
      return const StatusStyle(
        label: 'En preparacion',
        color: BrandColors.orange,
        background: Color(0x33F58A07),
      );
    case 'ready':
      return const StatusStyle(
        label: 'Lista',
        color: BrandColors.success,
        background: Color(0x3329C56B),
      );
    default:
      return const StatusStyle(
        label: 'Pendiente',
        color: BrandColors.muted,
        background: Color(0x22BDBDBD),
      );
  }
}
