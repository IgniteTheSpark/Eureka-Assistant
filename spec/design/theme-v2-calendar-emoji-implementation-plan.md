# Theme V2 Calendar Asset Emoji Implementation Plan

> **For agentic workers:** Execute inline against `redesignureka.pen`; every modified root frame must set `placeholder: true` during edits and restore it afterward.

**Goal:** Unify Calendar Asset imagery around a Skill-owned Emoji asset, replace mathematical day-offset watermarks with natural-language distance, and apply the result to every Calendar state.

**Architecture:** Agent output remains the Skill `emoji`. Production resolves it through a versioned Emoji SVG registry into `emoji_asset_key`; all Calendar surfaces consume the same resolved Asset Emoji renderer. Flash is not an Asset and therefore does not use that mapping, but every Flash surface must use the shared lightning `zap` identity. Goal, device, notification and navigation imagery remain out of scope.

**Design source:** `redesignureka.pen`

**Handoff source:** `theme-v2-coding-handoff.md`

## Global constraints

- Do not render an icon beside a page title or section title.
- Every actual Asset item receives its Skill Emoji.
- Use `16px` Emoji in dense Calendar rows.
- Light and Dark reuse the same Emoji artwork.
- Preserve current item ordering, event duration and overlap semantics.
- Verify Light and Dark screenshots after each Calendar surface is updated.

## Task 1 — Schedule Grid default state

**Roots:** `XbCxS`, `IugNo`

- [x] Remove `mzqUC` and `fXsYZ` from the page title and restore `ixYjG` / `zeRlU` to `x: 18`.
- [x] Remove icons from the All Day and Unscheduled section labels and restore their label alignment.
- [x] Add a Skill Emoji to the `产品发布日` all-day Asset.
- [x] Split each unscheduled Todo preview into independently positioned Emoji + text rows while retaining the maximum-three-visible internal-scroll contract.
- [x] Replace Lucide icons inside every event / Todo block with the matching Skill Emoji.
- [x] Confirm `小型讨论会`、`培训`、`3 个代办` remain three non-overlapping blocks.

## Task 2 — Schedule Grid derived states

**Roots:** `V9LoFM`, `sc1bQ`, `J20Phd`

- [x] Apply the same title and section-label treatment as Task 1.
- [x] Add Skill Emoji to every all-day Asset, unscheduled Todo, scheduled event and expanded Todo.
- [x] Keep the Inline Draft confirmation free of Emoji because it is not yet an Asset; created results use the shared renderer.
- [x] Preserve pushed-grid geometry in Todo Expanded and the 30-minute draft geometry in Inline Draft.

## Task 3 — Day Detail

**Roots:** `K1Z2iN`, `fHRmV`

- [x] Add the matching Skill Emoji to every row in Morning, Afternoon, Evening and Unscheduled bands.
- [x] Keep the time column and dividers aligned across Light and Dark.
- [x] Do not add Emoji to Day title, section labels, Flash Entry, Open Schedule or Dock.

## Task 4 — Sticky Flow and natural-language watermarks

**Roots:** `BeBq4`, `vjW39`, `J3XydT`, `n0Eup4`

- [x] Replace the previously inserted Lucide Asset icons with Skill Emoji artwork representing the versioned Emoji SVG renderer.
- [x] Normalize every Flash representation to the shared lightning `zap`; Flash remains outside the Asset Emoji scope.
- [x] Change future day watermark copy from `+1 DAY` to `1 DAY LATER`.
- [x] Retain `TODAY` for the current day and document past/future week, month and year rules in metadata.
- [x] Preserve sticky date rails, empty-day confirmation and Dock positions.

## Task 5 — Design-system documentation and verification

**Files:** `redesignureka.pen`, `theme-v2-coding-handoff.md`

- [x] Add a Theme V2 Asset Emoji System specimen documenting `16 / 20 / 28 / 40px` sizes, normalized SVG rendering, Light/Dark containers and fallback.
- [x] Add metadata to Calendar roots describing the shared Asset Emoji renderer and natural-language watermark formatter.
- [x] Capture screenshots of Day Detail, Schedule Grid, Todo Expanded, Inline Draft and Sticky Flow in Light/Dark where available.
- [x] Confirm there are no clipped Emoji, title icons, overlapping event blocks or mathematical `+N DAY / -N DAY` watermarks in the Calendar implementation whitelist.
