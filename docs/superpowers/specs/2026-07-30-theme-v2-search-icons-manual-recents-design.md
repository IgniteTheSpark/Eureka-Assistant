# Theme V2 Search Cleanup, Skill Emoji, and Manual Recents

Date: 2026-07-30  
Status: Approved product direction; implementation pending  
Parent contracts:

- `spec/design/theme-v2-coding-handoff.md`
- `spec/design/theme-v2-calendar-handoff.md`
- `spec/design/theme-v2-library-assets-handoff.md`
- `docs/superpowers/specs/2026-07-29-theme-v2-unified-asset-contract-design.md`

This is an incremental Theme V2 contract. It records decisions that must be
merged into the next consolidated Theme V2 handoff instead of being lost in
implementation history.

## 1. Scope

This change has exactly three product outcomes:

1. Remove the non-functional search field from Theme V2 Session history.
2. Make one Skill emoji the identity of every Asset produced by that Skill.
3. Replace Calendar manual record picker's current `常用` shortcut with a
   persisted `最近` section containing at most four recently manually created
   Skills.

Explicitly out of scope:

- report / summary containers or generation surfaces;
- external tasks and the `external_ref` container;
- global Asset full-text search;
- Session history search;
- an SVG emoji asset library or `emoji_asset_key` migration;
- changes to Goal, Today, device, notification, or agent task behavior.

Reports/summaries and external tasks remain hidden in Theme V2. They will be
handled by a dedicated future requirement.

## 2. Search Contract

### 2.1 Keep

The following existing search behavior remains:

- Library container directory search is a local case-insensitive substring
  filter over container display label and machine id.
- Event attendee/contact search is a server query over contact name, company,
  title, phone, and email with the existing debounce and result limit.

These are distinct domain searches. Neither becomes a global search service.

### 2.2 Remove

Theme V2 Session history currently renders a read-only field labelled `搜索`.
It has no query state, filtering, or backend behavior. Remove the field and
close the vertical gap it occupied.

Do not replace it with a disabled state, future-feature hint, or search icon.
Session history search can return only after it receives a dedicated product
contract.

### 2.3 No new Asset search

Asset container pages continue without search. The Library directory search
continues to search containers, not Assets or Asset field content.

## 3. Canonical Skill Emoji Contract

### 3.1 Identity rule

An Asset does not own an independently assigned icon. Its visual identity is
the emoji of its producing Skill:

```text
Skill.render_spec.icon
        ↓
all Assets produced by that Skill
        ↓
Calendar / Library / Asset list / Asset detail / Session card
```

For user-created Skills, Design Agent proposes the initial emoji. The user may
change it in Skill Builder/configuration. The saved `render_spec.icon` is then
authoritative on every surface.

The same rule applies regardless of whether an Asset was created manually,
from Flash, or from another Session.

### 3.2 System identities

First-class entities use stable system Skill identities:

| Identity | Emoji |
|---|---|
| Event | `📅` |
| Contact | `👤` |
| Todo | `📋` |
| Notes | `✍️` |

Where a persisted system Skill render spec exists, its non-empty configured
emoji is authoritative. The table is the stable fallback when that spec is not
available. A missing or empty custom Skill emoji uses `•`; no LLM call happens
during rendering.

Flash is not an Asset Skill. It continues to use the separate global lightning
/ zap identity and never inherits a Skill emoji.

### 3.3 Shared resolver

Production UI must use one resolver/model for Skill visual identity. The
resolver accepts:

- Skill machine name;
- the current `/api/skills` registry;
- first-class entity kind when no UserSkill exists.

It returns at least:

- display name;
- emoji;
- accent color.

Calendar dense rows may change emoji size and surrounding container treatment,
but may not replace the emoji with a generic Material icon. Asset lists and
details may use different card variants, but the emoji string must remain
identical.

The following independent mappings must be removed:

- Calendar Flow/Month type-to-Material-icon mapping;
- Event `▣` detail/list glyph;
- Contact `♙` detail/list glyph;
- list-header fallbacks that disagree with record/detail identity.

The canonical asset-detail envelope returns the same resolved emoji used by the
Skill registry. Skill emoji edits invalidate/reload affected Library, Calendar,
list, and detail data through the existing data revision mechanism.

### 3.4 Deferred emoji asset system

The broader handoff specifies Unicode normalization, packaged emoji SVGs, and a
stable `emoji_asset_key`. Product direction for this increment is to use the
Design Agent/user-selected emoji directly. Therefore this change unifies emoji
identity and data flow but does not implement the SVG asset pipeline.

This deferral must remain visible in the next consolidated handoff.

## 4. Manual Record `最近`

### 4.1 Presentation

Rename the manual record sheet section from `常用` to `最近`.

Rules:

- one non-wrapping row;
- maximum four Skill tiles;
- de-duplicated by Skill identity;
- ordered by most recent successful manual creation, newest first;
- no product-order filler;
- fewer than four histories display only the histories that exist;
- zero histories display `暂无`;
- `全部 Skills` remains below and keeps current product ordering and scrolling.

`最近` and `全部 Skills` may contain the same Skill. The former is a shortcut;
the latter is the complete catalog.

### 4.2 What counts

A Skill enters or moves to the front of `最近` only after a manually created
entity has been successfully persisted.

Counted:

- a custom/system Asset successfully created through the manual Asset API;
- a first-class Event successfully created manually;
- a first-class Contact successfully created manually;
- successful manual creation from Calendar or another product-owned manual
  creation entry point.

Not counted:

- opening the picker;
- tapping a Skill;
- opening an editor;
- cancelling or navigating back;
- failed validation or failed persistence;
- editing an existing entity;
- Flash/Session/agent-created entities;
- external sync/import entities.

### 4.3 Persistence and query

Recent manual Skills are backend-owned and user-scoped. They must remain
consistent across devices and logins; local SharedPreferences are not the
source of truth.

The backend derives each Skill's latest successful manual creation timestamp
from persisted entities:

- Asset: its producing Skill plus manual provenance;
- Event: the `event` identity plus manual provenance;
- Contact: the `contact` identity plus manual provenance.

For each Skill identity, take the maximum qualifying creation timestamp. Sort
those maxima descending and return at most four machine names. The client joins
those names against the currently eligible manual Skill catalog.

If a recent Skill is now disabled, deprecated, deleted, or otherwise not
eligible for manual creation, omit it without filling the gap.

Deleting the only qualifying manually created entity for a Skill removes that
Skill from the derived recent list. This follows the chosen derived-data model;
there is no separate durable usage log in this increment.

### 4.4 API and failure behavior

Expose a small authenticated, user-scoped read endpoint for recent manual Skill
identities. It returns ordered machine names only; display name, emoji, schema,
and render configuration still come from `/api/skills` and first-class system
definitions.

Picker loading combines:

1. the complete eligible Skill catalog;
2. recent manual Skill identities.

The complete catalog remains the required request. If it fails, keep the
existing sheet-level load error and retry.

If only the recent request fails:

- keep `全部 Skills` usable;
- render `最近暂不可用`, not `暂无`;
- retry the recent request the next time the sheet opens.

## 5. Data and Compatibility

There are no production users and no requirement to preserve old test data.
Implementation may reset/reseed the dedicated verification account.

This does not authorize deleting unrelated developer data or changing other
accounts. Automated/manual verification uses the existing disposable
`test@1.com` account.

No compatibility shim may preserve the removed Calendar/list/detail icon
mappings. Once the shared resolver lands, those mappings are deleted.

## 6. Verification Contract

Automated coverage must prove:

- Session history has no search field or reserved search gap.
- Library and attendee search behavior is unchanged.
- the same custom Skill emoji appears in Calendar Flow, Calendar Month/Day,
  Library recent items, Asset list rows, and Asset detail;
- Event and Contact use `📅` and `👤` consistently in list and detail surfaces;
- changing a Skill emoji changes subsequent resolved presentation everywhere;
- Flash still uses zap/lightning rather than a Skill emoji;
- recent manual Skills are user-scoped, de-duplicated, and capped at four;
- cancelled, failed, edited, Flash-created, and externally synced entities do
  not enter `最近`;
- zero recent Skills renders `暂无`;
- a partial recent-request failure preserves the usable full Skill catalog.

Android device verification must cover:

1. create five different Skill/entity types manually and confirm only the four
   newest unique Skills appear in `最近`;
2. create another record using an older Skill and confirm it moves to the front;
3. cancel a manual editor and confirm ordering does not change;
4. change a custom Skill emoji and compare the same Asset in Calendar, its
   container list, and canonical detail;
5. verify Event, Contact, and Flash identities.

## 7. Documentation Integration Note

The next Theme V2 documentation consolidation must merge:

- Section 2 into the Library and Session search contracts;
- Section 3 into the Asset Emoji System;
- Section 4 into Calendar Manual Record Skill Picker;
- the explicit report/summary and external-task exclusions into the Theme V2
  scope matrix.

After that merge, this incremental file may remain as implementation history,
but the consolidated handoff becomes the product truth.
