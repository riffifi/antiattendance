Vendored from Brockmann Flutter at commit 5f29000 (0.2.0), including the shared app-integration controls and revised Metro application frame.

The framework includes rich button content, compact selection controls, native text input options, arbitrary dialog content, localized calendar actions, and descendant semantics. These APIs now live in the source framework as well as this vendored copy.

The app preserves its application ID, secure storage keys, Android method channels, NFC lifecycle, QR protocols, server APIs, account and schedule state, localization, and light/dark/AMOLED preferences. Optional library sound remains disabled. The adaptive pivot/list frame preserves screen identities and the hidden developer entry. AA feature views are described in ../../docs/frontend.md.

To update, copy lib/, test/, docs/, assets/, android/, pubspec.yaml and LICENSE from the validated framework checkout; run app and framework checks before committing.

The 0.2 frame revision adds a persistent pivot viewport, explicit navigation
heading reuse, a custom title widget, leading-axis pivot alignment and protected
input gestures. The source framework and this copy share the same implementation
and regression checks. See docs/metro-audit.md for original Metro references and
Android-specific adaptations.
