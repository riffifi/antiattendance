Vendored from Brockmann Flutter, including adaptive layout commit 80c4908 and the shared app-integration extensions developed with Antiattendance.

The framework includes rich button content, compact selection controls, native text input options, arbitrary dialog content, localized calendar actions, and descendant semantics. These APIs now live in the source framework as well as this vendored copy.

The app preserves its application ID, secure storage keys, Android method channels, NFC lifecycle, QR protocols, server APIs, account and schedule state, localization, and light/dark/AMOLED preferences. Optional library sound remains disabled. The selector and rail retain their app-specific navigation and hidden developer entry.

To update, copy lib/, test/, docs/, assets/, android/, pubspec.yaml and LICENSE from the validated framework checkout; run app and framework checks before committing.
