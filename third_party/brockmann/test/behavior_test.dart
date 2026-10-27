import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAudio implements BrockmannSoundBackend {
  final played = <BrockmannSound>[];
  int stops = 0;
  @override
  Future<bool> prepare() async => true;
  @override
  Future<void> play(BrockmannSound cue, double gain) async {
    played.add(cue);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() => stop();
}

class QuietHaptics extends BrockmannHapticBackend {
  @override
  Future<void> play(BrockmannSound cue) async {}
  @override
  Future<void> cancel() async {}
}

void main() {
  testWidgets(
    'Sound is opt-in, coalesced, mode-filtered and stopped in background',
    (tester) async {
      final backend = FakeAudio();
      final sound = BrockmannSoundController(
        backend: backend,
        hapticBackend: QuietHaptics(),
      );
      await sound.configure(haptics: BrockmannHapticMode.off);
      sound.play(BrockmannSound.confirm);
      await tester.pump();
      expect(backend.played, isEmpty);
      await sound.configure(mode: BrockmannSoundMode.essential);
      sound.play(BrockmannSound.activate);
      sound.play(BrockmannSound.toggleOn);
      sound.play(BrockmannSound.confirm);
      await tester.pump();
      expect(backend.played, [BrockmannSound.confirm]);
      sound.didChangeAppLifecycleState(AppLifecycleState.paused);
      sound.play(BrockmannSound.reject);
      await tester.pump();
      expect(backend.played, hasLength(1));
      expect(backend.stops, greaterThan(0));
      sound.dispose();
    },
  );

  test('Every palette accent has accessible text in both themes', () {
    for (final brightness in Brightness.values) {
      for (final scheme in windows8Palette()) {
        final t = BrockmannThemeData(
          brightness: brightness,
          accent: scheme.primary,
        );
        expect(
          BrockmannThemeData.contrast(t.accent, t.onAccent),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          BrockmannThemeData.contrast(t.accentText, t.background),
          greaterThanOrEqualTo(4.49),
        );
      }
    }
  });

  testWidgets('Switch reverses through intermediate animation frames', (
    tester,
  ) async {
    bool value = true;
    await tester.pumpWidget(
      BrockmannApp(
        home: StatefulBuilder(
          builder: (context, set) => BrockmannPage(
            child: BrockmannSwitch(
              label: 'power',
              value: value,
              onChanged: (v) => set(() => value = v),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(BrockmannSwitch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(value, false);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Picker commits one choice and cancellation preserves the value',
    (tester) async {
      int selected = 1;
      await tester.pumpWidget(
        BrockmannApp(
          home: StatefulBuilder(
            builder: (context, set) => BrockmannPage(
              child: BrockmannPicker(
                label: 'theme',
                options: const ['light', 'dark', 'system'],
                selected: selected,
                onChanged: (v) => set(() => selected = v),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(BrockmannPicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('system'));
      await tester.pumpAndSettle();
      expect(selected, 2);
      await tester.tap(find.byType(BrockmannPicker));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(selected, 2);
    },
  );

  testWidgets('Palette variants fit narrow and enlarged layouts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final variant in BrockmannPaletteVariant.values) {
      for (final axis in Axis.values) {
        await tester.pumpWidget(
          BrockmannApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: BrockmannPage(
                  child: BrockmannColorPicker(
                    label: 'colour',
                    schemes: windows8Palette(),
                    selected: 12,
                    companionCount: 3,
                    variant: variant,
                    axis: axis,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$variant $axis');
      }
    }
  });

  testWidgets(
    'Pivot keeps earlier options available after selecting the last',
    (tester) async {
      int selected = 0;
      await tester.pumpWidget(
        BrockmannApp(
          home: StatefulBuilder(
            builder: (context, set) => BrockmannPage(
              child: BrockmannPivot(
                options: const ['one', 'two', 'three'],
                selected: selected,
                compact: true,
                onChanged: (v) => set(() => selected = v),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('three'));
      await tester.pumpAndSettle();
      expect(find.text('one'), findsOneWidget);
      await tester.tap(find.text('one'));
      expect(selected, 0);
    },
  );
}
