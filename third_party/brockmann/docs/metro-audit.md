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
The context title uses the secondary label style. Actions use light 24 dp heading typography in rows at least 64 dp tall, with a shared 24 dp text inset. This keeps the menu readable without treating every row and the context label as equal headings. Options wrap when needed and retain disabled and
destructive states. Sheets scroll and respect system insets.

This bottom-sheet presentation and the hold-and-drag choice shortcut are explicit
Brockmann adaptations requested for mobile, not literal requirements of the 2010
guide. Prefer a few clear actions. Use simple icons when they help recognition;
words remain the main way to understand menu options.
