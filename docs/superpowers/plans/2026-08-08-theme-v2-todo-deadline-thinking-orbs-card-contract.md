# Theme V2 Todo Deadline、Thinking Orbs 与 Session 卡片协议 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让所有新 Todo 都有统一的具体截止时间，让 Session 只消费最新实体卡片协议，并把顶部与 Session 的 Thinking Orbs 标准化为 A「有机编舞」视觉状态。

**Architecture:** 后端以一个纯函数 normalizer 统一 Todo deadline，再由 Asset 写入边界兜底保证业务不变量；Session 卡片由单一 contract builder 生成原始实体快照，Flutter 只负责按 render spec 与共享时间 formatter 展示。Thinking Orbs 增加独立视觉状态层，不改变 Capture 或 Agent 的后端状态机。

**Tech Stack:** Python 3.12、FastAPI、SQLAlchemy、pytest、Flutter/Dart、flutter_test、CustomPainter。

## Global Constraints

- 当前实现分支必须是 `codex/theme-v2-ui-refactor`，不得切换或构建旧版入口。
- 产品尚未上线；不迁移、不兼容旧 Session 卡片或旧测试快照。
- Todo `due_date` 是服务端写入前保证的业务不变量，不是要求用户手填的表单 required 字段。
- Todo `title` 继续是用户可见的 required 字段。
- 明确钟点优先；日期 + 时段使用时段末端；只有日期使用 18:00；无时间在当前时刻不晚于 18:00 时使用今天 18:00，否则明天 18:00。
- 时段末端固定为：凌晨 05:00、上午 11:00、中午 12:30、下午 17:00、晚上 23:00。
- 新建 Todo 一律为 `pending`；逾期只由 Reka 信号派生，只有用户显式完成才写入 `done`。
- Thinking Orbs 使用 A「有机编舞」；reduced motion 与额外无障碍动效策略暂不实施。
- 保留工作区现有改动；每个任务结束只核对本任务差异，中途不提交混有前序修改的文件。

---

### Task 1: 后端 Todo deadline 归一与写入不变量

**Files:**
- Create: `theme_v2_service/app/domains/assets/todo_deadline.py`
- Create: `theme_v2_service/tests/unit/test_todo_deadline.py`
- Modify: `theme_v2_service/app/domains/assets/service.py`
- Modify: `theme_v2_service/app/internal_mcp/tools.py`
- Modify: `theme_v2_service/app/domains/sessions/tools.py`
- Modify: `theme_v2_service/app/domains/capture/providers_legacy_flash.py`
- Modify: `theme_v2_service/app/domains/capture/pipeline.py`
- Test: `theme_v2_service/tests/integration/test_internal_mcp_tools.py`
- Test: `theme_v2_service/tests/contract/test_asset_api.py`

**Interfaces:**
- Produces: `normalize_todo_deadline(*, due_date, period, effective_at, occurred_at, reference_datetime, timezone_name) -> datetime`、`normalize_new_todo_payload(payload, *, period, effective_at, occurred_at, reference_datetime, timezone_name) -> dict[str, Any]`。
- Consumes: `due_date`、`period`、`effective_at`、可信 `reference_datetime`、产品默认时区。

- [x] **Step 1: 写纯函数表驱动失败测试**

```python
@pytest.mark.parametrize(
    ("due_date", "period", "expected"),
    [
        ("2026-08-09T15:20:00+08:00", "下午", "2026-08-09T15:20:00+08:00"),
        ("2026-08-09", "上午", "2026-08-09T11:00:00+08:00"),
        ("2026-08-09", None, "2026-08-09T18:00:00+08:00"),
        (None, "晚上", "2026-08-08T23:00:00+08:00"),
        (None, None, "2026-08-08T18:00:00+08:00"),
    ],
)
def test_normalizes_todo_deadline(due_date, period, expected):
    actual = normalize_todo_deadline(
        due_date=due_date,
        period=period,
        effective_at=None,
        occurred_at=None,
        reference_datetime=datetime(2026, 8, 8, 10, tzinfo=SHANGHAI),
        timezone_name="Asia/Shanghai",
    )
    assert actual.isoformat() == expected
```

- [x] **Step 2: 运行测试并确认因模块不存在而失败**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_todo_deadline.py -q`

Expected: FAIL，原因是 `app.domains.assets.todo_deadline` 尚不存在。

- [x] **Step 3: 实现纯 normalizer 与边界规则**

```python
PERIOD_END = {"凌晨": (5, 0), "上午": (11, 0), "中午": (12, 30), "下午": (17, 0), "晚上": (23, 0)}

def normalize_todo_deadline(*, due_date, period, effective_at, occurred_at,
                            reference_datetime, timezone_name):
    zone = ZoneInfo(timezone_name)
    reference = ensure_aware(reference_datetime, zone)
    parsed_due, due_is_date_only = parse_due_date(due_date, zone)
    if parsed_due is not None and not due_is_date_only:
        return parsed_due
    anchor = parsed_due.date() if parsed_due is not None else date_anchor(effective_at, zone)
    if anchor is not None:
        hour, minute = PERIOD_END.get(period, (18, 0))
        return datetime.combine(anchor, time(hour, minute), tzinfo=zone)
    if occurred_at is not None:
        return ensure_aware(occurred_at, zone)
    if period in PERIOD_END:
        hour, minute = PERIOD_END[period]
        candidate = datetime.combine(reference.date(), time(hour, minute), tzinfo=zone)
        return candidate if candidate >= reference else candidate + timedelta(days=1)
    cutoff = datetime.combine(reference.date(), time(18, 0), tzinfo=zone)
    return cutoff if reference <= cutoff else cutoff + timedelta(days=1)

def normalize_new_todo_payload(payload, *, period, effective_at, occurred_at,
                               reference_datetime, timezone_name):
    result = dict(payload)
    deadline = normalize_todo_deadline(
        due_date=result.get("due_date"),
        period=period,
        effective_at=effective_at,
        occurred_at=occurred_at,
        reference_datetime=reference_datetime,
        timezone_name=timezone_name,
    )
    result["due_date"] = deadline.isoformat()
    result["status"] = "pending"
    return result
```

- [x] **Step 4: 把所有写入入口接到同一边界**

在 `create_asset` 获取 `UserSkill` 后、schema 校验前，仅当 `skill.machine_name == "todo"` 时调用 `normalize_new_todo_payload`。`_create_todo` 接受由 `SessionToolExecutor` 注入、不会暴露给模型的 `reference_datetime`；硬件与上传流程从 `FlashExecutionContext.reference_datetime` 透传，普通 Chat 和手动创建使用服务端当前时间。

- [x] **Step 5: 增加 integration/contract 失败测试后实现至通过**

```python
assert created.json()["payload"]["due_date"] == "2026-08-09T18:00:00+08:00"
assert created.json()["payload"]["status"] == "pending"
assert past_created.json()["payload"]["status"] == "pending"
```

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_todo_deadline.py tests/integration/test_internal_mcp_tools.py tests/contract/test_asset_api.py -q`

Expected: PASS。

### Task 2: Flutter 共享时间格式与 Todo 专用 deadline 编辑器

**Files:**
- Create: `mobile/lib/theme_v2/foundation/theme_v2_time_formatter.dart`
- Create: `mobile/test/theme_v2/foundation/theme_v2_time_formatter_test.dart`
- Modify: `mobile/lib/render/render_spec.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_editors.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_editor.dart`
- Modify: `mobile/lib/theme_v2/asset_detail/theme_v2_asset_edit_page.dart`
- Modify: `mobile/test/theme_v2/library/asset/asset_editor_test.dart`
- Create: `mobile/test/theme_v2/asset_detail/theme_v2_todo_edit_page_test.dart`

**Interfaces:**
- Produces: `formatSessionDeadline(String, {DateTime? now})`、`defaultTodoDeadline({DateTime? now, DateTime? date})`、`TodoDeadlineField`。
- Consumes: 后端带时区 `due_date`；AssetEditorDraft 的 `setValue`。

- [x] **Step 1: 写 formatter 与默认时间失败测试**

```dart
expect(formatSessionDeadline('2026-08-08T18:00:00+08:00', now: now), '今天 18:00');
expect(formatSessionDeadline('2026-08-09T11:00:00+08:00', now: now), '明天 11:00');
expect(formatSessionDeadline('2026-08-10T17:00:00+08:00', now: now), '周一 17:00');
expect(defaultTodoDeadline(now: DateTime(2026, 8, 8, 18, 1)), DateTime(2026, 8, 9, 18));
```

Run: `flutter test test/theme_v2/foundation/theme_v2_time_formatter_test.dart`

Expected: FAIL，原因是 formatter 尚不存在。

- [x] **Step 2: 实现共享 formatter 并接入 `relative_date`**

```dart
String formatSessionDeadline(String raw, {DateTime? now}) {
  final value = parseZonedIsoToLocal(raw);
  final today = dateOnly((now ?? DateTime.now()).toLocal());
  final delta = dateOnly(value).difference(today).inDays;
  final clock = twoDigitClock(value);
  if (delta == 0) return '今天 $clock';
  if (delta == 1) return '明天 $clock';
  if (delta > 1 && delta < 7) return '${weekdayLabel(value)} $clock';
  return absoluteDateTime(value, includeYear: value.year != today.year);
}
```

- [x] **Step 3: 写 Todo 编辑器失败测试**

覆盖：Todo 字段只有 `title / due_date / content`；创建时自动填入 deadline；点击“今天”“明天”分别写入目标日 18:00；deadline 不带 required 星号；编辑已有 Todo 不重算当前值。

Run: `flutter test test/theme_v2/library/asset/asset_editor_test.dart test/theme_v2/asset_detail/theme_v2_todo_edit_page_test.dart`

Expected: FAIL，原因是当前仍使用 `due_at / notes / status` 与普通 TextField。

- [x] **Step 4: 实现专用 deadline 控件与创建默认值**

```dart
class TodoDeadlineField extends StatelessWidget {
  const TodoDeadlineField({required this.value, required this.onChanged, super.key});
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  // 显示当前值；提供“今天”“明天”“自定义”；自定义依次调用 showDatePicker/showTimePicker。
}
```

`ThemeV2AssetEditPage` 仅在 `mode == create && skillName == 'todo'` 且没有值时写入默认 `due_date`；`themeV2AssetEditorSpec('todo')` 使用中文 `title / due_date / content`，不展示 `status`。

- [x] **Step 5: 运行 Flutter 局部测试**

Run: `flutter test test/theme_v2/foundation/theme_v2_time_formatter_test.dart test/theme_v2/library/asset/asset_editor_test.dart test/theme_v2/asset_detail/theme_v2_todo_edit_page_test.dart`

Expected: PASS。

### Task 3: 服务端最新 Session 卡片 contract

**Files:**
- Create: `theme_v2_service/app/domains/sessions/card_contract.py`
- Create: `theme_v2_service/tests/unit/test_session_card_contract.py`
- Modify: `theme_v2_service/app/domains/sessions/tools.py`
- Modify: `theme_v2_service/app/domains/capture/jobs.py`
- Modify: `theme_v2_service/tests/unit/test_session_tools.py`
- Modify: `theme_v2_service/tests/integration/test_capture_jobs.py`

**Interfaces:**
- Produces: `SessionCardSource`、`build_entity_card(entity_kind, entity_id, entity, source, skill_machine_name=None)`、`cards_from_tool_result(name, result, source)`。
- Contract: `entity_kind`、`entity_id`、资产的 `skill_machine_name`、原始 `entity`、`source.session_id/input_turn_id/kind`。

- [x] **Step 1: 写严格 contract 失败测试**

```python
card = build_entity_card(
    entity_kind="asset",
    entity_id="asset-1",
    skill_machine_name="todo",
    entity={"asset_id": "asset-1", "payload": {"title": "交方案"}},
    source=SessionCardSource("session-1", "turn-1", "chat"),
)
assert set(card) == {"entity_kind", "entity_id", "skill_machine_name", "entity", "source"}
assert not ({"title", "subtitle", "icon", "accent_color", "meta_fields"} & set(card))
```

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_session_card_contract.py -q`

Expected: FAIL，原因是 contract builder 尚不存在。

- [x] **Step 2: 实现 builder 与诊断性校验**

```python
def build_entity_card(*, entity_kind, entity_id, entity, source, skill_machine_name=None):
    if entity_kind not in {"asset", "event", "contact"}:
        raise SessionCardInvalid(f"unsupported entity kind: {entity_kind}")
    if not entity_id:
        raise SessionCardInvalid("entity_id is required")
    if not isinstance(entity, dict):
        raise SessionCardInvalid("entity must be an object")
    if entity_kind == "asset" and not skill_machine_name:
        raise SessionCardInvalid("asset skill_machine_name is required")
    card = {
        "entity_kind": entity_kind,
        "entity_id": entity_id,
        "entity": dict(entity),
        "source": {
            "session_id": source.session_id,
            "input_turn_id": source.input_turn_id,
            "kind": source.kind,
        },
    }
    if entity_kind == "asset":
        card["skill_machine_name"] = skill_machine_name
    return card
```

- [x] **Step 3: Session Chat 工具改用 builder**

`SessionToolExecutor` 保存 `source_kind` 与可信上下文；`_cards_for_result` 不再输出 `asset_id/card_type/title/subtitle/icon` 顶层快照，只输出最新 contract。

- [x] **Step 4: Capture 落库改用同一个 builder**

`capture/jobs.py` 对成功的 asset/event/contact 生成同一协议并写入 `recording.result_records_json` 与 `SessionMessage.cards_json`；实体创建成功但 contract 构造失败时记录服务端诊断，不写残缺卡片。pending contact 继续走现有 pending-action UI，不伪装为实体卡片。

- [x] **Step 5: 运行后端卡片与捕捉测试**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_session_card_contract.py tests/unit/test_session_tools.py tests/integration/test_capture_jobs.py -q`

Expected: PASS。

### Task 4: Flutter 只消费最新 Session 卡片协议

**Files:**
- Modify: `mobile/lib/render/skill_card.dart`
- Modify: `mobile/lib/theme_v2/capture/capture_session_controller.dart`
- Modify: `mobile/lib/chat/chat_controller.dart`
- Modify: `mobile/test/theme_v2/capture/flash_notification_target_test.dart`
- Modify: `mobile/test/theme_v2/capture/capture_session_unified_chat_test.dart`
- Create: `mobile/test/render/session_card_contract_test.dart`

**Interfaces:**
- Consumes: Task 3 的 canonical entity card。
- Produces: 单一 `resolveSkillCardData` 与 `skillCardEntityRef` 路径，普通 Chat 与闪念 Session 共用。

- [x] **Step 1: 写 resolver 与详情路由失败测试**

```dart
final card = {
  'entity_kind': 'asset',
  'entity_id': 'todo-1',
  'skill_machine_name': 'todo',
  'entity': {'payload': {'title': '交方案', 'due_date': '2026-08-09T18:00:00+08:00'}},
  'source': {'session_id': 's1', 'input_turn_id': 't1', 'kind': 'chat'},
};
expect(resolveSkillCardData(card, specs).subtitle, '明天 18:00');
expect(skillCardEntityRef(card), const AssetEntityRef(kind: AssetEntityKind.asset, id: 'todo-1'));
```

Run: `flutter test test/render/session_card_contract_test.dart`

Expected: FAIL，因为当前 resolver 依赖旧 `card_type/asset_id/accent_color` 分支。

- [x] **Step 2: 删除实体卡片旧协议分支并实现 canonical resolver**

`resolveSkillCardData` 从 `entity` 读取 payload；asset 使用 `skill_machine_name + render spec`，event/contact 使用合成 spec；`skillCardEntityRef` 只使用 `entity_kind + entity_id`。pending-action 卡片仍在进入 resolver 前由专用组件处理。

- [x] **Step 3: 统一 Chat 与 Flash Session 恢复逻辑**

`CaptureSessionController` 不再识别 `kind/event_id/contact_id/asset_id` 或发起旧 hydration；消息恢复只保留通过 canonical shape 校验的卡片。`ChatController` 使用相同的轻量 shape 过滤函数。

- [x] **Step 4: 更新新协议 fixtures 并运行测试**

Run: `flutter test test/render/session_card_contract_test.dart test/theme_v2/capture/flash_notification_target_test.dart test/theme_v2/capture/capture_session_unified_chat_test.dart test/theme_v2/session/session_state_test.dart`

Expected: PASS；Todo 卡片不出现 ISO 字符串，event/contact/asset 均路由正确。

### Task 5: Thinking Orbs A「有机编舞」与 Light/Dark 光带

**Files:**
- Modify: `mobile/lib/theme_v2/capture/thinking_orb.dart`
- Modify: `mobile/lib/theme_v2/capture/capture_activity_top_bar.dart`
- Modify: `mobile/lib/theme_v2/session/session_analysis_block.dart`
- Modify: `mobile/lib/theme_v2/session/session_transcript.dart`
- Modify: `mobile/test/theme_v2/capture/thinking_orb_test.dart`
- Modify: `mobile/test/theme_v2/capture/capture_activity_top_bar_test.dart`
- Modify: `mobile/test/theme_v2/session/session_state_test.dart`

**Interfaces:**
- Produces: `ThinkingOrbVisualState` 十态枚举、`thinkingOrbStateForCapture`、Session Agent 状态映射、220ms morph。
- Consumes: 现有 `CaptureActivityPhase` 与 `AgentWorkPhase`，不改后端状态机。

- [x] **Step 1: 写十态 profile 与状态映射失败测试**

```dart
expect(ThinkingOrbVisualState.values, hasLength(10));
expect(thinkingOrbStateForCapture(CaptureActivityPhase.done), ThinkingOrbVisualState.success);
expect(thinkingOrbStateForAgent(AgentWorkPhase.executing), ThinkingOrbVisualState.executing);
expect(thinkingOrbProfile(ThinkingOrbVisualState.listening), isNot(thinkingOrbProfile(ThinkingOrbVisualState.transcribing)));
```

Run: `flutter test test/theme_v2/capture/thinking_orb_test.dart test/theme_v2/session/session_state_test.dart`

Expected: FAIL，因为当前只有八个 Capture phase，且 executing/composing 被折叠。

- [x] **Step 2: 实现 visual state、profile 与 220ms morph**

```dart
enum ThinkingOrbVisualState { listening, receiving, transcribing, understanding,
  executing, composing, organizing, success, empty, failed }

class ThinkingOrb extends StatefulWidget {
  const ThinkingOrb({required this.state, this.size = 32, super.key});
  final ThinkingOrbVisualState state;
  final double size;
}
```

Painter 以 profile 定义节点数量、轨道、重心、收束与失败分裂；状态变化时保存 previous/next profile，由独立 transition controller 在 220ms 内插值，循环 motion controller 继续提供呼吸与轨道运动。

- [x] **Step 3: 实现 Light/Dark 顶栏反差光带**

顶栏改为 StatefulWidget，使用约 4.8 秒往返的低速位移动画。Light 背景为冷白—浅蓝紫，光带为紫—珊瑚—暖黄；Dark 背景为蓝黑—深紫，光带为暖黄—洋红—亮青。Session 紧凑 Orb 不复制顶栏光带。

- [x] **Step 4: 让 Session 四个 Agent 状态保持独立**

`understanding / executing / composing / organizing` 一一映射到对应 visual state；顶栏继续映射 `done -> success`，终态释放逻辑不变。

- [x] **Step 5: 运行组件测试与静态分析**

Run: `flutter test test/theme_v2/capture/thinking_orb_test.dart test/theme_v2/capture/capture_activity_top_bar_test.dart test/theme_v2/session/session_state_test.dart`

Run: `flutter analyze lib/theme_v2/capture lib/theme_v2/session lib/theme_v2/library/asset lib/theme_v2/asset_detail lib/render test/theme_v2/capture test/theme_v2/session test/theme_v2/library/asset test/theme_v2/asset_detail test/render`

Expected: 测试 PASS；analyze 无 error。

### Task 6: 综合回归、Docker 重建与真机前验收

**Files:**
- Modify only if verification exposes a regression in files already listed above.

**Interfaces:**
- Consumes: Tasks 1–5 的全部产出。
- Produces: 可供 Theme V2 Docker 与真机测试的新构建。

- [x] **Step 1: 运行后端完整相关回归**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_todo_deadline.py tests/unit/test_capture_temporal.py tests/unit/test_session_card_contract.py tests/unit/test_session_tools.py tests/unit/test_capture_presenter.py tests/integration/test_internal_mcp_tools.py tests/integration/test_capture_jobs.py tests/contract/test_asset_api.py tests/contract/test_capture_api.py -q`

Expected: PASS。

- [x] **Step 2: 运行 Flutter 完整相关回归**

Run: `flutter test test/theme_v2/capture test/theme_v2/session test/theme_v2/library/asset test/theme_v2/asset_detail test/render`

Expected: PASS。

- [x] **Step 3: 检查差异与规格逐条覆盖**

Run: `git diff --check`

逐条确认：五类 deadline 输入、18:00 边界、创建状态、Todo UI、共享时间格式、canonical cards、三类详情路由、十个 Orb 状态、Light/Dark 光带。

- [x] **Step 4: 重建独立 Theme V2 Docker 并检查健康**

Run: `docker compose -f docker-compose.theme-v2.yml up -d --build api worker`

Run: `docker compose -f docker-compose.theme-v2.yml ps`

Expected: `api` 为 healthy，`worker` 为 running；不得启动旧版 compose 服务。

- [x] **Step 5: 生成 Theme V2 Android debug 构建**

Run: `flutter build apk --debug`

Expected: `build/app/outputs/flutter-apk/app-debug.apk` 生成成功。只有在用户设备已连接且解锁时才安装并执行真机验收。
