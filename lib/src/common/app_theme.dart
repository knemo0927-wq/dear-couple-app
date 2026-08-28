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
      primaryContainer: DearColors.coralSoft,
      onPrimaryContainer: DearColors.coralText,
      secondary: DearColors.coralLight,
      onSecondary: DearColors.ink,
      tertiary: DearColors.accent,
      surface: DearColors.card,
      surfaceContainerLowest: DearColors.backgroundTop,
      surfaceContainerLow: const Color(0xFFFFFBFC),
      surfaceContainer: DearColors.blush,
      surfaceContainerHigh: DearColors.blushDeep,
      surfaceContainerHighest: DearColors.blushDeep,
      onSurface: DearColors.ink,
      onSurfaceVariant: DearColors.secondary,
      outline: DearColors.outlineStrong,
      outlineVariant: DearColors.line,
      error: DearColors.error,
      shadow: DearColors.shadow,
    );

    final controlBorderRadius = BorderRadius.circular(DearRadii.control);
    final cardBorderRadius = BorderRadius.circular(DearRadii.card);
    final textTheme = DearTextStyles.applyTo(
      Typography.blackCupertino,
      primaryColor: DearColors.ink,
      secondaryColor: DearColors.secondary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: DearColors.backgroundTop,
      fontFamilyFallback: const ['Apple SD Gothic Neo', 'Noto Sans KR'],
      textTheme: textTheme,
      iconTheme: const IconThemeData(size: DearIconSizes.medium),
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
          height: 24 / 18,
          fontWeight: FontWeight.w800,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: cardBorderRadius,
          side: const BorderSide(color: DearColors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DearSpacing.space16,
          vertical: DearSpacing.space16,
        ),
        hintStyle: const TextStyle(color: DearColors.placeholder),
        labelStyle: const TextStyle(color: DearColors.secondary),
        border: OutlineInputBorder(
          borderRadius: controlBorderRadius,
          borderSide: const BorderSide(color: DearColors.outlineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: controlBorderRadius,
          borderSide: const BorderSide(color: DearColors.outlineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: controlBorderRadius,
          borderSide: const BorderSide(color: DearColors.coralText, width: 1.6),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: controlBorderRadius,
          borderSide: const BorderSide(color: DearColors.line),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: controlBorderRadius,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: controlBorderRadius,
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DearColors.coralText,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DearRadii.control),
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
            borderRadius: BorderRadius.circular(DearRadii.control),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DearColors.coralText,
          side: const BorderSide(color: DearColors.outlineStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DearRadii.control),
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
          borderRadius: BorderRadius.circular(DearRadii.control),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: DearColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(DearRadii.sheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: DearColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DearRadii.card),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: sakuraPink,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFFFF9AC2),
      onPrimary: const Color(0xFF4A0827),
      primaryContainer: const Color(0xFF502439),
      onPrimaryContainer: const Color(0xFFFFD9E7),
      secondary: const Color(0xFFF0B3CB),
      onSecondary: const Color(0xFF45202F),
      secondaryContainer: const Color(0xFF5B3343),
      onSecondaryContainer: const Color(0xFFFFD9E7),
      tertiary: const Color(0xFFFFB39E),
      onTertiary: const Color(0xFF561F12),
      surface: const Color(0xFF261B21),
      surfaceDim: const Color(0xFF171116),
      surfaceBright: const Color(0xFF423039),
      surfaceContainerLowest: const Color(0xFF171116),
      surfaceContainerLow: const Color(0xFF21171D),
      surfaceContainer: const Color(0xFF291C23),
      surfaceContainerHigh: const Color(0xFF32222A),
      surfaceContainerHighest: const Color(0xFF3A2832),
      onSurface: const Color(0xFFFFF5F8),
      onSurfaceVariant: const Color(0xFFDCC7CF),
      outline: const Color(0xFFD08BA6),
      outlineVariant: const Color(0xFF684654),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
      errorContainer: const Color(0xFF5B2025),
      onErrorContainer: const Color(0xFFFFDAD7),
      shadow: Colors.black,
      scrim: Colors.black,
    );
    final controlBorderRadius = BorderRadius.circular(DearRadii.control);
    final cardBorderRadius = BorderRadius.circular(DearRadii.card);
    final textTheme = DearTextStyles.applyTo(
      Typography.whiteCupertino,
      primaryColor: scheme.onSurface,
      secondaryColor: scheme.onSurfaceVariant,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      canvasColor: scheme.surfaceContainerLow,
      disabledColor: scheme.onSurface.withValues(alpha: 0.38),
      dividerColor: scheme.outlineVariant,
      shadowColor: scheme.shadow,
      splashColor: scheme.primary.withValues(alpha: 0.12),
      highlightColor: scheme.primary.withValues(alpha: 0.08),
      focusColor: scheme.primary.withValues(alpha: 0.16),
      hoverColor: scheme.primary.withValues(alpha: 0.08),
      fontFamilyFallback: const ['Apple SD Gothic Neo', 'Noto Sans KR'],
      textTheme: textTheme,
      iconTheme: IconThemeData(
        size: DearIconSizes.medium,
        color: scheme.onSurfaceVariant,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: scheme.surfaceContainerLowest,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: scheme.surfaceContainerLowest,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          height: 24 / 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: cardBorderRadius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DearSpacing.space16,
          vertical: DearSpacing.space16,
        ),
        hintStyle: const TextStyle(color: Color(0xFFCDB5BF)),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        floatingLabelStyle: TextStyle(color: scheme.primary),
        border: OutlineInputBorder(
          borderRadius: controlBorderRadius,
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: controlBorderRadius,
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: controlBorderRadius,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: controlBorderRadius,
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: controlBorderRadius,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: controlBorderRadius,
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DearRadii.control),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DearRadii.control),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DearRadii.control),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const StadiumBorder(),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        textColor: scheme.onSurface,
        iconColor: scheme.onSurfaceVariant,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStatePropertyAll(scheme.outline),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        side: BorderSide(color: scheme.outline, width: 1.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DearRadii.extraSmall),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant;
        }),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          );
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
        textStyle: WidgetStatePropertyAll(textTheme.bodyMedium),
        hintStyle: const WidgetStatePropertyAll(
          TextStyle(color: Color(0xFFCDB5BF)),
        ),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        textStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DearRadii.control),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DearRadii.control),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        modalBackgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: scheme.scrim.withValues(alpha: 0.56),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(DearRadii.sheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        barrierColor: scheme.scrim.withValues(alpha: 0.56),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DearRadii.card),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(DearRadii.chip),
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface),
      ),
    );
  }
}
