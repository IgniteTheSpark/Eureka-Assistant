# Library Asset Sticky Preview + Skill Stepper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Standardize Asset Edit previews as sticky top regions and replace the custom Skill creation flow with a three-step Describe → Fields → Card Stepper.

**Architecture:** Update Light/Dark screen pairs together inside `redesignureka.pen`. Preserve the existing Theme V2 global navigation and fixed card visual language; Step 3 writes a constrained display configuration shared by the creation flow and the container settings entry.

**Tech Stack:** Pencil `.pen` document, Pencil MCP `Get/Update/Insert/Copy/Move/Delete`, Markdown design specification.

## Global Constraints

- Design file: `/Users/admin/workwork/eureka-staff/Eureka-Assistant/spec/design/redesignureka.pen`.
- Specification: `docs/superpowers/specs/2026-07-29-library-assets-v2-design.md`.
- Reference viewport: `411 × 960`.
- Light and Dark must use identical geometry and behavior.
- Do not modify the deferred emoji/icon mapping system.
- Do not add breadcrumbs, selection underlines, or free-form card layout controls.
- Every modified root frame must be marked `placeholder: true` until its edits are complete.

---

### Task 1: Standardize Sticky Asset Edit Previews

**Files:**
- Modify: `redesignureka.pen`

**Interfaces:**
- Consumes: Theme V2 global top navigation and existing Todo/Tennis preview cards.
- Produces: a consistent sticky preview contract for `y49fg`, `S5GGTj`, `tAoSU`, and `czuBh`.

- [x] **Step 1: Read all four edit-screen trees and capture preview/form/action IDs.**
- [x] **Step 2: Mark each root as a placeholder.**
- [x] **Step 3: Move the preview label and card immediately below the global top navigation.**
- [x] **Step 4: Shift the editable form below the sticky preview without changing field order or values.**
- [x] **Step 5: Add metadata identifying the preview region as sticky and the form as the vertical scroll region.**
- [x] **Step 6: Reset placeholders, run `ctx.problems`, and screenshot Light/Dark Todo and Tennis Edit screens.**

### Task 2: Build the Three-Step Skill Creation Flow

**Files:**
- Modify: `redesignureka.pen`

**Interfaces:**
- Consumes: existing Wizard `a39tz`/`w9IId`, Preview `nS7NP`/`shMAL`, and existing Goal Stepper visual rhythm.
- Produces: Light/Dark Describe, Fields, and Card screens with a shared three-step progress indicator.

- [x] **Step 1: Convert the existing Wizard pair into Step 1 Describe screens with natural-language input, suggestions, and progress `1 / 3`.**
- [x] **Step 2: Convert the existing Preview pair into Step 2 Fields screens showing field name, type, meaning, required state, and reorder affordance.**
- [x] **Step 3: Create Light/Dark Step 3 Card screens using the fixed card skeleton.**
- [x] **Step 4: Add controls for title field, summary field, up to three supporting fields, supporting-field order, and compact/standard density.**
- [x] **Step 5: Add interaction metadata that Step 2 may change schema while Step 3 may change only card presentation.**
- [x] **Step 6: Verify all six screens structurally and visually.**

### Task 3: Connect Container Settings to Step 3

**Files:**
- Modify: `redesignureka.pen`

**Interfaces:**
- Consumes: Tennis container settings entry `MqMMD` and the Step 3 Card screens from Task 2.
- Produces: a documented direct route from container settings to card-display configuration.

- [x] **Step 1: Rename the upper-right Tune control to identify card-display settings.**
- [x] **Step 2: Add route metadata targeting Skill Builder Step 3 with the existing Skill ID.**
- [x] **Step 3: Add Step 3 metadata declaring that Save propagates to container, Recently Generated, and Calendar Asset cards.**
- [x] **Step 4: Validate both container themes and capture screenshots.**

### Task 4: Final Canvas and Documentation Verification

**Files:**
- Modify: `redesignureka.pen`
- Modify: `docs/superpowers/specs/2026-07-29-library-assets-v2-design.md`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: implementation-ready Library + Assets source frames and updated handoff contract.

- [x] **Step 1: Run `ctx.problems` over every modified root.**
- [x] **Step 2: Confirm no preview remains below form fields.**
- [x] **Step 3: Confirm the Stepper labels and controls match the approved contract.**
- [x] **Step 4: Confirm the container settings route cannot modify fields.**
- [x] **Step 5: Mark the specification status ready for handoff after screenshots pass.**
