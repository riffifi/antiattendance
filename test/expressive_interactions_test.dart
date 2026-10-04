import 'package:antiattendance/expressive.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('back closes the pass picker before leaving its screen', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Home')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: AppPassPicker(
            enabled: true,
            hint: 'Your account',
            items: const [
              M3EDropdownItem(value: 'a', label: 'Alice', selected: true),
              M3EDropdownItem(value: 'b', label: 'Bob'),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppPassPicker));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsNothing);
    expect(find.byType(AppPassPicker), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expressive menu closes on back and selects actions', (
    tester,
  ) async {
    Object? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: M3EMenu(
            entries: const [M3EMenuEntry(value: 'rename', label: 'Rename')],
            onSelected: (value) => choice = value,
            anchorBuilder: (_, open) =>
                M3EButton.text(onPressed: open, child: const Text('Actions')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsNothing);
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(choice, 'rename');
    expect(find.text('Rename'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
