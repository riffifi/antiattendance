# Metro interaction guidance

Reviewed Microsoft’s *UI Design and Interaction Guide for Windows Phone 7*,
July 2010 version 2.0, across its design philosophy, framework, input, hardware,
controls and writing guidance. The original document is available from this
[archived PDF mirror](https://www.pocketpc.ch/attachments/windows-phone-7-entwicklung/36554d1283328945-windows-phone-7-ui-design-guide-wichtigste-checkliste-ui-design-interaction-guide-windows-phone-7-v2.0.pdf).
This is historical guidance, adapted to Flutter and Android rather than a claim
of Windows Phone certification.

| Guide pages | Brockmann application |
| --- | --- |
| 8–15 | Typography and content establish hierarchy; keep chrome restrained. |
| 16–23 | Historical screen pixels are not Android dp. Allow translated text and text scaling. |
| 26–37 | Keep familiar geometric command icons and readable labels. Overflow actions belong near the bottom. |
| 38–41 | Respect orientation and theme; use typography roles rather than local hard-coded text styles. Geist remains the library typeface. |
| 42–69 | Preserve navigation context, distinguish activity from editable values, and support light/dark contrast. |
| 72–91 | Respond while the finger is down; execute discrete actions on release. Separate visible handles from generous touch targets. |
| 94–133 | Respect keyboard insets, system Back, app lifecycle and vibration preferences. |
| 136–189 | Provide pressed/disabled states; use horizontal sliders for continuous values. Keep pivots for related views. |
| 190–199 | Use concise, human labels and consistent capitalization and punctuation. |

## Handles and pickers

Use `BrockmannSlider` for an editable value and `BrockmannProgress` for activity.
Slider handles expand and take the accent while held, then relax on release.
Values continue following the finger directly; the press animation must not
introduce input lag. Range handles use the same visual language.

Date selection produces a quiet tactile detent when choosing a different day.
Time wheels emit one detent after a user scroll settles on a different value,
not for every intermediate number in a fling. Semantic increments also tick.
These ticks do not play audio, respect haptics-off and pause in the background.
Programmatic updates stay silent.

Anchored choices support both tap-to-open and a shortcut: hold the field, drag
through options, and lift to choose. Hovering near the panel’s upper/lower edge
scrolls long lists. Both tap and hold use the same anchored panel renderer: row measurements, 220 ms reveal, 200 ms closing label carry, surface, text roles and insets. Gesture preview uses its existing animated outline, with no filled accent row or alternate type scale. The model changes only on release inside the panel; releasing
outside, cancelling the pointer, or pressing Back abandons the draft. Full-page
choices retain their normal tap and keyboard interaction.

## Context actions

`showBrockmannContextMenu`, `BrockmannContextMenu`, and `BrockmannOverflowMenu`
all use the existing bottom action sheet. The legacy `position` argument remains
accepted for source compatibility; it no longer positions a floating menu.
The context title uses the secondary label style. Actions use 20 dp content typography in rows at least 56 dp tall, with a shared 24 dp text inset. This keeps the menu readable without treating every row and the context label as equal headings. Options wrap when needed and retain disabled and
destructive states. Sheets scroll and respect system insets.

This bottom-sheet presentation and the hold-and-drag choice shortcut are explicit
Brockmann adaptations requested for mobile, not literal requirements of the 2010
guide. Prefer a few clear actions. Use simple icons when they help recognition;
words remain the main way to understand menu options.

## Application-frame revision

Revisited Microsoft's [Metro design-team explanation](https://blogs.windows.com/windowsdeveloper/2011/02/17/from-transportation-to-pixels/)
and [navigation/application-bar guidance](https://learn.microsoft.com/en-us/archive/msdn-magazine/2011/december/windows-phone-how-to-translate-common-design-principles-to-the-windows-phone).
The revision applies their typographic navigation, content emphasis and meaningful
motion to the Android/Flutter implementation; its dp and type sizes are modern
Brockmann adaptations, not measurements claimed from Windows Phone.

- A compact pivot provides the active page heading. A feature can opt into
  `reuseNavigationHeading` instead of adding a second display heading. Wider
  navigation lists leave the feature's own heading visible.
- `BrockmannPivotViewport` transforms one live child tree. It never duplicates a
  keyed form or platform view to produce an outgoing animation. Swipes select
  one adjacent destination, cancellation restores the current content, and
  reduced motion retains the gesture without spatial movement.
- Direct manipulation regions retain their pointer gestures. Text input uses
  the shared region automatically. App command docks and horizontal calendars
  also declare their gesture ownership.
- Reading text uses 16/24 dp and supporting text 12/16 dp. Page headings, content
  names and metadata keep distinct roles. List text aligns to the page's reading
  axis; field outlines retain internal input padding.
- Primary actions stay in the page's bottom command area. Changing destinations
  dismisses the keyboard; the application continues to own cancellation and NFC
  shutdown rather than waiting for an animation to finish.

Regression checks cover keyed-state retention, interrupted navigation, cancellation,
text selection, reduced motion, resize, and the app's NFC exit path.

## Gesture and presentation coherence (0.3)

`BrockmannPivotMotion` supplies a shared fractional page position to the pivot
and its persistent viewport. Header and content drags scrub that same position;
commit and cancellation settle both surfaces with the same curve. The body uses
`BrockmannPageFrame`, the shared turnstile pose, and feathered row entry. Normal
Material page routes receive the same pose through `BrockmannPageTransitionsBuilder`.
Android predictive Back updates the route's own animation and supports cancellation.

Dialog surfaces have 24 dp safe outer insets and a 560 dp maximum reading width.
Their reveal uses the shared modal transition. Short picker lists can stay anchored
on phones at ordinary text sizes; longer lists and enlarged text retain full-page
selection. A caret and underline identify the closed choice field. Context commands
use a small context label with 20 dp action text, independently of page headings.

Checks hold the pointer before release to verify both title and content movement,
cancel gestures, preserve a keyed form through repeated changes and window resize,
and scrub/cancel/commit predictive Back on an ordinary page route.

## Application bar completion (0.3.2)

The application bar now exposes its ellipsis in every state. Compact mode shows
icons, expanded mode reveals labels, and a downward drag leaves the minimized
strip. Drag progress is continuous; cancellation and Back preserve page state.
The minimized strip keeps a 48 dp accessible handle on Android. The WP8 profile
also aligns pivot headings with the content reading margin.

Primary references:
- [ApplicationBar.Mode, including mini/default resting sizes](https://learn.microsoft.com/en-us/previous-versions/windows/apps/hh312718%28v%3Dvs.105%29)
- [ApplicationBar and its ellipsis expansion](https://learn.microsoft.com/en-us/previous-versions/windows/apps/ff402616%28v%3Dvs.105%29)
- [Windows Phone drawer interaction: tap or drag the ellipsis](https://blogs.windows.com/windowsdeveloper/2014/04/18/winjs-on-windows-phone-8-1/)
