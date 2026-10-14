import 'package:flutter/material.dart';

import 'design_tokens.dart';

abstract final class AppTheme {
  static ThemeData light() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.navy,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.navy,
          secondary: AppColors.teal,
          error: AppColors.danger,
          surface: Colors.white,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.navy,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: const BorderSide(color: AppColors.navy, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: colorScheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w600),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.white,
        indicatorColor: colorScheme.secondaryContainer,
        selectedIconTheme: IconThemeData(
          color: colorScheme.onSecondaryContainer,
        ),
        selectedLabelTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border),
    );
  }
}
