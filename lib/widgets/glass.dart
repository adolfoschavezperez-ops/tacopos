import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';

class PremiumBackground extends StatelessWidget {
  const PremiumBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.65, -0.75),
          radius: 1.15,
          colors: [
            Color(0x33241610),
            BrandColors.backgroundPrimary,
            BrandColors.backgroundSecondary,
          ],
          stops: [0, 0.56, 1],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            top: -130,
            right: -120,
            child: _AmbientGlow(color: BrandColors.accentGlow, size: 300),
          ),
          const Positioned(
            bottom: -140,
            left: -120,
            child: _AmbientGlow(color: Color(0x1AF59A23), size: 300),
          ),
          child,
        ],
      ),
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 22,
    this.blur = 16,
    this.fill,
    this.borderColor,
    this.glowColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double blur;
  final Color? fill;
  final Color? borderColor;
  final Color? glowColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: fill ?? BrandColors.glassFill,
                borderRadius: radius,
                border: Border.all(
                  color: borderColor ?? BrandColors.glassBorder,
                ),
                boxShadow: [
                  BoxShadow(
                    color: glowColor ?? Colors.black.withValues(alpha: 0.18),
                    blurRadius: glowColor == null ? 20 : 34,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.accent,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? accent;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final accentColor = accent ?? BrandColors.glassBorder;

    return GlassPanel(
      padding: padding,
      onTap: onTap,
      fill: selected
          ? BrandColors.accentGlow.withValues(alpha: 0.16)
          : BrandColors.glassFill,
      borderColor: selected
          ? BrandColors.accentYellow
          : BrandColors.glassBorder,
      glowColor: selected ? BrandColors.accentGlow : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: accentColor.withValues(alpha: selected ? 0.95 : 0.45),
              width: 2,
            ),
          ),
        ),
        child: Padding(padding: const EdgeInsets.only(left: 12), child: child),
      ),
    );
  }
}

class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.prominent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      fill: prominent ? BrandColors.accentYellow : BrandColors.glassFill,
      borderColor: prominent
          ? BrandColors.accentYellow
          : BrandColors.glassBorder,
      blur: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 20,
            color: prominent
                ? BrandColors.backgroundPrimary
                : BrandColors.textPrimary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: prominent
                    ? BrandColors.backgroundPrimary
                    : BrandColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 650 || size.height < 750;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: compact
                    ? Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      )
                    : Theme.of(context).textTheme.headlineMedium,
              ),
              if (subtitle != null) ...[
                SizedBox(height: compact ? 2 : 4),
                Text(
                  subtitle!,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: BrandColors.textMuted,
                    fontSize: compact ? 12 : 14,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 120, spreadRadius: 40),
          ],
        ),
      ),
    );
  }
}
