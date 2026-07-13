# Final whole-branch review fix report

## Status

PASS — all findings in `final-fix-brief.md` are implemented and the required focused verification is green.

## Commit

- Final fix commit: this commit (`fix: complete event attendee review findings`); the exact hash is reported in the agent handoff after commit creation.
- Base HEAD: `2dfd13b`.

## Changes

- Timeline events now batch-load deterministically ordered attendees and owned contacts, serialize attendees through the existing shared `_event_attendee_to_dict`, and expose the full event payload.
- Flutter retains the event payload and derives `TimelineItem.subtitle` through canonical `eventCardSummary`.
- Contact search retains `contacts` contains results and adds normalized `exact_contacts`; Flash binds only the exact set.
- Contact deletion preserves attendee fallback names and detaches contact IDs in the same transaction; contact-only attendee creation now persists the contact name in `name_raw`.
- The selector footer shows horizontally scrollable compact selected-name chips without avatars while keeping `保存(N)` fixed.
- Event list, detail, timeline, and deletion attendee queries use `created_at ASC, id ASC`.

## TDD evidence

### RED

- `python3 backend/scripts/test_event_attendee_contract.py` failed with `missing attendee helpers: ['_detach_event_attendee_contact']`.
- `python3 backend/scripts/test_timeline_event_attendees_contract.py` failed at `assert "EventAttendee" in source`.
- `python3 backend/scripts/test_flash_event_attendees_contract.py` failed because the skill still used `contacts[0]` instead of `exact_contacts[0]`.
- `flutter test test/timeline_event_summary_test.dart test/event_attendees_test.dart` failed with timeline subtitle actual `会议室` vs expected `14:00–15:00 · 会议室 · Alex +1`, and no footer `Footer Alex` widget.
- The follow-up trim contract failed because `query_contact` did not yet define stripped `search_query`.

### GREEN

- Backend attendee, event-card, Flash exact-match, and timeline contracts all print `ok`.
- Focused Flutter attendee/card/timeline suite reports `+40: All tests passed!`.
- Focused analysis reports `No issues found!`.

## Verification

- Dart format: 4 changed files checked, 0 further changes.
- Backend contracts:
  - `test_event_attendee_contract.py` — PASS
  - `test_event_card_contract.py` — PASS
  - `test_flash_event_attendees_contract.py` — PASS
  - `test_timeline_event_attendees_contract.py` — PASS
- `PYTHONPYCACHEPREFIX=/tmp/eureka-pycache python3 -m py_compile backend/mcp_server/tools.py backend/api/contacts.py backend/core/timeline.py` — PASS.
- `flutter test test/event_attendees_test.dart test/event_card_summary_test.dart test/timeline_event_summary_test.dart` — PASS, 40 tests.
- `flutter analyze lib/pages/event_attendees.dart lib/timeline/timeline.dart test/event_attendees_test.dart test/timeline_event_summary_test.dart` — PASS, no issues.
- `git diff --check` — PASS.

## Self-review

- API compatibility: existing event keys and `contacts` are retained; `payload` and `exact_contacts` are additive.
- Attendee shape: timeline uses the same seven keys as event APIs through the shared serializer.
- Query behavior: attendee and contact enrichment remains batched, with no per-event/per-attendee query loop.
- Delete safety: fallback assignment and unlinking occur before `db.delete(c)` and within the same session/commit.
- Scope: no spec/docs/deprecated frontend files changed; untracked `tmp/` was not touched.

## Concerns

- The local Python environment does not have runtime packages such as SQLAlchemy/FastMCP installed, so an import-level backend smoke test was unavailable. The required source contracts and `py_compile` gate pass.
- Flutter emits the existing dependency-update and iOS Swift Package Manager warnings; focused tests and analysis are clean.

## Follow-up: runtime Flash examples exact-match consistency

Status: PASS. Commit: follow-up commit reported in the agent handoff.

TDD evidence:

- RED: the strengthened full-runtime contract first failed because the customer example omitted `exact_contacts`; a second binding-source assertion then failed on the Feng example's literal `name`/`contact_id`, proving bound calls were not yet consistently sourced from `exact_contacts[0]`.
- GREEN: `test_flash_event_attendees_contract.py` passes after every Step 3b/Examples contact-query response exposes both arrays, every binding call uses `exact_contacts[0]`, Kevin demonstrates multiple contains with one exact binding, Alex/Alexander demonstrates zero exact remaining unbound, and two exact Liu rows remain unbound.

Verification:

- Flash attendee safety contract — PASS.
- Event attendee, event card, and timeline attendee contracts — PASS.
- `py_compile` for the changed Python contract — PASS.
- `git diff --check` — PASS.

Self-review / concern:

- Notes now state that only one exact contact may bind; runtime actual call lines are scanned with a negative-lookbehind regex that rejects bare `contacts[0]` without rejecting `exact_contacts[0]`.
- Per reviewer direction, the existing Minor `core.timeline` → private MCP serializer dependency is intentionally retained for this follow-up rather than expanded into a riskier refactor.
