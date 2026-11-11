# 3.8.3 finishing checklist

The direction remains WP8 with Geist. The original Microsoft guidance favors
content, typographic hierarchy and negative space:
https://learn.microsoft.com/en-us/archive/msdn-magazine/2011/december/windows-phone-how-to-translate-common-design-principles-to-the-windows-phone

Completed changes:

- [x] Show the selected class once; move other class choices to a labeled picker.
- [x] Make attendance and NFC name rows tappable, with selection counts and a true clear-selection action.
- [x] Keep a chosen schedule day through refreshes; Today preserves the selected group.
- [x] Combine week navigation and the selected date; handle missing dates safely.
- [x] Remove duplicate NFC entry buttons and hide empty request sections.
- [x] Give section labels less emphasis than primary content; preserve case in people's names.
- [x] Move long NFC help behind an explicit disclosure.
- [x] Separate informational messages from errors, with readable theme error colors.
- [x] Add a skippable first-run walkthrough, persistent completion and Settings replay.
- [x] Give My Profile a clear identity header, connection state, edit disclosure, save action and device access.
- [x] Save only changed profile fields; handle partial failures without repeating successful changes.
- [x] Prevent disclosure expansion state from colliding with nested text-field scroll offsets.
- [x] Wrap tutorial controls at large text sizes and keep the content scrollable.
- [x] Translate all new UI copy into Russian, English, French, Portuguese and Chinese.

Regression tests exercise tutorial persistence, double-size text, day retention,
profile updates, native NFC authorization/lifecycle and the existing app flows.
Device delivery follows AGENTS.md and preserves installed app data.

## 3.8.5 follow-up

- [x] First-use setup now previews and saves language and theme, with an interface sound option.
- [x] Settings uses a single theme chooser and refreshes sound preferences after replaying setup.
- [x] Header actions occupy the trailing gutter; this fixes both Skip and Updates → Refresh.
- [x] QR sign-in can open its validated MIREA approval link in a browser.
- [x] The server scanner has a following QR frame and an inline attendance queue. The selected class and people are frozen for each scan session, completed people are excluded, and uncertain submissions need explicit retry.
- [x] The About Easter egg flips vertically as one face and springs back; the extra extrusion/plate is removed.
- [x] Brockmann's feedback controller is mounted for UI audio and haptics, with a persisted sound switch. Android silent/vibrate modes suppress audio.

## 3.8.6 interaction audit

- [x] Use consistent, unobtrusive chevrons for Settings/setup rows that open another page; leave switches and immediate actions plain.
- [x] Keep language and appearance choice labels consistently capitalized.
- [x] Prevent rapid taps from stacking Settings pages or completing setup twice during dismissal.
- [x] Accept late-loaded setup language/theme preferences without resetting a choice in progress.
- [x] Prevent an older sound preference read from overriding a newly saved choice.
- [x] Retry profile claim refresh independently after a successful username save.

Regression coverage includes delayed preference reads, duplicate completion,
profile partial failures, existing large-text layouts and the full app suite.

## 3.8.7 shared pass enrollment

- [x] Offer enrollment for every enabled shared pass, including the user's own pass.
- [x] Use the server's account-specific `/site/passes/{id}/code` and `/issue` endpoints.
- [x] Show the selected person's name and explain that verification uses the owner's MIREA method.
- [x] Refresh available passes after returning from enrollment; prevent duplicate enrollment pages.
- [x] Retain explicit code requests, leading-zero codes, rate-limit handling and read-back after uncertain issuance.

The server implementation was inspected at `aa-server` commit `f056554`.
App regression tests cover shared-pass targeting, disabled passes and 320dp
layouts at double text size. Real issuance still requires the owner's code.

## 3.8.8 enrollment action placement

- [x] Check enrollment state on pass-list refresh and retain only a boolean per account.
- [x] Hide enrollment for existing credentials, disabled passes and unknown status.
- [x] Place the action inside the pass row, vertically centered beside the name.
- [x] Cover automatic disappearance after issuance and alignment at 320dp with double text size.

## 3.8.9 theme and interaction details

- [x] Make shared WP8 inputs use charcoal Dark surfaces and pure black AMOLED surfaces, including disabled fields, text, hints and icons.
- [x] Keep visible theme borders and accent focus rings; verify contrast in all three modes.
- [x] Submit person search from the keyboard, accept pasted @usernames and clear stale errors when edited.
- [x] Remove dangling separators from pass and person metadata when a group is absent.
- [x] Prevent duplicate pass/search pages and accidental Back during explicit pass mutations.
- [x] Explain unavailable enrollment status and offer refresh as recovery.
- [x] Show loading state again when retrying profile loading.

Brockmann's shared input implementation and its theme regression tests were
updated together. The external Brockmann checkout is unchanged.

## 3.8.10 schedule and group selection

- [x] Keep week/group navigation consistent with displayed lessons after failed requests.
- [x] Make the schedule's group selector a single navigable row without a duplicate action label.
- [x] Prevent stacked group/map pages during rapid taps.
- [x] Clear stale group results on edit and ignore responses for previous queries.
- [x] Use keyboard Search, dismiss the keyboard on submission and align result text with the input.
- [x] Show group-search failures with the shared theme error color.
- [x] Avoid empty lesson metadata rows.

Regression tests exercise out-of-order group responses and failed week changes,
in addition to retained-day, small-screen and existing schedule coverage.

## 3.8.11 session server screen

- [x] Replace repeated addresses, explanations and stacked buttons with one server/sync overview.
- [x] Put Sync now and Open website in the WP8 command bar.
- [x] Move account counts and last-sync metadata behind Details.
- [x] Move address editing, connection checks and disconnect behind Connection settings.
- [x] Keep initial connection simple: one explanation, one address field, one Connect command.
- [x] Support keyboard Go, visible retry errors and guarded connection/browser actions.
- [x] Align the reading column with the page title and verify all themes at double text size.

Rendered shipping-font previews and regression tests cover both connected and
disconnected states. Installation of 3.8.10 could not run because ADB no longer
reported a connected Pixel; delivery is retried for the final release.

## 3.8.12 profile editing

- [x] Show field-specific validation beside name and username, clearing it when edited.
- [x] Keep inline error text readable against Dark and AMOLED input surfaces.
- [x] Support Next/Done keyboard actions and dismiss the keyboard during saving.
- [x] Offer Keep editing / Discard changes when leaving a modified profile.
- [x] Collapse an expanded WP8 command bar before considering an unsaved-edit prompt.
- [x] Keep the profile open while saving and avoid prompts after a successful save.
- [x] Keep an unsuccessful initial profile load out of the editor and offer Retry.
- [x] Preserve drafts across profile reloads and prevent duplicate device/sign-in pages.

The shared field adapter now exposes Brockmann's inline error support. The
command bar reports user presentation changes so page navigation can respect
its Back behavior. Regression tests exercise validation, failed loads,
unsaved drafts, expanded commands and in-flight saving.

## 3.8.13 disclosure indicators

- [x] Morph the plus into a minus by smoothly shortening the vertical stroke over 160ms.
- [x] Reverse continuously when tapped again before the animation finishes.
- [x] Keep the indicator frame and header tap area stable.
- [x] Snap to the final state under reduced motion.
- [x] Expose expanded/collapsed state to assistive technology without announcing decorative glyphs.

Focused tests cover intermediate frames, rapid reversal, reduced motion and the
profile/session-server screens that use the shared disclosure.
