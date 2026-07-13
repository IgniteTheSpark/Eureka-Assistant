#!/usr/bin/env python3
"""Timeline event enrichment stays batched and API-compatible."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    source = (ROOT / "core/timeline.py").read_text()

    assert "EventAttendee" in source
    assert "_event_attendee_to_dict" in source
    assert ".where(EventAttendee.event_id.in_(event_ids))" in source
    assert ".order_by(EventAttendee.created_at.asc(), EventAttendee.id.asc())" in source
    assert "Contact.id.in_(contact_ids)" in source

    event_item = source[
        source.index("def _event_item("):
        source.index("\ndef _input_turn_item", source.index("def _event_item("))
    ]
    assert "attendees" in event_item
    assert '"payload"' in event_item
    for field in (
        "event_id",
        "title",
        "start_at",
        "end_at",
        "all_day",
        "location",
        "description",
        "attendees",
    ):
        assert f'"{field}"' in event_item, field

    print("ok - timeline event attendee contract")


if __name__ == "__main__":
    main()
