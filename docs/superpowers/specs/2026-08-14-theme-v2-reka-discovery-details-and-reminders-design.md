# Theme V2 Reka Discovery Details and Todo/Event Reminders Design

**Date:** 2026-08-14
**Status:** Approved design
**Scope:** Reka discovery detail routing, Todo/Event reminder preferences, overdue Todo snooze semantics, Rhythm detail, and the three-stage proactive Report chain

## 1. Objective

Reka discoveries should take the user to the smallest surface that supports the next meaningful decision. They must not duplicate canonical Asset details, silently move deadlines, or turn Reka into a progress and receipt feed.

This design establishes four related behaviors:

1. An overdue discovery opens the existing Todo detail instead of a new Reka-specific overdue sheet.
2. Todo and Event support one or more reminders before their due/start anchor, defaulting to 15 minutes before.
3. An overdue Todo can be surfaced again later without changing its deadline.
4. Rhythm and Report are new Reka-native content and therefore receive their own detail sheets. Report uses a three-stage actionable chain.

This document supersedes the Report lifecycle in `2026-08-05-theme-v2-reka-signals-and-rhythm-design.md`. The earlier document remains authoritative for Rhythm learning, Period-only inference, overdue eligibility, ranking, and partial-source isolation unless this document explicitly extends those rules.

The canonical visual language remains `spec/design/redesignureka.pen`. The Pencil file defines the Theme V2 bottom-sheet geometry and hierarchy; it does not define three dedicated Reka discovery sheets. Archived Goals frames marked `ARCHIVE · DO NOT IMPLEMENT` are not implementation sources.

## 2. Discovery Information Architecture

Reka continues to have three active signal families, but only two require new Reka detail sheets.

| Signal family | Tap destination | New surface? |
|---|---|---|
| Overdue Todo | Canonical Todo detail bottom sheet | No; extend existing Todo detail |
| Rhythm gap | Rhythm discovery detail bottom sheet | Yes |
| Report | Phase-aware Report discovery detail bottom sheet | Yes |

All Reka rows may share consistent list geometry. Their detail bodies and actions remain type-specific.

## 3. Todo and Event Reminder Preferences

### 3.1 Canonical preference

Todo and Event expose a canonical list named `reminder_offsets_minutes`.

- Each non-negative integer is the number of minutes before the entity's reminder anchor.
- `0` means remind at the anchor.
- Values are normalized, deduplicated, and sorted by the server.
- An empty list means no reminder.
- A missing preference on an existing future Todo/Event is interpreted as `[15]` for backward-compatible default behavior.
- New Todo/Event records default to `[15]`.

The standard picker supports multiple selections from:

- at time (`0`);
- 5 minutes before;
- 15 minutes before;
- 30 minutes before;
- 1 hour before;
- 1 day before;
- custom;
- none.

Selecting `none` clears all offsets. Selecting any offset clears `none`. Custom reminders must resolve to a non-negative whole-minute offset before the anchor; duplicate custom and preset values collapse to one value.

### 3.2 Reminder anchors

- A Todo uses its explicit `due_at` as the anchor. The current product has no date-only Todo path; this design does not introduce one.
- A timed Event uses `start_at` as the anchor.
- An all-day Event uses 09:00 local time on the Event's local calendar date. The default 15-minute reminder therefore fires at 08:45 local time.
- Timezone and daylight-saving conversion are performed by the server using the Event/user timezone applicable to the anchor.

### 3.3 Detail presentation

For a future, unfinished Todo, the existing Todo detail shows a compact `提醒` summary row, for example `15 分钟前、1 小时前`. Tapping the row opens a dedicated reminder-configuration sheet. Reminder choices are not expanded inline in the Todo detail.

For a future Event, the existing Event detail uses the same summary row and configuration sheet. The all-day anchor explanation is shown in the configuration sheet when applicable.

For an overdue, unfinished Todo:

- keep the original `截止时间` visible;
- hide the pre-due `提醒` row entirely;
- show only the overdue `稍后提醒` action;
- do not imply that snoozing changes the deadline.

For a completed Todo, neither reminder configuration nor snooze is actionable.

## 4. Overdue Todo Snooze

### 4.1 Semantics

Snooze belongs to the current overdue occurrence, not to the Todo deadline. The natural occurrence remains:

```text
overdue:<todo_id>:<due_at>
```

The occurrence's persisted interaction state supports `remind_again_at` in addition to its existing delivery, action, dismissal, and expiry fields.

- Snooze writes `remind_again_at`; it never writes `due_at`.
- The active overdue signal disappears immediately after a successful snooze.
- It becomes eligible again once at `remind_again_at` if the Todo is still unfinished and still has the same `due_at`.
- The user may snooze the resurfaced occurrence again.
- Completing the Todo or changing `due_at` invalidates the occurrence and any pending `remind_again_at` immediately.
- Changing `due_at` may later create a new overdue occurrence under the new natural identity.

### 4.2 Picker

The overdue Todo detail offers:

- 15 minutes later;
- 1 hour later;
- 3 hours later;
- tomorrow at 09:00 local time;
- custom date and time;
- no more reminders.

After a snooze is set, the Todo detail shows an explicit status such as `将在 16:30 再次提醒`, with controls to change it or choose `不再提醒`. Cancelling the pending resurfacing is the same occurrence-scoped dismissal as `不再提醒`; it does not make the overdue signal immediately active again.

`不再提醒` permanently dismisses only the current `Todo + due_at` occurrence. It does not complete the Todo, change `due_at`, disable reminders globally, or suppress a future occurrence created after a deadline change.

## 5. Rhythm Discovery Detail

Rhythm receives a dedicated Reka detail bottom sheet because it is inferred content rather than an existing Asset detail.

The sheet contains:

1. a `节律提醒` type label;
2. the inferred pattern, for example `你通常在周三晚上记录跑步`;
3. concise aggregate evidence, for example `最近 4 周有 3 周在这个时段记录`;
4. the current gap, for example `本周还没有跑步记录`;
5. primary action `立即记录`;
6. secondary action `暂不提醒此节律`.

The sheet uses only the existing Period vocabulary: `凌晨`, `上午`, `中午`, `下午`, and `晚上`. It must not display, retain for presentation, or imply an inferred exact hour.

`立即记录` opens the canonical quick-capture flow for the matching Skill. `暂不提醒此节律` suppresses the specific `user + skill + pattern_key`; the three-consecutive-cycle reactivation rule from the earlier Rhythm spec remains unchanged.

## 6. Three-stage Report Discovery Chain

### 6.1 Principle

Report is a single opportunity chain with three actionable phases. The phases are not three simultaneous signals. At most one phase in a chain is active in Reka at a time.

```text
opportunity -> planning -> plan_ready -> generating -> report_ready
```

Only `opportunity`, `plan_ready`, and `report_ready` are visible Reka signals. `planning` and `generating` are processing states, because the user has no decision to make while those jobs run.

The Report detail uses one phase-aware bottom-sheet shell. Copy, summary, target, and actions change with `phase`.

### 6.2 Phase 1: Report opportunity

Reka follows the user's accumulated Assets, meeting context, and other eligible scope to identify a potentially useful Report.

The detail shows:

- why the Report may be useful now;
- the meeting, Asset collection, time range, or other scope that caused the opportunity;
- an honest description of what a plan would cover, without presenting ungenerated findings.

Actions:

- primary: `生成报告方案`;
- secondary: `暂不生成`.

Confirming consumes or claims the opportunity idempotently and creates/reuses one Report generation run. Dismissing the opportunity creates no plan and ends only that opportunity.

### 6.3 Phase 2: Report plan ready

After planning completes, Reka surfaces a new actionable phase for the same chain.

The detail shows:

- the recommended plan;
- the Report goal;
- the time/evidence scope;
- the number or concise description of Assets and references to be used;
- unresolved blockers, if any.

The primary action is `查看并确认方案`. It enters the existing Report plan selection, material review, adjustment, and final confirmation flow. The sheet must not bypass evidence confirmation or create a second Report workflow.

If the user dismisses this phase, the plan draft remains available in the Report library. The active Reka signal is removed, but the run is not deleted or cancelled. If the user later opens the library and confirms generation, the same chain may progress normally.

### 6.4 Phase 3: Report ready

After generation completes, Reka surfaces the final actionable phase.

The detail shows:

- the Report title;
- two or three concise key findings or a short generated summary;
- generation time;
- relevant context label when useful.

Actions:

- primary: `查看完整报告`;
- secondary: `不再提醒`.

Opening consumes the active signal and opens the canonical Report viewer. Dismissing removes only this active signal; the completed Report remains in the Report library.

### 6.5 Identity and transitions

Every Report signal exposes a stable `chain_id`, `phase`, phase target, and stage-specific natural identity. A compatible shape is:

```text
report:<chain_id>:opportunity
report:<chain_id>:plan_ready
report:<chain_id>:report_ready
```

The exact storage key may follow existing TriggerExecution and ReportGenerationRun identifiers, but it must preserve these invariants:

- retrying a phase transition cannot create a duplicate run, plan, Report, or active signal;
- entering a later phase invalidates the earlier active phase;
- refreshing while `planning` or `generating` cannot resurrect the decision already consumed;
- dismissals are phase-scoped;
- `plan_revision` is used for plan-edit concurrency and must not create a new `plan_ready` signal after that phase was dismissed;
- the completed `report_id` is phase target metadata and must not create duplicate `report_ready` identities for the same chain;
- a later independent Report opportunity is not suppressed by an earlier dismissal.

## 7. Reka and Notifications

Reka is the source of truth for current actionable discoveries. Notifications remain delivery and history artifacts.

- A push or notification-center row may deliver an actionable Reka transition.
- Notification rows must not be re-read as candidates to manufacture Reka signals.
- The same Report phase must not appear twice in Reka because both a Nudge and Notification exist.
- Existing `report_available`, `report_plan_ready`, and `report_done` delivery types may route to the same canonical targets, but their lifecycle must follow the Report chain above.
- Workflow progress receipts remain excluded from Reka.

## 8. Scheduling and Mutation Rules

The server owns scheduling so behavior remains consistent across devices.

A reminder delivery is uniquely identified by the entity occurrence and offset, for example:

```text
todo:<todo_id>:<due_at>:before:<offset_minutes>
event:<event_id>:<start_at_or_all_day_anchor>:before:<offset_minutes>
```

- Repeated scheduler passes must be idempotent.
- Editing an anchor or reminder list invalidates pending deliveries that no longer match.
- Only reminder times still in the future are scheduled; historical reminders are not backfilled.
- Saving the entity and its reminder preference is atomic from the client's perspective.
- Completion, cancellation, deletion, or reschedule is checked again at delivery time.

The legacy fixed thresholds (`Event: 60/30/15`, `Todo: 60/15`) are replaced by the canonical user preference. Missing future preferences resolve to the approved `[15]` default rather than the legacy threshold sets.

## 9. Failure Handling

- A failed reminder save keeps the user's current selection visible as unsaved and offers retry; it must not report success optimistically.
- A failed snooze keeps the overdue signal active and retains an actionable retry state.
- If the Todo body loads but overdue interaction state fails, the canonical Todo content remains readable while snooze is disabled with retry feedback.
- Failure of one Reka source family must not hide healthy signals from the other families.
- A Report transition is committed before the previous phase disappears from the server result; client optimism may hide the row temporarily but must restore it on failure.
- A planning/generation failure belongs to the existing Report recovery flow and Notifications. It is not represented as a fake new discovery phase.
- Invalid or deleted targets are filtered server-side and logged by natural identity.

## 10. Verification

Backend tests must cover:

- default `[15]`, multi-offset normalization, `none`, custom offsets, and duplicate elimination;
- timed Todo, timed Event, and all-day Event 09:00-local anchors, including timezone boundaries;
- no backfill for elapsed reminder times and idempotent repeated scheduling;
- anchor/preference edits invalidating stale deliveries;
- snooze hiding and resurfacing the same overdue occurrence without modifying `due_at`;
- repeated snooze, no-more-reminders, completion, and due-time-change invalidation;
- Report opportunity -> planning -> plan-ready -> generating -> report-ready transitions;
- no visible signal during planning/generating;
- phase-scoped Report dismissal and plan/report preservation;
- transition idempotency and no duplicate Report chains;
- partial-source failure isolation.

Mobile tests must cover:

- overdue Reka tap opening the canonical Todo detail;
- future Todo/Event reminder summaries and multi-select configuration;
- overdue Todo hiding pre-due reminder UI and showing only snooze controls;
- snooze choices, scheduled status, change, and no-more-reminders;
- Rhythm detail using Period-only language and canonical quick capture;
- all three actionable Report phase presentations and targets;
- no Report detail shown for planning/generating;
- mutation failure retaining the current actionable state;
- Notifications and Reka routing to canonical targets without duplicate Reka rows.

True-device acceptance must verify at least one future reminder edit, one overdue snooze and resurfacing, one Rhythm detail, and all three Report decisions using the real Theme V2 API.

## 11. Non-goals

- no date-only Todo introduction;
- no client-only reminder scheduler as the source of truth;
- no automatic deadline movement when snoozing;
- no exact-hour Rhythm inference;
- no second Report planning or generation workflow inside Reka;
- no Report progress feed in Reka;
- no global dot-field, dark-theme, or unrelated Today visual expansion in this change.
