# Report Conditional External Research Design

**Date:** 2026-08-24

**Status:** Design approved in conversation; written spec awaiting user review

**Scope:** Report planning, anomaly-led external research, evidence-backed inline reference modules, and local asynchronous loading behavior

## 1. Objective

Reports must be able to use external knowledge for more than explicitly requested
research. A Report may discover that owned records contain an important anomaly
whose interpretation would materially improve with an authoritative external
reference.

This design makes external research a conditional evidence capability available
to every Report content family. It is not a new Report template, a health-only
feature, or a post-Report upsell.

The intended behavior is:

1. explicit comparison, verification, advice, or research requests are included
   in the confirmed plan before generation;
2. a credible anomaly discovered during generation may start relevant external
   research automatically without interrupting the user;
3. the core Report remains readable while the related external-reference module
   is loading;
4. external facts, owned facts, and Reka interpretation remain visibly and
   structurally distinct.

## 2. Relationship to Existing Report Designs

This specification extends, rather than replaces:

- `2026-08-19-report-scope-picker-skill-fields-design.md` for one-page demand
  confirmation and authoritative selected evidence;
- `2026-08-11-theme-v2-report-reliability-scope-and-async-illustration-design.md`
  for scope-bound plans, durable optional work, and readable Reports before all
  optional enrichment finishes;
- `2026-08-04-theme-v2-report-readability-presentation-actions-design.md` for
  trusted rendering and the final external-source list;
- the existing Report template catalog and presentation families.

Where older specifications say that a period summary activates Web Search only
after an explicit user request, this specification adds one bounded exception:
a credible generation-time anomaly may activate conditional external research
when external evidence can materially improve the interpretation.

The exact user-selected Asset references remain authoritative. Conditional
research may add public evidence but may not silently add unselected owned
Assets.

## 3. Product Decisions

### 3.1 External research is an evidence module

Content templates continue to decide how a Report analyzes its subject, for
example child care, spending, exercise, learning, work, or idea synthesis.
Presentation families continue to decide visual language, for example dashboard,
neon, editorial, note, deck, or briefing.

Conditional external research adds a typed evidence module to the chosen content
and presentation. It does not select or replace either one.

Examples include:

- feeding records compared with an applicable authoritative feeding reference;
- an expense change checked against a price, exchange-rate, or subscription
  change;
- a training anomaly compared with an appropriate training-load reference;
- a work metric interpreted alongside a relevant market event or benchmark;
- repeated reading notes enriched with the source theory or a credible opposing
  view.

### 3.2 Two trigger paths

External research has two independent trigger paths.

**Explicit trigger**

The user's initial brief or supplemental information asks for a comparison,
verification, external standard, current information, recommendation, or health
or financial reference. The plan must state the corresponding research purpose
before the user confirms generation.

**Conditional automatic trigger**

The user did not explicitly request research, but analysis discovers a credible
anomaly and external evidence would materially change or qualify its
interpretation. The generator starts the research automatically. It does not
pause for another confirmation and does not ask for missing information during
generation.

All data-summary Report plans implicitly permit this conditional behavior. The
plan contract communicates it once in concise supporting language equivalent to:

> 如分析过程中发现显著异常，Reka 可自动补充权威外部资料与参考范围。

### 3.3 No post-Report suggestion step

The system does not finish a Report and then offer an unrelated “compare with a
standard” upsell. Explicit needs belong in planning. Automatically discovered
needs belong beside the finding that triggered them.

## 4. Conditional Trigger Gate

An unusual value is not sufficient by itself. Before automatic research starts,
the analysis must evaluate all available evidence across four dimensions.

### 4.1 Data integrity

- Is the record complete enough to interpret?
- Could the value be a partial event, duplicate, unit mismatch, extraction
  mistake, or missing entry?
- Does the configured Skill field meaning support the proposed comparison?

### 4.2 Personal baseline

- How far does the value differ from this user's or subject's own history?
- Is the change isolated, repeated, or trending?
- Is the available history large enough to describe a baseline honestly?

The system must not encode a universal rule such as `20ml is abnormal`. In the
feeding example, 20ml first means that one record differs from the baby's own
recent feeding records. Medical significance is a separate externally supported
question.

### 4.3 External relevance

- Does a public standard, current event, benchmark, or professional reference
  exist for this kind of finding?
- Would it improve the explanation rather than merely add generic prose?
- Do the available user attributes satisfy the reference's applicability
  conditions?

### 4.4 Confidence and priority

Only high-value findings enter external research. Low-confidence anomalies stay
as owned-data observations. The research budget is bounded and prioritizes the
findings most likely to change the Report's interpretation. A Report must not
start one search for every small fluctuation.

## 5. Generation Flow

```text
confirmed owned evidence + user brief
  -> choose content template and presentation
  -> start core owned-data analysis
  -> evaluate explicit research requirements
  -> evaluate conditional anomaly gates
       -> no qualifying need: finish core Report normally
       -> qualifying need: create external-reference work
  -> persist and expose the readable core Report
  -> external research continues independently
       -> ready: replace the local loading module with trusted content
       -> failed: replace it with a local failure and retry state
```

Core analysis and external research should run in parallel where their inputs
allow it. External work must be durable across a worker or app restart and must
have an idempotent identity derived from the Report attempt and triggering
finding. Repeated refreshes or retries must not create duplicate paid searches
or duplicate modules.

External research does not change the Report's selected owned evidence scope.
It appends validated public sources and a bounded interpretation tied to one
specific finding.

## 6. Report Presentation

### 6.1 Normal Report state

Once trusted core content is persisted, the Report opens normally and is shown
as generated. Conditional external research does not add a Report-level
intermediate state, full-page loading view, top status banner, or blocking
overlay.

### 6.2 Local loading module

The only pending presentation is placed directly after the finding that
triggered research. It states:

- that an external reference is being generated;
- what kind of material is being checked;
- that the rest of the Report remains available;
- that the module will update in place.

The loading component reserves stable space and does not move unrelated Report
content as progress changes. It does not display fabricated partial conclusions.

### 6.3 Ready module

When research succeeds, the same slot is replaced in place with:

1. the owned-record fact that triggered the comparison;
2. the relevant external reference or comparison range;
3. Reka's bounded interpretation of their relationship;
4. applicability conditions and uncertainty;
5. source markers resolved into the Report's final source list.

The module inherits the Report's presentation family but retains a consistent
semantic label such as `外部参照` or, for high-risk health information,
`健康参考`. This prevents public evidence from looking like another owned-data
KPI.

### 6.4 Failed module

A failed or source-insufficient research attempt affects only its slot. The slot
states that the reference could not be completed and provides an idempotent
retry action. Core findings, charts, actions, sharing, and other Report sections
remain usable.

The Report never fills a failed slot with uncited model memory.

### 6.5 Sources

Compact source attribution may appear inside the ready module. The complete
title, publisher/domain, URL, and access information remain consolidated in the
existing `参考来源` section at the end of the Report.

Only sources actually used by a visible module appear in the final list.

## 7. Source and Safety Policy

### 7.1 Source selection

Research prioritizes sources appropriate to the domain:

1. primary government, standards-body, academic, or professional-association
   material;
2. original provider or company documentation for product, price, policy, and
   service changes;
3. high-quality secondary sources only when primary material is unavailable or
   requires interpretation.

Time-sensitive claims require freshness checks. Materially conflicting sources
must be represented as disagreement or uncertainty, not merged into a false
single standard.

The phrase “international standard” does not authorize inventing a global
consensus. The module names the actual authority, population, jurisdiction, and
applicability of each reference.

### 7.2 Health and other high-risk domains

Health, finance, legal, and similarly high-risk modules use stricter language
and source thresholds.

They may provide:

- sourced reference ranges and general educational information;
- differences between the owned record and an applicable reference;
- uncertainty and missing-context explanations;
- clear conditions for seeking qualified professional help.

They may not provide:

- a diagnosis presented as fact;
- medication, dosage, or treatment instructions unsupported by an authorized
  professional workflow;
- deterministic financial, legal, or safety-critical decisions;
- reassurance that contradicts a credible urgent-risk source.

When a credible urgent-risk condition is supported, the module prioritizes a
clear escalation message over visual analysis or generic suggestions.

## 8. Insufficient Context

Conditional research never interrupts generation to ask the user for more
information.

When required context is absent, the module must choose one of these outcomes:

- present a more general reference whose conditions are satisfied;
- explain which exact comparison cannot be made and why;
- omit the comparison and report that no reliable applicable reference was
  found.

It must not infer missing age, weight, geography, feeding method, currency,
training status, or other decisive attributes.

For example, sparse single-feeding records cannot be compared directly with a
daily weight-normalized intake recommendation. The module may describe the
change relative to the baby's own records and explain that a daily standardized
comparison is unsupported by the available data.

## 9. Data and State Boundaries

The Report owns a collection of external-reference module states equivalent to:

```text
module_id
trigger_finding_id
trigger_kind: explicit | conditional
domain
status: pending | ready | failed | insufficient
query_scope
source_manifest
trusted_content
error_category optional
revision
```

`pending` is a module status, not a Report Run status. A newer module revision
can update an open Report in place and is fetched on a normal reopen.

The trusted renderer accepts typed module content only. Model-authored HTML,
scripts, arbitrary SVG, remote image markup, and unvalidated URLs remain
forbidden under the existing Report renderer contract.

No new notification or Reka signal is created solely because an external module
finishes. The module itself changes from loading to ready or failed. Existing
Report completion and update mechanisms remain authoritative.

## 10. Error Handling

- Explicit research cannot find an applicable source: keep the Report readable
  and show an `insufficient` module explaining the limitation.
- Conditional research cannot find an applicable source: replace only the
  local loading slot with a concise insufficient-reference state.
- Provider timeout or temporary failure: show local failure and allow bounded,
  idempotent retry.
- Unsafe or unsupported high-risk request: omit unsafe advice while preserving
  safe factual analysis and explain the boundary.
- Citation or claim validation failure: reject the module content rather than
  publishing an ungrounded reference.
- Report closed during research: durable work continues; reopening reads the
  latest module revision.
- Report deleted or no longer owned: pending external work terminates without
  publishing content.

## 11. Observability and Performance

Track separate bounded timings and outcomes for:

- anomaly evaluation;
- trigger acceptance or rejection reason;
- external query construction;
- provider search and retrieval;
- source-quality and applicability validation;
- module generation and trusted rendering;
- local module revision pickup.

Logs contain Report, Run, module, trigger-finding, and job correlation IDs. They
exclude full private Asset payloads, credentials, and unbounded provider
responses.

External work is parallel and optional to core readability. It must not return
the Report to a generating state or increase the time before the user can open
trusted core content.

## 12. Focused Verification

Follow the repository `AGENTS.md` verification constraints. Implementation
evidence is limited to the reported behaviors, directly affected contracts, a
small set of credible adjacent risks, targeted static analysis, and diff checks.

### 12.1 Planning and trigger cases

- An explicit request to compare feeding with an external standard includes the
  research purpose in the confirmed plan.
- A normal personal-data summary does not start external research by default.
- A credible owned-baseline anomaly starts one conditional research job without
  another user confirmation.
- A partial, duplicate, unit-invalid, or low-confidence record does not trigger
  automatic research.
- Repeated evaluation of the same Report attempt does not duplicate research.
- Conditional research never adds unselected owned Assets.

### 12.2 Evidence and safety cases

- A feeding outlier is described first as a change relative to personal history,
  not as an automatic medical abnormality.
- Missing age or weight prevents an unsupported age- or weight-normalized
  comparison without pausing generation.
- “International standard” output names actual sources and applicability rather
  than inventing a universal standard.
- Health and financial modules apply their stricter source and language policy.
- Every visible external claim resolves to an accepted source.
- No reliable source produces `insufficient`, not uncited generated prose.

### 12.3 Report and mobile cases

- The Report opens normally while one external module is pending.
- There is no Report-level loading or intermediate state for conditional
  research.
- Only the related inline module displays loading.
- Ready content replaces the same slot without resetting Report scroll or
  action state.
- Failure affects only the module and exposes retry.
- Closing and reopening displays the latest durable module state.
- The final source list contains exactly the sources used by ready modules.

No repository-wide backend suite, full Flutter suite, unrelated-module audit, or
real-device rebuild is required for this scoped implementation unless the user
later requests merge/release preparation or another `AGENTS.md` exception
applies and is confirmed first.

## 13. Completion Criteria

This design is complete when:

- explicit external needs shape the plan before generation;
- credible anomalies can start cross-domain research automatically;
- automatic research does not interrupt the user or expand owned evidence;
- the Report is normally readable while only the relevant module loads;
- completed references appear beside their triggering conclusions;
- complete sources remain available at the end of the Report;
- insufficient context and provider failure degrade locally and honestly;
- high-risk information remains sourced, qualified, and non-diagnostic;
- focused regression and adjacent-risk tests pass under the repository
  verification policy.
