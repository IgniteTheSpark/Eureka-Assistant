# Theme V2 Overdue and Rhythm Signals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Theme V2's persisted Reka signal lifecycle, timed-Todo overdue candidates, deterministic Period-based Rhythm profiles, and a dedicated read/dismiss API for the Overdue and Rhythm signal families.

**Architecture:** Create a bounded `app.domains.reka` domain. Live Todo/Asset state remains authoritative; `rhythm_profiles` stores daily deterministic learning results, while `nudges` stores delivery and dismissal state keyed by a natural identity. `/api/reka/signals` gathers Overdue and Rhythm independently so one failed source does not hide the other. Report signals and the mobile Home repository migration are explicitly left for the next slice so the existing Report surface does not regress during this backend rollout.

**Tech Stack:** FastAPI, Pydantic v2, SQLAlchemy 2 async, Alembic, MySQL 8 JSON/DATETIME(6), pytest/pytest-asyncio, Python `zoneinfo` and `statistics` only.

## Global Constraints

- Use `Asset.created_at` in the requested/default local timezone for Rhythm learning; never learn exact hours or use `occurred_at`.
- Normalize Rhythm to exactly five Period values: `凌晨`, `上午`, `中午`, `下午`, `晚上`.
- Keep the 28-day lookback, minimum five samples, deterministic computation, and a confidence gate of `0.45` inherited from the established implementation.
- Exclude `todo` and `event` from Rhythm learning.
- Only unfinished Todos with an ISO date-time `due_date` can become overdue.
- Overdue occurrences expire exactly 72 hours after `due_at`; completion or reschedule removes them live; dismissal suppresses only the matching `todo_id + due_at` occurrence.
- Rhythm dismissal suppresses `user + skill + pattern_key` until three consecutive expected cycles after dismissal contain matching records; a missed expected cycle resets the streak.
- Pulling signals must not create Notification rows or consume push caps.
- This slice does not migrate Report signals or change Flutter Home to consume `/api/reka/signals`.

---

## File Structure

- Create `theme_v2_service/app/domains/reka/models.py`: `Nudge` lifecycle and `RhythmProfile` persistence.
- Create `theme_v2_service/app/domains/reka/periods.py`: local Period classification and second-half eligibility boundaries.
- Create `theme_v2_service/app/domains/reka/rhythm.py`: pure pattern learning, cycle matching, gap eligibility, and three-cycle reactivation.
- Create `theme_v2_service/app/domains/reka/overdue.py`: Todo parsing and 72-hour overdue candidate generation.
- Create `theme_v2_service/app/domains/reka/schemas.py`: stable public signal/action response models.
- Create `theme_v2_service/app/domains/reka/service.py`: source isolation, lifecycle upsert/dismiss, ranking, and serialization.
- Create `theme_v2_service/app/domains/reka/api.py`: authenticated read and dismiss endpoints.
- Create `theme_v2_service/app/domains/reka/maintenance.py`: daily Rhythm recomputation and stale-nudge expiry scheduler.
- Create `theme_v2_service/migrations/versions/0019_reka_overdue_rhythm.py`: additive tables and indexes.
- Modify `theme_v2_service/app/main.py`, `app/worker.py`, and test metadata imports to register the domain.

### Task 1: Period and Rhythm Pure Model

**Files:**
- Create: `theme_v2_service/app/domains/reka/__init__.py`
- Create: `theme_v2_service/app/domains/reka/periods.py`
- Create: `theme_v2_service/app/domains/reka/rhythm.py`
- Test: `theme_v2_service/tests/unit/test_reka_periods.py`
- Test: `theme_v2_service/tests/unit/test_reka_rhythm.py`

**Interfaces:**
- Produces: `period_for_local(datetime) -> str`, `period_eligible(period, local_now) -> bool`.
- Produces: `compute_patterns(timestamps, timezone_name) -> list[RhythmPattern]`.
- Produces: `rhythm_gap_candidate(pattern, timestamps, now, timezone_name, dismissed_at) -> RhythmGap | None`.

- [ ] **Step 1: Write failing Period tests** for all five boundaries and verify exact timestamps collapse to Period only.
- [ ] **Step 2: Run RED:**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest tests/unit/test_reka_periods.py -q
```

Expected: import failure because `app.domains.reka.periods` does not exist.

- [ ] **Step 3: Implement Period helpers** with these fixed second-half boundaries:

```python
PERIOD_ELIGIBLE_AT = {
    "凌晨": time(3, 0),
    "上午": time(9, 0),
    "中午": time(12, 30),
    "下午": time(15, 30),
    "晚上": time(21, 0),
}
```

- [ ] **Step 4: Write failing Rhythm tests** covering five-sample cold start, one skill producing independent morning/afternoon patterns, stable daily any-Period, stable weekly weekday, no early gap, pattern-scoped completion, dismissal, three-cycle recovery, and streak reset.
- [ ] **Step 5: Run RED** and confirm failures are missing APIs rather than fixture errors.
- [ ] **Step 6: Implement deterministic learning** using local dates, median positive day gaps, Period groups, and stable keys:

```python
RhythmPattern(
    pattern_key="daily:上午",
    cadence="daily",
    period="上午",
    weekdays=(),
    confidence=0.5,
    sample_n=5,
)
```

Period groups with at least five samples are evaluated independently. Median local-day gap `<= 2` is daily; `5 <= gap <= 9` plus a dominant weekday is weekly. If no Period group passes and the overall series passes, emit one `period=None` pattern. Confidence combines sample size and gap regularity and must meet `0.45`.

- [ ] **Step 7: Implement cycle evaluation and reactivation** without mutable counters. Daily cycles are local dates; weekly cycles are ISO weeks. Only complete expected cycles strictly after `dismissed_at` count, and the latest three expected cycles must all match.
- [ ] **Step 8: Run GREEN** for both unit files.

### Task 2: Persisted Lifecycle and Migration

**Files:**
- Create: `theme_v2_service/app/domains/reka/models.py`
- Create: `theme_v2_service/migrations/versions/0019_reka_overdue_rhythm.py`
- Modify: `theme_v2_service/tests/conftest.py`
- Modify: `theme_v2_service/tests/integration/test_migrations.py`
- Test: `theme_v2_service/tests/integration/test_reka_models.py`

**Interfaces:**
- Produces: `Nudge(user_id, natural_key, kind, ref, status, delivered_at, acted_at, dismissed_at, expires_at)` with unique `(user_id, natural_key)`.
- Produces: `RhythmProfile(user_id, skill, timezone_name, patterns_json, computed_at)` with primary key `(user_id, skill)`.

- [ ] **Step 1: Write failing model and migration assertions** for columns, natural-key uniqueness, JSON patterns, and indexes.
- [ ] **Step 2: Run RED** against the integration tests.
- [ ] **Step 3: Add SQLAlchemy models and migration** using MySQL `DATETIME(6)`, `JSON`, `CHAR(36)`, and explicit indexes for `(user_id, status)`, `(user_id, kind, ref)`, and profile lookup.
- [ ] **Step 4: Register model imports** in test metadata so `Base.metadata.create_all()` includes both tables.
- [ ] **Step 5: Run GREEN** for model and migration tests.

### Task 3: Overdue Source and Occurrence Lifecycle

**Files:**
- Create: `theme_v2_service/app/domains/reka/overdue.py`
- Test: `theme_v2_service/tests/unit/test_reka_overdue.py`
- Test: `theme_v2_service/tests/integration/test_reka_overdue_lifecycle.py`

**Interfaces:**
- Produces: `collect_overdue_candidates(session, user_id, now, timezone_name) -> list[OverdueCandidate]`.
- Candidate natural key: `overdue:<todo_id>:<due_at_utc_z>`.

- [ ] **Step 1: Write failing pure tests** for explicit datetime, date-only exclusion, unfinished filtering, immediate eligibility after deadline, and exact 72-hour expiry.
- [ ] **Step 2: Run RED.**
- [ ] **Step 3: Implement robust Todo parsing**: timezone-aware strings preserve their offset; naive ISO date-times use the requested local zone; bare dates and malformed values return no candidate.
- [ ] **Step 4: Write failing integration tests** proving completion removes the live candidate, reschedule replaces the identity, and dismissal of the old identity does not suppress the rescheduled occurrence.
- [ ] **Step 5: Implement the indexed Asset/UserSkill query and candidate projection.**
- [ ] **Step 6: Run GREEN** for Overdue unit and integration tests.

### Task 4: Rhythm Recompute and Persisted Suppression

**Files:**
- Modify: `theme_v2_service/app/domains/reka/rhythm.py`
- Create: `theme_v2_service/app/domains/reka/maintenance.py`
- Modify: `theme_v2_service/app/worker.py`
- Test: `theme_v2_service/tests/integration/test_reka_rhythm_profiles.py`
- Test: `theme_v2_service/tests/integration/test_reka_maintenance.py`

**Interfaces:**
- Produces: `recompute_rhythm_profiles(session, now, timezone_name) -> int`.
- Produces: `collect_rhythm_candidates(session, user_id, now, timezone_name) -> list[RhythmCandidate]`.
- Produces: `run_reka_maintenance_scheduler(stop_event, interval_seconds=1800)`.

- [ ] **Step 1: Write failing recompute tests** proving `created_at` is used, `occurred_at` is ignored, Todo/Event are excluded, multiple Period patterns persist, and stale profiles disappear after the 28-day window.
- [ ] **Step 2: Run RED.**
- [ ] **Step 3: Implement daily profile recomputation** as one transaction and retain the last valid profiles if computation raises.
- [ ] **Step 4: Write failing suppression integration tests** for dismissing a Rhythm pattern, remaining suppressed across future cycle identities, three completed cycles restoring eligibility, and a missed cycle resetting recovery.
- [ ] **Step 5: Implement live Rhythm collection** from persisted profiles plus current Assets; query the latest dismissed Nudge by `(user_id, kind='rhythm_gap', ref='<skill>:<pattern_key>')`.
- [ ] **Step 6: Implement failure-isolated scheduler** that recomputes at most once per local day and logs/retries without terminating the worker.
- [ ] **Step 7: Run GREEN** for Rhythm integration and maintenance tests.

### Task 5: Aggregation, Ranking, Dismiss API

**Files:**
- Create: `theme_v2_service/app/domains/reka/schemas.py`
- Create: `theme_v2_service/app/domains/reka/service.py`
- Create: `theme_v2_service/app/domains/reka/api.py`
- Modify: `theme_v2_service/app/main.py`
- Test: `theme_v2_service/tests/contract/test_reka_signals_api.py`
- Test: `theme_v2_service/tests/integration/test_reka_signal_service.py`

**Interfaces:**
- Produces: `GET /api/reka/signals?timezone=Asia/Shanghai`.
- Produces: `POST /api/reka/signals/{signal_id}/dismiss`.
- Response signal kinds: `rhythm_gap`, `overdue`.

- [ ] **Step 1: Write failing API tests** for authentication, owner scoping, stable response schema, dismiss idempotence, and invalid timezone validation.
- [ ] **Step 2: Write failing service tests** proving source isolation, natural-key idempotence, ranking Rhythm before Overdue, no Notification creation, and stale completed/rescheduled targets being filtered.
- [ ] **Step 3: Run RED.**
- [ ] **Step 4: Implement source isolation** with one `try/except` per collector; return `partial_failures` while preserving healthy candidates.
- [ ] **Step 5: Upsert lifecycle rows** only for active candidates. Reuse existing rows by natural key; never reactivate a dismissed occurrence.
- [ ] **Step 6: Serialize type-specific actions**:

```json
{"kind":"rhythm_gap","target":{"type":"skill","id":"breakfast"},"actions":["open","dismiss"]}
{"kind":"overdue","target":{"type":"asset","id":"todo-id"},"actions":["open","complete","reschedule","dismiss"]}
```

- [ ] **Step 7: Run GREEN** for contract and integration tests.

### Task 6: Regression and Runtime Verification

**Files:**
- Modify only if a regression is found in files already in this plan.

- [ ] **Step 1: Run the complete Reka suite:**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest tests/unit/test_reka_*.py tests/integration/test_reka_*.py \
  tests/contract/test_reka_*.py -q
```

- [ ] **Step 2: Run affected Theme V2 suites:**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest tests/unit/test_todo_deadline.py \
  tests/contract/test_timeline_api.py tests/integration/test_migrations.py \
  tests/integration/test_trigger_consumption.py -q
```

- [ ] **Step 3: Rebuild the Theme V2 API/worker and migrate the independent Docker database.**
- [ ] **Step 4: Inspect OpenAPI** for `/api/reka/signals` and query the live schema for `nudges` and `rhythm_profiles`.
- [ ] **Step 5: Seed one overdue Todo and one eligible Rhythm profile in the test database, call the authenticated endpoint twice, and verify stable IDs/no duplicate lifecycle rows.**
- [ ] **Step 6: Document the next slice:** Report candidate adapter plus Flutter Home/Inbox migration and true-device actions.
