import 'package:antiattendance/nfc_pass_page.dart';
import 'package:antiattendance/screen_navigation.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/main.dart';
import 'package:antiattendance/nfc_pass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
    await tester.ensureVisible(
      find.descendant(of: bar, matching: find.text('passes')),
    );
    await tester.tap(find.descendant(of: bar, matching: find.text('passes')));
    await tester.pumpAndSettle();
    expect(find.byType(NfcPassPage), findsOneWidget);
    expect(find.text('Enroll passes'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.descendant(of: bar, matching: find.text('attendance')),
    );
    await tester.tap(
      find.descendant(of: bar, matching: find.text('attendance')),
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(calls, contains('stop'));
    await tester.ensureVisible(
      find.descendant(of: bar, matching: find.text('passes')),
    );
    await tester.tap(find.descendant(of: bar, matching: find.text('passes')));
    await tester.pumpAndSettle();
    expect(find.byType(NfcPassPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    calls.clear();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CampusTextAction && w.tooltip == 'Settings',
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, contains('stop'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('pivot navigation and system Back stop the NFC session', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    FlutterSecureStorage.setMockInitialValues({});
    final calls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(nfcPassChannel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(nfcPassChannel, null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(useAdaptiveNavigation: true, store: _Accounts()),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<ScreenNavigation>(find.byType(ScreenNavigation))
        .onSelected(2);
    await tester.pumpAndSettle();
    calls.clear();
    await tester.drag(find.byType(ListView).first, const Offset(-220, 0));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(calls, contains('stop'));
    expect(find.text('settings'), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    tester
        .widget<ScreenNavigation>(find.byType(ScreenNavigation))
        .onSelected(2);
    await tester.pumpAndSettle();
    expect(find.byType(NfcPassPage), findsOneWidget);
    calls.clear();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(calls, contains('stop'));
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
