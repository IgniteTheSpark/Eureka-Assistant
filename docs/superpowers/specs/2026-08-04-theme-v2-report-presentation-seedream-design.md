# Theme V2 Report Presentation and Seedream Design

**Status:** Ready for implementation planning after product review

**Date:** 2026-08-04

**Scope:** Theme V2 Report presentation layer, one Seedream illustration, local public media delivery

## 1. Decision summary

Theme V2 will gain an independent, trusted Report presentation layer under `theme_v2_service`. It will migrate selected visual concepts from the old backend without importing or calling the old backend at runtime.

The first delivery is a vertical slice with:

- four deterministic Report families with visibly different layouts;
- a whitelist-based Markdown and structured-block renderer;
- at most one Seedream illustration per Report;
- a public, high-entropy media URL suitable for local Docker now and OSS/S3 later;
- deterministic image placement in both the private in-app Report and the public share page;
- graceful degradation when illustration generation is disabled or fails.

This work does not change Planner, Evidence, Job, or database architecture. It also does not require a standalone private Report URL: the app continues loading Report JSON and renders the returned HTML in a WebView.

## 2. Context and current gaps

The old backend already contains a richer Report presentation system:

- six color palettes;
- eight surface/layout styles;
- a structured content block kit;
- a Seedream image adapter.

Theme V2 currently renders all Reports through one generic stylesheet and template. Although `base_family`, `surface`, and `palette` values exist in the data model, they do not materially change the result. Theme V2 also has a generic illustration provider, but its model and endpoint are not configured in Docker, its request does not fully match the Ark image API, and generated files are not deterministically inserted into the Report body or share-card specification.

The consequence is that Report generation may technically complete while every family looks nearly identical and illustration generation remains invisible or unreliable.

## 3. Goals

1. Make `base_family` produce an immediately recognizable visual family.
2. Preserve the old design language by copying and restructuring trusted style rules into Theme V2.
3. Keep model-produced content untrusted: it may select structured directives but may not inject HTML, JavaScript, CSS, or arbitrary attributes.
4. Generate at most one privacy-safe decorative illustration using Seedream.
5. Store and serve that illustration through a small storage abstraction that can move from a Docker volume to OSS/S3 without changing the Report pipeline.
6. Prove the result with deterministic fixtures, automated tests, and real-device acceptance.

## 4. Non-goals

The first delivery does not include:

- all eight old surface styles;
- a user-facing style picker or “换装” operation;
- automatic re-rendering of existing Reports;
- actual OSS/S3 provisioning;
- multiple AI illustrations per Report;
- AI-generated charts, text inside illustrations, portraits, logos, or precise personal data;
- stabilization or redesign of the current DeepSeek Report content generator;
- Planner, Evidence, Job, queue, or database redesign.

Existing Reports retain their stored HTML. The new presentation path applies to newly rendered Reports and to explicit deterministic acceptance fixtures.

## 5. Architecture

### 5.1 Module boundary

Create the following package:

```text
theme_v2_service/app/domains/reports/presentation/
├── __init__.py
├── blocks.py
├── catalog.py
├── renderer.py
└── styles.py
```

Responsibilities:

- `catalog.py` maps `base_family` and `seed` to a concrete surface and palette.
- `blocks.py` parses only supported structured directives into a typed internal representation.
- `renderer.py` renders sanitized Markdown, typed blocks, trusted chart SVGs, and an optional illustration URL into the final HTML document.
- `styles.py` contains the copied and restructured trusted CSS for the four selected families.

The package must not import `backend.agents.*`. The old backend is a design source only; Theme V2 owns its copied implementation and tests.

### 5.2 Data contracts

The presentation entry point accepts a request equivalent to:

```python
PresentationRequest(
    title: str,
    content_md: str,
    base_family: str,
    seed: int,
    chart_svgs: list[str],
    illustration_url: str | None,
)
```

It returns:

```python
PresentationResult(
    html: str,
    surface: str,
    palette: str,
)
```

`surface` and `palette` are persisted alongside the existing `base_family` and `seed`. They describe the actual rendered output instead of acting as decorative metadata.

### 5.3 First-round style catalog

| Base family | Product meaning | Surface | Palette |
|---|---|---|---|
| `data_trend` | Data-led analysis | `surface-dashboard` | `pal-dashboard` |
| `theme_synthesis` | Narrative synthesis | `surface-editorial` | `pal-ink` |
| `professional_evaluation` | Structured assessment | `surface-deck` | `pal-minimal` |
| `briefing_research` | Concise research briefing | `surface-briefing` | `pal-minimal` |

`surface-briefing` is a Theme V2 adaptation of the old deck/briefing language rather than an alias that produces identical markup.

Within a base family, `seed` may select bounded decorative variants such as accent placement or section rhythm. Given the same family, seed, and content, rendering must be deterministic.

Unknown families fall back to `briefing_research` presentation semantics. The fallback is recorded in structured logs and does not fail the Report.

## 6. Trusted content rendering

### 6.1 Markdown

Markdown is converted with raw HTML disabled. URLs are filtered to approved schemes. The renderer escapes all plain text and attributes. Model output cannot introduce `<script>`, inline event handlers, style tags, iframes, or arbitrary CSS classes.

### 6.2 Structured block whitelist

The first delivery supports exactly these directives:

- `:::kpi`
- `:::timeline`
- `:::rank`
- `:::callout{tone=insight|warn|success}`
- `:::quote`
- `:::actions`
- `:::compare`

Every directive is parsed into a typed block and rendered by trusted templates. Unknown directives are displayed as escaped prose; they are never executed, silently interpreted, or passed through as HTML.

The `tone` attribute accepts only `insight`, `warn`, or `success`. Extra attributes are discarded. Quiz, flashcard, arbitrary embed, and raw HTML directives are outside the first delivery.

### 6.3 Charts

Charts remain deterministic application-generated SVG. The renderer accepts chart SVG only from the trusted chart-rendering component, not directly from model output. It strips scripts, external references, event handlers, and foreign objects before insertion.

### 6.4 Illustration placement

When an illustration URL exists, the renderer inserts one trusted figure after the hero/lead and before the first analytical section:

```html
<figure class="r-ai-img">
  <img src="..." alt="Report illustration" loading="lazy">
</figure>
```

The source URL is created by the storage layer, not copied from model output. If no illustration exists, the figure is omitted completely, leaving no empty frame or spacing gap.

## 7. Seedream illustration pipeline

### 7.1 Provider

Add a dedicated `SeedreamIllustrationProvider` rather than extending the generic text provider. Its Ark request contract is:

- model: `doubao-seedream-4-5-251128`;
- default endpoint: `https://ark.cn-beijing.volces.com/api/v3/images/generations`, overridable by environment;
- resolution: 2K;
- watermark: false;
- sequential image generation: disabled;
- response format: `b64_json`, with a provider URL download accepted as a fallback;
- request timeout: 90 seconds, with no automatic retry;
- maximum output: one image per Report.

Production configuration uses a dedicated `REPORT_ILLUSTRATION_API_KEY`. For local acceptance only, configuration may fall back to the existing old-service `IMAGE_API_KEY`. The key must never be logged, returned by an API, written into a fixture, or committed.

The implementation uses these configuration names:

```text
REPORT_ILLUSTRATION_ENABLED
REPORT_ILLUSTRATION_MODEL
REPORT_ILLUSTRATION_API_URL
REPORT_ILLUSTRATION_API_KEY
REPORT_MEDIA_ROOT
REPORT_MEDIA_PUBLIC_BASE_URL
```

Docker Compose passes only these names into the Theme V2 worker. Disabling `REPORT_ILLUSTRATION_ENABLED` bypasses the provider cleanly.

### 7.2 Prompt safety

The illustration prompt combines a short, sanitized summary with the migrated House Style. It explicitly requests:

- an editorial, abstract, non-photoreal supporting image;
- no words, numbers, charts, labels, or logos;
- no recognizable faces;
- no precise names, contact details, addresses, financial identifiers, or other personal data.

Prompt construction uses bounded Report metadata and summarized themes. Raw evidence, full transcripts, and private contact fields are not sent to the image provider.

### 7.3 Execution and persistence

The external image request runs outside a database transaction. After generation succeeds:

1. validate response type and size;
2. normalize the image to WebP if required;
3. write it through the Report object-storage interface;
4. receive its public URL;
5. render final HTML with that URL;
6. commit the Report result and media references in one short database transaction.

The Report stores:

- the image file/object identifier in `spec_json.generated_file_ids`;
- the same identifier in `share_card_spec.illustration_file_id`;
- provider, model, status, and safe diagnostic metadata under `generation_context.illustration`;
- the public URL only where required by rendered HTML and the response contract.

No API key, complete provider payload, or unsanitized prompt is persisted.

## 8. Media storage and URL model

### 8.1 Local Docker storage

The local implementation stores files in the existing Theme V2 media volume:

```text
volume: eureka-theme-v2_media_data
root:   /data/media
key:    report-illustrations/{opaque-id}.webp
```

`opaque-id` is a cryptographically random, high-entropy identifier. The object path contains no user ID, Report ID, title, date, original filename, or model prompt.

The API serves only the object route, without directory listing:

```text
http://localhost:8100/media/report-illustrations/{opaque-id}.webp
```

Responses use the correct image content type, immutable/long-lived caching, and `nosniff`. Unsupported extensions and malformed identifiers return 404.

### 8.2 Production migration

The Report pipeline depends on an object-storage protocol, not on local filesystem paths. A future OSS/S3 adapter returns the same kind of stable public URL, for example:

```text
https://cdn.ureka.example/report-illustrations/{opaque-id}.webp
```

Moving to OSS/S3 therefore changes storage configuration and the adapter, not Report rendering or mobile behavior.

### 8.3 Privacy and revocation tradeoff

Illustrations are treated as low-privacy decorative assets. Their URLs are public but practically unguessable. There is no URL signature, view ticket, cookie gate, or per-request authorization.

Accepted tradeoff: revoking a Report share link does not invalidate an illustration URL that a recipient already knows. An object can still be explicitly deleted from storage when required, but immediate cryptographic revocation is outside this design.

## 9. Report access model

Private app viewing remains:

1. authenticated `GET /api/reports/{report_id}`;
2. response includes the stored HTML/body contract;
3. Flutter renders it with `WebView.loadHtmlString`.

There is no new private browser URL and no Report-view token.

Public sharing remains:

```text
/r/{share_token}
```

Both private app HTML and the public share page reference the same public illustration URL. Share authorization continues to protect the Report text and metadata; it is not reused for decorative media.

## 10. Failure behavior and observability

Illustration failure never fails the Report. Timeout, invalid response, unsupported image, storage error, missing key, or disabled configuration produces a completed text-only Report.

The worker records a bounded status such as `disabled`, `succeeded`, `provider_error`, `invalid_image`, or `storage_error` in `generation_context.illustration`. Logs include Report/job correlation IDs, provider, model, duration, status, and sanitized error category. Logs exclude API keys, raw prompts, full evidence, provider response bodies, and generated binary data.

Presentation rendering failures fall back to the current safe Theme V2 renderer where possible. If both renderers fail, existing job failure semantics remain authoritative.

Provider calls use a bounded timeout and no unbounded retry. The first delivery performs at most one paid image request for each Report attempt and one paid call during real acceptance.

## 11. Verification strategy

### 11.1 Unit tests

- every supported `base_family` maps to the specified surface and palette;
- identical inputs and seed produce identical presentation choices;
- an unknown family uses the documented fallback;
- each whitelisted block renders through a trusted template;
- unsupported directives, raw HTML, scripts, handlers, and unsafe URLs cannot pass through;
- chart sanitization removes active or external content;
- Seedream requests contain the exact Ark model and required image parameters;
- prompt construction omits prohibited personal fields;
- stored object keys are opaque and contain no user/Report identifiers;
- successful generation updates body HTML, generated file IDs, share-card illustration ID, and generation context;
- provider and storage failures complete as text-only Reports.

### 11.2 Integration tests

Use a fake illustration provider and temporary object store to exercise the complete worker path without paid calls. Verify that the final private Report and public share HTML both contain the same accessible media URL.

Verify the local media endpoint returns the image with the expected headers and rejects enumeration-like, malformed, and unsupported paths.

### 11.3 Deterministic acceptance fixtures

Create four Reports with stable content, one for each first-round family. This isolates presentation acceptance from the currently unstable DeepSeek content generator.

The `theme_synthesis` fixture receives the single real Seedream illustration call. The other three remain text/chart only. Acceptance checks:

1. all four Reports are completed and visibly distinct;
2. each persisted surface and palette matches the catalog;
3. the illustrated Report shows one image after its lead section;
4. the same image appears in the public share page;
5. the media URL contains no user ID, Report ID, or readable title;
6. the Theme V2 Android app opens and scrolls each Report correctly on the connected device;
7. disabling or forcing failure of the image provider still yields a usable completed Report.

Real Planner/Generator compatibility is checked after the deterministic vertical slice, but generator quality is not an acceptance blocker for this presentation milestone.

## 12. Rollout

1. Land the presentation package and tests with illustration generation disabled by default.
2. Add local media serving and fake-provider integration coverage.
3. Configure the local worker using the existing private Ark key fallback and perform one paid Seedream acceptance call.
4. Verify the four fixtures in API, public share page, and the connected Android device.
5. Enable the feature only in the Theme V2 environment after the degraded path has also been verified.

Rollback is configuration-only for illustrations and routing-level for the new renderer. Existing stored Report HTML is immutable and remains viewable.

## 13. Follow-on scope

After this vertical slice is accepted, a separate product decision may schedule:

- migration of the remaining old surfaces and palettes;
- user-facing presentation selection or re-rendering;
- explicit deletion and lifecycle rules for media objects;
- production OSS/S3/CDN configuration;
- broader generator reliability and content-quality work.

These items are intentionally separated so the first implementation can prove the full presentation-to-device path without expanding architectural scope.
