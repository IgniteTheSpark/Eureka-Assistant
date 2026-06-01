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


def event_tool_calls(event: Any) -> list[dict]:
    """ALL tool calls in this event, as [{name, args}, ...].

    ADK batches parallel function calls into ONE event (deepseek does this for
    multi-intent turns like "记一笔账 + 建个事件 + 加个联系人"). The old singular
    accessor returned only calls[0], so every call after the first executed on
    the backend but was silently dropped from the SSE stream — the user saw one
    card instead of all of them. Return every call so the stream is complete.
    """
    if not hasattr(event, "get_function_calls"):
        return []
    out: list[dict] = []
    for fc in event.get_function_calls() or []:
        args = getattr(fc, "args", None) or {}
        try:
            args_dict = dict(args)
        except (TypeError, ValueError):
            args_dict = {"_raw": str(args)}
        out.append({"name": getattr(fc, "name", "unknown"), "args": args_dict})
    return out


def event_tool_results(event: Any) -> list[dict]:
    """ALL tool results in this event, as [{name, response}, ...]. See
    event_tool_calls — parallel results were dropped the same way."""
    if not hasattr(event, "get_function_responses"):
        return []
    out: list[dict] = []
    for fr in event.get_function_responses() or []:
        resp = getattr(fr, "response", None) or {}
        try:
            resp_dict = dict(resp)
        except (TypeError, ValueError):
            resp_dict = {"_raw": str(resp)}
        out.append({"name": getattr(fr, "name", "unknown"), "response": resp_dict})
    return out


def event_tool_call(event: Any) -> Optional[dict]:
    """First tool call as {name, args}, or None. (Back-compat singular; prefer
    event_tool_calls for streaming so parallel calls aren't dropped.)"""
    calls = event_tool_calls(event)
    return calls[0] if calls else None


def event_tool_result(event: Any) -> Optional[dict]:
    """First tool result as {name, response}, or None. (Back-compat singular.)"""
    results = event_tool_results(event)
    return results[0] if results else None


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
