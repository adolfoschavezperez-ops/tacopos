import 'package:flutter/material.dart';

import 'brand_colors.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: BrandColors.accentOrange,
      brightness: Brightness.dark,
      primary: BrandColors.accentYellow,
      secondary: BrandColors.accentOrange,
      surface: BrandColors.surfaceDark,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: BrandColors.backgroundPrimary,
      fontFamily: 'Roboto',
    );

    const titleStyle = TextStyle(
      color: BrandColors.textPrimary,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );

    return base.copyWith(
      textTheme: base.textTheme
          .apply(
            bodyColor: BrandColors.textSecondary,
            displayColor: BrandColors.textPrimary,
          )
          .copyWith(
            headlineLarge: titleStyle.copyWith(fontSize: 44, height: 1.02),
            headlineMedium: titleStyle.copyWith(fontSize: 30, height: 1.08),
            titleLarge: titleStyle.copyWith(fontSize: 22),
            titleMedium: titleStyle.copyWith(fontSize: 17),
            bodyLarge: const TextStyle(
              color: BrandColors.textSecondary,
              fontSize: 16,
              height: 1.35,
            ),
            bodyMedium: const TextStyle(
              color: BrandColors.textSecondary,
              fontSize: 14,
              height: 1.35,
            ),
            labelLarge: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: BrandColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: BrandColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
      cardTheme: CardThemeData(
        color: BrandColors.glassFill,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: BrandColors.glassBorder),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BrandColors.accentYellow,
          foregroundColor: BrandColors.backgroundPrimary,
          minimumSize: const Size(120, 50),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BrandColors.textPrimary,
          minimumSize: const Size(112, 48),
          side: const BorderSide(color: BrandColors.glassBorder),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: BrandColors.textSecondary,
          backgroundColor: BrandColors.glassFill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: BrandColors.glassBorder),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BrandColors.glassFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BrandColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BrandColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BrandColors.accentYellow),
        ),
        labelStyle: const TextStyle(color: BrandColors.textMuted),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: BrandColors.glassFill,
        selectedColor: BrandColors.accentGlow,
        side: const BorderSide(color: BrandColors.glassBorder),
        labelStyle: const TextStyle(
          color: BrandColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: BrandColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dividerTheme: const DividerThemeData(
        color: BrandColors.glassBorder,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: BrandColors.surfaceDark,
        contentTextStyle: const TextStyle(color: BrandColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
