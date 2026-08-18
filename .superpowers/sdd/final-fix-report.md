# Final review fix report

Base: `0af9485a07b4effaff79d8dfe8e9f50e584e9b3e`

## Commits

- `180e32e` — `fix: harden report and skill backend contracts`
- `783f8ac` — `fix: preserve mobile refresh and report confirmations`
- `63131fe` — `docs: remove legacy design whitespace`
- `20b4f83` — `fix: confirm durable capture mutations and blockers`
- `74b114c` — `fix: preserve queued library and today state`
- `f0fff1c` — `test: approve plain calendar baselines`
- `db0057f` — `fix: bind capture mutation evidence to current turn`
- `c9fd7ff` — `fix: audit capture mutation executions`
- `906b4dc` — `fix: confirm durable capture deletions`
- `8139092` — `test: assert calendar surface stays dither-free`

## Finding-by-finding evidence

| # | Implementation and compatibility | Focused RED/GREEN evidence | Commit |
|---|---|---|---|
| 1 | `reports/planner.py` and `planner_tools.py` load the exact, owner-scoped confirmed Asset IDs without per-Skill truncation, retain manual cross-Skill owners, derive template capabilities only from confirmed evidence owners, and validate output against that exact set. | RED: confirmed records past the per-Skill cap were absent and an unchecked Asset could be accepted. GREEN: `test_planner_receives_only_confirmed_assets_without_per_skill_cap_loss`, `test_planner_rejects_asset_not_in_confirmed_scope`, plus the presentation contract with unrelated built-ins. | `180e32e` |
| 2 | `mobile/lib/app_events.dart` bumps mutation revision only for explicit `confirmed_mutation` evidence, including a mutation receipt; lifecycle/capture/status events remain refresh-only. | RED: capture/session events advanced mutation revision without evidence. GREEN: `explicit mutation evidence advances the mutation revision` and `capture and session lifecycle events are refresh-only without evidence`. | `783f8ac` |
| 3 | `LibraryController` preserves a cached overview on background failure and coalesces an active refresh to at most one queued rerun, including requests arriving during that rerun. | RED: failure cleared the overview; the self-review edge test observed 3 loads instead of 2. GREEN: cached-failure, concurrent-refresh, and during-rerun tests pass. | `783f8ac` |
| 4 | Built-in protection is centralized in `is_system_skill`: catalog FK or protected normalized machine name (`todo`, `expense`, `contact`, `notes`, `event`, `qa`). Update, impact, and delete all use it. | RED: a protected name with a missing FK was editable/deletable. GREEN: protected-name update and deletion tests pass. | `180e32e` |
| 5 | `UserSkillRead.is_system` exposes authoritative provenance while keeping `global_skill_id` private. Mobile treats an explicit API boolean as authoritative, falls back to the legacy name catalog only when the field is absent, routes system Skills to card configuration, and custom Skills to management. Expense is covered. | RED: an Expense/system fixture routed through custom management. GREEN: asset API provenance assertions and `authoritative system provenance overrides custom container type`. | `180e32e`, `783f8ac` |
| 6 | Custom range boundaries serialize as UTC from mobile; backend `TimeRange` rejects naive datetimes and invalid ordering while accepting explicit non-UTC offsets. Scope-candidate query parameters require both boundaries. | RED: naive values validated and mobile emitted local/no-offset boundaries. GREEN: naive-boundary parameter tests, non-UTC midnight test, API range contract, and mobile UTC serialization test. | `180e32e`, `783f8ac` |
| 7 | Selecting any range refetches authoritative server candidates using `from`/`to`. Server expansion sets `requires_reconfirmation`; prepare returns blocker `scope_reconfirmation_required` until the resolved list is submitted unchanged a second time. Mobile displays that final-list confirmation step. | RED: the client filtered the 30-day preview locally and proceeded directly to prepare. GREEN: custom-range API contract, server expansion integration test, range-refetch mobile test, and second-confirmation mobile test. | `180e32e`, `783f8ac` |
| 8 | `prepare_scope_plan` blocks any non-empty `missing_dimensions` with stable code `scope_dimensions_unresolved` before enqueueing. | RED: unresolved scope could enqueue planning. GREEN: `test_prepare_rejects_unresolved_required_scope_dimensions`. | `180e32e` |
| 9 | Full-list, record, group, and refetched-range rebuilds retain `excluded_reference_ids` until explicit reselection. Manual reselection also clears an exclusion left by an older range. | RED: group/range rebuilds lost exclusions; self-review test retained a stale exclusion after manual reselection. GREEN: both exclusion regression tests pass. | `783f8ac` |
| 10 | Custom Skill update locks the owned row before validating `expected_updated_at`, making revision validation and write atomic. | RED: with the lock temporarily absent, the two-session test failed with `DID NOT RAISE SkillUpdateConflict`. GREEN: `test_concurrent_skill_updates_serialize_revision_check`. | `180e32e` |
| 11 | Backend validates complete or legacy-shorthand schemas: object/properties shape, snake_case IDs, supported scalar/array types, supported formats, array items, required references, and optional-only new fields. Mobile mirrors key/type checks and emits valid default array items. Legacy shorthand remains accepted, including valid fields named `type`, `properties`, or `required`. | RED: malformed schemas and new required fields were accepted; mobile accepted invalid keys/types. GREEN: malformed-schema parameter cases, API 422 contract, optional-only test, legacy-keyword compatibility test, and mobile controller validation tests. | `180e32e`, `783f8ac` |
| 12 | Deletion impact returns `confirmation_token` plus compatibility alias `revision`. DELETE requires the token, locks/recounts, returns stable `stale_delete_confirmation` on changed impact, and returns the actual deleted count. Mobile passes the token, clears stale confirmation state, requires reconfirmation, accepts either token field, and uses the DELETE result count. | RED: deletion accepted no/stale confirmation and the client reused the preview count. GREEN: API token/staleness contract and mobile token/actual-count/reconfirmation tests. | `180e32e`, `783f8ac` |
| 13 | Presentation candidates never escape `TemplateRegistry.candidates_for` compatibility. Standard families block with `presentation_incompatible`; custom text maps deterministically by a fixed hint catalog or blocks with `custom_presentation_unresolved`. Prepare preflights and exposes stable 409 `{code,message}` detail. | RED: incompatible family fell back to a same-family template outside the compatible set; registration built-ins also inflated capabilities. GREEN: incompatible-family, deterministic-custom, and API blocker contract tests. | `180e32e` |
| 14 | `ThemeV2AssetBubbleField.didUpdateWidget` prunes consumed spawn state and diameter caches to current Asset IDs. | RED: a removed/re-added Asset reused the old body position (`37` instead of the new handoff near `300`). GREEN: `removed asset IDs can consume a new spawn handoff when re-added`. | `783f8ac` |
| 15 | Removed the two reported trailing-space line endings from the older approved design document. | Inspection RED: Date/Status lines ended in two spaces. GREEN: `git diff --check` is clean. | `63131fe` |

## Final re-review evidence

| # | Implementation and compatibility | Focused RED/GREEN evidence | Commit |
|---|---|---|---|
| 1 | `NotificationCreate` carries non-persisted evidence into the transactional outbox, and `NotificationPayload` adds `confirmed_mutation: true` only when that committed outbox event contains the evidence. Capture intersects referenced Asset/Event IDs with successful, committed create/update/delete `AgentToolExecution` results for the same owner and current input turn, then verifies durable row presence for create/update or durable absence for delete. This confirms real writes while Q&A, status, no-record, phantom-reference, and unexecuted pre-existing references remain refresh-only. The mobile event consumer accepts the additive field while old payloads remain byte-shape compatible because false/absent is omitted. | RED: schema/outbox/capture tests showed no confirmed mutation path; self-review proved a referenced pre-existing Asset was incorrectly confirmed; independent review then proved entity-creation provenance would miss legitimate updates and excluding deletes would leave mutation-only mobile listeners stale. GREEN: notification schema and committed-outbox serialization tests, durable create/update/delete/Q&A/phantom/pre-existing integration tests, and backend-JSON mobile consumption tests pass. | `20b4f83`, `74b114c`, `db0057f`, `c9fd7ff`, `906b4dc` |
| 2 | Replaced exactly 28 Calendar golden masters after visual inspection of every light/dark Flow, month, year, day, schedule, and manual-picker image. Both Timeline tests now assert that the plain Calendar/new shell contains neither `ThemeV2DitherSurface` nor `ThemeV2DitherField`, including every surface transition in the first test. | RED: the old Timeline tests required Dither and the full Flutter run reported the 28 stale Calendar comparisons. GREEN: golden update 28/28, Calendar suite 152 passed, focused Timeline 2 passed, and the full Flutter suite passed. | `f0fff1c`, `8139092` |
| 3 | `LibraryController` now drains a coalesced load queue until the latest pending request has received a rerun. Calls arriving during one rerun coalesce into one following load instead of being cleared and lost. | RED: a request during the queued rerun left `loadCount == 2`. GREEN: the replacement test observes exactly one third load and the latest empty result. | `74b114c` |
| 4 | Cached-refresh and partial retry UI moved from `LibraryHub` to the shared `ThemeV2LibraryPage` shell, above the active surface, so index/all/configuration views keep their context and expose the same retry action. | RED: a failed refresh on Container Index had no retry banner. GREEN: the non-hub navigation widget test keeps Container Index visible and finds the shared message and retry action. | `74b114c` |
| 5 | `prepare_scope_plan` maps `PlannerContextTooLarge` to HTTP 409 `RunBlocked` with stable code `scope_context_too_large` and actionable range/record reduction guidance, before any planner job is enqueued. | RED: the exception escaped the API contract. GREEN: the API test asserts the exact structured detail and zero planner jobs. | `20b4f83` |
| 6 | Custom Skill creation rejects normalized protected machine names at the service boundary before schema/global baseline provisioning, and the API maps that specific conflict to HTTP 409. Direct pre-baseline POST is covered; legacy protected rows are still readable and tested by explicit historical-data seeding. | RED: POST-before-list reached persistence instead of a stable protected-name conflict. GREEN: the exact 409 detail contract passes, and adjusted service/proactive integration coverage passes without weakening the service guard. | `20b4f83` |
| 7 | The Today parent prunes `_assetSpawnStates` against the current pool at the start of reconciliation, complementing the child cache pruning from finding 14. | RED: removing an Asset left the parent's handoff entry available for re-add. GREEN: the widget test removes the Asset, observes an empty parent map, re-adds it, and proves the old handoff is not reused. | `74b114c` |

## API migration and compatibility notes

- `GET /api/user-skills` adds `is_system: bool`; existing fields are unchanged. Mobile falls back to the protected-name catalog only when an older server omits this field.
- `GET /api/user-skills/{id}/deletion-impact` adds `confirmation_token` and identical `revision`. Mobile accepts either spelling.
- `DELETE /api/user-skills/{id}` now requires `confirmation_token`. This intentional safety migration makes old unconfirmed delete calls return 422. A stale token returns HTTP 409 with `detail.code == "stale_delete_confirmation"`.
- Custom Skill create/update schema errors return HTTP 422 with structured `detail.code == "invalid_skill_schema"` (or the existing specific update conflict code). Legacy property-map schemas remain accepted.
- `GET /api/report-generation-runs/{id}/scope-candidates` accepts optional paired `from`/`to` values with explicit offsets. Omitting both keeps the old behavior.
- Scope confirmation responses may add `pending_decision.requires_reconfirmation`. Old clients can ignore the additive field, while prepare still fails safely with HTTP 409.
- Stable prepare blockers use HTTP 409 and `{ "detail": { "code", "message" } }`: `scope_dimensions_unresolved`, `scope_reconfirmation_required`, `presentation_incompatible`, and `custom_presentation_unresolved`.
- Live notification payloads may add `confirmed_mutation: true` after a committed capture durably creates, updates, or deletes an Asset/Event. The field is omitted for older notifications and all refresh-only events, so old clients and exact legacy payload shapes remain compatible.
- Protected custom Skill names now return HTTP 409 with `detail.code == "system_skill_protected"`, including before the first catalog/list request provisions baseline Skills.
- Oversized confirmed report scope now returns HTTP 409 with `detail.code == "scope_context_too_large"` and an actionable message.

No database migration is required.

## Verification results

Fresh final re-review commands after the last production-code change:

- Full backend, first diagnostic run: **865 passed, 9 failed, 2 warnings in 336.50s**. Every failure was an older integration fixture creating a newly protected `notes`/`contact` custom Skill through the service. Ordinary fixtures now use a custom name; the migration test explicitly seeds a legacy row.
- Protected-name regression slice after the fixture correction: **23 passed, 1 warning in 18.67s**.
- Full backend before the final self-review hardening: **874 passed, 2 warnings in 251.60s**.
- Pre-existing-record evidence RED/GREEN: **1 failed as expected**, then the four durable/Q&A/phantom/pre-existing capture cases → **4 passed, 1 warning in 3.41s**.
- Real update evidence RED/GREEN: both Asset and Event update cases failed as expected, then the six durable create/update and refresh-only cases → **6 passed, 1 warning in 5.51s**.
- Real delete evidence RED/GREEN: both Asset and Event delete cases failed as expected, then the eight durable create/update/delete and refresh-only cases → **8 passed, 1 warning in 7.31s**.
- Final full backend after all execution-audit evidence: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest -q --disable-warnings` → **879 passed, 2 warnings in 349.53s**.
- Notification/report/protected-name focused backend slice: **63 passed, 23 warnings in 44.79s**.
- Strengthened Today/Library/Calendar Timeline widget slice: **47 passed**; the wider affected mobile slice was **64 passed**.
- Calendar suite: `flutter test test/theme_v2/calendar` → **152 passed**.
- Focused Timeline after explicit Surface assertions: **2 passed**.
- Golden update command covering the two Calendar golden test files → **28 passed**, and the changed-master count is exactly **28**.
- Final full mobile after the assertion-only strengthening: `flutter test` → **1078 passed (58s)**.
- Final changed mobile sources/tests: `flutter analyze` with all 9 changed Dart paths → **No issues found (13.0s)**.
- `git diff --check` → clean before report generation.

## Remaining limitations

- The bundled `chiplet_ring` example analyzer fixture remains broken independently of these changes.
- No device install or build was run, per the Task 7 handoff requirement.
