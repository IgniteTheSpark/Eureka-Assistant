"""Regression checks for the event attendee API contract."""

from __future__ import annotations

import ast
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]


def _load_attendee_serializer(source: str):
    module = ast.parse(source)
    body = [
        node
        for node in module.body
        if isinstance(node, ast.FunctionDef)
        and node.name == "_event_attendee_to_dict"
    ]
    assert body, "_event_attendee_to_dict is missing"
    namespace: dict = {}
    exec(
        compile(ast.Module(body=body, type_ignores=[]), "attendee_subset", "exec"),
        namespace,
    )
    return namespace["_event_attendee_to_dict"]


def test_event_attendee_contract() -> None:
    tools_source = (ROOT / "mcp_server/tools.py").read_text()
    events_source = (ROOT / "api/events.py").read_text()
    contacts_source = (ROOT / "api/contacts.py").read_text()
    server_source = (ROOT / "mcp_server/server.py").read_text()

    serialize = _load_attendee_serializer(tools_source)
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
