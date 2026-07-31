import 'package:flutter/material.dart';

import '../core/commercial/tenant_runtime_context.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/brand_colors.dart';
import '../services/commercial_config_service.dart';

class CommercialBrandLogo extends StatelessWidget {
  const CommercialBrandLogo({
    super.key,
    required this.size,
    this.fit = BoxFit.contain,
  });

  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CommercialBranding>(
      stream: CommercialConfigService.instance.watchBranding(),
      builder: (context, snapshot) {
        final branding = snapshot.hasError
            ? CommercialBranding.defaults()
            : snapshot.data ?? CommercialBranding.defaults();
        return _BrandImage(branding: branding, size: size, fit: fit);
      },
    );
  }
}

class CommercialBrandName extends StatelessWidget {
  const CommercialBrandName({
    super.key,
    this.uppercase = false,
    this.textAlign,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final bool uppercase;
  final TextAlign? textAlign;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CommercialBranding>(
      stream: CommercialConfigService.instance.watchBranding(),
      builder: (context, snapshot) {
        final branding = snapshot.hasError
            ? CommercialBranding.defaults()
            : snapshot.data ?? CommercialBranding.defaults();
        final name = branding.shortName.trim().isEmpty
            ? AppConstants.brandName
            : branding.shortName;
        return Text(
          uppercase ? name.toUpperCase() : name,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          style: style,
        );
      },
    );
  }
}

class _BrandImage extends StatelessWidget {
  const _BrandImage({
    required this.branding,
    required this.size,
    required this.fit,
  });

  final CommercialBranding branding;
  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final logoUrl = branding.logoUrl.trim();
    if (logoUrl.isNotEmpty) {
      return Image.network(
        logoUrl,
        width: size,
        height: size,
        fit: fit,
        errorBuilder: (_, _, _) => _assetLogo(),
      );
    }
    return _assetLogo();
  }

  Widget _assetLogo() {
    return Image.asset(
      AppConstants.logoAsset,
      width: size,
      height: size,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.local_fire_department,
        size: size * 0.56,
        color: BrandColors.accentYellow,
      ),
    );
  }
}
