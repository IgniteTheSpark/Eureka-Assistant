# Theme V2 Library Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing Theme V2 Library data, state, navigation, and four whitelisted surfaces with the architecture and behavior defined by the approved complete-rebuild design.

**Architecture:** Parse the Library overview once into immutable domain models, keep data state and surface navigation in separate controllers, and let the app shell respond to the Library surface's chrome contract. Rebuild Hub, Container Index, All Containers, and Configure Pinned from shared semantic components while retaining only `ThemeV2LibraryPage` and explicit Asset/Builder adapters as external seams.

**Tech Stack:** Flutter/Dart 3.11, Material 3, `ChangeNotifier`, Riverpod integration seams, existing `ApiClient`, existing Theme V2 tokens/components, Flutter widget/golden tests.

## Global Constraints

- Canonical section: `WLBLn`; Library nodes: `LTmYy`, `c5ejE`, `B70HCg`, `RTqWK`, `V0MnR`, `uSlon`, `rssuX`, `PnnTE`.
- Reference viewport: 411 × 960; default horizontal inset: 18–20 px.
- Minimum interactive target: 44 × 44 px.
- One semantic widget tree serves Light and Dark.
- No breadcrumbs, web-style path labels, or explanatory Hub subtitle.
- Pinned ordinals contain digits only and selected state never uses an underline.
- Hub pinned geometry uses a 6 px gap.
- Recently Generated contains at most the newest 50 real Assets, one horizontal row, no count, pagination, second row, or `全部`.
- System containers are exactly Todo, Notes, Events, and Contacts.
- Counts use backend totals whenever the counts source succeeds.
- Existing dirty/untracked design files are user-owned and must not be staged.
- Every production behavior follows RED → verify RED → GREEN → verify GREEN.

---

## File Structure

### New focused files

- `mobile/lib/theme_v2/library/library_models.dart` — immutable Library domain.
- `mobile/lib/theme_v2/library/library_repository.dart` — API aggregation and projection.
- `mobile/lib/theme_v2/library/library_navigation.dart` — surface stack and chrome contract.
- `mobile/lib/theme_v2/library/library_states.dart` — Library loading/empty/error/partial UI.
- `mobile/test/theme_v2/library/library_repository_test.dart` — repository contract.
- `mobile/test/theme_v2/library/library_navigation_test.dart` — navigation and surface integration contract.
- `mobile/test/theme_v2/library/library_components_test.dart` — shared geometry/semantics.

### Replaced focused files

- `mobile/lib/theme_v2/library/library_controller.dart`
- `mobile/lib/theme_v2/library/library_components.dart`
- `mobile/lib/theme_v2/library/library_hub.dart`
- `mobile/lib/theme_v2/library/container_index.dart`
- `mobile/lib/theme_v2/library/pinned_configuration.dart`
- `mobile/lib/theme_v2/library/create_skill_action.dart`
- `mobile/lib/theme_v2/library/theme_v2_library_page.dart`
- `mobile/test/theme_v2/library/library_controller_test.dart`
- `mobile/test/theme_v2/library/library_navigation_test.dart`
- `mobile/test/theme_v2/library/theme_v2_library_golden_test.dart`

### Adjacent modifications

- `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart` — shell-owned navigation and chrome.
- `mobile/lib/theme_v2/asset/asset_card.dart` — visible-content semantic label.
- `mobile/test/theme_v2/asset/asset_card_test.dart` — semantic regression.
- `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart` — Library chrome matrix.

---

### Task 1: Introduce the Library domain and one-pass overview repository

**Files:**

- Create: `mobile/lib/theme_v2/library/library_models.dart`
- Create: `mobile/lib/theme_v2/library/library_repository.dart`
- Create: `mobile/test/theme_v2/library/library_repository_test.dart`

**Interfaces:**

- Consumes: `ApiClient`, `AssetItem`, `RenderSpec`, `CardDisplayConfig`, `AssetCardViewData`.
- Produces:
  - `LibraryContainerType`
  - `LibraryContainerSummary`
  - `LibraryRecentAsset`
  - `LibrarySourceFailure`
  - `LibraryOverview`
  - `LibraryLoadFailure`
  - `LibraryRepository.loadOverview()`
  - `ApiLibraryRepository`

- [ ] **Step 1: Write the failing API and projection tests**

Create tests that record every requested URL and return 55 unsorted Assets,
Skills with custom `card_display`, Events, Contacts, and counts:

```dart
test('loads one overview with one skills request and newest 50 assets', () async {
  final calls = <Uri>[];
  final api = _api((request) {
    calls.add(request.url);
    return switch (request.url.path) {
      '/api/assets' => _json({'assets': _assetRows(55)}),
      '/api/skills' => _json({'skills': [_todoSkill, _notesSkill, _tennisSkill]}),
      '/api/events' => _json({'events': [_event]}),
      '/api/contacts' => _json({'contacts': [_contact]}),
      '/api/assets/counts' => _json({'counts': {'todo': 48, 'notes': 23, 'tennis': 3}}),
      _ => throw StateError('unexpected ${request.url}'),
    };
  });

  final overview = await ApiLibraryRepository(api).loadOverview();

  expect(calls.where((uri) => uri.path == '/api/skills'), hasLength(1));
  expect(
    calls.singleWhere((uri) => uri.path == '/api/assets').queryParameters,
    {'limit': '50'},
  );
  expect(overview.systemContainers.map((item) => item.type), [
    LibraryContainerType.todo,
    LibraryContainerType.notes,
    LibraryContainerType.event,
    LibraryContainerType.contact,
  ]);
  expect(overview.customContainers.map((item) => item.id), ['tennis']);
  expect(overview.recentAssets, hasLength(50));
  expect(
    overview.recentAssets.map((item) => item.createdAt),
    orderedEquals(
      [...overview.recentAssets.map((item) => item.createdAt)]
        ..sort((a, b) => b.compareTo(a)),
    ),
  );
  expect(overview.recentAssets.first.primaryValue, '自定义主标题 54');
  expect(overview.totalAssetCount, 74);
});

test('keeps four system containers and marks partial source failures', () async {
  final overview = await ApiLibraryRepository(
    _apiWithFailures({'events', 'counts'}),
  ).loadOverview();

  expect(overview.systemContainers, hasLength(4));
  expect(overview.failedSources.keys, containsAll(['events', 'counts']));
  expect(
    overview.systemContainers
        .singleWhere((item) => item.type == LibraryContainerType.event)
        .totalCount,
    0,
  );
});

test('throws typed offline failure when every source is unavailable', () async {
  await expectLater(
    ApiLibraryRepository(_offlineApi()).loadOverview(),
    throwsA(
      isA<LibraryLoadFailure>().having(
        (error) => error.isOffline,
        'isOffline',
        isTrue,
      ),
    ),
  );
});
```

Use these concrete fixtures in the same test file:

```dart
ApiClient _api(
  FutureOr<http.Response> Function(http.Request request) responder,
) => ApiClient(
  client: MockClient((request) async => responder(request)),
  baseUrl: 'https://library.test',
  enableLogging: false,
);

http.Response _json(Object value) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

List<Map<String, dynamic>> _assetRows(int count) => List.generate(
  count,
  (index) => {
    'id': 'asset-$index',
    'user_skill_name': 'tennis',
    'payload': {'opponent': '自定义主标题 $index'},
    'created_at': DateTime(2026, 7, 1)
        .add(Duration(minutes: index))
        .toIso8601String(),
  },
);

const _todoSkill = {
  'name': 'todo',
  'display_name': '待办',
  'enabled': 1,
  'render_spec': {'icon': '📋', 'primary_field': 'title'},
};
const _notesSkill = {
  'name': 'notes',
  'display_name': '随记',
  'enabled': 1,
  'render_spec': {'icon': '✍️', 'primary_field': 'content'},
};
const _tennisSkill = {
  'name': 'tennis',
  'display_name': '网球比赛',
  'enabled': 1,
  'user_skill_id': 'skill-tennis',
  'render_spec': {
    'icon': '🎾',
    'primary_field': 'opponent',
    'card_display': {
      'primary_field_id': 'opponent',
      'secondary_field_ids': <String>[],
    },
  },
};
const _event = {
  'event_id': 'event-1',
  'title': '设计评审',
  'start_at': '2026-07-30T15:00:00+08:00',
};
const _contact = {
  'id': 'contact-1',
  'name': '小王',
  'created_at': '2026-07-28T10:00:00+08:00',
};

ApiClient _apiWithFailures(Set<String> failures) => _api((request) {
  const sourceByPath = {
    '/api/assets': 'assets',
    '/api/skills': 'skills',
    '/api/events': 'events',
    '/api/contacts': 'contacts',
    '/api/assets/counts': 'counts',
  };
  final source = sourceByPath[request.url.path]!;
  if (failures.contains(source)) {
    throw http.ClientException('$source unavailable', request.url);
  }
  return switch (source) {
    'assets' => _json({'assets': _assetRows(2)}),
    'skills' => _json({'skills': [_todoSkill, _notesSkill, _tennisSkill]}),
    'events' => _json({'events': [_event]}),
    'contacts' => _json({'contacts': [_contact]}),
    'counts' => _json({'counts': {'todo': 2, 'notes': 1, 'tennis': 3}}),
    _ => throw StateError(source),
  };
});

ApiClient _offlineApi() => _api((request) {
  throw const SocketException('offline');
});
```

Import `dart:async`, `dart:convert`, `dart:io`, `package:http/http.dart` as
`http`, and `package:http/testing.dart`.

- [ ] **Step 2: Run the repository test and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/library/library_repository_test.dart
```

Expected: compilation fails because `library_models.dart`,
`LibraryOverview`, and `ApiLibraryRepository.loadOverview` do not exist.

- [ ] **Step 3: Implement immutable models**

Implement the exact public shape:

```dart
enum LibraryContainerType { todo, notes, event, contact, custom }

@immutable
class LibraryContainerSummary {
  const LibraryContainerSummary({
    required this.id,
    required this.label,
    required this.mark,
    required this.type,
    required this.totalCount,
    required this.isSystem,
    this.activityLabel,
    this.userSkillId,
  });

  final String id;
  final String label;
  final String mark;
  final LibraryContainerType type;
  final int totalCount;
  final String? activityLabel;
  final String? userSkillId;
  final bool isSystem;
}

@immutable
class LibraryRecentAsset {
  const LibraryRecentAsset({
    required this.id,
    required this.skillName,
    required this.skillLabel,
    required this.mark,
    required this.primaryValue,
    required this.createdAt,
    required this.detailCard,
  });

  final String id;
  final String skillName;
  final String skillLabel;
  final String mark;
  final String primaryValue;
  final DateTime createdAt;
  final Map<String, dynamic> detailCard;
}

@immutable
class LibrarySourceFailure {
  const LibrarySourceFailure(this.source, {required this.isOffline});
  final String source;
  final bool isOffline;
}

@immutable
class LibraryOverview {
  const LibraryOverview({
    this.systemContainers = const [],
    this.customContainers = const [],
    this.recentAssets = const [],
    this.totalAssetCount = 0,
    this.failedSources = const {},
  });

  final List<LibraryContainerSummary> systemContainers;
  final List<LibraryContainerSummary> customContainers;
  final List<LibraryRecentAsset> recentAssets;
  final int totalAssetCount;
  final Map<String, LibrarySourceFailure> failedSources;

  List<LibraryContainerSummary> get containers =>
      List.unmodifiable([...systemContainers, ...customContainers]);
  int get containerCount => containers.length;
  int get customContainerCount => customContainers.length;
}

class LibraryLoadFailure implements Exception {
  const LibraryLoadFailure(this.message, {required this.isOffline});
  final String message;
  final bool isOffline;
}

abstract interface class LibraryRepository {
  Future<LibraryOverview> loadOverview();
}
```

- [ ] **Step 4: Implement the repository with one `/api/skills` parse**

Use `Future.wait` over exactly five captured calls. Parse the raw Skills
response once into a private record containing `SkillMeta`, `RenderSpec`, and
the raw render-spec map. Build four system summaries unconditionally. Build
custom summaries only for enabled non-system Skills and exclude
`external_ref`, `qa`, and `contact`.

The Asset request must be:

```dart
final response = await api.getJson('/api/assets?limit=50');
```

For each recent Asset, resolve the saved display contract:

```dart
final renderMap = skill.renderSpecMap;
final spec = skill.renderSpec;
final display = _displayOrFallback(renderMap, spec, asset.payload);
final viewData = AssetCardViewData.fromPayload(
  payload: asset.payload,
  display: display,
  spec: spec,
  skillLabel: skill.label,
);
```

Use this deterministic fallback when a stored display contract is missing or
invalid:

```dart
CardDisplayConfig _displayOrFallback(
  Map<String, dynamic> renderMap,
  RenderSpec? spec,
  Map<String, dynamic> payload,
) {
  try {
    return CardDisplayConfig.fromRenderSpec(renderMap);
  } on FormatException {
    final declared = spec?.primaryField?.trim() ?? '';
    final payloadField = payload.keys
        .map((key) => key.trim())
        .firstWhere((key) => key.isNotEmpty, orElse: () => 'content');
    return CardDisplayConfig(
      primaryFieldId: declared.isEmpty ? payloadField : declared,
    );
  }
}
```

Sort by `createdAt` descending and apply `.take(50)`. Sum backend counts for
`totalAssetCount` when counts succeeded. If counts failed, derive the fallback
from overview Assets and keep the `counts` failure in `failedSources`.

- [ ] **Step 5: Verify repository GREEN and run static analysis**

Run:

```bash
cd mobile
dart format lib/theme_v2/library/library_models.dart lib/theme_v2/library/library_repository.dart test/theme_v2/library/library_repository_test.dart
flutter test test/theme_v2/library/library_repository_test.dart
flutter analyze lib/theme_v2/library/library_models.dart lib/theme_v2/library/library_repository.dart test/theme_v2/library/library_repository_test.dart
```

Expected: all repository tests pass and analysis reports no issues.

- [ ] **Step 6: Commit the domain/repository slice**

```bash
git add mobile/lib/theme_v2/library/library_models.dart mobile/lib/theme_v2/library/library_repository.dart mobile/test/theme_v2/library/library_repository_test.dart
git commit -m "refactor(library): rebuild overview domain"
```

---

### Task 2: Replace the Library data controller and pinned state machine

**Files:**

- Replace: `mobile/lib/theme_v2/library/library_controller.dart`
- Replace: `mobile/test/theme_v2/library/library_controller_test.dart`
- Modify mechanically for compilation:
  - `mobile/lib/theme_v2/library/library_components.dart`
  - `mobile/lib/theme_v2/library/library_hub.dart`
  - `mobile/lib/theme_v2/library/container_index.dart`
  - `mobile/lib/theme_v2/library/pinned_configuration.dart`
  - `mobile/lib/theme_v2/library/theme_v2_library_page.dart`

**Interfaces:**

- Consumes: `LibraryRepository`, `LibraryOverview`,
  `LibraryContainerSummary`.
- Produces:
  - `LibraryStatus`
  - `LibraryPinnedStore`
  - `SharedPreferencesLibraryPinnedStore`
  - `LibraryController.load()`, `retry()`
  - independent `indexQuery`, `allQuery`
  - `indexSystemContainers`, `indexCustomContainers`
  - `allSystemContainers`, `allCustomContainers`
  - `replacePinned`, `movePinned`, `removePinned`, `addPinned`
  - `isSavingPins`, `pinSaveError`

- [ ] **Step 1: Replace controller tests with the new contract**

Cover load status, independent queries, persisted pin sanitation,
six-item cap, serialized optimistic saves, rollback, stale loads, and disposal:

```dart
test('directory queries are independent and clear without reload', () async {
  final repository = _Repository(_overview());
  final controller = LibraryController(
    repository: repository,
    pinnedStore: _PinnedStore(),
  );
  await controller.load();

  controller.setIndexQuery('网球');
  expect(controller.indexCustomContainers.map((item) => item.id), ['tennis']);
  expect(controller.allSystemContainers, hasLength(4));

  controller.setAllQuery('事件');
  expect(controller.allSystemContainers.map((item) => item.id), ['event']);
  expect(controller.indexQuery, '网球');

  controller.clearIndexQuery();
  expect(controller.indexCustomContainers, hasLength(1));
  expect(repository.loadCount, 1);
});

test('failed pinned save restores the latest confirmed order', () async {
  final store = _PinnedStore(initial: ['todo', 'notes'])..failNext = true;
  final controller = await _loadedController(store: store);

  final saving = controller.replacePinned(['notes', 'todo']);
  expect(controller.pinnedContainers.map((item) => item.id), ['notes', 'todo']);
  expect(controller.isSavingPins, isTrue);

  expect(await saving, isFalse);
  expect(controller.pinnedContainers.map((item) => item.id), ['todo', 'notes']);
  expect(controller.pinSaveError, isNotNull);
  expect(controller.isSavingPins, isFalse);
});
```

Define the test doubles explicitly:

```dart
class _Repository implements LibraryRepository {
  _Repository(this.value);
  final LibraryOverview value;
  int loadCount = 0;

  @override
  Future<LibraryOverview> loadOverview() async {
    loadCount++;
    return value;
  }
}

class _PinnedStore implements LibraryPinnedStore {
  _PinnedStore({List<String>? initial}) : initial = initial ?? const [];
  final List<String> initial;
  bool failNext = false;
  final List<List<String>> saved = [];

  @override
  Future<List<String>?> load() async => List.of(initial);

  @override
  Future<void> save(List<String> ids) async {
    if (failNext) {
      failNext = false;
      throw StateError('save denied');
    }
    saved.add(List.of(ids));
  }
}

LibraryContainerSummary _summary(
  String id,
  LibraryContainerType type, {
  int total = 1,
  bool system = true,
}) => LibraryContainerSummary(
  id: id,
  label: id,
  mark: '•',
  type: type,
  totalCount: total,
  isSystem: system,
);

LibraryOverview _overview() => LibraryOverview(
  systemContainers: [
    _summary('todo', LibraryContainerType.todo),
    _summary('notes', LibraryContainerType.notes),
    _summary('event', LibraryContainerType.event),
    _summary('contact', LibraryContainerType.contact),
  ],
  customContainers: [
    _summary(
      'tennis',
      LibraryContainerType.custom,
      total: 3,
      system: false,
    ),
  ],
  totalAssetCount: 7,
);

Future<LibraryController> _loadedController({
  required _PinnedStore store,
}) async {
  final controller = LibraryController(
    repository: _Repository(_overview()),
    pinnedStore: store,
  );
  await controller.load();
  return controller;
}
```

- [ ] **Step 2: Run the controller suite and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/library/library_controller_test.dart
```

Expected: compilation fails because the current controller exposes
`LibrarySnapshot`, one shared query, and no `isSavingPins`.

- [ ] **Step 3: Implement the replacement controller**

Use the status enum from the design and these query methods:

```dart
void setIndexQuery(String value) => _setQuery(
  value,
  current: _indexQuery,
  assign: (next) => _indexQuery = next,
);

void setAllQuery(String value) => _setQuery(
  value,
  current: _allQuery,
  assign: (next) => _allQuery = next,
);

void clearIndexQuery() => setIndexQuery('');
void clearAllQuery() => setAllQuery('');
```

Filtering is case-insensitive across `label` and `id` and never mutates the
overview. `load()` uses a revision counter, sets `partial` when
`overview.failedSources` is non-empty, and sets `empty` only when all custom
containers and Recent Assets are empty while the four product-defined system
containers have zero totals.

Pinned save operations set `isSavingPins`, chain onto one tail future, and only
roll back the currently visible optimistic revision.

- [ ] **Step 4: Apply compilation-only consumer migration**

Update imports to use `library_models.dart` and change:

```dart
LibraryContainer -> LibraryContainerSummary
LibrarySnapshot -> LibraryOverview
snapshot -> overview
container.count -> container.totalCount
container.icon -> container.mark
container.kind -> container.type
```

Do not change visual structure in this step. This keeps every commit buildable
while later tasks replace the presentation.

- [ ] **Step 5: Verify controller GREEN and all current Library tests compile**

Run:

```bash
cd mobile
dart format lib/theme_v2/library test/theme_v2/library/library_controller_test.dart
flutter test test/theme_v2/library/library_controller_test.dart
flutter test test/theme_v2/library
flutter analyze lib/theme_v2/library test/theme_v2/library
```

Expected: new controller tests pass; any failures in old widget assertions are
updated only where names/types changed, not by weakening behavior.

- [ ] **Step 6: Commit the controller switch**

```bash
git add mobile/lib/theme_v2/library mobile/test/theme_v2/library/library_controller_test.dart
git commit -m "refactor(library): replace library state controller"
```

---

### Task 3: Add Library surface navigation and shell-chrome coordination

**Files:**

- Create: `mobile/lib/theme_v2/library/library_navigation.dart`
- Replace: `mobile/test/theme_v2/library/library_navigation_test.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/lib/theme_v2/library/theme_v2_library_page.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`

**Interfaces:**

- Produces:
  - `LibrarySurface`
  - `LibraryChromeSpec`
  - `LibraryNavigationController.surface`
  - `chrome`, `canPop`, `open`, `back`, `home`
- Consumed by `ThemeV2AppShell` and `ThemeV2LibraryPage`.

- [ ] **Step 1: Write pure navigation RED tests**

```dart
test('surface stack preserves origin and exposes canonical chrome', () {
  final navigation = LibraryNavigationController();

  expect(navigation.surface, LibrarySurface.hub);
  expect(navigation.chrome, const LibraryChromeSpec(topNav: true, dock: true));

  navigation.open(LibrarySurface.containerIndex);
  navigation.open(LibrarySurface.allContainers);
  expect(navigation.chrome, const LibraryChromeSpec(topNav: true, dock: false));

  expect(navigation.back(), isTrue);
  expect(navigation.surface, LibrarySurface.containerIndex);

  navigation.open(LibrarySurface.pinnedConfiguration);
  expect(navigation.chrome, const LibraryChromeSpec(topNav: false, dock: true));
  navigation.home();
  expect(navigation.surface, LibrarySurface.hub);
  expect(navigation.canPop, isFalse);
});
```

- [ ] **Step 2: Run the navigation test and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/library/library_navigation_test.dart
```

Expected: compilation fails because `LibraryNavigationController` does not
exist.

- [ ] **Step 3: Implement the navigation controller**

```dart
enum LibrarySurface { hub, containerIndex, allContainers, pinnedConfiguration }

@immutable
class LibraryChromeSpec {
  const LibraryChromeSpec({required this.topNav, required this.dock});
  final bool topNav;
  final bool dock;
}

class LibraryNavigationController extends ChangeNotifier {
  final List<LibrarySurface> _stack = [LibrarySurface.hub];

  LibrarySurface get surface => _stack.last;
  bool get canPop => _stack.length > 1;

  LibraryChromeSpec get chrome => switch (surface) {
    LibrarySurface.hub ||
    LibrarySurface.containerIndex =>
      const LibraryChromeSpec(topNav: true, dock: true),
    LibrarySurface.allContainers =>
      const LibraryChromeSpec(topNav: true, dock: false),
    LibrarySurface.pinnedConfiguration =>
      const LibraryChromeSpec(topNav: false, dock: true),
  };

  void open(LibrarySurface next) {
    if (next == surface) return;
    _stack.add(next);
    notifyListeners();
  }

  bool back() {
    if (!canPop) return false;
    _stack.removeLast();
    notifyListeners();
    return true;
  }

  void home() {
    if (_stack.length == 1) return;
    _stack
      ..clear()
      ..add(LibrarySurface.hub);
    notifyListeners();
  }
}
```

Implement value equality for `LibraryChromeSpec`.

- [ ] **Step 4: Add shell integration RED tests**

Mount the production shell at Library and assert:

```dart
expect(find.byType(ThemeV2GlobalTopNav), findsOneWidget);
expect(find.byKey(ThemeV2FloatingDock.dockKey), findsOneWidget);

navigation.open(LibrarySurface.allContainers);
await tester.pump();
expect(find.byType(ThemeV2GlobalTopNav), findsOneWidget);
expect(find.byKey(ThemeV2FloatingDock.dockKey), findsNothing);

navigation.open(LibrarySurface.pinnedConfiguration);
await tester.pump();
expect(find.byType(ThemeV2GlobalTopNav), findsNothing);
expect(find.byKey(ThemeV2FloatingDock.dockKey), findsOneWidget);
```

Also assert system back pops the Library surface and reselecting Dock
destination 2 calls `home()`.

- [ ] **Step 5: Define reusable widget-test fixtures**

Keep navigation/widget tests deterministic with concrete in-file fixtures:

```dart
class _LibraryTestRepository implements LibraryRepository {
  const _LibraryTestRepository(this.overview);
  final LibraryOverview overview;

  @override
  Future<LibraryOverview> loadOverview() async => overview;
}

class _LibraryTestPinnedStore implements LibraryPinnedStore {
  const _LibraryTestPinnedStore(this.ids);
  final List<String> ids;

  @override
  Future<List<String>?> load() async => List.of(ids);

  @override
  Future<void> save(List<String> ids) async {}
}

Future<LibraryController> _controller({
  List<String> pinned = const ['todo', 'notes', 'tennis', 'expense'],
  List<String> custom = const ['tennis', 'expense', 'running', 'water'],
}) async {
  LibraryContainerSummary system(String id, LibraryContainerType type) =>
      LibraryContainerSummary(
        id: id,
        label: switch (id) {
          'todo' => '待办',
          'notes' => '随记',
          'event' => '事件',
          _ => '联系人',
        },
        mark: '•',
        type: type,
        totalCount: 1,
        isSystem: true,
      );
  LibraryContainerSummary user(String id) => LibraryContainerSummary(
        id: id,
        label: switch (id) {
          'tennis' => '网球比赛',
          'expense' => '消费账本',
          'running' => '跑步训练',
          _ => '喝水记录',
        },
        mark: '•',
        type: LibraryContainerType.custom,
        totalCount: 1,
        isSystem: false,
      );
  final controller = LibraryController(
    repository: _LibraryTestRepository(
      LibraryOverview(
        systemContainers: [
          system('todo', LibraryContainerType.todo),
          system('notes', LibraryContainerType.notes),
          system('event', LibraryContainerType.event),
          system('contact', LibraryContainerType.contact),
        ],
        customContainers: [for (final id in custom) user(id)],
        totalAssetCount: 8,
      ),
    ),
    pinnedStore: _LibraryTestPinnedStore(pinned),
  );
  await controller.load();
  return controller;
}

Widget _host(Widget child) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: Scaffold(body: SafeArea(child: child)),
);
```

- [ ] **Step 6: Integrate shell-owned navigation and local surfaces**

`ThemeV2AppShell` owns or accepts a `LibraryNavigationController`, listens to
it, and passes it to the production `ThemeV2LibraryPage`. Build the Library
`ThemeV2PageScaffold` with:

```dart
ThemeV2PageScaffold(
  body: ThemeV2LibraryPage(navigation: _libraryNavigation),
  showTopNav: _libraryNavigation.chrome.topNav,
  showDock: _libraryNavigation.chrome.dock,
)
```

In `_selectDestination`, when destination 2 is already selected, call
`_libraryNavigation.home()`.

Replace page-local pushes for the four Library surfaces with an
`AnimatedBuilder` switch on `navigation.surface`. Wrap the body in:

```dart
PopScope(
  canPop: !navigation.canPop,
  onPopInvokedWithResult: (didPop, _) {
    if (!didPop) navigation.back();
  },
  child: PageStorage(bucket: _pageStorageBucket, child: activeSurface),
)
```

Keep external Asset list routes and the Recent Asset detail sheet adapters.

- [ ] **Step 7: Verify navigation GREEN**

Run:

```bash
cd mobile
dart format lib/theme_v2/library/library_navigation.dart lib/theme_v2/library/theme_v2_library_page.dart lib/theme_v2/shell/theme_v2_app_shell.dart test/theme_v2/library/library_navigation_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart
flutter test test/theme_v2/library/library_navigation_test.dart
flutter test test/theme_v2/shell/theme_v2_navigation_state_test.dart
flutter analyze lib/theme_v2/library/library_navigation.dart lib/theme_v2/library/theme_v2_library_page.dart lib/theme_v2/shell/theme_v2_app_shell.dart
```

Expected: navigation and shell tests pass with the canonical chrome matrix.

- [ ] **Step 8: Commit navigation**

```bash
git add mobile/lib/theme_v2/library/library_navigation.dart mobile/lib/theme_v2/library/theme_v2_library_page.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/library/library_navigation_test.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart
git commit -m "refactor(library): coordinate local surfaces with app shell"
```

---

### Task 4: Rebuild shared Library components and state presentations

**Files:**

- Replace: `mobile/lib/theme_v2/library/library_components.dart`
- Create: `mobile/lib/theme_v2/library/library_states.dart`
- Replace: `mobile/lib/theme_v2/library/create_skill_action.dart`
- Create: `mobile/test/theme_v2/library/library_components_test.dart`

**Interfaces:**

- Produces:
  - `LibraryStatsBar`
  - `LibraryPinnedMosaic`
  - `LibrarySystemContainerCard`
  - `LibraryDirectoryRow`
  - `LibraryCustomContainerRow`
  - `LibrarySearchField`
  - `LibraryMetricStrip`
  - `LibraryAvailableContainerTile`
  - `LibrarySectionLabel`
  - `LibraryStateView`
  - `CreateSkillAction.compact`, `.primary`, `.configuration`

- [ ] **Step 1: Write component geometry, interaction, and semantics tests**

At a 375 px content width, assert:

```dart
final first = tester.getRect(find.byKey(const ValueKey('library-pinned-tile-todo')));
final second = tester.getRect(find.byKey(const ValueKey('library-pinned-tile-notes')));
final third = tester.getRect(find.byKey(const ValueKey('library-pinned-tile-tennis')));
final fourth = tester.getRect(find.byKey(const ValueKey('library-pinned-tile-expense')));

expect(first.size, const Size(247, 156));
expect(second.size, const Size(122, 156));
expect(second.left - first.right, 6);
expect(third.size, const Size(186, 178));
expect(fourth.size, const Size(183, 54));
expect(fourth.left - third.right, 6);
expect(find.text('01'), findsOneWidget);
expect(find.textContaining('/ A'), findsNothing);
```

Add tests for:

- press scale reaches `0.98`;
- Reduce Motion keeps scale at 1;
- semantic label includes container name and total;
- system card is 56 px and custom row is 50 px;
- directory row is 54 px with a 34 px mark box;
- disabled available tile has no tap action and announces the six-item limit;
- search empty state invokes `清除搜索`;
- primary, compact, and configuration Create Skill copy.

- [ ] **Step 2: Run the component suite and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/library/library_components_test.dart
```

Expected: tests fail because the exact component APIs and canonical geometry do
not exist.

- [ ] **Step 3: Implement responsive canonical mosaic geometry**

At width 375, use exact dimensions. At other widths preserve 6 px gaps and
proportions:

```dart
const gap = 6.0;
final usable = constraints.maxWidth - gap;
final firstWidth = usable * 247 / 369;
final secondWidth = constraints.maxWidth - gap - firstWidth;
final lowerLeftWidth = usable * 186 / 369;
final lowerRightWidth = constraints.maxWidth - gap - lowerLeftWidth;
```

Use slots:

```dart
Rect.fromLTWH(0, 0, firstWidth, 156)
Rect.fromLTWH(firstWidth + gap, 0, secondWidth, 156)
Rect.fromLTWH(0, 162, lowerLeftWidth, 178)
Rect.fromLTWH(lowerLeftWidth + gap, 162, lowerRightWidth, 54)
Rect.fromLTWH(lowerLeftWidth + gap, 222, lowerRightWidth, 54)
Rect.fromLTWH(lowerLeftWidth + gap, 282, lowerRightWidth, 54)
```

The tile uses one `Semantics` node, numeric ordinal
`(index + 1).toString().padLeft(2, '0')`, and `AnimatedScale` keyed
`library-pinned-press-transform-$id`.

- [ ] **Step 4: Implement row variants and Library states**

All colors come from `context.themeV2`. Use:

- system card: surfaced, radius 14, border, 56 px;
- custom row: transparent, bottom border, 50 px;
- directory row: transparent, bottom border, 54 px, 34 px soft mark box;
- search: 44 px Index and configurable 42 px All;
- `LibraryStateView.loading` shaped as title/stats/list skeleton;
- `LibraryStateView.emptySearch` with `清除搜索`;
- `LibraryStateView.error` with visible retry;
- partial banner keeps loaded content visible.

- [ ] **Step 5: Verify components GREEN**

Run:

```bash
cd mobile
dart format lib/theme_v2/library/library_components.dart lib/theme_v2/library/library_states.dart lib/theme_v2/library/create_skill_action.dart test/theme_v2/library/library_components_test.dart
flutter test test/theme_v2/library/library_components_test.dart
flutter analyze lib/theme_v2/library/library_components.dart lib/theme_v2/library/library_states.dart lib/theme_v2/library/create_skill_action.dart test/theme_v2/library/library_components_test.dart
```

Expected: all component tests pass without overflow.

- [ ] **Step 6: Commit shared UI**

```bash
git add mobile/lib/theme_v2/library/library_components.dart mobile/lib/theme_v2/library/library_states.dart mobile/lib/theme_v2/library/create_skill_action.dart mobile/test/theme_v2/library/library_components_test.dart
git commit -m "feat(library): rebuild shared library components"
```

---

### Task 5: Rebuild the Library Hub and Recently Generated

**Files:**

- Replace: `mobile/lib/theme_v2/library/library_hub.dart`
- Modify: `mobile/lib/theme_v2/asset/asset_card.dart`
- Modify: `mobile/test/theme_v2/asset/asset_card_test.dart`
- Modify: `mobile/test/theme_v2/library/library_navigation_test.dart`

**Interfaces:**

- Consumes: `LibraryController`, `LibraryStatsBar`,
  `LibraryPinnedMosaic`, `LibraryRecentAsset`, `ThemeV2AssetCard.iconTime`.
- Produces the complete Hub body and separate Index/All navigation callbacks.

- [ ] **Step 1: Write the AssetCard semantic RED test**

```dart
testWidgets('IconTime semantics include skill primary value and visible time', (
  tester,
) async {
  final semantics = tester.ensureSemantics();
  await tester.pumpWidget(
    _host(
      ThemeV2AssetCard(
        variant: AssetCardVariant.iconTime,
        data: const AssetCardViewData(
          mark: '球',
          skillLabel: '网球对局',
          primaryValue: 'Kevin',
          timeLabel: '19:30',
        ),
        onOpen: () {},
      ),
    ),
  );

  expect(
    find.bySemanticsLabel('打开网球对局：Kevin，19:30'),
    findsOneWidget,
  );
  semantics.dispose();
});
```

- [ ] **Step 2: Verify semantic RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/asset/asset_card_test.dart
```

Expected: the new semantic finder fails because the label omits time.

- [ ] **Step 3: Implement visible-content semantics**

Build the label from content visible in the selected variant:

```dart
String _semanticLabel() {
  final visible = <String>[widget.data.skillLabel, widget.data.primaryValue];
  if (widget.variant == AssetCardVariant.richCard) {
    visible.addAll(
      widget.data.secondaryValues
          .where((value) => value.trim().isNotEmpty)
          .take(3),
    );
  }
  if ((widget.variant == AssetCardVariant.iconTime ||
          widget.variant == AssetCardVariant.minimalRow) &&
      widget.data.timeLabel case final time?) {
    visible.add(time);
  }
  return '打开${visible.first}：${visible.skip(1).join('，')}';
}
```

- [ ] **Step 4: Write Hub RED tests**

Assert:

- only `资产库` appears as header;
- no `LIBRARY /`, explanatory subtitle, or recent count;
- stats left calls `onOpenContainerIndex`;
- `全部容器` calls `onOpenAllContainers`;
- pinned long press opens configuration;
- exactly one horizontal `Scrollable` is used for Recent Assets;
- all 50 items exist lazily and no 51st item exists;
- Recent items are `ThemeV2AssetCard` with `iconTime`;
- returning from a detail callback preserves horizontal offset;
- 360 px has no overflow.

Use stable keys:

```dart
const PageStorageKey('theme-v2-library-hub')
const PageStorageKey('theme-v2-library-recent-assets')
ValueKey('library-recent-$assetId')
```

- [ ] **Step 5: Verify Hub RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/library/library_navigation_test.dart --plain-name "hub"
```

Expected: assertions fail against the current header, 12-item cap, recent count,
and bespoke recent tiles.

- [ ] **Step 6: Implement the canonical Hub**

Use 18 px horizontal padding and this order:

1. title;
2. 54 px stats bar;
3. optional partial banner;
4. `PINNED / NN` plus 44 px configure action;
5. 340 px pinned mosaic;
6. primary Create Skill action;
7. `最近生成`;
8. 54 px horizontal AssetCard row.

Map Recent Assets to:

```dart
ThemeV2AssetCard(
  key: ValueKey('library-recent-${asset.id}'),
  variant: AssetCardVariant.iconTime,
  data: AssetCardViewData(
    mark: asset.mark,
    skillLabel: asset.skillLabel,
    primaryValue: asset.primaryValue,
    timeLabel: MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(asset.createdAt),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    ),
  ),
  onOpen: onOpenRecent == null ? null : () => onOpenRecent!(asset),
)
```

Use a 55 px item extent and 8 px separator so approximately six are visible.

- [ ] **Step 7: Verify Hub GREEN**

Run:

```bash
cd mobile
dart format lib/theme_v2/asset/asset_card.dart lib/theme_v2/library/library_hub.dart test/theme_v2/asset/asset_card_test.dart test/theme_v2/library/library_navigation_test.dart
flutter test test/theme_v2/asset/asset_card_test.dart
flutter test test/theme_v2/library/library_navigation_test.dart --plain-name "hub"
flutter analyze lib/theme_v2/asset/asset_card.dart lib/theme_v2/library/library_hub.dart
```

Expected: semantic and Hub tests pass.

- [ ] **Step 8: Commit Hub**

```bash
git add mobile/lib/theme_v2/asset/asset_card.dart mobile/lib/theme_v2/library/library_hub.dart mobile/test/theme_v2/asset/asset_card_test.dart mobile/test/theme_v2/library/library_navigation_test.dart
git commit -m "feat(library): rebuild hub and recent assets"
```

---

### Task 6: Rebuild Container Index and All Containers

**Files:**

- Replace: `mobile/lib/theme_v2/library/container_index.dart`
- Modify: `mobile/test/theme_v2/library/library_navigation_test.dart`

**Interfaces:**

- Consumes: independent controller queries and shared row components.
- Produces:
  - `ContainerIndex`
  - `AllContainers`

- [ ] **Step 1: Write directory RED tests**

For Container Index, assert:

```dart
expect(find.text('资产容器'), findsOneWidget);
expect(find.textContaining('LIBRARY /'), findsNothing);
expect(find.text('系统容器'), findsOneWidget);
expect(find.byType(LibrarySystemContainerCard), findsNWidgets(4));
expect(find.byType(LibraryCustomContainerRow), findsNWidgets(3));
expect(find.text('查看全部容器'), findsNothing);
expect(tester.getSize(find.byKey(const ValueKey('library-index-search'))).height, 44);
```

For All Containers, assert the native back target, three metrics, 42 px search,
54 px rows, Create Skill footer, and Dock-independent bottom reachability.

Search tests must prove:

```dart
await tester.enterText(find.byKey(const ValueKey('library-index-search')), '网球');
await tester.pump();
expect(find.text('网球比赛'), findsOneWidget);
expect(find.text('待办'), findsNothing);

await tester.tap(find.text('清除搜索'));
await tester.pump();
expect(find.text('待办'), findsOneWidget);
```

Switch to All Containers and prove the Index query remains unchanged.

- [ ] **Step 2: Run directory tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/library/library_navigation_test.dart --plain-name "container"
```

Expected: current headers, duplicate button, shared query, and row geometry fail
the new assertions.

- [ ] **Step 3: Implement Container Index**

Use a `ListView` with `PageStorageKey('theme-v2-library-container-index')`,
20 px horizontal inset, 12 px top gap, title, 44 px search, system group,
custom group, and compact Create Skill footer. Empty search renders
`LibraryStateView.emptySearch(onClear: controller.clearIndexQuery)`.

- [ ] **Step 4: Implement All Containers**

Use `PageStorageKey('theme-v2-library-all-containers')`, native 44 px back
target, 76 px metrics, 42 px search, `LibraryDirectoryRow` groups, and compact
Create Skill footer. Empty search calls `clearAllQuery`.

Do not manually insert Top Nav or Dock in either page.

- [ ] **Step 5: Verify directories GREEN**

Run:

```bash
cd mobile
dart format lib/theme_v2/library/container_index.dart test/theme_v2/library/library_navigation_test.dart
flutter test test/theme_v2/library/library_navigation_test.dart
flutter analyze lib/theme_v2/library/container_index.dart test/theme_v2/library/library_navigation_test.dart
```

Expected: navigation, directory, search, and state-preservation tests pass.

- [ ] **Step 6: Commit directories**

```bash
git add mobile/lib/theme_v2/library/container_index.dart mobile/test/theme_v2/library/library_navigation_test.dart
git commit -m "feat(library): rebuild container directories"
```

---

### Task 7: Rebuild Configure Pinned

**Files:**

- Replace: `mobile/lib/theme_v2/library/pinned_configuration.dart`
- Modify: `mobile/test/theme_v2/library/library_navigation_test.dart`
- Modify: `mobile/test/theme_v2/library/library_controller_test.dart`

**Interfaces:**

- Consumes: shared pinned mosaic, available tiles, controller optimistic
  mutations, navigation `back`.
- Produces the complete configuration surface.

- [ ] **Step 1: Write configuration RED tests**

Cover:

- no global navigation widget inside the page;
- own title and 44 px `完成配置`;
- numeric-only ordinals;
- no underline decoration;
- long-press drag moves the visible order;
- remove and add use 44 px targets;
- six pins disable remaining add tiles with explanatory semantics;
- pending save disables duplicate controls;
- failed persistence restores order and displays controller error;
- PageStorage preserves vertical offset.

Example:

```dart
testWidgets('six pinned containers disable available add actions', (
  tester,
) async {
  final semantics = tester.ensureSemantics();
  final controller = await _controller(
    pinned: const ['todo', 'notes', 'event', 'contact', 'tennis', 'expense'],
    custom: const ['tennis', 'expense', 'running', 'water'],
  );
  await tester.pumpWidget(_host(PinnedConfiguration(
    controller: controller,
    onDone: () {},
    onCreateSkill: () {},
  )));

  final add = find.bySemanticsLabel('加入 喝水记录，已达到六个常驻容器上限');
  expect(add, findsOneWidget);
  expect(
    tester.getSemantics(add),
    matchesSemantics(
      label: '加入 喝水记录，已达到六个常驻容器上限',
      isButton: true,
      isEnabled: false,
      hasEnabledState: true,
      hasTapAction: false,
    ),
  );
  semantics.dispose();
});
```

- [ ] **Step 2: Run configuration tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/library/library_navigation_test.dart --plain-name "pinned"
```

Expected: assertions fail against old headers, lettered ordinals, button layout,
and missing pending lock.

- [ ] **Step 3: Implement configuration surface**

Use this order:

1. configuration header and Done action;
2. stats/confirmation bar;
3. `CONFIGURE / NN · 长按拖动`;
4. pinned mosaic;
5. persistence feedback;
6. configuration Create/Add Skill banner;
7. available-container label and compact add grid.

Wrap reorder/remove/add callbacks with `controller.isSavingPins` guards. The
controller remains the only source of rollback truth.

- [ ] **Step 4: Verify configuration GREEN**

Run:

```bash
cd mobile
dart format lib/theme_v2/library/pinned_configuration.dart test/theme_v2/library/library_navigation_test.dart test/theme_v2/library/library_controller_test.dart
flutter test test/theme_v2/library/library_controller_test.dart
flutter test test/theme_v2/library/library_navigation_test.dart --plain-name "pinned"
flutter analyze lib/theme_v2/library/pinned_configuration.dart
```

Expected: controller rollback and configuration widget tests pass.

- [ ] **Step 5: Commit configuration**

```bash
git add mobile/lib/theme_v2/library/pinned_configuration.dart mobile/test/theme_v2/library/library_navigation_test.dart mobile/test/theme_v2/library/library_controller_test.dart
git commit -m "feat(library): rebuild pinned configuration"
```

---

### Task 8: Finish page states, adapters, visual baselines, and cleanup

**Files:**

- Modify: `mobile/lib/theme_v2/library/theme_v2_library_page.dart`
- Modify: `mobile/lib/theme_v2/library/library_states.dart`
- Replace: `mobile/test/theme_v2/library/theme_v2_library_golden_test.dart`
- Replace:
  - `mobile/test/theme_v2/library/goldens/library-hub-411-light.png`
  - `mobile/test/theme_v2/library/goldens/library-hub-411-dark.png`
  - `mobile/test/theme_v2/library/goldens/library-index-411-light.png`
  - `mobile/test/theme_v2/library/goldens/library-index-411-dark.png`
  - `mobile/test/theme_v2/library/goldens/library-all-411-light.png`
  - `mobile/test/theme_v2/library/goldens/library-all-411-dark.png`
  - `mobile/test/theme_v2/library/goldens/library-pinned-411-light.png`
  - `mobile/test/theme_v2/library/goldens/library-pinned-411-dark.png`
- Replace: `mobile/test/theme_v2/library/goldens/library-hub-360-light.png`
- Modify: `mobile/test/theme_v2/library/library_navigation_test.dart`

**Interfaces:**

- Consumes all preceding tasks.
- Produces the completed `ThemeV2LibraryPage` integration and final visual
  contract.

- [ ] **Step 1: Write page-state RED tests**

Assert:

- initial loading keeps Library-shaped structure and shell chrome;
- offline/error show retry immediately;
- partial data renders content plus retry banner;
- empty overview renders Create Skill;
- refresh with an existing overview keeps content and shows a live pending
  indicator;
- retry replaces the error with fresh data;
- opening/closing Recent Asset detail preserves Hub surface and offsets;
- opening a container still reaches the existing Asset list adapter;
- opening Create Skill still reaches Skill Builder Step 1.

- [ ] **Step 2: Run page-state tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/library/library_navigation_test.dart --plain-name "state"
```

Expected: loading/error/partial assertions fail until the new state layer is
wired into `ThemeV2LibraryPage`.

- [ ] **Step 3: Complete page state and adapter wiring**

In `ThemeV2LibraryPage`, render:

```dart
if (status == LibraryStatus.loading && controller.overview == null) {
  return const LibraryStateView.loading();
}
if (status == LibraryStatus.offline || status == LibraryStatus.error) {
  return LibraryStateView.error(
    offline: status == LibraryStatus.offline,
    message: controller.errorMessage,
    onRetry: controller.retry,
  );
}
```

For partial and background refresh, keep the active surface mounted and overlay
only the compact status affordance. Map `LibraryRecentAsset.detailCard` into
the existing `showThemeV2AssetDetail` adapter. Keep existing Asset list and
Skill Builder external behavior.

Remove dead `LibrarySnapshot`, `LibraryRecentItem`, Reports aggregation,
old page-local Library route wrappers, old mixed query, and obsolete header
widgets. Do not leave compatibility aliases.

- [ ] **Step 4: Replace golden tests first and verify missing/different baselines**

The golden harness mounts real `ThemeV2PageScaffold` chrome with a
`LibraryNavigationController`, fixed 411 × 960 view, deterministic fonts, and
the fixture overview. Add cases for all four surfaces in both brightness
modes plus Hub at 360 × 800.

Run:

```bash
cd mobile
flutter test test/theme_v2/library/theme_v2_library_golden_test.dart
```

Expected: FAIL because the rebuilt output differs from the old baselines.

- [ ] **Step 5: Generate and visually inspect new baselines**

Run:

```bash
cd mobile
flutter test --update-goldens test/theme_v2/library/theme_v2_library_golden_test.dart
```

Inspect every Light/Dark image. Confirm:

- correct Top Nav/Dock matrix;
- no breadcrumbs or Hub subtitle;
- numeric-only ordinals;
- canonical 6 px mosaic;
- no overflow or clipped final actions;
- one-row Recently Generated;
- readable dark borders/counts;
- no selected underline.

After any visual correction, regenerate and inspect again.

- [ ] **Step 6: Run the complete Library verification**

Run:

```bash
cd mobile
dart format lib/theme_v2/library test/theme_v2/library lib/theme_v2/shell/theme_v2_app_shell.dart lib/theme_v2/asset/asset_card.dart
flutter test test/theme_v2/library
flutter analyze lib/theme_v2/library test/theme_v2/library lib/theme_v2/shell/theme_v2_app_shell.dart lib/theme_v2/asset/asset_card.dart
```

Expected: all Library tests and static analysis pass.

- [ ] **Step 7: Run adjacent regression**

Run:

```bash
cd mobile
flutter test test/theme_v2/asset test/theme_v2/shell test/theme_v2/calendar test/theme_v2/session
```

Expected: all adjacent suites pass.

- [ ] **Step 8: Audit the final diff and commit**

Run:

```bash
git diff --check HEAD -- mobile/lib/theme_v2/library mobile/test/theme_v2/library mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart mobile/lib/theme_v2/asset/asset_card.dart mobile/test/theme_v2/asset/asset_card_test.dart
git status --short
git diff --stat HEAD -- mobile/lib/theme_v2/library mobile/test/theme_v2/library mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart mobile/lib/theme_v2/asset/asset_card.dart mobile/test/theme_v2/asset/asset_card_test.dart
```

Confirm only Library rebuild files, the Asset semantic fix, Shell integration,
the approved design/plan, and new golden files are included. Preserve all
unrelated user-owned changes.

Commit:

```bash
git add mobile/lib/theme_v2/library mobile/test/theme_v2/library mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart mobile/lib/theme_v2/asset/asset_card.dart mobile/test/theme_v2/asset/asset_card_test.dart
git commit -m "test(library): lock complete theme v2 rebuild"
```

---

## Completion Checklist

- [ ] Repository makes exactly five overview requests and only one Skills request.
- [ ] Recently Generated is Asset-only, sorted by creation time, and capped at 50.
- [ ] Four system containers remain product-defined during partial data.
- [ ] Backend totals win over loaded-item counts.
- [ ] Index and All search state are independent.
- [ ] Pinned saves serialize, cap at six, and roll back visibly.
- [ ] Library surface stack preserves origin and handles Android back.
- [ ] Shell chrome matches the four-surface matrix.
- [ ] Hub has no kicker/subtitle and uses numeric 6 px pinned geometry.
- [ ] All directories and Configure Pinned match the handoff contracts.
- [ ] Loading, empty, partial, offline, error, retry, and pending states exist.
- [ ] Scroll and filter state survive forward/back/detail interactions.
- [ ] Light/Dark and 360 px visuals were inspected.
- [ ] Library, Asset, Shell, Calendar, and Session verification passes.
