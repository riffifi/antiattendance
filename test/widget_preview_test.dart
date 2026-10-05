import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/widget_preview.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final nfc in [false, true]) {
    testWidgets(
      'widget preview selects compact size for nfc=$nfc on a narrow phone',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        bool? chosen;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => M3EButton.text(
                  onPressed: () async {
                    chosen = await showWidgetPreview(context, nfc: nfc);
                  },
                  child: const Text('Preview'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();
        expect(find.byType(WidgetPreview), findsNWidgets(2));
        await tester.tap(find.text('Compact · 1×1'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add widget'));
        await tester.pumpAndSettle();
        expect(chosen, true);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
