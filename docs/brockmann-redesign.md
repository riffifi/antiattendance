# Brockmann redesign

Branch: `redesign-bm`. The existing local migration is retained and merged with
upstream `main` through `7d4c565`, including AA ID and sensitive-session changes.
The vendored framework incorporates `polish-adaptive-layout` (`80c4908`) plus
shared integration APIs and retained editing across adaptive breakpoints.

The app uses Brockmann typography, themes, press/motion foundation, buttons,
text fields, selection controls, progress, pickers, dialogs, menus and toasts.
App adapters preserve rich localized content and independent row actions.
The AA ID sign-in and device-management screens also use this system.

Functionality remains in the application: attendance and QR queue, account and
session recovery/import/sharing, schedule and group selection, NFC passes and
widgets, indoor maps/navigation, updates, settings, and developer diagnostics.
App-specific selector/rail navigation retains screen state and NFC shutdown.
Light, dark and AMOLED choices remain available; sound stays opt-in.

Validation on 28 October 2026 with Flutter 3.47.4 / Dart 3.13.3:

- App analysis: no issues.
- App regression suite: 252 passing tests.
- Framework suite: 67 passing tests plus 3 integration-API tests.
- Showcase suite: 11 passing tests, including 320/412 dp, double text,
  both themes, navigation/edit retention and reorder layouts.

- `flutter build apk --release`: passed (81.4 MB universal APK).
- Pixel 7 (`2A101FDH20054Y`): `adb install -r` succeeded on 28 October;
  application ID `com.example.antiattendance`, version `3.5.1+39`.
  Installed app storage was preserved. Launch rendered the MIREA QR sign-in
  screen; completing university sign-in was left to the user.
Live university sign-in, attendance submission, NFC reader transactions and
server authorization require their real services and credentials; widget tests
verify their UI and logic without performing real attendance submissions.
