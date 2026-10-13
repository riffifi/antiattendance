import 'package:antiattendance/about_logo.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'rigid drag reveals the original logo and retains its orientation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: Center(child: AboutLogo())),
        ),
      );
      await tester.pumpAndSettle();
      final object = find.byKey(const ValueKey('about-logo-rotation'));
      expect(find.byKey(const ValueKey('about-logo-front')), findsOneWidget);
      await tester.drag(object, const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('about-logo-back')), findsOneWidget);
      expect(find.byKey(const ValueKey('about-logo-portrait')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('about-logo-back')), findsOneWidget);
      await tester.drag(object, const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('about-logo-front')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opposite rotation reveals the portrait and keeps it on reversal',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: Center(child: AboutLogo())),
        ),
      );
      await tester.pumpAndSettle();
      final object = find.byKey(const ValueKey('about-logo-rotation'));
      await tester.drag(object, const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('about-logo-portrait')), findsOneWidget);
      await tester.drag(object, const Offset(35, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('about-logo-portrait')), findsOneWidget);
      await tester.drag(object, const Offset(150, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('about-logo-front')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('badge has no shadow or visible rotation instructions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: Center(child: AboutLogo())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Drag to rotate'), findsNothing);
    final decorations = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(AboutLogo),
        matching: find.byType(DecoratedBox),
      ),
    );
    for (final widget in decorations) {
      expect((widget.decoration as BoxDecoration).boxShadow, isNull);
    }
  });

  testWidgets('tap flips the badge when reduced motion is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(AppThemeMode.dark),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Scaffold(body: Center(child: AboutLogo())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('about-logo-rotation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('about-logo-back')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
