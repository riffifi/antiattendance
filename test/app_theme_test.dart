import 'package:antiattendance/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all appearance modes keep readable surfaces', () {
    final light = AppTheme.build(AppThemeMode.light);
    final dark = AppTheme.build(AppThemeMode.dark);
    final amoled = AppTheme.build(AppThemeMode.amoled);

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(amoled.brightness, Brightness.dark);
    expect(amoled.scaffoldBackgroundColor, Colors.black);
    expect(dark.scaffoldBackgroundColor, isNot(Colors.black));
    expect(dark.colorScheme.surface, isNot(Colors.white));
    expect(amoled.colorScheme.surface, isNot(Colors.white));
  });

  test('phone color changes the accent in every appearance mode', () {
    const wallpaperColor = Color(0xFFCA812D);
    for (final mode in AppThemeMode.values) {
      final ordinary = AppTheme.build(mode).colorScheme.primary;
      final monet = AppTheme.build(
        mode,
        monetSeed: wallpaperColor,
      ).colorScheme.primary;
      expect(monet, isNot(ordinary), reason: mode.name);
    }
  });
}
