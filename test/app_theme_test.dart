import 'package:antiattendance/app_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

void main() {
  test('Monet colors surfaces as well as the accent', () {
    for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
      final green = AppTheme.build(mode, monetSeed: Colors.green);
      final pink = AppTheme.build(mode, monetSeed: Colors.pink);
      expect(
        green.scaffoldBackgroundColor,
        isNot(pink.scaffoldBackgroundColor),
      );
      expect(green.colorScheme.surface, isNot(pink.colorScheme.surface));
    }
    expect(
      AppTheme.build(
        AppThemeMode.amoled,
        monetSeed: Colors.pink,
      ).scaffoldBackgroundColor,
      Colors.black,
    );
  });
  for (final mode in AppThemeMode.values) {
    for (final seed in <Color?>[null, Colors.green, Colors.pink]) {
      test('$mode / $seed keeps accent and container text readable', () {
        final scheme = AppTheme.build(mode, monetSeed: seed).colorScheme;
        expect(
          contrast(scheme.primary, scheme.onPrimary),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(scheme.primaryContainer, scheme.onSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(scheme.surface, scheme.onSurface),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  }
}
