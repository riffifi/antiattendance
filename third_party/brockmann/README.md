# Brockmann for Flutter

An Android-first, touch-first UI library inspired by Swiss typography and Metro. Typography-led actions, flat surfaces, square edges, Geist fonts, one accent colour, and motion that explains a change. Includes a separate eleven-page Android showcase.

## Run the showcase

Requires Flutter 3.47 / Dart 3.13 or newer, Android SDK, and Java 17 or newer compatible with Gradle 9.3. Android minimum API 24.

```sh
cd example
flutter pub get
flutter run -d <android-device-id>
```

Build an installable development APK with `flutter build apk --debug`. The result is `example/build/app/outputs/flutter-apk/app-debug.apk`. Release signing is the application's responsibility; the example uses a development key.

## Use the library

Add a path dependency in your app's `pubspec.yaml`:

```yaml
dependencies:
  brockmann:
    path: ../brockmann
```

```dart
import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

void main() => runApp(const Example());

class Example extends StatefulWidget {
  const Example({super.key});
  @override
  State<Example> createState() => _ExampleState();
}

class _ExampleState extends State<Example> {
  bool enabled = false;
  @override
  Widget build(BuildContext context) => BrockmannApp(
    theme: const BrockmannThemeData(accent: Color(0xff008a83)),
    home: BrockmannPage(
      child: BrockmannSwitch(
        label: 'Enable processing',
        value: enabled,
        onChanged: (value) => setState(() => enabled = value),
      ),
    ),
  );
}
```

Controls are controlled widgets: store their values in your app, and update them from callbacks. A null callback disables a control. Fonts, icons and sound assets resolve from the package automatically. Use `BrockmannThemeData.material` as your app's theme extension if you already own a `MaterialApp`.

## Components

| Purpose | Components |
| --- | --- |
| Application | `BrockmannApp`, `BrockmannPage`, `BrockmannThemeData`, `BrockmannAdaptiveScaffold` |
| Layout | `BrockmannResponsive`, `BrockmannGrid`, `BrockmannColumns`, `BrockmannSplitView`, `BrockmannContent`, `BrockmannStack`, `BrockmannSection`, `BrockmannPageHeader`, `BrockmannButtonBar`, `BrockmannDivider`, `BrockmannGap`, `BrockmannSpace` |
| Typography | `BrockmannText`, `BrockmannType` (14 roles) |
| Input | `BrockmannButton`, `BrockmannSwitch`, `BrockmannSlider`, `BrockmannKnob`, `BrockmannTextField`, `BrockmannSearchField`, `BrockmannRangeSlider`, `BrockmannStepper` |
| Navigation | `BrockmannPivot`, `BrockmannPicker` (full-page or anchored), `BrockmannNavigationBar` |
| Colour | `BrockmannColorPicker`, `BrockmannColorField`, `BrockmannColorScheme`, `brockmannPalette()` |
| Display | `BrockmannTile`, `BrockmannLiveTile`, `BrockmannListItem`, `BrockmannMeter`, `BrockmannProgress`, `BrockmannStat`, `BrockmannPropertyList`, `BrockmannPlaceholder` |
| Overlays | `showBrockmannDialog`, `showBrockmannMenu`, `showBrockmannCommands`, `showBrockmannToast` |
| Selection | `BrockmannCheckbox`, `BrockmannRadioGroup`, `BrockmannSegmentedControl`, `BrockmannChip` |
| Composition | `BrockmannAccordion`, `BrockmannBadge`, `BrockmannBanner`, `BrockmannEmptyState` |
| Pickers and menus | `BrockmannCalendar`, `BrockmannTimePicker`, `showBrockmannDatePicker`, `showBrockmannTimePicker`, `BrockmannContextMenu`, `BrockmannOverflowMenu`, `showBrockmannContextMenu`, `showBrockmannActionSheet` |
| Reordering | `BrockmannReorderableList` |
| Foundation | `BrockmannPressable`, `BrockmannInteractionRegion`, optional `BrockmannIconButton` / `BrockmannGlyph` |
| Optional feedback | `BrockmannFeedbackController`, `BrockmannSoundController`, `BrockmannFeedbackScope`, `AndroidSoundBackend` |

See [the component guide](docs/components.md), [the Rust parity audit](docs/rust-parity.md), [the usage guide](docs/guide.md), [design guidelines](docs/design-guidelines.md), and [sound research and Android implementation](docs/sound-research.md), and [haptic rhythms](docs/haptics.md). The showcase in [example/lib/main.dart](example/lib/main.dart) is a complete integration example.

## Development

```sh
flutter pub get
flutter analyze
flutter test
cd example
flutter test
flutter test integration_test/showcase_test.dart -d <android-device-id>
```

Widgets use standard Flutter rendering and native text editing. Android is the first supported platform; optional sound and preference persistence have an Android implementation. Other platforms can supply their own sound backend and persistence.

MIT licensed. Geist fonts retain their SIL Open Font License; Phosphor icons retain their MIT license in `assets/`. The eight short synthesized cues are original project assets.

### Persistent application navigation (0.2)

`BrockmannAdaptiveScaffold` now uses a single live `BrockmannPivotViewport` for
compact navigation. Keep an `IndexedStack` or another stable state-owning body
inside it; destination changes never render duplicate keyed bodies. Declare
custom drag surfaces and command docks with `BrockmannInteractionRegion`.
`BrockmannTextField` already protects its native editing gestures.

Feature headers can set `reuseNavigationHeading: true` to reuse the compact
pivot title. Wider layouts retain their normal page heading. `titleWidget` accepts
a small application mark in place of the application-name label. See
[the Metro implementation notes](docs/metro-audit.md).

### Coherent gestures and presentations (0.3)

The adaptive frame shares `BrockmannPivotMotion` between its title strip and page.
Both title and content drags track a fractional page position before committing.
`BrockmannPageFrame` supplies the same turnstile pose to pivots and ordinary page
routes. Android predictive Back keeps its own cancellable route progress.

Short choices can use anchored phone flyouts. Dialogs use a bounded inset surface,
and typed context actions have a compact content hierarchy. Applications still
own authentication, persistence, cancellation and service lifecycle callbacks.

Use `BrockmannThemeData(style: BrockmannStyle.wp8)` for the WP8 control and motion
profile. The default style remains available.

`BrockmannCommandBar` supports up to four icon commands, compact / expanded /
minimized presentations, an ellipsis handle, direct vertical gestures,
keyboard and screen-reader actions, cancellation, and Back-to-collapse. Labels
expand to fit large system text. The 48 dp minimized handle is an Android touch
adaptation.
