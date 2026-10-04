import 'package:antiattendance/campus_design.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/main.dart';
import 'package:antiattendance/nfc_pass.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Accounts extends AccountStore {
  @override
  Future<List<SavedAccount>> load() async => const [
    SavedAccount(id: 'a', label: 'Alice', cookie: 'test-session'),
  ];
}

void main() {
  testWidgets('leaving Passes stops NFC and rapid reentry is safe', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    FlutterSecureStorage.setMockInitialValues({});
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(nfcPassChannel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(nfcPassChannel, null));
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(store: _Accounts()),
      ),
    );
    await tester.pumpAndSettle();
    final bar = find.byType(CampusNavigation);
    await tester.tap(find.descendant(of: bar, matching: find.text('Passes')));
    await tester.pumpAndSettle();
    expect(find.text('NFC passes'), findsOneWidget);
    expect(find.text('Start queue'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(
      find.descendant(of: bar, matching: find.text('Attendance')),
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(calls, contains('stop'));
    await tester.tap(find.descendant(of: bar, matching: find.text('Passes')));
    await tester.pumpAndSettle();
    expect(find.text('NFC passes'), findsOneWidget);
    expect(tester.takeException(), isNull);
    calls.clear();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is M3EIconButton && w.tooltip == 'Settings',
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, contains('stop'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}
