import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AppThemeMode { light, dark, amoled }

abstract final class AppColors {
  static const paper = Colors.white;
  static const ink = Color(0xFF111111);
  static const muted = Color(0xFF6C6C6C);
  static const blue = Color(0xFF202020);
  static const deepBlue = Color(0xFF202020);
  static const line = Color(0xFFC9C9C9);
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

  Color get selectionSurface =>
      Color.alphaBlend(selected.withValues(alpha: .28), surface);

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

  static final _cache = <(AppThemeMode, TargetPlatform), ThemeData>{};

  static ThemeData build(AppThemeMode mode) =>
      _cache.putIfAbsent((mode, defaultTargetPlatform), () => _build(mode));

  static ThemeData _build(AppThemeMode mode) {
    final brockmann = _AATheme(mode);
    final base = brockmann.material;
    final scheme = base.colorScheme.copyWith(
      onSurfaceVariant: brockmann.secondary,
      outline: brockmann.lineStrong,
      outlineVariant: brockmann.line,
      primaryContainer: brockmann.surface,
      onPrimaryContainer: brockmann.foreground,
      secondary: brockmann.accent,
      onSecondary: brockmann.onAccent,
      secondaryContainer: brockmann.surface,
      onSecondaryContainer: brockmann.foreground,
      error: mode == AppThemeMode.light
          ? const Color(0xffa52a22)
          : const Color(0xffffb4ab),
      surfaceTint: Colors.transparent,
    );
    return base.copyWith(
      colorScheme: scheme,
      textTheme: base.textTheme.copyWith(
        headlineLarge: BrockmannType.title.style(color: brockmann.foreground),
        headlineMedium: BrockmannType.heading.style(
          color: brockmann.foreground,
        ),
        headlineSmall: BrockmannType.heading.style(color: brockmann.foreground),
        titleLarge: BrockmannType.heading.style(color: brockmann.foreground),
        titleMedium: BrockmannType.value.style(color: brockmann.foreground),
        titleSmall: BrockmannType.body.style(color: brockmann.foreground),
        bodyLarge: BrockmannType.body
            .style(color: brockmann.foreground)
            .copyWith(fontSize: 16),
        bodyMedium: BrockmannType.body.style(color: brockmann.foreground),
        bodySmall: BrockmannType.caption.style(color: brockmann.secondary),
        labelLarge: BrockmannType.label.style(color: brockmann.foreground),
        labelMedium: BrockmannType.label.style(color: brockmann.secondary),
        labelSmall: BrockmannType.caption.style(color: brockmann.secondary),
      ),
      appBarTheme: AppBarTheme(
        toolbarHeight: 64,
        titleSpacing: 24,
        backgroundColor: brockmann.background,
        foregroundColor: brockmann.foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: BrockmannType.value.style(color: brockmann.foreground),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: mode == AppThemeMode.light
              ? Brightness.dark
              : Brightness.light,
          statusBarBrightness: mode == AppThemeMode.light
              ? Brightness.light
              : Brightness.dark,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: brockmann.secondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: brockmann.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: false,
        shape: Border(top: BorderSide(color: brockmann.line)),
      ),
      dividerTheme: DividerThemeData(
        color: brockmann.line,
        thickness: .5,
        space: .5,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: brockmann.surface,
        elevation: 0,
        shape: Border.symmetric(horizontal: BorderSide(color: brockmann.line)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brockmann.surface,
        contentTextStyle: BrockmannType.body.style(color: brockmann.foreground),
        elevation: 0,
        behavior: SnackBarBehavior.fixed,
        shape: Border(top: BorderSide(color: brockmann.line)),
      ),
    );
  }
}

/// Preserve distinct dark/AMOLED choices while using Brockmann's token system.
class _AATheme extends BrockmannThemeData {
  const _AATheme(this.mode)
    : super(
        brightness: mode == AppThemeMode.light
            ? Brightness.light
            : Brightness.dark,
        accent: mode == AppThemeMode.light ? Colors.black : Colors.white,
        tilt: false,
      );
  final AppThemeMode mode;
  @override
  Color get background =>
      mode == AppThemeMode.dark ? const Color(0xff0a0a0a) : super.background;
  @override
  Color get surface =>
      mode == AppThemeMode.amoled ? Colors.black : super.surface;
}
