# Theme V2 Report Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Theme V2 reports readable and visually differentiated, preserve citations without exposing internal evidence tags, and restore the complete idempotent Report-to-Todo workflow with source navigation.

**Architecture:** Keep the current Theme V2 Planner, pipeline, report, share, media, and Asset architecture. Add a pure normalization boundary between validated model output and persistence, port the trusted legacy surface/palette/block renderer into a Theme V2-owned presentation package, store typed actions/citation manifests in `Report.spec_json`, and add two nullable Asset provenance columns plus owner-scoped action APIs. The Flutter viewer consumes those APIs through a small controller and keeps legacy rerender, Theme V2 actions, and palette-aware chrome as separate capabilities.

**Tech Stack:** Python 3.12, FastAPI, Pydantic v2, SQLAlchemy async, Alembic/MySQL 8, Jinja2, MarkdownIt/bleach, pytest/pytest-asyncio, Flutter/Dart, WebView Flutter, Docker Compose, Android ADB.

## Global Constraints

- Implementation source: `docs/superpowers/specs/2026-08-04-theme-v2-report-readability-presentation-actions-design.md`.
- Theme V2 must not import or call `backend.agents.*` at runtime; legacy Report files are copy-only design references.
- Internal Asset evidence never appears in user-visible Markdown, HTML, share content, or mobile chrome.
- External sources appear only as a normal `参考来源` section with title, domain, HTTPS link, and optional access date.
- Four `base_family` values each have exactly two deterministic visual variants; identical input plus seed produces identical HTML.
- The renderer accepts only the approved block whitelist, trusted chart SVGs, owned media URLs, and at most one application-owned illustration.
- Each report has at most five suggested Todo actions; `due_at` is optional and must be copied from evidence/context.
- Report action POST accepts an existing action ID, not arbitrary user text.
- Todo creation is owner-scoped and idempotent under retries, double taps, and concurrent requests.
- Existing reports are repaired without Planner, Generator, Web Search, or Seedream calls.
- Existing unrelated dirty worktree changes must remain untouched; stage and commit only explicitly listed files.
- Do not push or merge this branch unless the user explicitly asks.
- Every production behavior change follows RED → GREEN → refactor; run each stated failing test before implementation.
- Backend integration tests always run through the Compose `test` profile and database `eureka_theme_v2_test`, never the live development database.

---

### Task 1: Normalize citations and typed actions before persistence

**Files:**
- Create: `theme_v2_service/app/domains/reports/normalization.py`
- Modify: `theme_v2_service/app/domains/reports/providers.py`
- Modify: `theme_v2_service/app/domains/reports/schemas.py`
- Modify: `theme_v2_service/app/domains/reports/security.py`
- Test: `theme_v2_service/tests/unit/test_report_normalization.py`
- Test: `theme_v2_service/tests/unit/test_report_generation_security.py`

**Interfaces:**
- Consumes: `GeneratorRequest.execution_plan.resolved_asset_ids`, `GeneratorRequest.external_sources`, validated `GeneratorResult.content_md`, and `GeneratorResult.suggested_actions`.
- Produces: `GeneratedSuggestedAction`, `ReportCitation`, `ReportSuggestedAction`, `NormalizedReportContent`, `normalize_report_content`, `allowed_citation_tags`, and `allowed_action_due_times`.

- [ ] **Step 1: Write failing normalization tests**

Add tests that define the complete display boundary:

```python
def test_normalizer_removes_internal_and_external_tags_but_keeps_manifest():
    normalized = normalize_report_content(
        content_md=(
            "第一段来自记录。[evidence:asset-1]\n\n"
            "外部结论。[source:https://example.com/research]"
        ),
        allowed_asset_ids=["asset-1"],
        external_sources=[
            {
                "title": "Research",
                "url": "https://example.com/research",
                "accessed_at": "2026-08-04T08:00:00Z",
            }
        ],
        suggested_actions=[
            GeneratedSuggestedAction(title="准备访谈问题", due_at=None)
        ],
    )

    assert "[evidence:" not in normalized.content_md
    assert "[source:" not in normalized.content_md
    assert normalized.citations[0].asset_ids == ["asset-1"]
    assert normalized.citations[1].source_urls == [
        "https://example.com/research"
    ]
    assert normalized.suggested_actions[0].id.startswith("action-")
```

Add separate tests for stable action IDs, maximum five actions, legacy
`:::actions` extraction when typed actions are empty, directive removal, typed
action precedence, and unknown/malformed marker rejection.

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test \
  python -m pytest tests/unit/test_report_normalization.py \
  tests/unit/test_report_generation_security.py -q
```

Expected: collection/import failure for `normalization` and
`GeneratedSuggestedAction`, proving the new boundary does not exist.

- [ ] **Step 3: Add the typed contracts**

In `providers.py` add:

```python
class GeneratedSuggestedAction(ProviderModel):
    title: str = Field(min_length=1, max_length=200)
    due_at: datetime | None = None


class GeneratorResult(ProviderModel):
    content_md: str = Field(min_length=1)
    chart_directives: list[ChartDirective] = Field(default_factory=list)
    illustration_prompt: str | None = None
    suggested_actions: list[GeneratedSuggestedAction] = Field(
        default_factory=list,
        max_length=5,
    )
    share_card_spec: ShareCardSpec
    usage: GeneratorUsage = Field(default_factory=GeneratorUsage)
```

In `schemas.py` add strict immutable `ReportCitation` and
`ReportSuggestedAction` models and extend `ReportSpec`:

```python
class ReportCitation(StrictModel):
    paragraph_hash: str
    asset_ids: list[str] = Field(default_factory=list)
    source_urls: list[str] = Field(default_factory=list)


class ReportSuggestedAction(StrictModel):
    id: str
    title: str = Field(min_length=1, max_length=200)
    due_at: datetime | None = None


class ReportSpec(StrictModel):
    # existing fields remain unchanged
    citations: list[ReportCitation] = Field(default_factory=list)
    suggested_actions: list[ReportSuggestedAction] = Field(default_factory=list)
    presentation_version: str = "report_html_v2"
```

- [ ] **Step 4: Implement the pure normalizer**

Implement these exact public types and entry point in `normalization.py`:

```python
@dataclass(frozen=True)
class NormalizedReportContent:
    content_md: str
    citations: list[ReportCitation]
    suggested_actions: list[ReportSuggestedAction]
    used_external_sources: list[dict]


def normalize_report_content(
    *,
    content_md: str,
    allowed_asset_ids: list[str],
    external_sources: list[dict],
    suggested_actions: list[GeneratedSuggestedAction],
) -> NormalizedReportContent
```

Use one compiled citation regex for `evidence|source`, split paragraphs on
blank lines, reject every tag not present in the exact allowlist, hash the clean
paragraph with SHA-256, remove citation markers and adjacent duplicate spaces,
and retain only used external sources. Normalize action titles with collapsed
whitespace and compute `action-<first 20 sha256 hex>` from
`index + "\0" + title + "\0" + normalized due_at`. When typed actions are
empty, parse at most five list items from a legacy `:::actions` block; always
remove legacy action blocks from display Markdown.

- [ ] **Step 5: Strengthen generator validation**

In `security.py`, add the exact public signatures
`allowed_citation_tags(request: GeneratorRequest) -> set[str]` and
`allowed_action_due_times(request: GeneratorRequest) -> set[datetime]`.

Require every citation marker in `content_md` to be in the exact allowlist.
Include action titles in numeric-claim validation. Walk evidence and execution
plan strings for ISO date/time values; normalize timezone-aware values to UTC
and reject an action `due_at` outside that set. Reject non-HTTPS source markers.

- [ ] **Step 6: Run normalization/security tests and verify GREEN**

Run the Step 2 command. Expected: all selected tests pass with no warnings.

- [ ] **Step 7: Commit Task 1**

Stage only the files listed in Task 1 and commit:

```bash
git commit -m "feat(report): normalize citations and actions"
```

---

### Task 2: Make official templates generate useful typed actions

**Files:**
- Modify: `theme_v2_service/app/domains/reports/providers_litellm.py`
- Modify: `theme_v2_service/report-templates/child-growth-review/SKILL.md`
- Modify: `theme_v2_service/report-templates/finance-review/SKILL.md`
- Modify: `theme_v2_service/report-templates/general-period-review/SKILL.md`
- Modify: `theme_v2_service/report-templates/idea-synthesis/SKILL.md`
- Modify: `theme_v2_service/report-templates/learning-review/SKILL.md`
- Modify: `theme_v2_service/report-templates/pre-event-briefing/SKILL.md`
- Modify: `theme_v2_service/report-templates/tennis-monthly-review/SKILL.md`
- Modify: `theme_v2_service/report-templates/work-monthly-review/SKILL.md`
- Test: `theme_v2_service/tests/unit/test_report_generation_security.py`
- Test: `theme_v2_service/tests/unit/test_template_registry.py`

**Interfaces:**
- Consumes: `GeneratorResult.suggested_actions` and the citation/due allowlists from Task 1.
- Produces: a generator prompt that separates clean `content_md` from typed actions and eight official skills with explicit action quality rules.

- [ ] **Step 1: Write failing prompt/template tests**

Assert the serialized generator prompt contains all of:

```python
assert "suggested_actions" in serialized
assert "Do not put citation tags into suggested action titles" in serialized
assert "Use due_at only when" in serialized
assert "Do not emit :::actions" in serialized
```

Load every Template Skill and assert it contains an `## Suggested actions`
section, a maximum of five, and an explicit empty-list rule.

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test \
  python -m pytest tests/unit/test_report_generation_security.py \
  tests/unit/test_template_registry.py -q
```

Expected: failures showing the current prompt and skills do not define typed
action behavior.

- [ ] **Step 3: Update the trusted generator prompt**

Extend the system instruction in `build_generator_messages` with the exact
behavior:

```text
Keep content_md as readable report prose. Do not emit :::actions.
Return zero to five concrete suggested_actions only when the report supports a
grounded next step. Do not put citation tags into suggested action titles.
Use due_at only when the exact date or timestamp appears in supplied evidence
or execution context; otherwise use null. Never invent deadlines.
```

Keep the existing DeepSeek `json_object` response mode, schema injection,
numeric allowlist, citation allowlist, and one bounded repair attempt.

- [ ] **Step 4: Add template-specific action rules**

Append `## Suggested actions` to every official skill. Use these semantic rules:

- child growth: only observation/logging or qualified-care preparation actions;
- finance: only concrete record-derived follow-ups, never investment advice;
- general review: only actions directly supported by a pattern or gap;
- idea synthesis: the smallest experiment for a promising direction;
- learning: the next bounded practice loop;
- pre-event: preparation checklist items grounded in event/research context;
- tennis: the next observable practice focus, never medical advice;
- work: next-period priorities tied to recorded outcomes/risks.

Every section must state `0–5`, ban generic filler, require `due_at = null`
unless an exact time is present, and permit an empty list.

- [ ] **Step 5: Run prompt/template tests and verify GREEN**

Run the Step 2 command. Expected: all selected tests pass.

- [ ] **Step 6: Commit Task 2**

```bash
git commit -m "feat(report): define actionable template output"
```

---

### Task 3: Port the trusted eight-variant presentation engine

**Files:**
- Create: `theme_v2_service/app/domains/reports/presentation/__init__.py`
- Create: `theme_v2_service/app/domains/reports/presentation/blocks.py`
- Create: `theme_v2_service/app/domains/reports/presentation/catalog.py`
- Create: `theme_v2_service/app/domains/reports/presentation/renderer.py`
- Create: `theme_v2_service/app/domains/reports/presentation/styles.py`
- Modify: `theme_v2_service/app/domains/reports/rendering.py`
- Modify: `theme_v2_service/app/templates/report.html.j2`
- Modify: `theme_v2_service/app/static/report-v1.css`
- Test: `theme_v2_service/tests/unit/test_report_presentation.py`
- Test: `theme_v2_service/tests/unit/test_report_rendering.py`

**Interfaces:**
- Consumes: clean Markdown, `base_family`, `seed`, trusted chart SVGs, owned media URL, `used_external_sources`, and `ReportSuggestedAction` values.
- Produces: `PresentationRequest`, `PresentationResult`, `select_variant`, `render_presentation`, and the facade `render_report_presentation`.

- [ ] **Step 1: Write failing catalog and renderer tests**

Create a single rich fixture containing headings, a paragraph, `:::kpi`,
`:::timeline`, `:::rank`, `:::callout{tone=insight}`, `:::quote`, `:::compare`,
a trusted chart marker, one illustration, sources, and actions.

Parametrize the exact catalog:

```python
@pytest.mark.parametrize(
    ("family", "seed", "surface", "palette"),
    [
        ("data_trend", 0, "surface-dashboard", "pal-dashboard"),
        ("data_trend", 1, "surface-neon", "pal-neon"),
        ("theme_synthesis", 0, "surface-editorial", "pal-ink"),
        ("theme_synthesis", 1, "surface-note", "pal-warm"),
        ("professional_evaluation", 0, "surface-deck", "pal-minimal"),
        ("professional_evaluation", 1, "surface-forest2", "pal-forest"),
        ("briefing_research", 0, "surface-mag", "pal-warm"),
        ("briefing_research", 1, "surface-wdash", "pal-dashboard"),
    ],
)
def test_catalog_selects_all_eight_variants(
    family: str,
    seed: int,
    surface: str,
    palette: str,
):
    selected, fallback = select_variant(family, seed)
    assert not fallback
    assert selected.surface == surface
    assert selected.palette == palette
```

Assert raw HTML/scripts/external images are absent, the selected surface and
palette classes are present, actions render once, used sources render once,
unknown directives are escaped, and identical inputs are byte-identical.

- [ ] **Step 2: Run the presentation tests and verify RED**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test \
  python -m pytest tests/unit/test_report_presentation.py \
  tests/unit/test_report_rendering.py -q
```

Expected: import failure for the new presentation package.

- [ ] **Step 3: Implement the deterministic catalog**

In `catalog.py` define:

```python
@dataclass(frozen=True)
class StyleVariant:
    surface: str
    palette: str
    color_scheme: Literal["light", "dark"]


FAMILY_VARIANTS: dict[str, tuple[StyleVariant, StyleVariant]] = {
    "data_trend": (
        StyleVariant("surface-dashboard", "pal-dashboard", "dark"),
        StyleVariant("surface-neon", "pal-neon", "dark"),
    ),
    "theme_synthesis": (
        StyleVariant("surface-editorial", "pal-ink", "dark"),
        StyleVariant("surface-note", "pal-warm", "light"),
    ),
    "professional_evaluation": (
        StyleVariant("surface-deck", "pal-minimal", "light"),
        StyleVariant("surface-forest2", "pal-forest", "dark"),
    ),
    "briefing_research": (
        StyleVariant("surface-mag", "pal-warm", "light"),
        StyleVariant("surface-wdash", "pal-dashboard", "dark"),
    ),
}


def select_variant(base_family: str, seed: int) -> tuple[StyleVariant, bool]:
    variants = FAMILY_VARIANTS.get(base_family)
    if variants is None:
        return FAMILY_VARIANTS["briefing_research"][0], True
    return variants[seed % 2], False
```

Mark `pal-minimal` and `pal-warm` as light; all other listed palettes are dark.

- [ ] **Step 4: Port the trusted block parser and renderer**

Copy the proven escaping and directive parsing behavior from
`backend/agents/report_render.py` and the design markup from
`backend/agents/report_render_designed.py` into `blocks.py`. Do not import those
files. Limit directive dispatch to:

```python
BLOCK_RENDERERS = {
    "kpi": render_kpi,
    "timeline": render_timeline,
    "rank": render_rank,
    "callout": render_callout,
    "quote": render_quote,
    "compare": render_compare,
}
```

Do not parse model-owned actions; `renderer.py` renders typed application
actions after the body. Keep chart replacement restricted to IDs in the trusted
`chart_svgs` map. Keep media replacement restricted to the passed illustration
URL.

- [ ] **Step 5: Port the style system without runtime coupling**

Copy `BASE_CSS` and the eight named `SURFACE_CSS` entries from
`backend/agents/report_styles.py` into `styles.py`. Preserve the semantic token
names and responsive rules, then make these Theme V2-specific edits:

- remove external font network dependencies;
- use bundled/system `Geist`, `Noto Sans SC`, `Noto Serif SC`, and fallbacks;
- enforce a 48px minimum action row height;
- add trusted `.r-sources` styling;
- add light/dark `color-scheme` per selected variant;
- retain reduced-motion behavior;
- remove legacy pet signature runtime and arbitrary script injection.

- [ ] **Step 6: Implement the presentation assembly**

Define in `renderer.py`:

```python
@dataclass(frozen=True)
class PresentationRequest:
    title: str
    content_md: str
    base_family: str
    seed: int
    chart_svgs: dict[str, str]
    illustration_url: str | None
    external_sources: list[dict]
    suggested_actions: list[ReportSuggestedAction]


@dataclass(frozen=True)
class PresentationResult:
    html: str
    surface: str
    palette: str
    color_scheme: Literal["light", "dark"]
    warnings: list[str]
```

Assemble a trusted masthead, parsed body, optional illustration, typed action
section, used source list, and static REKA wordmark footer. Escape every title,
action, source title, domain, accessed date, and URL attribute. Allow source
links only when URL parsing confirms `https`.

- [ ] **Step 7: Keep a compatibility facade**

In `rendering.py` expose a `render_report_presentation` function with the same
keyword inputs as `PresentationRequest` plus `media_urls`, and retain the
existing `render_report_html` keyword signature as a compatibility wrapper:

```python
def render_report_html(
    *,
    title: str,
    content_md: str,
    chart_svgs: dict[str, str],
    media_urls: dict[str, str],
) -> str:
    return render_report_presentation(
        title=title,
        content_md=content_md,
        chart_svgs=chart_svgs,
        media_urls=media_urls,
        base_family="briefing_research",
        seed=0,
        external_sources=[],
        suggested_actions=[],
        illustration_file_id=None,
    ).html
```

Give existing optional parameters safe defaults so old unit/API fallback calls
continue to work. Retire the forced generic CSS path once all calls use the
presentation result, but keep `report-v1.css` only for explicitly versioned
legacy fallback if a stored report lacks Theme V2 presentation metadata.

- [ ] **Step 8: Run presentation/rendering tests and verify GREEN**

Run the Step 2 command. Expected: all selected tests pass.

- [ ] **Step 9: Commit Task 3**

```bash
git commit -m "feat(report): port deterministic presentation engine"
```

---

### Task 4: Wire normalization and presentation through pipeline, persistence, and sharing

**Files:**
- Modify: `theme_v2_service/app/domains/reports/pipeline.py`
- Modify: `theme_v2_service/app/domains/reports/api_reports.py`
- Modify: `theme_v2_service/app/domains/reports/shares.py`
- Modify: `theme_v2_service/app/domains/reports/service.py`
- Test: `theme_v2_service/tests/unit/test_report_pipeline.py`
- Test: `theme_v2_service/tests/integration/test_report_persist.py`
- Test: `theme_v2_service/tests/integration/test_report_shares.py`
- Test: `theme_v2_service/tests/e2e/test_report_generation_flow.py`

**Interfaces:**
- Consumes: `normalize_report_content` and `render_report_presentation` from Tasks 1 and 3.
- Produces: clean `Report.content_md`, v2 HTML, actual `surface/palette`, citation manifest, typed actions, and clean future share snapshots.

- [ ] **Step 1: Write failing pipeline/persistence/share assertions**

Extend the real fake-provider pipeline test so the generator returns both raw
citation markers and a typed action. Assert:

```python
assert "[evidence:" not in report.content_md
assert "[evidence:" not in report.html
assert report.spec_json["citations"]
assert report.spec_json["suggested_actions"][0]["title"] == "复盘下一次训练"
assert report.spec_json["surface"] == "surface-editorial"
assert report.spec_json["presentation_version"] == "report_html_v2"
```

Add share assertions that both `snapshot_content_md` and public HTML contain no
raw markers and that only cited external sources appear under `参考来源`.

- [ ] **Step 2: Run selected pipeline tests and verify RED**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test \
  python -m pytest tests/unit/test_report_pipeline.py \
  tests/integration/test_report_persist.py \
  tests/integration/test_report_shares.py \
  tests/e2e/test_report_generation_flow.py -q
```

Expected: clean-content, action, citation, and presentation assertions fail.

- [ ] **Step 3: Normalize inside the HTML-render stage**

In `html_render_stage`, call `normalize_report_content` after generator and chart
validation. Pass the normalized Markdown, typed actions, used sources, family,
seed, trusted charts, and optional illustration URL to
`render_report_presentation`. Return this stage result:

```python
{
    "title": title,
    "content_md": normalized.content_md,
    "citations": [item.model_dump(mode="json") for item in normalized.citations],
    "suggested_actions": [
        item.model_dump(mode="json") for item in normalized.suggested_actions
    ],
    "html": presentation.html,
    "surface": presentation.surface,
    "palette": presentation.palette,
    "color_scheme": presentation.color_scheme,
    "warnings": presentation.warnings,
}
```

- [ ] **Step 4: Persist the normalized truth**

In `persist_stage`, use `rendered["content_md"]` rather than raw generator
Markdown. Populate `ReportSpec.citations`, `suggested_actions`, actual surface,
actual palette, seed, and `presentation_version="report_html_v2"`. Preserve
external sources and generated file IDs. Add presentation warnings to the
existing generation-context warnings without duplicates.

- [ ] **Step 5: Make API fallback and shares use v2 metadata**

When `Report.html` is missing, `view_report` and `public_share_html` must pass the
stored family, seed, external sources, and suggested actions to the facade.
Share creation snapshots the already-clean Markdown and HTML; remove the old
replacement of internal evidence IDs from report content because no ID is
user-visible after normalization. Keep media token replacement and share-card
identifier safety intact.

- [ ] **Step 6: Run pipeline/persistence/share tests and verify GREEN**

Run the Step 2 command. Expected: all selected tests pass.

- [ ] **Step 7: Commit Task 4**

```bash
git commit -m "feat(report): persist clean presented reports"
```

---

### Task 5: Add idempotent Report-to-Todo APIs and Asset provenance

**Files:**
- Create: `theme_v2_service/migrations/versions/0011_report_actions.py`
- Create: `theme_v2_service/app/domains/reports/actions.py`
- Modify: `theme_v2_service/app/db/models.py`
- Modify: `theme_v2_service/app/domains/assets/schemas.py`
- Modify: `theme_v2_service/app/domains/assets/service.py`
- Modify: `theme_v2_service/app/domains/reports/api_reports.py`
- Test: `theme_v2_service/tests/integration/test_report_actions.py`
- Test: `theme_v2_service/tests/contract/test_report_api.py`
- Test: `theme_v2_service/tests/integration/test_migrations.py`

**Interfaces:**
- Consumes: `Report.spec_json.suggested_actions` and existing baseline Todo skill provisioning.
- Produces: `list_report_actions`, `create_report_action_todo`, two HTTP endpoints, and Report provenance on `AssetRead`.

- [ ] **Step 1: Write failing owner/idempotency/provenance tests**

Create one owned report with two stored actions and test:

```python
listed = await client.get(f"/api/reports/{report.id}/actions", headers=owner)
created = await client.post(
    f"/api/reports/{report.id}/actions/{action_id}", headers=owner
)
repeated = await client.post(
    f"/api/reports/{report.id}/actions/{action_id}", headers=owner
)

assert listed.json()["actions"][0]["created"] is False
assert created.json()["created"] is True
assert repeated.json() == {
    **created.json(),
    "created": False,
}
```

Also assert: cross-owner 404, unknown action 404, no arbitrary title body,
canonical Todo payload, exact due date propagation, `source_report_id`,
`source_report_action_id`, `source_report_title`, one Asset after concurrent
requests, and missing Todo skill provisioned automatically.

- [ ] **Step 2: Run action/API/migration tests and verify RED**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test \
  python -m pytest tests/integration/test_report_actions.py \
  tests/contract/test_report_api.py \
  tests/integration/test_migrations.py -q
```

Expected: endpoint 404 and missing provenance fields/migration.

- [ ] **Step 3: Add the migration and model fields**

Add nullable `source_report_id CHAR(36)` and
`source_report_action_id VARCHAR(64)` to `assets`. Create:

```text
FOREIGN KEY source_report_id -> reports.id ON DELETE SET NULL
UNIQUE (user_id, source_report_id, source_report_action_id)
INDEX (user_id, source_report_id)
```

Mirror those columns in `Asset`. Extend `AssetRead` with nullable
`source_report_id`, `source_report_action_id`, and transient
`source_report_title`.

- [ ] **Step 4: Attach Report provenance in Asset service reads**

Add a batched helper that loads owner-matched Report titles for Assets with a
non-null `source_report_id`, then assigns `source_report_title` as a transient
attribute. Call it from `get_asset`, `list_assets`, and the action-create return
path. Never add provenance keys to editable `payload_json`.

- [ ] **Step 5: Implement the action service**

In `actions.py` define:

```python
@dataclass(frozen=True)
class ReportActionState:
    id: str
    title: str
    due_at: datetime | None
    created: bool
    todo_asset_id: str | None


async def list_report_actions(
    session: AsyncSession, *, user_id: str, report_id: str
) -> list[ReportActionState]


async def create_report_action_todo(
    session: AsyncSession, *, user_id: str, report_id: str, action_id: str
) -> tuple[ReportActionState, bool]
```

For POST, lock the owned Report row with `FOR UPDATE`, validate the stored
action ID, query any existing provenance pair, provision baseline skills, create
the canonical Todo through `assets.service.create_asset`, set provenance before
flush, and return the existing row on a retry. The row lock serializes concurrent
actions for one Report and the unique key remains the database backstop.

- [ ] **Step 6: Add thin API endpoints**

Add GET `/api/reports/{report_id}/actions` and POST
`/api/reports/{report_id}/actions/{action_id}`. Serialize UTC dates with the
existing `_timestamp` helper. Map missing Report/action to 404. Return:

```json
{"id":"action-7d4f","title":"准备访谈问题","due_at":null,"created":true,"todo_asset_id":"asset-42"}
```

- [ ] **Step 7: Run action/API/migration tests and verify GREEN**

Run the Step 2 command. Expected: all selected tests pass.

- [ ] **Step 8: Commit Task 5**

```bash
git commit -m "feat(report): create idempotent todos from actions"
```

---

### Task 6: Restore the native Theme V2 Report action tray

**Files:**
- Create: `mobile/lib/theme_v2/report/report_actions.dart`
- Modify: `mobile/lib/pages/report_viewer_page.dart`
- Modify: `mobile/lib/theme_v2/report/report_models.dart`
- Modify: `mobile/lib/theme_v2/report/report_container_page.dart`
- Modify: `mobile/lib/theme_v2/report/report_run_page.dart`
- Modify: `mobile/lib/theme_v2/report/report_notification_target.dart`
- Test: `mobile/test/theme_v2/report/report_actions_test.dart`
- Test: `mobile/test/theme_v2/report/report_viewer_theme_test.dart`
- Test: `mobile/test/theme_v2/report/report_notification_routing_test.dart`

**Interfaces:**
- Consumes: Task 5 GET/POST action APIs and report `spec.palette`.
- Produces: `ReportActionItem`, `ReportActionsController`, `ReportActionsTray`, `enableThemeV2Actions`, and palette-aware viewer chrome.

- [ ] **Step 1: Write failing controller and widget tests**

Cover: load, empty list, add one, add all sequentially, idempotent response,
partial failure preserving completed rows, duplicate tap suppression, disabled
busy state, minimum 48px row/button target, and `bumpData()` after creation.

Add entry-point assertions:

```dart
expect(page.enableLegacyEnhancements, isFalse);
expect(page.enableThemeV2Actions, isTrue);
expect(page.themeV2Palette, 'pal-ink');
```

- [ ] **Step 2: Run Flutter tests and verify RED**

Run from `mobile/`:

```bash
flutter test test/theme_v2/report/report_actions_test.dart \
  test/theme_v2/report/report_viewer_theme_test.dart \
  test/theme_v2/report/report_notification_routing_test.dart
```

Expected: missing controller/widget/capability fields.

- [ ] **Step 3: Implement the action model/controller**

In `report_actions.dart` define immutable `ReportActionItem` with
`id/title/dueAt/created/todoAssetId`, and a `ChangeNotifier` controller with:

```dart
Future<void> load(String reportId);
Future<bool> add(String reportId, String actionId);
Future<void> addAll(String reportId);
bool isAdding(String actionId);
int get pendingCount;
```

POST to `/api/reports/$reportId/actions/$actionId` with an empty JSON object.
Update only the returned row, keep prior successes on later failure, expose one
concise error message, and invoke an injected `onTodoCreated` callback.

- [ ] **Step 4: Extract the action tray widget**

Render `ReportActionsTray` below the WebView with Theme V2/legacy-compatible
colors. Use 48px minimum row/button height, at most a 240px scroll area, a
single-line header, two-line action title, optional due label, `加入待办`, busy,
and `已加入` states. Show `全部加入待办` only when `pendingCount >= 2`.

- [ ] **Step 5: Decouple viewer capabilities**

Keep `enableLegacyEnhancements` for legacy rerender only. Add:

```dart
final bool enableThemeV2Actions;
final String? themeV2Palette;
```

Theme V2 action loading no longer depends on legacy enhancements. Replace the
forced Theme V2 dark variable override with palette-aware chrome:

```dart
bool get _lightReport => const {'pal-minimal', 'pal-warm'}
    .contains(widget.themeV2Palette);
```

Use light or dark Scaffold/AppBar/action-tray tokens accordingly while leaving
the report HTML's own CSS variables untouched.

- [ ] **Step 6: Pass Theme V2 capabilities from every entry point**

Parse `spec.palette` in `CompletedReportSummary`. In report container, completed
run, and notification routes, pass `enableThemeV2Actions: true` and the stored
palette. Preserve `enableLegacyEnhancements: false` so the legacy rerender button
does not call an unsupported Theme V2 endpoint.

- [ ] **Step 7: Run Flutter tests and verify GREEN**

Run the Step 2 command. Expected: all selected tests pass.

- [ ] **Step 8: Commit Task 6**

```bash
git commit -m "feat(report): restore Theme V2 action tray"
```

---

### Task 7: Make Report-created Todos navigate back to their source

**Files:**
- Modify: `mobile/lib/theme_v2/asset_detail/asset_detail_model.dart`
- Modify: `mobile/lib/theme_v2/asset_detail/asset_detail_repository.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_detail_sheet.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_record.dart`
- Modify: `mobile/lib/theme_v2/report/report_notification_target.dart`
- Test: `mobile/test/theme_v2/asset_detail/asset_detail_repository_test.dart`
- Test: `mobile/test/theme_v2/library/asset/asset_detail_test.dart`
- Test: `mobile/test/theme_v2/report/report_notification_routing_test.dart`

**Interfaces:**
- Consumes: `AssetRead.source_report_id`, `source_report_action_id`, and `source_report_title` from Task 5.
- Produces: `AssetDetailSourceKind.report`, `reportId`, readable provenance copy, and source Report navigation.

- [ ] **Step 1: Write failing source parsing/navigation tests**

Given a Todo Asset response with Report provenance, assert the detail source is:

```dart
expect(detail.source.kind, AssetDetailSourceKind.report);
expect(detail.source.label, '来自报告《月度复盘》');
expect(detail.source.reportId, 'report-1');
expect(detail.source.canOpen, isTrue);
```

Test a deleted source response: the label remains but tapping is disabled/no-op
without throwing.

- [ ] **Step 2: Run source tests and verify RED**

Run from `mobile/`:

```bash
flutter test test/theme_v2/asset_detail/asset_detail_repository_test.dart \
  test/theme_v2/library/asset/asset_detail_test.dart \
  test/theme_v2/report/report_notification_routing_test.dart
```

Expected: unsupported source kind and missing Report fields/navigation.

- [ ] **Step 3: Extend the source model without overloading session fields**

Add `report` to `AssetDetailSourceKind` and nullable `reportId` to
`AssetDetailSource`. `canOpen` becomes:

```dart
bool get canOpen => switch (kind) {
  AssetDetailSourceKind.manual => false,
  AssetDetailSourceKind.report => reportId != null,
  AssetDetailSourceKind.flash || AssetDetailSourceKind.session =>
    sessionId != null && inputTurnId != null,
};
```

Update JSON parsing for canonical details and `_coreSource` for direct
`/api/assets/{id}` responses. Report provenance wins over manual source but never
over an actual capture/session source on records that were not created by the
Report action API.

- [ ] **Step 4: Open the source Report from Asset detail**

In `_openSource`, switch on source kind. For Report, fetch
`/api/reports/$reportId`, build `ReportViewerPage` with Theme V2 actions and the
stored palette, and push it. On 404, retain the detail surface and show
`来源报告已不存在` once; do not pop or replace the current route.

- [ ] **Step 5: Keep provenance outside editable fields/cards**

Ensure Report provenance top-level response fields are never included in
`AssetDetailField`, `AssetRecordField`, card secondary text, or edit payload.
Only the sticky source row shows it.

- [ ] **Step 6: Run source tests and verify GREEN**

Run the Step 2 command. Expected: all selected tests pass.

- [ ] **Step 7: Commit Task 7**

```bash
git commit -m "feat(assets): link report todos to their source"
```

---

### Task 8: Repair existing Theme V2 reports without model calls

**Files:**
- Create: `theme_v2_service/scripts/repair_report_presentations.py`
- Modify: `theme_v2_service/app/domains/reports/maintenance.py`
- Test: `theme_v2_service/tests/integration/test_report_maintenance.py`

**Interfaces:**
- Consumes: stored Report, ReportGenerationRun checkpoint data, normalizer, presentation engine, and stored media IDs.
- Produces: `ReportRepairResult`, `repair_report_presentations`, and a dry-run/apply CLI.

- [ ] **Step 1: Write failing repair/idempotency tests**

Create one legacy row containing raw evidence markers and a legacy actions block,
plus one unsafe row containing an unknown marker. Assert:

```python
result = await repair_report_presentations(session, dry_run=False)
assert result.repaired == 1
assert result.skipped_unsafe == 1
assert "[evidence:" not in repaired.content_md
assert "[evidence:" not in repaired.html
assert repaired.spec_json["presentation_version"] == "report_html_v2"
assert (await repair_report_presentations(session, dry_run=False)).repaired == 0
```

Also test `dry_run=True` makes no writes and chart SVG recovery reads the stored
generation-job `chart_validation` checkpoint when available.

- [ ] **Step 2: Run maintenance tests and verify RED**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test \
  python -m pytest tests/integration/test_report_maintenance.py -q
```

Expected: missing repair entry point.

- [ ] **Step 3: Implement bounded, idempotent repair**

Add:

```python
@dataclass(frozen=True)
class ReportRepairResult:
    eligible: int = 0
    repaired: int = 0
    skipped_unsafe: int = 0


async def repair_report_presentations(
    session: AsyncSession,
    *,
    dry_run: bool,
    limit: int = 100,
) -> ReportRepairResult
```

Select rows with raw markers or a non-v2 presentation version, lock in ID order
with `skip_locked`, normalize only exact stored allowlists, recover charts from
the generation-job checkpoint, reconstruct owned illustration URLs from stored
file IDs, rerender with stored family/seed, and update Markdown/HTML/spec only
when not dry-run. Skip unknown markers and log only sanitized report/error codes.

- [ ] **Step 4: Add the explicit CLI**

The script supports:

```text
python scripts/repair_report_presentations.py --dry-run
python scripts/repair_report_presentations.py --apply
```

Require exactly one mode, use `AsyncSessionFactory`, commit only in apply mode,
and print JSON counts without report content or user identifiers.

- [ ] **Step 5: Run maintenance tests and verify GREEN**

Run the Step 2 command. Expected: all selected tests pass.

- [ ] **Step 6: Commit Task 8**

```bash
git commit -m "fix(report): repair stored report presentations"
```

---

### Task 9: Close automated, Docker, visual, and real-device acceptance

**Files:**
- Create: `theme_v2_service/tests/fixtures/report_presentation_fixture.md`
- Create: `theme_v2_service/scripts/render_report_fixture_gallery.py`
- Modify: `theme_v2_service/tests/e2e/test_report_generation_flow.py`
- Modify: `docs/superpowers/plans/2026-08-04-theme-v2-report-completion.md`
- Modify only when a failing acceptance test exposes a defect: files from Tasks 1–8.

**Interfaces:**
- Consumes: all completed backend/mobile interfaces.
- Produces: deterministic eight-variant HTML fixture gallery, full automated evidence, repaired live rows, and one connected-device workflow result.

- [ ] **Step 1: Add the deterministic fixture gallery**

The script reads one rich Markdown fixture and writes eight HTML files to an
ignored temporary/output directory, one for every catalog entry. It must not
call Planner, Generator, Web Search, or Seedream. Print a JSON manifest with
family, seed, surface, palette, color scheme, path, and SHA-256.

- [ ] **Step 2: Run focused backend suites**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test \
  python -m pytest tests/unit/test_report_normalization.py \
  tests/unit/test_report_generation_security.py \
  tests/unit/test_report_presentation.py \
  tests/unit/test_report_rendering.py \
  tests/unit/test_report_pipeline.py \
  tests/contract/test_report_api.py \
  tests/integration/test_report_actions.py \
  tests/integration/test_report_persist.py \
  tests/integration/test_report_shares.py \
  tests/integration/test_report_maintenance.py \
  tests/e2e/test_report_generation_flow.py -q
```

Expected: zero failures/errors.

- [ ] **Step 3: Run the complete Theme V2 backend suite**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test \
  python -m pytest -q
```

Expected: zero failures/errors. Record the test count in this plan's execution
notes.

- [ ] **Step 4: Run focused Flutter tests and static analysis**

Run from `mobile/`:

```bash
flutter test test/theme_v2/report test/theme_v2/asset_detail \
  test/theme_v2/library/asset
flutter analyze lib/pages/report_viewer_page.dart lib/theme_v2/report \
  lib/theme_v2/asset_detail lib/theme_v2/library/asset
```

Expected: all tests pass and analyzer reports no issues.

- [ ] **Step 5: Rebuild the independent Theme V2 runtime**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml up -d --build migrate api worker
docker compose -f docker-compose.theme-v2.yml ps
curl -fsS http://127.0.0.1:8100/ready
```

Expected: migration completes, API/worker are up, MySQL/API are healthy, and
`/ready` returns `{"status":"ready"}`.

- [ ] **Step 6: Dry-run and apply historical repair**

Run in the API container:

```bash
python scripts/repair_report_presentations.py --dry-run
python scripts/repair_report_presentations.py --apply
python scripts/repair_report_presentations.py --dry-run
```

Expected: first dry-run reports the two current eligible rows; apply repairs
them; second dry-run reports zero eligible rows. Query counts only and confirm
no stored Markdown/HTML contains `[evidence:` or `[source:`.

- [ ] **Step 7: Build and install the Android debug app**

Run from `mobile/`:

```bash
flutter build apk --debug
adb -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s RFCY71B21YK reverse tcp:8000 tcp:8000
adb -s RFCY71B21YK shell am force-stop com.eureka.mindapp
adb -s RFCY71B21YK shell monkey -p com.eureka.mindapp \
  -c android.intent.category.LAUNCHER 1
```

Expected: build/install succeeds and the app launches against the independent
Theme V2 service.

- [ ] **Step 8: Execute one real Report-to-Todo workflow**

Using the connected device and existing owned Theme V2 records:

1. generate one actionable Report;
2. verify no raw evidence/source markers;
3. verify the selected visual family and optional Seedream illustration;
4. add one action, then add all remaining actions;
5. reopen and verify every created action shows `已加入`;
6. open the created Todo and follow `来自报告《…》` back to the same Report;
7. open a share and confirm clean content and normal external sources.

Capture one screenshot each for report body, action tray, created Todo source,
and returned Report. Record any unavailable external provider as a degraded
capability, not a presentation/action failure.

- [ ] **Step 9: Review the final diff against the design**

Check every section of the design spec maps to code/tests. Run:

```bash
git diff --check
git status --short
git diff --stat 374d8d0..HEAD
```

Confirm unrelated dirty files are neither staged nor committed and no backend
runtime import references `backend.agents`.

- [ ] **Step 10: Commit final fixtures/acceptance notes**

Stage only Task 9 files and any verified defect fixes, then commit:

```bash
git commit -m "test(report): close Theme V2 report acceptance"
```

Do not push or merge.
