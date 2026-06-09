# Agent evals — the regression net

Executable Chinese scenarios that run real utterances through the **live**
chat/flash pipelines and assert on observable behavior (which tool fired, the
skill/domain it routed to, create-vs-query-vs-redirect). This is the safety net
for the planned agent-layer refactor (codex review: `AgentRunner` / `IntentRouter`
/ token reductions) — extract shared runtime/routing **only while this stays green**.

## Run

```bash
# inside the backend container (has DB + LLM env + reaches localhost:8000)
docker exec eureka-assistant-backend-1 python -m evals.run_evals
docker exec eureka-assistant-backend-1 python -m evals.run_evals --repeat 3        # gauge flakiness
docker exec eureka-assistant-backend-1 python -m evals.run_evals --only water-route,query-domain
```

Exit code 0 iff every scenario passed every repeat. **50 scenarios**, baseline ~49-50/50
(the ~1 variance is the strict `domain` assertions on custom skills — re-run with `--repeat 3`).

## What it covers (`scenarios.py`, ~50 cases, 11 groups)

- **A. skill routing** — 喝水→daily_water, 跑步→running, 记账→expense, 读书→book_note, work_log
- **B. domain by content (§8)** — 交报告→工作, 买菜→生活, 电影票→娱乐, 灵感→灵感
- **C. chat ≠ 闪念** — bare opinion / pleasantry / 感慨 must NOT auto-create
- **D. explicit capture** — 「帮我记…」 overrides the conversational default
- **E. query, not create** — 待办列表 / 月消费 / 按域查 / 读了什么书
- **F. report = independent entry** — chat only redirects (出报告/复盘文档/图文总结)
- **G. event-vs-todo 铁律** — single time = todo, full range / all-day = event
- **H. contact** — 名片/认识了某人 → create_contact
- **I. CHAT-ANSWER** — external knowledge (区块链/行业/做法) → no tool
- **J. external sync** — 同步到钉钉/Notion/日历 → tool_create_task
- **K. flash multi-record** — don't drop the quieter record (2/3 cards)

## Notes

- deepseek is non-deterministic. A single FAIL is a signal to inspect, not always
  a regression — re-run with `--repeat 3`. Routing/domain/redirect are stable
  enough to assert; exact wording is never asserted.
- Runs against the **test user** `c737604…` (has the baseline + custom skills the
  scenarios reference). Keep that user's skills seeded.
- Each full run ≈ 13 live LLM calls. Cheap, but not free — run on agent-prompt or
  pipeline changes, and before/after any AgentRunner/IntentRouter work.

## When you add agent behavior

Add a scenario here in the same PR. The eval set IS the behavior spec — if it's
not asserted, it will drift. Especially: regression cases for bugs you just fixed
(this set already encodes 喝水 routing, chat≠闪念, domain tagging, query-not-create,
report-redirect, multi-record extraction — all hand-fixed in 2026-06).
