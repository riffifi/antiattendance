import 'package:antiattendance/app_haptics.dart';
import 'package:antiattendance/app_settings.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/app_tutorial.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'server_workspace_test.dart' show settleNetwork;

class _Audio implements BrockmannSoundBackend {
  final played = <BrockmannSound>[];
  @override
  Future<bool> prepare() async => true;
  @override
  Future<void> play(BrockmannSound cue, double gain) async {
    played.add(cue);
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => AppHaptics.controller = null);

  test('AA actions use the shared sound controller and respect off', () async {
    final backend = _Audio();
    final feedback = BrockmannFeedbackController(backend: backend);
    addTearDown(feedback.dispose);
    await feedback.configure(
      mode: BrockmannSoundMode.subtle,
      haptics: BrockmannHapticMode.off,
    );
    AppHaptics.controller = feedback;
    AppHaptics.selection();
    await Future<void>.delayed(Duration.zero);
    expect(backend.played, [BrockmannSound.select]);
    await feedback.configure(mode: BrockmannSoundMode.off);
    AppHaptics.navigation();
    await Future<void>.delayed(Duration.zero);
    expect(backend.played, hasLength(1));
  });

  testWidgets(
    'welcome language, appearance and sounds persist and update immediately',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppSettingsStore();
      var mode = AppThemeMode.light;
      String? language;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, update) => MaterialApp(
            locale: Locale(language ?? 'en'),
            supportedLocales: const [Locale('en'), Locale('ru')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: AppTheme.build(mode),
            home: AppTutorial(
              settings: store,
              themeMode: mode,
              language: language,
              onThemeModeChanged: (value) => update(() => mode = value),
              onLanguageChanged: (value) => update(() => language = value),
              onComplete: () async {},
            ),
          ),
        ),
      );
      await settleNetwork(tester);
      final theme = find.byKey(const ValueKey('oobe-theme'));
      await tester.ensureVisible(theme);
      await tester.pumpAndSettle();
      await tester.tap(theme);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await settleNetwork(tester);
      expect(mode, AppThemeMode.dark);
      expect(await store.loadThemeMode(), AppThemeMode.dark);
      final lang = find.byKey(const ValueKey('oobe-language'));
      await tester.ensureVisible(lang);
      await tester.pumpAndSettle();
      await tester.tap(lang);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Русский'));
      await settleNetwork(tester);
      expect(language, 'ru');
      expect(await store.loadLanguage(), 'ru');
      tester.widget<CampusSwitch>(find.byType(CampusSwitch)).onChanged!(false);
      await settleNetwork(tester);
      expect(await store.interfaceSounds(), isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
