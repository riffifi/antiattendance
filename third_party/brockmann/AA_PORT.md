Based on Brockmann Flutter commit 6ba8cd1, with AA-local integration and WP8 refinements (0.3.4).

The framework includes rich button content, compact selection controls, native text input options, arbitrary dialog content, localized calendar actions, and descendant semantics. These APIs now live in the source framework as well as this vendored copy.

The app preserves its application ID, secure storage keys, Android method channels, NFC lifecycle, QR protocols, server APIs, account and schedule state, localization, and light/dark/AMOLED preferences. Optional library sound remains disabled. The adaptive pivot/list frame preserves screen identities and the hidden developer entry. AA feature views are described in ../../docs/frontend.md.

To update, copy lib/, test/, docs/, assets/, android/, pubspec.yaml and LICENSE from the validated framework checkout; run app and framework checks before committing.

The 0.2 frame revision adds a persistent pivot viewport, explicit navigation
heading reuse, a custom title widget, leading-axis pivot alignment and protected
input gestures. The source framework and this copy share the same implementation
and regression checks. See docs/metro-audit.md for original Metro references and
Android-specific adaptations.

The 0.3 revision coordinates title and content gestures through one fractional
page position, uses the shared turnstile/feather motion for ordinary page routes,
and retains cancellable Android predictive Back. Inset dialogs, anchored short
choice lists, and context-labelled command bands share the same presentation
primitives. AA's schedule and settings use the revised spacing and hierarchy.

AA selects the optional WP8 profile in 0.3.1: outlined square controls, readable
light text fields, full-width message bands and faster pivot/route transitions.
Geist remains the interface typeface.

The 0.3.2 revision adds the shared three-state phone application bar with its
ellipsis handle, continuous vertical dragging, cancellation and Back-to-collapse.
The WP8 pivot margin now aligns with the page’s reading column.

The AA 3.8.0 audit carries the local WP8 refinements as 0.3.3, with centered app
commands reserving a separate corner ellipsis target. The vendored dependency is
the authoritative framework version for this app build; no upstream publication
or external framework checkout update is implied.

The 0.3.4 revision uses typographic WP8 section tabs, lifts the application-bar
ellipsis, and paints the system navigation inset with the bar surface. Hidden
tab bars release their Back guard and return in the compact state.
