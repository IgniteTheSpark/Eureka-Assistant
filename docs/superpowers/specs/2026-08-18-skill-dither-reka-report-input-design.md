# Custom Skill Management, Global Dither Readability, Reka Asset Output, and Report Input Design

**Date:** 2026-08-18  
**Status:** Approved for implementation planning  
**Branch:** `codex/skill-dither-report-revamp`

## Context

This round addresses four usability breaks discovered on a real device:

1. A user-created Skill cannot be safely edited or explicitly deleted. A Skill such as a tennis log therefore cannot gain a missing field such as location after creation.
2. The new Dither background visually interferes with schedule grids, small labels, and other dense content. Navigation and page backgrounds also feel like separate surfaces instead of one world.
3. The downward asset output on Today is expressed as a fast terminal seed before it becomes an asset ball. The transition is hard to perceive and has previously produced edge flashes.
4. Report creation treats scope confirmation as a fixed adapter flow. It resolves vague time language too early, does not reliably communicate which Assets will be used, and mixes report subject with report presentation.

## Goals

- Let users explicitly edit and delete their own custom Skills without risking silent corruption of historical Assets.
- Make Dither a continuous global background while guaranteeing crisp dense content.
- Make a generated Asset visibly emerge as a normal Asset ball behind Reka and fall directly into the Asset field.
- Make the first report step answer one question clearly: what inputs will this report use, and what optional guidance has the user supplied?
- Preserve the existing official report-template planner, but give it cleaner user-confirmed inputs.

## Non-goals

- Editing or deleting built-in/system Skills.
- Renaming an existing schema key, changing an existing field type, or destructively removing one field from historical Asset payloads.
- Redesigning the upward signal output flow.
- Letting the user author arbitrary report templates in this round.
- Weakening Dither globally merely to hide readability problems.

## Design principles

- **Explicit ownership:** destructive Skill actions are visible and limited to user-created Skills.
- **Stable data contracts:** existing schema keys and types remain stable; presentation metadata may evolve.
- **One continuous world:** Dither is rendered once behind the entire primary page shell.
- **Material continuity:** the moving object seen leaving Reka is the same Asset ball that enters physics.
- **Progressive clarification:** ask only for information missing from the user's report request.
- **User-confirmed evidence:** the report plan is generated only after the user can see and adjust its Assets.

## 1. Custom Skill management

### Current diagnosis

Theme V2 already exposes `PATCH /api/user-skills/{skill_id}` and accepts schema and render updates, but the product does not expose a complete custom-Skill editing experience. The update API also accepts unrestricted schema replacement and does not enforce the compatibility rules needed for historical Assets. Theme V2 has no delete endpoint even though `assets.user_skill_id` already uses `ON DELETE CASCADE`.

### Entry points

A user-created Skill detail screen exposes two discoverable actions:

- `编辑技能`
- `删除技能`

They must not depend on swipe gestures. Built-in Skills display neither action.

### Edit flow

The edit screen reuses the field and card-configuration portions of the Skill creation wizard, initialized from the current Skill.

Allowed changes:

- Skill display name and description.
- Existing field display label and meaning/description.
- Field order.
- Existing field visibility.
- New fields, including a new stable key and a selected type.
- Card icon and field presentation slots already supported by the current configuration UI.

Compatibility rules:

- Every field remains optional. No required-field control is shown.
- Existing field keys are read-only.
- Existing field types are read-only.
- An existing field is hidden rather than deleted. Its payload value remains readable on historical Assets.
- New keys must be unique snake_case and cannot reuse a hidden historical key with a different type.
- At least one visible field must remain.
- Routing metadata is preserved unless the edited name/description requires its display copy to change; this round does not silently regenerate routing semantics.

The service validates the submitted schema against the stored schema before persisting it. A compatibility violation returns `409` with a stable error code that the mobile UI maps to a field-specific explanation.

### Delete flow

Before confirmation the client receives the number of Assets owned by the Skill. The dialog states that the Skill and all `N` records will be permanently deleted.

On confirmation:

- The service verifies that the Skill belongs to the user.
- The service rejects deletion when `global_skill_id` is non-null or the machine name is protected.
- The service deletes the custom `UserSkill`; database cascades delete its Assets and dependent Asset-field rows.
- The response includes the deleted Skill id and deleted Asset count for UI confirmation and diagnostics.
- The client removes stale list/detail state and returns to the Skill library.

Suggested API additions:

```text
GET    /api/user-skills/{skill_id}/deletion-impact
DELETE /api/user-skills/{skill_id}
```

The delete call is the irreversible second step; it does not overload `enabled=false`.

## 2. Continuous global Dither and readable content

### Current diagnosis

The Dither surface is visually behind content rather than technically blurring it. The perceived blur comes from dynamic high-frequency dots showing through thin grid lines, 8–12 px labels, and translucent list surfaces. The shared Dither implementation also applies a global brightness value that can override page-level opacity intent. Some scrolling backgrounds are owned by an outer stack instead of the moving content, so they appear to drift or disappear.

### Layer model

Each Theme V2 primary page uses one continuous shell:

1. **Global Dither canvas** — one animated field covering the full page bounds, including behind the large top Nav, body, and bottom Dock.
2. **Glass navigation surfaces** — top Nav and bottom Dock sample that same background through a controlled frosted material. They do not instantiate their own Dither painter.
3. **Content isolation surfaces** — schedule grids, asset rows, report body, forms, and other dense reading regions use high-opacity surfaces.
4. **Decorative open space** — page margins and low-density gaps expose the Dither at full global intensity.

### Shared contracts

- One Dither instance per page shell.
- One global light/dark intensity policy; individual pages do not arbitrarily weaken it.
- Glass Nav/Dock tokens provide sufficient contrast for labels and icons in both themes.
- Dense content surfaces use a named opaque/near-opaque token instead of ad hoc alpha values.
- Scrolling row/card backgrounds are painted by the row/card itself so they move with content.
- Thin schedule lines, time labels, empty-date slashes, and secondary labels meet a higher contrast floor than decorative borders.
- Reduced-motion mode freezes or substantially slows the Dither without changing foreground contrast.

### Audit scope

The implementation audits every Theme V2 page using `ThemeV2DitherSurface` or the primary shell, with explicit checks for:

- Calendar flow, schedule timeline, and empty-date treatment.
- Asset library lists and detail/editor surfaces.
- Report list, report input/plan flow, and report reader.
- Today top Nav, content containers, and bottom Dock.
- Any form or list whose text currently sits directly on Dither.

## 3. Reka downward Asset output

### Current diagnosis

The current output overlay shares a terminal Seed representation for signals and Assets. An Asset travels as a small Seed with a trail, then hands off near the Asset floor. This adds an unnecessary intermediate symbol, makes the downward event hard to catch, and creates more handoff states at the container edge.

### New motion

- The upward signal flow remains unchanged.
- The Asset path no longer constructs or paints a terminal Seed or trail.
- A normal-size, final-style Asset ball is created directly behind Reka.
- The ball begins sufficiently occluded to read as emerging from Reka, then becomes visible and falls with a gravity-like acceleration curve.
- Reka gives a brief production pulse, turns clearly downward, tracks the falling ball for a short interval, and returns to idle.
- At the Asset-field boundary the overlay hands the same visual state—position, radius, style, and downward velocity—to the physics layer.
- The physics layer inserts the ball without replacement flash, duplicate frame, or mechanical list refresh.
- Collision with an edge is a normal physics event and never changes the full-screen background color.

For reduced motion, the final Asset ball fades into the nearest valid Asset-field position and joins physics without a long fall.

## 4. Report input confirmation

### Purpose of step one

The first report step is `确认报告输入`. Its primary job is to make the evidence set explicit. Time and Skill type are filters used to find Assets; they are not the report itself.

The screen has three sections:

1. Asset scope.
2. Optional presentation preference.
3. Optional supplemental text.

### Progressive Asset-scope behavior

The intake parser extracts three independent facts from the original request:

- Asset type(s) or specific Skill(s).
- Time range.
- Specific Asset reference(s).

The UI only asks for missing facts:

#### Type is known, time is ambiguous

Example: `总结最近的消费`.

- Show only relevant time-range pills, such as `近 7 天`, `近 30 天`, `本月`, and `自定义范围`.
- After selection, fetch and select every matching Asset in that range.
- Always show `手动添加资产`.

#### Type and time are known

Example: `总结本月的消费`.

- Do not ask the user to repeat either condition.
- Fetch and select every matching Asset.
- Show the selected group and `手动添加资产`.

#### A specific Asset is known

- Select that Asset directly.
- Prompt `还要关联其他资产吗？` beside the manual-add entry.
- Do not force a time-range choice.

#### No usable Asset clue is known

- Show a compact Asset picker seeded with semantically related recent Skills/Assets.
- Require at least one selected Asset before plan generation.

### Asset selection model

The response distinguishes:

- Automatically matched Assets.
- Manually added Assets.
- Explicitly removed Assets.

Changing a time filter recomputes only the automatic set. Manual additions persist. Explicit removals persist while the removed Asset remains within the new candidate set. The final list shown on screen is the authoritative evidence scope submitted to the planner.

Groups show Skill name, selected count, total count, select-all state, and expandable records. The user can remove individual Assets or whole groups and can add Assets outside the inferred type or time range.

### Optional presentation preference

Presentation is a content-agnostic structural preference, not a subject label. It is a nullable single selection:

- `数据复盘`
- `主题综合`
- `专业评估`
- `调研简报`
- `其他`

No selection means the Planner recommends the presentation family. Supporting copy says this explicitly. Selecting `其他` opens a dedicated text field for the desired presentation.

If the user selects a standard family, it becomes a hard planner constraint. If the user supplies `其他`, it becomes a high-priority presentation instruction; the Planner maps it to a compatible official template or returns a clear blocker rather than silently ignoring it.

### Optional supplemental text

A separate free-text field accepts focus questions, comparison targets, background, intended use, or other report requirements. It is not merged with the custom-presentation field.

### Plan generation responsibilities

After input confirmation, the existing bounded Planner still owns:

- Selecting a compatible official template and analysis method.
- Comparing the confirmed Assets' capabilities and fields.
- Choosing attention questions and bounded public research.
- Deciding chart, web, and illustration policies within official template constraints.
- Producing up to three options with exactly one recommendation.

When the user fixed a presentation family, plan options do not ask for or silently change that family again. The alternatives instead compare analysis angle, emphasis, supporting evidence, chart use, and public research. When presentation is unset, the recommendation explains the selected family.

### Root-cause correction

The current `period_summary` adapter defaults vague `最近` to seven days and builds candidate/default scope separately from the mobile override. The new intake contract carries unresolved dimensions explicitly. It does not create a report scope until required filters are confirmed, and there is a single authoritative selected-Asset set shared by the candidate response, UI, saved draft, and Planner request.

## State and API direction

The report scope draft gains an input-preference object rather than overloading `adapter_kind`:

```json
{
  "asset_scope": {
    "skill_ids": [],
    "references": [],
    "time_range": null,
    "selection_provenance": {}
  },
  "presentation_preference": {
    "family": null,
    "custom_text": ""
  },
  "additional_focus": ""
}
```

Exact wire naming may follow existing Pydantic/Dart conventions, but the three concepts remain separate. Existing in-progress runs must continue to decode with empty/default preference fields.

## Error and edge behavior

- An empty Asset result explains the active filters and keeps the manual picker available.
- If an Asset is deleted between confirmation and plan preparation, preparation returns a stale-scope conflict and reloads the input step.
- If a custom Skill changes while its edit page is open, optimistic revision checking prevents overwriting the newer schema.
- Network failure during destructive Skill deletion leaves the local Skill visible until the server confirms success.
- Dither initialization failure falls back to the standard page background without affecting foreground layout.
- Reka output cancellation before physics handoff removes the transient ball; cancellation after handoff is owned by the physics field.

## Verification strategy

Implementation follows test-first slices.

### Service tests

- Custom-only Skill update and delete authorization.
- Schema compatibility: add field, relabel, reorder/hide, reject key/type mutation.
- Deletion impact count and cascade deletion.
- Report intake cases for type-only, type-plus-time, specific Asset, and no clue.
- All matching Assets selected after time confirmation.
- Manual additions and explicit removals survive automatic-scope recomputation.
- Nullable/standard/custom presentation preference reaches Planner request.
- Fixed presentation family constrains returned options.

### Flutter tests

- Custom Skill actions are discoverable; built-ins do not expose them.
- Edit form locks historical keys/types and keeps all fields optional.
- Delete dialog shows the Asset count and requires explicit confirmation.
- Report input renders only missing filters for each intent shape.
- Asset groups, manual picker, nullable presentation pills, `其他`, and supplemental text remain independent.
- Global shell owns one Dither surface; dense schedule/list regions use isolation surfaces.
- Asset output paints a final Asset ball, never an Asset Seed, and hands it to physics once.

### Real-device QA

- Light and dark mode calendar readability at normal and large text sizes.
- Continuous Dither behind top Nav and bottom Dock without seams.
- Scroll dense lists and verify row backgrounds do not drift.
- Observe Reka output at full speed and reduced motion; verify no red edge flash.
- Create a tennis Skill, add location later, create a new record, verify old records remain valid, then delete the Skill and its records.
- Run `总结最近的消费`, choose 7 and 30 days, and verify every matching expense is selected before plan generation.

## Rollout

Ship behind the existing Theme V2 surface. Schema-update and delete endpoints remain server-authoritative. Add structured diagnostics for rejected schema changes, Skill deletion counts, report auto/manual selection counts, and Reka physics handoff. Do not migrate or rewrite historical Asset payloads.
