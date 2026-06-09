# Eureka Assistant Implementation / Tech Review

审阅时间：2026-06-05

审阅范围：当前分支的后端 agent loop、prompt/skills、MCP/tool 调用、数据模型/API、移动端契约、spec 对齐。`spec` 中的 pet 与 game 功能按当前未实现处理，不计为实现缺口。

## Executive Summary

项目整体方向是对的：核心能力已经能串起 Flash 捕捉、Chat CRUD、Task 外部同步、Report 引擎、Domain Layer A、Connected Apps 和 Flutter 主路径。当前不是“完全 ad hoc 的系统”，但已经进入 prompt debt 与 fallback debt 的临界点。

最健康的设计是 Report pipeline：LLM 负责体裁和内容表达，Python 负责确定性取数与 HTML render。这把 LLM 不稳定性限制在可控层里，是后续其他 agent pipeline 应该参考的模式。

最需要收敛的是 Chat Assistant、Flash dispatcher/sub-skill 和 fallback/retry 体系。现在存在四条并行 agent 管线、两套意图路由、全量工具 schema 注入、超长 prompt、多个 provider-specific fallback。继续往 `assistant.py` 或各个 `SKILL.md` 里堆反例，短期有效，长期会推高 token 成本和行为漂移风险。

## Highest Priority Findings

### P1: Fresh Deploy Migration Chain May Fail

`0001_mysql_init` 基于当前 `Base.metadata` 做 `create_all`，会一次性建出后续迁移也要创建或加列的表和字段。后续 `0004_users`、`0006_reports`、`0007_connected_apps`、`0009_domain` 再执行时可能出现 duplicate table/column。

Relevant files:

- `backend/db/migrations/versions/0001_mysql_init.py`
- `backend/db/migrations/versions/0004_users.py`
- `backend/db/migrations/versions/0006_reports.py`
- `backend/db/migrations/versions/0007_connected_apps.py`
- `backend/db/migrations/versions/0009_domain.py`

Recommendation: first fix the migration chain before shipping or onboarding new environments. Either freeze `0001` as a historical snapshot or make later migrations idempotent with explicit table/column existence checks.

### P1: Connected Apps Encryption Can Degrade in Production

If `CONNECTED_APPS_KEY` is missing, `backend/core/crypto.py` derives the Fernet key from `jwt_secret`. This is acceptable only for local development. In production, if `jwt_secret` is weak or still default, third-party credentials become predictably decryptable.

Relevant files:

- `backend/core/crypto.py`
- `backend/config.py`

Recommendation: enforce `CONNECTED_APPS_KEY` in production startup. Do not allow jwt-derived fallback outside dev.

### P1: Chat Does Not Persist Tool Call History Despite Depending on It

Docs and `_format_history()` assume previous tool calls/results are part of message history, but `persist_chat_turn()` currently stores `agent_text` and cards, not full `tool_call` / `tool_result` rows. Cross-turn references like “刚刚那个” mostly rely on session asset hints, which are limited and can miss edge cases.

Relevant files:

- `backend/api/chat.py`
- `backend/core/session_service.py`

Recommendation: choose one model and make it explicit:

- Persist tool calls/results as first-class message rows, or
- Remove tool-history assumptions and build a `SessionIndex` / `RecentEntityIndex` for references.

### P1: Chat And Flash Maintain Duplicate Intent Systems

Chat uses a very large `ASSISTANT_INSTRUCTION_BASE`; Flash uses `flash-dispatcher/SKILL.md` plus sub-skills. Both define boundaries for todo/event/notes/task/report/domain, but they are not backed by one shared intent registry. The same utterance can drift across Chat and Flash over time.

Relevant files:

- `backend/agents/assistant.py`
- `backend/skills/flash-dispatcher/SKILL.md`
- `backend/agents/flash_pipeline.py`

Recommendation: extract a shared `IntentRouter` contract and eval set. Chat and Flash can still have different UX behavior, but they should share intent names, boundary tests, and routing semantics.

### P1: Assistant Prompt Is Acting As A Business State Machine

`ASSISTANT_INSTRUCTION_BASE` contains intent routing, tool rules, report redirection, external sync, domain behavior, cross-turn reference rules, style constraints, and many “踩坑补丁”. Each chat turn pays this token cost even when most rules are irrelevant.

Relevant files:

- `backend/agents/assistant.py`
- `backend/api/chat.py`

Recommendation: split the assistant into:

- Thin base persona and output discipline
- Lightweight router
- Intent-specific policy packs
- Tool subsets based on resolved intent

## Agent Loop And Token Review

### Current Pipelines

The system effectively has four separate agent pipelines:

1. Chat: `/api/chat` -> single Assistant -> internal MCP tool loop -> SSE
2. Flash: dispatcher -> parallel sub-skill agents -> Python aggregator
3. Task: placeholder asset/task -> async external MCP runner
4. Report: dispatcher -> deterministic Python fetch -> content LLM -> Python render

The Report path is the most general and reliable because it avoids LLM tool-call flakiness for data fetching.

### Token Hotspots

Main token drivers:

- Assistant base prompt: high fixed cost every chat turn
- Full MCP tool schema injection: high cost, especially when sub-skills only need a few tools
- 20-message history stringification: can balloon with tool JSON
- User skill dictionary injection: grows with number of skills
- Flash multi-intent runs: `1 + N` LLM calls, each with prompt/tool overhead
- Report raw data injection: capped, but can still be large

### Recommended Token Reductions

1. Tool subset by intent/skill. For example, todo skill should not receive every contact/event/report/task tool schema.
2. Replace all-history string prefix with structured recent entities, last references, and summaries.
3. Inject only top-k candidate skill schemas instead of full user skill dictionary.
4. Move from prompt-only routing to a shared router + schema-driven extractor.
5. Keep Report’s deterministic data plane and apply similar principles elsewhere.

## Fallback / Reliability Debt

Current fallback logic is useful but scattered:

- Chat detects leaked tool calls and retries whole runs.
- Flash parses malformed JSON and reconstructs from tool events.
- Flash force-creates custom assets if agent output fails.
- Event intent can reroute to todo on validation failure.
- Task recovers prior assistant reply when content is empty.
- External ref extraction relies on heuristic keys.

These should become a single reliability layer instead of per-pipeline patches:

- `AgentRunner`: unified runner, usage accounting, tool event collection, retry budget
- `StructuredOutputParser`: schema-aware JSON parsing/repair
- `ToolGroundTruthResolver`: trust successful tool results over malformed final text
- `SessionContextResolver`: shared handling for “刚刚/上面/那个”
- `ValidationPolicyRouter`: structured reroute based on validation failures

## Data / API Review

### What Is Solid

- MySQL portability is considered through `GUID`, `UTCDateTime`, JSON arrays, integer booleans, and avoiding Postgres-only patterns.
- Report engine is persisted as first-class `Report` rows with markdown/html/spec.
- Connected Apps has catalog, encrypted credentials, per-user MCP toolsets, and write-only credential responses.
- Domain Layer A exists across assets and skills.

### Main Gaps

- `GET /api/skills` does not return `domain`, despite schema/spec expectations.
- Custom skill confirm does not write domain prior.
- `global_skills.domain` exists but is not meaningfully populated.
- Report `spec_json` does not persist `domain`, even when dispatcher/fetch uses it.
- Connected Apps probe may mark connections as connected when live validation cannot run.
- Decrypt failure returns `{}` and silently disables toolsets instead of surfacing `error` / `needs_reauth`.

## Mobile Contract Review

The Flutter app successfully wires the new capabilities together, but API contract logic is spread across pages.

Main issues:

- Chat context assets are written with `PATCH /api/sessions/{id}/context`, but switching sessions reads only messages and does not restore `context_asset_ids`.
- SSE 401 does not follow the same auth recovery behavior as REST.
- Several pages convert failures into empty lists, making API failure look like “no data”.
- Report swipe delete lacks confirmation.
- API paths for assets/events/contacts/tasks/reports are manually constructed in multiple widgets.

Recommendation: introduce a small entity/client layer:

- `EntityClient`
- `CardEnvelope`
- shared delete/update/detail routes
- explicit error states instead of empty fallback

## Spec Alignment Review

The implemented product mostly matches the current intended product, but the spec is behind the code in several places:

- Multi-user auth is implemented, while older spec text still references fixed `user_id=default`.
- Reports now use independent `/api/reports/intake` and `/api/reports/generate`, not `POST /api/chat` with `session_type=report`.
- `idea`/`misc` are merged into `notes`, but some spec/prompt appendix references remain.
- GSAP report viewer injection is implemented, while some spec text marks it pending.
- Table counts and router lists are outdated.

Largest non-pet/game missing items:

- PresentationMode
- Report asset picker domain filter
- Design/AddSkill domain prior UI
- Full-screen settings hub

Recommendation: update spec before adding pet/game, otherwise future implementation will inherit stale assumptions.

## Suggested Fix Order

1. Fix deployment P1s:
   - Migration chain fresh deploy
   - Production `CONNECTED_APPS_KEY` enforcement

2. Fix session/reference contract:
   - Persist tool calls/results or replace history dependency with `SessionIndex`
   - Restore mobile `context_asset_ids` on session load
   - Align SSE 401 behavior with REST

3. Create shared agent infrastructure:
   - `AgentRunner`
   - `ToolGroundTruthResolver`
   - `StructuredOutputParser`
   - usage and retry policy

4. Create shared intent infrastructure:
   - `IntentRouter`
   - shared intent enum
   - Chat/Flash boundary tests
   - domain/report/task routing rules in code or data, not only prompt prose

5. Reduce token costs:
   - tool subset per intent
   - top-k skill schema injection
   - structured history summaries
   - thin Assistant prompt with policy packs

6. Add agent evals:
   - 20-50 Chinese scenarios
   - assert tool calls, payloads, domain, report redirect, query-not-create behavior
   - include regression cases for “刚刚那个”, “把上面同步到钉钉”, incomplete event time, and custom skill creation

7. Clean spec and mobile contracts:
   - update outdated spec sections
   - centralize mobile entity routes
   - stop silent empty-list failure fallbacks

## Final Judgment

The project is viable and the conceptual architecture is promising, especially the Report pipeline and render-spec-driven UI direction. The main risk is not that the system is “wrong”; it is that LLM reliability workarounds are currently scattered and prompt-driven. If the next development phase adds pet/game/domain-heavy UX without first extracting common runtime, routing, and contract layers, the system will become harder to reason about and more expensive to run.

Highest ROI next step: fix deployment/security P1s, then build `AgentRunner + IntentRouter + agent evals` before adding major new product surface area.

## Verification Notes

- `flutter analyze` passed.
- Backend local `python` is 2.7 and `python3` is 3.9.6, while `backend/Dockerfile` targets Python 3.12. Local compile failures under Python 3.9 should not be treated as backend syntax failures.
- No code fixes were applied as part of this review file.

---

## Disposition / Triage (2026-06-05, by Claude)

### Fixed this pass (verified)
- **P1.1 Migration chain (fresh deploy):** confirmed — `0001_mysql_init` uses `Base.metadata.create_all()` on live models, so a clean `alembic upgrade head` collided at the first `create_table`/`add_column` migration. **Codex's list was incomplete** — `0003` and `0005` collide too, not just `0004/0006/0007/0009`. Added skip-if-exists guards (`inspect().has_table/has_column/has_index`) to **0003/0004/0005/0006/0007/0009**. Verified: all guard predicates return "exists" against the full live schema (the exact post-0001 state), so every migration skips on fresh deploy. (Could not run a literal fresh `upgrade head` — the `eureka` DB user lacks CREATE-DATABASE.)
- **P1.2 CONNECTED_APPS_KEY:** added `config.validate_prod_secrets()` called at startup in `main.py`. Prod-like (`ENV=prod/staging` or `JWT_SECRET` overridden) now **refuses to boot** without both a non-default `JWT_SECRET` and a set `CONNECTED_APPS_KEY`. Added `ENV` setting. Dev box passes (has both); backend healthy after reload.
- **Data gap — `GET /api/skills` domain:** now serialized (`api/skills.py`). Verified: baseline contact→社交/expense→生活/notes→灵感, custom skills → null.

### Now obsolete / out-of-date in this review (review predates the last two sessions)
- **"Report asset picker domain filter missing"** — built (`report_asset_picker_page.dart`: domain chip bar + per-row chip).
- **"Design/AddSkill domain prior UI" + "custom skill confirm doesn't write domain prior"** — **intentional product decision** (custom skills get no skill-level domain; per-record content-based only). Not a gap.
- Stale `session_id` crash (separate from P1.3) — already fixed (`get_or_create_chat_session` falls back to new session).

### Started this pass — agent infra (2026-06-05)
- **Agent evals (DONE, the regression net):** `backend/evals/` — 13 Chinese scenarios run the live chat/flash pipelines and assert tool/skill/domain/redirect/cards. `python -m evals.run_evals`. **Baseline 13/13.** This is codex's step 6, built FIRST (before the AgentRunner/IntentRouter refactor) so the refactor can't silently regress behavior. See `backend/evals/README.md` + spec §1.10.
- **First round of agent fixes (caught by the new evals):** stronger domain content-tagging (custom skills have no prior, so 喝水→健康 / 买菜→生活 must come from content — was flaky, now reliable) + tightened chat≠闪念 so pleasantries (「你好呀，今天天气不错」) don't auto-create. Re-run: 13/13.
- **AgentRunner (DONE 2026-06-05):** `core/agent_runner.py` — `run_agent() -> AgentRunResult{text, tool_events, usage_tokens}`, the one batch ADK-run loop. flash/report/task now route through it via `flash_pipeline._run_agent` (thin delegation, zero churn for importers); design_agent's 2 hand-rolled loops migrated; added usage accounting. Verified: imports OK, evals green (running-route 3/3 after refactor), design draft works (`POST /api/skills` → 200 draft). Chat keeps its streaming loop (shares only `event_mapper`). Spec §1.10.
- **Next (net in place):** `ToolGroundTruthResolver` → `StructuredOutputParser` → `IntentRouter` → token cuts. Roadmap in spec §1.10.

### Accepted as backlog (valid, not done this pass)
- P1.3 tool-call history vs `_format_history` (dead branch; refs lean on `session_assets_hint`).
- P1.4/P1.5 + token hotspots + scattered fallbacks → `AgentRunner` / `IntentRouter`. **Agreed: extract these (net is now ready) before adding pet/game surface.**
- `global_skills.domain` unpopulated; report `spec_json` lacks `domain`; decrypt-failure returns `{}` silently.
- Mobile: `context_asset_ids` not restored on session switch; SSE 401 ≠ REST auth recovery; empty-list-as-no-data; report swipe-delete confirm; centralize entity routes.
- Spec drift cleanup (PresentationMode, table counts, router lists).
