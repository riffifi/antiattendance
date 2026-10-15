# UI audit · 15 October 2026

Source review covers every app screen and every dialog/sheet entry point below.
The design remains monochrome and typography-led. Familiar utility actions may
use small Phosphor icons; destinations and primary actions retain text labels.
Icons retain localized tooltips, accessibility labels, focus, and 48-pixel targets.

## Screens

| Screen / states | Findings and outcome |
| --- | --- |
| Selector and left navigator | Retained continuous label morph, vertical snapping, haptics, reduced motion and system insets. |
| Attendance: empty, populated, selected, filtered, busy, expired/error | Retained ruled account layout; shared checks and menu surfaces clarified; input dialogs support keyboard submission and reject blank values. |
| Schedule: no group, loading, failed, empty day, lessons/current lesson | Previous/next use directional icons; time column accommodates enlarged text. Retained readable lesson metadata and native localized date picker. |
| Passes: empty, enrollment, queue, single, running, unsupported/error | Clear checkmarks; bounded widget action row. Verification dialog scrolls and supports keyboard submission. NFC lifecycle unchanged. |
| Settings: embedded and standalone | Safe bottom inset, clear selection, shared sheet improvements. Existing monochrome previews and responsive theme controls retained. |
| Legacy local-account view | Available from Settings; retains local login, recovery and transfers using the audited navigation and controls. |
| Group picker: initial, searching, results, empty, error | Search icon; explicit initial/no-result guidance. Clearing a pending short query resets the spinner and ignores stale results. |
| Maps: loading/failure, search, favorites, filters, floor/map, route | Compact refresh/clear actions. Starting-place picker now scrolls its entire header/results area above the keyboard. Existing zoom, route instructions and floor controls retained. |
| Single sign-in: loading/error, QR, browser, session feedback | Back icon, safe system navigation inset; diagnostic sheet scrolls. Browser and QR authentication behavior retained. |
| Batch sign-in: overview, QR, browser, completed/error | Back icon, safe bottom inset, scrollable leave confirmation and responsive numeric count dialog. |
| Session recovery: checking, valid, expired, failed, restoring | Shared list constrains long retry/sign-in buttons so names remain readable. Existing bounded scrolling and footer retained. |
| QR export: preparing/error, frames, transfer code | Safe bottom inset; lighter headings consistent with the type hierarchy. QR keeps its white background and adaptive size. |
| QR import: camera/error, frames, code/error, review | Consistent review heading; existing camera overlay safe areas and scrollable code/review retained. |
| Nearby export: discovery/error, receivers, sending/results | Safe bottom inset and shared selection controls. Existing scrollable receiver list retained. |
| Nearby import: starting/error, waiting, received/review | Safe bottom inset, lighter headings, scrollable error/retry; retry creates a fresh receiver and cleans up the previous subscription. |
| Queue scanner: live camera/error, pending, sending, complete | Compact close/torch actions; existing camera overlay safe areas and scrolling status list retained. |
| Study summary: loading, empty, failed, populated/expired | Failed load has a retry action; existing bounded, separated summary panels retained. |
| Session server: initial/configured, connecting, connected/error | Existing safe, bounded settings column and explicit progress/errors retained; shared back control improved. |
| NFC diagnostics: unsupported, starting, scanning, detected/error | Safe bottom inset and lighter headings; existing flexible technical values retained. |
| Turnstile probe: unavailable/error, listening, field/events | Safe bottom inset and consistent headings; existing retry and event list retained. |
| Debug menu: loading/error, report, expanded sections, tools | Compact refresh/copy actions free header space. Existing redacted report and lazy disclosures retained. |
| Updates: checking, current, available, downloading/error | Compact refresh, safe bottom inset; removed decorative update-card shadow. Existing progress and installation footer retained. |
| About: version/loading, logo interaction, repository failure | Back icon and safe bottom inset. Retained bounded scroll, responsive branding and reachable repository footer. |

## Dialogs, sheets and menus

All custom sheets now share a bounded 640-pixel surface, a subtle drag indicator,
an explicit accessible close action, keyboard-aware padding and safe bottom inset.
Existing predictive-back cancellation/commit behavior remains active. Small
column-based menus explicitly scroll; list-based pickers keep their own scrolling.
Every app-authored AlertDialog now scrolls its title/content on constrained screens.

| Entry point | Review / change |
| --- | --- |
| Daily admin testing password | Scrollable obscured field, keyboard submission, localized labels; requires the separate daily server password. |
| New account name | Scrollable input; blank submission disabled; keyboard submit. |
| Rename account | Same input behavior; existing maximum length and initial value retained. |
| Paste attendance QR / paste lesson QR | Same input behavior; QR validation retained. |
| Add accounts: single/multiple | Scrollable menu; existing platform support handling retained. |
| Number of batch users | Scrollable dialog; flexible count area prevents narrow-screen overflow. |
| Delete account confirmation | Scrollable content; explicit Cancel/Delete retained. |
| Attendance actions menu | Shared bounded, scrollable, dismissible action sheet. |
| Account actions menu | Same shared surface; text labels retained for consequential actions. |
| Account detail sheet | Same shared surface; wrapped counters retained. |
| Export method: nearby/QR | Scrollable method sheet. |
| Import method: nearby/QR | Scrollable method sheet. |
| Batch login leave confirmation | Scrollable explanatory content; Stay/Finish retained. |
| Login session diagnostics | Scrollable sheet; session values remain hidden. |
| NFC verification, including invalid-code retry | Scrollable dialog; six-digit validation and keyboard submit. |
| Bulk pass enrollment | Header/scrolling account list/action retained within bounded sheet. |
| Pass removal menu | Shared compact sheet; account context retained. |
| Pass usage guide | Existing scrollable guide retained within shared sheet. |
| Own-account / single-pass pickers | Shared picker with checkmarks and disclosure caret. |
| Lesson details / confirmations / scan / paste / room action | Existing scrollable content and wrapped confirmations retained. |
| Schedule group menu | Shared bounded sheet; group labels retained. |
| Schedule date picker | Retained Flutter's localized accessible picker with the square monochrome app dialog theme. |
| Preferred group menu | Shared compact scroll surface. |
| Language menu | Shared compact scroll surface; localized labels retained. |
| Attendance and NFC launcher-widget previews | Shared sheet; preview sits below its option label so it cannot squeeze the label. |
| Map actions menu | Shared bounded sheet. |
| Campus picker | Shared bounded sheet. |
| Floor picker/menu | Shared bounded sheet; manual-floor explanation retained. |
| Starting-place search picker | Header and results now form one lazy scroll view. |
| Schedule room picker | Existing bounded list retained. |
| Route instructions | Existing bounded instruction list retained. |

## Verification and limits

Automated coverage includes narrow/landscape/tablet layouts, enlarged text, the
main destinations, supporting pages, QR transfer, map flows, launcher previews,
NFC lifecycle, predictive back, long row actions, keyboard-constrained sheets,
search cancellation, button geometry and reduced motion. The release APK is built
and installed on the Pixel according to `AGENTS.md`.

Source review is not a claim that every camera, browser, physical gate, network
discovery or notification outcome was reproduced on hardware. Those live states
still depend on devices, service availability and real account responses.

Developer is hidden until five separate downward swipes on the left rail while Attendance (01) is selected. The fifth swipe opens Developer (00), above Attendance in the rail. It remains available only in memory until the app closes. Settings and the logo provide no developer shortcut. The four-column selector stays unchanged.
