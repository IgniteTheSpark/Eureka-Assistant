# Event Attendees Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe event-attendee binding across the backend, Flash event skill, and Flutter event UI, including contact search/create, attendee removal/rebinding, and card summaries.

**Architecture:** Keep `event_attendees` as the only persisted event/contact relation. Backend serializers enrich attendee rows from `contacts`; Flutter edits a local attendee draft and synchronizes it after the event body is saved; Flash resolves only an exact single contact result and otherwise stores a bare name.

**Tech Stack:** FastAPI, SQLAlchemy async, MCP tools, prompt-based Flash sub-skill, Flutter/Dart, `flutter_test`.

## Global Constraints

- Implement the approved contract in `spec/handoffs/handoff-event-attendees.md`.
- Target Flutter under `mobile/`; `frontend-next（deprecated）` is renamed only and receives no implementation work.
- Never auto-create a contact from Flash attendee extraction.
- Never choose the first result when a contact name has multiple matches.
- Removing an attendee deletes only `event_attendees`, never `contacts`.
- EventCard uses `time → location → first attendee +N` with no avatars.

---

### Task 1: Backend attendee contract and contact search

**Files:**
- Create: `backend/scripts/test_event_attendee_contract.py`
- Modify: `backend/mcp_server/tools.py`
- Modify: `backend/api/events.py`
- Modify: `backend/api/contacts.py`
- Modify: `backend/mcp_server/server.py`

**Interfaces:**
- Produces: attendee JSON `{id, contact_id, name_raw, display_name, role, is_resolved, contact_summary}`.
- Produces: `update_event_attendee(event_id, attendee_id, name, contact_id, role, user_id)` and `delete_event_attendee(event_id, attendee_id, user_id)`.
- Produces: `PATCH/DELETE /api/events/{event_id}/attendees/{attendee_id}`.

- [ ] **Step 1: Write the failing backend contract test**

Create an AST-safe regression script that checks enriched resolved/unresolved serialization, the two new API routes, and the five searchable contact fields:

```python
assert resolved == {
    "id": "att-1", "contact_id": "contact-1", "name_raw": "Old Alex",
    "display_name": "Alex", "role": "attendee", "is_resolved": True,
    "contact_summary": "Acme · Product Manager",
}
assert unresolved["display_name"] == "张总"
for field in ("name", "company", "title", "phone", "email"):
    assert f"Contact.{field}.ilike" in contacts_source
```

- [ ] **Step 2: Run it and verify RED**

Run: `cd backend && python3 scripts/test_event_attendee_contract.py`

Expected: FAIL because `_event_attendee_to_dict`, PATCH/DELETE routes, and multi-field search are absent.

- [ ] **Step 3: Implement enriched serialization and attendee mutations**

Add one pure serializer used by both `query_event` and `get_event`; batch-load contact rows by `contact_id`. Add/update/delete operations must scope both event and attendee by the current user’s event, validate bound contacts belong to that user, and return the enriched attendee shape.

```python
def _event_attendee_to_dict(attendee, contact=None):
    summary = " · ".join(x for x in (contact.company, contact.title) if x) if contact else ""
    return {
        "id": str(attendee.id),
        "contact_id": str(attendee.contact_id) if attendee.contact_id else None,
        "name_raw": attendee.name_raw,
        "display_name": contact.name if contact else attendee.name_raw,
        "role": attendee.role,
        "is_resolved": contact is not None,
        "contact_summary": summary,
    }
```

- [ ] **Step 4: Implement API routes and five-field search**

`AttendeePatch` keeps all fields optional; use `model_fields_set` so an explicit empty `contact_id` can unbind. Contact search applies `or_(name, company, title, phone, email).ilike(%q%)`, ordered newest-first and limited.

- [ ] **Step 5: Run backend contract and syntax checks**

Run: `cd backend && python3 scripts/test_event_attendee_contract.py && python3 -m py_compile api/events.py api/contacts.py mcp_server/tools.py mcp_server/server.py`

Expected: contract prints `ok - event attendee contract`; compilation exits 0.

### Task 2: Flash safe contact resolution

**Files:**
- Create: `backend/scripts/test_flash_event_attendees_contract.py`
- Modify: `backend/skills/flash-event-skill/SKILL.md`

**Interfaces:**
- Consumes: `tool_query_contact(name_query)` returning `contacts[]`.
- Produces: one attendee tool call per deduplicated extracted name, bound only when `len(contacts) == 1`.

- [ ] **Step 1: Write the failing prompt contract test**

```python
text = SKILL.read_text()
assert "tool_query_contact" in text
assert "0 命中" in text and "1 命中" in text and "2+ 命中" in text
assert "不创建 contact" in text
assert "完全重复" in text and "去重" in text
```

- [ ] **Step 2: Run it and verify RED**

Run: `cd backend && python3 scripts/test_flash_event_attendees_contract.py`

Expected: FAIL because the checked-in runtime skill still says never query contacts.

- [ ] **Step 3: Update the runtime skill**

Replace Step 3b and examples with the approved 0/1/2+ algorithm, preserving original attendee wording for unresolved cases and forbidding auto-contact creation.

- [ ] **Step 4: Run the prompt contract**

Run: `cd backend && python3 scripts/test_flash_event_attendees_contract.py`

Expected: `ok - flash event attendee safety contract`.

### Task 3: Flutter attendee models and contact selector

**Files:**
- Create: `mobile/lib/pages/event_attendees.dart`
- Create: `mobile/test/event_attendees_test.dart`
- Modify: `mobile/lib/pages/create_asset.dart`

**Interfaces:**
- Produces: `EventAttendeeDraft.fromJson`, `ContactChoice.fromJson`, `contactSummary`, `syncEventAttendees`.
- Produces: `showEventAttendeeSelector(...)` supporting debounced multi-select and a single-select binding mode.
- Consumes: `ApiClient.getJson('/api/contacts', query: {'q': query, 'limit': 20})` and a callback that opens `ContactForm`.

- [ ] **Step 1: Write failing Dart tests for parsing and sync decisions**

```dart
expect(EventAttendeeDraft.fromJson({
  'id': 'a1', 'contact_id': null, 'name_raw': 'Alex',
  'display_name': 'Alex', 'is_resolved': false,
}).isResolved, isFalse);
expect(contactSummary({'company': 'Acme', 'title': 'PM'}), 'Acme · PM');
expect(eventAttendeeSummaryName({'display_name': 'Alex', 'name_raw': 'Old'}), 'Alex');
```

- [ ] **Step 2: Run it and verify RED**

Run: `cd mobile && flutter test test/event_attendees_test.dart`

Expected: compile failure because the attendee module does not exist.

- [ ] **Step 3: Implement focused models and selector sheet**

The sheet loads recent contacts at empty query, debounces search by 300 ms, keeps same-name contacts distinct by id, shows summary/phone for disambiguation, exposes `新增联系人` when results are empty, and keeps a fixed `保存(N)` footer.

- [ ] **Step 4: Make ContactForm return the created contact**

Preserve the existing receipt keys and add `contact_id` plus the backend `contact` map so the selector can auto-select the new contact without refetching.

- [ ] **Step 5: Run focused tests and analyzer**

Run: `cd mobile && flutter test test/event_attendees_test.dart && flutter analyze lib/pages/event_attendees.dart lib/pages/create_asset.dart`

Expected: tests pass and analyzer exits 0.

### Task 4: EventForm attendee editing and synchronization

**Files:**
- Modify: `mobile/lib/pages/create_asset.dart`
- Modify: `mobile/test/event_attendees_test.dart`

**Interfaces:**
- Consumes: enriched attendees from `existing['attendees']`.
- Produces: POST for new contacts, PATCH for unresolved attendee bindings, DELETE for removed persisted attendees after the event save succeeds.

- [ ] **Step 1: Add failing tests for the attendee sync plan**

Cover: add two contacts, remove persisted attendee, bind unresolved attendee, and ignore unchanged bound attendee. Assert exact method/path/body operations.

- [ ] **Step 2: Run it and verify RED**

Run: `cd mobile && flutter test test/event_attendees_test.dart`

Expected: FAIL because no diff/sync implementation exists.

- [ ] **Step 3: Add the EventForm attendee section**

Render each attendee as a compact list/chip with display name, summary, `未绑定名片` hint, remove action, and `绑定名片` for unresolved persisted rows. `添加参会人` opens multi-select and filters already-bound contacts.

- [ ] **Step 4: Synchronize only after event save succeeds**

For create, read `event_id` from POST response then POST selected contacts. For edit, PUT the event body then apply the attendee diff. On any attendee failure, keep the form open and show `保存参会人失败` so partial state is visible and retryable.

- [ ] **Step 5: Run focused Flutter tests**

Run: `cd mobile && flutter test test/event_attendees_test.dart`

Expected: all attendee tests pass.

### Task 5: EventCard summary compatibility and full verification

**Files:**
- Modify: `mobile/lib/render/render_spec.dart`
- Modify: `mobile/test/event_card_summary_test.dart`

**Interfaces:**
- Consumes: new `display_name/name_raw` attendee shape and legacy `name` shape.
- Produces: first attendee label plus `+N`, without deduplicating attendee rows.

- [ ] **Step 1: Add failing card tests**

```dart
expect(summaryFor([
  {'display_name': 'Alex', 'name_raw': 'Old'},
  {'display_name': 'Alex', 'name_raw': 'Other'},
]), 'Alex +1');
```

Also cover unresolved `name_raw` and legacy `name`.

- [ ] **Step 2: Run and verify RED**

Run: `cd mobile && flutter test test/event_card_summary_test.dart`

Expected: FAIL because current code prefers legacy `name` and deduplicates equal display names.

- [ ] **Step 3: Update summary compatibility**

Choose `display_name`, then `name_raw`, then legacy `name`; count attendee rows, falling back to `attendees_count` only when it is larger.

- [ ] **Step 4: Run complete verification**

Run:

```bash
cd backend && python3 scripts/test_event_attendee_contract.py
cd backend && python3 scripts/test_flash_event_attendees_contract.py
cd backend && python3 scripts/test_event_card_contract.py
cd backend && python3 -m py_compile api/events.py api/contacts.py mcp_server/tools.py mcp_server/server.py
cd mobile && flutter test test/event_attendees_test.dart test/event_card_summary_test.dart
cd mobile && flutter analyze lib/pages/create_asset.dart lib/pages/event_attendees.dart lib/render/render_spec.dart
git diff --check
```

Expected: every command exits 0; no whitespace errors.
