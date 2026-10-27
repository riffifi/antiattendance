# Rust implementation audit

The Rust implementation in `../rust/brockmann` is the behavior reference. This port uses Flutter's rendering and Android input/lifecycle services; it does not embed the Rust renderer.

| Reference | Flutter implementation and checks |
| --- | --- |
| `animation.rs` | `motion.dart`: the same Bézier controls and 32-step inversion, active-tween position/velocity preservation, 250 ms outgoing turnstile (including rapid interruption), 40 ms stagger / 300 ms incoming feather. New motion starts directly on the authored curve; velocity correction is reserved for interrupted active motion. Tests cover intermediate positions, interruption, completion, reduced spatial motion and idle frame scheduling. |
| `theme.rs`, `text.rs` | Same 14 type roles, font files, variable weight, tabular Mono values, neutral surfaces and contrast-safe accent text. All neutral tokens interpolate during a theme change. Android text input uses Flutter's editable text / platform IME rather than the Rust editor. |
| `widget.rs`, `ui.rs` | Controlled components with separate semantic model and animated presentation. 180 ms two-way switch wipe and full thumb travel, animated On/Off replacement, captured thumb drag committed on release. Sliders follow direct input immediately and animate external changes. Press tilt uses pointer position and the Rust strength tiers. |
| `ui.rs` choice navigation | Large, un-underlined title pivots, retained previous options, minimum necessary overflow pan. Compact tabs remain a separate style. Content uses feather entry and direction-aware outgoing turnstile; horizontal page swipes do not take over an active child slider gesture. |
| `color_picker.rs` | Deliberate mobile redesign: animated curated tiles and an arbitrary HSV colour field, with accessible slider alternatives and optional alpha. Historical palettes remain compatible data; the historical ribbon renderer has been removed. |
| `ui.rs` display / drag | Animated list selection, tile activation pulse, 400 ms live flip paused while hovered or pressed, 800 ms meter peak hold then 40 dB/s decay. Hold-to-reorder is 250 ms; flat proxy, animated neighbours, scrollable instructions, accessible move actions. |
| `ui.rs` overlays | Native Back cancellation and Navigator focus scope; explicit full-page or anchored presentations, Android predictive-back page routes and an aligned selected-row reveal, with one carried label landing in the closed field, full-duration early cancellation, and a 140 ms keyboard candidate outline. Phone rows stagger in. Modal and toast styling stays flat. |
| `icons.rs`, `build.rs` | Original Phosphor set plus 28 application icons, in regular and bold weights. Arrow press translation, spreading dots, optional expanded plus/caret rotation. Flutter consumes SVGs directly instead of build-time tessellation. |
| `sound.rs`, `sound/output.rs` | Same eight original PCM designs, gain, priority and admission policy. Android uses SoundPool with background asset preparation, optional modes, no focus request, no delayed playback, lifecycle stop/release. |
| `layout.rs`, `geometry.rs` | Same typography and spacing language, safe mobile margins, natural text wrapping and touch targets. Flutter owns constraint layout, hit testing and device scaling. Neutral structural borders use physical hairlines. |
| `runtime.rs`, `render.rs`, `scene.rs`, `primitives.wgsl` | Android/Flutter owns scheduling, GPU rendering, input routing, font rasterization and accessibility. No parallel wgpu scene is maintained. Profile tests on the Pixel measure actual Flutter build and raster timings. |
| Rust demos / showcase | Eleven catalogue pages, adjustable colour variants, 14 typography specimens and animated weight presets, motion presets, controls, overlays, tiles and optional sound. |

## Deliberate Android differences and remaining boundaries

Phone commands commit on tap release so scrolling can cancel activation. Discrete touch controls have a 48 dp minimum. Colour tiles and an HSV field replace the historical ribbon. Dials add direct arc input and centre dragging; sliders preserve thumb grab offset. Dropdown presentation can be chosen explicitly. Directional stretch feedback is provided at all scroll boundaries. Native Android Back and IME replace desktop Escape/clipboard plumbing where appropriate.

The Rust MIDI-device host, desktop cursor warping, TOML hot reload, debug grid overlays, and manual frame stepping are not Android features in this package. Flutter provides hot reload and DevTools. The standalone `Panorama`/continuum animation helpers are not exposed as widgets here. Android phones use the full-page selection transition.

This document records concrete behavior and platform boundaries; it is not a claim that two different renderers produce pixel-identical frames.
