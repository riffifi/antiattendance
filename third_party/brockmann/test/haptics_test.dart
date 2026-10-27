import 'dart:async';

import 'package:brockmann/brockmann.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class Haptics extends BrockmannHapticBackend {
  final played = <BrockmannSound>[];
  int cancellations = 0;
  final gestures = <bool>[];
  @override
  Future<void> gesture({required bool lifting}) async {
    gestures.add(lifting);
  }

  @override
  Future<void> play(BrockmannSound cue) async {
    played.add(cue);
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }
}

class Audio implements BrockmannSoundBackend {
  final played = <BrockmannSound>[];
  Completer<bool>? startup;
  @override
  Future<bool> prepare() => startup?.future ?? Future.value(true);
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
  testWidgets('Picker detents are haptic-only, coalesced and respect mute', (
    tester,
  ) async {
    final haptics = Haptics(), audio = Audio();
    final feedback = BrockmannFeedbackController(
      backend: audio,
      hapticBackend: haptics,
    );
    feedback.selection();
    feedback.selection();
    await tester.pump();
    expect(haptics.played, [BrockmannSound.select]);
    expect(audio.played, isEmpty);
    await feedback.configure(haptics: BrockmannHapticMode.off);
    feedback.selection();
    expect(haptics.played, hasLength(1));
    feedback.dispose();
  });

  testWidgets(
    'Essential haptics work while audio is muted and prioritize outcomes',
    (tester) async {
      final haptics = Haptics(), audio = Audio();
      final feedback = BrockmannFeedbackController(
        backend: audio,
        hapticBackend: haptics,
      );
      feedback.play(BrockmannSound.select);
      await tester.pump();
      expect(haptics.played, isEmpty);
      feedback.play(BrockmannSound.toggleOn);
      feedback.play(BrockmannSound.confirm);
      await tester.pump();
      expect(haptics.played, [BrockmannSound.confirm]);
      expect(audio.played, isEmpty);
      feedback.dispose();
    },
  );
  testWidgets('Muting and backgrounding cancel a pending haptic sequence', (
    tester,
  ) async {
    final haptics = Haptics();
    final feedback = BrockmannFeedbackController(
      backend: Audio(),
      hapticBackend: haptics,
    );
    feedback.play(BrockmannSound.confirm);
    await feedback.configure(haptics: BrockmannHapticMode.off);
    await tester.pump();
    expect(haptics.played, isEmpty);
    await feedback.configure(haptics: BrockmannHapticMode.subtle);
    feedback.didChangeAppLifecycleState(AppLifecycleState.paused);
    feedback.play(BrockmannSound.reject);
    await tester.pump();
    expect(haptics.played, isEmpty);
    expect(haptics.cancellations, greaterThanOrEqualTo(2));
    feedback.dispose();
  });
  testWidgets('Haptic feedback does not wait for sound assets', (tester) async {
    final haptics = Haptics(), audio = Audio()..startup = Completer<bool>();
    final feedback = BrockmannFeedbackController(
      backend: audio,
      hapticBackend: haptics,
    );
    final preparing = feedback.configure(
      mode: BrockmannSoundMode.subtle,
      haptics: BrockmannHapticMode.subtle,
    );
    feedback.play(BrockmannSound.select);
    await tester.pump();
    expect(haptics.played, [BrockmannSound.select]);
    expect(audio.played, isEmpty);
    audio.startup!.complete(true);
    await preparing;
    expect(audio.played, isEmpty); // No late audio replay.
    feedback.dispose();
  });
  testWidgets('Pickup and landing are distinct and honor mute', (tester) async {
    final haptics = Haptics();
    final feedback = BrockmannFeedbackController(
      backend: Audio(),
      hapticBackend: haptics,
    );
    feedback.gesture(lifting: true);
    feedback.gesture(lifting: false);
    await tester.pump();
    expect(haptics.gestures, [true, false]);
    await feedback.configure(haptics: BrockmannHapticMode.off);
    feedback.gesture(lifting: true);
    expect(haptics.gestures, hasLength(2));
    feedback.dispose();
  });
  testWidgets(
    'Native adapter sends semantic cue and cancellation, no forced setting',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AndroidSoundBackend.channel,
        (call) async {
          calls.add(call);
          return call.method == 'haptics.play' ? true : null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          AndroidSoundBackend.channel,
          null,
        ),
      );
      final backend = AndroidHapticBackend();
      await backend.play(BrockmannSound.reject);
      await backend.cancel();
      expect(calls.map((c) => c.method), ['haptics.play', 'haptics.cancel']);
      expect(calls.first.arguments, {'cue': 'reject'});
    },
  );
}
