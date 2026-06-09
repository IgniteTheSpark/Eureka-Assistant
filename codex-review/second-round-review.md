# Eureka Assistant Review — 第二轮复审

审阅时间：2026-06-05 15:14-15:28

背景：用户已根据第一轮 implementation / tech review 修复一轮。本轮复审重点验证上一轮 P1/P2 是否闭合，并检查修复后是否引入新的边界问题。

## Findings

### P1: Chat tool history 仍未真正持久化

`_stream_assistant` 会把 `tool_call` / `tool_result` 通过 SSE 发给前端，但 `/api/chat` endpoint 只用 `tool_result` 生成 `persist_cards`。最后调用 `persist_chat_turn(...)` 时，没有传入 `tool_call` / `tool_result`。

这意味着上一轮指出的“跨轮引用依赖工具历史，但历史里没有工具调用”仍未关闭。当前跨轮引用仍主要依赖 session asset hints，而不是完整 tool history。

Relevant files:

- `backend/api/chat.py`
- `backend/core/session_service.py`

Recommendation:

- 要么真正把每个 tool call/result 持久化为 message rows；
- 要么删除 history tool-call 假设，改为明确的 `SessionIndex` / `RecentEntityIndex`。

### P1: 移动端历史会话恢复仍没有恢复 context assets

`ChatController.loadSession()` 只读取 `/api/sessions/{id}/messages`，没有读取 session meta / `context_asset_ids`。

因此用户切回历史会话时，后端 session 里已有上下文资产，但移动端 context chip 可能为空，用户会误以为上下文没有附加。

Relevant files:

- `mobile/lib/chat/chat_controller.dart`
- `mobile/lib/pages/chat_page.dart`

Recommendation:

- `loadSession()` 同时请求 `/api/sessions/{id}`；
- 将返回的 `context_asset_ids` 映射回 UI context chips；
- 或后端 `messages` endpoint 一并返回 session context meta。

### P2: 新 AgentRunner 仍使用 singular tool event accessor，可能丢并行 tool events

`core/event_mapper.py` 明确说明 `event_tool_calls()` / `event_tool_results()` 才能保留同一 ADK event 中的所有并行工具调用。

但新建的 `core/agent_runner.py` 使用的是 singular `event_tool_call()` / `event_tool_result()`，只取第一个。虽然当前多数 sub-skill 一次只调用一个工具，但这个 runner 已经开始作为公共层使用，后续会成为隐藏丢事件风险。

Relevant files:

- `backend/core/agent_runner.py`
- `backend/core/event_mapper.py`

Recommendation:

- 将 `AgentRunner` 改为使用 plural accessors；
- 对同一 event 中多个 calls/results 做按顺序或 name 配对；
- 至少不要 silently drop 后续 tool events。

### P2: Report `spec_json` 仍未持久化 domain

`report_pipeline._fetch_report_data()` 已经读取并 normalize `scope["domain"]`，且会按 domain 过滤数据。但最终持久化的 `spec` 没有包含 `domain`。

这会导致按域生成的报告在后续 rerender、审计或重跑时丢失原始 scope。

Relevant file:

- `backend/agents/report_pipeline.py`

Recommendation:

- 在 `spec` 中加入 `"domain": normalize_domain(scope.get("domain"))`。

### P2: `GET /api/assets?domain=` 仍未 normalize

`assets.py` 的 structured path 和 direct query path 都直接使用传入的 `domain` 字符串比较，没有经过 `normalize_domain()`。

这会让非法值静默返回空结果，也让空白/别名等输入和 create/update 路径行为不一致。

Relevant file:

- `backend/api/assets.py`

Recommendation:

- 在 query 开始处统一 `domain = normalize_domain(domain)`；
- 对非法 domain 可以返回 400，或按 `None` 处理，但需要显式一致。

### P2: `list_skills` 已返回 domain，但 custom skill confirm 仍不写 prior

`GET /api/skills` 已补上 `domain` 字段，这是进展。但 `confirm_skill()` 创建 `UserSkill` 时仍没有写 `domain`，新建 `GlobalSkill` 也没有写 domain。

如果产品决定“custom skill 的 domain 永远由内容决定”，这可以接受；但它仍未对齐 spec 中 design prior / AddSkillWizard prior 的方向。

Relevant file:

- `backend/api/skills.py`

Recommendation:

- 如果继续遵循 spec：扩展 draft/confirm schema，允许 design agent 或用户选择 domain prior；
- 如果不做 prior：更新 spec，明确 custom skills default domain is null and content-based。

### P2: SSE 401 仍未触发 AuthStore.onUnauthorized

REST `ApiClient` 已在 401 时触发 `AuthStore.onUnauthorized`，但 `sse_client.dart` 在 non-2xx 时只抛 `ApiException`。

Chat SSE 或 report generate SSE 遇到 token 过期时，行为仍和 REST 不一致。

Relevant file:

- `mobile/lib/api/sse_client.dart`

Recommendation:

- 在 `_sse()` 中，如果 `res.statusCode == 401`，先调用 `AuthStore.onUnauthorized?.call()`，再 throw `ApiException`。

## 已确认修好的点

### Fresh deploy migration chain 已通过验证

本轮创建了独立临时 MySQL schema，并运行：

```bash
docker compose run --rm -e DATABASE_URL="mysql://eureka:eureka@db:3306/<temp_db>" backend alembic upgrade head
```

结果完整跑到 `0009_domain`，没有 duplicate table / column。该临时 schema 随后已删除。

### 生产密钥检查已落地

`main.py` 启动前调用 `validate_prod_secrets()`。当环境被判断为 production-like 时，会强制要求安全 `JWT_SECRET` 和独立 `CONNECTED_APPS_KEY`。

注意：当前判断逻辑把 `JWT_SECRET` 非默认也视为 production-like。如果本地 dev 只改了 `JWT_SECRET` 但没配置 `CONNECTED_APPS_KEY`，服务会拒绝启动。这是安全但偏严格的取舍。

### Agent eval / AgentRunner 已开始落地

新增了：

- `backend/core/agent_runner.py`
- `backend/evals/`

这是正确方向。但 `AgentRunner` 的 tool-event 处理还需要从 singular 改成 plural。

### Report picker domain filter 已补

`mobile/lib/pages/report_asset_picker_page.dart` 增加了 domain filter/chip 逻辑，覆盖了上一轮 spec 对齐里提到的报告资产选择器领域筛选缺口。

## Verification

本轮执行并通过：

```bash
docker compose run --rm backend python -m compileall .
flutter analyze
```

本轮还执行并通过 fresh schema migration:

```bash
alembic upgrade head
```

后端本机没有 `python3.12`，但 Docker 后端容器使用 Python 3.12，编译以容器结果为准。

## Round 2 Judgment

第二轮修复后，整体健康度明显提升：部署迁移 P1 已关闭，生产密钥检查已落地，移动端 analyzer 和后端 Python 3.12 编译均通过，report picker domain 也补齐。

仍建议下一轮优先处理：

1. Chat tool history / SessionIndex contract
2. Mobile context restore
3. AgentRunner plural tool events
4. Report spec_json domain persistence
5. SSE 401 auth consistency

这些修完后，再进入更大的 prompt 分层、IntentRouter、tool subset、agent eval 扩展，会更稳。

---

## Round 2 — Disposition (by Claude, 2026-06-05)

### Fixed this pass (verified: backend syntax + flutter analyze + build web + evals)
- **P2 AgentRunner plural tool events:** `core/agent_runner.py` now uses `event_tool_calls`/`event_tool_results` (plural) and pairs each result to its call by name (FIFO) — no parallel tool event dropped. Verified: flash `flash-multi` (multi-tool) eval green.
- **P2 Report `spec_json` domain:** `report_pipeline` now persists `"domain": normalize_domain(scope.get("domain"))` in `spec` → rerender/audit keeps the scope.
- **P2 `GET /api/assets?domain=` normalize:** `list_assets` runs `domain = normalize_domain(domain)` up front → illegal/aliased values handled consistently with create/update (→ None = no filter), not raw-compared.
- **P2 SSE 401 → onUnauthorized:** `sse_client._sse` now calls `AuthStore.onUnauthorized` on 401 before throwing, matching REST. Expired token on chat/report SSE drops to login.
- **P1 Mobile context restore:** `GET /api/sessions/{id}` now returns resolved `context_assets` ([{id,label}]); `ChatController.loadSession` fetches + stores them; `chat_page` seeds the chip rail. Reopening a history session restores its context chips.

### By design — spec already aligned (not a gap)
- **Custom skill `confirm` doesn't write domain prior** — product decision 2026-06: custom skills have **no** skill-level domain (content-based per record). Spec already says so (§8.1/§8.2, §2, §3); only baseline 记账/随记/名片 carry a prior. design-agent / AddSkillWizard intentionally not touched.

### Still open (the one real fork) — needs a decision
- **P1 Chat tool history / SessionIndex:** `persist_chat_turn` still stores text+cards, not `tool_call`/`tool_result` rows; `_format_history`'s tool branch is effectively dead and cross-turn "刚刚那个" leans on `session_assets_hint`. Two clean options: (a) persist tool calls/results as message rows, or (b) drop the tool-history assumption and build an explicit `SessionIndex`/`RecentEntityIndex`. This is architectural — deferred for an explicit choice (pairs naturally with the IntentRouter/AgentRunner refactor, spec §1.10).
