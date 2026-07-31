from datetime import datetime
from types import SimpleNamespace

import pytest
from pydantic import ValidationError

from app.domains.notifications.schemas import NotificationCreate, NotificationPayload


@pytest.mark.parametrize(
    "values",
    [
        {"user_id": "u1", "type": "", "title": "title"},
        {"user_id": "u1", "type": "x" * 33, "title": "title"},
        {"user_id": "u1", "type": "report_done", "title": ""},
        {
            "user_id": "u1",
            "type": "report_done",
            "title": "title",
            "link": "x" * 256,
        },
    ],
)
def test_create_schema_rejects_invalid_public_fields(values):
    with pytest.raises(ValidationError):
        NotificationCreate(**values)


def test_payload_serializes_utc_suffix_and_empty_body():
    payload = NotificationPayload.model_validate(
        SimpleNamespace(
            id="n1",
            type="report_done",
            title="done",
            body=None,
            link=None,
            read=False,
            created_at=datetime(2026, 7, 31, 10, 0, 0),
        )
    )

    assert payload.model_dump(mode="json") == {
        "id": "n1",
        "type": "report_done",
        "title": "done",
        "body": "",
        "link": None,
        "read": False,
        "created_at": "2026-07-31T10:00:00Z",
    }
