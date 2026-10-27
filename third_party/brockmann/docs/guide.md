# Usage guide

## Application and theme

Install `BrockmannApp` at the root, or add `BrockmannThemeData` to your own `ThemeData.extensions`. Read tokens with `context.brockmann`. `BrockmannPage` handles safe areas, keyboard resizing, and a scrolling body. Put persistent navigation in its `header`; use `scroll: false` when the child owns its scrolling viewport.

The showcase stores theme, accent, reduce-motion and sound preferences through `BrockmannPreferences`. This optional Android adapter stores simple primitive values in private application preferences. Application domain data belongs in your own storage.

Set `brightness`, `accent`, and optionally `reduceMotion`. The platform's animation accessibility setting is respected even when your own setting is false. `motionScale` is a study/debug setting, not an animation speed control to expose in every application.

## Controls

Update controlled values in `onChanged`. Disable with a null callback. Buttons separate primary, secondary and text styles. Use one primary action in a decision group. Text fields retain Flutter's IME, selection, clipboard and obscured entry behavior; supply either a controller or an initial value.

Sliders accept `min`, `max`, `step`, `defaultValue`, and `formatValue`. Keep labels above values; format units explicitly. Direct dragging follows the finger immediately; external slider changes animate over 240 ms. Double-tap restores `defaultValue`. Knobs support tapping the arc to set a value, dragging around the arc to rotate, and dragging the centre vertically for fine control (140 dp for the full range). Shift reduces sensitivity on hardware keyboards. TalkBack exposes increment and decrement. Slider handles keep the grab offset, so picking up a handle does not jump the value. Prefer sliders when precision and discoverability matter on phones.

A switch animates both directions over 180 ms, with the desktop’s inset thumb geometry, retargeting from the current visual state if interrupted. Its value commits immediately; do not delay application state until the animation ends. Tapping a label operates the switch. Scrolling past it must not toggle it.

## Navigation and dropdowns

`BrockmannPivot` keeps all options in the layout. It scrolls only when needed and reveals the selected item with minimal movement; earlier destinations remain available by touch. Compact mode is appropriate for a catalogue with many destinations. Use short, distinct names. The title pivot reserves 12 dp at the beginning and end of its strip. A horizontal swipe selects one neighbouring destination on release instead of manually scrolling the title list; compact tabs retain direct scrolling.

Page swipes map finger displacement directly to turnstile angle and opacity. On release, complete the remaining turn and introduce the next page with the staggered feather; cancelled gestures return to rest. Child sliders retain their own horizontal gestures. Rapid changes by tapping preserve each outgoing page’s current position and give it the full 250 ms turnstile exit. Outgoing pages stop receiving input and accessibility focus; incoming content retains its staggered entry. Use stable page identities and let `BrockmannPageSwitcher` own the transition.

`BrockmannPicker` opens a full selection page on phones, with the current item visible. Android Back or the visible close action cancels. A tap commits once; full-page routes use Flutter’s Android predictive-back transition. Cancelling predictive back restores the open list without committing a value. On wider screens the bordered list is anchored around the selected row and clamped to the safe viewport. Enlarged text switches back to the full-page presentation. Set `presentation: BrockmannPickerPresentation.anchored` to use the selected-row desktop-style list on a phone, or `.fullPage` to always use a selection page. `.adaptive` chooses based on available space. Closed controls have 16 dp of internal inset, separating the hover/press outline, label and value. The wide list reveals over 220 ms and closes over 200 ms, carrying a single selected label into its live field position even when the new value wraps. Early cancellation closes from the current geometry. Arrow keys, Home and End move the candidate with a 140 ms outline glide; Enter or Space commits, and Escape cancels. Candidate navigation never changes the model until commitment.

Dialog, menu and command surfaces extend edge to edge as flat bands; their content stays inset and is limited to 560 dp for readability. Horizontal system cutouts inset content without shrinking the surface. Dialog, menu and command helpers return the chosen string, or null on cancellation. Act on the returned result after checking `context.mounted`. Use confirmations only when they help the user make a real decision. Toasts are brief status messages; meaningful failures also need persistent visible text.

## Colour input

`BrockmannColorPicker` is a curated tile palette. It expands the selected tile over 180 ms and adds a contrast-safe check mark, a name and a hex readout. `grid` wraps to the available width; `swatches` scrolls in either axis. The old `ribbon` enum value remains an API alias for the scrolling tile strip; the Windows visual treatment has been removed.

```dart
BrockmannColorPicker(
  label: 'Project colour',
  schemes: brockmannPalette(),
  selected: selected,
  onChanged: (index) => setState(() => selected = index),
)
BrockmannColorField(
  label: 'Compose a colour',
  value: colour,
  showAlpha: true,
  onChanged: (value) => setState(() => colour = value),
)
```

The colour field combines a saturation/brightness plane, a hue spectrum, and labelled saturation, brightness and optional opacity sliders. The sliders provide accessible alternatives to the two-dimensional plane. Continuous input is immediate and silent; external plane marker changes animate over 180 ms. Palette companions belong to the selected colour and appear as separate samples; they never recolour the UI automatically. `windows8Palette()` remains available as legacy data only. Use `brockmannPalette()` or supply application-specific named schemes for new interfaces.

## Tiles and reordering

Use flexible wraps or lists, allowing a tile to grow with its label and the user's text scale. A label and value occupy separate lines. Avoid fixed row heights that can overlap type.

`BrockmannReorderableList` owns its scroll viewport. Give every child a stable identity key. Hold for 250 ms to drag; neighbours animate into the opening. The proxy stays flat, without tilt or a shadow. TalkBack exposes Move earlier and Move later.

```dart
onReorder: (oldIndex, newIndex) {
  setState(() => items.insert(newIndex, items.removeAt(oldIndex)));
}
```

`newIndex` is already adjusted for removal by Flutter 3.47's `onReorderItem` API. Do not decrement it a second time. For longer lists, leave `shrinkWrap` false and place the list in an `Expanded` viewport rather than nesting it inside another scrolling list.

## Optional sound

Create one `BrockmannSoundController` for the application and dispose it with the owner. Pass it to `BrockmannApp(feedback: controller)`. Sound starts off. Explicitly enable `essential` or `subtle` with `configure`. Store the user's preference in your application. Default volume is 0.35.

Essential allows switches and confirm/reject outcomes; Subtle also allows selection, opening, closing, and primary activation. Continuous input, hover, focus, dragging and scrolling stay silent. Emit confirm/reject when an operation actually succeeds/fails, not when a button is pressed. `controller.play(BrockmannSound.confirm)` is the explicit outcome API.

Native Android uses a preloaded SoundPool, drops unavailable cues, and stops/releases on background or mute. Nothing waits to play later. A failed backend leaves the interface fully usable. To test without audio, inject a `BrockmannSoundBackend`. Do not create a controller per widget or request audio focus for UI clicks.

## Haptic feedback

Use `BrockmannFeedbackController` for independent audio and touch preferences. Essential haptics are enabled by default and defer to Android's system setting. Configure `haptics: BrockmannHapticMode.off` to disable them. Confirm is a short double tick; reject is a triple tick. Reorder pickup/landing use one native gesture effect each. Sound can stay off. See [haptic integration and guidelines](haptics.md).

## Additional controls and Android behavior

See [components](components.md) for selection controls, range input, search, bottom navigation, calendar/time dialogs, context menus and action sheets. Every component stores application state in its owner; disabled callbacks remain null. Range input uses Flutter’s touch mechanics with square handles. Date and time helpers use the custom `BrockmannCalendar` and `BrockmannTimePicker`, with clear typographic hierarchy, caret month navigation and written confirmation actions.

`BrockmannScrollBehavior` uses directional stretch feedback at scroll boundaries for vertical and horizontal viewports. It follows the scroll direction, including reversed lists. `BrockmannApp` installs Android predictive-back transitions, and full-page dropdowns are real page routes. Keep `android:enableOnBackInvokedCallback="true"` in the host application. Use `PopScope(canPop: ...)` when an application needs to protect unsaved work; do not introduce `WillPopScope`.

The showcase has adaptive foreground/background launcher layers and a monochrome layer for Android’s themed icons. A host app supplies its own identity assets and launcher preference.

## Gesture ownership and typography

Colour planes, dials, sliders and range handles own pointers that start inside their direct-input surface. Page swipes are rejected for those pointers rather than competing after a drag begins. The time wheels follow the same rule. Wrap custom direct-input widgets in `BrockmannInteractionRegion` to get the same behavior.

Handle pickup has one native haptic after a 160 ms hold or initial drag, provided a feedback controller is installed and haptics are allowed. There are no repeated drag ticks or sounds.

Search presents the query with a magnifier and × clear button. Sheets and context menus keep visible action labels and render icons when explicitly supplied by their entries. Basic core symbols (+/−, ×, dots, arrows and carets) are used where they improve recognition. Chips offer an accessible × remove action; the application removes the item from state. The showcase’s Inputs page uses typographic hierarchy and no bottom icon navbar.


Slider handles also expand and take the accent while held, easing back on release.
Anchored choices support holding the field and dragging through the list without
lifting: release inside to choose, outside to cancel. Hold near an edge to scroll.
Date changes and settled time-wheel changes provide haptic-only detents.
Context actions consistently open the large typographic bottom sheet.
See [Metro interaction guidance](metro-audit.md) for sources and design decisions.

The Tiles showcase offers all six combinations of vertical/horizontal and
small/medium/large. Choose `BrockmannTileSize` for density, then constrain a
horizontal viewport’s height and tile widths for the current text scale.
Keep margins outside `BrockmannReorderableItem`; it marks the painted tile rather
than the reorder slot. `BrockmannTile` already includes that surface. Use the
list’s `spacing` property for gaps. Direct reorder regions own their pointers,
so horizontal drags cannot switch screens.
