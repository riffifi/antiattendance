import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'WP8 profile keeps input readable in both themes and speeds pivots',
    (tester) async {
      for (final brightness in Brightness.values) {
        final theme = BrockmannThemeData(
          style: BrockmannStyle.wp8,
          brightness: brightness,
        );
        expect(theme.copyWith(accent: Colors.blue).windowsPhone, isTrue);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.material,
            home: const Scaffold(
              body: BrockmannTextField(label: 'Name', initialValue: 'Alex'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final input = tester.widget<TextFormField>(find.byType(TextFormField));
        // Inspect the editable field: its ink must contrast with the light fill,
        // including when the rest of the app is dark.
        final editable = tester.widget<EditableText>(find.byType(EditableText));
        expect(editable.style.color, Colors.black);
        final decorator = tester.widget<InputDecorator>(
          find.byType(InputDecorator),
        );
        expect(decorator.decoration.filled, isTrue);
        expect(
          BrockmannThemeData.contrast(
            editable.style.color!,
            decorator.decoration.fillColor!,
          ),
          greaterThan(10),
        );
        expect(
          theme.pivotDuration(tester.element(find.byWidget(input))),
          const Duration(milliseconds: 240),
        );
        final builder = theme
            .material
            .pageTransitionsTheme
            .builders[TargetPlatform.android]!;
        expect(builder.transitionDuration, const Duration(milliseconds: 320));
        expect(
          builder.reverseTransitionDuration,
          const Duration(milliseconds: 180),
        );
      }
    },
  );
}
