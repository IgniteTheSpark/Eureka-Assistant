import json
from io import StringIO

from ring_desktop import codex_notify
from ring_desktop.codex_notify import (
    CODEX_BUNDLE_ID,
    event_for_payload,
    post_ring_event,
)


def test_completed_turn_maps_to_task_complete():
    assert event_for_payload({"type": "agent-turn-complete"}) == "taskComplete"


def test_attention_and_error_payloads_are_supported():
    assert event_for_payload({"type": "approval-requested"}) == "needsAttention"
    assert event_for_payload({"type": "agent-turn-failed"}) == "error"


def test_codex_hook_payloads_map_to_vibration_events():
    assert event_for_payload({"hook_event_name": "Stop"}) == "taskComplete"
    assert event_for_payload(
        {"hook_event_name": "PermissionRequest"}
    ) == "needsAttention"


def test_unknown_payload_does_not_trigger_ring_event():
    assert event_for_payload({"type": "something-else"}) is None


def test_post_ring_event_uses_codex_bundle_and_event():
    captured = {}

    class Response:
        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return None

        def read(self):
            return b'{"ok":true}'

    def open_request(request, timeout):
        captured["url"] = request.full_url
        captured["body"] = json.loads(request.data)
        captured["timeout"] = timeout
        return Response()

    assert post_ring_event("taskComplete", open_request=open_request)
    assert captured == {
        "url": "http://127.0.0.1:17863/event",
        "body": {"app": CODEX_BUNDLE_ID, "event": "taskComplete"},
        "timeout": 1,
    }


def test_main_reads_hook_json_from_stdin(monkeypatch):
    events = []
    computer_use = []
    monkeypatch.setattr(
        codex_notify, "post_ring_event", lambda event: events.append(event) or True
    )
    monkeypatch.setattr(
        codex_notify,
        "notify_computer_use",
        lambda payload: computer_use.append(payload),
    )
    stdout = StringIO()

    result = codex_notify.main(
        [],
        stdin=StringIO('{"hook_event_name":"Stop","turn_id":"turn-1"}'),
        stdout=stdout,
    )

    assert result == 0
    assert events == ["taskComplete"]
    assert computer_use == []
    assert json.loads(stdout.getvalue()) == {}
