import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';

class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key, this.message = 'Cargando...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: BrandColors.yellow),
          const SizedBox(height: 14),
          Text(message, style: const TextStyle(color: BrandColors.muted)),
        ],
      ),
    );
  }
}
