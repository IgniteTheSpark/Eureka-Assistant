# Theme V2 Today Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Today-only Theme V2 Home, backed by the independent Theme V2 `/api/today` read model, with no Goal surface or dependency and with correct geometry, inactive lifecycle, Dock integration, responsive behavior, and visual regression coverage.

**Architecture:** The new backend assembles one ownership-safe Today read model from UserSkill, Asset, Event, and Notification truth. A new injectable Flutter repository maps that response into Theme V2 Home models while the legacy `TodayPage`/`loadToday` path remains untouched; the Theme V2 shell passes an explicit `active` flag and owns shared Dock chrome.

**Tech Stack:** FastAPI, SQLAlchemy 2 async, MySQL 8, Flutter/Dart, existing Theme V2 foundation/shell, `flutter_test`, golden tests.

## Global Constraints

- Visual truth is `spec/design/theme-v2-today-handoff.md` and Pen section `PYuZt` after the Pen owner's changes land.
- This plan treats `spec/design/redesignureka.pen` as read-only; do not edit or commit it from this implementation stream.
- Current Home exposes Today only; `secondary = null` and has no visible, interactive, layout, gesture, or semantics footprint.
- Do not add, restore, request, cache, route, track, or feature-flag Goal.
- Do not filter user-authored content merely because it contains the Chinese word `目标`; filtering is by queue item type only.
- Reference viewport is 411 × 960; panel is `x=8, y=54, w=395, h=790`; Dock remains `x=121, y=865, w=169, h=60`.
- At widths above 411, the 395px panel is horizontally centered. Below 411, horizontal margins are 8px.
- Today Panel starts 10px below the top SafeArea and shrinks above Dock clearance when height is insufficient.
- Light/Dark use one component tree; minimum hit target is 44 × 44; motion respects reduced motion.
- Leaving Home pauses BubblePool ticker, tilt sensors, and repeating animation through `active=false` and `TickerMode`.
- Theme V2 Today uses `THEME_V2_API_BASE`, default `http://localhost:8100`; legacy surfaces keep `API_BASE` during staged migration.
- This plan does not stop the legacy Docker stack or claim app-wide backend independence for Calendar/Library routes outside the current scope.

---

## File Structure

### Backend Create

- `theme_v2_service/app/domains/today/schemas.py`
- `theme_v2_service/app/domains/today/service.py`
- `theme_v2_service/app/domains/today/api.py`
- `theme_v2_service/tests/unit/test_today_queue_filter.py`
- `theme_v2_service/tests/integration/test_today_read_model.py`
- `theme_v2_service/tests/contract/test_today_api.py`

### Mobile Create

- `mobile/lib/theme_v2/home/home_models.dart`
- `mobile/lib/theme_v2/home/home_layer_state.dart`
- `mobile/lib/theme_v2/home/home_controller.dart`
- `mobile/lib/theme_v2/home/home_repository.dart`
- `mobile/lib/theme_v2/home/theme_v2_home_page.dart`
- `mobile/lib/theme_v2/home/home_today_panel.dart`
- `mobile/lib/theme_v2/home/home_agenda_panel.dart`
- `mobile/lib/theme_v2/home/home_reka_queue.dart`
- `mobile/lib/theme_v2/home/home_asset_field.dart`
- `mobile/test/theme_v2/home/home_layer_state_test.dart`
- `mobile/test/theme_v2/home/home_repository_test.dart`
- `mobile/test/theme_v2/home/theme_v2_home_page_test.dart`
- `mobile/test/theme_v2/home/theme_v2_home_golden_test.dart`
- `mobile/test/theme_v2/home/theme_v2_home_shell_golden_test.dart`
- `mobile/test/theme_v2/home/goldens/home-today-411-light.png`
- `mobile/test/theme_v2/home/goldens/home-today-411-dark.png`
- `mobile/test/theme_v2/home/goldens/home-agenda-411-light.png`
- `mobile/test/theme_v2/home/goldens/home-agenda-411-dark.png`
- `mobile/test/theme_v2/home/goldens/home-shell-today-411-light.png`
- `mobile/test/theme_v2/home/goldens/home-shell-today-411-dark.png`

### Modify

- `theme_v2_service/app/main.py`
- `mobile/lib/config.dart`
- `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- `mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart`
- `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`
- `mobile/test/theme_v2/shell/theme_v2_shell_test.dart`

### Preserve

- `mobile/lib/pages/today_page.dart`
- `mobile/lib/today/today_data.dart`
- `mobile/lib/today/bubble_pool.dart` business destinations and physics behavior
- `spec/design/redesignureka.pen`

---

### Task 1: Define and serve the independent `/api/today` read model

**Files:**

- Create: `theme_v2_service/app/domains/today/schemas.py`
- Create: `theme_v2_service/app/domains/today/service.py`
- Create: `theme_v2_service/app/domains/today/api.py`
- Modify: `theme_v2_service/app/main.py`
- Create: `theme_v2_service/tests/unit/test_today_queue_filter.py`
- Create: `theme_v2_service/tests/integration/test_today_read_model.py`
- Create: `theme_v2_service/tests/contract/test_today_api.py`

**Interfaces:**

- Consumes: current user, local day/timezone, UserSkill, Asset, Event, and Notification.
- Produces: authenticated `GET /api/today` and stable `TodayResponse`.

- [ ] **Step 1: Write failing response and ownership tests**

Add four async tests with the exact names
`test_today_returns_only_current_user_records`,
`test_today_uses_effective_time_for_agenda_and_created_time_for_pool`,
`test_today_keeps_user_text_containing_target_word`, and
`test_today_filters_goal_queue_types_and_recounts`. Seed both owners, one
effective-today Asset created yesterday, one created-today Asset effective
tomorrow, a Todo titled `更新个人目标`, and Goal/non-Goal Notification types.
Assert ownership isolation, the two separate time semantics, preserved Todo
text, and Queue count derived only from the non-Goal allowlist.

- [ ] **Step 2: Define the response schema**

```python
class TodayResponse(BaseModel):
    generated_at: datetime
    timezone: str
    chain: list[TodayAction]
    no_time_todos: list[TodayAction]
    pool: list[TodayAsset]
    pool_true_count: int
    flash_count: int = 0
    todo_done: int
    todo_total: int
    flash_latest_id: str | None = None
    skills: dict[str, TodaySkillMeta]
    reka_queue: list[TodayQueueItem]
```

`TodayAction` includes `kind`, `id`, `title`, `effective_at`, `timed`, `subtitle`, `domain`, `end_at`, `done`, and canonical destination. `TodayAsset` includes `id`, `type`, `domain`, `title`, `payload`, and `created_at`. `TodayQueueItem` includes `id`, `type`, `title`, `body`, `link`, and `created_at`.

- [ ] **Step 3: Define the queue contract explicitly**

Phase 1 queue uses unread Notifications of these non-Goal types, newest first, maximum 10:

```python
TODAY_QUEUE_TYPES = frozenset({
    "reminder", "report_available", "report_plan_ready", "report_done",
    "report_failed", "task_done", "task_failed", "flash_done",
})


def include_today_queue_item(notification: Notification) -> bool:
    return not notification.read and notification.type in TODAY_QUEUE_TYPES
```

Never inspect title/body text for Goal keywords. Unknown types stay in notification history but do not enter the compact Today Queue.

- [ ] **Step 4: Assemble the read model with bounded queries**

Use the requested timezone or configured user timezone to compute the local day, convert bounds to UTC, and query:

- today's and upcoming owned Events/Todos for chain/agenda;
- Assets created during the local day for bubble pool, newest first, body capped at 50 but true count uncapped;
- UserSkill display name/icon/schema metadata used by returned Assets;
- unread Queue Notifications using the explicit type allowlist.

Treat a Todo as an Asset whose UserSkill machine name is `todo`; derive done from payload `status == done` or `done == true`. `flash_count` remains zero until a V2 Flash session source exists; do not call the legacy backend.

- [ ] **Step 5: Expose the authenticated route**

```python
@router.get("/today", response_model=TodayResponse)
async def get_today(
    timezone_name: str | None = Query(default=None, alias="timezone"),
    user_id: str = Depends(get_current_user_id),
) -> TodayResponse:
    zone = validate_timezone(timezone_name or get_settings().default_user_timezone)
    async with AsyncSessionFactory() as session:
        return await build_today_response(session, user_id=user_id, now=utc_now(), zone=zone)
```

Reject invalid IANA timezone names with `422` and never accept a request-body user ID.

- [ ] **Step 6: Run backend tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_today_queue_filter.py tests/integration/test_today_read_model.py tests/contract/test_today_api.py -q`

Expected: ordering, counts, timezone, ownership, Goal-type filtering, text preservation, and empty-state cases PASS.

- [ ] **Step 7: Commit**

```bash
git add theme_v2_service/app/domains/today theme_v2_service/app/main.py theme_v2_service/tests/unit/test_today_queue_filter.py theme_v2_service/tests/integration/test_today_read_model.py theme_v2_service/tests/contract/test_today_api.py
git commit -m "feat(theme-v2): add today read model"
```

---

### Task 2: Add Flutter Home models and independent repository

**Files:**

- Create: `mobile/lib/theme_v2/home/home_models.dart`
- Create: `mobile/lib/theme_v2/home/home_repository.dart`
- Modify: `mobile/lib/config.dart`
- Create: `mobile/test/theme_v2/home/home_repository_test.dart`

**Interfaces:**

- Consumes: `GET /api/today` at `AppConfig.themeV2ApiBase`.
- Produces: `ThemeV2HomeData`, `ThemeV2HomeRepository`, and `ApiThemeV2HomeRepository`.

- [ ] **Step 1: Write a failing JSON mapping test**

```dart
test('maps Theme V2 Today response including filtered Reka Queue', () async {
  final repository = ApiThemeV2HomeRepository(
    api: ApiClient(client: fakeClient(todayJson), baseUrl: 'http://theme-v2'),
  );
  final data = await repository.load();
  expect(data.today.chain.single.title, '团队周会');
  expect(data.today.poolTrueCount, 3);
  expect(data.rekaQueue.single.type, 'report_available');
});
```

- [ ] **Step 2: Add a separate compile-time base URL**

```dart
static const themeV2ApiBase = String.fromEnvironment(
  'THEME_V2_API_BASE',
  defaultValue: 'http://localhost:8100',
);
```

Do not change `AppConfig.apiBase` or point legacy Calendar/Library calls to 8100 in this task.

- [ ] **Step 3: Define immutable Home models**

`ThemeV2HomeData` contains `TodayData today` plus
`List<HomeQueueItem> rekaQueue`, with `empty` and strict `fromJson`. Map the
backend chain, no-time Todo, pool, counts, flash summary, and Skill metadata into
the existing `TodayData`/`ChainItem`/`PoolAsset` classes; do not duplicate those
display models. Queue items contain only the server fields above; no Goal field
or fallback parser exists.

- [ ] **Step 4: Implement the repository**

```dart
abstract interface class ThemeV2HomeRepository {
  Future<ThemeV2HomeData> load();
}

class ApiThemeV2HomeRepository implements ThemeV2HomeRepository {
  ApiThemeV2HomeRepository({ApiClient? api})
      : _api = api ?? ApiClient(baseUrl: AppConfig.themeV2ApiBase),
        _ownsApi = api == null;

  final ApiClient _api;
  final bool _ownsApi;

  @override
  Future<ThemeV2HomeData> load() async =>
      ThemeV2HomeData.fromJson((await _api.getJson('/api/today')) as Map<String, dynamic>);

  void dispose() { if (_ownsApi) _api.close(); }
}
```

- [ ] **Step 5: Run repository tests**

Run: `cd mobile && flutter test test/theme_v2/home/home_repository_test.dart`

Expected: success, empty, malformed JSON, HTTP error, and independent base URL tests PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/config.dart mobile/lib/theme_v2/home/home_models.dart mobile/lib/theme_v2/home/home_repository.dart mobile/test/theme_v2/home/home_repository_test.dart
git commit -m "feat(theme-v2): connect home to today api"
```

---

### Task 3: Add Today-only Home state, lifecycle, and responsive geometry

**Files:**

- Create: `mobile/lib/theme_v2/home/home_layer_state.dart`
- Create: `mobile/lib/theme_v2/home/home_controller.dart`
- Create: `mobile/lib/theme_v2/home/theme_v2_home_page.dart`
- Create: `mobile/test/theme_v2/home/home_layer_state_test.dart`
- Create: `mobile/test/theme_v2/home/theme_v2_home_page_test.dart`

**Interfaces:**

- Consumes: `ThemeV2HomeRepository`, `dataRevision`, and `active`.
- Produces: `ThemeV2HomePage(active: bool)`, Today/Agenda presentation, stable load/refresh/error lifecycle.

- [ ] **Step 1: Write failing layer and lifecycle tests**

Test `secondary == null`, Today↔Agenda without layer creation, one initial load, refresh retaining old data, initial error retry, injected object ownership, active false, and Calendar→Home state preservation.

- [ ] **Step 2: Write exact geometry tests**

At 411 × 960 assert panel top-left `Offset(8, 54)` and size `Size(395, 790)`. At 500px width assert left `(500 - 395) / 2 = 52.5`. At 360px assert left 8 and width 344. At short height assert panel bottom stays above `ThemeV2FloatingDock.contentClearance`.

- [ ] **Step 3: Implement state contracts**

```dart
enum HomeSurface { today }
enum HomePresentation { today, agenda }

class HomeLayerState {
  const HomeLayerState({this.primary = HomeSurface.today, this.secondary});
  static const current = HomeLayerState();
  final HomeSurface primary;
  final HomeSurface? secondary;
  bool get hasSecondary => secondary != null;
}
```

`ThemeV2HomeController` is a ChangeNotifier with only `openAgenda()` and `closeAgenda()`.

- [ ] **Step 4: Implement page ownership and refresh lifecycle**

```dart
class ThemeV2HomePage extends StatefulWidget {
  const ThemeV2HomePage({
    super.key,
    required this.active,
    this.controller,
    this.repository,
  });
  final bool active;
  final ThemeV2HomeController? controller;
  final ThemeV2HomeRepository? repository;
}
```

Own/dispose only internally created objects. Initial load shows Theme V2 loading; refresh keeps data; initial error shows retry; refresh error keeps data and announces a light message. Reload on `dataRevision` change.

- [ ] **Step 5: Implement centered responsive geometry**

```dart
final panelWidth = constraints.maxWidth >= 411
    ? 395.0
    : math.max(0.0, constraints.maxWidth - 16.0);
final panelLeft = (constraints.maxWidth - panelWidth) / 2;
final panelHeight = math.min(790.0, math.max(0.0, constraints.maxHeight - 10.0));
```

The enclosing Theme V2 scaffold already applies top SafeArea and Dock content clearance, so page-relative top is 10 and full-screen top is 54 at the reference viewport.

- [ ] **Step 6: Gate animations and tickers**

Wrap the page subtree in `TickerMode(enabled: widget.active)` and pass `active` to the Asset field/BubblePool adapter. When `active` changes false, no reload occurs and presentation/scroll state remains.

- [ ] **Step 7: Run state and geometry tests**

Run: `cd mobile && flutter test test/theme_v2/home/home_layer_state_test.dart test/theme_v2/home/theme_v2_home_page_test.dart`

Expected: all lifecycle, geometry, ownership, and inactive tests PASS.

- [ ] **Step 8: Commit**

```bash
git add mobile/lib/theme_v2/home/home_layer_state.dart mobile/lib/theme_v2/home/home_controller.dart mobile/lib/theme_v2/home/theme_v2_home_page.dart mobile/test/theme_v2/home/home_layer_state_test.dart mobile/test/theme_v2/home/theme_v2_home_page_test.dart
git commit -m "feat(theme-v2): add today-only home lifecycle"
```

---

### Task 4: Implement Today, Reka Queue, Asset field, and Agenda panels

**Files:**

- Create: `mobile/lib/theme_v2/home/home_today_panel.dart`
- Create: `mobile/lib/theme_v2/home/home_reka_queue.dart`
- Create: `mobile/lib/theme_v2/home/home_asset_field.dart`
- Create: `mobile/lib/theme_v2/home/home_agenda_panel.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_home_page.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_home_page_test.dart`

**Interfaces:**

- Consumes: `ThemeV2HomeData`, controller callbacks, active flag, canonical Asset/Event destinations.
- Produces: handoff-aligned Default and Agenda component trees.

- [ ] **Step 1: Write failing content and absence tests**

Test Next Moment, no-next empty state, Queue count after server filtering, queue-only Goal fixture absence, ordinary title `更新个人目标` retained, empty Queue, bubble tap destination, Agenda open/close, no horizontal layer drag, 44px controls, and no Goal semantics.

- [ ] **Step 2: Implement `HomeTodayPanel`**

Render in exact order: localized Today/date header, Next Moment, Reka Queue, Asset bubble field, Agenda open action. Use Theme V2 tokens and radius 18. Truncate long Next Moment title to one line without changing region height.

- [ ] **Step 3: Implement `HomeRekaQueue`**

Render only `data.rekaQueue`; count equals list length. Empty/list/loading height is stable. Item tap sends its opaque `type + link` to the existing notification target router; the widget never parses Goal or deletes text by keyword.

- [ ] **Step 4: Adapt the existing physics field**

Reuse BubblePool rendering/physics through a focused adapter that maps `HomeAsset` to existing pool input. Preserve canonical Asset destinations, internal overflow behavior, and stable empty structure. Pass `active` through; remove the old background horizontal layer-switch callback.

- [ ] **Step 5: Implement Agenda/Fishbone**

Use the same outer panel. Header contains a 44 × 44 close action; the Agenda viewport is Expanded and scrollable; generated-asset chamber has fixed height and remains at panel bottom. Reclaimed vertical space benefits the viewport. Internal horizontal content must not register a Home-layer gesture.

- [ ] **Step 6: Run component tests**

Run: `cd mobile && flutter test test/theme_v2/home/theme_v2_home_page_test.dart`

Expected: all data, interaction, accessibility, inactive, and Goal-absence tests PASS.

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/theme_v2/home/home_today_panel.dart mobile/lib/theme_v2/home/home_reka_queue.dart mobile/lib/theme_v2/home/home_asset_field.dart mobile/lib/theme_v2/home/home_agenda_panel.dart mobile/lib/theme_v2/home/theme_v2_home_page.dart mobile/test/theme_v2/home/theme_v2_home_page_test.dart
git commit -m "feat(theme-v2): implement today and agenda panels"
```

---

### Task 5: Mount Home with correct active state and shell chrome

**Files:**

- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_shell_test.dart`

**Interfaces:**

- Consumes: `ThemeV2HomePage(active: bool)`.
- Produces: tab 0 without Top Nav, with shared persistent Dock, and correct off-tab lifecycle.

- [ ] **Step 1: Write the failing production-shell test**

```dart
expect(find.byType(ThemeV2HomePage), findsOneWidget);
expect(find.byType(ThemeV2GlobalTopNav), findsNothing);
expect(find.byKey(ThemeV2FloatingDock.dockKey), findsOneWidget);
expect(find.text('目标'), findsNothing);
```

Switch Home→Calendar and assert the retained Home receives `active=false`; switch back and assert the same controller/presentation/scroll state remains and `active=true` resumes.

- [ ] **Step 2: Add injectable Home dependencies to the shell**

Add optional `ThemeV2HomeRepository? homeRepository` and `ThemeV2HomeController? homeController` constructor fields for tests. Production defaults create the API repository inside Home.

- [ ] **Step 3: Replace legacy tab 0**

```dart
ThemeV2PageScaffold(
  body: ThemeV2HomePage(
    active: _index == 0,
    repository: widget.homeRepository,
    controller: widget.homeController,
  ),
  showTopNav: false,
)
```

Remove only the unused `TodayPage` import from Theme V2 shell; preserve legacy TodayPage itself.

- [ ] **Step 4: Align Dock safe-area geometry**

Remove the extra `ThemeV2Spacing.md` below the shared Dock: bottom padding is
exactly `MediaQuery.paddingOf(context).bottom`. Keep width 169, height 60, and
`contentClearance = 80`. At 411 × 960 with top/bottom safe insets 44/35, this
places the Dock at y=865 and leaves the Today panel bottom at y=844.

- [ ] **Step 5: Run shell tests**

Run: `cd mobile && flutter test test/theme_v2/shell/theme_v2_navigation_state_test.dart test/theme_v2/shell/theme_v2_shell_test.dart`

Expected: Dock, top-nav absence, active lifecycle, IndexedStack persistence, Calendar home reset, and Library home behavior PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart mobile/test/theme_v2/shell/theme_v2_shell_test.dart
git commit -m "feat(theme-v2): mount active today home"
```

---

### Task 6: Add page and shell visual regression coverage

**Files:**

- Create: `mobile/test/theme_v2/home/theme_v2_home_golden_test.dart`
- Create: `mobile/test/theme_v2/home/theme_v2_home_shell_golden_test.dart`
- Create: six PNG files under `mobile/test/theme_v2/home/goldens/`

**Interfaces:**

- Consumes: fixed repository fixtures, Home controller, and real Theme V2 shell/Dock.
- Produces: four panel goldens and two full-shell Dock goldens.

- [ ] **Step 1: Create deterministic fixtures**

Use fixed 2026-07-31 timestamps, one timed Event, one no-time Todo titled `更新个人目标`, three Assets, one `report_available` Queue item, and one filtered `goal_progress` server fixture used only in repository/backend tests. Disable animations and use text scale 1.

- [ ] **Step 2: Write page-level golden tests**

Render ThemeV2HomePage at 411 × 960 in Light/Dark and Today/Agenda. These images verify the panel and internal composition only; they do not claim to verify Dock.

- [ ] **Step 3: Write shell-level golden tests**

Render the real `ThemeV2AppShell` at 411 × 960 with injected Home repository and startup overlays disabled. Capture Light/Dark Today state and assert Dock bounds `x=121, y=865, w=169, h=60`, panel bottom 844, and 21px visual separation.

- [ ] **Step 4: Generate images**

Run: `cd mobile && flutter test --update-goldens test/theme_v2/home/theme_v2_home_golden_test.dart test/theme_v2/home/theme_v2_home_shell_golden_test.dart`

Expected: six PNG files are created.

- [ ] **Step 5: Inspect all six images**

Verify Light/Dark geometry identity, no Goal affordance, preserved user Todo text, centered panel, Agenda chamber bottom alignment, Dock clearance, no top nav, and no clipped 44px action.

- [ ] **Step 6: Run without updating**

Run: `cd mobile && flutter test test/theme_v2/home/theme_v2_home_golden_test.dart test/theme_v2/home/theme_v2_home_shell_golden_test.dart`

Expected: all golden tests PASS.

- [ ] **Step 7: Commit**

```bash
git add mobile/test/theme_v2/home/theme_v2_home_golden_test.dart mobile/test/theme_v2/home/theme_v2_home_shell_golden_test.dart mobile/test/theme_v2/home/goldens
git commit -m "test(theme-v2): add today page and shell goldens"
```

---

### Task 7: Run backend/frontend integration and Goal-absence gates

**Files:**

- Modify only if a test exposes a defect: files created by Tasks 1–6.

**Interfaces:**

- Consumes: running Theme V2 API at 8100 and Theme V2 Flutter shell.
- Produces: a reproducible integration proof with no legacy Today data calls.

- [ ] **Step 1: Seed isolated Theme V2 data**

Create one test user token, Todo Skill, custom Skill, current Event, Todo containing `目标` in its title, three Assets, and one report notification in the new MySQL database. Do not seed or read the legacy database.

- [ ] **Step 2: Verify the API contract**

Run: `curl -fsS -H "Authorization: Bearer $THEME_V2_TEST_TOKEN" "http://localhost:8100/api/today?timezone=Asia%2FShanghai"`

Expected: owned Today data, non-Goal queue count, and no Goal type.

- [ ] **Step 3: Run focused Flutter tests**

Run: `cd mobile && flutter test test/theme_v2/home test/theme_v2/shell/theme_v2_navigation_state_test.dart test/theme_v2/shell/theme_v2_shell_test.dart`

Expected: all tests PASS.

- [ ] **Step 4: Run static analysis on changed Dart files**

Run: `cd mobile && flutter analyze lib/config.dart lib/theme_v2/home lib/theme_v2/shell/theme_v2_app_shell.dart test/theme_v2/home test/theme_v2/shell/theme_v2_navigation_state_test.dart test/theme_v2/shell/theme_v2_shell_test.dart`

Expected: `No issues found!`.

- [ ] **Step 5: Search active production code for Goal dependencies**

Run: `rg -n "Goal|goal|目标" mobile/lib/theme_v2/home mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`

Expected: no production dependency or visible Goal copy; test fixtures/comments documenting absence may appear only under tests.

- [ ] **Step 6: Verify Home no longer calls legacy Today endpoints**

Run: `rg -n "loadToday|/api/timeline|/api/contacts|/api/sessions" mobile/lib/theme_v2/home`

Expected: no matches; `ApiThemeV2HomeRepository` calls only `/api/today`.

- [ ] **Step 7: Commit any test-driven corrections**

Stage only files changed to make the named gates pass, then commit:

```bash
git commit -m "fix(theme-v2): close today integration gaps"
```

Skip this commit when no correction was required.

---

## Completion Gate

- Theme V2 Today receives real data only from the independent service's `/api/today` endpoint.
- Legacy `TodayPage` and `loadToday` remain intact for rollback and are not mounted by Theme V2 shell.
- The panel, SafeArea, Dock, wide/narrow layouts, Default/Agenda states, Light/Dark, and inactive lifecycle match the handoff.
- Reka Queue has an explicit non-Goal backend contract and never filters ordinary user text.
- Page-level and shell-level goldens cover their actual ownership boundaries.
- Pen changes remain owned by the existing Pen task and are not overwritten by this plan.
