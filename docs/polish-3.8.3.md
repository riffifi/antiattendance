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
