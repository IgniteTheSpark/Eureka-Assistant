# Theme V2 Report Readability, Presentation, and Actions Design

**Status:** Approved for implementation

**Date:** 2026-08-04

**Scope:** Theme V2 Report content normalization, deterministic presentation, report-to-Todo actions, existing-report repair, and mobile acceptance

## 1. Decision summary

Theme V2 Report will be completed as one independent vertical slice. The service
will keep its existing Planner, pipeline, report, share, and media architecture,
but it will replace the generic Markdown presentation path with a trusted
deterministic renderer ported from the proven legacy design language.

The delivery includes:

- raw internal citation tags never appearing in user-visible content;
- normal external source presentation at the end of a report;
- four semantic report families with two deterministic visual variants each;
- a whitelist renderer for trusted report blocks, charts, and one illustration;
- typed suggested actions and an idempotent Report-to-Todo API;
- a native mobile action tray with Report provenance back-navigation;
- deterministic repair of the two existing Theme V2 reports without another
  model call;
- automated fixture coverage plus one real-model, real-device acceptance flow.

Theme V2 owns the copied implementation. It does not import, call, or depend on
the legacy backend at runtime.

## 2. Diagnosed gaps

### 2.1 Evidence leakage

The current generator prompt requires exact markers such as
`[evidence:<asset-id>]` and `[source:<url>]`. Validation checks for the presence
of a marker, but the Markdown renderer neither resolves nor removes it. The raw
markers are therefore persisted in both `Report.content_md` and `Report.html`.

The live Theme V2 database contains two reports and both contain raw evidence
markers in stored Markdown and stored HTML. There are no existing share
snapshots, so the historical repair can update the Report rows without mutating
published snapshots.

### 2.2 Generic presentation

Theme V2 currently renders every report through one generic serif stylesheet.
`base_family`, `surface`, `palette`, and `seed` do not produce meaningful visual
differences. The older backend already has a proven deterministic block kit,
six palettes, and eight presentation surfaces, but Theme V2 does not use them.

### 2.3 Missing action loop

The older product implemented the complete Report-to-Todo loop:

1. report content declared actionable next steps;
2. the pipeline extracted them;
3. the viewer displayed a native action tray;
4. the server created a Todo idempotently;
5. the Todo retained Report provenance.

Theme V2 currently has none of those backend contracts. Its eight official
template skills do not request typed actions, the Report schema does not persist
them, `/api/reports/{id}/actions` does not exist, and Theme V2 callers explicitly
disable the legacy viewer action enhancement.

## 3. Product boundaries

### 3.1 Internal evidence

Internal Asset evidence is an audit and validation concern. It is never shown
as a raw identifier, label, footnote, chip, or appendix in the report body.

The system retains internal traceability through:

- `ReportSpec.source_asset_ids`;
- a paragraph-level citation manifest produced during normalization;
- structured logs and generation context.

### 3.2 External sources

External web sources remain user-readable because they help the user evaluate
research. They appear once, at the end of the report, under `参考来源`, using:

- source title;
- site/domain;
- clickable `https` URL;
- accessed date when available.

No raw `[source:...]` marker appears inline. Only sources actually cited by the
generator are included in the visible source list.

### 3.3 Suggested actions

Suggested actions are optional. A report must not invent an action simply to
fill a component. When present:

- there are at most five;
- each title is concrete, directly actionable, and at most 200 characters;
- generic advice such as “多记录” or “继续努力” is rejected by the template
  instruction;
- `due_at` is optional and may only copy an explicit date/time from evidence or
  the execution context;
- missing `due_at` remains unscheduled rather than receiving an invented date;
- the first release creates Todos only, not Events.

## 4. Content and citation normalization

### 4.1 Generator contract

`GeneratorResult` gains a typed `suggested_actions` list:

```python
class GeneratedSuggestedAction(ProviderModel):
    title: str = Field(min_length=1, max_length=200)
    due_at: datetime | None = None

class GeneratorResult(ProviderModel):
    content_md: str
    chart_directives: list[ChartDirective]
    illustration_prompt: str | None
    suggested_actions: list[GeneratedSuggestedAction] = Field(
        default_factory=list,
        max_length=5,
    )
    share_card_spec: ShareCardSpec
    usage: GeneratorUsage
```

All eight official Template Skills specify when an action is warranted and when
the list must remain empty. `content_md` is presentation prose; actions are
typed application data rather than button-like Markdown authored by the model.

The normalizer still accepts legacy `:::actions` blocks. It extracts them when
typed actions are absent and removes the directive from display Markdown. The
renderer adds the trusted action component from the normalized typed list, so
old and new content cannot produce duplicate action sections.

### 4.2 Citation validation

The validator computes an exact allowlist from resolved Asset IDs and accepted
external source URLs. It rejects:

- an unknown evidence ID;
- an unknown or non-HTTPS source URL;
- malformed citation markers;
- a numeric claim that is not present in the allowed evidence values;
- a numeric action title that is not grounded in allowed values;
- an action due date that is not copied from an allowed evidence/context date.

The existing one-repair model retry remains bounded to one retry.

### 4.3 Normalized persisted content

After validation and before HTML rendering, a pure normalizer returns:

```python
NormalizedReportContent(
    content_md: str,
    citations: list[ReportCitation],
    suggested_actions: list[ReportSuggestedAction],
)
```

For every paragraph containing citation markers, the normalizer records a
stable SHA-256 paragraph hash and its internal Asset IDs or external URLs. It
then removes the markers and normalizes the surrounding whitespace. The clean
Markdown is persisted as `Report.content_md`; the citation manifest and typed
actions are persisted in `Report.spec_json`.

This makes both `content_md` and `html` safe for private API consumers and share
snapshots while retaining machine traceability.

## 5. Deterministic presentation engine

### 5.1 Package boundary

Theme V2 receives a focused package:

```text
theme_v2_service/app/domains/reports/presentation/
├── __init__.py
├── blocks.py
├── catalog.py
├── renderer.py
└── styles.py
```

- `blocks.py` parses supported directives into typed blocks and escapes all
  untrusted text.
- `catalog.py` maps `base_family + seed` to a bounded variant.
- `styles.py` owns the copied Theme V2 CSS tokens and eight surface styles.
- `renderer.py` assembles the masthead, safe blocks, deterministic chart SVGs,
  optional illustration, sources, actions, and final HTML document.

The existing `rendering.py` remains the pipeline-facing facade and illustration
orchestration module. It delegates final presentation to this package.

### 5.2 Family catalog

The proven legacy designs are ported and mapped to Theme V2 semantics:

| Base family | Variant A | Variant B |
|---|---|---|
| `data_trend` | `surface-dashboard / pal-dashboard` | `surface-neon / pal-neon` |
| `theme_synthesis` | `surface-editorial / pal-ink` | `surface-note / pal-warm` |
| `professional_evaluation` | `surface-deck / pal-minimal` | `surface-forest2 / pal-forest` |
| `briefing_research` | `surface-mag / pal-warm` | `surface-wdash / pal-dashboard` |

The stored `seed` selects A or B deterministically. Identical inputs produce
identical HTML. Unknown families fall back to the first `briefing_research`
variant and emit a structured warning.

### 5.3 Trusted block whitelist

The renderer supports exactly:

- ordinary headings, paragraphs, lists, quotes, and tables;
- `kpi`;
- `timeline`;
- `rank`;
- `callout` with `insight`, `warn`, or `success` tone;
- `quote`;
- `compare`;
- application-owned `actions`;
- deterministic chart placeholders;
- one application-owned illustration;
- one application-owned external sources section.

Unknown directives become escaped prose. Raw HTML, scripts, inline handlers,
iframes, style tags, arbitrary classes, data URLs, and external image URLs are
not accepted.

### 5.4 Illustration and charts

Existing chart validation and generated SVG remain authoritative. The model
cannot supply executable SVG or HTML. The presentation engine inserts only
known chart IDs.

Seedream remains optional and limited to one image. When present, the trusted
renderer places it after the lead and before the first analytical section.
Failure omits the entire figure without empty spacing and never fails the report.

### 5.5 Color behavior

The HTML declares its actual color scheme and owns its complete palette. The
Flutter viewer no longer replaces report design tokens with one forced dark
palette. Instead, Theme V2 passes the stored palette to the viewer so its AppBar
and native action tray choose readable light or dark chrome.

## 6. Report-to-Todo contract

### 6.1 Persisted actions

`ReportSpec` gains:

```python
citations: list[ReportCitation] = []
suggested_actions: list[ReportSuggestedAction] = []
presentation_version: str = "report_html_v2"
```

Each suggested action receives a deterministic ID derived from normalized
title, normalized due date, and list position. The ID remains stable across
HTML rerendering.

### 6.2 Todo provenance and idempotency

The Theme V2 `assets` table gains nullable provenance fields:

```text
source_report_id
source_report_action_id
```

The unique key `(user_id, source_report_id, source_report_action_id)` guarantees
that retries, double taps, and concurrent requests cannot create duplicates.
`source_report_id` is an owner-scoped foreign key with `ON DELETE SET NULL`.

The Todo payload remains canonical:

```json
{
  "title": "准备三条客户访谈问题",
  "content": "准备三条客户访谈问题",
  "due_date": null,
  "status": "pending"
}
```

The Report title is returned as presentation metadata rather than inserted into
editable Todo fields.

### 6.3 API

```text
GET  /api/reports/{report_id}/actions
POST /api/reports/{report_id}/actions/{action_id}
```

The GET response is:

```json
{
  "actions": [
    {
      "id": "action-id",
      "title": "准备三条客户访谈问题",
      "due_at": null,
      "created": false,
      "todo_asset_id": null
    }
  ]
}
```

POST accepts no arbitrary title. It creates only an action already stored on
the owned Report. An existing Todo returns `created: false` and the same Asset
ID. Missing reports and cross-owner access return 404; unknown action IDs return
404; a missing baseline Todo skill is repaired with the existing baseline-skill
provisioning path.

### 6.4 Mobile action tray

The Report viewer separates three capabilities that are currently coupled:

- legacy palette rerender;
- Theme V2 report actions;
- Theme V2 palette-aware chrome.

Theme V2 enables actions and palette-aware chrome while leaving legacy rerender
disabled. The native tray shows:

- `接下来` header;
- one row per action, maximum five;
- a minimum 48 logical-pixel touch target;
- `加入待办`, progress, and `已加入` states;
- `全部加入待办` only when at least two actions remain;
- a bounded scroll area that never obscures the report;
- a concise failure toast without discarding other completed rows.

After creation, normal data revision refresh makes the Todo visible in Today,
Calendar, and the Todo container.

### 6.5 Provenance navigation

`AssetRead` exposes Report provenance separately from editable payload. The
Theme V2 Asset detail source model gains `report`. A generated Todo displays:

```text
来自报告《报告标题》  >
```

Tapping it loads `/api/reports/{source_report_id}` and opens the same Theme V2
Report viewer. If the source Report no longer exists, the row remains visible
but non-navigable.

## 7. Existing-report repair

An idempotent maintenance command scans Theme V2 reports with either:

- raw citation markers in `content_md` or `html`; or
- `presentation_version != report_html_v2`.

For each row it:

1. validates citation markers against the stored `source_asset_ids` and
   `external_sources`;
2. strips allowed markers and records the manifest;
3. extracts any legacy `:::actions` block;
4. rerenders using the stored family and seed;
5. updates clean Markdown, HTML, surface, palette, citations, actions, and
   presentation version in one short transaction.

It does not call Planner, Generator, Web Search, or Seedream. It does not alter
the report title, evidence selection, share-card copy, or generation-run state.
Malformed or unknown markers cause that row to be skipped with a diagnostic
instead of silently deleting content.

The current database has two eligible reports and zero share snapshots. Future
share creation always snapshots already-clean content.

## 8. Error behavior

- Invalid generator citation: one bounded repair attempt, then the existing
  permanent-provider failure path.
- Empty actions: report succeeds with no action tray.
- Invalid action due date: generator output is rejected; no invented fallback.
- Illustration failure: report succeeds without a figure.
- Unknown presentation family: deterministic briefing fallback and warning.
- Todo creation race: unique key winner is returned; no duplicate.
- Todo skill missing: provision baseline skills and retry in the same request.
- Source Report deleted: Todo remains valid; provenance row becomes static.
- Historical row with unsafe marker: skip and report; do not damage stored data.

## 9. Verification strategy

### 9.1 Automated backend

- citation allowlist and unknown-marker rejection;
- clean persisted Markdown and HTML;
- visible external source list without raw markers;
- all eight presentation variants from deterministic fixtures;
- block whitelist and raw HTML/script rejection;
- identical inputs produce identical HTML;
- typed and legacy action normalization;
- at-most-five action constraint and grounded due dates;
- owner scoping, idempotency, and concurrent Todo creation;
- Todo provenance serialization;
- share HTML contains clean content;
- maintenance repair is idempotent and performs no provider calls.

### 9.2 Automated Flutter

- all Theme V2 report entry points enable actions but not legacy rerender;
- light and dark report palettes select readable viewer chrome;
- action tray loading, empty, pending, busy, success, partial failure, and
  add-all states;
- minimum touch targets;
- created Todo triggers data revision;
- Todo detail displays Report provenance and opens the correct report;
- deleted Report provenance remains non-crashing and non-navigable.

### 9.3 Acceptance fixtures

Create a deterministic fixture gallery with one content fixture rendered under
all eight variants. These fixtures are the normal visual-regression path and do
not call an external model or image provider.

### 9.4 Real workflow

Run one final real workflow on the connected Android device:

1. generate an actionable report from owned Theme V2 records;
2. confirm no raw evidence/source tags are visible;
3. confirm the selected family and Seedream illustration render correctly;
4. add one action, then add the remaining actions;
5. reopen the report and confirm idempotent `已加入` state;
6. open the created Todo and navigate back to the source Report;
7. create/open a share and confirm readable content and external sources.

This single real workflow replaces repeated multi-hour manual checks while the
deterministic gallery covers the eight visual variants.

## 10. Non-goals

This delivery does not add:

- a user-facing style picker or arbitrary palette editing;
- runtime calls to the legacy backend;
- Events created from report actions;
- inline internal evidence chips or Asset footnotes;
- multiple illustrations;
- OSS/S3 provisioning changes;
- a new Report database architecture;
- re-generation of historical report prose.
