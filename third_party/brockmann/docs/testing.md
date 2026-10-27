# Validation record

Validated on 18 October 2026 with Flutter 3.47.4 / Dart 3.13.3.

## Local checks

- `flutter analyze`: no issues.
- `flutter test` in the library: 57 passing tests.
- `flutter test` in the showcase: eleven passing tests. Each catalogue page is sampled through intermediate animation frames at 320 and 412 dp, text scale 1 and 2, in both themes. Separate checks verify that editing survives navigation and that tag removal updates the showcase state.
- Android arm64 profile APK builds successfully with the native SoundPool and Activity-aware haptic plugin.

The library checks cover contrast, two-way toggle/drag input, motion interruption, retained navigation, anchored text carry and keyboard focus, explicit phone dropdown presentation, predictive-back cancellation and completion, palette/HSV selection, dial arc and centre input, slider thumb capture, fixed vertical meter width, nested gesture ownership, single/muted handle-hold haptics, custom date bounds/leap days/cancellation, time-wheel drafts, typography-led action surfaces with familiar glyphs and accessible labels, both overflow orientations, narrow/large-text input layouts, both weights of all 45 icons, typed context-menu results/disabled entries, horizontal/vertical edge feedback, reorder, audio/haptic admission and lifecycle cancellation.

The current update adds continuous hold/drag/release and cancellation checks for anchored choices, plus haptic-only detent admission and large bottom-sheet context actions. Six reorder tests cover both axes at every tile size, outline bounds excluding outer padding, gesture ownership, and one pickup/release pulse each. Accessible moves are checked for commit and muted haptics. The showcase additionally samples all six variants at 320 dp and double text scale. A parity test compares tapped/held panel bounds, row text geometry and typography, samples the expanding reveal, and verifies the closing label moves to the field. Full-page motion checks sample the gradual reveal, preserve opacity and position through early dismissal, and verify that deep selections enter without an initial blank delay. Predictive Back also checks visual progress. Context-sheet checks cover the quiet title, lighter actions and full-width band.

## Physical Pixel 7

Connected device: Pixel 7, Android 17 / API 37. Profile-mode integration visits all eleven pages, samples the animation frame by frame, drags the colour plane and hue slider without changing pages, drags a dial, reorders tiles vertically and horizontally without changing pages, selects from tapped and held anchored choices and full-page dropdowns, opens the revised action sheet, confirms custom calendar/time-wheel choices, preloads native sound without playing audio, and requests a short confirmation haptic. The run passed. Android accepted the haptic request; the exact physical feel remains a user/device judgment.

Recorded profile sample (the full catalogue plus colour, dial and dropdown interactions, including vertical/horizontal reorder interaction, coordinated full-page picker motion, shared anchored picker rendering and refined action-sheet typography):

| Measurement | Result |
| --- | --- |
| Frames collected | 635 |
| Build duration, p95 | 17.527 ms |
| Raster duration, p95 | 16.976 ms |
| Native sound bank | Ready |
| Haptic request accepted | True |

The first five frames are omitted from percentile calculations. This is one end-to-end sample with cold pages, SVGs, gradients, popup construction and the phone’s normal background workload, not a controlled sustained-refresh benchmark. Build and raster p95 exceed the 16.67 ms budget of a 60 Hz display in this sample; these results do not establish smooth rendering at every refresh rate. Predictive-back cancel/commit is additionally exercised through Flutter’s back-gesture channel in widget tests. The profile integration validates route selection and on-device touch handling, not every possible physical system-gesture path.

## Reproduce

```sh
flutter analyze
flutter test
cd example
flutter test
flutter drive --profile --driver=test_driver/integration_test.dart \
  --target=integration_test/showcase_test.dart -d <device-id>
```

The driver writes `example/build/previews/pixel-profile-report.json`. Use an unlocked phone with the app in the foreground when checking haptics; a locked/background view intentionally declines tactile feedback. Do not change Android's haptic settings to force a passing result.

The normal interactive APK is `example/build/app/outputs/flutter-apk/app-profile.apk`. It is a development-signed profile build; the integration driver temporarily builds a different entry point, so rebuild the normal application before distributing that path to a reviewer.
