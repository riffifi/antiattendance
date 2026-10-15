# Typography redesign · Swiss / Windows Phone direction

The main screen is four equal full-height columns, with bottom-to-top labels
separated by thin gray rules. Selecting one moves and narrows that column into
the left navigator while the destination fades and slides into place. INDEX,
tapping the rail label, or system Back reverses the transition.

The navigator shows the current destination only. Vertical dragging follows the
finger, then snaps to the adjacent page in either direction. Each crossed destination
produces one selection haptic; a boundary gives one light pulse per gesture. Arrow keys, a mouse wheel, and
accessibility increase/decrease actions also navigate. Page scrolling stays
inside the content area. Reduced-motion settings skip the transitions.

Attendance, Schedule, Passes, and Settings share the same shell. Leaving Passes
stops the NFC session. Returning from Settings reloads account preferences.
Notification and launcher-widget entry points still open their target screen.

Screen content follows rail movement with a small, viewport-adaptive translation,
scale, and fade. A spring snaps the rail, then the destination enters from the
matching direction. Screens commit only after settling, so a cancelled swipe
does not open a screen or interrupt NFC. Opening/closing durations shorten when
a transition is interrupted. Reduced motion removes travel, scaling, and fades.

Content and rail layers retain their identities and controllers. Repaint
boundaries isolate content while the transforms animate. Attendance and visited
Settings retain state behind the index; returning from Settings refreshes account
data in place instead of tearing down the content for a loading indicator. NFC
is still stopped and disposed when leaving its screen.

Controls react visually on pointer-down. Completed normal actions and selection
changes tick; navigation taps give light feedback; primary actions give a medium
pulse. Cancelled presses and disabled controls do not vibrate. Unsupported
platform feedback cannot interrupt an action.


Geist Light headings, Geist Mono details, ruled lists, custom square controls,
baseline text fields, and monochrome menus carry the design through primary and
supporting flows. Light, dark, and black appearances remain available. Monet,
the Android wallpaper-color channel, and the Material 3 Expressive dependency
have been removed. Flutter's existing Material infrastructure remains for
routing, localization, text editing, native back handling, and themed dialogs.

Decorative icons are removed throughout the app. Actions read as words, including
back, actions, paste, maps, refresh, search, and zoom. Page headings lead the
layout; their action rows sit beneath them. The schedule date range and its
previous/date/next controls use separate rows so translated labels and enlarged
text fit. The rail retains vertical snapping and haptics. Selection uses a small
typographic mark with explicit accessibility state; scan success and failure
use text instead of pictograms. QR codes and floor plans remain functional data.

The content pane reserves system status/navigation insets. Scan and NFC actions
remain above the system navigation area. Dialogs and sheets retain native back
handling and keyboard insets.

## Previews

[Light selector](previews/selector-light.png) · [Dark selector](previews/selector-dark.png)

[Light attendance](previews/attendance-light.png) · [Dark attendance](previews/attendance-dark.png)

[Schedule](previews/schedule-light.png) · [Passes](previews/passes-light.png) · [Settings](previews/settings-light.png)

Regenerate all previews with:

```sh
TYPOGRAPHY_PREVIEW_DIR=docs/previews flutter test test/screen_selector_test.dart --plain-name 'export typography previews'
```

## Backups

- Original Git branch: `backup/before-typography-20261015-132554` (commit `5e7bb6f`).
- Original full archive: `/home/leo/dev/flutter/.backups/antiattendance-before-typography-20261015-132554.tar.gz`.
- Snapshot before the type-only refinement: `/home/leo/dev/flutter/.backups/antiattendance-before-type-only-20261015.tar.gz`.
- Snapshot before this expanded redesign: `/home/leo/dev/flutter/.backups/antiattendance-before-full-redesign-20261015.tar.gz`.

The original archive includes Git metadata and the independently versioned server.
The newer snapshot includes app sources and the first redesign. Generated build
and package caches are excluded. SHA-256 files accompany the archives.

## Verification

- `flutter analyze`: no issues.
- `flutter test`: all 234 tests pass.
- Populated schedule on a narrow inset phone with enlarged text: passes.
- Android release APK: `build/app/outputs/flutter-apk/app-release.apk` (81.5 MB).
- Installed successfully on Pixel 7 with `adb install -r`; app launch verified.

Commands: `flutter analyze`, `flutter test`, and `flutter build apk --release`.
The navigation tests cover the morph, bidirectional swipes, haptic counts,
boundaries, content-scroll isolation, system insets, reduced motion, NFC cleanup,
and narrow screens with enlarged text. Selector tests cover all five languages
and portrait/landscape layouts. Physical-device gesture feel remains a manual
check.

The retention regression test verifies that content builds once across opening,
a held drag, cancellation, returning to the index, and an interrupted transition.
Another test holds the Settings account refresh pending and verifies that the
attendance scroll state and visible data remain intact. These are lifecycle and
layout checks; physical-device frame timing has not been profiled.

Selector label visibility is computed on every morph frame, including the exact
return endpoint. Theme changes apply the new palette once and fade out a snapshot
of the previous painted screen over 180 ms, instead of interpolating the entire
theme on every frame. Snapshot resolution is capped at 1.5×, images are released
after use, and reduced motion switches immediately.

The rectangular summary switch has a 56×28 track within a minimum 48-pixel touch
target. Presses use a subtle surface response rather than inverting the hit box.
Its state changes immediately, rolls back on permission denial or setup failure,
and notification synchronization runs without holding the Settings page disabled.
Regression tests cover the return endpoint, switch geometry and feedback,
permission approval/denial, persistence, and theme crossfade rebuild counts.

Device delivery follows `AGENTS.md`: build release and install on the connected
Pixel with `adb install -r`, retaining app data.
