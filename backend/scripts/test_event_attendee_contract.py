"""Regression checks for the event attendee API contract."""

from __future__ import annotations

import ast
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]


def _load_attendee_helpers(source: str) -> dict:
    module = ast.parse(source)
    expected = {
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
    unbound_name = helpers["_event_attendee_unbound_name"]
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

    contact_only = SimpleNamespace(name_raw=None)
    assert unbound_name(contact_only, contact) == "Alex"
    assert unbound_name(contact_only, SimpleNamespace(name="  ")) is None

    assert "async def update_event_attendee(" in tools_source
    assert "async def delete_event_attendee(" in tools_source
    assert "update_event_attendee" in server_source
    assert "delete_event_attendee" in server_source
    assert '@router.patch("/events/{event_id}/attendees/{attendee_id}")' in events_source
    assert '@router.delete("/events/{event_id}/attendees/{attendee_id}")' in events_source

    for field in ("name", "company", "title", "phone", "email"):
        assert f"Contact.{field}.ilike" in contacts_source


if __name__ == "__main__":
    test_event_attendee_contract()
    print("ok - event attendee contract")
