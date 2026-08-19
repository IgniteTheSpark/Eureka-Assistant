# Report Scope, Full-screen Asset Picker, and Skill Field Configuration

Date: 2026-08-19

## Objective

Correct three connected user flows without redesigning unrelated surfaces:

1. A vague report request such as “总结最近的跳舞情况” must immediately show matching dance assets instead of entering with zero selected assets.
2. Report scope confirmation must let the user understand and edit the exact assets, presentation preference, and additional instructions on one page.
3. Custom Skill fields must be editable through a small, separate field-configuration entry while the existing card-display page remains intact.

This design also converts the Report evidence picker into a full-screen selection surface and makes its asset rows use the same configured card fields as the Asset Library.

## Non-goals

- Do not redesign the Asset Library, Skill detail page, or Skill creation wizard.
- Do not introduce a new global picker abstraction for unrelated flows.
- Do not add field requiredness, field disabling, or user-controlled field ordering.
- Do not alter historical asset payloads when a Skill schema changes.
- Do not run repository-wide audits or full test suites for this scoped change unless the repository `AGENTS.md` exception rules apply and the user confirms them.

## 1. Report demand confirmation

### 1.1 Page purpose

The first Report surface is a complete demand-confirmation page, not the first step of a wizard. It establishes:

- which assets will be used;
- what presentation form the user prefers;
- what additional conditions or context should guide the report.

There is no stepper. The page submits one complete brief to “生成报告方案”.

### 1.2 Page order

1. Original report request, with the existing edit affordance if available.
2. Adaptive clarification cards for missing time and/or asset type.
3. Selected-asset summary grouped by type.
4. Persistent manual asset-selection entry.
5. Optional presentation-form pills, including “其他”.
6. Optional free-text additional information.
7. A bottom action dock containing only “生成报告方案”.

The bottom action dock does not repeat the asset count. The selected-asset section is the single source of truth for scope.

### 1.3 Adaptive clarification rules

Time and asset type are filters used to derive assets; they are not independent Report steps.

| User intent | Clarification shown |
| --- | --- |
| Time and asset type are explicit | No clarification card; show the derived selection directly. |
| Asset type is explicit, time is vague | Show only the time card. |
| Time is explicit, asset type is vague | Show only the asset-type card. |
| Both are vague | Show time first; after confirmation, collapse it and reveal asset type below. |

For vague “最近”, the page starts with “最近 30 天” as the recommended default and immediately previews/selects matching assets from that window. The user can confirm it as-is or switch to:

- 最近 7 天;
- 最近 14 天;
- 最近 30 天;
- 其他, using the existing custom date-range interaction.

Changing the time window refetches candidates and updates the selected-asset summary in place.

After a clarification is confirmed, its card collapses into a compact editable row such as `时间范围  最近 30 天  修改`. It remains on the same page.

### 1.4 Asset-type clarification

When type is ambiguous, show relevant type pills with candidate counts. Choosing a type automatically selects matching assets inside the active time window.

The page does not build a second “more types” selector. “更多类型” opens the same full-screen Report asset picker used by manual selection.

### 1.5 Selection model

The derived selection is:

`matching assets in active time/type filters - manual exclusions + manual additions`

- Changing time or type recomputes the matching set.
- Assets explicitly removed by the user remain excluded during the current Report brief.
- Assets explicitly added through the picker remain included even when they sit outside the automatic filters.
- The server remains authoritative for the candidate set; the client preserves explicit additions and exclusions when merging a refetch.

### 1.6 Selected-asset summary

Do not render a long asset-card list directly on the Report page. Display compact grouped summaries such as:

- `跳舞 × 8`
- `跑步 × 1`

The persistent “手动添加资产” entry appears beside or immediately below this summary.

Clicking `跳舞 × 8` opens the full-screen picker with:

- the “跳舞” type pill active;
- the eight selected dance assets checked;
- all other selections preserved.

Clicking “手动添加资产” opens the same picker with “全部” active.

### 1.7 Presentation and additional information

Presentation-form pills and additional information stay on this same page.

- Presentation selection is optional.
- The pills describe output form, not report subject matter.
- “其他” lets the user provide a custom presentation preference.
- Additional information is a free-text field and is optional.
- If no presentation form is selected, the generated plan may recommend one.

## 2. Full-screen Report asset picker

### 2.1 Container

Replace the 92%-height modal sheet with a true full-screen route. Preserve the existing loader, server-side search, pagination, filter response, initial selection, and returned evidence-reference model.

### 2.2 Main layout

The main picker contains:

1. Close/cancel and page title.
2. Search.
3. Asset-type pills with counts.
4. The asset list.
5. A fixed confirmation bar.

There is no “全部 / 已选” tab on the main interface.

Type pills use a wrapping layout. They may occupy multiple rows and never require horizontal swiping. Only types available in the current picker data are shown.

### 2.3 Asset rows

Custom asset rows reuse the Asset Library’s configured display contract:

- the configured primary field supplies the main line;
- the configured secondary fields supply the second line, in configured order;
- the Skill label is a separate type indicator and never substitutes for missing content;
- a missing, deleted, or empty configured field simply does not render;
- the renderer must never duplicate the Skill label as both lines.

Events, contacts, and other already-supported evidence kinds retain their existing readable representations.

### 2.4 Confirmation bar and selected review

The fixed bottom bar has two independent targets:

- `已选择 9 项 ›`
- `完成`

Clicking the selected count opens an “已选资产” secondary page within the same picker flow. That page:

- displays every selected item using the same card representation;
- groups or filters by type using wrapping pills;
- supports immediate single-item removal;
- returns to the main picker without losing search, type filter, scroll position, or other selections.

Clicking “完成” returns the unique selected evidence-reference set to the Report page.

### 2.5 Entry contexts

The picker accepts an optional initial type filter in addition to the existing selected set:

- manual-add entry: `全部`;
- `跳舞 × 8` entry: `跳舞`;
- `跑步 × 1` entry: `跑步`.

All contexts use the same picker implementation and the same selection state model.

### 2.6 Loading and error behavior

- Preserve the existing search debounce and server pagination.
- Keep current selections visible and intact while another page or filter loads.
- A page-load error shows a scoped retry without discarding selection.
- Empty search/filter results state “没有符合条件的资产” while the confirmation bar remains available if anything is already selected.

## 3. Custom Skill field configuration

### 3.1 Minimal entry change

Keep the existing card-display icon and “卡片展示设置” page with their current interaction. Do not create a Skill management hub or combine two editors.

In the custom Skill asset-list header, add one field-configuration icon immediately beside the existing card-display icon. It has:

- tooltip and accessibility label `字段配置`;
- a single action that opens a separate full-screen field-configuration page.

The card-display page remains unchanged. The new field entry does not appear inside that page.

### 3.2 Field-configuration page

The field page contains only:

- the current schema fields;
- field name, type, and meaning;
- add field;
- edit field;
- delete field;
- a top navigation save action that is active only when there are changes.

It does not contain:

- required/optional controls or labels;
- enable/disable or hide controls;
- drag handles or sorting;
- Skill name, icon, description, or other “basic information”;
- card-display configuration or preview.

Custom capture fields remain optional. A record can still be classified into the Skill even when no configured field value was extracted.

### 3.3 Schema mutation behavior

- Adding, editing, or deleting a field updates only the Skill schema used for future captures.
- Existing asset payloads are never migrated, rewritten, or deleted.
- Deleting a field is allowed even if the card-display configuration references it.
- Any card-display slot that references a deleted or absent field renders nothing.
- Deletion does not prompt for a replacement field and does not block saving.

The existing whole-Skill deletion flow remains available and is not redesigned by this work.

## 4. Data flow

### Report

1. Parse the request into explicit and missing dimensions.
2. Apply the recommended 30-day preview when “最近” is unresolved.
3. Fetch relevant candidate groups and records.
4. Preselect matching records instead of returning an empty automatic selection.
5. Let time/type changes refetch candidates.
6. Merge server candidates with explicit user additions and exclusions.
7. Submit exact selected references, presentation preference, and additional information to plan generation.

### Skill fields

1. Load the current custom Skill schema.
2. Edit a local draft through the field-only page.
3. Save with the existing revision/concurrency contract.
4. Refresh Skill configuration consumers after mutation.
5. Render missing card fields as absent without touching historical assets.

## 5. Focused verification

Follow the repository `AGENTS.md` verification constraints. The expected evidence is focused, not full-suite.

### Backend cases

- “总结最近的跳舞情况” with dance records produces a 30-day preview and non-empty selected dance references.
- Switching among 7/14/30/custom windows returns the correct candidate set.
- Explicit type and explicit time skip unnecessary clarification.
- Ambiguous type returns relevant type options.
- Manual additions and exclusions survive candidate refetches.
- Exact selected references remain authoritative for plan generation.
- Field deletion updates the schema while historical asset payloads remain unchanged.

### Flutter cases

- Report demand confirmation shows time/type cards only when needed.
- Time changes update grouped selected counts.
- Presentation and additional information remain on the same page.
- Group summary and manual-add entries open the same full-screen picker with the correct initial filter.
- Picker type pills wrap and the main screen has no selected tab.
- Clicking `已选择 n 项` opens the selected-review page and removal synchronizes back.
- Custom asset rows use configured primary/secondary fields and never duplicate the Skill label.
- The card-display title icon opens the field-only configuration page.
- Field configuration has no required, disabled, sorting, basic-information, or card-display controls.
- Deleting a display-referenced field succeeds and the missing card slot renders nothing.

Run only these regression cases, directly affected tests, targeted static analysis, and diff checks during implementation. Any broader verification requires the justification and confirmation specified by `AGENTS.md`.
