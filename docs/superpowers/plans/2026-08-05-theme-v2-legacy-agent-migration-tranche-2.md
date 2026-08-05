# Theme V2 Legacy Agent Migration — Tranche 2 Plan

**Date:** 2026-08-05

**Parent design:** `docs/superpowers/specs/2026-08-05-theme-v2-legacy-agent-migration-design.md`

**Goal:** restore the complete internal Eureka CRUD MCP contract on Theme V2
models without switching the Flash dispatcher or Report pipeline yet.

## Boundaries

- Keep the isolated Theme V2 MySQL/API/worker runtime.
- Keep `/api/chat` as the only Session chat route used by new code.
- Do not attach external MCP, Task Skill, Morning Briefing, or legacy Report.
- Do not import legacy database modules at runtime.
- Preserve current Theme V2 cards; MCP returns normalized domain results only.

## Task 1 — Freeze the tool contracts

Add contract tests for the legacy-compatible names and result shapes:

- asset: create todo/note/generic, query/digest, update, delete;
- contact: create/query/update/delete;
- event: create/query/get/update/delete and attendee CRUD;
- InputTurn: query/get.

The tests must prove authenticated user scoping, provenance ownership, partial
custom payloads, invalid target rejection, and no cross-user candidate leak.

## Task 2 — Add the missing Theme V2 domain foundation

Create an additive migration and matching SQLAlchemy models for:

- first-class `contacts` with notes/socials/InputTurn provenance;
- `asset_fields` typed projections for configured queryable fields;
- Event InputTurn provenance and recurrence metadata;
- EventAttendee → Contact `ON DELETE SET NULL` ownership-safe linkage;
- durable `agent_tool_executions` keyed by user + stable idempotency key;
- `UserSkill.queryable_fields_json`, ordering, and enabled state.

Backfill AssetField rows for existing assets. Do not migrate or delete current
contact-shaped assets in this tranche; that cutover belongs to the dedicated
data/presenter migration after both readers exist.

## Task 3 — Implement Theme V2 domain services

Add owner-scoped services for Contact and attendee CRUD. Extend Asset/Event
services so Agent mutations:

- validate Session and InputTurn ownership;
- persist source Session/InputTurn provenance;
- use permissive validation for custom Agent writes and built-in invariants for
  built-ins;
- rebuild AssetField projections after create/update;
- preserve attendee display names when a Contact is detached/deleted;
- emit outbox records in the same transaction.

## Task 4 — Port the internal MCP implementation

Create a Theme V2-local `app/internal_mcp` package with:

- legacy-compatible tool functions and response envelopes;
- a single trusted runtime context containing user, Session, InputTurn, and
  idempotency prefix;
- stable replay of completed mutations through `agent_tool_executions`;
- a FastMCP stdio server exposing the legacy `tool_*` names;
- no legacy imports and no external MCP configuration.

## Task 5 — Adapt current Chat tooling

Replace the four ad-hoc `SessionToolExecutor` implementations with an adapter
over the internal MCP implementation. The LiteLLM-facing definitions may keep
their current temporary names, but every operation must use the same domain
contract and provenance/idempotency path as the stdio MCP server.

The legacy Chat Assistant/ADK toolset switch remains Tranche 3; this tranche
provides the runtime it will consume.

## Task 6 — Verification and rollout

Run:

1. focused MCP/domain/ownership/idempotency tests;
2. real isolated MySQL upgrade from 0014 to the new head and downgrade/upgrade;
3. the complete Theme V2 backend suite;
4. Flutter Session/Library/Calendar critical regressions;
5. independent Docker rebuild, health/readiness, migration and worker logs;
6. Android install/start smoke against host 8100 through `adb reverse`.

Commit only Tranche 2 files. Existing unrelated Pen/mobile changes remain
untouched and unstaged.
