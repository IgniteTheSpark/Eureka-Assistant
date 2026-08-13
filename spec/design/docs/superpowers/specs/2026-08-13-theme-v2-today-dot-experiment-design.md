# Theme V2 Today Dot-Matrix Experiment Design

> Date: 2026-08-13
>
> Status: Approved design; awaiting written-spec review
>
> Product surface: Theme V2 Today / Light / experimental empty scene
>
> Pencil source: `redesignureka.pen`, node `zjzLR` (`UReka · Theme V2 / Light / Today Renew / Empty / 411`)

## 1. Outcome

Implement a small, reversible Today experiment for long-running device feedback before rebuilding the complete active Today page.

The experiment validates only:

- the Light dot-matrix material;
- Reka as a living deformation beneath that material;
- Reka's three quick actions;
- pull-to-refresh and its restrained dot feedback.

The current Today implementation remains available as the default and fallback. Calendar, Library, Session, reports, dark mode, active Today content, signals, and asset balls are not redesigned in this tranche.

## 2. Rollout Boundary

The experiment is selected at compile time:

```text
--dart-define=TODAY_DOT_EXPERIMENT=true
```

`TODAY_DOT_EXPERIMENT` defaults to `false`.

When disabled, the application uses the current `ThemeV2HomePage` without visual or behavioral changes. When enabled, the Today destination uses the experimental Light empty scene. The experiment intentionally does not render schedule, signal, or asset content, even when the repository returns it. It is a UX evaluation build, not a complete production Today replacement.

Tests receive an explicit override seam so they do not depend on process-level compile-time state.

## 3. Visual Contract

Reference viewport is `411 × 860`. The scene extends to the actual safe-area and Dock bounds on taller devices without scaling the grid artwork.

The visible stack from back to front is:

1. warm gray-green surface;
2. static base dot grid;
3. local Reka deformation sampled from the same grid;
4. Reka eye-dot clusters;
5. global navigation, Today title/date, and the existing Dock;
6. Reka quick-action menu or refresh/error overlay when present.

Reference material values:

| Property | Value |
|---|---|
| Surface | approximately `#E3EAE5` |
| Base dot | approximately `#74837A` |
| Grid interval | `8 logical px` |
| Base radius | `0.8–1.0 logical px` |
| Base opacity | `0.42–0.55` |
| Reka influence radius | `86–95 px` |
| Reka center-dot radius | up to approximately `2.2–2.5 px` |
| Eye signal | warm orange-red, approximately `#C6532F` |

Dots are crisp circles aligned to physical pixels. The grid is a background material, not a card, input surface, particle field, or information visualization.

The empty scene contains only:

- global navigation;
- `今日` and its date metadata;
- the continuous dot field;
- Reka;
- the authored line `今天很安静，我在这里。`;
- the existing floating Dock.

No empty cards, schedule placeholder, signal counter, asset placeholder, or automatically expanded menu is shown.

## 4. Dot-Matrix Behavior

### 4.1 Base field

The base dot field is completely passive:

- no hit testing;
- no pointer, drag, tilt, parallax, or scroll response;
- no business-state encoding;
- no continuous full-field animation;
- no independent accessibility semantics.

The dot field stays fixed behind the Today scene while foreground chrome and overlays are composited above it.

### 4.2 Reka beneath the membrane

Reka is not a separate illustrated sphere. It is a local radial displacement and density change in the existing grid, with eye-dot clusters above the deformation.

The base grid remains still outside Reka's influence radius. Inside the radius, Reka has a slow autonomous idle motion so it reads as alive rather than printed:

- breathing period: `4.5–6 s`;
- influence-radius change: at most `±4 px`;
- center drift: at most `1–2 px`;
- easing: continuous sine-like motion with no loop seam;
- boundary: smooth falloff with no visible circle or outline.

The eyes may blink or shift their gaze occasionally. Eye motion must be sparse and must not imply a notification or required action.

User input does not deform the dots. Tapping Reka produces no ripple, gather, halo, burst, or density response; it only presents the quick-action menu.

### 4.3 Reduced motion

When Reduce Motion is enabled:

- Reka's local deformation is static;
- eye changes use a short cross-fade or remain static;
- refresh feedback uses opacity only;
- menu presentation uses the product's reduced-motion transition.

## 5. Reka Interaction

Reka owns an invisible hit target of at least `64 × 64 px`, positioned over the visible deformation. It stays above the dot painter in hit testing.

Accessibility contract:

```text
name: Reka 快捷操作
role: button
state: collapsed / expanded
```

Tap opens a compact menu near Reka with exactly three actions:

1. `创建资产` — reuse the existing create-asset menu and schema-driven creation flow;
2. `创建报告` — open the existing Report container with create mode requested;
3. `开始新聊天` — open the existing Theme V2 blank Session flow.

Selecting an action closes the menu before navigation. Dismissing the menu changes no data. Long press, Flash Thought, signals, expressions driven by business state, and extra disabled actions are excluded.

## 6. Refresh Interaction

The experimental empty scene is always vertically pullable, including when its foreground content is shorter than the viewport.

Refresh data flow:

```text
pull crosses threshold
→ call the existing ThemeV2HomeRepository.load()
→ retain the current scene while loading
→ complete or fail
→ keep the experiment scene visible
```

Dot feedback is deliberately small and does not translate dots:

- while pulling, only a shallow band near the top increases dot opacity slightly;
- on release, that band returns to its resting opacity over approximately `320 ms`;
- there is no ripple, wave displacement, spinner made from moving dots, or whole-page pulse;
- the feedback is visual accompaniment to refresh, not an additional control.

Refresh semantics announce `正在刷新今日` through a polite live region.

On success, repository state is updated for future tranches, but schedule, signals, and assets remain hidden by the experiment boundary. On failure, keep the scene intact and show the existing recoverable refresh-failure message with `重试`.

## 7. Component Boundaries

The implementation should isolate the experiment instead of adding experimental branches throughout the current three-card Home tree.

Suggested units:

```text
TodayDotExperimentPage
├── TodayDotMatrixScene
│   ├── TodayDotMatrixPainter
│   ├── TodayRekaDeformation
│   └── TodayRekaHotspot
├── TodayRekaQuickActions
└── TodayDotRefreshOverlay
```

Responsibilities:

- `TodayDotExperimentPage`: repository lifecycle, refresh state, route callbacks, and experiment scene composition;
- `TodayDotMatrixScene`: responsive scene geometry and the passive background contract;
- `TodayDotMatrixPainter`: physical-pixel-aligned base grid plus local Reka deformation;
- `TodayRekaDeformation`: small autonomous animation values only, with no navigation or repository knowledge;
- `TodayRekaHotspot`: semantics and tap handling independent of paint geometry;
- `TodayRekaQuickActions`: three existing-route adapters and dismissal behavior;
- `TodayDotRefreshOverlay`: pull progress and the short opacity recovery.

The painter must repaint only for Reka's low-frequency idle animation or refresh opacity changes. Navigation, repository results, and unrelated shell rebuilds must not regenerate grid geometry unnecessarily.

## 8. Shell and Routing Integration

`ThemeV2AppShell` remains the owner of global navigation and route construction.

The shell selects either the existing Home or the experiment at the Today destination. It injects callbacks for asset creation, report creation, and blank Session navigation so the experiment does not construct mature flows internally.

The existing top navigation and Dock remain canonical. The experiment does not create a second app bar, dock, theme switch, or navigation stack.

## 9. Error and Edge States

- Initial repository load failure does not replace the experiment with a full-screen error; the passive scene remains visible and a recoverable message is announced.
- Repeated refresh requests are coalesced while one request is active.
- A late response from an older request cannot replace the current refresh state.
- Route callbacks that are unavailable in an isolated test host disable the corresponding action semantically rather than throwing.
- Text scaling keeps the authored line readable without changing Reka's hit-target minimum.
- Narrow devices preserve the `8 px` grid interval and adjust scene placement, not grid scale.
- App backgrounding pauses autonomous Reka animation through normal ticker lifecycle behavior.
- Dark theme is outside this tranche. If the application is forced dark while the experiment is enabled, the experiment continues using its explicit Light evaluation palette rather than presenting an unreviewed dark derivation.

## 10. Verification

### Widget behavior

- experiment flag/override selects the correct Home implementation;
- disabled experiment preserves the current Home tree;
- base painter ignores pointer input;
- Reka exposes a `64 × 64 px` or larger semantic button;
- tapping Reka opens exactly three actions;
- every quick action invokes its injected route callback once;
- dismissing the menu invokes no action;
- empty scene can pull to refresh with short content;
- concurrent refreshes are coalesced;
- refresh failure preserves the scene and exposes Retry;
- reduced motion stops Reka deformation and uses opacity-only refresh feedback.

### Visual and geometry

- Light `411 × 860` empty-scene Golden matches Pencil node `zjzLR`;
- at least one taller viewport verifies safe-area extension without artwork scaling;
- grid interval remains `8 logical px` across tested device-pixel ratios;
- Reka falloff has no hard circular boundary;
- refresh-rest and refresh-active Goldens differ only in the intended top band and ordinary system overlays;
- no overflow, clipped authored copy, Dock collision, or content behind the home indicator.

### Performance

- no full-scene image asset is required for the grid;
- grid geometry is cached for a stable viewport;
- the painter does not allocate one Widget per dot;
- idle Reka animation is scoped to the scene repaint boundary;
- profile-mode frame timing is inspected on the target Android device before expanding the experiment.

## 11. Acceptance Checklist

- [ ] The experiment is opt-in and the existing Home remains unchanged when disabled.
- [ ] The Light empty scene matches Pencil node `zjzLR` at `411 × 860`.
- [ ] The dot matrix is a passive background with no direct interaction.
- [ ] Only the Reka-local region moves autonomously.
- [ ] Reka motion is slow, bounded, and disabled by Reduce Motion.
- [ ] Reka tap does not animate or deform the dots.
- [ ] Reka opens Create Asset, Create Report, and Start New Chat.
- [ ] Pull-to-refresh works on the empty scene.
- [ ] Refresh feedback changes local opacity only and settles in about `320 ms`.
- [ ] Refresh failure preserves the scene and can retry.
- [ ] Schedule, signals, asset balls, dark mode, and other pages remain outside this tranche.

## 12. Follow-up Tranches

Only after sustained device feedback approves the material, density, Reka motion, hit target, and refresh feel:

1. implement Pencil node `ToR3u` and reconnect schedule, signals, and asset balls;
2. validate the complete Light Today state model;
3. design and tune the Dark Today palette;
4. decide whether the static dot background grammar should expand to other pages.
