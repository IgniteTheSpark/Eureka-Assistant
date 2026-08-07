# Theme V2 Unified Report Planning and Public Research Design

**Date:** 2026-08-07

**Status:** Design approved; written spec awaiting user review

**Scope:** Theme V2 Report planning interaction, editable evidence and research scope, safe quick generation, public-research quality, and source navigation

## 1. Context

Theme V2 already has one `ReportGenerationRun` workflow for user-initiated and
Trigger-initiated Reports, but the product experience and public-research
contract are incomplete.

The current mobile proposal page shows only each option's title and summary.
Users cannot inspect the concrete research scope, add an extra focus, add or
remove Assets, or understand which personal data will be used internally versus
sent to public search. The current `time_range` is also presented too broadly:
in the service it primarily limits internal evidence, but a generic UI field
can be mistaken for a Web Search date filter.

The live pre-event Report for `球队建设情况讨论` exposed a deeper service bug:

- the Event description named Real Madrid and Barcelona, but Trigger launch
  context carried only the Event ID, start time, and title;
- Planner could read the Event, but the selected execution plan and later
  evidence bundle lost its description and public entities;
- query sanitization treated the generated `report_goal` itself as sensitive,
  removed it, and fell back to generic capability words;
- DeepSeek returned unrelated counterparty URLs with empty snippets;
- the provider accepted those URL-only results as a successful search;
- the generator produced generic contractual advice instead of grounded team
  and roster research;
- Markdown links in report prose were not rendered as links, and the mobile
  viewer blocked external navigation.

This is a contract failure across planning, scope resolution, Web Search,
generation, and presentation. It must not be addressed with scenario-specific
queries or a one-off football hotfix.

## 2. Decision Summary

All Report origins use one resumable product flow:

```text
user request / pre-event offer / other Reka Report offer
  -> create or reuse ReportGenerationRun
  -> prepare 1 recommended plan and up to 2 real alternatives
  -> show plan and explicit default scope
  -> quick-generate with safe defaults
     OR edit focus, Assets, and public-research scope
  -> freeze one validated ReportExecutionPlan
  -> run the existing Report Pipeline
  -> open the completed Report
```

The Report proposal is not a separate product for each Trigger. Origin changes
the Planner input, recommended option, and default selected Assets only. It does
not change or skip the planning contract.

The proposal page has two actions:

- primary: `按推荐方案生成` when the default scope has no blockers;
- secondary: `调整关注范围与资料`.

When a required confirmation exists, the primary action becomes a concrete
task such as `完成 1 项确认`. It is never rendered as an unexplained disabled
button.

## 3. Goals

1. Give every Report origin the same understandable plan-before-generation
   workflow.
2. Keep the default path to one confirmation tap when the recommended scope is
   safe and complete.
3. Let users add or remove attention questions and existing Assets before
   generation.
4. Make public-research entities, questions, and identity blockers visible.
5. Keep private Event and Asset context available to Planner and Generator
   without sending raw private context to Web Search.
6. Produce relevant, substantive, cited public research or truthfully report a
   degraded/failing search.
7. Preserve the existing Report templates, trusted renderer, Seedream
   illustration, suggested Todo extraction, Report container, and Pipeline
   architecture.

## 4. Non-goals

This slice does not:

- redesign Trigger scheduling, Reka offer ranking, Report container ownership,
  Report sharing, Seedream storage, or Report-to-Todo semantics;
- give the Report Generator an unrestricted Web Search tool;
- send complete Event descriptions, transcripts, contact cards, or Asset
  payloads to the Web Search provider;
- introduce a general-purpose data-room or file upload system;
- add an `all assets` bulk-select action;
- expose template IDs, field bindings, provider models, or source-quality
  scores to users;
- put a generic time-range control on every Report;
- automatically research a person merely because the person appears in an
  Event or selected Contact Asset.

## 5. Unified Product Flow

### 5.1 Entry and draft ownership

The following actions create or reuse a `ReportGenerationRun`:

- a user submits an active Report request;
- a user accepts a pre-event research offer;
- a user accepts another Reka-generated Report offer.

Opening the Report container alone still does not create a Run. An unaccepted
Trigger still does not appear as a Report draft.

One Run owns the proposal, the editable plan draft, generation, retry, and final
Report. Leaving the page or backgrounding the app preserves the current draft.
Returning does not create another Run or lose selected Assets.

### 5.2 Step 1: choose a Report plan

Planner returns one recommended option and at most two meaningful alternatives.
If only one option is justified, the UI shows one.

Each user-visible option shows:

- Report type and title;
- what the Report will answer;
- whether it uses public research;
- selected internal Asset count;
- public-research entity count;
- expected relative generation time when available;
- recommendation state.

The page preselects the recommended option. Switching options creates a draft
from that option's own default scope; it does not merge hidden fields from the
previous option.

### 5.3 Quick generation

`按推荐方案生成` is available when:

- the recommended option validates;
- every selected Asset is still owned and readable;
- required public entities have sufficient identity information;
- no person requires explicit identity resolution;
- required policy fields are complete.

The plan card displays the Assets and public-research entities summarized above
the button. Quick generation therefore means “accept the visible defaults,” not
“let the system make an invisible decision.”

A system-proposed meeting Report does not automatically add a meeting attendee
to public person research. A user request that explicitly asks to research a
person counts as research intent, but quick generation is available only if one
qualified identity can be resolved. Otherwise the primary button becomes the
identity-confirmation task.

The secondary action always opens Step 2.

### 5.4 Step 2: confirm focus and evidence

Step 2 contains only applicable sections:

1. `关注的问题`
   - Planner-proposed question chips can be removed.
   - A user can enter an additional focus in natural language.
   - The service resolves additions into typed questions and public entities;
     raw additions are never concatenated directly into a Web Search query.
2. `使用的个人资产`
   - selected Assets appear as removable chips;
   - `添加资产` opens the Asset Picker;
   - selecting a Contact uses it as private Report context only.
3. `公开调研对象`
   - organizations, products, teams, institutions, public topics, and explicitly
     requested people are shown separately from private Assets;
   - each person shows identity status and public qualifier;
   - users can remove any entity.
4. a contextual Report period only when the Report is inherently time-based.

The page does not show a generic `时间范围` row.

### 5.5 Asset Picker

The Asset Picker is a full-screen modal route with:

- search by Asset display title and safe summary fields;
- a type-filter row beginning with `全部`, followed by available Asset types;
- an always-visible `已选择 N 项` area;
- selected Asset chips with individual remove controls;
- `清空` when at least one Asset is selected;
- multi-select rows with canonical Asset-type icons, title, type, and effective
  time or creation time where applicable;
- a sticky `使用这 N 项资产` action.

`全部` means “show every Asset type.” It never means “select the entire Asset
library.” Filters do not discard selections made in another filter. Search and
pagination preserve the selected-ID set.

The service is authoritative for ownership and availability. Deleted,
unavailable, or cross-owner IDs cannot enter the plan even if a stale client
submits them.

### 5.6 Final confirmation and generation

After editing, the final screen summarizes:

- chosen Report plan;
- attention questions;
- internal Asset count and types;
- public-research entities;
- any applicable Report period;
- public research and illustration capability states.

`确认并生成` freezes one immutable `ReportExecutionPlan`. The Pipeline reads
only this frozen plan. Double taps and repeated requests return the same active
generation job.

## 6. Time Semantics

The product distinguishes three concepts:

1. **Report period** limits internal evidence for a time-based Report, such as a
   July running review. It appears only when meaningful and can be edited.
2. **Public research freshness** describes whether research needs current,
   recent, as-of-date, or historical information. Planner/Scope Resolver infers
   it and the UI displays it only when it materially changes the request.
3. **Source dates** are shown in the completed Report so users can evaluate
   recency.

Examples:

- a meeting briefing has no generic time field and defaults to the latest
  available public information;
- a July running report shows `报告周期：7 月 1 日—7 月 31 日`;
- “Kevin 过去一年的公开动态” shows `过去 12 个月` within Kevin's public
  research scope, not as a global Report time range.

## 7. Public Person Research Boundary

Public person research requires explicit user intent and at least one public
disambiguator:

- company or organization;
- professional role;
- confirmed public profile URL.

If a selected Contact has suitable company or role fields, the service may
return those safe qualifiers for the client to prefill, but private contact
fields stay local. Name-only ambiguous search is blocked.

Allowed research is limited to public professional information such as current
and previous roles, official bios, published work, public interviews, and
publicly announced projects. The system must not search for or report private
addresses, personal phone or email, family information, sensitive traits,
medical or financial data, or data-broker records.

Sources from different people must not be merged. The completed Report labels
identity ambiguity when public evidence is insufficient.

## 8. Data Contracts

### 8.1 Public research brief

Web Search accepts a typed `PublicResearchBrief`, never a `ReportEvidenceBundle`
or raw Event:

```json
{
  "entities": [
    {
      "kind": "organization",
      "display_name": "Real Madrid",
      "qualifiers": ["football club"],
      "confirmed": true
    }
  ],
  "questions": [
    "current first-team squad",
    "position structure",
    "recent squad changes"
  ],
  "freshness": {"mode": "current"},
  "source_policy": "authoritative_first"
}
```

Permitted entity kinds are `public_topic`, `organization`, `product`,
`institution`, and `person`. `person` additionally requires confirmation and a
public qualifier.

The brief excludes user IDs, Event IDs, Event start time unless publicly
relevant, participant lists, internal budgets, private opinions, complete
notes, addresses, phone numbers, emails, and Contact internal fields.

### 8.2 Plan option and draft

`ReportPlanOption` gains typed fields equivalent to:

```text
attention_questions
public_research_scope
blocking_confirmations
```

The existing `evidence_scope.asset_ids` remains the internal evidence set. A
Run stores one editable plan draft derived from the selected option. The draft
contains only IDs and bounded user additions; it does not duplicate full Asset
payloads.

Editing the draft uses one owner-scoped endpoint:

```http
PUT /api/report-generation-runs/{run_id}/plan-draft
```

The request carries the selected option ID, expected draft revision, attention
questions, bounded additional focus, selected Asset IDs, edited public scope,
and identity confirmations. The service:

1. validates option and Asset IDs;
2. resolves bounded natural-language additions into typed questions/entities;
3. returns updated public scope and blockers;
4. persists the draft and increments its revision under the same Run.

Deterministic edits such as removing a question or Asset complete in the API
request. A changed natural-language focus enqueues one
`report_scope_resolution` Workflow Job after committing the API transaction.
The Run uses existing `planning` state with `active_stage=scope_resolution`
while that job resolves typed questions and entities, then returns to
`awaiting_selection`. The client polls the existing Run detail resource.

Run detail returns `plan_draft`, `plan_revision`, and blocker state. Generate
extends its request with `expected_plan_revision`; a revision mismatch cannot
start a stale plan. There remains one Run state machine and one Planner flow.
Scope resolution is a bounded planning job, not a parallel Report workflow.

### 8.3 Execution plan

`ReportExecutionPlan` freezes:

```text
selected template and version
report goal
attention questions
resolved Asset IDs
contextual Report period
validated PublicResearchBrief
web policy
illustration policy
render policy
```

Full Event and selected Asset content are loaded internally for Generator
evidence. Only `PublicResearchBrief` crosses the Web Search provider boundary.

## 9. Scope Resolution and Privacy

The Scope Resolver is a focused planning component, not a Web Search agent. It
may read the private Planner context, selected Asset summaries, Event details,
and bounded user additions to propose a typed public brief.

It must:

- recognize explicit public entities such as Real Madrid and Barcelona from an
  Event description;
- map user questions to those entities;
- classify person entities and create a blocker when identity is incomplete;
- avoid copying sentences from private notes into query text;
- preserve relevant public names rather than adding the final public brief to a
  sensitive-string removal set;
- return no brief when public research is unnecessary.

The Report Generator may use the complete owned Event and Asset context because
it is producing the user's private Report. Web Search receives only the typed
brief. Seedream continues receiving only its existing privacy-safe decorative
summary.

## 10. Web Search Quality Contract

### 10.1 Query construction

Queries are derived from public entities, qualifiers, questions, freshness, and
source policy. They are not derived from generic capability names such as
`counterparty`, `event`, or `free_text`.

For the motivating example, acceptable queries include equivalents of:

```text
Real Madrid official current first-team squad
FC Barcelona official current first-team squad
Real Madrid Barcelona recent squad changes 2026
```

The query builder retains the existing bounded query count and length limits.
It redacts explicitly private values from the final query, but never redacts the
validated public entity or the question that it is supposed to search.

### 10.2 Accepted source

A Web source counts as accepted only when it has:

- a valid canonical `https` URL;
- a non-empty title;
- substantive cited text, a provider summary, or an answer span tied to the
  URL;
- relevance to at least one requested entity and question;
- source metadata needed by the Report citation layer.

An `open_page` URL with no cited or summarized content is not success. Search
output consisting only of unrelated URLs is not success.

`authoritative_only` requires a source that satisfies the template's authority
rules. `authoritative_first` ranks official organization pages, official public
profiles, primary publications, and direct interviews ahead of secondary
sources.

### 10.3 Failure and degradation

- `optional`: no relevant accepted sources records `failed_degraded`; the
  Report completes using owned evidence and clearly omits public claims.
- `required` or `authoritative_only`: no qualifying sources produces a
  retryable Report failure with user-facing copy that the required public
  research could not be completed.
- partial sources may support only the questions they match; the Generator must
  not generalize them to unsupported questions.

Provider errors and quality-rejection reasons are recorded as bounded
categories. Logs exclude raw Event/Asset payloads and provider response bodies.

## 11. Generation and Presentation

The Generator receives:

- the immutable execution plan;
- complete owned internal evidence;
- accepted public sources grouped by entity and question;
- warnings for unavailable Assets or degraded optional capabilities.

It must synthesize the source content into the Report rather than dump raw URLs
or generic preparation advice. A source URL alone is not evidence. Public facts
must map to accepted sources.

The existing Report readability contract remains authoritative:

- no raw `[evidence:...]` or `[source:...]` markers in visible content;
- public sources appear in one `参考来源` section with title, domain, accessed
  date, and clickable HTTPS link;
- supported Markdown links render as trusted anchors;
- the Theme V2 mobile viewer opens external HTTPS links through the platform
  browser instead of silently blocking navigation;
- suggested actions remain typed, grounded, and idempotently creatable as
  Todos;
- Seedream remains optional, privacy-safe, limited to one illustration, and
  non-fatal;
- the four deterministic Report families remain visually distinct.

## 12. Failure and Recovery

- Planner or Scope Resolver failure leaves the Run resumable and offers retry;
  it does not invent an empty default scope.
- A stale or deleted Asset is revalidated before execution. The service returns
  a scope blocker or removes it only with an explicit warning; it never loads a
  cross-owner Asset.
- An identity blocker opens only the relevant person confirmation instead of
  forcing the user through every Step 2 field.
- Repeated draft updates are idempotent by Run and revision.
- Generate freezes a draft revision. A stale generate request returns the
  current draft and blocker state rather than running an older hidden scope.
- After generation starts, scope editing is locked for that attempt. The user
  may cancel and return to the saved draft or start a new Run.
- Completed and failed Runs continue using the existing Report container,
  notification, retry, and cancellation semantics.

## 13. Verification Strategy

### 13.1 Service unit and contract tests

Cover:

- all origins producing the same plan/draft contract;
- recommended option initialization and meaningful alternatives;
- quick-generate eligibility and blocker copy;
- plan-draft ownership, Asset availability, revision, and idempotency;
- public person consent, qualifiers, ambiguous identities, and prohibited
  private fields;
- public brief construction without raw Event/Contact/Asset content;
- contextual Report period versus research freshness;
- query construction retaining public entities and excluding generic fallback;
- URL-only/empty-snippet/irrelevant results being rejected;
- source authority and question mapping;
- optional degradation and required failure;
- immutable execution-plan snapshot.

### 13.2 Root-cause regression

Use a deterministic Event fixture equivalent to:

```text
title: 球队建设情况讨论
description: 讨论球队建设情况，参考皇家马德里和巴塞罗那的阵容
```

Acceptance requires:

- Planner/Scope Resolver emits Real Madrid and Barcelona public entities;
- Web Search receives football roster questions, not `counterparty event
  free_text location`;
- unrelated contract-law URLs cannot pass the quality gate;
- Generator receives substantive accepted source content;
- final Report contains useful roster/structure information with clickable
  sources;
- the Event's private raw description is absent from the Web Search request.

### 13.3 Mobile widget tests

Cover:

- one-option and multi-option proposal states;
- primary quick-generate and secondary adjust actions;
- blocker action replacing quick generate;
- focus chip add/remove;
- Asset Picker search, all/type filters, cross-filter selections, selected chips,
  remove, clear, and sticky confirmation;
- Contact Asset selection remaining separate from public person research;
- contextual Report period appearing only when applicable;
- draft restoration after navigation or app lifecycle change;
- external source link launching.

### 13.4 Integration and real-device acceptance

Run one deterministic fake-provider E2E suite, then one bounded real DeepSeek
Web Search acceptance for the team-comparison example. Record query categories,
accepted source domains, and status without logging private context or API keys.

On the Theme V2 device build, verify:

1. user-created Report quick path;
2. user-created Report with Asset Picker edits;
3. pre-event Report with public organization research;
4. explicit qualified Kevin background research;
5. ambiguous Kevin blocker and resolution;
6. completed Report readability, actionable Todo extraction, optional
   illustration, and external source navigation.

## 14. Combined Delivery with Thinking Orbs

This design and
`2026-08-07-theme-v2-thinking-orbs-capture-status-design.md` form one delivery
round but remain separate vertical slices:

- **Report slice:** service schemas, scope resolution, search quality,
  presentation links, and Report mobile planning/Picker UI.
- **Thinking Orbs slice:** mobile capture coordinator, global top-navigation
  takeover, Session inline states, and typed capture events.

They must not share state models or make Report generation appear as a capture
task. They may share Theme V2 tokens and normal app lifecycle conventions only.

The combined implementation plan orders contract work and focused tests first,
then mobile surfaces, then proportional Docker and real-device acceptance. Each
slice remains independently reviewable and revertible. Reduced-motion and new
accessibility work for Thinking Orbs remain deferred exactly as recorded in its
approved design.

## 15. Completion Criteria

This Report slice is complete when:

- every accepted Report origin shows the same proposal contract;
- a safe recommended plan can begin with one tap;
- users can edit focus and existing Assets through the approved Picker;
- private Assets and public-research entities remain visibly and technically
  separate;
- public person research enforces explicit intent and identity qualification;
- generic time range is absent and contextual time semantics are correct;
- the team-comparison regression produces relevant, substantive, cited research;
- URL-only irrelevant search results cannot be marked successful;
- public sources render and open correctly;
- existing readability, suggested Todo, Seedream, and visual-family behavior
  continue to pass;
- the combined implementation round also satisfies the separate Thinking Orbs
  completion criteria without coupling the two architectures.
