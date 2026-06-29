import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/brand_colors.dart';

class BrandLogoMark extends StatelessWidget {
  const BrandLogoMark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 48.0 : 96.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: BrandColors.backgroundPrimary,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: BrandColors.glassBorder),
            boxShadow: const [
              BoxShadow(
                color: BrandColors.accentGlow,
                blurRadius: 30,
                offset: Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.all(compact ? 4 : 6),
            child: Image.asset(
              AppConstants.logoAsset,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.local_fire_department,
                size: compact ? 30 : 54,
                color: BrandColors.accentYellow,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppConstants.brandName.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: BrandColors.textPrimary,
                  fontSize: compact ? 18 : 32,
                  fontWeight: FontWeight.w800,
                  height: 0.95,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${AppConstants.appName} by ${AppConstants.creator}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: BrandColors.accentOrange,
                  fontSize: compact ? 12 : 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
