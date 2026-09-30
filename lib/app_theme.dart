import 'package:flutter/material.dart';

abstract final class AppColors {
  static const paper = Color(0xFFF5F6F3);
  static const ink = Color(0xFF14243A);
  static const muted = Color(0xFF718093);
  static const blue = Color(0xFF315DDE);
  static const deepBlue = Color(0xFF152B62);
  static const line = Color(0xFFE3E8EC);
  static const lime = Color(0xFFD9F36B);
  static const mint = Color(0xFFE7F6EE);
  static const red = Color(0xFFFCE9E4);
}

abstract final class AppTheme {
  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: AppColors.blue,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: AppColors.ink,
      error: Color(0xFFBD4B46),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Geist',
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.paper,
      textTheme: base.textTheme.apply(
        fontFamily: 'Geist',
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.paper,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Geist',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.line,
          disabledForegroundColor: AppColors.muted,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.line),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.paper,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(
          fontFamily: 'Geist',
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
