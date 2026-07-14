"""Codex legacy-notify bridge for Ring-desktop and Computer Use."""

import json
import subprocess
import sys
from typing import Callable, Optional
from urllib.request import Request, urlopen


CODEX_BUNDLE_ID = "com.openai.codex"
RING_EVENT_URL = "http://127.0.0.1:17863/event"
SKY_CLIENT = (
    "/Users/admin/.codex/computer-use/Codex Computer Use.app/Contents/"
    "SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
)

EVENT_BY_PAYLOAD_TYPE = {
    "agent-turn-complete": "taskComplete",
    "approval-requested": "needsAttention",
    "input-requested": "needsAttention",
    "agent-turn-failed": "error",
    "error": "error",
}
EVENT_BY_HOOK_NAME = {
    "Stop": "taskComplete",
    "PermissionRequest": "needsAttention",
}


def event_for_payload(payload: dict) -> Optional[str]:
    return (
        EVENT_BY_HOOK_NAME.get(payload.get("hook_event_name"))
        or EVENT_BY_PAYLOAD_TYPE.get(payload.get("type"))
    )


def post_ring_event(
    event_name: str,
    open_request: Callable = urlopen,
) -> bool:
    body = json.dumps(
        {"app": CODEX_BUNDLE_ID, "event": event_name}
    ).encode()
    request = Request(
        RING_EVENT_URL,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with open_request(request, timeout=1) as response:
        response.read()
    return True


def notify_computer_use(payload_text: str) -> None:
    subprocess.run(
        [SKY_CLIENT, "turn-ended", payload_text],
        check=False,
        timeout=5,
    )


def main(argv=None, stdin=None, stdout=None) -> int:
    args = sys.argv[1:] if argv is None else argv
    stdin = sys.stdin if stdin is None else stdin
    stdout = sys.stdout if stdout is None else stdout
    payload_text = args[-1] if args else stdin.read()
    if not payload_text:
        return 0

    try:
        payload = json.loads(payload_text)
        is_hook = "hook_event_name" in payload
        event_name = event_for_payload(payload)
        if event_name:
            post_ring_event(event_name)
        if not is_hook:
            try:
                notify_computer_use(payload_text)
            except (OSError, subprocess.SubprocessError):
                pass
        else:
            stdout.write("{}\n")
    except (OSError, ValueError, TypeError):
        # Notifications must never affect the Codex turn that just completed.
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
