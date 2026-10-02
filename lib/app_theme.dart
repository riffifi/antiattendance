import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AppThemeMode { light, dark, amoled }

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

class AppPalette {
  const AppPalette({
    required this.paper,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.blue,
    required this.onBlue,
    required this.deepBlue,
    required this.line,
    required this.selected,
    required this.mint,
    required this.success,
  });

  final Color paper;
  final Color surface;
  final Color ink;
  final Color muted;
  final Color blue;
  final Color onBlue;
  final Color deepBlue;
  final Color line;
  final Color selected;
  final Color mint;
  final Color success;

  static AppPalette of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return AppPalette(
      paper: theme.scaffoldBackgroundColor,
      surface: scheme.surface,
      ink: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      blue: scheme.primary,
      onBlue: scheme.onPrimary,
      deepBlue: isDark ? scheme.onPrimaryContainer : scheme.primary,
      line: scheme.outlineVariant,
      selected: scheme.primaryContainer,
      mint: isDark ? scheme.secondaryContainer : AppColors.mint,
      success: isDark ? const Color(0xFF73D5AB) : const Color(0xFF238664),
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => AppPalette.of(this);
}

abstract final class AppTheme {
  static ThemeData get light => build(AppThemeMode.light);

  static ThemeData build(AppThemeMode mode, {Color? monetSeed}) {
    final isDark = mode != AppThemeMode.light;
    final amoled = mode == AppThemeMode.amoled;
    final paper = amoled
        ? Colors.black
        : isDark
        ? const Color(0xFF101820)
        : AppColors.paper;
    final surface = amoled
        ? const Color(0xFF0A0A0A)
        : isDark
        ? const Color(0xFF1B2632)
        : Colors.white;
    final ink = isDark ? const Color(0xFFF2F5F8) : AppColors.ink;
    final muted = isDark ? const Color(0xFFA7B5C4) : AppColors.muted;
    final line = isDark ? const Color(0xFF354251) : AppColors.line;
    final scheme =
        (monetSeed == null
                ? isDark
                      ? ColorScheme.fromSeed(
                          seedColor: AppColors.blue,
                          brightness: Brightness.dark,
                        )
                      : const ColorScheme.light(
                          primary: AppColors.blue,
                          onPrimary: Colors.white,
                          error: Color(0xFFBD4B46),
                        )
                : ColorScheme.fromSeed(
                    seedColor: monetSeed,
                    brightness: isDark ? Brightness.dark : Brightness.light,
                  ))
            .copyWith(
              surface: surface,
              onSurface: ink,
              onSurfaceVariant: muted,
              outlineVariant: line,
            );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Geist',
    );
    return base.copyWith(
      scaffoldBackgroundColor: paper,
      canvasColor: paper,
      cardColor: surface,
      textTheme: base.textTheme.apply(
        fontFamily: 'Geist',
        bodyColor: ink,
        displayColor: ink,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Geist',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paper,
        indicatorColor: scheme.primary,
        elevation: 0,
        height: 70,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : muted,
            size: 23,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Geist',
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : muted,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: line,
          disabledForegroundColor: muted,
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
          foregroundColor: scheme.primary,
          side: BorderSide(color: line),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paper,
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
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF2E3B49) : AppColors.ink,
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
