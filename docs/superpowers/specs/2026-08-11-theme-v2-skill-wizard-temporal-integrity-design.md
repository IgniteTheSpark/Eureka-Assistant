# Theme V2 Skill Wizard and Temporal Integrity Design

## Goal

Make custom Skill configuration understandable without invented preview data,
and make Flash scheduling preserve one product contract from natural language
through persistence and Session rendering:

- a single time point, date, or undated action is a Todo;
- a complete time span, duration, or all-day block is an Event;
- explicit and contextual time meaning is preserved without silently forcing an
  ambiguous clock into the morning;
- database timestamps cross API and Session-card boundaries as explicit UTC.

This is a contract repair across existing boundaries, not a phrase-specific
hotfix. No rule may depend on names or places from the reported recording.

## Evidence and Root Causes

The capture recorded as
`196df0e4-a25d-405f-8727-48be8eccbb33` contains four valid ASR clauses. Its
persisted execution trace shows four separate failures in the current contract:

1. A single-point lunch at noon was accepted as an Event and received an
   invented one-hour end time because the deterministic normalizer does not
   enforce the Dispatcher single-point rule for built-in Event intents.
2. The complete range `两点到两点半` was correctly sent to Event execution, but
   the trusted temporal parser only recognizes Arabic digits. MCP rejected the
   write three times, after which the pipeline fell back to a Todo at the
   default 18:00 deadline.
3. The complete range `4点到6点` was re-anchored by the trusted layer to
   04:00–06:00. The parser treated an unqualified clock as an explicit morning
   clock instead of preserving its AM/PM ambiguity and the surrounding
   afternoon context.
4. Internal MCP serialized UTC-naive database values without a `Z` suffix.
   Flutter therefore interpreted Session-card Event timestamps as local time,
   producing an additional eight-hour display error.

The Skill Wizard preview issue has a separate source: the controller fabricates
field-specific sample values such as a dance venue or book-note content. These
values look like user data even though they are only placeholders.

## Product Rules

### Todo and Event Shape

- A scheduled create with one clock, one date, a fuzzy period, or no temporal
  expression is a Todo.
- A scheduled create with an explicit start and end, a start plus duration, or
  an all-day expression is an Event.
- The rule is semantic-shape based. Words such as `开会`, `吃饭`, `约`, or a
  person's name do not decide the entity type.
- A newly created Todo whose normalized deadline is earlier than the trusted
  capture reference time is created as `completed`.
- Equality with the reference time is not overdue and remains `pending`.

### Trusted Time Interpretation

- The temporal parser accepts Arabic and common Chinese clock numerals,
  including `两/二`, `十`, `十一`, `十二`, `半`, and common range separators
  `到`, `-`, `~`, `—`, and `－`.
- An explicit day period controls AM/PM. For example, `下午四点` is 16:00 and
  `早上四点` is 04:00.
- Adjacent scheduling clauses may inherit the most recent explicit date and day
  period from the same transcript. In `下午一点到一点半……两点到两点半……四点到六点`,
  the later ranges remain in the afternoon.
- A bare 1–11 clock is an AM/PM candidate, not proof of morning. If no explicit
  or inherited day period exists, choose the closest reasonable interval on the
  resolved date relative to the trusted capture reference; never default to
  early morning merely because the numeric hour is below 12.
- The trusted layer validates and canonicalizes source-supported facts. It must
  not overwrite a model-proposed time with a different AM/PM interpretation
  when the source remains ambiguous.
- Model-provided dates and clocks outside the source-supported candidates are
  rejected before mutation.

## Architecture

### One Temporal Shape Boundary

Extend the existing capture temporal module instead of adding a second parser.
It exposes a source-derived scheduling shape and time candidates used by both
intent normalization and MCP mutation validation:

- `point`: Todo-compatible;
- `range`: Event-compatible;
- `duration`: Event-compatible;
- `all_day`: Event-compatible;
- `none`: Todo-compatible.

The Dispatcher remains the semantic classifier, but deterministic normalization
enforces this structural result before a sub-agent runs. This prevents a
single-point Event from reaching Event execution and prevents a complete range
from being silently persisted as a Todo.

### Transcript Context

The provider derives trusted temporal context from the full transcript before
parallel intent execution. Each intent receives only its source slice plus the
resolved date/day-period context applicable at that slice. The context travels
through the existing `InternalMCPTrustedContext`; it is not exposed in model
tool schemas and cannot be supplied or overwritten by the model.

MCP Event creation uses that trusted context to validate the Agent's proposed
start/end values. Failure remains explicit. A valid source range must not fall
back to Todo merely because one spelling of its clock was unsupported.

### Timestamp Serialization

Internal MCP serializes ORM timestamps with the same UTC-`Z` helper already used
by the public Asset, Session, and Capture APIs. This applies to Event start/end
and entity created/updated timestamps placed in canonical Session cards.

The Flutter date parser also treats a timezone-less canonical Session Event
timestamp as UTC. This is defense in depth for currently stored test cards;
new server responses always include `Z`.

## Skill Wizard Interaction

The visible flow remains Describe → Fields → Card.

### Clarification Questions

- Question 1 is a single-select pill group for recording scope.
- Question 2 is a multi-select pill group for information the user wants to
  retain.
- Both groups append an `其他` pill.
- Selecting `其他` reveals an inline text input for that question. Deselecting
  it clears its custom answer.
- The content question options are generated from the user's Skill goal and
  normalized to two through five concise, non-technical labels.
- The submitted answer remains one string per question for API compatibility:
  selected labels and optional custom text are joined in stable display order.
- The Wizard cannot generate fields until the single-select scope and at least
  one content option are selected.

### Card Preview

- Preview demonstrates layout and field selection, not fabricated user data.
- The Skill name remains the card title.
- The primary and enabled secondary slots display localized field labels only,
  such as `舞种`, `时长`, `地点`, and `感受`.
- Date, number, boolean, and text fields follow the same label-only rule.
- Renaming or adding a field updates the preview and selector immediately.
- The initial Card step still selects one primary field and up to three
  secondary fields.

## Failure Handling

- Invalid or empty generated pill options are replaced with bounded,
  goal-relevant defaults; technical keys are never shown.
- Selecting `其他` without text leaves that answer incomplete and shows an
  inline validation message.
- A source range that cannot be resolved produces one failed intent card; it
  does not silently create a default-time Todo.
- Timestamp serialization never emits a timezone-less datetime for a canonical
  Session entity.
- Existing incorrectly persisted entities are not rewritten automatically.
  They remain explicit test artifacts unless a separate data-repair operation
  is authorized.

## Testing

### Deterministic Backend Tests

- single point with meeting or meal semantics → Todo;
- no temporal expression → Todo with the existing default deadline;
- Arabic and Chinese numeral ranges → Event;
- start plus duration and all-day expressions → Event;
- explicit morning/afternoon markers;
- inherited day period across adjacent clauses;
- ambiguous bare clock around the trusted reference time;
- past Todo deadline → `completed`, equality → `pending`;
- MCP accepts source-supported Chinese ranges and rejects hallucinated times;
- internal MCP Event/card timestamps end in `Z`.

### Mobile Tests

- first question renders single-select pills plus `其他`;
- second question renders multi-select pills plus `其他`;
- each `其他` field appears only while selected and is validated;
- selected answers are submitted in stable order;
- Card preview shows labels rather than provider sample values;
- renamed and added fields update the label-only preview;
- one primary and three secondary defaults remain selected;
- canonical Session Event UTC timestamps render in local time.

### Live and Device Acceptance

- Run sanitized natural-language DeepSeek cases for single points, Chinese
  numeral ranges, and ambiguous afternoon ranges.
- On Theme V2 device, create a draft Skill without submitting it and verify both
  pill groups, `其他`, and label-only Card preview.
- Submit a new hardware Flash containing a single point and two complete ranges;
  verify Todo/Event types, persisted times, Calendar placement, and Session card
  display agree.

## Acceptance Criteria

- A single-point meal or meeting never creates an Event.
- `两点到两点半` creates an Event rather than falling back to a default Todo.
- An afternoon-context `4点到6点` persists and displays as 16:00–18:00.
- Session, Calendar, and detail surfaces display the same local Event time.
- Newly created already-overdue Todos are immediately completed.
- Skill Wizard uses single-select and multi-select pills with functional
  `其他` inputs.
- Skill Card preview contains no invented user values.
