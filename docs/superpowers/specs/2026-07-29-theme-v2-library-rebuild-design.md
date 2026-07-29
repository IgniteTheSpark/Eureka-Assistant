# Theme V2 Library Rebuild Design

Date: 2026-07-29

Status: approved for implementation planning

## Goal

Rebuild the complete Theme V2 Library tranche from the current Library + Assets
handoff. The result replaces the existing V2 Library data aggregation,
navigation, state management, and four Library surfaces while preserving the
public app-shell entry and the adapters into later Asset and Skill Builder
work.

## Sources of Truth

Implementation follows:

1. `spec/design/redesignureka.pen`, section `WLBLn`
2. `spec/design/theme-v2-library-assets-handoff.md`
3. Shared Theme V2 tokens, global top navigation, floating Dock, and Part 1
   `ThemeV2AssetCard`

The Library whitelist is:

| Surface | Light | Dark |
|---|---|---|
| Library Hub | `LTmYy` | `c5ejE` |
| Container Index | `B70HCg` | `RTqWK` |
| All Containers | `V0MnR` | `uSlon` |
| Configure Pinned | `rssuX` | `PnnTE` |

When an older canvas detail conflicts with an explicit handoff requirement,
the handoff requirement wins for:

- no breadcrumbs or web-style path labels;
- no explanatory subtitle below the Hub title;
- numeric-only pinned ordinals;
- no underline-based selected state;
- one Light/Dark component tree;
- newest 50 Assets only in Recently Generated.

Canvas geometry, spacing, hierarchy, color treatment, and chrome visibility
remain authoritative.

## Scope

This rebuild includes:

- Library overview loading and aggregation;
- Library navigation and shell-chrome coordination;
- Library Hub;
- Container Index;
- All Containers;
- Configure Pinned;
- Create New Skill entry points;
- initial loading, empty, partial, offline, error, retry, and pending states;
- pinned ordering persistence and rollback;
- search, back behavior, and scroll-position preservation;
- Light/Dark and narrow-width coverage.

This rebuild does not implement or redesign:

- Todo tabs and Todo item logic;
- concrete Asset container lists;
- Asset detail sheets;
- Asset editors;
- Skill Builder internals;
- Calendar, Session, Goals, Devices, or Reports.

Those consumers remain connected through explicit callbacks and adapters.

## Architecture

The rebuild removes the current V2 Library's mixed model/controller file and
full-screen route wrappers. It introduces focused domain, repository,
navigation, controller, state, and presentation units.

### Files and responsibilities

`library_models.dart`

- Defines immutable Library domain models.
- Contains no Flutter widgets, API calls, persistence, or navigation.
- Owns container grouping, counts, activity labels, and Recent Asset
  projection inputs.

`library_repository.dart`

- Loads the Library overview from mature APIs.
- Requests the latest 50 Assets explicitly.
- Loads Skills, Events, Contacts, and backend Asset counts concurrently.
- Returns successful source data plus typed source failures.
- Does not load Reports for Library presentation.

`library_navigation.dart`

- Owns the Library surface stack.
- Exposes shell-chrome requirements for the active surface.
- Implements back and home behavior without pushing a route over the app
  shell.

`library_controller.dart`

- Coordinates repository loading and pinned persistence.
- Exposes status, overview, per-directory search queries, pinned containers,
  and available containers.
- Serializes optimistic pinned saves and rolls back the visible order on
  failure.

`library_states.dart`

- Provides Library-specific loading, empty-search, empty-library, partial, and
  error/retry presentations.
- Keeps page structure visible rather than replacing failure with an
  indefinite skeleton.

`library_components.dart`

- Provides the stats bar, pinned tile, system container card, directory row,
  search field, metrics, available-container tile, section label, and Create
  Skill action variants.
- Uses Theme V2 semantic tokens only.

`library_hub.dart`, `container_index.dart`, `all_containers.dart`,
`pinned_configuration.dart`

- Each file renders one Library surface and contains no fetching or route
  construction.

`theme_v2_library_page.dart`

- Remains the public Library entry.
- Owns or accepts a data controller and accepts the shell-owned navigation
  controller.
- Selects the active Library surface.
- Adapts container and recent-asset actions to existing Asset list/detail and
  Skill Builder entry points.

`theme_v2_app_shell.dart`

- Owns the production `LibraryNavigationController` and passes it into
  `ThemeV2LibraryPage`.
- Rebuilds shell chrome when the active Library surface changes.
- Does not duplicate global navigation inside Library page widgets.

## Domain Model

### Container types

```dart
enum LibraryContainerType {
  todo,
  notes,
  event,
  contact,
  custom,
}
```

The four system containers are exactly:

1. Todo
2. Notes
3. Events
4. Contacts

All enabled user-created Skills become custom containers. Reports and
`external_ref` are not injected as Library system containers.

The four system containers are product-defined and remain present during a
partial load. Skills metadata may provide their mark and backend identity, but
does not decide whether they exist. When a source and its backend count are
both unavailable, the affected container stays visible with a zero fallback
and the overview remains visibly partial.

### Container summary

```dart
class LibraryContainerSummary {
  final String id;
  final String label;
  final String mark;
  final LibraryContainerType type;
  final int totalCount;
  final String? activityLabel;
  final String? userSkillId;
  final bool isSystem;
}
```

`totalCount` always comes from a backend total when that source succeeded. The
number of records currently loaded in memory never substitutes for a known
backend total.

`activityLabel` is presentation-ready, optional metadata:

- Todo: today's item count when derivable;
- Notes: most recent activity;
- Events: next event time;
- Contacts: current-week additions when derivable;
- Custom Skills: most recent Asset activity among the overview records.

Missing activity data hides the secondary line; it does not invent a value.

### Recent Asset

```dart
class LibraryRecentAsset {
  final String id;
  final String skillName;
  final String skillLabel;
  final String mark;
  final String primaryValue;
  final DateTime createdAt;
  final Map<String, dynamic> detailCard;
}
```

Recently Generated contains only real Assets. It is sorted by `createdAt`
descending and truncated to 50 after defensive client-side sorting. Events,
Contacts, and Reports are not merged into this list.

### Overview

```dart
class LibraryOverview {
  final List<LibraryContainerSummary> systemContainers;
  final List<LibraryContainerSummary> customContainers;
  final List<LibraryRecentAsset> recentAssets;
  final int totalAssetCount;
  final Map<String, LibrarySourceFailure> failedSources;
}
```

The combined ordered `containers` view is system first, then custom. Container
and custom totals are derived from these normalized lists.

## Repository Contract

```dart
abstract interface class LibraryRepository {
  Future<LibraryOverview> loadOverview();
}
```

The API implementation performs one concurrent overview load:

- `GET /api/assets?limit=50`
- `GET /api/skills`
- `GET /api/events`
- `GET /api/contacts`
- `GET /api/assets/counts`

Every source is captured independently.

The Skills response is parsed once into both container metadata and the active
`RenderSpec` needed to resolve a Recent Asset's primary value. The repository
does not issue a second `/api/skills` request. Custom primary fields therefore
follow the saved card-display/render specification rather than a list of
guessed payload keys.

- All sources fail: throw typed offline or load failure.
- Some sources fail: return an overview with `failedSources`.
- Successful empty sources remain successful empty data.
- Asset counts fall back to counts derived from the 50 overview Assets only
  when the counts source failed; this fallback is marked partial.
- The repository never performs view-specific navigation or persistence.

Stale overlapping loads cannot replace a newer retry response.

## Controller Contract

The controller owns these status values:

```dart
enum LibraryStatus {
  idle,
  loading,
  ready,
  partial,
  empty,
  offline,
  error,
}
```

It exposes:

- immutable current overview;
- independent Container Index and All Containers search queries;
- sanitized pinned IDs, capped at six;
- pinned containers in persisted order;
- available containers in catalog order;
- pending and error state for pinned persistence.

Pinned mutations are optimistic:

1. update visible order immediately;
2. serialize the persistence call;
3. confirm the saved order on success;
4. restore the latest confirmed order on failure;
5. expose concise failure feedback.

Disposal invalidates pending loads and mutations.

## Navigation and Shell Chrome

```dart
enum LibrarySurface {
  hub,
  containerIndex,
  allContainers,
  pinnedConfiguration,
}
```

The navigation controller maintains a small surface stack so All Containers
can return to either Hub or Container Index without losing origin state.

| Surface | Global Top Nav | Floating Dock |
|---|---:|---:|
| Hub | yes | yes |
| Container Index | yes | yes |
| All Containers | yes | no |
| Configure Pinned | no | yes |

Navigation rules:

- Hub stats region opens Container Index.
- Hub `全部容器` action opens All Containers.
- Hub pinned tile opens its Asset container adapter.
- Hub pinned long press and configure action open Configure Pinned.
- Container Index system/custom rows open their container adapter.
- All Containers back returns to its exact origin.
- Configure Pinned `完成配置` returns to its exact origin.
- Android/system back pops the Library surface stack before leaving Library.
- Reselecting the Library Dock destination returns the Library to Hub.
- Navigating to another Dock destination and back preserves the current
  Library surface until Library is explicitly reselected.

No Library surface constructs a duplicate global Top Nav or Dock.

## State Preservation

A stable `PageStorageBucket` and unique keys preserve:

- Hub vertical scroll;
- Hub Recently Generated horizontal scroll;
- Container Index scroll;
- All Containers scroll;
- Configure Pinned scroll;
- independent search query per directory surface.

Opening and closing an Asset detail or later Asset list recreates neither the
Library data controller nor the shell-owned navigation controller. Returning
restores the prior surface, filter, and offset.

## Surface Design

### Library Hub

- Horizontal inset: 18 px at the 411 px reference width.
- Title: `资产库`.
- No kicker, breadcrumb, or explanatory subtitle.
- Stats bar: 375 × 54.
- The stats area and `全部容器` action are separate semantic targets.
- Pinned label: `PINNED / 06`.
- Pinned layout:
  - row one: 247 × 156 and 122 × 156;
  - row two: 186 × 178 on the left;
  - three 183 × 54 compact rows on the right;
  - 6 px gaps.
- Pinned ordinals are numeric only: `01` through `06`.
- Large tile radius: 14 px; compact tile radius: 10 px.
- Press feedback: scale near `0.98` and a subtle luminance change.
- Reduce Motion disables the animated scale while preserving feedback state.
- Create New Skill is a separate 375 × 76 primary action.
- Recently Generated is one 54 px horizontal row.
- Approximately six items are visible at 411 px.
- It uses Part 1 `ThemeV2AssetCard` with `iconTime`.
- It has no count badge, second row, pagination, or `全部` action.

### Container Index

- Global Top Nav and Dock remain visible.
- Title: `资产容器`.
- No breadcrumb, subtitle, or page-local duplicate top navigation.
- Search: 371 × 44.
- System group uses four 371 × 56 surfaced rows with name, optional activity,
  total count, and chevron.
- Custom group uses 371 × 50 flat rows with separators, name, and count.
- Create New Skill is a compact 371 × 52 footer action.
- There is no redundant `查看全部容器` button in the body.

### All Containers

- Global Top Nav remains visible; Dock is hidden.
- Native back target and title `全部容器`.
- Three 76 px metric cards show Container, Asset, and Custom totals.
- Search: 371 × 42.
- System and custom groups use 54 px directory rows with a 34 px mark box,
  name, optional activity, count, and chevron.
- Create New Skill is a 371 × 48 footer action.
- Long content scrolls; the last action remains reachable above the safe area.

### Configure Pinned

- Global Top Nav is hidden; Dock remains visible.
- The page provides its own configuration title and `完成配置` action.
- It reuses the same pinned geometry as Hub.
- Ordinals remain numeric only.
- Selected, focused, and drag states never use an underline.
- A pinned tile exposes reorder and remove actions with 44 px semantic targets.
- Dragging uses long press and supports Reduce Motion.
- The create/add Skill banner is distinct from the Hub copy.
- Available containers render as compact add tiles with at least 44 × 44 touch
  targets.
- At six pins, remaining add tiles are disabled and explain the limit.
- Empty pinned and all-pinned states remain actionable and legible.

## Search and Empty States

Container Index and All Containers filter system and custom groups locally
from their own query.

- Empty catalog: show Library empty state and Create New Skill action.
- Empty search: show query-aware empty state with `清除搜索`.
- Clearing search restores both groups without reloading.
- Search never mutates pinned ordering or overview data.

Initial loading uses a Library-shaped skeleton. Offline and error states show
retry immediately. Partial data remains visible with a retry banner.

## Accessibility

- Every interactive target is at least 44 × 44 px.
- Container semantics announce name and total count.
- Directory rows include activity metadata in their label when visible.
- Stats announce both number and meaning.
- Recent Asset semantics announce Skill, primary value, and localized time.
- Pinned configuration exposes native button and reorder semantics.
- Disabled add actions announce that the six-item maximum was reached.
- Focus returns to the originating control after a modal Asset detail closes.
- Dynamic Type keeps primary actions reachable; visual truncation does not
  remove the full semantic label.

## Migration

The rebuild replaces the existing V2 Library implementation in focused
commits:

1. introduce new domain/repository contracts and tests;
2. introduce Library navigation and shell-chrome coordination;
3. replace shared Library components;
4. replace Hub;
5. replace Container Index and All Containers;
6. replace Configure Pinned;
7. replace Library state handling and adapters;
8. update goldens and run adjacent regression.

The stable external entry remains:

```dart
const ThemeV2LibraryPage(...)
```

Existing callbacks for opening a container, opening a recent Asset, creating a
Skill, and setting a Goal remain available as test and integration seams.

Legacy V2 internal model names are not retained as compatibility aliases.
Callers inside the Theme V2 Library package migrate to the new contracts in the
same change set.

## Verification

Automated verification includes:

- repository source aggregation, limit, sorting, partial, offline, and retry;
- normalized system/custom container projection and backend totals;
- stale-load and disposal races;
- independent directory queries and clear-search behavior;
- surface-stack navigation and shell-chrome matrix;
- Android back and Library Dock reselection;
- pinned add/remove/reorder, six-item cap, serialized saves, and rollback;
- Hub geometry, numeric ordinals, pressed feedback, Reduce Motion, and one-row
  Recently Generated;
- container row variants and accessibility labels;
- scroll-position preservation;
- 360 px overflow checks;
- 411 × 960 Light/Dark golden coverage for all four Library surfaces;
- adjacent Theme V2 Shell, Asset, Calendar, and Session regression suites.

## Acceptance Criteria

- All four whitelisted Library surfaces use the rebuilt architecture.
- No Library page duplicates or accidentally hides shell chrome.
- Hub contains no breadcrumb or explanatory subtitle.
- Pinned ordinals contain digits only.
- Pinned layout uses the canonical 6 px geometry.
- No selected state is represented by an underline.
- Recently Generated contains at most 50 newest Assets in one horizontal row.
- Container totals use backend totals when available.
- System containers are exactly Todo, Notes, Events, and Contacts.
- Search, surface, and scroll state survive forward/back navigation.
- Pinned persistence failure visibly rolls back.
- Loading, empty, partial, offline, error, pending, and retry states are
  implemented.
- Light and Dark use one semantic component tree.
- All relevant touch targets and semantic labels satisfy the handoff.
- Library and adjacent regression tests pass with no static-analysis issues.
