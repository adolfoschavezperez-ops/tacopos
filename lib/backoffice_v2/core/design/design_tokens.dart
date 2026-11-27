import 'package:flutter/material.dart';

/// Centralized design tokens for TacoPOS Backoffice 2.0.
///
/// Unified with the approved Login aesthetic:
/// - Deep graphite sidebar (#111318) across both light and dark modes
/// - Strategic TacoPOS orange (#F97316) and amber (#F59E0B) brand accents
/// - Multi-level surface depth, crisp 1px borders, and semantic financial states
@immutable
class BackofficeTokens extends ThemeExtension<BackofficeTokens> {
  const BackofficeTokens({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceSubtle,
    required this.surfaceHover,
    required this.sidebarBg,
    required this.sidebarSurface,
    required this.sidebarBorder,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.brandAccent,
    required this.brandAmber,
    required this.brandAccentSoft,
    required this.brandOnAccent,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.skeletonBase,
    required this.skeletonHighlight,
  });

  final Brightness brightness;
  final Color canvas;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceSubtle;
  final Color surfaceHover;
  final Color sidebarBg;
  final Color sidebarSurface;
  final Color sidebarBorder;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color brandAccent;
  final Color brandAmber;
  final Color brandAccentSoft;
  final Color brandOnAccent;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;
  final Color skeletonBase;
  final Color skeletonHighlight;

  bool get isDark => brightness == Brightness.dark;

  static const light = BackofficeTokens(
    brightness: Brightness.light,
    canvas: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFF1F3F6),
    surfaceHover: Color(0xFFF8FAFC),
    sidebarBg: Color(0xFF111318),
    sidebarSurface: Color(0xFF1B1E25),
    sidebarBorder: Color(0x14FFFFFF),
    border: Color(0xFFE4E4E7),
    borderStrong: Color(0xFFD4D4D8),
    textPrimary: Color(0xFF111318),
    textSecondary: Color(0xFF3F3F46),
    textMuted: Color(0xFF71717A),
    brandAccent: Color(0xFFF97316),
    brandAmber: Color(0xFFF59E0B),
    brandAccentSoft: Color(0x1AF97316),
    brandOnAccent: Color(0xFFFFFFFF),
    success: Color(0xFF059669),
    successSoft: Color(0x14059669),
    warning: Color(0xFFD97706),
    warningSoft: Color(0x14D97706),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0x14DC2626),
    info: Color(0xFF2563EB),
    infoSoft: Color(0x142563EB),
    skeletonBase: Color(0xFFE4E4E7),
    skeletonHighlight: Color(0xFFF4F4F5),
  );

  static const dark = BackofficeTokens(
    brightness: Brightness.dark,
    canvas: Color(0xFF0B0D12),
    surface: Color(0xFF14171F),
    surfaceElevated: Color(0xFF1B1F2A),
    surfaceSubtle: Color(0xFF181B24),
    surfaceHover: Color(0xFF202430),
    sidebarBg: Color(0xFF0F1117),
    sidebarSurface: Color(0xFF191D26),
    sidebarBorder: Color(0x14FFFFFF),
    border: Color(0x14FFFFFF),
    borderStrong: Color(0x24FFFFFF),
    textPrimary: Color(0xFFFAFAF9),
    textSecondary: Color(0xFFD4D4D8),
    textMuted: Color(0xFF8E929C),
    brandAccent: Color(0xFFF97316),
    brandAmber: Color(0xFFF59E0B),
    brandAccentSoft: Color(0x21F97316),
    brandOnAccent: Color(0xFFFFFFFF),
    success: Color(0xFF34D399),
    successSoft: Color(0x1A34D399),
    warning: Color(0xFFFBBF24),
    warningSoft: Color(0x1AFBBF24),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0x1AF87171),
    info: Color(0xFF60A5FA),
    infoSoft: Color(0x1A60A5FA),
    skeletonBase: Color(0xFF1B1F2A),
    skeletonHighlight: Color(0xFF242937),
  );

  static BackofficeTokens of(BuildContext context) {
    return Theme.of(context).extension<BackofficeTokens>() ?? light;
  }

  @override
  BackofficeTokens copyWith({
    Brightness? brightness,
    Color? canvas,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceSubtle,
    Color? surfaceHover,
    Color? sidebarBg,
    Color? sidebarSurface,
    Color? sidebarBorder,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? brandAccent,
    Color? brandAmber,
    Color? brandAccentSoft,
    Color? brandOnAccent,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? info,
    Color? infoSoft,
    Color? skeletonBase,
    Color? skeletonHighlight,
  }) {
    return BackofficeTokens(
      brightness: brightness ?? this.brightness,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      sidebarBg: sidebarBg ?? this.sidebarBg,
      sidebarSurface: sidebarSurface ?? this.sidebarSurface,
      sidebarBorder: sidebarBorder ?? this.sidebarBorder,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      brandAccent: brandAccent ?? this.brandAccent,
      brandAmber: brandAmber ?? this.brandAmber,
      brandAccentSoft: brandAccentSoft ?? this.brandAccentSoft,
      brandOnAccent: brandOnAccent ?? this.brandOnAccent,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
    );
  }

  @override
  BackofficeTokens lerp(covariant ThemeExtension<BackofficeTokens>? other, double t) {
    if (other is! BackofficeTokens) return this;
    return BackofficeTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      sidebarBg: Color.lerp(sidebarBg, other.sidebarBg, t)!,
      sidebarSurface: Color.lerp(sidebarSurface, other.sidebarSurface, t)!,
      sidebarBorder: Color.lerp(sidebarBorder, other.sidebarBorder, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      brandAccent: Color.lerp(brandAccent, other.brandAccent, t)!,
      brandAmber: Color.lerp(brandAmber, other.brandAmber, t)!,
      brandAccentSoft: Color.lerp(brandAccentSoft, other.brandAccentSoft, t)!,
      brandOnAccent: Color.lerp(brandOnAccent, other.brandOnAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
      skeletonBase: Color.lerp(skeletonBase, other.skeletonBase, t)!,
      skeletonHighlight: Color.lerp(skeletonHighlight, other.skeletonHighlight, t)!,
    );
  }
}

class BackofficeSpacing {
  const BackofficeSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const double radiusSm = 6;
  static const double radiusMd = 10;
  static const double radiusLg = 14;
  static const double sidebarWidth = 252;
  static const double sidebarCollapsedWidth = 72;
  static const double topBarHeight = 60;
}
