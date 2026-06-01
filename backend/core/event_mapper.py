"""
ADK Event → Message-field mapping — Phase B Step 4 (decision Q1 #3).

ADK Runner emits Event objects during each agent run. The API layer
(api/chat.py, Step 5) consumes them in two ways:
1. Stream them out to the frontend as SSE events
2. After the run, persist representative Message rows to Postgres

This module is the ONE place that knows ADK Event structure. ADK upgrades
that change Event shape only touch this file — API and persistence stay clean.

NOTE on ADK API exact shape:
ADK 1.0 Event has methods like is_final_response(), get_function_calls(),
get_function_responses(). The accessors below are defensive (hasattr checks)
so different ADK micro-versions don't break us; Step 5 integration will
exercise the real surface and we can tighten or relax as needed.
"""
from typing import Any, Optional


def event_role(event: Any) -> Optional[str]:
    """
    Map an ADK Event → message.role (or None if this event doesn't translate
    to a persistable Message — e.g., intermediate streaming chunks).

    - Final agent response → 'agent'
    - Function call (tool invocation) → 'tool'
    - Function response (tool result) → 'tool'
    """
    if hasattr(event, "get_function_calls") and event.get_function_calls():
        return "tool"
    if hasattr(event, "get_function_responses") and event.get_function_responses():
        return "tool"
    if hasattr(event, "is_final_response") and event.is_final_response():
        return "agent"
    return None


def event_text(event: Any) -> str:
    """Extract text payload from an Event (empty string if none)."""
    content = getattr(event, "content", None)
    if not content:
        return ""
    parts = getattr(content, "parts", None) or []
    for part in parts:
        text = getattr(part, "text", None)
        if text:
            return text
    return ""


def event_tool_call(event: Any) -> Optional[dict]:
    """If this event represents a tool call, return {name, args}; else None."""
    if not hasattr(event, "get_function_calls"):
        return None
    calls = event.get_function_calls() or []
    if not calls:
        return None
    fc = calls[0]
    args = getattr(fc, "args", None) or {}
    try:
        args_dict = dict(args)
    except (TypeError, ValueError):
        args_dict = {"_raw": str(args)}
    return {"name": getattr(fc, "name", "unknown"), "args": args_dict}


def event_tool_result(event: Any) -> Optional[dict]:
    """If this event represents a tool result, return {name, response}; else None."""
    if not hasattr(event, "get_function_responses"):
        return None
    responses = event.get_function_responses() or []
    if not responses:
        return None
    fr = responses[0]
    resp = getattr(fr, "response", None) or {}
    try:
        resp_dict = dict(resp)
    except (TypeError, ValueError):
        resp_dict = {"_raw": str(resp)}
    return {"name": getattr(fr, "name", "unknown"), "response": resp_dict}


def is_streamable_token(event: Any) -> bool:
    """
    Heuristic: is this a partial streaming token (not a complete final
    response, not a tool call)? Used by api/chat.py to decide whether to
    emit an SSE 'token' event vs a 'tool_call' / 'tool_result' / 'done'.
    """
    if event_tool_call(event) or event_tool_result(event):
        return False
    if hasattr(event, "is_final_response") and event.is_final_response():
        return False
    return bool(event_text(event))
