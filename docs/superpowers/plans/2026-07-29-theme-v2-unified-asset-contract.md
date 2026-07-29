# UReka Theme V2 Unified Asset Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every legacy asset-detail path with one backend-authoritative Theme V2 pipeline, add exact source-turn navigation, restore content-aware Markdown long text, and add reduced-motion-safe pinned-container wiggle.

**Architecture:** A normalized backend detail envelope is the only source for entity fields, display configuration, capabilities, and provenance. Flutter callers pass only `AssetEntityRef`; one repository, controller, sheet, full-screen state, and editor render every asset surface. Message-to-input-turn provenance is stored explicitly, Skill schemas author Markdown long text through `long: true`, and the legacy detail/editor implementation is deleted after migration.

**Tech Stack:** Flutter 3 / Dart, Material, Riverpod, FastAPI, SQLAlchemy, Alembic, MySQL, existing `ApiClient`, existing lightweight Markdown renderer, Python contract scripts, Flutter widget/golden tests, Android ADB.

## Global Constraints

- Visual truth remains `spec/design/theme-v2-library-assets-handoff.md`.
- Product and data truth remains `docs/superpowers/specs/2026-07-29-theme-v2-unified-asset-contract-design.md`.
- No production compatibility path or field-name-based long-text fallback may remain.
- All destructive reset/seed operations must be scoped to `test@1.com`.
- Every production detail caller passes stable entity kind plus ID; caller payloads are not detail truth.
- Half-sheet to full-screen expansion reuses one controller and performs no second detail fetch.
- `long: true` is valid only for `type: string` and means Markdown display plus Markdown editing.
- Source navigation uses explicit `session_id` and `input_turn_id`, never text matching or positional guessing.
- Motion respects `MediaQuery.disableAnimationsOf(context)`.
- Write each regression test first, run it red, implement the minimum behavior, then run it green.
- Preserve the user's unrelated modified and untracked specification/Pen files.

---

### Task 1: Persist Explicit Message-to-Input-Turn Provenance

**Files:**
- Create: `backend/db/migrations/versions/0030_unified_asset_provenance.py`
- Modify: `backend/db/models.py`
- Modify: `backend/core/session_service.py`
- Modify: `backend/core/flash_service.py`
- Modify: `backend/api/chat.py`
- Modify: `backend/api/sessions.py`
- Create: `backend/scripts/test_unified_asset_provenance.py`

**Interfaces:**
- Produces: `Message.input_turn_id: UUID?`
- Produces: `persist_user_message(..., input_turn_id: str) -> Message`
- Produces: Session message JSON field `input_turn_id`
- Consumes: existing `InputTurn.id`, Flash and Chat turn creation

- [ ] **Step 1: Write the failing provenance contract**

```python
async def test_user_message_keeps_exact_input_turn() -> None:
    turn = await create_input_turn_for_message(
        db, str(session.id), user_id, "第二条闪念", source="voice"
    )
    message = await persist_user_message(
        db,
        str(session.id),
        user_id,
        "第二条闪念",
        input_turn_id=str(turn.id),
    )
    assert message.input_turn_id == turn.id
```

Also assert that `GET /api/sessions/{id}/messages` serializes the same UUID for
the user message and `null` for an agent message.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
cd backend
python scripts/test_unified_asset_provenance.py
```

Expected: FAIL because `persist_user_message` does not accept
`input_turn_id` and `Message` has no corresponding column.

- [ ] **Step 3: Add the destructive development migration and model columns**

```python
def upgrade() -> None:
    op.add_column("messages", sa.Column("input_turn_id", GUID(), nullable=True))
    op.create_foreign_key(
        "fk_messages_input_turn",
        "messages",
        "input_turns",
        ["input_turn_id"],
        ["id"],
    )
    op.create_index(
        "idx_messages_input_turn",
        "messages",
        ["user_id", "input_turn_id"],
    )
    op.add_column(
        "assets",
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "contacts",
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
    )
```

Model fields use `_utcnow` for default/on-update. The test account will be
reseeded, so no legacy message-to-turn backfill is added.

- [ ] **Step 4: Persist and serialize the relation**

```python
async def persist_user_message(
    db: AsyncSession,
    session_id: str,
    user_id: str,
    user_text: str,
    *,
    input_turn_id: str,
) -> Message:
    msg = Message(
        session_id=uuid.UUID(session_id),
        input_turn_id=uuid.UUID(input_turn_id),
        user_id=user_id,
        role="user",
        text=user_text,
    )
```

Pass the freshly created turn ID from both Flash and Chat call sites. Add
`"input_turn_id": str(m.input_turn_id) if m.input_turn_id else None` to the
Session messages response.

- [ ] **Step 5: Run provenance and neighboring session tests**

Run:

```bash
cd backend
python scripts/test_unified_asset_provenance.py
python scripts/test_flash_text_terminal_status.py
python scripts/test_demo_reset.py
```

Expected: all scripts exit 0.

- [ ] **Step 6: Commit**

```bash
git add backend/db/migrations/versions/0030_unified_asset_provenance.py backend/db/models.py backend/core/session_service.py backend/core/flash_service.py backend/api/chat.py backend/api/sessions.py backend/scripts/test_unified_asset_provenance.py
git commit -m "feat(assets): persist exact input turn provenance"
```

---

### Task 2: Add the Canonical Backend Asset Detail Envelope

**Files:**
- Create: `backend/api/asset_details.py`
- Modify: `backend/main.py`
- Modify: `backend/api/assets.py`
- Modify: `backend/api/events.py`
- Modify: `backend/api/contacts.py`
- Create: `backend/scripts/test_asset_detail_contract.py`

**Interfaces:**
- Produces: `GET /api/asset-details/{kind}/{entity_id}`
- Produces: normalized `entity`, `skill`, `fields`, `values`, `display`,
  `source`, and `capabilities`
- Consumes: `Asset`, `Event`, `Contact`, `UserSkill`, `GlobalSkill`,
  `InputTurn`, and `Session`

- [ ] **Step 1: Write failing contract cases**

```python
assert manual["source"] == {
    "kind": "manual",
    "label": "手动创建",
    "session_id": None,
    "input_turn_id": None,
}
assert flash["source"]["kind"] == "flash"
assert flash["source"]["session_id"] == str(session.id)
assert flash["source"]["input_turn_id"] == str(turn.id)
assert flash["fields"][3] == {
    "id": "remark",
    "label": "备注",
    "type": "string",
    "required": False,
    "long": True,
    "order": 3,
}
```

Add cases for asset, event, contact, unknown kind, wrong-user ID, and missing
entity.

- [ ] **Step 2: Run the contract and verify RED**

Run:

```bash
cd backend
python scripts/test_asset_detail_contract.py
```

Expected: FAIL with 404 because the route does not exist.

- [ ] **Step 3: Implement one envelope serializer**

```python
class AssetDetailEnvelope(TypedDict):
    entity: dict
    skill: dict
    fields: list[dict]
    values: dict
    display: dict
    source: dict
    capabilities: dict
```

The route validates kind with:

```python
EntityKind = Literal["asset", "event", "contact"]
```

Asset fields come from `UserSkill.payload_schema` in declared order. Asset
display comes from `UserSkill.render_spec.card_display`, falling back only to
the schema's declared primary field, never a caller payload.

Event and Contact use explicit server-owned schemas in this module. Their
source is resolved by joining `source_input_turn_id -> InputTurn -> Session`.

- [ ] **Step 4: Make stale-save version authoritative**

Return `updated_at` as `entity.version`. Require update requests to include
`expected_version`; return HTTP 409 when it does not match. A successful update
returns the new version.

```python
if req.expected_version != current.updated_at.isoformat():
    raise HTTPException(status_code=409, detail="stale asset version")
```

- [ ] **Step 5: Register the router and run contract tests**

Run:

```bash
cd backend
python scripts/test_asset_detail_contract.py
python scripts/test_event_source_provenance.py
python scripts/test_event_card_contract.py
python scripts/test_event_attendee_contract.py
```

Expected: all scripts exit 0.

- [ ] **Step 6: Commit**

```bash
git add backend/api/asset_details.py backend/main.py backend/api/assets.py backend/api/events.py backend/api/contacts.py backend/scripts/test_asset_detail_contract.py
git commit -m "feat(assets): add canonical detail envelope"
```

---

### Task 3: Make Markdown Long Text a Strict Skill and Seed Contract

**Files:**
- Modify: `backend/api/skills.py`
- Modify: `backend/agents/design_agent.py`
- Modify: `backend/agents/skill_factory.py`
- Modify: `backend/db/seed.py`
- Modify: `backend/core/demo_reset.py`
- Create: `backend/scripts/seed_theme_v2_asset_contract.py`
- Create: `backend/scripts/test_skill_long_text_contract.py`

**Interfaces:**
- Produces: strict payload-field metadata `{type, label, required, long}`
- Produces: reset/seed workflow scoped to user ID resolved from `test@1.com`
- Consumes: existing Skill draft and confirm endpoints

- [ ] **Step 1: Write strict schema tests**

```python
assert validate_payload_schema({
    "remark": {
        "type": "string",
        "label": "备注",
        "required": False,
        "long": True,
    }
})["remark"]["long"] is True

with pytest.raises(ValueError):
    validate_payload_schema({
        "amount": {"type": "number", "label": "金额", "long": True}
    })

with pytest.raises(ValueError):
    validate_payload_schema({
        "remark": {"type": "string", "label": "备注"}
    })
```

Also verify draft and confirm preserve `long` without field-name backfill.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
cd backend
python scripts/test_skill_long_text_contract.py
```

Expected: FAIL because `_backfill_long` silently guesses missing metadata.

- [ ] **Step 3: Replace fallback guessing with validation**

```python
def validate_payload_schema(schema: dict) -> dict:
    validated = {}
    for order, (field_id, raw) in enumerate(schema.items()):
        field = dict(raw)
        if not isinstance(field.get("long"), bool):
            raise ValueError(f"{field_id}.long must be boolean")
        if field["long"] and field.get("type") != "string":
            raise ValueError(f"{field_id}.long requires type=string")
        field["order"] = order
        validated[field_id] = field
    return validated
```

Delete `_PROSE_KEY_HINTS` and `_backfill_long`. Strengthen the design Agent
prompt and JSON schema so every field emits an explicit boolean `long`.

- [ ] **Step 4: Add the isolated reset/seed script**

The script accepts only:

```bash
python scripts/seed_theme_v2_asset_contract.py --email test@1.com --reset
```

It rejects every other email. It creates the account when absent, resets only
that user workspace, and seeds:

- manual and Flash-linked versions of the same custom Skill;
- a three-turn Flash session whose middle turn owns a seeded asset;
- short, threshold, and overflowing text;
- Markdown headings, lists, emphasis, quote, and table;
- `宝贝饮食` with `remark.long == true`;
- Todo, Notes, Event, Contact, and another custom Skill.

- [ ] **Step 5: Run strict schema and scoped reset tests**

Run:

```bash
cd backend
python scripts/test_skill_long_text_contract.py
python scripts/test_demo_reset.py
python scripts/seed_theme_v2_asset_contract.py --email test@1.com --reset
```

Expected: tests exit 0 and the seed command prints the created entity IDs
without touching other users.

- [ ] **Step 6: Commit**

```bash
git add backend/api/skills.py backend/agents/design_agent.py backend/agents/skill_factory.py backend/db/seed.py backend/core/demo_reset.py backend/scripts/seed_theme_v2_asset_contract.py backend/scripts/test_skill_long_text_contract.py
git commit -m "feat(skills): make markdown fields explicit"
```

---

### Task 4: Build the Single Flutter Detail Model, Repository, and Launcher

**Files:**
- Create: `mobile/lib/theme_v2/asset_detail/asset_entity_ref.dart`
- Create: `mobile/lib/theme_v2/asset_detail/asset_detail_model.dart`
- Create: `mobile/lib/theme_v2/asset_detail/asset_detail_repository.dart`
- Create: `mobile/lib/theme_v2/asset_detail/open_asset_detail.dart`
- Move/Modify: `mobile/lib/theme_v2/library/asset/asset_detail_presentation.dart`
- Move/Modify: `mobile/lib/theme_v2/library/asset/asset_detail_sheet.dart`
- Test: `mobile/test/theme_v2/asset_detail/asset_detail_repository_test.dart`
- Test: `mobile/test/theme_v2/asset_detail/open_asset_detail_test.dart`

**Interfaces:**
- Produces: `AssetEntityRef(kind: AssetEntityKind, id: String)`
- Produces: `AssetDetailModel.fromJson(Map<String, dynamic>)`
- Produces: `AssetDetailRepository.load(AssetEntityRef)`
- Produces: `openAssetDetail(BuildContext, AssetEntityRef)`
- Consumes: canonical backend detail envelope

- [ ] **Step 1: Write model and repository tests**

```dart
final model = await repository.load(
  const AssetEntityRef(kind: AssetEntityKind.asset, id: 'asset-1'),
);
expect(model.fields.map((field) => field.id), ['meal', 'remark']);
expect(model.fields.last.long, isTrue);
expect(model.source.inputTurnId, 'turn-2');
expect(requests, ['GET /api/asset-details/asset/asset-1']);
```

The launcher test opens half-sheet state and verifies exactly one repository
load even after expanding.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/asset_detail/asset_detail_repository_test.dart test/theme_v2/asset_detail/open_asset_detail_test.dart
```

Expected: compile failure because the new public types do not exist.

- [ ] **Step 3: Implement immutable detail types**

```dart
enum AssetEntityKind { asset, event, contact }

@immutable
class AssetEntityRef {
  const AssetEntityRef({required this.kind, required this.id});
  final AssetEntityKind kind;
  final String id;
}
```

`AssetDetailModel` owns ordered field definitions, typed values, display,
source, capabilities, and version. It never exposes the raw response as UI
state.

- [ ] **Step 4: Implement repository and launcher**

```dart
Future<AssetDetailModel> load(AssetEntityRef ref) async {
  final response = await api.getJson(
    '/api/asset-details/${ref.kind.name}/${ref.id}',
  );
  return AssetDetailModel.fromJson(
    (response as Map).cast<String, dynamic>(),
  );
}
```

The launcher creates one controller, awaits the modal route, and disposes the
controller. The controller memoizes its load future and expansion changes
presentation only.

- [ ] **Step 5: Run new and existing detail tests**

Run:

```bash
cd mobile
flutter test test/theme_v2/asset_detail test/theme_v2/library/asset/asset_detail_test.dart
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/theme_v2/asset_detail mobile/lib/theme_v2/library/asset/asset_detail_presentation.dart mobile/lib/theme_v2/library/asset/asset_detail_sheet.dart mobile/test/theme_v2/asset_detail mobile/test/theme_v2/library/asset/asset_detail_test.dart
git commit -m "feat(theme-v2): add canonical asset detail launcher"
```

---

### Task 5: Restore Content-Aware Markdown Detail and Editing

**Files:**
- Create: `mobile/lib/theme_v2/markdown/theme_v2_markdown_text.dart`
- Create: `mobile/lib/theme_v2/asset_detail/asset_text_value.dart`
- Create: `mobile/lib/theme_v2/asset_detail/markdown_field_editor.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_detail_content.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_editor.dart`
- Modify: `mobile/lib/theme_v2/library/create_skill/skill_wizard_models.dart`
- Modify: `mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart`
- Test: `mobile/test/theme_v2/asset_detail/asset_text_value_test.dart`
- Test: `mobile/test/theme_v2/asset_detail/markdown_field_editor_test.dart`
- Modify: `mobile/test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart`

**Interfaces:**
- Produces: `AssetTextValue(text, markdown, full, onExpand)`
- Produces: `MarkdownFieldEditor(label, controller, errorText)`
- Consumes: `AssetDetailField.long`

- [ ] **Step 1: Write failing text-layout tests**

```dart
expect(
  tester.getSize(find.byKey(const ValueKey('asset-text-natural'))).height,
  lessThan(120),
);
expect(find.text('展开全文'), findsNothing);
```

For an overflowing plain string and Markdown value, assert `展开全文` exists.
After tapping it, assert the full state contains the final unique sentence,
uses natural height when short, and is capped with a local scroll region when
long.

- [ ] **Step 2: Write failing Markdown editor tests**

```dart
await tester.enterText(
  find.byKey(const ValueKey('markdown-editor-input')),
  '# 标题\n\n- 第一项',
);
await tester.tap(find.text('预览'));
expect(find.text('标题'), findsOneWidget);
expect(find.text('第一项'), findsOneWidget);
await tester.tap(find.text('编辑'));
expect(controller.text, '# 标题\n\n- 第一项');
```

Also assert Skill Builder serializes `type: string, long: true` when the user
selects `Markdown 长文本`.

- [ ] **Step 3: Run tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/asset_detail/asset_text_value_test.dart test/theme_v2/asset_detail/markdown_field_editor_test.dart test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart
```

Expected: failures for fixed 120/480 heights and missing Markdown editor type.

- [ ] **Step 4: Implement natural-height overflow behavior**

The collapsed widget measures the rendered value at actual width and text
scale. When it does not exceed six lines, return the natural content directly.
When it exceeds six lines, clip to the calculated six-line height and add fade
plus `展开全文`.

```dart
if (!overflows) {
  return KeyedSubtree(
    key: const ValueKey('asset-text-natural'),
    child: content,
  );
}
```

The full widget uses `ConstrainedBox(maxHeight: resolvedReadingHeight)` around a
selectable `SingleChildScrollView`, allowing short content to shrink-wrap.

- [ ] **Step 5: Implement the Theme V2 Markdown editor**

Use the existing Markdown grammar, moved to a Theme V2-safe renderer. The
editor has raw Edit and rendered Preview modes, no toolbar, at least nine input
lines, and preserves the same controller across mode changes.

Route `field.long == true` to `MarkdownFieldEditor`; all other fields retain
type-aware compact controls.

- [ ] **Step 6: Run text, editor, detail, and builder tests**

Run:

```bash
cd mobile
flutter test test/theme_v2/asset_detail test/theme_v2/library/asset test/theme_v2/library/create_skill
```

Expected: all tests pass with no overflow exceptions.

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/theme_v2/markdown mobile/lib/theme_v2/asset_detail mobile/lib/theme_v2/library/asset/asset_detail_content.dart mobile/lib/theme_v2/library/asset/asset_editor.dart mobile/lib/theme_v2/library/create_skill mobile/test/theme_v2/asset_detail mobile/test/theme_v2/library
git commit -m "feat(assets): restore markdown long text"
```

---

### Task 6: Focus the Exact Source Input Turn and Restore Detail on Back

**Files:**
- Modify: `mobile/lib/chat/chat_models.dart`
- Modify: `mobile/lib/chat/chat_controller.dart`
- Modify: `mobile/lib/theme_v2/session/theme_v2_session_page.dart`
- Modify: `mobile/lib/theme_v2/session/session_transcript.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_detail_content.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_detail_sheet.dart`
- Test: `mobile/test/theme_v2/session/session_source_focus_test.dart`
- Modify: `mobile/test/theme_v2/library/asset/asset_detail_test.dart`

**Interfaces:**
- Produces: `ChatMessage.inputTurnId`
- Produces: `ThemeV2SessionPage(focusedInputTurnId: String?)`
- Produces: `SessionTranscript(focusedInputTurnId: String?)`
- Consumes: normalized `AssetDetailSource`

- [ ] **Step 1: Write the failing exact-focus test**

Create three user turns and open the Session with the middle
`focusedInputTurnId`. Assert the first frame after loading calls
`Scrollable.ensureVisible` for the middle keyed row, not the transcript tail,
and renders `session-focused-turn-turn-2`.

- [ ] **Step 2: Write the failing source navigation test**

Open a full-screen Asset Detail at a non-zero scroll position, tap
`来自闪念`, pop the Session route, and assert:

```dart
expect(controller.presentation, AssetDetailPresentationKind.fullPage);
expect(controller.scrollController.offset, closeTo(savedOffset, 1));
```

For manual source, assert no chevron, button semantics, or route push.

- [ ] **Step 3: Run tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/session/session_source_focus_test.dart test/theme_v2/library/asset/asset_detail_test.dart
```

Expected: failures because messages discard `input_turn_id` and source rows do
not navigate.

- [ ] **Step 4: Parse and render the explicit focus target**

```dart
ChatMessage.user(
  m['id'] as String,
  m['text'] as String? ?? '',
  inputTurnId: m['input_turn_id'] as String?,
);
```

SessionTranscript owns a `GlobalKey` per visible input-turn ID, scrolls the
requested key to alignment `0.5` once, and applies a 420 ms accent-soft
highlight. Reduced Motion uses a static highlight with zero transition.

- [ ] **Step 5: Push Session above the preserved detail route**

Only sources with both session and input-turn IDs are interactive:

```dart
await Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => ThemeV2SessionPage(
      boundSessionId: source.sessionId,
      focusedInputTurnId: source.inputTurnId,
    ),
  ),
);
```

Do not pop or recreate the Asset Detail route.

- [ ] **Step 6: Run Session and detail tests**

Run:

```bash
cd mobile
flutter test test/theme_v2/session test/theme_v2/library/asset/asset_detail_test.dart
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/chat/chat_models.dart mobile/lib/chat/chat_controller.dart mobile/lib/theme_v2/session mobile/lib/theme_v2/library/asset/asset_detail_content.dart mobile/lib/theme_v2/library/asset/asset_detail_sheet.dart mobile/test/theme_v2/session mobile/test/theme_v2/library/asset/asset_detail_test.dart
git commit -m "feat(assets): navigate to exact source turn"
```

---

### Task 7: Migrate Every Caller and Delete the Legacy Detail Chain

**Files:**
- Modify: `mobile/lib/app_events.dart`
- Modify: `mobile/lib/pages/calendar_page.dart`
- Modify: `mobile/lib/pages/notifications_page.dart`
- Modify: `mobile/lib/render/skill_card.dart`
- Modify: `mobile/lib/today/bubble_pool.dart`
- Modify: `mobile/lib/today/next_action.dart`
- Modify: `mobile/lib/theme_v2/library/theme_v2_library_page.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_list_page.dart`
- Create: `mobile/lib/theme_v2/asset_detail/theme_v2_asset_edit_page.dart`
- Modify: `mobile/lib/pages/create_asset.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_editor_router.dart`
- Delete: `mobile/lib/render/asset_detail_sheet.dart`
- Create: `mobile/test/theme_v2/asset_detail/asset_detail_entry_points_test.dart`

**Interfaces:**
- Consumes: `openAssetDetail(context, AssetEntityRef)`
- Produces: `ThemeV2AssetEditPage(reference, initialValues, mode)`
- Produces: no production `showAssetDetail` or `showThemeV2AssetDetail`

- [ ] **Step 1: Write a source-level migration guard**

The test scans `mobile/lib` and fails when production files contain:

```dart
const forbidden = [
  'showAssetDetail(',
  'showThemeV2AssetDetail(',
  "render/asset_detail_sheet.dart",
];
```

Exclude the migration guard file itself. Also assert every known entry-point
file imports `open_asset_detail.dart`.

- [ ] **Step 2: Run the guard and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/asset_detail/asset_detail_entry_points_test.dart
```

Expected: FAIL and list every legacy caller.

- [ ] **Step 3: Replace caller payload assembly with stable references**

Examples:

```dart
openAssetDetail(
  context,
  AssetEntityRef(kind: AssetEntityKind.asset, id: assetId),
);
```

Calendar events use `AssetEntityKind.event`; contacts use
`AssetEntityKind.contact`. A missing stable ID disables the open action rather
than showing a non-canonical detail.

- [ ] **Step 4: Move still-valid create/editor primitives**

Move Markdown editing to the new Theme V2 component from Task 5. Route create
flows through the current Skill schema/editor services without importing the
legacy detail file. Keep dedicated system entity editors as required by the
handoff.

The replacement route is explicit:

```dart
enum AssetEditMode { create, update }

class ThemeV2AssetEditPage extends StatelessWidget {
  const ThemeV2AssetEditPage({
    super.key,
    required this.reference,
    required this.initialValues,
    required this.mode,
  });

  final AssetEntityRef reference;
  final Map<String, dynamic> initialValues;
  final AssetEditMode mode;
}
```

Create mode loads the canonical Skill schema before building the draft and
POSTs a new asset. Update mode uses the model/version already owned by the
detail controller. Event and Contact remain routed to their dedicated editors,
but those editors consume the same normalized field values and Markdown
component.

- [ ] **Step 5: Delete the legacy renderer and run the migration guard**

Run:

```bash
cd mobile
flutter test test/theme_v2/asset_detail/asset_detail_entry_points_test.dart
rg -n "showAssetDetail|showThemeV2AssetDetail|render/asset_detail_sheet.dart" lib
```

Expected: test passes and `rg` returns no production matches.

- [ ] **Step 6: Run consumer regression suites**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar test/theme_v2/library test/theme_v2/session test/asset_source_test.dart test/event_attendees_test.dart
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add mobile/lib mobile/test/theme_v2/asset_detail mobile/test
git commit -m "refactor(assets): remove legacy detail pipeline"
```

---

### Task 8: Add Reduced-Motion-Safe Pinned Container Wiggle

**Files:**
- Modify: `mobile/lib/theme_v2/library/library_components.dart`
- Modify: `mobile/lib/theme_v2/library/pinned_configuration.dart`
- Modify: `mobile/test/theme_v2/library/library_components_test.dart`
- Modify: `mobile/test/theme_v2/library/library_navigation_test.dart`

**Interfaces:**
- Produces: `PinnedTileWiggle(active, phase, child)`
- Consumes: configuration-mode state and `MediaQuery.disableAnimationsOf`

- [ ] **Step 1: Write failing motion tests**

Assert configuration mode creates a repeating transform with rotation no
greater than ±0.6 degrees and translation no greater than 1 px. Assert normal
mode has identity transform. With `disableAnimations: true`, assert identity
transform and no active ticker.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/library/library_components_test.dart test/theme_v2/library/library_navigation_test.dart
```

Expected: FAIL because configure mode has no wiggle animation.

- [ ] **Step 3: Implement staggered micro-motion**

Each tile derives phase from its index. Use one repeating controller owned by
the mosaic/configuration surface, not one controller per tile:

```dart
final radians = math.sin((value + phase) * math.pi * 2) * (0.6 * math.pi / 180);
final dy = math.cos((value + phase) * math.pi * 2) * 1.0;
```

Dragging passes `active: false` for that tile. Leaving configuration disposes
the controller.

- [ ] **Step 4: Run motion and navigation tests**

Run:

```bash
cd mobile
flutter test test/theme_v2/library/library_components_test.dart test/theme_v2/library/library_navigation_test.dart
```

Expected: all tests pass and Flutter reports no leaked tickers.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/library/library_components.dart mobile/lib/theme_v2/library/pinned_configuration.dart mobile/test/theme_v2/library/library_components_test.dart mobile/test/theme_v2/library/library_navigation_test.dart
git commit -m "feat(library): add pinned container wiggle"
```

---

### Task 9: Full Verification, Test-Account Reset, and Android QA

**Files:**
- Modify only if verification exposes defects in files already owned by Tasks
  1–8.

**Interfaces:**
- Consumes: all previous tasks
- Produces: fresh automated and Android evidence

- [ ] **Step 1: Apply migrations and reseed `test@1.com`**

Run:

```bash
docker compose up -d --wait db backend
docker compose exec backend alembic upgrade head
docker compose exec backend python scripts/seed_theme_v2_asset_contract.py --email test@1.com --reset
```

Expected: healthy services, migration at head, and a printed seed manifest.

- [ ] **Step 2: Run backend contract regression**

Run:

```bash
cd backend
python scripts/test_unified_asset_provenance.py
python scripts/test_asset_detail_contract.py
python scripts/test_skill_long_text_contract.py
python scripts/test_demo_reset.py
python scripts/test_event_source_provenance.py
python scripts/test_todo_surface_contract.py
```

Expected: every script exits 0.

- [ ] **Step 3: Run Flutter analysis and regression**

Run:

```bash
cd mobile
flutter analyze lib/theme_v2 lib/render lib/today lib/pages lib/chat
flutter test test/theme_v2/asset_detail test/theme_v2/library test/theme_v2/calendar test/theme_v2/session
flutter test test/asset_source_test.dart test/event_attendees_test.dart
```

Expected: analyzer reports no issues and all tests pass.

- [ ] **Step 4: Build and install the Theme V2 Android APK**

Run:

```bash
cd mobile
flutter build apk --debug --dart-define=THEME_V2=true
/Users/admin/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
/Users/admin/Library/Android/sdk/platform-tools/adb -s RFCY71B21YK reverse tcp:8000 tcp:8000
```

Expected: build exits 0, install reports `Success`, reverse is active.

- [ ] **Step 5: Validate identical detail from every surface**

Using `test@1.com`, open the seeded asset from Library, Calendar Flow,
Calendar Month/Day, Today, and Session. Capture screenshots and UI trees.
Compare:

- entity ID;
- Skill and primary value;
- ordered fields and values;
- source label and clickability;
- half-sheet geometry;
- full-screen content;
- edit/delete capabilities.

Expected: no visible or semantic differences.

- [ ] **Step 6: Validate source, Markdown, and motion**

- Open the Flash-linked asset and tap `来自闪念`.
- Verify the middle seeded turn is centered/highlighted.
- Press Back and confirm detail expansion plus scroll are preserved.
- Verify manual source has no navigation semantics.
- Verify `宝贝饮食.备注` has natural short height, working overflow expansion,
  full Markdown reading, and Edit/Preview editing.
- Long-press a pinned container, verify micro-wiggle and reorder.
- Enable Android Reduce Motion and verify the wiggle is absent.

- [ ] **Step 7: Prove legacy removal and repository cleanliness**

Run:

```bash
rg -n "showAssetDetail|showThemeV2AssetDetail|render/asset_detail_sheet.dart|_PROSE_KEY_HINTS|_backfill_long" mobile/lib backend
git diff --check
git status --short
```

Expected: no production legacy matches, no whitespace errors, and only the
user's pre-existing unrelated spec/Pen changes remain.

- [ ] **Step 8: Commit a verification defect only after its own red-green cycle**

For each defect found in Steps 1–7, first add a focused regression to the
owning test file, run that test to reproduce the failure, patch the owning
production file, and rerun the same test green. Stage exactly those two paths
with an explicit `git add path/to/test.dart path/to/source.dart` or
`git add backend/scripts/test_contract.py backend/path/to/source.py`, then
commit:

```bash
git commit -m "fix(assets): close unified detail verification gap"
```

Skip this step when verification required no code changes.
