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
