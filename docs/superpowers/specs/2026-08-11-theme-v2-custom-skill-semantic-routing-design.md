# Theme V2 Custom Skill Semantic Routing Design

## Goal

Make custom Skill creation confirm what the user intends to record, generate a
hidden semantic routing profile, and prove with live DeepSeek evaluations that
natural Chinese utterances route to the intended enabled Skill.

## Product Rules

- Users describe what they want to record in ordinary language.
- When the description leaves a material ambiguity, the designer returns one
  compact confirmation group before generating fields: a choice question for
  the recording boundary and a text question for the information the user
  wants to retain.
- Neither question exposes technical schema details.
  For example, `喝水记录` asks whether the Skill covers plain water only or all
  non-alcoholic drinks.
- A sufficiently specific description can proceed directly to the editable
  field step.
- Field labels, descriptions, and types remain editable. Machine keys remain an
  internal implementation detail.
- Generated fields stay optional for Agent capture.

## Hidden Routing Profile

The designer generates a compact `routing_profile` alongside the draft:

```json
{
  "intent": "记录用户实际喝下的白水",
  "aliases": ["喝水", "饮水", "补水"],
  "include": ["白水", "矿泉水", "纯净水"],
  "exclude": ["咖啡", "茶", "牛奶", "酒", "购买水", "提醒喝水"],
  "positive_examples": ["刚喝了500毫升水"],
  "negative_examples": ["买矿泉水花了6块", "提醒我晚上喝水"]
}
```

The mobile client carries this profile through confirmation but does not render
it as editable technical UI. The API stores it at JSON Schema root key
`x-routing`; this avoids a database migration while keeping it distinct from
captured payload fields.

Normalization limits every list and string, removes empty and duplicate values,
and never trusts provider output as executable configuration.

## Runtime Routing

At request time, the Dispatcher receives only enabled Skills. Each custom entry
is rendered as a readable catalog containing stable ID, display name, purpose,
localized field meaning, aliases, include/exclude boundaries, and a few positive
and negative examples.

DeepSeek performs semantic selection. Deterministic code then validates the
returned stable Skill ID and prevents custom Skills from stealing structural
built-ins:

- future actions remain Todo/Event;
- purchases remain Expense even when the purchased object resembles a custom
  record;
- custom Skills outrank Notes and may correct a Todo classification only when
  the source is clearly a completed historical fact;
- ambiguous custom candidates fall back to Notes rather than guessing.

Deterministic phrase matching remains a bounded recovery layer, not the primary
semantic engine.

## Wizard Flow

The visible flow remains three stages: Describe, Fields, Card.

1. Describe: the user enters the recording goal. The first design request may
   return the scope and recording-content questions inside the same stage.
2. Fields: after the answer, the Agent generates editable labels, descriptions,
   types, sample data, and the hidden routing profile.
3. Card: the existing real-data preview and display selector are used before
   creating the Skill.

The primary action copy reflects whether the user is confirming scope or
generating fields. Technical routing metadata and field keys are not shown.

## Live Semantic Evaluation

Two different gates remain separate:

1. Deterministic structural stress tests verify concurrency, caps, partial
   failure, ordering, and idempotency with controlled provider output.
2. Live DeepSeek behavior evaluations seed isolated custom Skills and assert the
   exact operation, machine name, stable Skill ID, intent count, and built-in
   boundary for natural Chinese input.

The live suite covers plain-water scope, running, dance, tennis, future-action
negatives, purchase/reminder negatives, mixed multi-intent input, update,
delete, query, and Notes fallback. It repeats cases so model instability is
visible instead of being hidden by one successful run.

The connected-device acceptance retains the exact failed transcript from
recording `e4f4226d-c9e7-4502-ab1e-3d36622de79d` as a regression case.

## Failure Handling

- A malformed designer response returns a bounded 502 and creates no Skill.
- A designer provider outage returns 503 and keeps the user's description and
  answers in the Wizard.
- A clarification response is capped at two questions: one choice with two or
  three options and one text answer for desired recording content. If the
  provider omits the content question, the service adds the stable product
  question.
- Missing or invalid routing metadata does not block Skill creation; the normal
  display name, description, and field catalog remain valid routing context.
- Live evaluation failures identify the exact utterance, expected route, and
  actual structured output.

## Acceptance Criteria

- `跳舞记录` triggers a goal/scope clarification before field generation.
- `喝水记录` can confirm plain-water-only versus broader beverage scope.
- Confirmed Skills persist normalized `x-routing` metadata without displaying
  it in the Wizard.
- Dispatcher prompts present readable routing semantics rather than an opaque
  JSON Schema dump.
- Unit and widget tests cover clarification, hidden metadata transport, and
  field/card compatibility.
- A live DeepSeek suite asserts concrete Skill routes for the reviewed natural
  language matrix.
