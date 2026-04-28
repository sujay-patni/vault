import 'package:flutter/material.dart';

class VaultColors {
  static const background = Color(0xFF080B10);
  static const surface = Color(0xFF10151D);
  static const surfaceHigh = Color(0xFF151B24);
  static const border = Color(0xFF263241);
  static const borderStrong = Color(0xFF334155);
  static const primary = Color(0xFF7AA7FF);
  static const primaryDim = Color(0xFF15233A);
  static const text = Color(0xFFE5E7EB);
  static const textMuted = Color(0xFF94A3B8);
  static const danger = Color(0xFFF87171);
}

class VaultSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

class VaultRadii {
  static const double sm = 6;
  static const double md = 8;
}

ThemeData buildVaultTheme() {
  final scheme = const ColorScheme.dark(
    primary: VaultColors.primary,
    onPrimary: Color(0xFF07111F),
    secondary: Color(0xFF9CC2FF),
    surface: VaultColors.surface,
    onSurface: VaultColors.text,
    onSurfaceVariant: VaultColors.textMuted,
    error: VaultColors.danger,
    outline: VaultColors.border,
    outlineVariant: VaultColors.border,
  );

  final base = ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: VaultColors.background,
    useMaterial3: true,
    brightness: Brightness.dark,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: VaultColors.text,
      displayColor: VaultColors.text,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: VaultColors.background,
      foregroundColor: VaultColors.text,
      titleTextStyle: TextStyle(
        color: VaultColors.text,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: VaultColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VaultRadii.md),
        side: const BorderSide(color: VaultColors.border),
      ),
      margin: const EdgeInsets.only(bottom: VaultSpacing.md),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VaultColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: VaultSpacing.lg,
        vertical: 14,
      ),
      labelStyle: const TextStyle(color: VaultColors.textMuted),
      hintStyle: const TextStyle(color: VaultColors.textMuted),
      helperStyle: const TextStyle(color: VaultColors.textMuted),
      prefixIconColor: VaultColors.textMuted,
      suffixIconColor: VaultColors.textMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VaultRadii.md),
        borderSide: const BorderSide(color: VaultColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VaultRadii.md),
        borderSide: const BorderSide(color: VaultColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VaultRadii.md),
        borderSide: const BorderSide(color: VaultColors.primary),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(VaultRadii.md),
        borderSide: const BorderSide(color: VaultColors.danger),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VaultRadii.md),
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 0,
      backgroundColor: VaultColors.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VaultRadii.md),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VaultRadii.sm),
      ),
      side: const BorderSide(color: VaultColors.border),
      backgroundColor: VaultColors.surface,
      selectedColor: VaultColors.primaryDim,
      labelStyle: const TextStyle(color: VaultColors.textMuted),
      padding: const EdgeInsets.symmetric(horizontal: VaultSpacing.sm),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: VaultColors.textMuted,
      textColor: VaultColors.text,
      titleTextStyle: TextStyle(
        color: VaultColors.text,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      subtitleTextStyle: TextStyle(color: VaultColors.textMuted, fontSize: 13),
      contentPadding: EdgeInsets.symmetric(horizontal: VaultSpacing.lg),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: VaultColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VaultRadii.md),
        side: const BorderSide(color: VaultColors.border),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: VaultColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: VaultColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VaultRadii.md),
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: VaultColors.border,
      thickness: 1,
      space: 1,
    ),
  );
}
