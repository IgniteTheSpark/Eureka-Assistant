# Theme V2 Home Visual Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Theme V2 root surfaces with one title hierarchy, three independent Home regions, an open-top bounded gravity chamber, canonical asset glyphs, deterministic 50-ball replacement, and a semantic Home Dock icon.

**Architecture:** Keep the existing Shell, repositories, `TodayData`, Forge2D `BubbleField`, and navigation controllers. Move root-page title styling into one shared widget, make Home a viewport-aware vertical document, render the gravity chamber as a dedicated bounded component, and layer retirement snapshots over the unchanged maximum of 50 physical bodies.

**Tech Stack:** Flutter/Dart, Material, Forge2D, sensors_plus, Widget tests, Golden tests, Android ADB acceptance.

## Global Constraints

- Do not change Theme V2 navigation architecture, tab order, backend APIs, or database models.
- Home has three independent regions: Next Moment, Reka, and the open-top gravity chamber; there is no page-sized outer panel.
- Root titles are exactly `今日`, `日历`, and `资产库`, rendered at 22px with the same horizontal position.
- The gravity chamber itself never scrolls; on a short viewport the entire Home document may scroll as one rigid layout.
- Preserve the large `poolTrueCount` watermark, real collisions, device gravity, dragging, tapping, and rotating ball artwork.
- Physical bodies remain capped at the newest 50 assets; the watermark shows the uncapped true count.
- No 3D chamber, 360-degree rotation, or new rendering/physics dependency in this iteration.
- Respect Reduce Motion, App lifecycle pause, 44px hit targets, Light/Dark tokens, 360px width, and connected-device verification.

---

### Task 1: Canonical asset glyphs across Home, Agenda, timeline, and Core Detail

**Files:**
- Modify: `mobile/lib/timeline/timeline.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Modify: `mobile/lib/theme_v2/home/home_today_panel.dart`
- Modify: `mobile/lib/theme_v2/home/home_agenda_panel.dart`
- Modify: `mobile/lib/theme_v2/asset_detail/asset_detail_repository.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_home_page_test.dart`
- Modify: `mobile/test/timeline_theme_v2_service_regression_test.dart`
- Modify: `mobile/test/theme_v2/asset_detail/asset_detail_repository_test.dart`

**Interfaces:**
- Produces: `resolveMeta(String key, Map<String, SkillMeta> registry) -> SkillMeta` with canonical aliases and custom-skill priority.
- Extends: `ThemeV2AssetBubbleField` with `skills: Map<String, SkillMeta>`.
- Consumes: `TodayData.skills`, which already contains server skill icons and labels.

- [ ] **Step 1: Write failing resolver and widget tests**

Add pure resolver coverage to `timeline_theme_v2_service_regression_test.dart`:

```dart
test('asset aliases and expense share canonical glyphs', () {
  expect(resolveMeta('todo', const {}).icon, '📋');
  expect(resolveMeta('calendar', const {}).icon, '📅');
  expect(resolveMeta('note', const {}).icon, '✍️');
  expect(resolveMeta('idea', const {}).icon, '✍️');
  expect(resolveMeta('misc', const {}).icon, '✍️');
  expect(resolveMeta('expense', const {}).icon, '💳');
  expect(resolveMeta('unknown', const {}).icon, '•');
});

test('custom skill registry keeps its configured glyph', () {
  const registry = {
    'tennis': SkillMeta('🎾', '网球记录', 'green'),
  };

  expect(resolveMeta('tennis', registry).icon, '🎾');
});
```

Extend `_pumpField` in `theme_v2_asset_bubble_field_test.dart` with a `skills` argument and pass it to the widget. Add:

```dart
testWidgets('bubble renders canonical and custom skill glyphs', (tester) async {
  final expense = PoolAsset(
    id: 'expense-1',
    type: 'expense',
    domain: 'life',
    title: '午餐',
    payload: const {'amount': 88},
    createdAt: DateTime(2026, 8, 3, 11),
  );
  final tennis = PoolAsset(
    id: 'tennis-1',
    type: 'tennis',
    domain: 'sport',
    title: '晚间网球',
    payload: const {'duration': 60},
    createdAt: DateTime(2026, 8, 3, 12),
  );

  await _pumpField(
    tester,
    assets: [expense, tennis],
    disableAnimations: true,
    skills: const {'tennis': SkillMeta('🎾', '网球记录', 'green')},
  );

  expect(find.text('💳'), findsOneWidget);
  expect(find.text('🎾'), findsOneWidget);
  expect(find.byIcon(Icons.restaurant_outlined), findsNothing);
});
```

Add a Core Detail assertion that an expense skill model has `icon == '💳'`.

- [ ] **Step 2: Run focused tests and verify legacy mappings fail**

Run:

```bash
cd mobile
flutter test test/timeline_theme_v2_service_regression_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart test/theme_v2/asset_detail/asset_detail_repository_test.dart
```

Expected: alias/custom widget tests fail because Home still renders Material icons and expense fallback differs.

- [ ] **Step 3: Canonicalize the shared resolver**

In `timeline.dart`, change the expense fallback to `💳` and implement alias lookup after custom-registry lookup:

```dart
const _builtin = <String, SkillMeta>{
  'todo': SkillMeta(todoAssetIcon, '待办', 'blue'),
  'event': SkillMeta(eventAssetIcon, '日程', 'purple'),
  'contact': SkillMeta(contactAssetIcon, '名片', 'neutral'),
  'notes': SkillMeta(notesAssetIcon, '随记', 'amber'),
  'expense': SkillMeta('💳', '记账', 'green'),
  'external_ref': SkillMeta('🔗', '外部', 'purple'),
};

String _canonicalSkillKey(String key) => switch (key.trim().toLowerCase()) {
  'calendar' => 'event',
  'note' || 'idea' || 'misc' => 'notes',
  final normalized => normalized,
};

SkillMeta resolveMeta(String key, Map<String, SkillMeta> registry) {
  final normalized = key.trim().toLowerCase();
  final registered = registry[normalized] ?? registry[key];
  final canonical = _canonicalSkillKey(normalized);
  final meta = registered ?? _builtin[canonical] ?? SkillMeta('•', key);
  final pin = _pinnedIcons[canonical];
  return pin == null
      ? meta
      : SkillMeta(
          pin,
          meta.label,
          meta.accentColor,
          meta.userSkillId,
          meta.enabled,
        );
}
```

In `asset_detail_repository.dart`, import `timeline.dart` and replace `_coreAssetIcon` with:

```dart
String _coreAssetIcon(String machineName) =>
    resolveMeta(machineName, const <String, SkillMeta>{}).icon;
```

- [ ] **Step 4: Render glyph text in Home and Agenda**

Add `skills` to `ThemeV2AssetBubbleField`:

```dart
  const ThemeV2AssetBubbleField({
    super.key,
    required this.assets,
    required this.trueCount,
    this.skills = const {},
    this.active = true,
    this.gravityStream,
    this.onOpenAsset,
  });

  final Map<String, SkillMeta> skills;
```

Pass `data.skills` from `HomeTodayPanel`, thread the map through compact and animated visuals, and replace `_assetIcon` with:

```dart
Text(
  resolveMeta(asset.type, skills).icon,
  textAlign: TextAlign.center,
  style: TextStyle(
    fontSize: math.min(22, constraints.maxWidth * 0.31),
    height: 1,
    color: highlighted ? Colors.white : tokens.muted,
  ),
)
```

Delete `_assetIcon`. Add `skills` to `_AgendaBubbleBackdrop`, pass `data.skills`, render the same resolved glyph with `Text`, and delete `_agendaAssetIcon`.

- [ ] **Step 5: Run focused tests and verify they pass**

Run:

```bash
cd mobile
flutter test test/timeline_theme_v2_service_regression_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart test/theme_v2/home/theme_v2_home_page_test.dart test/theme_v2/asset_detail/asset_detail_repository_test.dart
```

Expected: canonical, custom, Home, and Core Detail glyph tests pass.

- [ ] **Step 6: Commit canonical asset identity**

```bash
git add mobile/lib/timeline/timeline.dart mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart mobile/lib/theme_v2/home/home_today_panel.dart mobile/lib/theme_v2/home/home_agenda_panel.dart mobile/lib/theme_v2/asset_detail/asset_detail_repository.dart mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart mobile/test/theme_v2/home/theme_v2_home_page_test.dart mobile/test/timeline_theme_v2_service_regression_test.dart mobile/test/theme_v2/asset_detail/asset_detail_repository_test.dart
git commit -m "fix: unify Theme V2 asset glyphs"
```

---

### Task 2: Shared root-page title and semantic Home Dock icon

**Files:**
- Create: `mobile/lib/theme_v2/shell/theme_v2_page_title.dart`
- Modify: `mobile/lib/theme_v2/library/library_hub.dart`
- Modify: `mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_shell_test.dart`
- Modify: `mobile/test/theme_v2/calendar/theme_v2_calendar_page_test.dart`
- Modify: `mobile/test/theme_v2/library/library_navigation_test.dart`

**Interfaces:**
- Produces: `ThemeV2PageTitle({required String title, Key? key})` with header semantics and exact 22px styling.
- Extends: each Dock destination with `icon` and `selectedIcon`.

- [ ] **Step 1: Write failing title and Dock tests**

Add to `theme_v2_shell_test.dart`:

```dart
testWidgets('root page title exposes shared typography and header semantics', (
  tester,
) async {
  await tester.pumpWidget(
    const _PureThemeV2Host(child: ThemeV2PageTitle(title: '今日')),
  );

  final text = tester.widget<Text>(find.text('今日'));
  expect(text.style?.fontSize, 22);
  expect(text.style?.fontWeight, FontWeight.w700);
  expect(find.bySemanticsLabel('今日'), findsOneWidget);
});
```

Update the Dock assertion for selected index 0 to expect `Icons.home_rounded`, then pump selected index 1 and assert the unselected Today icon is `Icons.home_outlined`.

Add root-surface assertions to Calendar and Library tests:

```dart
expect(find.byKey(const ValueKey('theme-v2-page-title-calendar')), findsOneWidget);
expect(find.text('日历'), findsOneWidget);
```

```dart
final title = find.byKey(const ValueKey('theme-v2-page-title-library'));
expect(title, findsOneWidget);
expect(tester.getTopLeft(title).dx, 18);
```

- [ ] **Step 2: Run focused tests and verify they fail**

Run:

```bash
cd mobile
flutter test test/theme_v2/shell/theme_v2_shell_test.dart test/theme_v2/calendar/theme_v2_calendar_page_test.dart test/theme_v2/library/library_navigation_test.dart
```

Expected: missing `ThemeV2PageTitle`, missing Calendar title, and old sparkle Dock icon failures.

- [ ] **Step 3: Create the shared page title**

Create `theme_v2_page_title.dart`:

```dart
import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';

class ThemeV2PageTitle extends StatelessWidget {
  const ThemeV2PageTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: TextStyle(
          color: context.themeV2.foreground,
          fontFamily: 'Geist',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.2,
        ),
      ),
    );
  }
}
```

Use the keys `theme-v2-page-title-library` and `theme-v2-page-title-calendar` at call sites. In `LibraryHub`, replace the `headlineMedium` title with `ThemeV2PageTitle` and keep the ListView left padding at 18.

In the Calendar overview branch, wrap the existing `Stack` with:

```dart
return Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    const Padding(
      padding: EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: ThemeV2PageTitle(
        key: ValueKey('theme-v2-page-title-calendar'),
        title: '日历',
      ),
    ),
    Expanded(child: calendarOverviewStack),
  ],
);
```

Do not wrap Day Detail or Schedule routes.

- [ ] **Step 4: Give the Dock selected/unselected Home icons**

Change destinations and icon selection to:

```dart
static const _destinations = <({
  IconData icon,
  IconData selectedIcon,
  String label,
})>[
  (
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    label: '今日',
  ),
  (
    icon: Icons.calendar_month_outlined,
    selectedIcon: Icons.calendar_month_outlined,
    label: '日历',
  ),
  (
    icon: Icons.local_library_outlined,
    selectedIcon: Icons.local_library_outlined,
    label: '资产',
  ),
];
```

Pass `selected ? destination.selectedIcon : destination.icon` into `_DockDestination`; keep dimensions, colors, safe area, and semantics unchanged.

- [ ] **Step 5: Run focused tests and verify they pass**

Run the same three Flutter test files. Expected: all pass.

- [ ] **Step 6: Commit title and Dock consistency**

```bash
git add mobile/lib/theme_v2/shell/theme_v2_page_title.dart mobile/lib/theme_v2/library/library_hub.dart mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart mobile/test/theme_v2/shell/theme_v2_shell_test.dart mobile/test/theme_v2/calendar/theme_v2_calendar_page_test.dart mobile/test/theme_v2/library/library_navigation_test.dart
git commit -m "feat: unify Theme V2 root navigation chrome"
```

---

### Task 3: Three-region Home and open-top gravity chamber

**Files:**
- Create: `mobile/lib/theme_v2/home/theme_v2_gravity_chamber.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_home_page.dart`
- Modify: `mobile/lib/theme_v2/home/home_today_panel.dart`
- Modify: `mobile/lib/theme_v2/home/home_agenda_panel.dart`
- Modify: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_home_page_test.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`

**Interfaces:**
- Produces: `ThemeV2GravityChamber({required Widget child})` with `gravity-chamber` key, open visual top, side/bottom boundary, bottom radius, and clipped content.
- Extends: `HomeTodayPanel` with required `double chamberHeight`.
- Produces: viewport-derived chamber height `max(340, ceil(min(assetCount, 50) / floor(contentWidth / 44)) * 44)`.

- [ ] **Step 1: Replace fixed-geometry expectations with failing three-region tests**

In `theme_v2_home_page_test.dart`, replace the Pen fixed-panel assertions with:

```dart
final pageTitle = find.byKey(const ValueKey('theme-v2-page-title-home'));
final nextMoment = find.byKey(HomeTodayPanel.nextMomentKey);
final rekaQueue = find.byKey(HomeTodayPanel.rekaQueueKey);
final chamber = find.byKey(HomeTodayPanel.gravityChamberKey);

expect(tester.getTopLeft(pageTitle).dx, 18);
expect(tester.getTopLeft(nextMoment).dx, 18);
expect(tester.getTopLeft(rekaQueue).dx, 18);
expect(tester.getTopLeft(chamber).dx, 18);
expect(tester.getSize(nextMoment).height, 126);
expect(tester.getSize(rekaQueue).height, 188);
expect(tester.getSize(chamber).height, greaterThanOrEqualTo(340));
expect(
  tester.getTopLeft(rekaQueue).dy - tester.getBottomLeft(nextMoment).dy,
  12,
);
expect(
  tester.getTopLeft(chamber).dy - tester.getBottomLeft(rekaQueue).dy,
  12,
);
```

Add a 360px test that finds a page-level `Scrollable`, asserts no `Scrollable` is a descendant of the chamber, scrolls the complete chamber into view, and verifies its bottom remains at least 24px above the document end.

Change the compact-field test in `theme_v2_asset_bubble_field_test.dart` to assert `find.descendant(of: field, matching: find.byType(Scrollable))` finds nothing while all 50 44px targets fit inside the supplied 304×480 chamber.

Add an empty-chamber assertion:

```dart
await _pumpField(tester, assets: const [], disableAnimations: true);
expect(find.text('0'), findsOneWidget);
expect(find.text('今日生成'), findsOneWidget);
expect(find.text('今天生成的资产会落在这里'), findsOneWidget);
```

- [ ] **Step 2: Run Home tests and verify fixed-panel failures**

Run:

```bash
cd mobile
flutter test test/theme_v2/home/theme_v2_home_page_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
```

Expected: failures for missing title/chamber keys, fixed panel offsets, and the current compact internal GridView.

- [ ] **Step 3: Implement the open-top chamber painter**

Create `theme_v2_gravity_chamber.dart` with a Stack that paints the gradient before its child and side/bottom strokes after it. The painter path is exact:

```dart
import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';

const double themeV2HomePanelRadius = 19;

class ThemeV2GravityChamber extends StatelessWidget {
  const ThemeV2GravityChamber({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(themeV2HomePanelRadius),
        bottomRight: Radius.circular(themeV2HomePanelRadius),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tokens.surface.withValues(alpha: 0),
                  tokens.surface.withValues(alpha: 0.72),
                  tokens.background.withValues(alpha: 0.9),
                ],
                stops: const [0, 0.18, 1],
              ),
            ),
          ),
          child,
          IgnorePointer(
            child: CustomPaint(
              painter: _GravityChamberBorderPainter(
                color: tokens.border.withValues(alpha: 0.78),
                radius: themeV2HomePanelRadius,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GravityChamberBorderPainter extends CustomPainter {
  const _GravityChamberBorderPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..moveTo(0.5, 48)
      ..lineTo(0.5, size.height - radius)
      ..quadraticBezierTo(0.5, size.height - 0.5, radius, size.height - 0.5)
      ..lineTo(size.width - radius, size.height - 0.5)
      ..quadraticBezierTo(
        size.width - 0.5,
        size.height - 0.5,
        size.width - 0.5,
        size.height - radius,
      )
      ..lineTo(size.width - 0.5, 48);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_GravityChamberBorderPainter oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}
```

The chamber background uses a transparent-to-surface gradient over the top 56px and a surface-to-background vertical gradient below it. Clip only the lower corners at `homePanelRadius`; do not draw a top border.

Remove `homePanelRadius` from `home_today_panel.dart`, import `theme_v2_gravity_chamber.dart`, and use `themeV2HomePanelRadius` in the remaining Home/Agenda card radii. This keeps one radius constant without an import cycle.

- [ ] **Step 4: Convert Home to a viewport-aware vertical document**

Keep `ThemeV2HomePage.panelKey` as the page document key, but remove `referencePanelSize`, `_panelSize`, fixed `Positioned`, and `_HomeStateSurface`. Build:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final contentWidth = math.max(0, constraints.maxWidth - 36);
    final columns = math.max(1, (contentWidth / 44).floor());
    final rows = (math.min(_data?.pool.length ?? 0, 50) + columns - 1) ~/ columns;
    final chamberHeight = math.max(340.0, rows * 44.0);
    return SingleChildScrollView(
      key: ThemeV2HomePage.panelKey,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ThemeV2PageTitle(
            key: ValueKey('theme-v2-page-title-home'),
            title: '今日',
          ),
          const SizedBox(height: 14),
          _content(chamberHeight: chamberHeight),
        ],
      ),
    );
  },
)
```

Initial loading/error states occupy a bounded `SizedBox(height: 340)` below the title. Today passes `chamberHeight`; Agenda uses a bounded `SizedBox(height: 720)` so the document, not the panel, handles short screens.

In `HomeTodayPanel`, remove the page-sized `DecoratedBox`, `ClipRRect`, and positioned title/count/accent. Return:

```dart
Column(
  children: [
    SizedBox(
      key: nextMomentKey,
      width: double.infinity,
      height: 126,
      child: _NextMomentCard(
        item: upcoming.firstOrNull,
        sameTimeItems: _sameTimeItems(upcoming),
        now: now,
        todayCount: todayCount,
        onOpenAgenda: onOpenAgenda,
      ),
    ),
    const SizedBox(height: 12),
    SizedBox(
      key: rekaQueueKey,
      width: double.infinity,
      height: 188,
      child: _RekaQueue(
        items: queue,
        onOpenAgenda: onOpenAgenda,
      ),
    ),
    const SizedBox(height: 12),
    SizedBox(
      key: gravityChamberKey,
      width: double.infinity,
      height: chamberHeight,
      child: ThemeV2GravityChamber(
        child: ThemeV2AssetBubbleField(
          key: assetBubbleFieldKey,
          assets: data.pool,
          trueCount: data.poolTrueCount,
          skills: data.skills,
          active: active,
        ),
      ),
    ),
  ],
)
```

- [ ] **Step 5: Make watermark and Reduce Motion layout chamber-relative**

Replace fixed watermark coordinates with `Positioned(right: 18, bottom: 82)` for the number and `Positioned(right: 24, bottom: 72)` for “今日生成”. Preserve the current 112px/9px typography and accent alpha values.

When `widget.assets.isEmpty`, render this non-interactive message above the watermark:

```dart
Center(
  child: Text(
    '今天生成的资产会落在这里',
    style: TextStyle(
      color: tokens.muted,
      fontFamily: 'Geist',
      fontSize: 12,
    ),
  ),
)
```

Replace `_ThemeV2CompactAssetGrid`'s `GridView.builder` with a non-scrollable `Wrap` of fixed 44px targets:

```dart
final columns = math.max(1, (constraints.maxWidth / 44).floor());
final cellWidth = constraints.maxWidth / columns;
return Align(
  alignment: Alignment.bottomLeft,
  child: Wrap(
    children: [
      for (var index = 0; index < assets.length; index++)
        SizedBox(
          width: cellWidth,
          height: 44,
          child: _compactAssetTarget(assets[index], index),
        ),
    ],
  ),
);
```

Remove `_compactChamberTop`; the dedicated chamber no longer shares space with Next Moment or Reka.

- [ ] **Step 6: Run Home tests and verify they pass**

Run the two focused files from Step 2. Expected: three-region, no-internal-scroll, responsive watermark, physics, and accessibility tests pass.

- [ ] **Step 7: Commit the Home structure**

```bash
git add mobile/lib/theme_v2/home/theme_v2_gravity_chamber.dart mobile/lib/theme_v2/home/theme_v2_home_page.dart mobile/lib/theme_v2/home/home_today_panel.dart mobile/lib/theme_v2/home/home_agenda_panel.dart mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart mobile/test/theme_v2/home/theme_v2_home_page_test.dart mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
git commit -m "feat: build open Theme V2 gravity chamber"
```

---

### Task 4: Deterministic 50-ball retirement transition

**Files:**
- Modify: `mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart`
- Modify: `mobile/lib/today/today_data.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`
- Modify: `mobile/test/today_data_test.dart`

**Interfaces:**
- Preserves: `TodayData.pool` contains newest-first assets capped at 50; `poolTrueCount` remains uncapped.
- Produces: `selectTodayPool(Iterable<PoolAsset> assets, {int maxBodies = 50}) -> ({List<PoolAsset> pool, int trueCount})`.
- Produces internally: `_RetiringBubbleSnapshot(asset, center, radius, angle, index)` rendered for 260ms without semantics or collision.
- Produces internally: `_pendingAssets` and `_grabbedAssetId` so a grabbed retiring ball is replaced only after release.

- [ ] **Step 1: Write failing data-cap and retirement tests**

Add a pure 51-asset selection test to `today_data_test.dart`:

```dart
final assets = List.generate(
  51,
  (index) => PoolAsset(
    id: 'asset-$index',
    type: 'notes',
    domain: 'work',
    title: 'Asset $index',
    payload: const {},
    createdAt: DateTime(2026, 8, 3, 10).add(Duration(minutes: index)),
  ),
);
final selected = selectTodayPool(assets.reversed);

expect(selected.trueCount, 51);
expect(selected.pool, hasLength(50));
expect(selected.pool.first.id, 'asset-50');
expect(selected.pool.last.id, 'asset-1');
expect(selected.pool.any((asset) => asset.id == 'asset-0'), isFalse);
```

Add these widget expectations after pumping 50 assets and then `_assets(51).skip(1).toList()`:

```dart
expect(
  find.byKey(const ValueKey('theme-v2-retiring-bubble-asset-0')),
  findsOneWidget,
);
expect(
  find.byKey(const ValueKey('theme-v2-asset-bubble-asset-50')),
  findsOneWidget,
);
expect(find.bySemanticsLabel('打开资产 Contact 0'), findsNothing);

await tester.pump(const Duration(milliseconds: 280));
expect(
  find.byKey(const ValueKey('theme-v2-retiring-bubble-asset-0')),
  findsNothing,
);
```

Add a grabbed-ball test: start a gesture on `asset-0`, pump the replacement set, assert `asset-0` remains and `asset-50` is absent, release, pump once, then assert the new asset appears and the retiring snapshot starts.

Add a Reduce Motion variant that replaces immediately and never finds a retiring key.

- [ ] **Step 2: Run focused tests and verify abrupt removal fails**

Run:

```bash
cd mobile
flutter test test/today_data_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart
```

Expected: the selection test fails because `selectTodayPool` is missing; retirement and grabbed deferral tests fail because removal is abrupt.

- [ ] **Step 3: Implement deterministic newest-50 selection**

Implement and use the deterministic selector in `today_data.dart`:

```dart
({List<PoolAsset> pool, int trueCount}) selectTodayPool(
  Iterable<PoolAsset> assets, {
  int maxBodies = 50,
}) {
  final sorted = List<PoolAsset>.of(assets)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return (
    pool: sorted.take(maxBodies).toList(growable: false),
    trueCount: sorted.length,
  );
}
```

Replace `_loadPool`'s final sort/take block with `return selectTodayPool(all);`.

- [ ] **Step 4: Capture retiring visual snapshots before physical removal**

Add this immutable private record:

```dart
class _RetiringBubbleSnapshot {
  const _RetiringBubbleSnapshot({
    required this.asset,
    required this.center,
    required this.radius,
    required this.angle,
    required this.index,
  });

  final PoolAsset asset;
  final Offset center;
  final double radius;
  final double angle;
  final int index;
}
```

Store `List<_RetiringBubbleSnapshot> _retiring = []`, `String? _grabbedAssetId`, and `List<PoolAsset>? _pendingAssets`. Before removing a missing Bubble in `_syncAssets`, capture its current screen values when `widget.active && !_reduceMotion && _foreground`.

Render snapshots above the watermark and below active interaction targets:

```dart
for (final snapshot in _retiring)
  Positioned(
    key: ValueKey('theme-v2-retiring-bubble-${snapshot.asset.id}'),
    left: snapshot.center.dx - snapshot.radius,
    top: snapshot.center.dy - snapshot.radius,
    child: IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        onEnd: () => _removeRetiring(snapshot.asset.id),
        builder: (context, progress, child) => Opacity(
          opacity: 1 - progress,
          child: Transform.translate(
            offset: Offset(0, 12 * progress),
            child: Transform.scale(
              scale: 1 - 0.28 * progress,
              child: child,
            ),
          ),
        ),
        child: Transform.rotate(
          angle: snapshot.angle,
          child: SizedBox.square(
            dimension: snapshot.radius * 2,
            child: _ThemeV2BubbleVisual(
              asset: snapshot.asset,
              index: snapshot.index,
              skills: widget.skills,
              onTap: _noop,
            ),
          ),
        ),
      ),
    ),
  ),
```

`_removeRetiring` removes by ID only while mounted. `_noop` is a private top-level empty function.

- [ ] **Step 5: Defer replacement while the retiring asset is grabbed**

On pan start, set `_grabbedAssetId = bubble.id`. In `didUpdateWidget`, when the removed-ID set contains `_grabbedAssetId`, assign `_pendingAssets = List.of(widget.assets)` and leave the current body set intact. On pan end/cancel:

```dart
void _releaseGrab() {
  _field?.release();
  _grabbedAssetId = null;
  final pending = _pendingAssets;
  _pendingAssets = null;
  if (pending != null) _syncAssetsTo(pending);
}
```

Refactor `_syncAssets()` into `_syncAssetsTo(List<PoolAsset> nextAssets)` so the deferred list, not only `widget.assets`, controls removal and addition. Metadata updates for IDs that remain visible still use the newest `PoolAsset` object.

- [ ] **Step 6: Run focused tests and verify all capacity rules pass**

Run the two files from Step 2. Expected: newest-50 selection, true count, retirement duration, no retiring semantics, grabbed deferral, and Reduce Motion replacement all pass.

- [ ] **Step 7: Commit deterministic replacement**

```bash
git add mobile/lib/theme_v2/home/theme_v2_asset_bubble_field.dart mobile/lib/today/today_data.dart mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart mobile/test/today_data_test.dart
git commit -m "feat: animate Theme V2 bubble retirement"
```

---

### Task 5: Golden, static analysis, and connected-device acceptance

**Files:**
- Modify: `mobile/test/theme_v2/home/theme_v2_home_golden_test.dart`
- Modify: `mobile/test/theme_v2/home/goldens/home-today-411-light.png`
- Modify: `mobile/test/theme_v2/home/goldens/home-today-411-dark.png`
- Modify: `mobile/test/theme_v2/home/goldens/home-agenda-411-light.png`
- Modify: `mobile/test/theme_v2/home/goldens/home-agenda-411-dark.png`
- Modify: `mobile/test/theme_v2/calendar/goldens/calendar-flow-resting-411-light.png`
- Modify: `mobile/test/theme_v2/calendar/goldens/calendar-flow-resting-411-dark.png`
- Modify: `mobile/test/theme_v2/library/goldens/library-hub-411-light.png`
- Modify: `mobile/test/theme_v2/library/goldens/library-hub-411-dark.png`
- Create: `mobile/test/theme_v2/home/goldens/home-today-360-light.png`

**Interfaces:**
- Consumes: all completed UI behavior.
- Produces: reviewed visual baselines plus a running APK on Android device `RFCY71B21YK`.

- [ ] **Step 1: Update Golden geometry assertions and add 360px Home coverage**

Replace fixed `395×790` panel assertions with region keys and Dock-clearance assertions. Add this 360×800 Light test; it scrolls the rigid Home document and proves the chamber has no descendant scrollable:

Add `import 'package:eureka/theme_v2/home/home_today_panel.dart';` to the Golden test imports.

```dart
testWidgets('Home today 360 light keeps one rigid gravity chamber', (
  tester,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    _GoldenHomeHost(
      brightness: Brightness.light,
      child: RepaintBoundary(
        key: surface,
        child: ThemeV2PageScaffold(
          showTopNav: false,
          body: ThemeV2HomePage(
            repository: _FakeHomeRepository(_homeFixture),
            now: now,
          ),
          dock: const ThemeV2FloatingDock(
            selectedIndex: 0,
            onDestinationSelected: _noopIndex,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final chamber = find.byKey(HomeTodayPanel.gravityChamberKey);
  expect(
    find.descendant(of: chamber, matching: find.byType(Scrollable)),
    findsNothing,
  );
  await tester.drag(
    find.byKey(ThemeV2HomePage.panelKey),
    const Offset(0, -180),
  );
  await tester.pumpAndSettle();

  await expectLater(
    find.byKey(surface),
    matchesGoldenFile('goldens/home-today-360-light.png'),
  );
});
```

- [ ] **Step 2: Generate changed Goldens**

Run:

```bash
cd mobile
flutter test --update-goldens test/theme_v2/home/theme_v2_home_golden_test.dart test/theme_v2/calendar/theme_v2_calendar_golden_test.dart test/theme_v2/library/theme_v2_library_golden_test.dart
```

Expected: only the listed Home root, Calendar overview, and Library hub images change; detail-route Goldens remain unchanged.

- [ ] **Step 3: Inspect every changed Golden**

Open each changed image and verify: 18px aligned titles, no Home outer frame, 12px region gaps, open chamber top, visible bottom boundary, retained watermark, no internal scrollbar, canonical glyphs, Home Dock icon, and no content collision with the Dock. Reject and correct any clipping or accidental fixed black surface before continuing.

- [ ] **Step 4: Run focused and full Flutter verification**

Run:

```bash
cd mobile
dart format lib/theme_v2 lib/timeline/timeline.dart lib/today/today_data.dart test/theme_v2 test/timeline_theme_v2_service_regression_test.dart test/today_data_test.dart
flutter analyze
flutter test test/theme_v2/home test/theme_v2/shell test/theme_v2/calendar test/theme_v2/library test/theme_v2/asset_detail test/timeline_theme_v2_service_regression_test.dart test/today_data_test.dart
```

Expected: Analyze reports no issues and all selected tests pass.

- [ ] **Step 5: Build, install, and launch on the connected device**

Run:

```bash
cd mobile
flutter build apk --debug
$HOME/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
$HOME/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK reverse tcp:8000 tcp:8100
$HOME/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK shell am force-stop com.eureka.mindapp
$HOME/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
```

Expected: app launches against the independent Theme V2 API on port 8100.

- [ ] **Step 6: Perform physical acceptance**

Verify on-device: Today/Calendar/Library title alignment; Home icon states; clear whitespace above Dock; balls fall from the chamber opening; chamber has a visible finite bottom; phone tilt changes gravity; balls collide, rotate, drag, and open exact assets; expense/custom icons match the library; adding the 51st fixture retires the oldest visible ball without deleting it from the library; no Flutter/API exception appears in filtered logs.

- [ ] **Step 7: Commit reviewed visual baselines**

```bash
git add mobile/test/theme_v2/home/theme_v2_home_golden_test.dart mobile/test/theme_v2/home/goldens mobile/test/theme_v2/calendar/goldens/calendar-flow-resting-411-light.png mobile/test/theme_v2/calendar/goldens/calendar-flow-resting-411-dark.png mobile/test/theme_v2/library/goldens/library-hub-411-light.png mobile/test/theme_v2/library/goldens/library-hub-411-dark.png
git commit -m "test: refresh Theme V2 root surface goldens"
```
