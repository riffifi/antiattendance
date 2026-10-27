# Building application interfaces

All controls are controlled: keep values in your owning state and update them in callbacks. Text controllers and domain data belong to the application. Null callbacks disable input. The library supplies presentation and interaction; it does not implement account systems, networking, file permissions or application storage.

## Choosing the right input

| Need | API | Guidance |
| --- | --- | --- |
| Boolean / mixed selection | `BrockmannCheckbox` | Enable `tristate` only for a meaningful mixed state. The label toggles too. |
| Immediate on/off | `BrockmannSwitch` | For settings that apply immediately. |
| Mutually exclusive list | `BrockmannRadioGroup<T>` | Keep short choices visible and name each using `labelFor`. |
| Few related modes | `BrockmannSegmentedControl<T>` | Wraps at small widths rather than hiding modes. |
| Long selection | `BrockmannPicker` | `fullPage` for focus; `anchored` to retain context; `adaptive` to choose by width. |
| Single number | `BrockmannSlider`, `BrockmannKnob` | Slider for general input, dial for spatial/audio parameter interfaces. |
| Numeric interval | `BrockmannRangeSlider` | Uses `RangeValues`, optional `min`, `max` and `divisions`. |
| Exact small counts | `BrockmannStepper` | Set a sensible `min`, `max` and positive `step`. |
| Calendar / time | `showBrockmannDatePicker`, `showBrockmannTimePicker` | Returns null on cancellation. Custom calendar and numeral-wheel dialogs keep a draft until confirmation. Calendar headers and date names use the active locale; the time editor uses explicit 24-hour numerals. |
| Curated colour | `BrockmannColorPicker` | `brockmannPalette()` is the new default data set; custom named schemes are supported. |
| Arbitrary colour | `BrockmannColorField` | HSV plane with labelled sliders; enable `showAlpha` only when transparency is useful. |
| Search | `BrockmannSearchField` | Large query text, a search glyph and an accessible × clear button. Supply a controller. Clear emits an empty query through `onChanged`. Filtering belongs to the caller. |

Dial arc dragging tracks relative angular movement without wrap jumps. Tapping the arc sets the corresponding value. Dragging the centre vertically changes the value gently. External updates animate; direct touch updates immediately. Continuous controls stay silent.

## Menus and secondary actions

Use `BrockmannMenuEntry<T>` to define typed actions once:

```dart
const actions = [
  BrockmannMenuEntry(value: 'copy', label: 'Copy', icon: BrockmannIcon.copy),
  BrockmannMenuEntry(value: 'delete', label: 'Delete',
    icon: BrockmannIcon.trash, destructive: true),
];
```

`BrockmannContextMenu<T>` wraps a child and opens on hold or secondary click; it delivers the selected value through `onSelected`. Its child should offer a visible alternate action for users who cannot discover long press. `showBrockmannContextMenu` retains its global `position` argument for compatibility; all context actions now open the bottom action sheet. Disabled entries never return a result.

`showBrockmannActionSheet(context, title: ..., entries: actions)` presents actions in the same bottom sheet with a quiet context label, light 24 dp action text, rows at least 64 dp tall, wrapping and safe-area protection. Both menu helpers return null on cancellation. A supplied entry icon is rendered beside its visible label; entries without icons stay text-only. Use familiar, simple command symbols deliberately, without inventing a pictogram for every row. `showIcons: false` provides a wholly textual presentation. Marking an action destructive only changes its presentation; your application performs the action and decides whether confirmation is necessary.

## Composition

`BrockmannChip` represents a tag or filter, with an optional separate × remove target and a specific spoken label. The owner must remove the item from its collection inside `onDeleted`; the showcase demonstrates actual removal. `BrockmannBadge` is noninteractive status text. `BrockmannBanner` combines a title and persistent explanation, with an optional icon, optionally dismissible. Banners and empty states omit icons unless a caller explicitly supplies one. `BrockmannEmptyState` provides a title, message and optional icon/action.

`BrockmannAccordion` is controlled by `expanded` and `onChanged`; its content animates height while hidden content leaves hit testing and accessibility. Keep critical actions outside collapsed content.

The primary navigation pattern is the typographic pivot. The optional compatibility widget `BrockmannNavigationBar` takes `BrockmannDestination(label, icon)` values and a controlled index. It is no longer demonstrated or recommended as the default bottom-navigation treatment. Use `BrockmannPivot` for the large typographic screen switcher. Neither widget creates domain routes on its own.

## Typography and basic iconography

Typography establishes hierarchy and names actions. Familiar glyphs provide useful shorthand: +/− for numeric adjustment, × for close/clear/remove, horizontal or vertical dots for overflow, arrows for navigation, carets for disclosure, a magnifier for search, and checks for selection. These belong in core controls; they are not exceptions that have to be requested individually. Keep confirmation choices and menu labels written when the meaning benefits from words.

This follows [Microsoft’s icon guidance](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/icons): prefer recognizable meanings and shapes that remain legible at small sizes and harmonize with typography. The [command-bar guidance](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/command-bar) informs the discoverable overflow affordance. These principles inform Brockmann’s Metro-inspired design; the library retains its own Geist typography and Phosphor assets.

Phosphor provides 45 icons in regular and bold weights. Use `BrockmannGlyph` for noninteractive symbols and `BrockmannIconButton` for compact actions. Every icon-only control needs an accessible label and tooltip, a 48 dp touch target, visible focus and a disabled state. More detailed imagery remains an application choice, not automatic row decoration. Assets retain the [Phosphor MIT license](https://github.com/phosphor-icons/core).

`BrockmannOverflowMenu<T>(entries: ..., onSelected: ...)` opens typed menu actions from horizontal dots; set `vertical: true` for vertical dots. Both orientations preserve written menu labels and keyboard activation. This is a visible alternative to a long-press-only context menu.

## Direct manipulation and handle feedback

`BrockmannInteractionRegion` gives a custom direct-input surface priority over `BrockmannPageSwitcher`. A pointer beginning in that region is excluded from page navigation before the page recognizer enters the gesture arena. Region-local drag thresholds are small so a surrounding scrolling list does not capture an intentional colour or dial drag. Page whitespace remains swipeable. Wrap custom pads, editors and other continuous surfaces in the same widget.

Built-in colour planes, dials, sliders, range sliders and time wheels already use the region. Disabled controls do not claim gestures.

Slider handles visibly expand and take the accent on touch, then ease back on release; range handles use matching activation feedback. Slider and range handles emit one tactile pickup after a 160 ms hold, or when dragging starts first. The same gesture never repeats an impact and emits no sound. Feedback uses the shared controller's native drag-start cue and respects haptic mute, lifecycle and Android settings. Supplying `BrockmannApp(feedback: controller)` enables this independently of audio.

## Custom calendar and time editor

Use `BrockmannCalendar(value: ..., firstDate: ..., lastDate: ..., onChanged: ...)` inline. The month heading, year selection, weekday headers and date cells establish the hierarchy; simple carets navigate months. Out-of-range days are disabled, leap days are represented by actual calendar dates, and the selected day has a clear inverse fill. `showBrockmannDatePicker` wraps this in an edge-to-edge band with use date and cancel actions.

`BrockmannTimePicker(value: ..., onChanged: ...)` is an inline 24-hour editor with hour and minute numeral wheels, selection rules and TalkBack increment/decrement actions. Wheel dimensions adapt to text scaling. `showBrockmannTimePicker` keeps wheel changes as a draft until use time is pressed. Neither helper delegates its UI to Material's calendar or clock dialog.

## Android integration

The full-screen choice is a page route using Flutter’s [predictive-back transition](https://docs.flutter.dev/platform-integration/android/predictive-back). Anchored choices retain the selected-row reveal/text handoff. Use `PopScope` for an ahead-of-time pop decision; cancellation must leave selection unchanged.

The showcase includes separate adaptive icon foreground/background layers and Android 13+ monochrome support, following [Android’s adaptive icon model](https://developer.android.com/develop/ui/views/launch/icon_design_adaptive). These assets brand the showcase; applications supply their own launcher identity.

Boundary stretch uses the actual scroll axis and direction, so top/bottom and left/right remain consistent for reversed lists. Retain the application scroll behavior when constructing custom scroll views. Use a live meter for signal levels and `BrockmannProgress` for work progress; a vertical meter stays 4 dp wide even inside a stretched layout.

Anchored pickers share the same renderer and reveal/closing label animations for tapping and holding. They support hold-and-drag selection, edge auto-scrolling, release-to-commit and outside/Back cancellation. Date selections and settled time-wheel changes emit restrained haptic-only detents. See [Metro guidance](metro-audit.md).

## Reorder variants

`BrockmannTile(size: BrockmannTileSize.small | medium | large, ...)` provides
88, 128 and 192 dp minimum heights. Tiles grow for text; `height` remains an
explicit override. The showcase’s Tiles screen combines these with vertical
lists and horizontal strips, preserving the same item order when switching.

`BrockmannReorderableList(axis: Axis.horizontal, spacing: 12, ...)` uses the same
250 ms hold, flat proxy, moving neighbours and automatic edge scroll as a
vertical list. Give horizontal lists a bounded height and children explicit
widths, allowing enough room for scaled text. List spacing defaults to zero for
compatibility; use `spacing` instead of padding the tile’s painted content.

The animated drag outline follows the tile surface, excluding list gaps and
outer margins. `BrockmannTile` includes this automatically. For custom content,
wrap only its painted surface with `BrockmannReorderableItem`, inside any outer
padding. Pickup and release each emit one native haptic; intermediate movement
stays quiet. TalkBack’s Move earlier/later commits emit one landing tick.
Haptic mute and system preferences apply, independently of sound.

Full-page picker motion uses a coordinated 200 ms surface fade and 300 ms row
feather with 30 ms stagger, capped at 480 ms for the visible viewport. Closing
takes 260 ms and preserves current row opacity/position before retreating.
Android predictive Back drives the route progress directly and restores it on
cancellation; reduced motion uses a short fade.
