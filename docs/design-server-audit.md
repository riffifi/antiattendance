# WP8 design and server integration audit

AA 3.8.0+44 builds on the existing WP8 edits in this working tree. Geist,
light/dark/AMOLED, the title/content gutter distinction, compact app-bar states,
and the About Easter egg are retained.

AA 3.8.1+45 distinguishes charcoal dark pages (#181818) and application bars
(#292929) from pure-black AMOLED surfaces. Material surface tokens use the same
neutral palette. WP8 section tabs use text hierarchy instead of filled segments.
Maps use typographic campus/floor selectors and categories, square icon zoom
controls, and the shared draggable application bar. The navigation inset belongs
to that bar, with Android's automatic contrast scrim disabled.

## Design corrections

- App-bar command groups stay centered, with dedicated space on both edges.
  The corner ellipsis no longer overlaps the fourth command at 320 dp.
- QR paste, daily results and calendar commands use bundled Phosphor SVGs.
- A single active class is presented once; the class selector appears only when
  the server offers multiple eligible classes.
- Schedule dates use the phone's locale. Pass permissions use quiet explanatory
  copy and flat list rows. Account name and exact username are editable.
- Reduced motion no longer disables the entire Navigator ticker tree. Brockmann
  keeps its reduced-motion presentation and bounded transition durations, while
  route completion and progress remain functional.
- Native server screens are checked at 320 dp, normal and double text sizes in
  light/dark themes, with real view rendering for visual inspection. Group names,
  long subjects, empty/error states and scrollable lists retain their hierarchy.

## Server contract

Verified against riffifi/aa-server commit 28ab0f1, advertised by the live server
as version 2.2.2. Sources:

- https://github.com/riffifi/aa-server/blob/28ab0f1/docs/client-api-migration.md
- https://github.com/riffifi/aa-server/blob/28ab0f1/docs/API.md

The production entry point uses ServerWorkspace and the shared JSON operations:
server QR job creation/status/one-time claim, AA ID refresh/devices, class state,
class-scoped marks, daily results, schedules/search, and pass permissions.
Known retired deployment URLs migrate to aa.ytc-srv.org / aaid.ytc-srv.org;
custom addresses remain configurable. Tokens stay in secure storage. The QR job
capability is held only in memory. A failed server handoff is explicitly shown.

Native metadata snapshots do not require a passes array. Auto-sync stops before
legacy cookie/group/pass upload logic when that contract is detected. Historical
local workflows remain isolated from the production shell for compatibility;
there is no raw Pulse RPC fallback from the new main screens.

Attendance submissions use explicit authorized account IDs from the visible
group filter and the selected lesson_start. Hidden selections are not submitted. A context conflict refreshes the view without resubmitting. Lost
mutation responses are never automatically retried. Per-person failures remain
visible. Daily results and notifications index marks by both account and lesson;
missing marks remain missing, and external journal strings are supported.

The server removed digital NFC issue/token/verification endpoints. Passes now
manages the owner's switch, grants, revocations, incoming decisions and outgoing
requests. It does not advertise NFC activation or Telegram approval. The normal
attendance launcher shortcut is retained; the former NFC shortcut opens Passes.

## Validation limits

Public version/health endpoints were checked without credentials. No real
attendance marks, pass grants, login approvals or account edits were performed.
The tests use synthetic accounts and responses. End-to-end university approval,
real attendance and phone lock state are reported separately at delivery.
