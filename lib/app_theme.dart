import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

enum AppThemeMode { light, dark, amoled }

abstract final class AppColors {
  static const paper = Color(0xFFFAFAFA);
  static const ink = Color(0xFF20232B);
  static const muted = Color(0xFF636774);
  static const blue = Color(0xFF234CDB);
  static const deepBlue = Color(0xFF152B62);
  static const line = Color(0xFFE2E3E9);
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
      mint: scheme.secondaryContainer,
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
    final generated = ColorScheme.fromSeed(
      seedColor: monetSeed ?? AppColors.blue,
      brightness: isDark ? Brightness.dark : Brightness.light,
    );
    final paper = amoled
        ? Colors.black
        : monetSeed != null
        ? generated.surface
        : isDark
        ? const Color(0xFF14151A)
        : AppColors.paper;
    final surface = monetSeed != null
        ? generated.surfaceContainerLow
        : amoled
        ? const Color(0xFF0A0A0A)
        : isDark
        ? const Color(0xFF202127)
        : Colors.white;
    final ink = monetSeed != null
        ? generated.onSurface
        : isDark
        ? const Color(0xFFF2F5F8)
        : AppColors.ink;
    final muted = monetSeed != null
        ? generated.onSurfaceVariant
        : isDark
        ? const Color(0xFFA7ADBD)
        : AppColors.muted;
    final line = monetSeed != null
        ? generated.outlineVariant
        : isDark
        ? const Color(0xFF3B3D47)
        : AppColors.line;
    final scheme = generated.copyWith(
      primary: monetSeed == null && !isDark ? AppColors.blue : null,
      onPrimary: monetSeed == null && !isDark ? Colors.white : null,
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
    final feedback = WidgetStateProperty.resolveWith<Color?>(
      (states) =>
          states.contains(WidgetState.focused) ||
              states.contains(WidgetState.hovered)
          ? scheme.primary.withValues(alpha: .08)
          : Colors.transparent,
    );
    return base.copyWith(
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: scheme.primary.withValues(alpha: .05),
      focusColor: scheme.primary.withValues(alpha: .08),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: muted,
        ).copyWith(overlayColor: feedback),
      ),
      scaffoldBackgroundColor: paper,
      canvasColor: paper,
      cardColor: surface,
      textTheme: base.textTheme
          .copyWith(
            headlineLarge: TextStyle(
              fontSize: 36,
              height: 1.05,
              letterSpacing: -1.5,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
            titleLarge: TextStyle(
              fontSize: 22,
              letterSpacing: -.6,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          )
          .apply(fontFamily: 'Geist', bodyColor: ink, displayColor: ink),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
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
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 76,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
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
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ).copyWith(overlayColor: feedback),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: line),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ).copyWith(overlayColor: feedback),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Geist',
            fontWeight: FontWeight.w600,
          ),
        ).copyWith(overlayColor: feedback),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: line),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: line),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF2E3B49) : AppColors.ink,
        contentTextStyle: const TextStyle(
          fontFamily: 'Geist',
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
