# Theme V2 Agenda, Reka, and Calendar Regression Fixes

**Goal:** Align the Theme V2 Home agenda and Reka modules with their product boundaries, and make Calendar drill-down navigation explicit and consistent.

**Status:** Completed and verified on 2026-08-04.

## Requirements

- [x] Home Agenda renders only events and todos.
- [x] Every todo displays its time and uses completion itself as the state; no separate status label is shown.
- [x] Home Reka contains only unread assistant discoveries, reminders, and report states defined by the notification allowlist; ordinary todos and capture receipts are excluded.
- [x] Reka records use one consistent 56 px row height.
- [x] Calendar expand and collapse use the same 44 px control.
- [x] Calendar title and content have explicit spacing.
- [x] Day Detail hides the bottom dock and provides an explicit return to Calendar.
- [x] Schedule Detail hides the bottom dock and provides an explicit return to Day Detail.

## Architecture Boundaries

- Agenda filtering belongs to the Today/Home read-model boundary; it must not change backend asset types.
- Reka is notification-backed and fail-closed through an explicit allowed-type set.
- Nested calendar pages use ordinary Navigator routes and top back actions; the global dock remains exclusive to primary shell pages.

## Verification

- [x] Focused Home, Today, Calendar, navigation, and golden suites passed.
- [x] Full Flutter suite passed: 704/704.
- [x] Focused production analysis reported no issues.
- [x] Physical-device navigation and layout acceptance passed on the connected Samsung device.
