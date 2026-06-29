import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/brand_colors.dart';

class BrandLogoMark extends StatelessWidget {
  const BrandLogoMark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 52.0 : 88.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: BrandColors.yellow,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66F58A07),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Icon(
            Icons.local_fire_department,
            size: compact ? 34 : 54,
            color: BrandColors.black,
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppConstants.brandName.toUpperCase(),
              style: TextStyle(
                color: BrandColors.white,
                fontSize: compact ? 19 : 34,
                fontWeight: FontWeight.w900,
                height: 0.95,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${AppConstants.appName} by ${AppConstants.creator}',
              style: TextStyle(
                color: BrandColors.orange,
                fontSize: compact ? 12 : 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
