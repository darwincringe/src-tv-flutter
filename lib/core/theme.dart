import 'package:flutter/material.dart';

/// Palette ported from the Kotlin `ui/theme/Color.kt`.
class AppColors {
  static const railBlack = Color(0xFF0A0A0A);
  static const charcoal = Color(0xFF161616);
  static const charcoalLight = Color(0xFF242424);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xB3FFFFFF); // white 70%
  static const ratingYellow = Color(0xFFFFC107);
}

/// Dark-only theme (the app never uses a light scheme), mirroring the Kotlin
/// `darkColorScheme` setup.
ThemeData buildAppTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.charcoal,
    canvasColor: AppColors.charcoal,
  );
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      surface: AppColors.charcoal,
      primary: AppColors.textPrimary,
      secondary: AppColors.ratingYellow,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
  );
}
