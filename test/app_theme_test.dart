import 'package:antiattendance/app_theme.dart';
import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

void main() {
  test('dark uses charcoal while AMOLED keeps all chrome truly black', () {
    final dark = AppTheme.build(AppThemeMode.dark);
    final amoled = AppTheme.build(AppThemeMode.amoled);
    final darkTokens = dark.extension<BrockmannThemeData>()!;
    final amoledTokens = amoled.extension<BrockmannThemeData>()!;
    expect(dark.scaffoldBackgroundColor, const Color(0xff181818));
    expect(darkTokens.surface, const Color(0xff292929));
    expect(dark.colorScheme.surface, darkTokens.surface);
    expect(amoled.scaffoldBackgroundColor, Colors.black);
    expect(amoledTokens.surface, Colors.black);
    expect(amoled.colorScheme.surface, Colors.black);
    expect(amoled.colorScheme.surfaceContainerHigh, Colors.black);
    expect(amoled.colorScheme.surfaceContainerLowest, Colors.black);
  });
  for (final mode in AppThemeMode.values) {
    {
      test('$mode keeps text readable with a neutral palette', () {
        final scheme = AppTheme.build(mode).colorScheme;
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
