import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dear_design.dart';

class AppTheme {
  static const Color sakuraPink = DearColors.coral;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: sakuraPink,
      brightness: Brightness.light,
    ).copyWith(
      primary: DearColors.coralText,
      onPrimary: Colors.white,
      secondary: DearColors.coralLight,
      onSecondary: DearColors.ink,
      tertiary: DearColors.accent,
      surface: DearColors.card,
      surfaceContainer: DearColors.blush,
      surfaceContainerHighest: DearColors.blushDeep,
      onSurface: DearColors.ink,
      onSurfaceVariant: DearColors.secondary,
      outlineVariant: DearColors.line,
      error: DearColors.error,
    );

    final borderRadius = BorderRadius.circular(DearRadii.medium);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: DearColors.backgroundTop,
      fontFamilyFallback: const ['Apple SD Gothic Neo', 'Noto Sans KR'],
      textTheme: Typography.blackCupertino.apply(
        bodyColor: DearColors.ink,
        displayColor: DearColors.ink,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: DearColors.backgroundTop,
        elevation: 0,
        foregroundColor: DearColors.ink,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: DearColors.backgroundTop,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          color: DearColors.ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: const BorderSide(color: DearColors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        hintStyle: const TextStyle(color: DearColors.disabled),
        labelStyle: const TextStyle(color: DearColors.muted),
        border: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: DearColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: DearColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: DearColors.coral, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DearColors.coralText,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DearRadii.medium),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DearColors.coralText,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DearRadii.medium),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DearColors.coralText,
          side: const BorderSide(color: DearColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DearRadii.medium),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: DearColors.coralText,
        foregroundColor: Colors.white,
        shape: StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DearRadii.medium),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: DearColors.card,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: DearColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DearRadii.large),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: sakuraPink,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFFFF9CC7),
      secondary: const Color(0xFFFFB7D6),
      surface: const Color(0xFF1A1217),
      surfaceContainerHighest: const Color(0xFF35222D),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
      ),
    );
  }
}
