# Sound research and Flutter implementation

The references below informed the original Brockmann interaction sound design. Their findings support selective, meaningful feedback; the exact eight waveforms, durations, gain, and mode policy are project design decisions, not prescriptions from the papers.

## Android adaptation

`BrockmannSoundController` is silent by default. Essential admits switches and outcomes; Subtle adds deliberate activations and navigation. A microtask coalesces concurrent cues by semantic priority. A 45 ms global guard and 100 ms repeat guard prevent a stream of clicks; a more important outcome can bypass that guard. Sliders, knobs, pointer motion, scrolling, and drag updates emit no cues.

`AndroidSoundBackend` uses a method channel and native `SoundPool` with four voices and `USAGE_ASSISTANCE_SONIFICATION`. Small original PCM WAVs are copied to private cache and loaded on a worker. Playback is enabled only after every sample reports loaded. Missing or failed audio is silent. No audio focus, microphone, storage, or notification permission is requested. Android system volume and audio routing remain in control.

Default playback gain is 0.35; the assets themselves are normalized independently of that user setting. Preloading never previews audio. Backgrounding, muting, disposal, or interrupted startup invalidate pending work, stop the pool, and prevent delayed playback. An injectable backend permits deterministic tests without producing audio.

Source: [Android SoundPool](https://developer.android.com/reference/android/media/SoundPool).

The following is the retained research/reference material from the Rust implementation. Rust API and configuration examples describe that original implementation; use [the Flutter guide](guide.md#optional-sound) for this package's API.

---

# Sound for moments that matter

Brockmann's sound family is dry and small: a contact tick, a soft switch pop, related opening/closing pops, and two explicit outcome cues. There are no sweeps, reverb tails, background loops, hover bleeps or typing sounds. Sound is an optional supplement to the visible interface. It is off by default, and its preference is independent of reduced motion.

“Perfect” is a listening goal rather than a property the library can prove. These sounds are original, reproducible designs informed by research. The exact tones, timings and mappings below are design decisions; they have not been validated in a listening study.

## Research behind the choices

[Brewster, Wright & Edwards, *An Evaluation of Earcons for Use in Auditory Human-Computer Interfaces*, CHI 1993](https://eprints.gla.ac.uk/3257/) compares structured earcons and unstructured sounds. Its experiments motivate using a related, learnable sound vocabulary rather than unrelated effects. The study concerns recognition tasks, not a proof that every graphical control needs sound.

Their [*Experimentally Derived Guidelines for the Creation of Earcons*, 1995](https://www.dcs.gla.ac.uk/~stephen/papers/HCI95.pdf) synthesizes six experiments. It recommends distinguishing cues through several acoustic dimensions, keeping intensity under user control and within a narrow range, and keeping sounds brief enough to follow interaction. Very short notes are discussed for simple cues. We use rhythm as well as timbre/pitch for outcomes; on/off cues are relative companions, not standalone alarms.

[Zhang et al., *Exploring Interactive Sound Design for Auditory Websites*, CHI 2022](https://www.microsoft.com/en-us/research/wp-content/uploads/2022/04/zhang_chi2022.pdf) reports a design study with fourteen professionals. It identifies aesthetics, clarity and interactivity as design considerations and discusses short sounds used selectively. Its setting is auditory websites, so applying those considerations to a visual desktop toolkit is our interpretation, not a directly tested result.

The common direction we adopt is restraint, consistency and user control. These papers do not establish a universally optimal click duration, gain or frequency. A screen reader still needs proper semantics and useful text; a quiet click cannot replace either.

## The family

| Cue | Duration | Character | Automatic use |
| --- | ---: | --- | --- |
| `Activate` | 34 ms | Dry contact click, 980 → 760 Hz body | Enabled primary button activation |
| `Select` | 30 ms | Shorter, drier tick, 1240 → 1040 Hz body | Changed tabs/pivots, committed dropdown choice, discrete palette selection |
| `ToggleOn` | 48 ms | Rounded pop, 650 → 940 Hz body | A switch changes to on |
| `ToggleOff` | 56 ms | Lower, slightly longer pop, 700 → 430 Hz body | A switch changes to off |
| `Open` | 60 ms | Quiet lift, 420 → 620 Hz body | Picker, menu, dialog or command layer opens |
| `Close` | 54 ms | Quiet settling pop, 580 → 360 Hz body | A layer closes; a committed picker uses `Select` instead |
| `Confirm` | 104 ms | Two light contacts, second higher | Explicit application result only |

The frequencies describe each main resonance, not a pure sine beep or the entire spectrum. Each cue also has a short secondary resonance and a quiet, low-pass-filtered contact transient. A 1.5 ms shaped attack, exponential decay and 6 ms shaped release eliminate an abrupt sample boundary. Samples have near-zero DC, exact zero endpoints and a normalized peak of 0.2 before user gain. At the default 0.35 gain, an isolated cue peaks at 0.07, about −23 dBFS. Digital levels do not specify loudness at a listener's ears.

The sound has no simulated room, panning or random pitch variation. Timbre stays stable across themes and repeated interactions. Outcome rhythms distinguish completion and failure without relying on loudness alone. The gentle reject sound is for ordinary UI failures, not a safety alarm.

## Enable it

The native host includes the optional `sound` Cargo feature by default. It uses CPAL 0.16 for output. No device opens until the application opts in.

```rust
use brockmann::{SoundMode, SoundSettings, Ui};
let mut ui = Ui::default();
ui.sound = SoundSettings {
    mode: SoundMode::Subtle,
    volume: 0.35,
};
```

Set preferences in `Application::configure` and update them from your settings UI. The app owns persistence; the toolkit does not write a preference file.

| Mode | Cues allowed |
| --- | --- |
| `Off` | None, including explicit requests |
| `Essential` | Switch on/off, explicit confirm/reject |
| `Subtle` | All eight cues, subject to selective routing and rate limits |

`volume` is a linear gain clamped to 0–1. Zero and non-finite values mute. Use a clearly labelled sound setting and a separate volume control. Muting clears pending requests and fades the active mixer gain toward zero; the worker releases the device. Reduced motion does not change sound settings or stretch sound durations.

Build without native audio if your app owns its audio engine or must avoid the dependency:

```sh
cargo build --no-default-features
```

Synthesis, WAV export, settings and semantic requests remain available. The built-in host reports `SoundStatus::NotBuilt` if playback is requested without the feature. On Linux, the default CPAL backend requires ALSA development libraries (`libasound2-dev` on Debian/Ubuntu). Other native backends are supplied by CPAL for the host platform.

## Which interactions stay silent

- Hover, focus movement and tooltip appearance.
- Typing, caret movement, selection and validation while editing.
- Slider and knob movement, wheel scrolling and MIDI updates.
- Programmatic view reconciliation, preset value animation and meter/progress updates.
- Intermediate palette drag updates. A discrete click/key selection can tick; dragging ticks at release if it changed the scheme. Wheel selection stays silent.
- Disabled controls, unchanged selections, ordinary secondary/text/icon button activation and notification appearance by itself.

A primary button's `Activate` acknowledges accepting the input. It does not announce success. Switch sounds describe the committed local UI state. For an operation whose result depends on storage, hardware or a server, play its outcome only when that result is known.

## Explicit outcomes and per-widget control

```rust
use brockmann::{SoundCue, Ui};
fn saved(ui: &mut Ui) {
    ui.notify("Session saved");
    ui.play_sound(SoundCue::Confirm);
}
fn save_failed(ui: &mut Ui) {
    ui.show_dialog("could not save", "Check the output path and try again.", vec!["close".into()]);
    ui.play_sound(SoundCue::Reject);
}
```

Keep the visible explanation. Do not attach confirm to every “save” press or infer error meaning from a dialog's wording. Notifications are silent unless the app explicitly supplies a cue. A rejection with a dialog coalesces into one `Reject`, rather than playing an opening pop as well.

```rust
use brockmann::{SoundCue, SoundFeedback, Widget};
use brockmann::widget::ButtonStyle;
let silent = Widget::toggle("feedback", "Interaction sounds", false)
    .sound(SoundFeedback::Silent);
let action = Widget::button("apply", "Apply", ButtonStyle::Secondary)
    .sound(SoundFeedback::Cue(SoundCue::Activate));
```

`Silent` suppresses the widget's semantic cues, including its picker open/close cues. `Cue` overrides an existing semantic trigger; it is not a request to sonify every hover or continuous value update. Global mute and essential-only filtering always win. A silent group does not implicitly change its children: apply overrides to the relevant interactive widgets.

## Scheduling and audio architecture

`Ui` collects at most one pending semantic cue per dispatch. Explicit rejection and confirmation outrank switch changes, selection, layer sounds and activation. New cues at equal priority replace old ones. Requests never become a playback queue.

The native `SoundOutput` applies a monotonic real-time gate: at least 45 ms between ordinary cues, and 100 ms between repetitions. A higher-priority outcome can bypass that interval so a fast operation failure isn't hidden by its activation click. The animation clock, slow-motion inspection and paused frames never time-stretch audio.

Device discovery, sample generation, stream construction and destruction run on a worker. When the device advertises buffer limits, output requests 256 frames clamped to those limits, with a fallback to its default buffer if that request fails. The callback reads an atomic latest-request slot, uses eight precomputed sample buffers and mixes at most four fixed voices. It performs no sample generation, allocation, locking, logging or file access. Active tails finish naturally; if all four voices are occupied a new cue is dropped. Gain changes are smoothed over roughly 3 ms. Mono feedback is copied to the output channels, with 0.8 peak headroom even if four full-level sample peaks coincide.

Cues submitted during startup are discarded. Requests older than 120 ms are discarded at the callback, avoiding late feedback after a stall. Actual onset latency depends on the output device, backend and buffer configuration; this implementation does not guarantee an end-to-end latency. The callback reads a monotonic timestamp only when a pending command exists.

Device failures degrade to silence and `SoundStatus::Unavailable`. Disabling and re-enabling sound retries device initialization. The UI remains usable if there is no output device. `Ui::sound_status` reports the host state; it is separate from the user's desired sound settings. A custom host can consume `Ui::take_sound()` and feed the samples into its own engine instead. Do not open a second feedback device in a production synth if it competes with the instrument's stream: use the shared application audio engine and keep UI effects out of the recorded/master signal as appropriate.

Audio keeps its own clock; an enabled stream can run silently between cues while the renderer sleeps. Muting releases the stream. Device teardown is signalled on shutdown rather than joined on the UI thread.

## Audition and export

```sh
cargo run --example showcase -- --page sound
cargo run --example showcase -- --page sound --sound
cargo run --example showcase -- --export-sounds target/sounds
```

The sound page includes mode/volume controls, eight audition buttons, device status and live switch/dropdown/outcome examples. Mode filters also apply to the audition buttons. `--sound` enables subtle feedback across the catalogue for the current launch; the default launch stays silent. The smaller demo exposes an **Interaction sounds** setting too.

Export produces eight mono 48 kHz / 16-bit WAVs at the default gain and `preview.wav`, which presents them in table order with 700 ms of silence between cues. It works without the sound feature or an audio device. The synthesis and export APIs are `sound::synthesize` and `sound::write_wav`.

Listen on headphones and small speakers, at low volume, over speech and over the app's expected audio. Check that on/off remain related, selection doesn't become a stream of ticks, and failure is recognisable without sounding punitive. Repeat common tasks for several minutes to assess fatigue. Include people with different hearing and sensory preferences; keep mute easy to reach. Objective checks cover duration, bounded peaks, DC, endpoints, routing and throttling, but do not replace that listening work.
