import 'package:flutter/material.dart';

import 'design_tokens.dart';

class BackofficeTheme {
  const BackofficeTheme._();

  static ThemeData light() => _build(BackofficeTokens.light);
  static ThemeData dark() => _build(BackofficeTokens.dark);

  static ThemeData _build(BackofficeTokens tokens) {
    final isDark = tokens.isDark;
    final colorScheme = ColorScheme(
      brightness: tokens.brightness,
      primary: tokens.brandAccent,
      onPrimary: tokens.brandOnAccent,
      secondary: tokens.textPrimary,
      onSecondary: tokens.surface,
      error: tokens.danger,
      onError: Colors.white,
      surface: tokens.surface,
      onSurface: tokens.textPrimary,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: tokens.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.canvas,
      dividerColor: tokens.border,
      fontFamily: 'Inter',
      fontFamilyFallback: const ['Segoe UI', 'Roboto', 'sans-serif'],
      extensions: [tokens],
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
          color: tokens.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: tokens.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: tokens.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 14,
          color: tokens.textSecondary,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          color: tokens.textSecondary,
          height: 1.4,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: tokens.textMuted,
          height: 1.35,
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: tokens.textPrimary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: tokens.textMuted,
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BackofficeSpacing.radiusLg),
          side: BorderSide(color: tokens.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? tokens.brandAccent : tokens.textPrimary,
          foregroundColor: isDark ? tokens.brandOnAccent : tokens.surface,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BackofficeSpacing.radiusMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          backgroundColor: tokens.surface,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          side: BorderSide(color: tokens.border),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BackofficeSpacing.radiusMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.textSecondary,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BackofficeSpacing.radiusMd),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: tokens.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        hintStyle: TextStyle(fontSize: 13, color: tokens.textMuted),
        labelStyle: TextStyle(fontSize: 13, color: tokens.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BackofficeSpacing.radiusMd),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BackofficeSpacing.radiusMd),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BackofficeSpacing.radiusMd),
          borderSide: BorderSide(color: tokens.brandAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BackofficeSpacing.radiusMd),
          borderSide: BorderSide(color: tokens.danger),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.border,
        thickness: 1,
        space: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? tokens.surfaceSubtle : tokens.textPrimary,
          borderRadius: BorderRadius.circular(BackofficeSpacing.radiusSm),
        ),
        textStyle: TextStyle(
          fontSize: 12,
          color: isDark ? tokens.textPrimary : tokens.surface,
        ),
      ),
    );
  }
}
