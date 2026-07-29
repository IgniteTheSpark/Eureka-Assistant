# Theme V2 Calendar Manual Record Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify Calendar schedule headers, make Flash a count-only entry, add Day Detail manual recording and empty states, and provide a shared Skill Picker bottom sheet.

**Architecture:** Existing Calendar frames remain the product truth. Repeated Light/Dark states receive the same node structure and interaction metadata. Flow empty days and Day Detail invoke one conceptual `ManualRecordSkillPicker` with a date context; the picker navigates to the selected Skill’s existing Asset Edit surface and never creates an Asset itself.

**Tech Stack:** Pencil `.pen` schema 2.14, existing Theme V2 variables, Lucide action icons, existing Skill icon artwork.

## Global Constraints

- Do not add icons to Schedule section titles; icons belong to actual Asset children.
- Remove instructional hint copy such as “今天记一笔” and “再次点击日期进入日详情”.
- Day Detail empty state is based on `asset_count = 0`, independent of `flash_count`.
- Flash entry is count-only and opens the corresponding Flash Session.
- Picker contains system and user-created Skills and scrolls internally.
- Light and Dark use the same structure and interaction contract.
- Modified root frames use `placeholder: true` during Pencil edits and restore it immediately afterward.

---

### Task 1: Normalize Schedule headers

**Files:**
- Modify: `redesignureka.pen`

**Interfaces:**
- Consumes: existing All Day and Unscheduled trays in all Schedule states.
- Produces: identical `全天日程 · N` and `未排期代办 · N` header structures.

- [x] Update `x6WzO`, `OkwHU` and corresponding trays in default, Todo Expanded and Inline Draft Light/Dark roots.
- [x] Keep existing Asset children and maximum-three-visible Todo behavior.
- [x] Remove `Grid Hint` and other instructional hint nodes.
- [x] Verify Light/Dark header bounds and copy match.

### Task 2: Add icons to Progressive Day Summary Assets

**Files:**
- Modify: `redesignureka.pen`

**Interfaces:**
- Consumes: `ZfqSF`, `UcZjE`.
- Produces: dense Asset rows with the same Skill imagery used by Flow and Day Detail.

- [x] Add Skill artwork to every morning, afternoon and evening record.
- [x] Shift record copy to preserve alignment and avoid overlaps.
- [x] Keep band labels and time markers icon-free.
- [x] Verify both themes visually.

### Task 3: Update populated Day Detail

**Files:**
- Modify: `redesignureka.pen`

**Interfaces:**
- Consumes: `K1Z2iN`, `fHRmV`.
- Produces: count-only Flash entry and explicit manual-record action.

- [x] Replace Flash hint with a numeric count.
- [x] Set interaction context to `open_flash_session` and explicitly disable create behavior.
- [x] Add `＋ 手动记录` beside the Schedule action.
- [x] Set action metadata with current day `effective_date`.
- [x] Remove remaining hints from Day Detail.
- [x] Verify content and Dock remain unobstructed.

### Task 4: Create Day Detail empty states

**Files:**
- Modify: `redesignureka.pen`

**Interfaces:**
- Consumes: populated Day Detail header/action structure from Task 3.
- Produces: Light/Dark empty Day Detail frames where Flash count may remain non-zero.

- [x] Copy the populated Light/Dark Day Detail roots into empty-state roots.
- [x] Preserve date, Schedule, manual record, Flash count and Dock.
- [x] Remove Asset bands and axis.
- [x] Add `今天还没有记录` and one `手动记录` primary action.
- [x] Add root context `empty_when: asset_count == 0`.
- [x] Verify a fixture with `asset_count = 0, flash_count = 5`.

### Task 5: Create Manual Record Skill Picker

**Files:**
- Modify: `redesignureka.pen`

**Interfaces:**
- Consumes: `effective_date`, system Skills and user Skills.
- Produces: selected `user_skill_id` and navigation to the Skill-specific Asset Edit page.

- [x] Create Light and Dark 411px overlay states using existing Calendar Day Detail as the dimmed background.
- [x] Add bottom sheet title, close action and two-column Skill tiles.
- [x] Include representative system and custom Skills and an internal-scroll indicator.
- [x] Add metadata/context documenting selection and navigation behavior.
- [x] Verify sheet respects bottom safe area and does not open the keyboard.

### Task 6: Connect Flow empty days

**Files:**
- Modify: `redesignureka.pen`
- Modify: `theme-v2-coding-handoff.md`

**Interfaces:**
- Consumes: existing empty-day confirmation and Manual Record Skill Picker.
- Produces: shared manual-record flow with the clicked date.

- [x] Rename empty-day confirmation CTA to `手动记录`.
- [x] Remove repeated-click hints.
- [x] Add interaction context passing the clicked calendar date to the picker.
- [x] Document count-only Flash, empty Day Detail and picker routing in the coding handoff.
- [x] Run final structural and screenshot verification across all modified Light/Dark roots.
