"""
Fake external MCP server — Phase B v1.4.x.

Stands in for real third-party MCPs (Notion / Google Calendar / Dingtalk)
during demo + development. Each tool:
  - Sleeps a few seconds (simulates network round-trip)
  - Returns a fake `external_id` + `external_url` shaped exactly like a real
    MCP would, so the task-skill's downstream extraction works unchanged
    when we later swap in real MCPs

Run standalone:
    python -m mcp_server.fake_external_mcp

Wired into the system via backend/agents/mcp_config.py.
"""
import asyncio
import json
import uuid

from fastmcp import FastMCP

mcp = FastMCP("fake-external")


def _fake_id() -> str:
    return uuid.uuid4().hex[:12]


@mcp.tool()
async def create_notion_page(title: str, content: str = "") -> str:
    """
    Create a page in Notion. Use when the user wants to save / sync content
    into their Notion workspace.

    Args:
        title:   Page title.
        content: Body markdown (optional).

    Returns:
        JSON with external_id + external_url.
    """
    await asyncio.sleep(3)
    fid = _fake_id()
    return json.dumps({
        "ok":              True,
        "external_system": "notion",
        "external_id":     fid,
        "external_url":    f"https://www.notion.so/fake-{fid}",
        "external_type":   "page",
        "title":           title,
        "summary":         (content[:120] + ("…" if len(content) > 120 else "")) if content else "",
    }, ensure_ascii=False)


@mcp.tool()
async def create_calendar_event(
    title: str,
    start_at: str = "",
    duration_minutes: int = 60,
    location: str = "",
) -> str:
    """
    Create an event in Google Calendar. Use when the user wants to add a
    meeting / appointment to their calendar.

    Args:
        title:            Event title.
        start_at:         ISO8601 start time with TZ (e.g. "2026-05-27T15:00:00+08:00"). Empty = unspecified.
        duration_minutes: Length in minutes (default 60).
        location:        Optional location.

    Returns:
        JSON with external_id + external_url.
    """
    await asyncio.sleep(3)
    fid = _fake_id()
    return json.dumps({
        "ok":              True,
        "external_system": "google_calendar",
        "external_id":     fid,
        "external_url":    f"https://calendar.google.com/event?eid=fake-{fid}",
        "external_type":   "event",
        "title":           title,
        "summary":         f"{start_at} · {duration_minutes}min" + (f" · {location}" if location else ""),
    }, ensure_ascii=False)


@mcp.tool()
async def send_dingtalk(message: str, channel: str = "default") -> str:
    """
    Send a message to Dingtalk. Use when the user wants to ping a colleague
    or post to a Dingtalk channel.

    Args:
        message: Message body.
        channel: Channel name (defaults to "default").

    Returns:
        JSON with external_id + external_url (deep link to the message).
    """
    await asyncio.sleep(2)
    fid = _fake_id()
    return json.dumps({
        "ok":              True,
        "external_system": "dingtalk",
        "external_id":     fid,
        "external_url":    f"https://im.dingtalk.com/m/fake-{fid}",
        "external_type":   "message",
        "title":           message[:60] + ("…" if len(message) > 60 else ""),
        "summary":         f"channel: {channel}",
    }, ensure_ascii=False)


if __name__ == "__main__":
    mcp.run()
