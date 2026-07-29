# Theme V2 Assets + Skill Builder Rebuild Design

**Date:** 2026-07-29  
**Status:** Approved for implementation  
**Visual source of truth:** `spec/design/redesignureka.pen`, Library/Assets section `WLBLn`  
**Behavioral source of truth:** `spec/design/theme-v2-library-assets-handoff.md`

## 1. Objective

Finish the Theme V2 Library asset tranche as one coherent system:

1. Rebuild the four system asset containers and custom-skill asset containers.
2. Rebuild asset detail, long-text expansion, source provenance, completion, deletion, and editing.
3. Rebuild Skill Builder as the handoff's exact three-step flow.
4. Reuse one Card Display Settings model and selector in Skill Builder and existing-skill configuration.
5. Remove “设为目标” from Asset Detail and remove its callback/result plumbing.

The result must preserve the proven backend behavior and existing asset data while replacing the partial generic Theme V2 UI with the handoff/Pen contract.

## 2. Scope

### 2.1 Included

- Todo, Notes, Events, Contacts container screens.
- Custom-skill container screens.
- Container loading, empty, error, refresh, filtering, pagination, and scroll restoration.
- Shared card rendering for asset rows and live editor/builder previews.
- Todo status tabs: `全部`, `今天`, `已完成`, `待安排`.
- Asset details as bottom sheets that expand in place to full page.
- Domain-aware presentation for Todo, Notes, Event, Contact, and custom-schema assets.
- Long-text overflow detection, fade, “查看全部”, selection, and local scrolling.
- Source provenance above the sticky action footer.
- Optimistic Todo completion with rollback.
- System preset edit pages and custom-schema editing.
- Skill Builder Step 1 Describe, Step 2 Fields, and Step 3 Card.
- Existing custom-skill Card Display Settings opening directly in Step 3 configuration mode.
- Presentation serialization compatible with canonical `card_display` and legacy render-spec readers.
- Removal of the Asset Detail goal action, public callback, intent result, and implementation file.

### 2.2 Excluded

- Goal domain, Goal Core, and Today logic.
- Calendar behavior and layout.
- Session-card interaction changes outside Library.
- Backend schema migrations.
- Editing an existing skill's schema. Existing-skill configuration is presentation-only.
- Changing the production default of `THEME_V2`.

## 3. Product Rules

### 3.1 Container identity

The four system containers are exactly:

- Todo
- Notes
- Events
- Contacts

They use dedicated list, detail, and editor presentation where the domain requires it. Custom skills remain separate containers and use their payload schema plus render specification.

### 3.2 Asset cards

- Asset-container rows and all live previews use the shared Theme V2 asset-card primitives.
- Rich custom records use `ThemeV2AssetCard.richCard`.
- Recent/simple records use the approved icon/time variant where specified.
- Todo may use its compact domain row, but typography, surface, radius, spacing, and states come from the shared Library component layer.
- A row never invents a second render-spec interpretation; it receives an already-normalized card projection.

### 3.3 Detail presentation

- Every asset type opens as a bottom sheet.
- The half state is 576 logical pixels high on the 411×960 reference viewport, capped safely for smaller devices.
- Expand changes the same route/controller into the full state. It does not fetch again.
- Full state begins below the global top navigation and occupies the remaining viewport.
- Collapsing returns to the same half-sheet state with the same draft, hydration, and content position.
- Closing restores the exact container filter and scroll offset.
- Source provenance is placed 8 logical pixels above the sticky action area.
- Footer actions stay visible while record content scrolls.
- “设为目标” does not exist in any asset-detail state.

### 3.4 Long text

In half state:

- The body is 371×120 on the reference viewport.
- It shows roughly five to six lines.
- Overflow gets a bottom fade and “查看全部”.
- Non-overflow text gets neither.

In full state:

- The text region is 371 logical pixels wide.
- Its target height is about 480, with a 320 minimum when the viewport is constrained.
- Only this text region scrolls.
- Text is selectable.

### 3.5 Todo

- Tabs are `全部`, `今天`, `已完成`, `待安排`.
- Each tab shows its count and keeps its own scroll offset.
- Records without a date/time are unscheduled and are grouped at the end of the appropriate result, never mixed between scheduled records.
- Completion updates immediately and rolls back on request failure.
- Detail's primary action is completion/reopen according to state.

### 3.6 Editors

- Todo, Notes, Event, Contact, and custom-schema records route to their domain editor.
- System preset assets retain their dedicated edit pages.
- Editors show a sticky live card preview before the form.
- Preview updates from the local draft without writing to the backend.
- Saving validates required fields, performs the typed write, updates the previous detail/list projection, and closes only on success.
- Failed saves retain user input and expose a retryable inline error.

## 4. Architecture

### 4.1 Read models

Introduce an `AssetRecordViewModel` boundary between API/domain objects and widgets. It contains:

- stable record ID and container identity;
- record kind (`todo`, `note`, `event`, `contact`, `custom`);
- normalized title, subtitle, metadata, timestamps, and status;
- ordered field values for detail/editor display;
- source provenance;
- payload schema and original payload where applicable;
- a normalized card projection derived from `CardDisplayConfig`.

`AssetRecordAdapter` converts existing `AssetItem`, Event, Contact, and custom-skill responses into this view model. Widgets do not parse backend payloads or render specs directly.

### 4.2 Container state

`AssetContainerController` owns:

- the selected filter/tab;
- records and pagination cursor for each filter;
- scroll offset for each filter;
- loading, empty, error, refreshing, and loading-more states;
- optimistic Todo mutations and rollback snapshots.

System and custom containers share the controller contract but use typed repository loaders. The controller is retained above the detail route so return navigation does not rebuild the list state.

### 4.3 Detail state

Keep the current `AssetDetailController` behavior that already provides one-time hydration and preserves state between half/full modes. Extend it to expose:

- normalized `AssetRecordViewModel`;
- presentation kind;
- expand/collapse state;
- long-text region state;
- completion, edit, and delete commands;
- source provenance;
- operation-specific error state.

Presentation is split into domain widgets rather than one generic field dump:

- `TodoAssetDetail`
- `NoteAssetDetail`
- `EventAssetDetail`
- `ContactAssetDetail`
- `SchemaAssetDetail`

The route owns geometry and sticky chrome. Domain widgets own only record content and domain actions.

### 4.4 Editors

`AssetEditorRouter` chooses the editor from the normalized record kind. Existing typed Event and Contact write paths remain authoritative. Todo and Notes receive explicit form models. Custom records use an extended schema draft model.

Every editor projects its draft through the same adapter used by list/detail cards, so preview and saved output cannot diverge.

### 4.5 Card display

`CardDisplayConfig` remains the single presentation model:

- exactly one `primaryFieldId`;
- ordered `secondaryFieldIds`;
- at most three secondary fields;
- primary cannot also be secondary;
- enabling a secondary appends it to the order;
- disabling removes it and compacts the remaining order;
- changing primary removes that field from secondary selection.

There is no drag ordering and no density setting.

`CardFieldSelectionController` is a small reducer used by:

- Skill Builder Step 3;
- existing custom-skill Card Display Settings;
- tests for invariants and serialization.

`CardFieldSelector` renders every schema field once with:

- a primary radio;
- a secondary toggle;
- a visible 1–3 activation-order badge.

The controller writes through `CardDisplayConfig.applyToRenderSpec`, preserving unrelated render-spec keys and maintaining the legacy primary/secondary/meta representation required by current consumers.

### 4.6 Skill Builder

The visible flow is exactly three steps:

1. **Describe** — free-form description, examples, AI guidance, and any clarification questions embedded in the same step.
2. **Fields** — edit generated name, field label, type, meaning, required status, order; add, remove, and reorder fields.
3. **Card** — shared live RichCard preview plus shared Card Field Selector.

`SkillDraftField` is a mutable draft value with:

- stable local ID;
- backend key;
- label;
- supported field type;
- meaning/description;
- required flag.

`SkillBuilderController` owns the draft/reducer and separates:

- generation/clarification;
- local schema editing;
- local card projection;
- final create confirmation.

Creation submits the edited payload schema plus the compatible render spec to the existing confirm endpoint.

Existing custom-skill settings use the same Step 3 screen in `configuration` mode:

- load the stored payload schema and render spec;
- do not expose schema editing;
- save only presentation fields through the existing skill PATCH endpoint;
- keep the current skill and records intact.

## 5. API and Compatibility

- Continue using existing typed Todo/Notes/Events/Contacts/custom-asset endpoints.
- Continue using the existing Skill Builder draft and confirm endpoints.
- Continue using `PATCH /api/skills/{user_skill_id}` for presentation-only configuration.
- Preserve unknown payload and render-spec fields when editing.
- Read both canonical `card_display` and legacy render-spec forms.
- Write canonical `card_display` and the compatible legacy representation in one operation.
- No backend migration is required for this tranche.

If an implementation test exposes a missing server behavior, document that contract before changing the backend. UI refactoring alone does not authorize a new storage model.

## 6. Navigation and Chrome

- Library container screens remain major pages and retain the global top navigation and persistent dock.
- Bottom-sheet details overlay the current container; they do not replace its navigation state.
- Full detail/editor/builder states preserve the Theme V2 top safe-area and navigation rhythm.
- Skill creation opens at Describe.
- Existing custom-skill configuration opens directly at Card in configuration mode.
- Back from Builder Step 2/3 returns one step; back from Step 1 dismisses without creating.

## 7. Loading, Empty, Error, and Motion

- Initial load uses the shared Library skeleton.
- Empty states are domain-specific and keep the surrounding page structure stable.
- Refresh does not clear already visible records.
- Pagination failure keeps loaded records and offers retry.
- Details show structural content immediately and hydrate missing fields in place.
- Destructive delete requires explicit confirmation.
- Motion uses existing Theme V2 durations and respects Reduce Motion.
- Half/full transitions animate geometry and opacity only; content is not reconstructed.

## 8. Goal Action Removal

The goal action is removed as an API cleanup, not merely hidden:

- delete `set_goal_action.dart`;
- remove `SetGoalIntent`;
- make `showThemeV2AssetDetail` return `Future<void>`;
- remove `onSetGoal` from asset list and `ThemeV2LibraryPage`;
- remove result propagation from sheet/page callers;
- update tests to assert that no goal action is present.

Goal Core itself is untouched.

## 9. Test Strategy

### 9.1 Unit tests

- record adapters for all five kinds;
- Todo filter classification and unscheduled ordering;
- per-tab state and scroll restoration;
- optimistic completion rollback;
- `CardDisplayConfig` and selector reducer invariants;
- Skill schema draft add/edit/remove/reorder/validation;
- compatible render-spec serialization;
- configuration-mode save payload;
- goal callback/result API removal at compile level.

### 9.2 Widget tests

- all system/custom container states;
- Todo tabs/counts and unscheduled placement;
- half/full detail geometry and state retention;
- sticky source/action footer;
- long-text overflow versus non-overflow behavior;
- dedicated editors and live previews;
- Skill Builder exact three-step progression;
- Step 2 schema editing;
- shared Step 3 selector in create and configuration modes;
- absence of “设为目标”.

### 9.3 Golden tests

Light and dark, 411×960 reference viewport:

- Todo list, half detail, full detail, edit;
- Notes list, half detail, full detail, edit;
- Events list/detail/edit;
- Contacts list/detail/edit;
- custom list/detail/edit;
- Skill Builder Steps 1–3;
- Card Display Settings configuration mode.

### 9.4 Regression and device verification

- run focused Theme V2 asset/library tests;
- run the existing Calendar and Library regression suites;
- run `flutter analyze` for touched files;
- build an Android debug APK with `THEME_V2=true`;
- install on the connected Android device;
- verify Library navigation, all system containers, custom container, detail half/full transitions, edit/save, Skill Builder, existing-skill configuration, and goal-action absence;
- capture screenshots for visual comparison with the Pen.

## 10. Acceptance Criteria

- All Pen-whitelisted Asset screens have an implemented Theme V2 counterpart.
- Four system containers and custom containers preserve their existing data and behavior.
- Todo tabs, counts, unscheduled ordering, and optimistic completion work.
- Details open at the specified half height and expand without refetching or losing state.
- Long text follows the half/full contract.
- Source and sticky actions match the handoff.
- System preset records open their dedicated editors.
- All editor and builder previews use the shared card implementation.
- Skill Builder has exactly three visible steps and supports full Step 2 schema editing.
- Creation and existing-skill configuration share the Step 3 selector and reducer.
- Existing-skill configuration changes presentation only.
- Render specs remain compatible with existing consumers.
- No Asset Detail UI, callback, result type, or source file contains the goal action.
- Focused tests, regression tests, analysis, APK build, and real-device validation pass.
