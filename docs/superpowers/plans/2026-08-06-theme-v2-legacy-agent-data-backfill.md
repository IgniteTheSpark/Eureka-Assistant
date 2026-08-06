# Theme V2 Legacy Agent Data Backfill Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the additive legacy-Agent data migration by converting contact-shaped Assets to first-class Contacts and old Flash Chat rows to unified Session messages without merging same-name people or deleting source data.

**Architecture:** Migration `0017` keeps the legacy rows as recoverable source records and stores explicit destination IDs on them. Interactive Asset queries hide converted contact-shaped Assets; Event attendee links and persisted card references point to the first-class Contact. Old Flash chat rows point to their migrated `SessionMessage`, and compatibility readers return only rows not yet migrated.

**Tech Stack:** Alembic, MySQL 8 JSON, SQLAlchemy 2, pytest, FastAPI.

## Constraints

- Same-name contacts are never merged. One legacy Asset becomes one Contact.
- A contact-shaped Asset without a non-empty name remains untouched.
- Source Session/InputTurn/timestamps and original rows are preserved.
- Report data remains readable from the archived source Asset.
- The migration is additive and idempotent.

### Task 1: Add explicit migration mappings

- [x] Add `assets.migrated_contact_id` and `flash_chat_messages.migrated_session_message_id` to models and migration `0017`.
- [x] Backfill valid contact Assets to deterministic first-class Contact IDs.
- [x] Rewrite legacy attendee and persisted Session/capture card references.
- [x] Convert old Flash chat user turns and agent replies into unified InputTurn/SessionMessage rows.

### Task 2: Retire migrated legacy records from interactive reads

- [x] Hide mapped contact Assets from Asset list/get, Timeline, Chat context, Flash compatibility context, and MCP Asset CRUD/query.
- [x] Hide migrated FlashChatMessage rows from compatibility Session responses.
- [x] Keep report evidence access to source Assets unchanged.

### Task 3: Verify and deploy

- [x] Add migration fixtures for two same-name Alex records, attendee/card rewrite, malformed-contact preservation, and Flash chat conversion.
- [x] Run migration round-trip plus interactive Asset/MCP/Session regression suites.
- [x] Apply `0017` to the isolated Theme V2 database and verify counts/mappings read-only.
