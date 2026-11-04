# AA frontend

AA keeps Brockmann's typographic, flat visual language. The presentation layer
lives in `lib/frontend/`; it receives data and callbacks rather than owning
credentials, network clients or NFC services.

- `attendance_page.dart` owns account search and the visible account list. Its
  host owns selection and submission. Select-all passes only the IDs visible
  after group and search filtering; hidden selections stay unchanged. The action
  dock wraps on narrow screens and with enlarged text.
- `attendance_account_row.dart` presents account identity, attendance counts,
  session status and account commands. Session validation and account mutations
  return to the host through callbacks.
- `schedule_calendar.dart` controls group, month, week and day selection. It
  receives the selected date and emits a new date. Large text can scroll the
  weekday strip; dates have full-date semantics. The schedule page retains
  loading, caching, attendance and map callbacks.
- `pass_status_panel.dart` displays queue or single-pass status. It never starts
  NFC. `NfcPassPage` continues to own enrollment, approvals, preferences, queue
  lifecycle and immediate service shutdown when leaving the destination.
- `settings_view.dart` lays out named sections, while `SettingsPage` owns settings
  persistence and navigation. Account/sync, appearance, daily tools, app details
  and diagnostics have separate sections.
- `page_layout.dart` defines the reading column, insets, section headings and
  empty states used by feature screens.

The shared `CampusScaffold` handles secondary routes and their adaptive headers.
`ScreenNavigation` preserves the application's page identities as the window
changes size. Existing API, storage, native channels and authentication flows
remain in their feature implementations.

Validation includes account/group selection, scan/paste submission, session
checks, schedule confirmations, NFC shutdown, settings persistence and layouts
with large text. `CAMPUS_PREVIEW_DIR` enables the existing test preview output
for visual inspection across themes.

## Metro frame

The compact pivot supplies the page's heading; feature headers retain useful
supporting text without repeating the display title. The shared Brockmann pivot
viewport supports content swipes while preserving a single keyed content tree.
Command docks and calendar strips keep ownership of gestures beginning in them.
The wider navigation list retains ordinary feature headings. See the vendored
[Metro implementation notes](../third_party/brockmann/docs/metro-audit.md).
