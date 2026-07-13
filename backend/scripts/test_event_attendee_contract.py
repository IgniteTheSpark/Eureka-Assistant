"""Regression checks for the event attendee API contract."""

from __future__ import annotations

import ast
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]


def _load_attendee_helpers(source: str) -> dict:
    module = ast.parse(source)
    expected = {
        "_apply_event_attendee_patch",
        "_detach_event_attendee_contact",
        "_event_attendee_to_dict",
        "_event_attendee_unbound_name",
    }
    body = [
        node
        for node in module.body
        if isinstance(node, ast.FunctionDef)
        and node.name in expected
    ]
    found = {node.name for node in body}
    assert found == expected, f"missing attendee helpers: {sorted(expected - found)}"
    namespace: dict = {}
    exec(
        compile(ast.Module(body=body, type_ignores=[]), "attendee_subset", "exec"),
        namespace,
    )
    return namespace


def test_event_attendee_contract() -> None:
    tools_source = (ROOT / "mcp_server/tools.py").read_text()
    events_source = (ROOT / "api/events.py").read_text()
    contacts_source = (ROOT / "api/contacts.py").read_text()
    server_source = (ROOT / "mcp_server/server.py").read_text()

    helpers = _load_attendee_helpers(tools_source)
    serialize = helpers["_event_attendee_to_dict"]
    apply_patch = helpers["_apply_event_attendee_patch"]
    detach_contact = helpers["_detach_event_attendee_contact"]
    attendee = SimpleNamespace(
        id="att-1",
        contact_id="contact-1",
        name_raw="Old Alex",
        role="attendee",
    )
    contact = SimpleNamespace(
        name="Alex",
        company="Acme",
        title="Product Manager",
    )

    resolved = serialize(attendee, contact)
    assert resolved == {
        "id": "att-1",
        "contact_id": "contact-1",
        "name_raw": "Old Alex",
        "display_name": "Alex",
        "role": "attendee",
        "is_resolved": True,
        "contact_summary": "Acme · Product Manager",
    }

    attendee.contact_id = None
    attendee.name_raw = "张总"
    unresolved = serialize(attendee)
    assert unresolved["display_name"] == "张总"
    assert unresolved["is_resolved"] is False
    assert unresolved["contact_summary"] == ""

    contact_only = SimpleNamespace(
        id="att-2",
        contact_id="contact-1",
        name_raw=None,
        role="attendee",
    )
    error = apply_patch(
        contact_only,
        name=None,
        contact_id="",
        role=None,
        previous_contact=contact,
    )
    assert error is None
    unbound = serialize(contact_only)
    assert unbound["contact_id"] is None
    assert unbound["display_name"] == "Alex"

    unresolved_attendee = SimpleNamespace(
        id="att-3",
        contact_id=None,
        name_raw="张总",
        role="attendee",
    )
    error = apply_patch(
        unresolved_attendee,
        name="",
        contact_id=None,
        role=None,
    )
    assert error == "attendee requires a contact or display name"
    assert unresolved_attendee.name_raw == "张总"

    contact_only.contact_id = "contact-1"
    contact_only.name_raw = None
    detach_contact(contact_only, contact)
    assert contact_only.contact_id is None
    assert contact_only.name_raw == "Alex"

    existing_fallback = SimpleNamespace(
        id="att-4",
        contact_id="contact-1",
        name_raw="Original Alex",
        role="attendee",
    )
    detach_contact(existing_fallback, contact)
    assert existing_fallback.contact_id is None
    assert existing_fallback.name_raw == "Original Alex"

    assert "async def update_event_attendee(" in tools_source
    assert "async def delete_event_attendee(" in tools_source
    assert "update_event_attendee" in server_source
    assert "delete_event_attendee" in server_source
    assert '@router.patch("/events/{event_id}/attendees/{attendee_id}")' in events_source
    assert '@router.delete("/events/{event_id}/attendees/{attendee_id}")' in events_source

    for field in ("name", "company", "title", "phone", "email"):
        assert f"Contact.{field}.ilike" in contacts_source

    attendee_order = (
        ".order_by(EventAttendee.created_at.asc(), EventAttendee.id.asc())"
    )
    assert tools_source.count(attendee_order) >= 2
    assert attendee_order in (ROOT / "core/timeline.py").read_text()

    add_attendee = tools_source[
        tools_source.index("async def add_event_attendee("):
        tools_source.index("async def update_event_attendee(")
    ]
    assert "name_raw=_event_attendee_unbound_name(name, contact)" in add_attendee

    delete_contact = contacts_source[
        contacts_source.index('@router.delete("/contacts/{contact_id}")'):
        contacts_source.index("\ndef _serialize", contacts_source.index('@router.delete("/contacts/{contact_id}")'))
    ]
    assert "select(EventAttendee)" in delete_contact
    assert "EventAttendee.contact_id == c.id" in delete_contact
    assert "_detach_event_attendee_contact(attendee, c)" in delete_contact
    assert delete_contact.index("_detach_event_attendee_contact") < delete_contact.index("db.delete(c)")


if __name__ == "__main__":
    test_event_attendee_contract()
    print("ok - event attendee contract")
