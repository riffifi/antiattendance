import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app fields preserve native formatting and submission', (
    tester,
  ) async {
    String? submitted;
    await tester.pumpWidget(
      BrockmannApp(
        home: BrockmannPage(
          child: BrockmannTextField(
            label: 'Code',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 4,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => submitted = value,
            leading: const Text('#'),
            suffixText: 'digits',
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'a12b345');
    expect(find.text('1234'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, '1234');
    expect(tester.takeException(), isNull);
  });

  testWidgets('rich actions retain their accessible label and foreground', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      BrockmannApp(
        home: BrockmannPage(
          child: BrockmannButton.primary(
            label: '',
            child: const Text('Scan selected accounts'),
            onPressed: () => taps++,
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Scan selected accounts'), findsOneWidget);
    await tester.tap(find.text('Scan selected accounts'));
    expect(taps, 1);
    final context = tester.element(find.text('Scan selected accounts'));
    expect(
      DefaultTextStyle.of(context).style.color,
      context.brockmann.onAccent,
    );
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('app supplies localized calendar commands', (tester) async {
    await tester.pumpWidget(
      BrockmannApp(
        home: Builder(
          builder: (context) => BrockmannPage(
            child: BrockmannButton(
              label: 'Open',
              onPressed: () => showBrockmannDatePicker(
                context,
                initialDate: DateTime(2026, 10, 28),
                firstDate: DateTime(2026),
                lastDate: DateTime(2027),
                title: 'Выберите дату',
                confirmLabel: 'Готово',
                cancelLabel: 'Отмена',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Выберите дату'), findsOneWidget);
    expect(find.text('Готово'), findsOneWidget);
    await tester.ensureVisible(find.text('Отмена'));
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.byType(BrockmannCalendar), findsNothing);
  });
}
