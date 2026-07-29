# UReka Theme V2 Unified Asset Contract Design

**Status:** Approved for implementation  
**Date:** 2026-07-29  
**Scope:** Mobile, backend, database, Agent/Skill Builder, test data  
**Visual source:** `spec/design/theme-v2-library-assets-handoff.md`

## 1. Decision

Theme V2 Asset Detail is not a compatibility skin over the legacy asset
implementation. It becomes the only production asset-detail path.

The implementation will:

- replace every legacy Asset Detail entry point;
- make entity identity, schema, display configuration, and provenance explicit
  backend contracts;
- make Markdown long text an explicit Skill capability;
- support exact navigation from an asset to its originating input turn;
- delete superseded mobile detail, editor, fallback, and field-guessing logic
  after every caller has migrated;
- reset isolated test data instead of supporting legacy records.

There are no real users and no production user data. Validation will use the
isolated account `test@1.com`; its data may be deleted and reseeded freely.

## 2. Why the Current Implementation Drifts

The app currently has two Asset Detail implementations:

- Theme V2 Library opens `showThemeV2AssetDetail`;
- Calendar, Today, Session, notifications, and legacy Library paths still open
  `showAssetDetail`.

Those entry points also construct different combinations of `CardData`,
payload snapshots, `RenderSpec`, entity type, source session, and IDs. Sharing
only the visible widget would therefore still allow the same asset to show
different content.

The current Theme V2 long-text path has two additional defects:

- a custom field is foldable only when its incoming schema already marks it as
  `long`;
- the half and full layouts reserve fixed heights, so short content leaves
  unexplained whitespace while an unclassified long value may be clipped
  without an expansion affordance.

The legacy editor contains a Markdown editor, but the Theme V2 editor replaced
it with a generic multiline `TextField`.

## 3. Source-of-Truth Boundaries

The sources of truth are deliberately separated:

| Concern | Source of truth |
|---|---|
| Visual geometry, Light/Dark, sheet behavior | `theme-v2-library-assets-handoff.md` |
| Asset identity, schema, values, display, provenance | Unified backend detail contract |
| Long-text editing semantics | Skill payload schema |
| Exact originating turn | Database provenance relation |
| Card title and secondary fields | Saved `CardDisplayConfig` |
| Client rendering | One Theme V2 Asset Detail component tree |

Caller-provided payloads are temporary launch snapshots only. They may support
an immediate loading frame, but they never override the canonical response.

## 4. Unified Detail Architecture

### 4.1 One public mobile entry point

Every surface calls one API:

```dart
Future<void> openAssetDetail(
  BuildContext context,
  AssetEntityRef reference,
)
```

`AssetEntityRef` contains only stable identity:

```dart
class AssetEntityRef {
  final AssetEntityKind kind;
  final String id;
}
```

Supported kinds are asset, event, contact, and task-backed asset. Calendar,
Today, Library, Session cards, notifications, and future consumers may not
construct their own detail payload or choose a separate detail widget.

### 4.2 Canonical repository

The launcher resolves the reference through `AssetDetailRepository`. The
repository returns one normalized `AssetDetailModel` containing:

- entity kind and ID;
- Skill identity and display name;
- icon and Card Display configuration;
- ordered field definitions;
- typed values;
- editable and deletable capabilities;
- source/provenance;
- version or update timestamp used to reject stale saves.

System entities may remain in their existing database tables. The repository
and backend detail endpoint normalize them into the same response shape; this
project does not require moving Events or Contacts into the `assets` table.

### 4.3 One presentation state

The same controller and widget instance own:

- hydration;
- half-sheet/full-screen presentation;
- scroll position;
- edit draft;
- source navigation;
- save and delete state.

Expanding to full screen changes presentation state only. It does not push a
second detail route, rebuild from a second payload, or fetch the entity again.

## 5. Backend Detail Contract

The backend exposes a normalized detail envelope:

```json
{
  "entity": {
    "kind": "asset",
    "id": "uuid",
    "version": "updated-at-or-revision"
  },
  "skill": {
    "id": "uuid",
    "machine_name": "baby_meal",
    "display_name": "宝贝饮食",
    "icon": "..."
  },
  "fields": [
    {
      "id": "remark",
      "label": "备注",
      "type": "string",
      "required": false,
      "long": true,
      "order": 4
    }
  ],
  "values": {
    "remark": "Markdown text"
  },
  "display": {
    "primary_field_id": "meal",
    "secondary_field_ids": ["time", "amount"]
  },
  "source": {
    "kind": "flash",
    "label": "来自闪念",
    "session_id": "uuid",
    "input_turn_id": "uuid"
  },
  "capabilities": {
    "editable": true,
    "deletable": true
  }
}
```

Source kinds are:

- `manual`: static source row, no navigation;
- `flash`: navigates to the exact input turn in a Flash session;
- `session`: navigates to the exact input turn in another Agent session.

An entity with missing or invalid provenance must not pretend to be clickable.
It renders a static source label and records a diagnostic event.

## 6. Provenance and Exact Input-Turn Navigation

`session_id` alone is insufficient because one Flash session may contain many
input turns. Text matching and “the nth user message” are also not acceptable
production contracts.

The database and API will maintain an explicit relation between the user
message shown in a Session transcript and its `InputTurn`:

- user messages created from a turn persist that turn ID;
- the Session messages API returns `input_turn_id`;
- the mobile `ChatMessage` model preserves it;
- transcript rows expose a stable key by input-turn ID.

When the user taps a navigable source:

1. keep the current Asset Detail route and controller in the navigation stack;
2. push the Theme V2 Session route with `focusedInputTurnId`;
3. load the requested session;
4. scroll the matching input turn to the middle of the viewport;
5. apply a short, accessible highlight pulse;
6. on Back, restore the original Asset Detail presentation and scroll state.

Reduced Motion removes the pulse animation but retains a static highlight long
enough to establish location.

## 7. Text Display Contract

Every string value uses content-aware layout. Display folding does not depend
on the field being marked `long`.

### 7.1 Short content

- Height equals the rendered content height.
- No fixed 120 px placeholder is reserved.
- No border is added merely to explain unused space because unused space no
  longer exists.

### 7.2 Overflowing content

- Measure the actual rendered content at the available width and text scale.
- Half sheet shows approximately five to six lines.
- Only real overflow adds the fade and `展开全文`.
- The control announces the field label and expansion result.

### 7.3 Full-screen content

- Full screen displays the complete value.
- Content shorter than the reading limit keeps its natural height.
- Content exceeding the reading limit uses a dedicated selectable scroll
  region, with a target maximum of 480 px at the 411 × 960 reference viewport.
- Expanding does not trigger a second detail fetch.

Fields declared as long text render Markdown. Other overflowing strings retain
plain selectable text semantics.

## 8. Markdown Long-Text Contract

Long text remains stored as a string. The schema marks the capability:

```json
{
  "type": "string",
  "long": true
}
```

`long: true` has one unambiguous product meaning:

- detail mode renders Markdown and supports folding;
- edit mode uses the Markdown editor;
- Card Display may still select the field, but cards always show a plain,
  single-line excerpt.

The editor provides:

- a large multiline input;
- `编辑 / 预览` modes;
- direct Markdown syntax entry;
- headings, emphasis, inline code, lists, quotes, callouts, and existing table
  rendering;
- no formatting toolbar;
- keyboard-safe scrolling and reachable Save action.

Short strings keep the compact, type-aware editor.

## 9. Skill Builder and Agent Contract

Long text is authored, not guessed by the client.

Skill Builder Fields must visibly distinguish:

- short text;
- Markdown long text;
- number;
- date/time;
- boolean;
- enum/list types already supported by the product.

Selecting Markdown long text writes `type: string` plus `long: true`.

The Skill Builder draft Agent must set `long: true` for semantic document
fields such as body, notes, remark, description, reflection, or other content
expected to span paragraphs. Backend validation rejects `long: true` on
non-string fields and preserves the flag through confirmation.

The mobile client will not keep a field-name compatibility list. If the Agent
or Builder produces the wrong field capability, that is a schema-generation
defect and must fail contract tests instead of being hidden by UI guesses.

## 10. Pinned-Container Long-Press Motion

Long-pressing a pinned container enters configuration mode. While that mode is
active:

- tiles use staggered micro-rotation around ±0.6 degrees;
- translation remains within 1 px;
- timing differs slightly per tile to avoid synchronized mechanical motion;
- the dragged tile stops its idle wiggle;
- tap targets, labels, ordering controls, and drag semantics remain stable;
- leaving configuration disposes all animation controllers.

With Reduce Motion enabled, continuous wiggle is disabled. Configuration mode
uses the existing border and surface treatment only.

## 11. Data Reset and Seed Strategy

Implementation and validation use `test@1.com`.

The workflow may:

- create the account if it does not exist;
- delete all data owned by that account;
- apply destructive development migrations when required;
- reseed system Skills, custom Skills, assets, Flash sessions, input turns, and
  messages;
- repeat reset and seed during automated and real-device validation.

The seed must include:

- the same asset opened from Library, Calendar, Today, and Session;
- a manual asset with a static source;
- a Flash-created asset linked to a non-final input turn;
- short text, exactly-at-threshold text, and overflowing text;
- Markdown with headings, lists, emphasis, quotes, and a table;
- a custom `宝贝饮食` Skill with a Markdown `备注` field;
- system assets and at least one additional custom Skill.

No other account may be deleted or mutated by reset tooling.

## 12. Legacy Removal

Removal is part of completion, not a later cleanup:

- migrate all `showAssetDetail` callers;
- delete the legacy Asset Detail renderer;
- move any still-valid generic Markdown renderer into a shared Theme V2-safe
  location;
- delete the legacy full-page asset editor after its required behaviors have
  moved;
- delete caller-side CardData/detail-payload assembly;
- delete field-name-based long-text guessing;
- remove the rollout branch that can still select the old Asset Detail path.

Repository search must show no production imports or calls to the removed
detail entry point.

## 13. Error Handling

- A detail-load failure keeps the sheet open and offers Retry.
- A missing entity renders a terminal not-found state and a Close action.
- A stale save is rejected and offers Reload; it must not silently overwrite a
  newer value.
- A missing source session or input turn renders a non-navigable source row
  with feedback instead of opening an unrelated Session.
- Source navigation load failure returns to the preserved detail state.
- Save and delete disable duplicate submissions.

## 14. Verification

### Contract tests

- detail envelope is identical regardless of consumer;
- every seeded Flash asset has valid session and input-turn provenance;
- every persisted turn-backed user message exposes the same input-turn ID;
- Markdown field metadata survives draft, confirmation, create, fetch, edit,
  and refetch;
- manual sources are non-navigable.

### Flutter tests

- all callers use the single launcher;
- the same reference produces the same detail field order and layout;
- short text takes natural height;
- real overflow alone displays `展开全文`;
- full-screen reading exposes the complete Markdown content;
- Markdown editor switches between Edit and Preview without losing text;
- source navigation focuses the exact turn and Back restores detail state;
- wiggle starts only in configuration mode and respects Reduce Motion.

### End-to-end validation

On the connected Android device and `test@1.com`:

1. open one seeded asset from Library, Calendar Flow, Calendar Month/Day,
   Today, and Session;
2. compare content, field order, layout, source, and actions;
3. navigate from the Flash source to a non-final input turn and return;
4. verify short, long, and Markdown fields in half, full, edit, and preview
   states;
5. long-press a pinned container, reorder it, and verify motion plus persisted
   order;
6. repeat the motion check with Reduce Motion enabled.

## 15. Completion Criteria

This project is complete only when:

- every app entry point opens the same Theme V2 Asset Detail pipeline;
- the canonical response, not caller data, determines displayed content;
- source navigation lands on the exact input turn;
- short text has no artificial whitespace;
- overflowing text always exposes a working full-content path;
- long-text editing supports Markdown Edit/Preview;
- pinned containers provide the approved micro-wiggle;
- the isolated account can be reset and reseeded reproducibly;
- legacy Asset Detail and editor production code has been removed;
- automated and Android real-device verification pass.
