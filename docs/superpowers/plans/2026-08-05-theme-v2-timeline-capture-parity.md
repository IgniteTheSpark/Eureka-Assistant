# Theme V2 Timeline and Capture Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the legacy asset-time model, authoritative Timeline API, and capture-only Flash counts in the isolated Theme V2 stack.

**Architecture:** Store precise occurrence and fuzzy-period facts on assets, derive Timeline presentation on the service, and port the legacy deterministic time parser behind the bounded capture agent. Theme V2 Calendar consumes the authoritative Timeline response instead of reconstructing semantic time from raw records.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy 2, Alembic, Pydantic 2, pytest, Dart, Flutter.

## Global Constraints

- Do not proxy or start the legacy backend.
- Keep `created_at` as audit time.
- Never invent a clock for a fuzzy period.
- Flash count uses capture recordings only and excludes Flash chat messages.
- Preserve unrelated dirty worktree files.

---

### Task 1: Persist mature temporal facts

**Files:**
- Create: `theme_v2_service/migrations/versions/0012_asset_temporal.py`
- Modify: `theme_v2_service/app/db/models.py`
- Modify: `theme_v2_service/app/domains/assets/schemas.py`
- Modify: `theme_v2_service/app/domains/assets/service.py`
- Test: `theme_v2_service/tests/integration/test_migrations.py`
- Test: `theme_v2_service/tests/contract/test_asset_api.py`

**Interfaces:**
- Produces: `Asset.period: str | None`, `Asset.occurred_at: datetime | None`.
- Produces: `AssetCreate/AssetUpdate.period` and `.occurred_at`.
- Produces: asset JSON fields `period` and `occurred_at` as UTC `Z`.

- [ ] **Step 1: Write failing migration and API tests**

```python
assert {"period", "occurred_at"}.issubset(asset_columns)

created = await client.post("/api/assets", headers=_headers(owner), json={
    "user_skill_id": skill["id"],
    "payload": {"content": "昨天下午复盘"},
    "period": "下午",
    "occurred_at": None,
})
assert created.json()["period"] == "下午"
assert created.json()["occurred_at"] is None
```

- [ ] **Step 2: Run tests and verify RED**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test pytest tests/integration/test_migrations.py tests/contract/test_asset_api.py -q`

Expected: FAIL because the columns and response fields do not exist.

- [ ] **Step 3: Add migration, model fields, schemas, and UTC serialization**

```python
period: Mapped[str | None] = mapped_column(String(8))
occurred_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
```

Validate `period` against `{"凌晨", "上午", "中午", "下午", "晚上"}` and use the existing `_utc_naive` write helper.

- [ ] **Step 4: Run tests and verify GREEN**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/migrations/versions/0012_asset_temporal.py theme_v2_service/app/db/models.py theme_v2_service/app/domains/assets/schemas.py theme_v2_service/app/domains/assets/service.py theme_v2_service/tests/integration/test_migrations.py theme_v2_service/tests/contract/test_asset_api.py
git commit -m "feat(theme-v2): restore asset temporal metadata"
```

### Task 2: Port deterministic capture-time extraction

**Files:**
- Create: `theme_v2_service/app/domains/capture/temporal.py`
- Modify: `theme_v2_service/app/domains/capture/agent.py`
- Modify: `theme_v2_service/app/domains/capture/providers_litellm.py`
- Modify: `theme_v2_service/app/domains/capture/jobs.py`
- Test: `theme_v2_service/tests/unit/test_capture_temporal.py`
- Test: `theme_v2_service/tests/unit/test_capture_agent.py`
- Test: `theme_v2_service/tests/integration/test_capture_jobs.py`

**Interfaces:**
- Produces: `CaptureTemporalHints(period, occurred_at, anchor_date)`.
- Produces: `extract_temporal_hints(source_text, reference_datetime)`.
- Changes provider input from `local_date` to `reference_datetime`.
- Adds non-persisted `CaptureRecordCommand.source_text`.

- [ ] **Step 1: Write failing parser tests**

```python
REFERENCE = datetime(2026, 8, 5, 0, 13, tzinfo=ZoneInfo("Asia/Shanghai"))

def test_extracts_exact_relative_time():
    hints = extract_temporal_hints("刚刚喝了200ml", REFERENCE)
    assert hints.occurred_at == REFERENCE

def test_extracts_relative_day_clock():
    hints = extract_temporal_hints("昨天晚上8点喝了300ml", REFERENCE)
    assert hints.occurred_at.isoformat() == "2026-08-04T20:00:00+08:00"

def test_keeps_fuzzy_period_without_fake_clock():
    hints = extract_temporal_hints("昨天下午喝了600ml", REFERENCE)
    assert hints.anchor_date == date(2026, 8, 4)
    assert hints.period == "下午"
    assert hints.occurred_at is None
```

- [ ] **Step 2: Run parser test and verify RED**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test pytest tests/unit/test_capture_temporal.py -q`

Expected: import failure because `capture.temporal` does not exist.

- [ ] **Step 3: Implement the bounded parser and provider contract**

Port the legacy `_PERIOD_KEYWORDS`, relative-day resolution, `刚刚` handling,
and clock regex. The provider trusted config must include:

```python
{
    "reference_datetime": reference_datetime.isoformat(),
    "timezone": "Asia/Shanghai",
}
```

Require each generated record to include a transcript-grounded `source_text`.
Before persistence, fill only missing `period`/`occurred_at`; when a schema has
a date-formatted field, fill its date from `anchor_date` only if absent.

- [ ] **Step 4: Run capture unit and integration tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test pytest tests/unit/test_capture_temporal.py tests/unit/test_capture_agent.py tests/integration/test_capture_jobs.py -q`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/capture/temporal.py theme_v2_service/app/domains/capture/agent.py theme_v2_service/app/domains/capture/providers_litellm.py theme_v2_service/app/domains/capture/jobs.py theme_v2_service/tests/unit/test_capture_temporal.py theme_v2_service/tests/unit/test_capture_agent.py theme_v2_service/tests/integration/test_capture_jobs.py
git commit -m "fix(capture): restore deterministic time extraction"
```

### Task 3: Add the authoritative Timeline API

**Files:**
- Create: `theme_v2_service/app/domains/timeline/__init__.py`
- Create: `theme_v2_service/app/domains/timeline/service.py`
- Create: `theme_v2_service/app/domains/timeline/api.py`
- Modify: `theme_v2_service/app/main.py`
- Test: `theme_v2_service/tests/contract/test_timeline_api.py`

**Interfaces:**
- Produces: `GET /api/timeline` with the existing mobile `TimelineItem` shape.
- Produces: `effective_at_for_asset(asset, skill) -> datetime`.

- [ ] **Step 1: Write failing Timeline contract tests**

Create four water assets representing `刚刚`, exact `昨晚8点`, fuzzy
`昨天下午`, and fuzzy `昨天早上`. Assert:

```python
items = (await client.get("/api/timeline", headers=_headers(token))).json()["items"]
assert all(item["title"] != "daily_water_intake" for item in items)
assert exact["effective_at"] == "2026-08-04T12:00:00Z"
assert afternoon["period"] == "下午"
assert afternoon["has_clock_time"] is False
```

Also create three capture recordings and two `flash_chat_messages`; assert the
Timeline contains exactly three `kind == "input_turn"` items.

- [ ] **Step 2: Run contract test and verify RED**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test pytest tests/contract/test_timeline_api.py -q`

Expected: 404 from `/api/timeline`.

- [ ] **Step 3: Implement Timeline assembly**

Join assets to user skills. Resolve title from `render_spec.primary_field`,
common title fields, then `display_name`. Resolve semantic time using the chain
in the approved design. Serialize capture recording times with the existing
UTC `Z` helper and never query `flash_chat_messages` for count entries.

- [ ] **Step 4: Run contract test and verify GREEN**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/timeline theme_v2_service/app/main.py theme_v2_service/tests/contract/test_timeline_api.py
git commit -m "feat(theme-v2): add authoritative timeline"
```

### Task 4: Consume Timeline and preserve Flash counts in Flutter

**Files:**
- Modify: `mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart`
- Modify: `mobile/lib/timeline/timeline.dart`
- Test: `mobile/test/theme_v2/calendar/theme_v2_calendar_timeline_test.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_flow_test.dart`

**Interfaces:**
- Consumes: `GET /api/timeline` from Task 3.
- Preserves: `CalendarData.flashCount` based only on `kind == input_turn`.

- [ ] **Step 1: Write a failing Flutter repository/widget test**

Return three `input_turn` rows on August 5 and ordinary chat history outside
the Timeline response. Assert the sticky rail finds `✦ 3`, and a custom water
asset displays `每日喝水量` rather than `daily_water_intake`.

- [ ] **Step 2: Run test and verify RED**

Run: `cd mobile && flutter test test/theme_v2/calendar/theme_v2_calendar_timeline_test.dart`

Expected: FAIL because production loading bypasses `/api/timeline`.

- [ ] **Step 3: Switch Theme V2 Calendar to the authoritative loaders**

Use `fetchTimeline(_apiClient)` and `fetchSkills(_apiClient)`. Keep the existing
404 fallback in `timeline.dart` for non-Theme-V2 compatibility, but make its
custom title fallback use the skill display name rather than machine name.

- [ ] **Step 4: Run focused Flutter tests**

Run: `cd mobile && flutter test test/theme_v2/calendar/theme_v2_calendar_timeline_test.dart test/theme_v2/calendar/calendar_flow_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart mobile/lib/timeline/timeline.dart mobile/test/theme_v2/calendar/theme_v2_calendar_timeline_test.dart mobile/test/theme_v2/calendar/calendar_flow_test.dart
git commit -m "fix(calendar): consume authoritative Theme V2 timeline"
```

### Task 5: Repair current local acceptance data

**Files:**
- Create: `theme_v2_service/scripts/repair_local_acceptance_data.py`
- Test: `theme_v2_service/tests/unit/test_repair_local_acceptance_data.py`

**Interfaces:**
- Produces: idempotent `repair_payload(payload) -> dict` and bounded known-record temporal repair.

- [ ] **Step 1: Write failing pure-function tests**

```python
assert repair_payload({"distance": 5, "acceptance_marker": "x"}) == {"distance": 5}
assert repair_payload({"distance": 5}) == {"distance": 5}
```

- [ ] **Step 2: Run and verify RED**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test pytest tests/unit/test_repair_local_acceptance_data.py -q`

- [ ] **Step 3: Implement idempotent repair and dry-run output**

The script may only remove the exact key `acceptance_marker` and repair the
four identified water asset IDs/values. It must print intended changes before
commit and accept `--apply` for the actual local mutation.

- [ ] **Step 4: Run unit test, then dry run and apply once**

Run tests, then:

```bash
docker compose -f docker-compose.theme-v2.yml exec api python scripts/repair_local_acceptance_data.py
docker compose -f docker-compose.theme-v2.yml exec api python scripts/repair_local_acceptance_data.py --apply
```

Expected: dry run lists only bounded assets; apply completes once; a second dry
run reports no changes.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/scripts/repair_local_acceptance_data.py theme_v2_service/tests/unit/test_repair_local_acceptance_data.py
git commit -m "chore(theme-v2): add bounded acceptance data repair"
```
