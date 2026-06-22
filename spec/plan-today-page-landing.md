# 今日页 (Today Page landing) Implementation Plan

> **✅ 已落地 2026-06-22** (branch `feat/today-page-landing`) — Slice 0–7 全部完成、4 边态真机验过；落地决策 / 与原型的偏差见 [04-frontend §4.5.0「已落地」块](04-frontend.md)。下文留作实施记录。

> **For agentic workers:** implement task-by-task; steps use `- [ ]`. This is a **Flutter mobile UI feature** — the TDD default is adapted (see "Verification model"). Truth sources, read first: [handoff-today-landing.md](handoff-today-landing.md) (scope/order), [prototype-today-page.md](prototype-today-page.md) (verbatim hifi tokens/motion/physics constants), [04-frontend §4.5.0](04-frontend.md) (logic/data). The prototype README is the **verbatim visual spec** — this plan references its exact tokens rather than re-typing them; "see README §X" means copy those literal values.

**Goal:** Replace tab0 with a new `TodayPage` home: two frosted panels (① Next Action card-fan, ② Dashboard) floating over a ③ full-screen physics bubble pool of today's captured assets, with Reka on top.

**Architecture:** New `TodayPage` becomes IndexedStack index 0 (calendar → index 1, library → index 2). One `TodayData` fetch feeds all three sections. The bubble pool is a **self-written 2D solver** driven by a single shared `Ticker` that sleeps when idle and stops when the page is inactive (battery). Charts + bubbles are `CustomPainter`. Detail = existing `showAssetDetail`. No new data model; one small backend filter added.

**Tech Stack:** Flutter, `CustomPainter` (bubbles + charts), `Ticker`/`SingleTickerProviderStateMixin`, `sensors_plus` (tilt), existing `ApiClient` + `EurekaColors` + `domainColor` + `showAssetDetail`.

---

## Decisions resolved (were open in the review)

1. **Physics engine = self-written** (not `forge2d`). The README's approach (circle-circle + positional relaxation + sleeping) is simple, and we need exact control over sleeping, the wall-less box, and "bubbles settle *behind* the panels with the nav pill as an AABB collider" — Box2D fights all three. Lighter binary, no native dep.
2. **Scale cap = 50 bubbles.** Pool renders the 50 most-recent-by-`created_at` assets as physics bodies (≈8 rows at r=23 on a 430-wide pool; perf-safe with 14 relax passes). Dashboard header shows the **true** count (`今天 N 颗`), so overflow is never hidden, just not simulated.
3. **Battery = sleep + lifecycle gating.** One shared `Ticker`. It runs only while ≥1 bubble is awake; when all sleep it stops (no idle RAF). It also stops when the page isn't the active tab or the app is backgrounded. The accelerometer stream is subscribed only while the page is active+visible.
4. **Morning-brief merge = light.** Next Action hosts the chain. On the morning's first open (reuse `morning_briefing`'s once-per-day gate + `/api/briefing/today`), an expandable "早报" strip appears *inside* the Next Action panel (greeting + 昨日回顾 + 本周进度). No standalone 晨报页. Deep briefing layout is one sub-task, not a blocker.
5. **New dep = `sensors_plus`** only. Charts self-drawn (no chart lib). Physics self-written (no forge2d).

## Verification model (TDD adaptation)

- **Pure logic** (chain builder, summary calc, physics integrator/collision math, treemap squarify) → **unit tests first** (`flutter test`), real TDD.
- **UI / visual / physics-feel** → `flutter analyze` clean → `flutter build apk --debug --dart-define=API_BASE=http://$IP:8000` → install on device `RFCY71B21YK` → screenshot via ADB (the workflow used all session). Each UI task lists the exact screenshot to capture + what to verify.
- **Commit** after each task.

## File structure

```
mobile/lib/pages/today_page.dart          # TodayPage shell: 3-layer Stack, TodayData fetch, panel collapse state
mobile/lib/today/today_data.dart          # TodayData model + load() (chain + pool + flashCount) ; pure-ish
mobile/lib/today/next_action.dart         # Part 1: C-fan deck, countdown, no-time todos, morning-brief strip, empty
mobile/lib/today/bubble_pool.dart         # Part 2 pool: BubbleField widget + CustomPainter + gesture/tilt wiring
mobile/lib/today/bubble_physics.dart      # pure solver: Bubble, step(), collide, relax, sleep  (UNIT-TESTED)
mobile/lib/today/dashboard.dart           # Part 2 dashboard: chips, summary strip, chart switcher
mobile/lib/today/charts.dart              # rose / bar / treemap CustomPainters + squarify()  (squarify UNIT-TESTED)
mobile/lib/today/today_summary.dart       # summary-strip calc per filter (记账 special-case)  (UNIT-TESTED)
mobile/test/today_summary_test.dart
mobile/test/bubble_physics_test.dart
mobile/test/charts_squarify_test.dart
mobile/lib/app_shell.dart                 # MODIFY: insert TodayPage at index 0, dock relabel, 我的岛 → Reka menu
backend/api/assets.py                     # MODIFY: add created_at from/to filter to GET /api/assets
```

Reuse (do not rebuild): `EurekaColors` (`theme/eureka_colors.dart`), `domainColor`/`DomainChip` (`theme/domains.dart`), `showAssetDetail` (`render/asset_detail_sheet.dart:22`), `ApiClient` (`api/api_client.dart`), `SessionDetailPage` (flash pill target), the existing floating Reka (`pet/floating_mascot.dart`).

---

## Slice 0: deps + backend created_at filter

### Task 0.1: add `sensors_plus`
**Files:** Modify `mobile/pubspec.yaml`
- [ ] Add `sensors_plus: ^6.0.0` under dependencies (verify latest on pub.dev at run time; pin the resolved version).
- [ ] Run `cd mobile && flutter pub get`. Expected: resolves, no conflicts.
- [ ] Commit: `chore(deps): add sensors_plus for today-page tilt`

### Task 0.2: created_at filter on GET /api/assets
**Files:** Modify `backend/api/assets.py:130-186` (`list_assets`)
- [ ] **Test first** (backend): add `backend/tests/test_assets_created_filter.py` — seed 2 assets with `created_at` on different days for a user, GET `/api/assets?created_from=<dayA 00:00+08>&created_to=<dayA 23:59+08>`, assert only dayA's asset returns. (Mirror an existing api test's client/fixtures.)
- [ ] Run: `cd backend && pytest tests/test_assets_created_filter.py -v` → FAIL (param ignored).
- [ ] Add two `Query(None)` params `created_from` / `created_to` (ISO8601). In the direct-query path, after the existing filters: `if created_from: stmt = stmt.where(Asset.created_at >= _parse(created_from))` and same `<= created_to` (reuse `datetime.fromisoformat(...replace("Z","+00:00"))`, same pattern as `query_asset`).
- [ ] Run pytest → PASS. Restart backend: `docker restart eureka-assistant-backend-1`.
- [ ] Commit: `feat(api): created_from/created_to filter on GET /api/assets (today-page pool)`

---

## Slice 1: nav — TodayPage at tab0

### Task 1.1: TodayPage skeleton
**Files:** Create `mobile/lib/pages/today_page.dart`
- [ ] Create `TodayPage` (StatefulWidget). Build a 3-layer `Stack`: (back) `Positioned.fill` placeholder `ColoredBox(eu.bg)` for the pool; (overlay) radial atmosphere `DecoratedBox` (README Design Tokens "radial atmosphere"); (front) a `Column` → `Expanded(SizedBox())` for now + bottom `SizedBox(height: 78)` reserved-gap above the dock. Rebuild on `ValueListenableBuilder(dataRevision)` (mirror calendar_page's `_futureFor(rev)` pattern; data wired in Slice 2).
- [ ] No test (skeleton). Will fill in later slices.

### Task 1.2: wire into the shell + relabel dock
**Files:** Modify `mobile/lib/app_shell.dart`
- [ ] Import `today_page.dart`. In the `IndexedStack.children` (line 131-140), make index 0 = `const TodayPage()`, index 1 = `const CalendarPage()`, index 2 = `const LibraryPage()`. Remove `PetBoard` from the stack (我的岛 leaves the dock — see 1.3). The IndexedStack now has 3 children all-built (calendar+library are cheap; the WebView-heavy PetBoard is gone).
- [ ] Update `FloatingDock.items` (line 171-190) to exactly: `DockItem(Icons.wb_sunny_outlined, '今日', active:_index==0, onTap:()=>_go(0))`, `DockItem(Icons.calendar_today_outlined, '日历', _index==1, ()=>_go(1))`, `DockItem(Icons.grid_view_outlined, '资产', _index==2, ()=>_go(2))`.
- [ ] In `_go`, drop the `_index==2` island fly-out block (我的岛 no longer a tab) and the `calendarHome` re-tap (move its trigger to index 1: `if (i==1 && _index==1) calendarHome.value++;`). Keep `START_TAB` clamp at `0,2`.
- [ ] `flutter analyze lib/app_shell.dart lib/pages/today_page.dart` → No issues.
- [ ] Build + install + launch; screenshot `/tmp/n1.png`. Verify: dock reads 今日 / 日历 / 资产; tab0 shows the dark atmosphere skeleton; tab1 = calendar; tab2 = library.
- [ ] Commit: `feat(nav): TodayPage at tab0, dock = 今日/日历/资产`

### Task 1.3: 我的岛 → Reka radar menu
**Files:** Modify the Reka floating-ball menu (find it: `grep -rn "雷达\|radial\|RadialMenu\|menuItems" lib/pet/`). 
- [ ] Add a "我的岛" entry to the Reka ball's menu that pushes `PetBoard` as a full route (`Navigator.push(MaterialPageRoute(builder:(_)=>const Scaffold(body: SafeArea(child: PetBoard(bottomInset: 20)))))`). If no radar menu exists yet, that is a separate §4.1 feature — in that case STOP and report; do not block the rest of this plan (我的岛 stays reachable only via this entry once §4.1 lands).
- [ ] Build + verify 我的岛 opens from the ball; commit `feat(nav): 我的岛 enters via Reka menu`.

---

## Slice 2: data layer

### Task 2.1: TodayData model + load
**Files:** Create `mobile/lib/today/today_data.dart`
- [ ] Define `ChainItem` ({String kind /*event|todo*/, String id, String title, String sub, String domain, DateTime at, Duration? dur, String? note, bool done}) and `PoolAsset` ({String id, String type /*skill name*/, String domain, String title, Map payload, DateTime createdAt}) and `TodayData` ({List<ChainItem> chain, List<ChainItem> noTimeTodos, List<PoolAsset> pool, int poolTrueCount, int flashCount}).
- [ ] `Future<TodayData> loadToday(ApiClient api)`:
  - **chain**: `GET /api/timeline?from=<todayStart ISO+08>&to=<todayEnd ISO+08>`; keep items where `kind=='event'` (→ ChainItem at=start_at, dur from end_at) or (`kind=='asset' && skill_name=='todo'`); split: items with a clock time (`has_clock_time` true or event) and `at >= now` → `chain` (sort `at` asc); todos without a clock time → `noTimeTodos`. (Timeline item fields per [§3.8](03-api-reference.md): `effective_at`, `has_clock_time`, `domain`, `payload`, `kind`, `skill_name`, `end_at`.)
  - **pool**: `GET /api/assets?created_from=<todayStart>&created_to=<todayEnd>&limit=500`; map to `PoolAsset` (domain, skill_name→type, payload, created_at); `poolTrueCount = list.length`; cap `pool = list.take(50)`.
  - **flashCount**: `GET /api/sessions?session_type=flash` → count those whose `created_at`/`date` is today (reuse the date helper).
  - Beijing day bounds: `_todayBounds()` → today 00:00:00 / 23:59:59 at +08:00 (mirror `_isoBeijing`).
- [ ] **Unit test** `mobile/test/today_summary_test.dart` is Slice 5; for 2.1 add a light `loadToday` smoke is skipped (network). Instead unit-test the **pure splitter**: extract `splitChain(List<TimelineItemLike> items, DateTime now)` → (chain, noTimeTodos) and test: an event at now+1h → chain; a todo due 14:00 with now=15:00 → dropped (past); a no-clock todo → noTimeTodos. Run `flutter test test/today_split_test.dart` → write failing → implement → pass.
- [ ] Commit: `feat(today): TodayData model + loadToday (chain/pool/flash)`

### Task 2.2: wire data into TodayPage
**Files:** Modify `today_page.dart`
- [ ] Add `Future<TodayData> _futureFor(int rev)` (cache by rev, like calendar). FutureBuilder over `loadToday`. On data, pass `chain`/`noTimeTodos` to Next Action (Slice 3), `pool` to BubblePool (Slice 4), pool+flash to Dashboard (Slice 5) — stub those as `SizedBox` for now, just confirm the fetch runs.
- [ ] Build + launch tab0; check backend logs show the 3 GETs; screenshot (still skeleton). Commit `feat(today): wire TodayData fetch into TodayPage`.

---

## Slice 3: Part 1 — Next Action

### Task 3.1: C-fan deck + focal card (static)
**Files:** Create `mobile/lib/today/next_action.dart`
- [ ] `NextActionPanel(chain, noTimeTodos)`. Frosted container (README "Next Action panel": `rgba(15,23,40,.66)`+blur12, border, radius18, `margin 4 14 0`). Header row (`接下来` mono label · collapsed title · `chainPos "k / N"` `#8ab4ff` · caret) with collapse state `_open`.
- [ ] Deck (height 152): `Stack` of 2 peek cards (`Transform.rotate(-2.2°)` / `1.5°`, faint) + focal card (fixed **height 124**, gradient + border + shadow + padding per README "Focal card"). Focal content: domain dot (9px glow) + sub (`事件 · 地点` / todo sub) + time label; title 20/600.
- [ ] `flutter analyze`; build; screenshot `/tmp/na1.png` on a day with chain (use 6-25 test data via... note: chain is by *now*, so seed an event today via the device or `seed_test_day` adapted to today). Verify the focal card + 2 peek cards render, fixed height.
- [ ] Commit `feat(today): Next Action C-fan deck + focal card`

### Task 3.2: event vs todo card bodies + countdown
**Files:** Modify `next_action.dart`
- [ ] Event card bottom: countdown `⏳ N 分 M 秒后` (mono, `#8ab4ff`) + progress bar (README values) + `🔔 到点提醒你` + `在日历看 ›` (tap → push CalendarPage/DayDetail at the event). Todo card bottom: note + `完成 ✓` pill (tap → `_toggleTodoDone` via PUT status, then `bumpData`).
- [ ] Countdown: a 1s `Timer.periodic` in the panel state updating `now` (cancel in dispose). Progress = elapsed/(dur) clamp.
- [ ] **Unit test** the countdown formatter: `fmtCountdown(Duration)` → "23 分 00 秒" / "1 时 05 分" boundaries. `flutter test` red→green.
- [ ] Build; screenshot `/tmp/na2.png`; verify the countdown ticks (two screenshots ~2s apart show different seconds) + 完成 works.
- [ ] Commit `feat(today): event countdown + todo complete in Next Action`

### Task 3.3: swipe to cycle + advance + no-time list + empty
**Files:** Modify `next_action.dart`
- [ ] Horizontal drag on the deck → `currentActionIndex` ±1 (clamp); animate the fan (peek↔focal). When the focal event's `at` passes now, or a todo is completed, drop it from the chain (advance). `chainPos` = `index+1 / chain.length`.
- [ ] Counter row: `左右滑切换` hint + `🕒 无时间待办 {N} ▾`. Tapping expands a dashed container (README "No-time todos") listing `noTimeTodos` (domain dot + title + 19px circle checkbox → `_toggleTodoDone`).
- [ ] Empty state (chain empty): centered 🌤️ + the two lines (README "Empty state").
- [ ] Build; screenshots: swipe cycles `/tmp/na3.png`, no-time expanded `/tmp/na4.png`, empty `/tmp/na5.png` (seed a no-action day).
- [ ] Commit `feat(today): Next Action swipe/advance + no-time todos + empty`

### Task 3.4: morning-brief strip (light merge)
**Files:** Modify `next_action.dart`; read `pages/morning_briefing_page.dart` for the once-per-day gate + `/api/briefing/today` shape.
- [ ] On morning first-open (reuse the gate; if shown-today already, skip), fetch the briefing and render a collapsible "早报" strip at the top of the panel: greeting + 昨日回顾 + 本周进度 (one tap to dismiss → not shown again today, same prefs key family as `mb_shown_date`).
- [ ] Build; screenshot `/tmp/na6.png` (force-show via the existing debug flag pattern, **do not commit the flag = true**). Verify strip renders + dismisses.
- [ ] Commit `feat(today): merge morning brief into Next Action (no standalone page)`

---

## Slice 4: Part 2 — physics bubble pool (the big one; build sub-step by sub-step)

### Task 4.1: pure solver (UNIT-TESTED first)
**Files:** Create `mobile/lib/today/bubble_physics.dart`; test `mobile/test/bubble_physics_test.dart`
- [ ] **Test first**: `class Bubble {double x,y,vx,vy,r; int stillFrames; bool sleeping; ...}`. `class BubbleField {Size box; Rect navAabb; List<Bubble> bubbles; Offset gravity;}`. Tests:
  - `step()` with gravity (0, .44): an awake bubble's `vy` increases then `y` increases; clamped to floor (`y <= box.height - r`).
  - circle-circle: two overlapping bubbles, after `step()` they separate (distance ≥ r1+r2 within ε after ~14 relax passes).
  - nav AABB: a bubble pushed into `navAabb` is ejected to its nearest side, never resting inside.
  - sleeping: a bubble below speed threshold for 16 `step()`s → `sleeping=true`; a `wake()` (or a collision) resets `stillFrames`.
  - `anyAwake` false when all sleep.
- [ ] `flutter test test/bubble_physics_test.dart` → red.
- [ ] Implement: semi-implicit Euler (`vy += g; v *= .97; clamp |v|<=max; x+=vx; y+=vy`), wall-less box (reflect off left/right/floor/ceiling with restitution .22), nav AABB ejection, circle-circle positional relaxation loop (`for i in 14: for each pair overlapping: push apart by half-overlap`), sleeping (stillFrames++ when `speed<eps && grounded`; freeze; collisions/`wake()` reset). Constants from README §Bubble (g .44, restitution .22, damping .97, relax 14, sleep 16).
- [ ] `flutter test` → green. Commit `feat(today): bubble physics solver (tested)`

### Task 4.2: render + ticker + sleep/lifecycle gating
**Files:** Create `mobile/lib/today/bubble_pool.dart`
- [ ] `BubblePool(pool, trueCount)` StatefulWidget + `SingleTickerProviderStateMixin`. Build `BubbleField` from `pool` (initial positions: stagger across top). `CustomPaint` painter draws each bubble = README "Bubble visual" (radial gradient `circle at 34% 30%, #fffc, domainColor 78%`, the 3 shadows, centered type-emoji glyph `saturate .85`). Domain = `domainColor(eu, a.domain)`; glyph = `_glyphFor(type)` (README "Type → glyph": todo 📌 / expense 💰 / contact 👤 / notes 📝 / sport 🎾 / default ◦).
- [ ] Ticker: on each tick, if `field.anyAwake` call `field.step()` + `setState`; **else `_ticker.stop()`**. Restart on any wake (drag/tilt/new/drop). Stop the ticker in `deactivate`/when not visible (use `TickerMode` / a `visible` flag fed by the page's active-tab). Empty state (pool empty): centered 🫧 + line (README).
- [ ] Build; screenshot `/tmp/bp1.png` — bubbles fall + settle + **stop** (take a 2nd shot 3s later: identical = sleeping, no jitter). Verify domain colors + glyphs.
- [ ] Commit `feat(today): bubble pool render + ticker with sleep/lifecycle gating`

### Task 4.3: tap (detail) + drag/throw
**Files:** Modify `bubble_pool.dart`
- [ ] `GestureDetector`: hit-test tap → nearest bubble within r → `showAssetDetail(context, assetId: a.id, ...)` (reuse). Pan: grab nearest bubble, follow finger (set position, zero gravity on it, `wake()`); on release, velocity = recent finger delta → throw; re-settles.
- [ ] Build; screenshot tap-opens-sheet `/tmp/bp2.png` + a thrown bubble mid-air `/tmp/bp3.png`.
- [ ] Commit `feat(today): bubble tap-detail + drag-throw`

### Task 4.4: tilt + drop-in
**Files:** Modify `bubble_pool.dart`
- [ ] Subscribe `accelerometerEvents` (sensors_plus) only while active; map device tilt → `field.gravity` vector (README: upside-down → bubbles rise, panels = ceiling, nav pill collider). Wake all on gravity change. Unsubscribe in dispose/inactive.
- [ ] New record (pool grew on `bumpData` re-fetch) → drop the new bubble in from the top (spawn above ceiling, wake).
- [ ] Build on device; **manual tilt check** (physical) — screenshot before/after tilt `/tmp/bp4.png`; verify bubbles roll. Drop-in: create an asset for today (FAB elsewhere) → returns → new bubble drops `/tmp/bp5.png`.
- [ ] Commit `feat(today): bubble tilt-gravity + drop-in`

---

## Slice 5: Dashboard

### Task 5.1: summary calc (UNIT-TESTED) + chips
**Files:** Create `mobile/lib/today/today_summary.dart`, `mobile/lib/today/dashboard.dart`; test `mobile/test/today_summary_test.dart`
- [ ] **Test first** `summaryFor(filter, List<PoolAsset>)` → a `SummaryStrip` ({icon, title, sub, metric}): 记账 filter → metric `¥{sum}` (sum payload amount field), sub "最大 ¥X · 共 N 笔"; any other type → "最新一条" (latest by createdAt: icon+title+time), no aggregation; 全部 → "共 N 条" + latest preview. Tests cover 记账 sum, a custom type (latest-only), 全部.
- [ ] `flutter test test/today_summary_test.dart` red→green.
- [ ] Dashboard panel (hidden entirely if `pool` empty). Header `今天 {trueCount} 颗` + `⚡{flashCount}` pill (tap → newest today flash session via `SessionDetailPage`; **not** a filter) + caret. Filter chips (horizontal scroll): `全部 N` + one per present type (README glyphs; **no 闪念 chip**). Active chip styling per README. Tapping a chip sets `filterKey` → (a) filters the pool (pass `filterKey` up to BubblePool to dim/hide non-matching), (b) recomputes summary, (c) recomputes charts.
- [ ] Build; screenshot `/tmp/db1.png`; verify chips + summary + 记账 ¥sum; tap a chip → pool filters + summary changes `/tmp/db2.png`.
- [ ] Commit `feat(today): dashboard chips + summary strip (tested)`

### Task 5.2: charts (rose / bar / treemap) + drill + switch
**Files:** Create `mobile/lib/today/charts.dart`; test `mobile/test/charts_squarify_test.dart`
- [ ] **Test first**: `squarify(List<double> counts, Rect)` → list of Rects with areas ∝ counts, union == rect (within ε), no overlaps. red→green.
- [ ] Three `CustomPainter`s: rose (equal-angle wedges, radius ∝ count, group color, 1px `#0e1626` stroke + legend), bar (one bar/group, height ∝ count, gradient, count above/label below), treemap (squarify, cell = color@.82, label TL + count BR). Grouping = `chartData(filterKey, pool)`: filter==全部 → group by **type**; specific type → group by **domain** (§8). Count-based.
- [ ] Selector below chart (`✿玫瑰 / ▥柱状 / ◳树图`) + swipe to cycle (`chartType` state). Label `{scope}` (今日构成·按类型 / {type}·按领域).
- [ ] Build; screenshots of each chart `/tmp/db3-rose.png` `/tmp/db4-bar.png` `/tmp/db5-tree.png`; verify drill (全部=by type, 记账 selected=by domain).
- [ ] Commit `feat(today): dashboard 3 charts + drill + switch`

---

## Slice 6: detail sheet wire + flash pill + 4 edge states

### Task 6.1: edge states end-to-end
**Files:** Modify `today_page.dart`
- [ ] Verify the 4 cases compose correctly (README "Empty / edge states"): (1) full day; (2) only chain, no records → Next Action cards + **dashboard hidden** + pool empty-state; (3) only records → Next Action empty + dashboard+pool populated; (4) all empty → both empty states, clean welcome. The component-level empties already exist; this task wires the dashboard-hidden-when-no-records condition + confirms layering.
- [ ] Seed each case (adapt `seed_test_day.py` to today / clear) and screenshot all four `/tmp/edge1-4.png`.
- [ ] Commit `feat(today): 4 edge states verified`

---

## Slice 7: polish

### Task 7.1: design-review pass
- [ ] Run `/design-review` against the live TodayPage (bubble material/light, chart art, panel layering, empty-state warmth, fan peek angles, motion curves). Apply fixes atomically.铁律: 高级 / 直观 / 有交互, not toy-like.
- [ ] Commit each fix.

### Task 7.2: spec sync
- [ ] Update [04-frontend §4.5.0](04-frontend.md) + [handoff-today-landing.md](handoff-today-landing.md) status → ✅ landed (commit refs), note the resolved decisions (engine=self-written, cap=50, battery gating).
- [ ] Commit `docs(spec): Today page landed`

---

## Self-review (spec coverage)

- handoff §1 nav → Slice 1. Part 1 Next Action → Slice 3 (deck/countdown/no-time/morning-brief/empty all covered). Part 2 pool → Slice 4 (color/glyph/tap/drag/tilt/drop-in/sleep). Part 2 dashboard → Slice 5 (chips/summary/3 charts/drill). detail sheet → reused (6). 4 edge states → 6.1. summary special-casing → 5.1 (记账 sum, else latest-one). data (no new model) → Slice 2 + 0.2. don't-do (no support.js / no DEMO panel / 8 colors / flash=pill / no 段视图) → respected throughout. build order = handoff §6. **Gap check:** Reka radar menu for 我的岛 (1.3) depends on §4.1 existing — flagged as a stop-and-report if absent, not silently skipped.
