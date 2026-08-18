# Final review fix report

Base: `0af9485a07b4effaff79d8dfe8e9f50e584e9b3e`

## Commits

- `180e32e` — `fix: harden report and skill backend contracts`
- `783f8ac` — `fix: preserve mobile refresh and report confirmations`
- `63131fe` — `docs: remove legacy design whitespace`

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

## API migration and compatibility notes

- `GET /api/user-skills` adds `is_system: bool`; existing fields are unchanged. Mobile falls back to the protected-name catalog only when an older server omits this field.
- `GET /api/user-skills/{id}/deletion-impact` adds `confirmation_token` and identical `revision`. Mobile accepts either spelling.
- `DELETE /api/user-skills/{id}` now requires `confirmation_token`. This intentional safety migration makes old unconfirmed delete calls return 422. A stale token returns HTTP 409 with `detail.code == "stale_delete_confirmation"`.
- Custom Skill create/update schema errors return HTTP 422 with structured `detail.code == "invalid_skill_schema"` (or the existing specific update conflict code). Legacy property-map schemas remain accepted.
- `GET /api/report-generation-runs/{id}/scope-candidates` accepts optional paired `from`/`to` values with explicit offsets. Omitting both keeps the old behavior.
- Scope confirmation responses may add `pending_decision.requires_reconfirmation`. Old clients can ignore the additive field, while prepare still fails safely with HTTP 409.
- Stable prepare blockers use HTTP 409 and `{ "detail": { "code", "message" } }`: `scope_dimensions_unresolved`, `scope_reconfirmation_required`, `presentation_incompatible`, and `custom_presentation_unresolved`.

No database migration is required.

## Verification results

Fresh final commands after the last production-code change:

- Full backend: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest -q --disable-warnings` → **869 passed, 2 warnings in 253.59s**.
- Affected backend slice: the eight changed contract/integration/unit files → **87 passed, 1 warning in 37.18s**.
- Affected mobile slice: the seven changed Flutter test files → **127 passed**.
- Changed mobile sources/tests: `flutter analyze` with all 17 changed paths → **No issues found**.
- Custom schema focused suite after the final legacy-compatibility RED/GREEN → **16 passed**.
- `git diff --check` → clean before report generation.

Additional project-wide checks:

- `flutter test` → **1046 passed, 30 failed**. All 30 failures are pixel comparisons in the unmodified Calendar golden suites (`theme_v2_calendar_golden_test.dart` and `theme_v2_manual_record_picker_golden_test.dart`); no changed/affected test failed.
- Project-root `flutter analyze` → **2 errors**, both in the unmodified `packages/chiplet_ring/example/test/widget_test.dart`: missing `package:chiplet_ring_example/main.dart` and the resulting missing `MyApp` type. The changed-file analysis is clean.
- Python `black`/`ruff` checks were attempted inside the test image, but neither module is installed. The full Python suite and `git diff --check` provide the available repository verification.

## Remaining limitations

- The existing Calendar golden environment must be reconciled separately; this task intentionally did not rewrite unrelated approved goldens.
- The bundled `chiplet_ring` example analyzer fixture remains broken independently of these changes.
- No device install or build was run, per the Task 7 handoff requirement.
