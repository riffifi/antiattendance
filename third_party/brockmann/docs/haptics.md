# Haptic feedback

Mobile feedback can be felt as well as seen or heard. Brockmann routes the same semantic events to independent sound and haptic backends, so a muted interface still has tactile feedback.

## Use it

Own one controller and dispose it with your application:

```dart
final feedback = BrockmannFeedbackController();

await feedback.configure(
  mode: BrockmannSoundMode.off,
  haptics: BrockmannHapticMode.essential,
);

// Pass feedback to BrockmannApp(feedback: feedback).
// Emit outcomes when the application knows the result:
feedback.play(BrockmannSound.confirm);
feedback.play(BrockmannSound.reject);
```

`BrockmannSoundController` remains a compatibility alias. The cue enum retains its original name for source compatibility; it describes semantic events shared by both channels.

Haptic modes are Off, Essential and Subtle. Essential is the default and includes committed switch changes, explicit outcomes, and reorder pickup/landing. Subtle also includes deliberate selection, primary activation, and layer changes. Sound remains off by default. The showcase persists both preferences independently.

## Vocabulary

| Event | Tactile response |
| --- | --- |
| Selection | Android segment tick (clock tick fallback) |
| Toggle on/off | Android toggle-on / toggle-off effects, with older-device fallbacks |
| Primary activation | Context click |
| Open/close | Gesture start/end where supported |
| Confirm | Two device-tuned ticks, 60 ms apart |
| Reject | Three device-tuned ticks at 0, 70 and 140 ms |
| Reorder pickup | Drag-start effect, long-press fallback |
| Reorder landing | One tick |

The double/triple rhythms are authored design choices. They are deliberately short; users should not need to learn a long vibration code. Always show the outcome visually. Explanatory error text remains essential even when a rejection rhythm is enabled.

Continuous drags, slider updates, scrolling, typing and hover produce no Brockmann haptics. Reordering gives feedback once on pickup and once on landing, never at each pixel or neighbour swap. Native text editing can still produce platform accessibility/editing feedback under Android's settings.

## Android behavior

The native plugin implements `ActivityAware` and uses the attached window's `View.performHapticFeedback`. This uses device-tuned effects and needs no VIBRATE permission. It does not use flags that ignore system settings. Muting, backgrounding, detaching the Activity, or a new cue invalidates remaining rhythm pulses. Every pulse checks that the same view remains attached and focused.

Android's system touch-feedback preference and hardware decide whether a pulse is produced. Do not override those settings or add a forced fallback vibration when the view declines feedback. Exact feel varies across phones; the Pixel's tactile response is not a guarantee for every Android motor.

Sound and tactile admission are independent: haptics do not wait for sound asset preparation, and audio becoming ready never replays an old tactile event. Concurrent events coalesce by meaning; short repeat guards prevent accidental chatter. A higher-priority outcome can bypass the ordinary interval. Reduced motion does not silently mute tactile feedback; it has its own setting.

Inject a `BrockmannHapticBackend` in tests. Extend the abstract backend to inherit the optional gesture hook, implement `play` and `cancel`, and verify event admission/cancellation without vibrating a phone.

## Sources

Android recommends semantic view feedback for ordinary interactions, honoring user settings without requesting vibration permissions: [Haptics API reference](https://developer.android.com/develop/ui/views/haptics/haptics-apis), [Add haptic feedback to events](https://developer.android.com/develop/ui/views/haptics/haptic-feedback). The broader principles favor clear, consistent tactile effects over indiscriminate buzzing: [Android haptics UX foundation](https://source.android.com/docs/core/interaction/haptics/haptics-ux-foundation).

## Handle pickup

Interactive sliders and range handles use a single drag-start impact. Hold a handle for 160 ms or begin dragging it to receive the pickup response once; moving it further does not produce additional ticks. Plain track taps are not impacts. This uses the same OS-respecting feedback controller as reorder pickup, with no audio and no vibration permission. Set haptics off to suppress it.
