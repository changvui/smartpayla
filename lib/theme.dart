import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF0B6B5B);
  static const primaryDark = Color(0xFF064A40);
  static const background = Color(0xFFF4F7F6);
  static const surface = Colors.white;
  static const ink = Color(0xFF14201D);
  static const muted = Color(0xFF667873);
  static const border = Color(0xFFE1EAE6);
  static const green = Color(0xFF1E7B4F);
  static const amber = Color(0xFFB26A00);
  static const red = Color(0xFFB3261E);
  static const blue = Color(0xFF2B5F9E);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: AppColors.ink),
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.primary.withValues(alpha: 0.12),
      height: 68,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
  );
}
