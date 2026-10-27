# Brockmann: Design & Motion Spec

Brockmann is a native Rust UI library (wgpu) for building apps with one consistent design language: the typography and interaction logic of Windows Phone 7/8 Metro, laid out with the discipline of Swiss modernism, set entirely in Geist. First consumers: the procedural drum synth and the code editor.

This document specifies how everything looks, moves and responds. It contains no implementation code. Where a number is given, treat it as the starting value to tune by eye.

---

## 1. Principles

1. **Content is the interface.** No chrome that doesn’t carry information. No shadows, gradients, bevels, glass, icons-as-decoration or ornamental borders.
2. **Typography is the structure.** Hierarchy comes from size, weight and position, not boxes. A label sitting above a value is a complete component.
3. **Flat, rectangular, honest.** Every shape is a rectangle. Corner radius is 0 everywhere. The only curves are in type, knob arcs and the Phosphor icon glyphs.
4. **Grid or nothing.** Every element snaps to the layout grid. Asymmetric, flush-left layouts with generous empty space.
5. **Motion explains.** Animation shows where something came from or went to. It is fast, decisive and never decorative. Nothing bounces, wobbles or overshoots.
6. **Direct manipulation.** Every control responds to press instantly (under one frame of latency), before any animation plays.
7. **No filler text.** No taglines, no “Welcome”, no placeholder copy, no helper text that restates the label. If a string doesn’t help the user act, it doesn’t exist.

---

## 2. Rendering requirements (wgpu)

- Resolution independent. All sizes are in logical pixels, scaled by the display scale factor. Rectangle edges must land on **physical pixel boundaries** (snap after scaling) so strokes stay crisp at 100%, 125%, 150%, 200%.
- Rectangles and strokes: instanced quads in a single pipeline, analytic anti-aliasing (or none, since edges are pixel-snapped). No SDF rounding needed because there are no radii. Arcs (knobs) use an SDF fragment path.
- Text: glyph atlas with **MSDF or high-quality grayscale coverage** rasterization, subpixel positioning on the x axis, no subpixel (LCD) color fringing. Variable-font axes (weight) must be sampleable at runtime so weight can be **animated**.
- Frame pacing: render on demand (damage-driven). Idle app = zero GPU work. During any animation, request frames at display refresh rate. Target 144 Hz cleanly.
- Input latency budget: pointer or key event to visible state change within one frame.
- Color: render in sRGB, blend in linear where text coverage is applied. Hairlines are always exactly 1 physical pixel unless specified.
- A single global “time” source drives all animation, so every transition is deterministic and can be frame-stepped in debug mode.

---

## 3. Design tokens

### 3.1 Color

Two themes, **Dark** (default) and **Light**. Both are strictly achromatic except for the single accent color. No other hues exist in the UI chrome.

| Token | Dark | Light |
| --- | --- | --- |
| `bg` | #000000 | #FFFFFF |
| `surface` (rare, for overlays only) | #121212 | #F2F2F2 |
| `fg` (primary text) | #FFFFFF | #000000 |
| `fg-2` (secondary text, labels) | #A6A6A6 | #5A5A5A |
| `fg-3` (disabled, hints) | #5C5C5C | #A8A8A8 |
| `line` (hairlines, inactive outlines) | #3A3A3A | #BDBDBD |
| `line-strong` (control outlines at rest) | #8A8A8A | #4A4A4A |
| `accent` | #00ABA9 (teal, matches the reference) | same |
| `accent-press` | accent darkened 18% | same |
| `on-accent` | #FFFFFF | #FFFFFF |
| `danger` (only for destructive confirms and clipping/overload) | #E51400 | #E51400 |

Rules:

- The accent is the only color. It marks: on/active state, the current selection, the filled portion of a value, focus. Never use it for decoration or large backgrounds.
- The user can swap the accent (a small set of Metro colors: teal #00ABA9, cobalt #0050EF, lime #A4C400, orange #FA6800, crimson #E51400, magenta #D80073, violet #AA00FF). Everything derives from the single token.
- Contrast: `fg` on `bg` and `on-accent` on `accent` must pass 4.5:1. If a chosen accent fails with white text, switch `on-accent` to black automatically.
- Page background is always flat `bg`. No images, no noise, no vignettes.

### 3.2 Spacing and grid

- **Base unit: 4 px.** All spacing is a multiple of 4. Preferred steps: 4, 8, 12, 16, 24, 32, 48, 64, 96.
- **Layout grid: 12 columns**, gutter 16, outer margin 24 (compact), 48 (regular), 96 (wide). Compact below 720 px, regular 720 to 1280, wide above.
- **Metro tile grid** for dashboards and parameter groups: square cells of 96 px with 8 px gaps (so a 2x2 block is 200 px). Items snap to this grid; sizes are 1x1, 2x1, 2x2, 4x2.
- **Flush-left axis.** A strong left edge at the outer margin. Page titles, section labels and controls align to it. Secondary content aligns to a second fixed axis at column 4. Do not center things.
- Vertical rhythm: baseline grid of 4 px. Text baselines land on it.

### 3.3 Stroke

- Hairline: 1 px (`line`).
- Control outline: 2 px (`line-strong`), as in the reference toggle.
- Focus ring: 2 px `accent`, offset 2 px outside the control, rectangular.

### 3.4 Elevation

There is none. Overlays (menus, dialogs) separate from the page by a flat `surface` fill plus a 1 px `line` border, and by dimming the page behind them to 60% (dark) or 40% (light) black.

### 3.5 Icons

Icons are a tiny, closed set of basic glyphs. Text always wins: if a word fits, use the word. No icon ever appears as decoration, as a logo, or next to a label that already says the same thing.

**The set (nothing outside it ships in the library):**

| Glyph | Use |
| --- | --- |
| Dots (DotsThree horizontal, DotsThreeVertical) | more / overflow, opens the app bar or a menu |
| Plus, minus | add, remove, increment, decrement, zoom |
| Cross (×) | close, clear, remove |
| Check | confirmed, selected in a multi-select |
| Caret (chevron) up, down, left, right | expand/collapse, sort direction, pivot and pager steps, picker affordance |
| Arrow up, down, left, right | back/forward navigation, move, import/export direction |

Anything else (search, settings, share, play, record and so on) is a lowercase text command instead. Exception: the transport glyphs Play, Stop and Record are allowed in the drum synth and code editor, since there is no better word.

**Construction:**

- **Source: Phosphor Icons** (MIT licensed). The library embeds exactly these glyphs and no others: `DotsThree`, `DotsThreeVertical`, `Plus`, `Minus`, `X`, `Check`, `CaretUp`, `CaretDown`, `CaretLeft`, `CaretRight`, `ArrowUp`, `ArrowDown`, `ArrowLeft`, `ArrowRight`, plus `Play`, `Stop`, `Record` for the transport exception.
- **Weight:** Regular at 20 and 24 px, Bold at 16 px so strokes stay legible. Thin, Light, Fill and Duotone are never used.
- **Rounded terminals are the one deliberate exception** to the zero-radius rule. Do not restyle, square off or outline-trace the glyphs.
- Converted to vector paths at build time and tessellated for wgpu (or drawn from a glyph atlas), so they stay crisp at every scale and take any theme color. The glyph’s bounding box snaps to physical pixels.
- Sizes: 16, 20, 24. Color is `fg-2` at rest, `fg` on hover, `accent` when active, `fg-3` when disabled.
- Hit target stays 40 x 40 px (48 touch) even when the glyph is 16 px.
- An icon-only control always gets a tooltip (6.13) and an accessible name.

**Motion:**

- Caret expand/collapse: rotates 180° over 160 ms `ease-out-expo`, in sync with the content opening.
- Plus to cross: the plus rotates 45° over 160 ms `ease-out-expo` when a panel it opens becomes open, and back on close.
- Arrows and carets used as steppers nudge 4 px in their pointing direction on press, returning in 160 ms. No tilt.
- Dots do not animate on hover; on press, the three dots briefly spread 2 px apart and return over 120 ms.

---

## 4. Typography

Geist is the only typeface family. Use every variant that ships:

- **Geist Sans**: all UI text. Variable weight 100 to 900.
- **Geist Mono**: numeric readouts, code, units, MIDI note numbers, anything that must align in columns. Tabular figures always.
- **Geist Pixel variants (all available cuts)**: reserved for display moments only: a large peak meter number, a splash-free app title bar wordmark, a BPM readout, empty-state counters. Never for body or labels. Used sparingly so it remains special.

If a variant isn’t present in the font files, the library falls back to Geist Sans or Mono silently; it never falls back to a system font.

### 4.1 Scale (Metro proportions)

| Role | Face / weight | Size / line | Case | Tracking |
| --- | --- | --- | --- | --- |
| `display` (page hero) | Sans Light 200 | 72 / 72 | lowercase | -2% |
| `title` (page title, pivot header) | Sans Light 300 | 40 / 44 | lowercase | -1% |
| `heading` (section) | Sans Regular 400 | 24 / 28 | lowercase | 0 |
| `value` (the “On” in the reference) | Sans Medium 500 | 20 / 24 | as typed | 0 |
| `body` | Sans Regular 400 | 14 / 20 | sentence | 0 |
| `label` | Sans Regular 400 | 12 / 16 | **UPPERCASE** only for tiny category tags; else sentence | +4% |
| `caption` | Sans Regular 400 | 11 / 16 | sentence | +2% |
| `mono-value` | Mono Regular 400 | 14 / 20 | n/a | 0 |
| `mono-large` | Mono Light 300 | 32 / 36 | n/a | 0 |
| `pixel-display` | Pixel (best-fitting cut) | 48 to 96 | as typed | 0 |

Rules:

- **Large type is light, small type is regular.** The contrast between a huge light lowercase title and small regular text is the Metro signature. Do not use bold for emphasis in large sizes.
- Page titles and pivot headers are **lowercase**, never title case.
- Maximum two weights on screen per component. Maximum four sizes per screen.
- Text color is only `fg`, `fg-2`, `fg-3` or `accent`.
- Left-aligned, ragged-right. No justified text. No centered text except single numeric readouts inside a knob.
- Optical alignment: large light glyphs hang slightly outside the margin (about -0.06 em) so their visual edge aligns with smaller text below.

---

## 5. Layout patterns

1. **Page**: a huge lowercase `title` at the top-left, 24 px below the top margin, then content starting on the 96 px line. Optional `caption` above the title for the app name in `fg-2`, uppercase label style.
2. **Pivot** (horizontal sections): section headers in `title` size sit in a row at the top. The active header is `fg`, the others `fg-3`. The row extends past the right edge, so inactive headers are partially cropped, hinting at more content to the side. Content below scrolls horizontally in lockstep.
3. **Panorama** (for large apps with several top-level areas): background-free, content columns separated only by space, scrolling horizontally with parallax between title and content.
4. **Settings list**: single column, left aligned, each row is a label (`body`, `fg-2`) over a `value` (`fg`) with the control right-aligned at the right margin. Rows are 72 px tall with 8 px between, no divider lines.
5. **Tile dashboard**: Metro tile grid for module-style apps (the drum synth’s per-drum panels). A tile is a flat rectangle outlined by `line` or filled with accent when active, a `label` in its bottom-left, and a `mono-large` or `pixel-display` value in its top-left.
6. **Split editor** (for the code editor): fixed left gutter and sidebar, flat panes separated by a single 1 px `line`, no tab shapes (tabs are text with an accent underline).
7. **App bar**: a 48 px strip at the bottom (mobile-style) or a 40 px strip at the top (desktop). Icon-less. Contains up to five **text** commands in `body`, lowercase. The `…` overflow is a literal ellipsis that expands the bar upward into a vertical list.

---

## 6. Components

Every component defines: anatomy, dimensions, states, and its transitions (see section 8 for the global motion curves).

### 6.1 Toggle switch (hero component, matches the reference)

Anatomy, as in the screenshot: a **label** on top (`body`, `fg-2`), the **state word** below it (`value`, `fg`: “On” / “Off”), and the **switch** right-aligned and vertically centered across both lines.

**Switch geometry**

- Track: 52 x 20 px, rectangular, 2 px outline.
- Thumb: a flat rectangle, 12 x 28 px (taller than the track so it pokes out above and below by 4 px), no outline, no radius.
- Inner padding: thumb travels with a 4 px inset from the track’s inner edge.

**States**

- **Off**: track is outline only (`line-strong`, 2 px), interior empty (transparent). Thumb is `fg`, positioned at the left. State word reads “Off”.
- **On**: track interior fills solid `accent` (outline becomes `accent` too). Thumb is `on-accent`/`fg`, positioned at the right. State word reads “On”.
- **Pressed (either)**: thumb widens to 16 px over 80 ms (grows toward the center of travel, so it doesn’t shift its far edge), and the track interior shows a 25% accent wash. This communicates “grabbed”.
- **Hover** (pointer): outline brightens one step; the state word does not change.
- **Focus (keyboard)**: rectangular accent focus ring around the whole row’s control area.
- **Disabled**: everything drops to `fg-3` / `line`. No accent. Not interactive. The state word stays but in `fg-3`.

**Interaction**

- Tap/click anywhere on the row toggles.
- Drag the thumb: it follows the pointer 1:1 along the track, clamped. On release, it commits to whichever side is closer, or the direction of flick if velocity exceeds 600 px/s.
- Keyboard: Space or Enter toggles, Left sets Off, Right sets On.
- The state word changes at the **midpoint** of the thumb’s travel, not at the end.

**Animation**

- Thumb slide: 180 ms, `ease-out-expo` (see 8.1). Position only; the thumb’s width returns from 16 to 12 px over the last 80 ms.
- Fill: the accent fill **wipes** across the full track extent using the same normalized progress as the thumb. Width is `track_width × progress`, including exactly 0 and 1: no special end caps may appear or disappear abruptly. The outline blends between its neutral and accent colors through that progress. The fill never cross-fades; thumb travel and 180 ms timing stay unchanged in both directions.
- State word: cross-slides: the outgoing word moves 6 px down and fades out in 90 ms while the incoming word enters from 6 px above and fades in over 120 ms, staggered by 40 ms.

### 6.2 Slider

- Track: 2 px line, full width, `line-strong`. Filled portion (from minimum, or from center for bipolar parameters) is `accent`, 6 px tall.
- Thumb: flat 12 x 28 px rectangle, `fg`, same family as the toggle thumb.
- Above the track: label (`label`, `fg-2`) left, value (`mono-value`, `fg`) right on the same baseline.
- Hover: thumb gets an `accent` top edge (2 px).
- Pressed: thumb widens to 16 px, value text color becomes `accent`, and a small flat tooltip-free value stays in place (no popping bubbles).
- Drag precision: holding Shift drops sensitivity to 10%. Double-click resets to default; the thumb glides there in 160 ms `ease-out-expo` and the value text counts to the default.
- Scroll wheel: one notch changes value by one step; Shift+wheel by a tenth of a step.
- Keyboard: arrows step, PageUp/PageDown step x10, Home/End jump.
- Value readout updates continuously while dragging with no animation lag (readout is instantaneous; only the thumb has no smoothing either; smoothing of the audio parameter is the app’s responsibility).

### 6.3 Knob (for synth parameters)

Knobs exist because the drum synth needs dense parameter panels, but they follow the Metro flatness.

- Geometry: no round body. A **270° arc** (from 7:30 to 4:30 o’clock) drawn as a thin 2 px `line` for the empty path, with a 4 px `accent` stroke for the filled portion. A 2 px indicator tick at the current angle in `fg`. Diameter 56 px, hit area 72 px.
- Center: the value in `mono-value`, centered, `fg`.
- Below: label in `label` style, `fg-2`, left-aligned to the knob’s left edge (not centered).
- Drag: vertical drag (up = increase), 200 px full-range; Shift for fine. Cursor is hidden and pointer is captured during drag; it reappears at the knob afterwards.
- Hover: arc’s empty path brightens one step. Press: accent stroke thickens from 4 to 6 px over 80 ms.
- Double-click resets. Right-click opens “MIDI learn” (see 6.9).
- Animation: when value is set programmatically (preset load), the arc sweeps to the new angle over 240 ms `ease-out-expo` and the numeric value counts along.

### 6.4 Button

Three types, all rectangles.

- **Primary**: filled `accent` rectangle, `on-accent` text in `value` weight, height 40, horizontal padding 24, text left-aligned (not centered) at 16 px inset. Use at most one per view.
- **Secondary**: 2 px `line-strong` outline, `fg` text, same size.
- **Text button**: no outline, `body` text in `fg`, underlined 2 px `accent` only on hover/focus.

States:

- Hover: primary gets 10% white overlay; secondary outline becomes `fg`.
- **Pressed: the tilt.** Reproduce the Windows Phone press feedback. The button tilts **toward the press point** in 3D: up to 6° rotation around the x and y axes with a perspective of 400 px, scale 0.97, over 60 ms. Release returns over 220 ms `ease-out-expo`. On desktop, the tilt is applied to buttons, tiles and list rows (not to sliders, knobs or toggles). Tilt can be disabled globally.
- Disabled: `fg-3`, no tilt.

### 6.5 Text input

- A 2 px outline rectangle, 40 px high, `line-strong`. Label sits **above** in `label` style, never as placeholder.
- Focus: outline turns `accent`. Caret is a 2 px `accent` bar, blinking with a hard on/off, 530 ms period (no fade).
- Selection: `accent` at 40% fill.
- Error: outline `danger`, error message below in `caption` `danger`. Only for real errors.
- Typing animation: none. Characters appear instantly.
- Clear affordance: a plain “×” glyph in `fg-2` appears at the right when non-empty and focused.

### 6.6 List and list items

- Rows: 56 px minimum, `heading` or `body` text, left-aligned at the margin. No dividers; separation by space only.
- Two-line rows: primary (`value`) over secondary (`caption`, `fg-2`).
- Selection: the selected row’s text turns `accent` and a 4 px accent bar appears at the **far left edge** of the row, growing from zero height at center to full height over 120 ms.
- Press: tilt (6.4).
- Reorder (drag): the dragged row lifts by scaling to 1.02 and gaining a 1 px `line` outline; neighbors shift 56 px with 160 ms `ease-out-expo`.

### 6.7 List picker / dropdown

- Closed: a label above the current `value`, with **16 px horizontal content inset** shared by label, value and desktop menu options. A 2 px neutral outline appears on hover only; text must have breathing room inside it. Keyboard focus uses the separate outside accent ring.
- Compact open: the **full-screen picker**, Metro style: the page dims, a list of choices in `heading` size slides in as a vertical stack at the left margin, the current choice in `accent`. Tapping one selects and closes.
- Desktop open (720 logical px and wider): a flat menu opens **around the selected option**, keeping its `value` text at the closed value’s position whenever window bounds permit. Options are 48 px tall, with 16 px horizontal inset and 8 px panel padding above/below. The panel reveals above/below this anchor over **220 ms**; selected text stays still. Clamp to the window and scroll overflow inside the stationary panel. Hover never recenters it; keyboard focus glides between rows over 140 ms.
- Desktop close/selection: commit the model immediately. Over **200 ms**, collapse the panel and carry the chosen label into the closed value, drawing a single copy throughout the handoff. Cancellation collapses around the unchanged value. Closing during opening starts from the current reveal and opacity. Reduced motion replaces reveal/movement with a **100 ms opacity transition**.

### 6.8 Pivot, tabs and segmented choice

- Pivot headers: preserve every fitting title in place. Selecting a later title must not hide preceding options by moving the active title to the left edge. Overflow pans only enough to reveal the selection; pointer dragging, wheel, trackpad and keyboard navigation expose further titles. No previous chevron. Nested pivots manage their overflow independently.
- Segmented choice (small sets, 2 to 4 options): a row of `body` text labels with 24 px gaps. The selected label is `fg` with a 2 px `accent` underline; others `fg-2`. The underline **slides** between options over 180 ms and resizes to the new label’s width.

### 6.9 MIDI learn

- Entering learn mode on a control: its outline becomes a 2 px `accent` **dashed** rectangle (dash 6, gap 4) that marches clockwise at 24 px/s; the value readout is replaced with “…” in `accent` until a CC arrives.
- On receiving CC: the dash stops, the outline snaps solid for 240 ms, then fades to rest. The control’s caption shows `CC 74` in `mono-value`.
- Escape cancels; the dashes fade out in 120 ms.

### 6.10 Meters and readouts

- Level meter: a vertical or horizontal 4 px bar in `line`, with the level as an `accent` fill. Over 0 dBFS the top segment turns `danger`. Peak hold is a 2 px `fg` tick that holds 800 ms then falls at 40 dB/s.
- Meter fill is instantaneous (no easing) because it is data, not UI.
- Big readouts (BPM, current note, velocity): `pixel-display` or `mono-large`.

### 6.11 Dialogs and menus

- **Dialog**: the page dims, a full-width flat `surface` band slides in vertically centered, with a `heading` title (lowercase), `body` message, and 1 to 2 text/secondary buttons left aligned along the bottom. No title bar, no close icon. Escape dismisses.
- **Context menu**: a flat `surface` rectangle with a 1 px `line` border, `body` items 36 px tall, left aligned, no icons, no shortcuts column unless relevant (shortcuts in `caption` `fg-3`, right aligned). Opens at the pointer instantly (no entry animation) because speed matters more than flair.
- **Toast / notification**: a single flat bar from the top, `surface`, 1 px `line`, `body` text. Slides down 8 px and fades in over 160 ms, holds 2.5 s, fades out 160 ms. Never stacks; a new toast replaces the old one.

### 6.12 Scrolling

- Scrollbars: a 2 px `line-strong` bar at the right edge, visible only while scrolling or hovering the edge, fading in 120 ms and out after 800 ms. On hover over the bar it widens to 8 px.
- Momentum scrolling with friction (deceleration 0.0015 per ms), overscroll stretches content up to 40 px with a resistance curve and returns over 280 ms `ease-out-expo`. No bounce past the origin.
- Panorama scrolling applies parallax: the title moves at 0.5x the speed of the content.

### 6.13 Tooltips

- Appear after 600 ms of hover. A flat `surface` rectangle with 1 px `line`, `caption` text, placed 8 px from the element. No arrow. Fade in 100 ms, out 80 ms. Hide immediately on press.

---

## 7. Interaction model

### 7.1 Input methods

The library treats **pointer, touch, keyboard and MIDI** as first-class inputs. Gamepad is out of scope.

### 7.2 State machine (every interactive element)

`rest` to `hover` to `pressed` to `rest`, with `focus` (keyboard) and `disabled` as independent layers. Transitions between states are specified per component. Press always responds on pointer-**down**, never on up, with exceptions where it’s a drag-to-confirm.

### 7.3 Focus and keyboard navigation

- Tab / Shift+Tab move focus in reading order. Arrow keys navigate within a group (list, segmented choice, pivot).
- The focus ring appears only for keyboard focus, never for pointer focus.
- Focus ring movement is **animated**: the ring glides between elements over 140 ms `ease-out-expo`, resizing as it goes.
- Every action reachable by pointer is reachable by keyboard.

### 7.4 Gestures (touch/trackpad)

- Tap: select/toggle. Press and hold 500 ms: context action (the tile tilts down further to 0.94 scale as a cue).
- Horizontal swipe on a pivot or panorama changes section, with velocity-based snapping.
- Two-finger scroll on trackpads maps to scrolling; pinch is reserved for app-level zoom (code editor).

### 7.5 Pointer capture and cursor

- Dragging any slider or knob captures the pointer so it keeps working outside the window.
- Cursor: default arrow; text I-beam in inputs; for knob/slider drag the cursor is hidden and a faint 1 px accent crosshair is **not** shown (no extras). Resize handles use standard resize cursors.

### 7.6 Text editing (shared by inputs and the code editor)

- Full IME support, clipboard, word and line navigation, undo/redo with coalescing by typing bursts of 300 ms.
- Caret movement is instant by default (no smooth caret); an optional smooth caret mode uses 60 ms linear.

### 7.7 Accessibility

- Respect the OS **reduce motion** setting: replace every translate/scale/tilt with a 100 ms opacity crossfade and disable parallax and marching dashes.
- Respect OS text scaling: type scale multiplies, spacing multiplies with it, grid reflows.
- Provide an accessibility tree (AccessKit) so screen readers get roles, names, values and state.
- Minimum hit target 40 x 40 px (touch 48).

---

## 8. Motion system

### 8.1 Easing curves

| Name | Definition | Use |
| --- | --- | --- |
| `ease-out-expo` | cubic-bezier(0.16, 1, 0.3, 1) | Default for almost everything: fast start, long gentle settle (the Metro feel) |
| `ease-in-expo` | cubic-bezier(0.7, 0, 0.84, 0) | Exits and things leaving |
| `ease-in-out` | cubic-bezier(0.76, 0, 0.24, 1) | Large layout movements |
| `linear` | none | Meters, marching dashes, progress |

Nothing uses spring physics or overshoot. Nothing uses default ease-in-out except large repositioning.

### 8.2 Durations

| Token | ms | Use |
| --- | --- | --- |
| `instant` | 0 | Data, menus, text |
| `quick` | 80 to 120 | Press feedback, hover, small fades |
| `base` | 160 to 220 | Toggles, selection, underline slides |
| `slow` | 280 to 350 | Pivot switch, page parts |
| `page` | 350 (in) / 250 (out) | Page transitions |

Exits are always faster than entrances (roughly 70%).

### 8.3 Page transitions: Turnstile

The signature transition, adapted from WP.

- **Navigate forward (turnstile forward in)**: the incoming page rotates in around its **left edge** (Y axis) from -50° to 0° with perspective 800 px, while moving from 80 px to the right of its final position, and its opacity goes 0 to 1. 350 ms, `ease-out-expo`.
- **Outgoing page (turnstile forward out)**: rotates around its left edge from 0° to +50° while fading to 0. 250 ms, `ease-in-expo`. The outgoing and incoming animations **overlap** by about 120 ms.
- **Navigate back**: mirror: the current page does a forward-out rotation to the left (0° to -50°), and the previous page comes back from +50° to 0°.
- **Staggered content (feather)**: within the incoming page, each top-level element animates separately: it enters from 60 px right, rotating from -35° to 0°, opacity 0 to 1, 300 ms `ease-out-expo`. Elements are delayed top to bottom by **40 ms each**, capped at 8 elements (the rest enter with the 8th). The page title enters first and slightly farther (100 px).
- The reduce-motion fallback is a 100 ms crossfade.

### 8.4 Continuum transitions

When the user selects an item and a detail view opens, the **selected element’s text continues**: its label detaches from the list, moves and scales to its new position as the detail title (280 ms `ease-in-out`), while the rest of the list turnstile-exits and the detail content feathers in. This preserves context. Use for list-to-detail and tile-to-page.

### 8.5 Tile and panel entrances

- On first appearance of a tile dashboard, each tile tilts in: starting rotated about the x axis at -60° and offset 20 px down, settling to flat over 400 ms `ease-out-expo`, staggered by 30 ms in reading order (left to right, then down).
- **Live tile behavior (optional per tile)**: a tile may flip to show secondary information: rotate 90° around its horizontal axis in 200 ms `ease-in-expo`, swap content, rotate back 200 ms `ease-out-expo`. Interval is set by the app. Flipping is never triggered while the pointer is over the tile.

### 8.6 Value change animations

- Numeric changes caused by the user: instantaneous.
- Numeric changes caused by the app (preset loads, resets): count up/down along the easing in 240 ms.
- Text swaps (like On/Off): vertical micro-slide with fade, as defined in 6.1.

### 8.7 Overlays

- **Dim layer**: fades to 60% black over 160 ms `ease-out-expo`, out in 120 ms.
- **Dialog**: slides in from 24 px below with fade, 220 ms `ease-out-expo`; out 140 ms `ease-in-expo`.
- **Full-screen picker list**: items stagger in 30 ms apart sliding from 40 px left, 220 ms each.

### 8.8 Loading and progress

- Indeterminate progress: **five small squares (4 x 4 px)** in `accent` travel along a horizontal line (the classic Metro dots, squared): each dot runs a 3.2 s loop accelerating toward the middle and decelerating at the ends, staggered by 160 ms, seamlessly looping. Lives in a 1 px tall strip along the top of the window or inline under a label.
- Determinate progress: a 4 px `accent` bar over a 2 px `line` track. Fill changes follow `linear` between updates.
- Never use spinners.

### 8.9 Performance of motion

- Every animation can be frame-stepped and slowed (debug key: Ctrl+Shift+Slow, 10x).
- Animations are interruptible: a new target mid-flight retargets from the **current value and current velocity** with no jump.
- Animated properties are limited to transform, opacity, color, and font weight. Layout-affecting animation is only used in list reorder and expand/collapse and must be done on the GPU by transforming already laid out content when possible.

---

## 9. Swiss modernism rules

These govern composition, not individual components.

- **Grid-first composition.** Place blocks on the 12 column grid. Whitespace is a structural element, not leftover.
- **Asymmetry and tension.** Large title flush left, content offset to column 4, a lot of empty space on the right. Avoid mirrored or centered layouts.
- **Scale contrast.** One element on each screen is dramatically large (the title, or a single big number). Everything else is small. No medium-sized middle.
- **Alignment lines.** Elements share edges: text baselines, left edges and tops align across the whole screen. Do not nudge for “looks.”
- **Rules, sparingly.** Horizontal hairlines (1 px `line`) may divide major sections in dense tools (code editor) but never wrap items in boxes.
- **Information density with calm.** Dense parameter panels (the drum synth) use the tile grid and mono numerals, with strict uniform spacing so density reads as order.
- **No ornament.** Text first. Icons exist only when a word would be clumsy, and then only from the minimal glyph set in section 3.5.

---

## 10. Screen archetypes (how the library’s pieces assemble)

### 10.1 Drum synth

Top-left: `caption` “drum synth” in `fg-2` uppercase label style, with the huge lowercase `title` of the active kit or section beneath. A pivot for **kick / snare / hat / toms / cymbals / master**. Each pivot page is a tile grid: large `pixel-display` velocity/hit indicator tile (flashes `accent` on hit and decays over 300 ms `linear`), then knobs grouped in 2x2 tiles per parameter family (tone, decay, noise, drive). Right edge: a thin vertical meter. Bottom app bar: `learn midi`, `presets`, `settings`.

### 10.2 Code editor

A very quiet screen: left gutter in `mono-value` `fg-3` line numbers, editor text in Geist Mono 14/22 on `bg`, a 1 px `line` between sidebar and editor, tabs as text with an `accent` underline, status line in `caption`. The command palette is a dialog band that slides from the top, a single input and a list in `heading`-size rows with the match highlighted in `accent`. Extensions’ UI uses the same components, so they look native for free.

### 10.3 Settings

A plain list of toggle rows exactly like the reference: label over value, switch at the right, 72 px rows. Nothing else.

---

## 11. Library architecture (for Codex)

Behavior-level requirements only; Codex chooses the implementation.

- **Language/stack**: Rust, wgpu, winit for windowing, an accessibility layer (AccessKit), and a text shaping library (cosmic-text or parley) for layout.
- **Structure**: a retained widget tree with immediate-style ergonomics (builder-style view functions that diff into the tree) so apps are easy to write and animations can persist across frames.
- **Theme**: a single `Theme` value holds all tokens from section 3 and 4 and is hot-swappable at runtime (dark/light/accent change animates as a 200 ms color crossfade).
- **Animation engine**: a central scheduler with springs disabled; supports curves from 8.1, retargeting with preserved velocity, sequencing, stagger groups, and reduce-motion substitution.
- **Layout**: a grid/stack layout system aware of the 4 px base unit, the 12 column grid, the tile grid, and baseline snapping. Everything snaps to physical pixels.
- **Components**: all of section 6, each with documented state machines.
- **Extensibility**: an app (or extension) can define custom widgets using the same primitives (rect, stroke, text, arc, transform) and the same animation API, so third-party widgets are indistinguishable from built-ins.
- **Hot reload of theme and layout** in debug builds.
- **Debug overlay**: toggles to show the grid, baseline grid, hit areas, and frame timings.
- **Cross-platform**: Windows, Linux, macOS from day one. Touch support where the OS provides it.
- **Audio-friendly**: UI thread never blocks audio; parameter changes pass through lock-free channels, owned by the app. The library exposes parameter-widget bindings but doesn’t own audio.

---

## 12. Build order and acceptance criteria

1. **Foundation**: window, wgpu surface, rect/stroke/text/arc rendering, pixel snapping, Geist loading (all variants), theme tokens. *Accept*: a static page with a `display` title and body text renders crisply at 100% and 200% scale.
2. **Animation engine** with the easing curves. *Accept*: a test rect retargets mid-flight with no jump.
3. **Toggle switch** exactly per 6.1, side by side with the reference screenshot. *Accept*: visually matches the screenshot’s structure (label over “On”, teal filled track, flat thumb) and all states and animations work.
4. **Button (with tilt), slider, knob, text input.**
5. **List, picker, pivot, segmented choice.**
6. **Turnstile and feather page transitions, continuum.**
7. **Overlays**: dialog, menu, toast, tooltip.
8. **Accessibility, reduce motion, keyboard navigation, MIDI learn widget behavior.**
9. **Demo app**: the settings screen from 10.3, then a stub of the drum synth screen.

Final check for every screen: remove one element and see if the screen gets worse. If not, leave it removed.


## Colour scheme picker and catalogue

A reusable Windows 8 inspired colour ribbon supports horizontal and vertical orientation, continuous and spaced swatch variants, and zero to three application-defined companion accents per primary colour. Named palettes and hex readouts remain available alongside samples. Paired caret markers sit outside the colour data and animate to selection in 180 ms; programmatic changes follow the shared 240 ms value motion, while reduced motion uses a 100 ms crossfade. The legacy ribbon uses dense 24 logical pixel columns with small bright samples on tinted bands, a neutral frame and hollow selection triangles. The swatch variant retains 48 pixel targets for touch use. Overflow follows the selection and remains reachable by wheel, keyboard and accessible radio options. Custom palettes, disabled and empty states are supported. The companions describe content; UI chrome retains one accent.

A separate `showcase` example catalogues all controls, typography (including all five Geist Pixel cuts), palette variants, tiles, meters, overlays, layout and motion. It supports deterministic offscreen snapshots. See `docs/color-picker.md` and `docs/showcase.md` for implementation and usage guidance.


## Optional interaction sound

Sound is off by default and independent of reduced motion. Essential mode includes switch states and explicit outcomes; subtle mode adds primary action clicks, committed selections and layer transitions. Hover, typing, scrolling, continuous controls, MIDI and background value animation stay silent. A deterministic dry click/pop family uses short envelopes, quiet filtered contact transients and no reverb or spatial movement. Explicit confirmation/rejection must reflect actual application results and retain visible explanations. Semantic requests coalesce and rate-limit without a playback backlog; native device setup and synthesis run off the UI thread, with precomputed samples and fixed voices in the callback. Apps can mute individual widgets or consume feedback into their own audio engine. The showcase includes audition, volume, mode controls, status and WAV export. Acoustic details, research and limitations are in `docs/sound.md`.


## Precision scrolling and reorder revision

Trackpad pixel deltas retain platform acceleration and momentum, are converted from physical to logical pixels once, and respect gesture phases. Do not add a second inertia curve to an already accelerated OS stream. Compact tiles give values and labels disjoint text rectangles; larger tile rows set explicit heights. Reorderable rows and opt-in tiles stay flat and follow the pointer, emit live sibling-slot reorder events at midpoint crossings, animate displaced siblings for 200 ms, and settle on release. A 250 ms touch hold distinguishes reorder from ordinary scrolling. Precise scrolling, overflow navigation and accessible options remain available independently of sound preferences.
