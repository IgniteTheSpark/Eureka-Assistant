# Eureka Assistant Review — 第三轮复审

审阅时间：2026-06-05 15:43-15:55

背景：用户又基于第二轮 findings 修复一轮。本轮重点验证第二轮遗留项是否真正闭合，并检查修复引入的新边界问题。

## Findings

### P1: Chat context chip rail 修复不完整，切换会话/新对话会残留旧上下文

第二轮的“历史会话恢复 context assets”后端和 controller 数据层已经补上，但 `ChatPage` 的本地 `_context` 仍是独立状态，只在 `_context.isEmpty && _chat.contextAssets.isNotEmpty` 时 seed 一次。

这会导致两个可复现边界：

1. 从一个带 context chips 的会话切到另一个会话时，如果 `_context` 已非空，新会话的 `contextAssets` 不会覆盖旧 chips。
2. 在 drawer 点“新对话”只调用 `widget.chat.reset()`，没有清空页面本地 `_context`；`ChatController.reset()` 也没有清空 `contextAssets`。UI 仍显示旧上下文，但新 session 实际没有这些 context。

这是一个状态一致性问题：用户看到的上下文 chips 和后端真正用于 prompt 的 session context 可能不一致。

Relevant files:

- `mobile/lib/pages/chat_page.dart`
- `mobile/lib/chat/chat_controller.dart`

Recommendation:

- 把 context chips 的单一真相移进 `ChatController.contextAssets`，`ChatPage` 直接渲染 controller 状态；
- 或至少在 `loadSession()` 后用新 `contextAssets` 全量 replace `_context`，并在 `reset()` / 新对话时同时 clear `_context` 和 `contextAssets`。

### P1: Chat tool history / RecentEntityIndex 仍是唯一未决架构项

`persist_chat_turn()` 已支持 `tool_call` / `tool_result` 参数，但 `/api/chat` 持久化时仍只传 `cards`，不传工具调用历史。

这和 `chat.py` 文件头部注释、`_format_history()` 里的 tool-call 分支、以及 assistant prompt 里“最近 tool_call/tool_result rows”的假设不一致。当前跨轮“刚刚那个”主要靠 `session_assets_hint` / `session_context_hint`，不是完整 tool history。

这不一定要按“持久化每个 tool event”修，但需要明确二选一：

1. 持久化 tool call/result rows，让 history contract 成立；
2. 删除 tool-history 假设，建立显式 `SessionIndex` / `RecentEntityIndex`，把 “recent entities” 作为确定性上下文输入。

Relevant files:

- `backend/api/chat.py`
- `backend/core/session_service.py`
- `backend/agents/assistant.py`

Recommendation:

- 如果短期优先稳定，建议选 `SessionIndex` / `RecentEntityIndex`。因为 chat/flash/report 都已经更像“确定性索引 + LLM 决策”，比把完整 ADK event 历史塞回 prompt 更省 token、更 general。

## 已确认闭合的第二轮项

### AgentRunner plural tool events 已修

`backend/core/agent_runner.py` 已改用 `event_tool_calls()` / `event_tool_results()`，并用 pending FIFO 以 name 配对结果；`flash-multi` eval 也通过。

### Report `spec_json.domain` 已修

`backend/agents/report_pipeline.py` 的持久化 `spec` 已包含 normalized `domain`，按领域生成的报告后续 rerender/audit 不会丢 scope。

### `GET /api/assets?domain=` normalize 已修

`backend/api/assets.py` 已在 query 起点调用 `normalize_domain(domain)`，structured path 和 direct query path 共用 normalized 值。

### SSE 401 → `AuthStore.onUnauthorized` 已修

`mobile/lib/api/sse_client.dart` 已在 non-2xx 分支中对 401 调用 `AuthStore.onUnauthorized?.call()`，和 REST `ApiClient` 行为对齐。

### 移动端 session API 恢复 context assets 的数据链路已修

`GET /api/sessions/{id}` 已返回 `context_assets`，`ChatController.loadSession()` 会读取它们。剩余问题在 `ChatPage` 本地 `_context` 状态没有全量同步/清理。

### Custom skill domain prior：按产品决策关闭

当前 spec 已明确 custom skills 不带 skill-level domain prior，记录按内容打 domain。`confirm_skill()` 不写 custom prior 现在是 design choice，不再作为 gap。

## Verification

本轮执行并通过：

```bash
docker compose run --rm backend python -m compileall .
flutter analyze
docker compose exec -T backend python -m evals.run_evals
```

结果：

- 后端 Python 编译通过。
- Flutter analyzer: `No issues found!`
- Agent evals: `13/13 passed`，包括 `flash-multi`、domain routing、query/report redirect 等场景。

## Round 3 Judgment

这轮修复质量明显比上一轮稳：第二轮大部分 P2 已闭合，并且 eval 网开始能覆盖 routing/domain/multi-tool 的关键行为。

当前优先级建议：

1. 先修移动端 `_context` / `contextAssets` 单一真相，避免 UI 和后端 prompt context 不一致。
2. 对 Chat tool history 做明确架构决策：推荐 `SessionIndex` / `RecentEntityIndex`，不要继续在 prompt 里假设不存在的 tool rows。
3. 之后再继续做更大的 prompt 分层、IntentRouter、tool subset/token budget。

