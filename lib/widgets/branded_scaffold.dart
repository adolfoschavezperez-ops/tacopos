import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/brand_colors.dart';
import 'glass.dart';

class BrandedScaffold extends StatelessWidget {
  const BrandedScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.bottomNavigationBar,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AppBar(
              toolbarHeight: 68,
              titleSpacing: 12,
              backgroundColor: BrandColors.backgroundPrimary.withValues(
                alpha: 0.62,
              ),
              title: Row(
                children: [
                  const _AppBarLogo(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          AppConstants.brandName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: BrandColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: actions,
            ),
          ),
        ),
      ),
      body: PremiumBackground(
        child: SafeArea(
          top: false,
          child: Padding(padding: const EdgeInsets.only(top: 68), child: body),
        ),
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class _AppBarLogo extends StatelessWidget {
  const _AppBarLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: BrandColors.glassFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BrandColors.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Image.asset(
          AppConstants.logoAsset,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.local_fire_department,
            color: BrandColors.accentYellow,
          ),
        ),
      ),
    );
  }
}
