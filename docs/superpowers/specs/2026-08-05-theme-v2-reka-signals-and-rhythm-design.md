# Theme V2 Reka Signals, Rhythm, and Timed Surfaces Design

**Date:** 2026-08-05  
**Status:** Approved design, deferred implementation  
**Scope:** Theme V2 home Reka section, Rhythm learning, overdue/report signal lifecycles, and timed Todo behavior in Next/time surfaces

## 1. Objective

The Theme V2 home Reka section is a proactive-insight surface. It must not be a second notification feed or a list of workflow receipts. It answers one question: **what has Reka noticed that may be useful to the user now?**

The same change also makes the home time surfaces internally consistent:

- events and explicitly timed Todos belong to Next and the time axis;
- untimed Todos remain in their Todo/asset container and do not enter time surfaces;
- multiple events or Todos at the same displayed minute are all represented.

This document records the agreed behavior for later implementation. It does not authorize implementation in the current debugging work.

## 2. Product Taxonomy

Reka has three active signal families.

### 2.1 Rhythm gap

Reka learns that the user normally records a particular skill in a recurring period and notices when the current expected period is approaching its end without a record.

Examples:

- the user usually records breakfast in the morning, but has not done so today;
- the user usually logs running on Wednesday evenings, but has not done so this week;
- one skill may have independent morning, afternoon, and evening patterns.

### 2.2 Overdue Todo

Only an unfinished Todo with an explicit clock time can become an overdue Reka signal. Date-only and untimed Todos are excluded.

An overdue occurrence is active for at most 72 hours after its due time. It disappears immediately when completed or rescheduled. If the user ignores it, that overdue occurrence never appears again. Rescheduling changes the occurrence identity, so a later overdue occurrence may appear independently.

### 2.3 Report insight

A newly available report or proactive report insight creates a signal for that specific report execution. Opening/consuming it removes the signal. Ignoring it suppresses only that report; a later report is a new signal and may appear normally. Expired or deleted reports disappear automatically.

The existing `report_done`, task-completion, flash-completion, and other workflow receipts remain in Notifications and are excluded from Reka.

## 3. Rhythm Semantics

### 3.1 Reuse the existing Period concept

Rhythm is never learned or presented at minute precision. All capture times are normalized into the existing five local periods:

| Period | Local time range |
|---|---|
| `凌晨` | 00:00–05:59 |
| `上午` | 06:00–11:59 |
| `中午` | 12:00–12:59 |
| `下午` | 13:00–17:59 |
| `晚上` | 18:00–23:59 |

Even if a record was captured at an exact time such as 08:13 or 09:45, the Rhythm model learns only `上午`. It must not retain, display, or trigger from an inferred exact hour.

This does not change the meaning of Asset metadata. `occurred_at` and `Asset.period` continue to describe when the content happened for timeline rendering. Rhythm learns **when the user records** and therefore uses `Asset.created_at` converted to the user's local period.

### 3.2 Pattern model

The current single `(user, skill)` profile is extended to hold independent patterns:

```text
RhythmProfile
  user_id
  skill
  patterns[]
    pattern_key
    cadence            daily | weekly
    period             凌晨 | 上午 | 中午 | 下午 | 晚上 | null
    weekdays[]         optional, Monday=0
    confidence
    sample_n
  computed_at
```

`period=null` means the cadence is stable but the recording time is scattered across periods. A skill may contain multiple patterns, such as morning, afternoon, and evening medication records.

The existing 28-day lookback, minimum five samples, deterministic statistics, daily offline recomputation, and confidence gate remain the baseline. The raw median interval may be retained as diagnostic evidence, but it does not produce an exact-time reminder.

Todo and Event remain excluded from Rhythm learning because they have explicit scheduling semantics.

### 3.3 Trigger rule

The heartbeat reads the last computed profile; it does not run a model or recompute the profile per request.

For a period-specific pattern, a gap becomes eligible only after the current period enters its second half and no matching record exists in that expected period. The fixed local eligibility boundaries are `凌晨 03:00`, `上午 09:00`, `中午 12:30`, `下午 15:30`, and `晚上 21:00`. This avoids reminding at the beginning of a broad period without learning an exact hour. For a stable daily pattern without a stable period, eligibility begins at `21:00`. A weekly pattern evaluates its expected local week and optional weekday/period.

Completion is pattern-scoped. A morning record satisfies the morning pattern only; it does not suppress an afternoon or evening pattern for the same skill.

### 3.4 Ignore and reactivation

Ignoring a Rhythm signal suppresses that specific `user + skill + pattern_key` indefinitely.

It becomes eligible again only after the user completes three consecutive expected cycles after the ignore time:

- daily morning pattern: three consecutive mornings;
- daily any-period pattern: three consecutive local days;
- weekly pattern: three consecutive expected weeks.

Every expected cycle must contain a matching record. A missed cycle resets the reactivation streak. This replaces the old behavior of two ignored nudges followed by a fixed 72-hour backoff.

## 4. Storage and Aggregation

The system uses a hybrid model: **live candidates plus persisted interaction state**, not a frozen daily Reka snapshot.

### 4.1 Sources of truth

- Rhythm candidate: `RhythmProfile` plus current Assets.
- Overdue candidate: the current timed Todo Asset.
- Report candidate: the current report trigger/execution state.

### 4.2 Persisted state

Reuse the existing `nudges` lifecycle instead of creating a parallel notification-like table. Each active candidate is upserted using a stable natural identity:

- `rhythm:<skill>:<pattern_key>:<cycle>`
- `overdue:<todo_id>:<due_at>`
- `report:<execution_id>`

The Nudge row records `kind`, `ref`, `status`, `delivered_at`, `acted_at`, `dismissed_at`, and `expires_at`. Existing notification rows remain delivery/history artifacts; they are not the Reka source of truth.

The Rhythm reactivation streak is derived from Assets after the latest dismissal rather than stored as a mutable counter. Although each emitted signal has a cycle-specific natural identity, suppression is looked up by `user + skill + pattern_key` across later cycles until the three-cycle reactivation rule succeeds. Completing or rescheduling a Todo and consuming a report are read live, so stale signals disappear without a daily rebuild.

### 4.3 Read path

Theme V2 consumes a dedicated endpoint such as:

```http
GET /api/reka/signals?timezone=Asia/Shanghai
```

The server:

1. obtains current candidates from the three source families;
2. applies completion, reschedule, expiry, dismissal, and Rhythm-reactivation rules;
3. deduplicates by natural identity;
4. ranks the remaining signals;
5. returns the active set with actions and target references.

The home shows the top two or three signals. The full Reka surface may show the larger active set. Refresh occurs on app foreground, pull-to-refresh, and relevant local mutations. SSE or push delivery may invalidate the cache, but is not required as the sole read path.

## 5. Home Reka UI

All Reka records use one consistent card/row geometry. Content may use at most a title plus two lines of supporting text; record height must not vary by signal kind.

Actions are type-specific:

- Rhythm: open the matching quick-capture skill; allow ignore.
- Overdue: open the Todo, complete/reschedule, or ignore.
- Report: open the report; allow ignore.

When there are no active signals, the section remains present and offers:

- **生成新报告** — enter the existing user-initiated Report planning/material-selection/generation flow;
- **查看历史报告** — open the Report container/library.

Neither action creates a second Report workflow.

## 6. Next and Time Surfaces

### 6.1 Inclusion rules

- Event with a scheduled time: included.
- Todo with an explicit clock time: included.
- Date-only Todo or Todo without a time: excluded from Next, home Agenda, and calendar time grids; it remains available in its Todo/asset container.

Future scheduled Todo/Event items are not duplicated in Reka. Once a timed Todo becomes overdue, its proactive overdue signal may enter Reka under the three-day lifecycle.

### 6.2 Same-minute grouping

Items are grouped by their displayed local minute. `15:00:00` and `15:00:37` are the same group.

Next renders the selected group as a vertical list of independently tappable Event/Timed-Todo rows. It shows at most three rows. If more exist, it shows `另 N 项`; tapping that affordance opens the full time axis. Labels must describe mixed content accurately and must not call a mixed Event/Todo group “N 个代办”.

Calendar/time-axis grouping uses the same minute-normalization helper so the same data cannot group differently across surfaces.

## 7. Ranking and Guardrails

Home ranking prioritizes:

1. a recently available high-value report insight;
2. a currently eligible Rhythm gap;
3. a recent overdue Todo, ordered by due time.

The home list is capped at three. Ranking does not delete lower-ranked active signals from the full Reka surface.

Existing gentle-language, quiet-hours, global enable/disable, and push daily-cap guardrails remain applicable to interruptive push/peek delivery. Pulling the Reka section is not itself a push and therefore does not consume a delivery quota, but dismissed and expired state is always respected.

## 8. Failure Handling

- Failure of one source family must not hide valid candidates from the other families.
- A failed Reka request shows the stable empty/entry container with a retry affordance; it must not fall back to workflow receipts.
- Invalid or missing targets are filtered server-side and logged with their natural identity.
- Profile recomputation failure leaves the last valid profile readable and retries on the next daily job; heartbeat failure must not terminate the companion loop.

## 9. Verification

Backend tests must cover:

- exact capture times collapsing to Period only;
- one skill learning multiple independent Period patterns;
- daily and weekly pattern gaps;
- no early-period reminder and eligibility in the second half;
- dismissal plus three-cycle reactivation, including streak reset;
- an explicit-time Todo appearing in Next and later as overdue;
- untimed/date-only Todos excluded from all time surfaces and overdue signals;
- 72-hour overdue expiry, ignore permanence, completion, and reschedule identity;
- per-report dismissal and later-report independence;
- partial-source failure and ranking.

Mobile tests must cover:

- consistent Reka row geometry and type actions;
- Report empty-state actions using existing routes;
- same-minute mixed Event/Timed-Todo grouping, three-row cap, and `另 N 项`;
- no untimed Todo in Next, Agenda, or calendar time grid;
- refresh after completing/rescheduling a Todo and consuming/dismissing a signal.

## 10. Non-goals

- no exact-hour Rhythm prediction;
- no LLM decision on whether to remind;
- no predicted or automatically created Todos;
- no migration of workflow receipts into Reka;
- no new Report-generation path;
- no implementation as part of the current Flash-capture debugging task.
