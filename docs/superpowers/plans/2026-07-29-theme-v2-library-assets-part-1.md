# Theme V2 Library & Assets Part 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the backward-compatible Theme V2 asset display contract and the four shared asset-card variants without changing existing Library, Calendar, Session, or Skill Builder behavior.

**Architecture:** A framework-neutral display model in `theme_v2/asset/asset_card_display.dart` adapts the existing open `render_spec` JSON and asset payloads into immutable card data. A single token-driven Flutter widget in `theme_v2/asset/asset_card.dart` renders `minimalRow`, `minimalLine`, `richCard`, and `iconTime` variants; later parts integrate the component into each consumer.

**Tech Stack:** Flutter/Dart, Material 3, existing `ThemeV2Tokens`, existing `RenderSpec` formatting helpers, `flutter_test`, golden tests.

## Global Constraints

- Canonical requirements are `spec/design/theme-v2-library-assets-handoff.md` and Pencil section `WLBLn`.
- Part 1 does not modify Library Hub, Todo tabs, Asset Detail, Skill Builder, Calendar interactions, or Session conversation UI.
- `CardDisplayConfig` contains one non-empty primary field and zero to three ordered secondary fields.
- Old `primary_field`, `secondary_field`, and `meta_fields` data remains readable and writable.
- Light and Dark use one widget tree and semantic Theme V2 tokens.
- RichCard divider starts inside the text column and never crosses the left mark.
- Secondary values are individually truncatable, omit blanks, and never render more than three values.
- No user-selectable density, drag ordering, or summary-field concept is added.

---

### Task 1: Backward-compatible CardDisplayConfig

**Files:**
- Create: `mobile/lib/theme_v2/asset/asset_card_display.dart`
- Create: `mobile/test/theme_v2/asset/asset_card_display_test.dart`

**Interfaces:**
- Produces: `CardDisplayConfig.fromRenderSpec(Map<String, dynamic>)`
- Produces: `CardDisplayConfig.applyToRenderSpec(Map<String, dynamic>)`
- Produces: immutable `primaryFieldId` and `secondaryFieldIds`

- [ ] **Step 1: Write failing canonical and legacy parsing tests**

```dart
test('prefers canonical card_display and normalizes its secondary order', () {
  final config = CardDisplayConfig.fromRenderSpec({
    'primary_field': 'legacy_title',
    'secondary_field': 'legacy_subtitle',
    'card_display': {
      'primary_field_id': 'opponent',
      'secondary_field_ids': [
        'score',
        'venue',
        'score',
        'opponent',
        '',
        'result',
        'ignored',
      ],
    },
  });

  expect(config.primaryFieldId, 'opponent');
  expect(config.secondaryFieldIds, ['score', 'venue', 'result']);
});

test('projects legacy secondary and meta fields into one ordered list', () {
  final config = CardDisplayConfig.fromRenderSpec({
    'primary_field': 'title',
    'secondary_field': 'summary',
    'meta_fields': [
      {'field': 'date'},
      {'field': 'location'},
      {'field': 'date'},
    ],
  });

  expect(config.primaryFieldId, 'title');
  expect(config.secondaryFieldIds, ['summary', 'date', 'location']);
});
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/asset/asset_card_display_test.dart
```

Expected: FAIL because `asset_card_display.dart` and `CardDisplayConfig` do not exist.

- [ ] **Step 3: Implement parsing and normalization**

```dart
@immutable
class CardDisplayConfig {
  CardDisplayConfig({
    required String primaryFieldId,
    Iterable<String> secondaryFieldIds = const [],
  }) : primaryFieldId = primaryFieldId.trim(),
       secondaryFieldIds = List.unmodifiable(
         _normalizeSecondary(primaryFieldId, secondaryFieldIds),
       ) {
    if (this.primaryFieldId.isEmpty) {
      throw ArgumentError.value(primaryFieldId, 'primaryFieldId');
    }
  }

  final String primaryFieldId;
  final List<String> secondaryFieldIds;

  factory CardDisplayConfig.fromRenderSpec(Map<String, dynamic> source) {
    final canonical = source['card_display'];
    if (canonical is Map) {
      final map = canonical.cast<Object?, Object?>();
      final primary = map['primary_field_id']?.toString().trim() ?? '';
      if (primary.isNotEmpty) {
        return CardDisplayConfig(
          primaryFieldId: primary,
          secondaryFieldIds:
              (map['secondary_field_ids'] as List? ?? const [])
                  .map((value) => value.toString()),
        );
      }
    }
    final primary = source['primary_field']?.toString().trim() ?? '';
    if (primary.isEmpty) {
      throw const FormatException('render_spec requires a primary field');
    }
    return CardDisplayConfig(
      primaryFieldId: primary,
      secondaryFieldIds: [
        if (source['secondary_field'] != null)
          source['secondary_field'].toString(),
        for (final meta
            in (source['meta_fields'] as List? ?? const []).whereType<Map>())
          if (meta['field'] != null) meta['field'].toString(),
      ],
    );
  }
}
```

- [ ] **Step 4: Run parsing tests and verify GREEN**

Run the same test command.

Expected: both parsing tests PASS.

- [ ] **Step 5: Write failing compatibility serialization tests**

```dart
test('writes canonical and legacy projections without dropping other keys', () {
  final config = CardDisplayConfig(
    primaryFieldId: 'opponent',
    secondaryFieldIds: ['score', 'venue', 'result'],
  );

  final output = config.applyToRenderSpec({
    'icon': '🎾',
    'actions': ['edit'],
    'primary_field': 'old',
    'primary_format': 'old_format',
    'secondary_field': 'score',
    'secondary_format': 'badge',
    'meta_fields': [
      {'field': 'venue', 'format': 'text'},
      {'field': 'result', 'format': 'badge'},
    ],
  });

  expect(output['card_display'], {
    'primary_field_id': 'opponent',
    'secondary_field_ids': ['score', 'venue', 'result'],
  });
  expect(output['primary_field'], 'opponent');
  expect(output['secondary_field'], 'score');
  expect(output['secondary_format'], 'badge');
  expect(output['meta_fields'], [
    {'field': 'venue', 'format': 'text'},
    {'field': 'result', 'format': 'badge'},
  ]);
  expect(output['icon'], '🎾');
  expect(output['actions'], ['edit']);
});
```

- [ ] **Step 6: Implement compatibility serialization**

`applyToRenderSpec` must copy the source map, collect existing format directives by field, write nested `card_display`, mirror the first secondary into `secondary_field`, mirror the remaining fields into `meta_fields`, remove obsolete secondary keys when the list is empty, and preserve unrelated keys.

```dart
Map<String, dynamic> applyToRenderSpec(Map<String, dynamic> source) {
  final output = Map<String, dynamic>.from(source);
  final formats = _fieldFormats(source);
  output['card_display'] = {
    'primary_field_id': primaryFieldId,
    'secondary_field_ids': secondaryFieldIds,
  };
  output['primary_field'] = primaryFieldId;
  _writeFormat(output, 'primary_format', formats[primaryFieldId]);

  if (secondaryFieldIds.isEmpty) {
    output.remove('secondary_field');
    output.remove('secondary_format');
  } else {
    final first = secondaryFieldIds.first;
    output['secondary_field'] = first;
    _writeFormat(output, 'secondary_format', formats[first]);
  }
  output['meta_fields'] = [
    for (final field in secondaryFieldIds.skip(1))
      {
        'field': field,
        if (formats[field] case final format?) 'format': format,
      },
  ];
  return output;
}
```

- [ ] **Step 7: Run Task 1 tests and commit**

Run:

```bash
cd mobile
flutter test test/theme_v2/asset/asset_card_display_test.dart
dart format lib/theme_v2/asset/asset_card_display.dart test/theme_v2/asset/asset_card_display_test.dart
git add lib/theme_v2/asset/asset_card_display.dart test/theme_v2/asset/asset_card_display_test.dart
git commit -m "feat(assets): add compatible card display config"
```

Expected: all Task 1 tests PASS.

---

### Task 2: Payload-to-card presentation adapter

**Files:**
- Modify: `mobile/lib/theme_v2/asset/asset_card_display.dart`
- Modify: `mobile/test/theme_v2/asset/asset_card_display_test.dart`

**Interfaces:**
- Consumes: `CardDisplayConfig`, `RenderSpec`, `applyFormat`
- Produces: `AssetCardViewData.fromPayload(...)`
- Produces: `mark`, `skillLabel`, `primaryValue`, `secondaryValues`, `timeLabel`

- [ ] **Step 1: Write failing projection tests**

```dart
test('projects formatted primary and three nonblank secondary values', () {
  const spec = RenderSpec(
    cardLayout: 'horizontal',
    icon: '🎾',
    accentColor: 'neutral',
    primaryField: 'opponent',
    secondaryField: 'played_at',
    secondaryFormat: 'date',
    metaFields: [
      MetaFieldSpec('score', null),
      MetaFieldSpec('venue', null),
    ],
  );
  final data = AssetCardViewData.fromPayload(
    payload: const {
      'opponent': 'Kevin',
      'played_at': '2026-07-02T09:00:00',
      'score': '4–1',
      'venue': '深云体育公园',
    },
    display: CardDisplayConfig(
      primaryFieldId: 'opponent',
      secondaryFieldIds: ['played_at', 'score', 'venue'],
    ),
    spec: spec,
    skillLabel: '网球对局',
    timeLabel: '21:34',
  );

  expect(data.mark, '🎾');
  expect(data.primaryValue, 'Kevin');
  expect(data.secondaryValues, ['2026-07-02', '4–1', '深云体育公园']);
  expect(data.timeLabel, '21:34');
});

test('skips blank values and falls back to the skill label for primary', () {
  final data = AssetCardViewData.fromPayload(
    payload: const {'title': ' ', 'status': null, 'location': '会议室'},
    display: CardDisplayConfig(
      primaryFieldId: 'title',
      secondaryFieldIds: ['status', 'location'],
    ),
    spec: null,
    skillLabel: '事件',
  );

  expect(data.mark, '•');
  expect(data.primaryValue, '事件');
  expect(data.secondaryValues, ['会议室']);
});
```

- [ ] **Step 2: Run tests and verify RED**

Expected: FAIL because `AssetCardViewData` does not exist.

- [ ] **Step 3: Implement immutable projection**

```dart
@immutable
class AssetCardViewData {
  const AssetCardViewData({
    required this.mark,
    required this.skillLabel,
    required this.primaryValue,
    this.secondaryValues = const [],
    this.timeLabel,
  });

  factory AssetCardViewData.fromPayload({
    required Map<String, dynamic> payload,
    required CardDisplayConfig display,
    required RenderSpec? spec,
    required String skillLabel,
    String? timeLabel,
  }) {
    String formatted(String field) =>
        applyFormat(payload[field], spec?.formatForField(field)).trim();
    final primary = formatted(display.primaryFieldId);
    return AssetCardViewData(
      mark: spec?.icon.trim().isNotEmpty == true ? spec!.icon.trim() : '•',
      skillLabel: skillLabel.trim(),
      primaryValue: primary.isEmpty ? skillLabel.trim() : primary,
      secondaryValues: List.unmodifiable([
        for (final field in display.secondaryFieldIds)
          if (formatted(field) case final value when value.isNotEmpty) value,
      ]),
      timeLabel: timeLabel?.trim(),
    );
  }

  final String mark;
  final String skillLabel;
  final String primaryValue;
  final List<String> secondaryValues;
  final String? timeLabel;
}
```

- [ ] **Step 4: Run projection tests, format, and commit**

```bash
cd mobile
flutter test test/theme_v2/asset/asset_card_display_test.dart
dart format lib/theme_v2/asset/asset_card_display.dart test/theme_v2/asset/asset_card_display_test.dart
git add lib/theme_v2/asset/asset_card_display.dart test/theme_v2/asset/asset_card_display_test.dart
git commit -m "feat(assets): project payloads into card data"
```

Expected: all projection and compatibility tests PASS.

---

### Task 3: Four shared Theme V2 AssetCard variants

**Files:**
- Create: `mobile/lib/theme_v2/asset/asset_card.dart`
- Create: `mobile/test/theme_v2/asset/asset_card_test.dart`

**Interfaces:**
- Consumes: `AssetCardViewData`, `ThemeV2Tokens`
- Produces: `AssetCardVariant`
- Produces: `ThemeV2AssetCard(data:, variant:, onOpen:, disabled:, height:)`
- Produces stable keys: `asset-card-mark`, `asset-card-divider`, `asset-card-secondary-N`

- [ ] **Step 1: Write failing RichCard geometry and empty-metadata tests**

```dart
testWidgets('RichCard divider begins after the mark and keeps three values', (
  tester,
) async {
  await tester.pumpWidget(_host(
    const SizedBox(
      width: 375,
      child: ThemeV2AssetCard(
        variant: AssetCardVariant.richCard,
        data: AssetCardViewData(
          mark: '🎾',
          skillLabel: '网球对局',
          primaryValue: 'Kevin',
          secondaryValues: ['胜', '4–1', '深云体育公园'],
        ),
      ),
    ),
  ));

  final mark = tester.getRect(find.byKey(const ValueKey('asset-card-mark')));
  final divider =
      tester.getRect(find.byKey(const ValueKey('asset-card-divider')));
  expect(divider.left, greaterThan(mark.right));
  expect(find.byKey(const ValueKey('asset-card-secondary-2')), findsOneWidget);
});

testWidgets('RichCard omits divider and second row without metadata', (
  tester,
) async {
  await tester.pumpWidget(_host(
    const ThemeV2AssetCard(
      variant: AssetCardVariant.richCard,
      data: AssetCardViewData(
        mark: '✍️',
        skillLabel: '笔记',
        primaryValue: '只有标题',
      ),
    ),
  ));

  expect(find.byKey(const ValueKey('asset-card-divider')), findsNothing);
  expect(find.byKey(const ValueKey('asset-card-secondary-row')), findsNothing);
});
```

- [ ] **Step 2: Run widget tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/asset/asset_card_test.dart
```

Expected: FAIL because `asset_card.dart` does not exist.

- [ ] **Step 3: Implement the variant shell and RichCard**

Implement a stateful outer target with `Semantics`, `GestureDetector`, `AnimatedScale`, and one excluded child subtree. Use zero animation duration when `MediaQuery.disableAnimations` is true. RichCard reference geometry:

```dart
enum AssetCardVariant { minimalRow, minimalLine, richCard, iconTime }

class ThemeV2AssetCard extends StatefulWidget {
  const ThemeV2AssetCard({
    super.key,
    required this.variant,
    required this.data,
    this.onOpen,
    this.disabled = false,
    this.height,
  });

  final AssetCardVariant variant;
  final AssetCardViewData data;
  final VoidCallback? onOpen;
  final bool disabled;
  final double? height;
}
```

For a 96 px RichCard use 14 px horizontal padding, a 44 px mark, 18 px mark-to-copy gap, 16 px radius, 16–17 px primary text, a one-pixel token divider, and 12 px secondary text. For `height <= 86`, use a 40 px mark and 14 px radius. Render secondary items as separate `Flexible<Text>` children with separator `Text(' · ')` nodes between nonblank values.

- [ ] **Step 4: Write failing compact/minimal/icon and interaction tests**

Cover:

- `height: 86` produces a 40 × 40 mark;
- MinimalRow contains optional time, mark, skill label, and primary value but no divider;
- MinimalLine contains skill label and primary only;
- IconTime contains mark and time only;
- enabled card calls `onOpen`;
- disabled card does not call `onOpen`;
- a 320 px wide card with three long values has no overflow exception.

- [ ] **Step 5: Implement remaining variants and semantics**

MinimalRow is a 52 px single row. MinimalLine is a single constrained line without mark or metadata. IconTime has a minimum 44 px target and shows a centered mark over Geist Mono time. All variants use `ThemeV2Tokens` and do not branch their node structure by brightness.

- [ ] **Step 6: Run widget tests, format, and commit**

```bash
cd mobile
flutter test test/theme_v2/asset/asset_card_test.dart
dart format lib/theme_v2/asset/asset_card.dart test/theme_v2/asset/asset_card_test.dart
flutter analyze lib/theme_v2/asset test/theme_v2/asset
git add lib/theme_v2/asset/asset_card.dart test/theme_v2/asset/asset_card_test.dart
git commit -m "feat(assets): add shared theme v2 card family"
```

Expected: widget tests PASS and analyzer reports no issues.

---

### Task 4: Light/Dark card-family goldens

**Files:**
- Create: `mobile/test/theme_v2/asset/asset_card_golden_test.dart`
- Create: `mobile/test/theme_v2/asset/goldens/asset-card-family-411-light.png`
- Create: `mobile/test/theme_v2/asset/goldens/asset-card-family-411-dark.png`

**Interfaces:**
- Consumes: `ThemeV2AssetCard`, `buildThemeV2Theme`
- Produces: reference screenshots for full RichCard, compact RichCard, no-metadata RichCard, MinimalRow, MinimalLine, and IconTime

- [ ] **Step 1: Write the failing golden harness**

The 411 × 960 surface loads Geist, Geist Mono, Material Icons, and PingFang when available. Its body uses an 18 px horizontal inset and a 12 px vertical gap. Render:

1. 375 × 96 RichCard with three secondary values;
2. 371 × 86 compact RichCard with a long third value;
3. 375 × 96 RichCard with no secondary values;
4. 375 × 52 MinimalRow;
5. 375 px MinimalLine;
6. a six-item IconTime row.

For each brightness:

```dart
await expectLater(
  find.byKey(surface),
  matchesGoldenFile('goldens/asset-card-family-411-$suffix.png'),
);
```

- [ ] **Step 2: Run golden tests and verify RED**

```bash
cd mobile
flutter test test/theme_v2/asset/asset_card_golden_test.dart
```

Expected: FAIL because the golden files do not exist.

- [ ] **Step 3: Generate and inspect the goldens**

```bash
cd mobile
flutter test test/theme_v2/asset/asset_card_golden_test.dart --update-goldens
```

Inspect both PNGs. Confirm:

- no clipping or overflow;
- RichCard divider starts after the mark;
- long metadata truncates while later values remain visible;
- the no-metadata primary is vertically centered;
- Minimal and IconTime variants contain no RichCard-only content;
- Light/Dark use matching geometry.

- [ ] **Step 4: Re-run without update and commit**

```bash
cd mobile
flutter test test/theme_v2/asset
flutter analyze lib/theme_v2/asset test/theme_v2/asset
git add test/theme_v2/asset/asset_card_golden_test.dart test/theme_v2/asset/goldens
git commit -m "test(assets): lock theme v2 card visuals"
```

Expected: all Part 1 tests PASS and analyzer reports no issues.

---

### Task 5: Part 1 regression gate

**Files:**
- Verify only; no production-file expansion

**Interfaces:**
- Consumes: all Part 1 outputs
- Produces: evidence that the isolated component work does not regress existing rendering and Theme V2 surfaces

- [ ] **Step 1: Run focused and neighboring suites**

```bash
cd mobile
flutter test test/theme_v2/asset
flutter test test/theme_v2/library
flutter test test/theme_v2/calendar
flutter test test/theme_v2/session
```

Expected: all tests PASS.

- [ ] **Step 2: Run static analysis**

```bash
cd mobile
flutter analyze lib/theme_v2/asset test/theme_v2/asset
```

Expected: `No issues found!`

- [ ] **Step 3: Review committed scope**

```bash
git status --short
git log --oneline --max-count=8
git diff HEAD~4..HEAD --stat
```

Expected: Part 1 commits contain only the approved design/plan, shared asset-card module, tests, and goldens. Existing unrelated user files remain unstaged.
