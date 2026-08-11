# Theme V2 Skill Wizard and Temporal Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Skill creation use understandable single/multi-select clarification and label-only card previews, while making Flash scheduling preserve Todo/Event shape, Chinese clock ranges, contextual AM/PM, and explicit UTC through Session rendering.

**Architecture:** Extend the existing capture temporal boundary so normalization and trusted MCP mutation share the same source-derived scheduling facts. Carry only resolved transcript date/day-period context in `InternalMCPTrustedContext`, keep it invisible to model schemas, serialize canonical timestamps as UTC `Z`, and retain a Flutter parsing guard for old timezone-less Session cards. Keep the Wizard API compatible by submitting one stable string per question while maintaining structured selection state inside the controller.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy, FastMCP, pytest, Flutter/Dart, flutter_test.

## Global Constraints

- Do not add phrase-, person-, company-, or venue-specific rules.
- Do not add a second temporal parser; extend `app.domains.capture.temporal`.
- A single time point, date, fuzzy period, or no time is Todo-compatible; a range, duration, or all-day expression is Event-compatible.
- A newly created Todo is completed only when its normalized deadline is strictly earlier than the trusted capture reference; equality remains pending.
- Trusted temporal context is server-derived, model-invisible, and cannot be overwritten by tool arguments.
- Existing incorrectly stored test entities are not mutated by this implementation.
- Skill preview displays localized field labels only and never fabricates values.
- Preserve the existing default of one primary field and at most three secondary fields.

---

## File Map

- `theme_v2_service/app/domains/assets/skill_design.py`: normalize two generated clarification questions into single/multiple choice contracts.
- `theme_v2_service/app/domains/capture/temporal.py`: parse scheduling shape, Chinese clocks, ranges, explicit periods, and inherited transcript context.
- `theme_v2_service/app/domains/capture/intent_normalizer.py`: deterministically enforce built-in Todo/Event shape before tool execution.
- `theme_v2_service/app/domains/capture/providers_legacy_flash.py`: derive per-intent trusted context from the full transcript.
- `theme_v2_service/app/domains/sessions/tools.py`: carry trusted temporal context into Internal MCP calls.
- `theme_v2_service/app/internal_mcp/runtime.py`, `contracts.py`, `server.py`, `tools.py`: inject model-invisible temporal context, validate Event clocks, and emit UTC `Z` timestamps.
- `mobile/lib/theme_v2/library/create_skill/skill_wizard_controller.dart`: maintain single/multi/other selection state and label-only preview payload.
- `mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart`: render pill groups and conditional Other inputs.
- `mobile/lib/render/render_spec.dart`: interpret timezone-less canonical Event values as legacy UTC.
- Focused backend and Flutter tests listed in each task lock the contract before implementation.

### Task 1: Normalize Skill clarification contracts

**Files:**
- Modify: `theme_v2_service/tests/unit/test_skill_design.py`
- Modify: `theme_v2_service/app/domains/assets/skill_design.py`

**Interfaces:**
- Consumes: provider JSON `questions[*]` and the existing `design_skill_step(description, answers)` API.
- Produces: normalized question dictionaries with `type: "choice"`, `multiple: bool`, two-to-five concise `options`, and stable keys `recording_scope` / `recording_content`.

- [ ] **Step 1: Write failing backend question-contract tests**

```python
def test_scope_and_content_are_single_and_multiple_choice_questions():
    result = _normalize_design_step(
        {"questions": [
            {"key": "recording_scope", "prompt": "主要记录什么？", "type": "choice", "options": ["训练", "课程"]},
            {"key": "recording_content", "prompt": "保留哪些内容？", "type": "text", "options": []},
        ]},
        "跳舞记录",
    )
    scope, content = result["questions"]
    assert scope["type"] == "choice" and scope["multiple"] is False
    assert content["type"] == "choice" and content["multiple"] is True
    assert 2 <= len(content["options"]) <= 5


def test_question_options_are_bounded_and_do_not_contain_other():
    result = _normalize_design_step(
        {"questions": [
            {"key": "recording_scope", "prompt": "主要记录什么？", "type": "choice", "options": ["训练", "课程", "比赛", "其他"]},
        ]},
        "跳舞记录",
    )
    assert result["questions"][0]["options"] == ["训练", "课程", "比赛"]
    assert result["questions"][1]["key"] == "recording_content"
    assert result["questions"][1]["multiple"] is True
```

- [ ] **Step 2: Run the tests and confirm RED**

Run: `cd theme_v2_service && pytest tests/unit/test_skill_design.py -q`

Expected: FAIL because content remains a text question and `multiple` is absent.

- [ ] **Step 3: Implement normalized choice metadata and provider prompt**

```python
def _recording_content_question(options=None) -> dict:
    normalized = _bounded_unique_strings(options, limit=5, max_length=80)
    if len(normalized) < 2:
        normalized = ["类型", "时长", "地点", "感受"]
    return {
        "key": "recording_content",
        "prompt": "每次记录时，你最想保留哪些内容？",
        "type": "choice",
        "multiple": True,
        "options": normalized,
        "placeholder": "请输入其他想记录的内容",
    }
```

Normalize scope to `multiple: False`, content to `multiple: True`, remove provider-returned `其他`, cap scope at three and content at five, and update the LiteLLM system prompt to request both choice groups.

- [ ] **Step 4: Run the focused backend tests and confirm GREEN**

Run: `cd theme_v2_service && pytest tests/unit/test_skill_design.py -q`

Expected: all tests pass.

### Task 2: Add structured Wizard selection and label-only preview

**Files:**
- Modify: `mobile/test/theme_v2/library/create_skill/skill_wizard_controller_test.dart`
- Modify: `mobile/lib/theme_v2/library/create_skill/skill_wizard_controller.dart`

**Interfaces:**
- Consumes: `SkillWizardQuestion.multiple` from Task 1.
- Produces: `toggleQuestionOption`, `toggleQuestionOther`, `setQuestionOtherText`, `selectedOptionsFor`, `isOtherSelected`, and stable string answers submitted through the existing repository body.

- [ ] **Step 1: Write failing controller tests**

```dart
test('single and multiple answers serialize in stable option order', () async {
  controller.toggleQuestionOption('recording_scope', '训练');
  controller.toggleQuestionOption('recording_scope', '比赛');
  controller.toggleQuestionOption('recording_content', '地点');
  controller.toggleQuestionOption('recording_content', '时长');
  controller.toggleQuestionOther('recording_content');
  controller.setQuestionOtherText('recording_content', '音乐');

  expect(controller.answerFor('recording_scope'), '比赛');
  expect(controller.answerFor('recording_content'), '时长、地点、音乐');
});

test('label-only preview ignores provider and generated sample values', () async {
  await createDraftWithSamplePayload({'dance_style': 'Hip-hop', 'venue': '舞社 A'});
  expect(controller.samplePayload['dance_style'], '舞种');
  expect(controller.samplePayload['venue'], '地点');
  final added = controller.addField(label: '章节');
  expect(controller.samplePayload[added.key], '章节');
});
```

- [ ] **Step 2: Run the controller tests and confirm RED**

Run: `cd mobile && flutter test test/theme_v2/library/create_skill/skill_wizard_controller_test.dart`

Expected: FAIL because structured selection APIs are absent and preview still contains fabricated values.

- [ ] **Step 3: Implement structured answer state and label-only payload**

```dart
final Map<String, Set<String>> _selectedOptions = {};
final Set<String> _otherSelected = {};
final Map<String, String> _otherText = {};

String _composeAnswer(SkillWizardQuestion question) {
  final selected = _selectedOptions[question.key] ?? const <String>{};
  final ordered = [for (final option in question.options) if (selected.contains(option)) option];
  final custom = _otherSelected.contains(question.key) ? (_otherText[question.key] ?? '').trim() : '';
  if (custom.isNotEmpty) ordered.add(custom);
  return ordered.join('、');
}

dynamic _previewValue(SkillDraftField field) {
  final label = field.label.trim();
  return label.isEmpty ? '字段' : label;
}
```

Single-select toggles replace the prior option; multi-select toggles preserve provider option order. Deselecting Other clears its text. Validation rejects Other without text and rejects content with no selected option. During draft initialization, replace every provider sample value with `_previewValue(field)`.

- [ ] **Step 4: Run controller tests and confirm GREEN**

Run: `cd mobile && flutter test test/theme_v2/library/create_skill/skill_wizard_controller_test.dart`

Expected: all tests pass.

### Task 3: Render single/multi pills and conditional Other input

**Files:**
- Modify: `mobile/test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart`
- Modify: `mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart`

**Interfaces:**
- Consumes: structured selection state and methods from Task 2.
- Produces: one pill group per question, an appended `其他` pill, conditional keyed text fields, and inline validation through the controller.

- [ ] **Step 1: Write failing widget tests**

```dart
testWidgets('scope is single-select and content is multi-select with Other', (tester) async {
  await openClarificationStep(tester);
  expect(find.text('其他'), findsNWidgets(2));
  await tester.tap(find.text('训练'));
  await tester.tap(find.text('比赛'));
  expect(controller.selectedOptionsFor('recording_scope'), {'比赛'});
  await tester.tap(find.text('时长'));
  await tester.tap(find.text('地点'));
  expect(controller.selectedOptionsFor('recording_content'), {'时长', '地点'});
});

testWidgets('Other requires text and clears it when deselected', (tester) async {
  await openClarificationStep(tester);
  await tester.tap(find.byKey(const ValueKey('skill-question-other-recording_content')));
  expect(find.byKey(const ValueKey('skill-question-other-input-recording_content')), findsOneWidget);
  expect(await controller.generate(), isFalse);
  expect(controller.errorMessage, contains('其他'));
});
```

- [ ] **Step 2: Run the widget tests and confirm RED**

Run: `cd mobile && flutter test test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart`

Expected: FAIL because content is still a free-text input and Other has no state.

- [ ] **Step 3: Replace `_ClarificationQuestion` with controller-backed pills**

```dart
Wrap(
  spacing: ThemeV2Spacing.sm,
  runSpacing: ThemeV2Spacing.sm,
  children: [
    for (final option in question.options)
      _SuggestionChip(
        label: option,
        selected: controller.selectedOptionsFor(question.key).contains(option),
        onPressed: () => controller.toggleQuestionOption(question.key, option),
      ),
    _SuggestionChip(
      key: ValueKey('skill-question-other-${question.key}'),
      label: '其他',
      selected: controller.isOtherSelected(question.key),
      onPressed: () => controller.toggleQuestionOther(question.key),
    ),
  ],
)
```

Render the keyed Other `TextFormField` only while selected and route its text to `setQuestionOtherText`.

- [ ] **Step 4: Run Wizard tests and confirm GREEN**

Run: `cd mobile && flutter test test/theme_v2/library/create_skill/skill_wizard_controller_test.dart test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart`

Expected: all tests pass.

### Task 4: Parse scheduling shape and contextual Chinese clock ranges

**Files:**
- Modify: `theme_v2_service/tests/unit/test_capture_temporal.py`
- Modify: `theme_v2_service/app/domains/capture/temporal.py`

**Interfaces:**
- Produces: `ScheduleShape` values `point`, `range`, `duration`, `all_day`, `none`; `CaptureTemporalContext(anchor_date, period)`; source-supported start/end candidates on `CaptureTemporalHints`; and `temporal_contexts_for_intents(transcript, source_texts, reference_datetime)`.
- Consumes: trusted capture reference datetime and ordered atomic source slices.

- [ ] **Step 1: Write failing temporal tests**

```python
def test_chinese_numeral_range_is_an_afternoon_event():
    hints = extract_temporal_hints(
        "两点到两点半要见投资人",
        datetime(2026, 8, 11, 13, 40, tzinfo=SHANGHAI),
        inherited_period="下午",
    )
    assert hints.shape == "range"
    assert hints.start_at == datetime(2026, 8, 11, 14, 0, tzinfo=SHANGHAI)
    assert hints.end_at == datetime(2026, 8, 11, 14, 30, tzinfo=SHANGHAI)


def test_adjacent_clauses_inherit_the_latest_explicit_period():
    contexts = temporal_contexts_for_intents(
        "下午一点到一点半复盘，然后两点到两点半见面，然后4点到6点周会",
        ["下午一点到一点半复盘", "两点到两点半见面", "4点到6点周会"],
        REFERENCE,
    )
    assert [item.period for item in contexts] == ["下午", "下午", "下午"]


def test_bare_clock_keeps_am_pm_candidates_instead_of_forcing_morning():
    hints = extract_temporal_hints("4点到6点周会", REFERENCE)
    assert hints.shape == "range"
    assert hints.start_at is None
    assert {candidate.hour for candidate in hints.start_candidates} == {4, 16}
```

```python
@pytest.mark.parametrize(("source", "shape"), [
    ("中午12点吃饭", "point"),
    ("两点到两点半见面", "range"),
    ("四点开始开两个小时会", "duration"),
    ("明天全天团建", "all_day"),
])
def test_schedule_shapes(source, shape):
    assert extract_temporal_hints(source, REFERENCE).shape == shape


def test_explicit_period_and_chinese_half_are_canonical():
    morning = extract_temporal_hints("上午四点", REFERENCE)
    afternoon = extract_temporal_hints("下午四点", REFERENCE)
    half = extract_temporal_hints("下午十点半", REFERENCE)
    assert morning.occurred_at.hour == 4
    assert afternoon.occurred_at.hour == 16
    assert (half.occurred_at.hour, half.occurred_at.minute) == (22, 30)
```

- [ ] **Step 2: Run temporal tests and confirm RED**

Run: `cd theme_v2_service && pytest tests/unit/test_capture_temporal.py -q`

Expected: FAIL because Chinese numerals, shape, candidates, and inherited context are absent.

- [ ] **Step 3: Implement one source-derived temporal parser**

```python
ScheduleShape = Literal["point", "range", "duration", "all_day", "none"]

@dataclass(frozen=True)
class CaptureTemporalContext:
    anchor_date: date | None = None
    period: str | None = None

@dataclass(frozen=True)
class CaptureTemporalHints:
    anchor_date: date | None = None
    period: str | None = None
    occurred_at: datetime | None = None
    shape: ScheduleShape = "none"
    start_at: datetime | None = None
    end_at: datetime | None = None
    start_candidates: tuple[datetime, ...] = ()
    end_candidates: tuple[datetime, ...] = ()
```

Implement a bounded Chinese clock-number decoder for `一` through `十二`, support `半`, parse start/end pairs and start-plus-duration, preserve ambiguous 1–11 as AM/PM candidates, resolve explicit/inherited periods first, and derive context for each intent from the transcript prefix without modifying provenance text.

- [ ] **Step 4: Run temporal tests and confirm GREEN**

Run: `cd theme_v2_service && pytest tests/unit/test_capture_temporal.py -q`

Expected: all tests pass.

### Task 5: Enforce Todo/Event shape before execution

**Files:**
- Modify: `theme_v2_service/tests/unit/test_flash_intent_normalizer.py`
- Modify: `theme_v2_service/app/domains/capture/intent_normalizer.py`

**Interfaces:**
- Consumes: `schedule_shape(source_text)` from Task 4.
- Produces: normalized built-in creates where point/date/fuzzy/none are Todo and range/duration/all-day are Event.

- [ ] **Step 1: Write failing shape-normalization tests**

```python
@pytest.mark.parametrize("source", [
    "今天中午12点和张总吃饭",
    "明天和张总吃饭",
    "和张总吃饭",
])
def test_single_point_date_or_undated_action_is_todo(source):
    result = normalize_intents([FlashIntent(type="event", source_text=source)], custom_skill_names=set())
    assert result[0].type == "todo"


@pytest.mark.parametrize("source", [
    "两点到两点半见投资人",
    "下午四点开始开两个小时周会",
    "明天全天团建",
])
def test_range_duration_or_all_day_is_event(source):
    result = normalize_intents([FlashIntent(type="todo", source_text=source)], custom_skill_names=set())
    assert result[0].type == "event"
```

- [ ] **Step 2: Run normalizer tests and confirm RED**

Run: `cd theme_v2_service && pytest tests/unit/test_flash_intent_normalizer.py -q`

Expected: FAIL because built-in Event/Todo model output is not structurally corrected.

- [ ] **Step 3: Add deterministic scheduled-create shape enforcement**

```python
def _normalize_scheduled_builtin(intent: FlashIntent) -> FlashIntent:
    if intent.operation != "create" or intent.type not in {"todo", "event"}:
        return intent
    shape = schedule_shape(intent.source_text)
    expected = "event" if shape in {"range", "duration", "all_day"} else "todo"
    return intent.model_copy(update={"type": expected, "custom_skill_id": None})
```

Apply this after canonical operation inference and before custom scheduled normalization. Reuse `schedule_shape`; remove duplicate range-shape regexes once no tests depend on them.

- [ ] **Step 4: Run normalizer and semantic-evaluation tests and confirm GREEN**

Run: `cd theme_v2_service && pytest tests/unit/test_flash_intent_normalizer.py tests/unit/test_capture_semantic_eval_cases.py -q`

Expected: all tests pass.

### Task 6: Carry trusted transcript context and validate Event mutations

**Files:**
- Modify: `theme_v2_service/tests/unit/test_internal_mcp_runtime.py`
- Modify: `theme_v2_service/tests/unit/test_internal_mcp_contracts.py`
- Modify: `theme_v2_service/tests/integration/test_internal_mcp_tools.py`
- Modify: `theme_v2_service/app/domains/capture/providers_legacy_flash.py`
- Modify: `theme_v2_service/app/domains/sessions/tools.py`
- Modify: `theme_v2_service/app/internal_mcp/runtime.py`
- Modify: `theme_v2_service/app/internal_mcp/contracts.py`
- Modify: `theme_v2_service/app/internal_mcp/server.py`
- Modify: `theme_v2_service/app/internal_mcp/tools.py`

**Interfaces:**
- Consumes: per-intent `CaptureTemporalContext` and source candidates from Task 4.
- Produces: trusted arguments `source_anchor_date` and `source_period`, hidden from model schemas, and source-supported Event start/end persisted as UTC.

- [ ] **Step 1: Write failing trusted-context and Event tests**

```python
def test_runtime_injects_temporal_context_and_strips_model_spoofing():
    trusted = InternalMCPTrustedContext(
        user_id="owner",
        source_text="4点到6点周会",
        source_anchor_date=date(2026, 8, 11),
        source_period="下午",
    )
    result = InternalMCPRuntime._trusted_arguments(
        "tool_create_event",
        {"source_period": "上午"},
        trusted,
    )
    assert result["source_period"] == "下午"
    assert result["source_anchor_date"] == "2026-08-11"


async def test_create_event_accepts_chinese_range_and_rejects_hallucinated_clock(session):
    accepted = await execute_tool(
        "tool_create_event",
        {"title": "会面", "start_at": "2026-08-11T14:00:00+08:00", "end_at": "2026-08-11T14:30:00+08:00"},
        context=await _context(),
        reference_datetime="2026-08-11T13:40:00+08:00",
        source_text="两点到两点半见投资人",
        source_period="下午",
    )
    assert accepted["ok"] is True
    assert accepted["event"]["start_at"].endswith("Z")
```

```python
async def test_create_event_rejects_clock_outside_source_candidates(session):
    result = await execute_tool(
        "tool_create_event",
        {"title": "会面", "start_at": "2026-08-11T09:00:00+08:00", "end_at": "2026-08-11T09:30:00+08:00"},
        context=await _context(),
        reference_datetime="2026-08-11T13:40:00+08:00",
        source_text="两点到两点半见面",
        source_period="下午",
    )
    assert result["ok"] is False
    assert result["error_code"] == "source_time_mismatch"


async def test_create_event_inherits_afternoon_for_bare_range(session):
    result = await execute_tool(
        "tool_create_event",
        {"title": "周会", "start_at": "2026-08-11T16:00:00+08:00", "end_at": "2026-08-11T18:00:00+08:00"},
        context=await _context(),
        reference_datetime="2026-08-11T13:40:00+08:00",
        source_text="4点到6点周会",
        source_period="下午",
    )
    assert result["event"]["start_at"] == "2026-08-11T08:00:00Z"
    assert result["event"]["end_at"] == "2026-08-11T10:00:00Z"
```

- [ ] **Step 2: Run the focused MCP tests and confirm RED**

Run: `cd theme_v2_service && pytest tests/unit/test_internal_mcp_runtime.py tests/unit/test_internal_mcp_contracts.py tests/integration/test_internal_mcp_tools.py -q`

Expected: FAIL because temporal context fields are absent, Chinese ranges are rejected, and serialized datetimes lack `Z`.

- [ ] **Step 3: Implement trusted context propagation and candidate validation**

```python
@dataclass(frozen=True)
class InternalMCPTrustedContext:
    user_id: str
    # existing fields remain unchanged
    source_anchor_date: date | None = None
    source_period: str | None = None
```

Add both names to trusted contract injection for temporal tools and transport signatures, never to visible schema parameters. The provider computes ordered contexts once from the full transcript and gives each `SessionToolExecutor` the matching anchor/period. `_create_event` accepts only a model interval matching a source candidate, canonicalizes an unambiguous or context-resolved source range, and returns an explicit source-time error instead of a Todo fallback for a valid range.

Use one serializer for ORM values:

```python
def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    aware = value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)
    return aware.isoformat().replace("+00:00", "Z")
```

- [ ] **Step 4: Run MCP, capture-provider, and contract tests and confirm GREEN**

Run: `cd theme_v2_service && pytest tests/unit/test_internal_mcp_runtime.py tests/unit/test_internal_mcp_contracts.py tests/integration/test_internal_mcp_tools.py tests/unit/test_capture_agent.py tests/unit/test_session_card_contract.py -q`

Expected: all tests pass.

### Task 7: Render canonical Session Event time consistently on Flutter

**Files:**
- Modify: `mobile/test/render/session_card_contract_test.dart`
- Modify: `mobile/lib/render/render_spec.dart`

**Interfaces:**
- Consumes: canonical UTC `Z` timestamps from Task 6 and old timezone-less UTC test-card timestamps.
- Produces: local `HH:mm–HH:mm` Session Event subtitles without an eight-hour shift.

- [ ] **Step 1: Write a failing legacy UTC defense test**

```dart
test('timezone-less canonical event timestamps are interpreted as UTC', () {
  final event = card(
    kind: 'event',
    id: 'event-utc',
    entity: {
      'event_id': 'event-utc',
      'title': '周会',
      'start_at': '2026-08-11T08:00:00',
      'end_at': '2026-08-11T10:00:00',
    },
  );
  final data = resolveSkillCardData(event, const {});
  expect(data.subtitle, '16:00–18:00');
});
```

Run this test with `TZ=Asia/Shanghai` in the Flutter test environment so the expected local conversion is deterministic.

- [ ] **Step 2: Run the test and confirm RED**

Run: `cd mobile && TZ=Asia/Shanghai flutter test test/render/session_card_contract_test.dart`

Expected: FAIL with `08:00–10:00`.

- [ ] **Step 3: Add the narrow parsing guard**

```dart
DateTime? _eventDate(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  var parsed = DateTime.tryParse(raw.replaceAll('Z', '+00:00'));
  if (parsed == null) return null;
  final hasZone = raw.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
  if (!hasZone) {
    parsed = DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute, parsed.second, parsed.millisecond, parsed.microsecond);
  }
  return parsed.toLocal();
}
```

- [ ] **Step 4: Run Session-card tests and confirm GREEN**

Run: `cd mobile && TZ=Asia/Shanghai flutter test test/render/session_card_contract_test.dart`

Expected: all tests pass.

### Task 8: Integrated regression and Theme V2 device acceptance

**Files:**
- Modify only if a regression reveals a defect inside the files already listed above.

**Interfaces:**
- Consumes: Tasks 1–7.
- Produces: verified backend and mobile build suitable for real-device acceptance.

- [ ] **Step 1: Run the focused backend suite**

Run: `cd theme_v2_service && pytest tests/unit/test_skill_design.py tests/unit/test_capture_temporal.py tests/unit/test_flash_intent_normalizer.py tests/unit/test_internal_mcp_runtime.py tests/unit/test_internal_mcp_contracts.py tests/integration/test_internal_mcp_tools.py tests/unit/test_capture_semantic_eval_cases.py tests/unit/test_session_card_contract.py -q`

Expected: all tests pass with no xfail added for the new contracts.

- [ ] **Step 2: Run the focused Flutter suite and analyzer**

Run: `cd mobile && flutter test test/theme_v2/library/create_skill/skill_wizard_controller_test.dart test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart test/render/session_card_contract_test.dart`

Run: `cd mobile && flutter analyze lib/theme_v2/library/create_skill/skill_wizard_controller.dart lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart lib/render/render_spec.dart`

Expected: tests pass and analyzer reports no issues.

- [ ] **Step 3: Run sanitized live-model semantic cases**

Use generic, non-private synthetic text for: one point meal, Chinese-numeral range, adjacent afternoon ranges, and an undated action. Verify normalized types and tool arguments without sending the user's real transcript or names to the external model.

Expected: point/undated cases route to Todo; ranges route to Event; inherited afternoon remains 16:00–18:00.

- [ ] **Step 4: Build and install only Theme V2**

Run: `cd mobile && flutter build apk --debug --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=THEME_V2_ENABLED=true`

Install `mobile/build/app/outputs/flutter-apk/app-debug.apk`, restore the existing device reverse from `tcp:8000` to the Theme V2 host API on `tcp:8100`, force-stop `com.eureka.mindapp`, and launch it.

Expected: the Theme V2 Today shell opens; no legacy build is installed.

- [ ] **Step 5: Complete device acceptance**

Verify a new Skill draft shows single-select scope, multi-select content, two Other inputs, label-only preview, one primary, and up to three secondary fields. Then record a new sanitized Flash with one time point and two ranges; verify Todo/Event type, persisted time, Calendar placement, and Session-card time all agree.

Expected: every acceptance criterion in `docs/superpowers/specs/2026-08-11-theme-v2-skill-wizard-temporal-integrity-design.md` passes.
