import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/brand_colors.dart';

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
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const Text(
              AppConstants.brandName,
              style: TextStyle(
                color: BrandColors.orange,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: actions,
      ),
      body: Stack(
        children: [
          const _BrushAccent(top: 18, right: -60),
          const _BrushAccent(bottom: 24, left: -90, compact: true),
          SafeArea(child: body),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class _BrushAccent extends StatelessWidget {
  const _BrushAccent({
    this.top,
    this.right,
    this.bottom,
    this.left,
    this.compact = false,
  });

  final double? top;
  final double? right;
  final double? bottom;
  final double? left;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: -0.18,
          child: Container(
            width: compact ? 180 : 260,
            height: compact ? 28 : 42,
            decoration: BoxDecoration(
              color: BrandColors.orange.withValues(
                alpha: compact ? 0.16 : 0.22,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}
