"""
AgentRunner — the one place that runs an ADK agent once and collects the result
(codex review §AgentRunner).

Before this, every batch pipeline (flash dispatch / flash sub-skill / report /
task / design) hand-rolled the same loop: create an in-memory session, spin a
`Runner`, iterate `run_async`, pull the final text + tool events. That copy was
mis-homed in `flash_pipeline._run_agent` (report/task imported it FROM flash,
a layering smell) and design_agent had its own duplicate.

This module owns the canonical batch runner. It returns a structured
`AgentRunResult` (final text + tool events + summed token usage) so callers get
one shape, and usage accounting lives in one spot. Chat keeps its own STREAMING
loop (it must yield SSE events live + has retry) — a `run_stream` variant is a
later step; for now chat shares only the `core/event_mapper` helpers.

Next per the roadmap (§1.10): fold retry budget + ToolGroundTruthResolver in here.
"""
import uuid
from dataclasses import dataclass, field
from typing import Optional

from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai.types import Content, Part

from core.event_mapper import event_tool_calls, event_tool_results, event_usage

APP_NAME = "eureka-agent-runner"
_session_service = InMemorySessionService()


@dataclass
class AgentRunResult:
    """Outcome of one agent run.

    text:         the agent's final-response text (may be empty/garbled — callers
                  that need structured output parse it, with tool_events as a
                  ground-truth fallback).
    tool_events:  [{name, args, response}] captured in call order. The fallback
                  that lets a pipeline recover when the model writes a write to
                  the DB but emits malformed final JSON.
    usage_tokens: summed total_tokens the model reported across the run (0 if the
                  provider doesn't report usage). For cost visibility / budgets.
    """
    text: str = ""
    tool_events: list = field(default_factory=list)
    usage_tokens: int = 0


async def run_agent(agent, message: str, user_id: str) -> AgentRunResult:
    """Run [agent] once on [message] and collect the result.

    Spins a one-shot in-memory ADK session (each call is isolated). Mirrors the
    behavior of the old flash_pipeline._run_agent, plus token-usage accounting.
    """
    sid = str(uuid.uuid4())
    await _session_service.create_session(
        app_name=APP_NAME, user_id=user_id, session_id=sid,
    )
    runner = Runner(agent=agent, app_name=APP_NAME, session_service=_session_service)
    user_msg = Content(role="user", parts=[Part(text=message)])

    result = AgentRunResult()
    # ADK batches PARALLEL function calls/results into a single event (deepseek
    # does this for multi-intent turns). Use the plural accessors and pair each
    # result to its call by name so no parallel tool event is silently dropped
    # (codex round-2 P2). pending_calls is a FIFO of unpaired calls.
    pending_calls: list = []
    async for event in runner.run_async(
        user_id=user_id, session_id=sid, new_message=user_msg,
    ):
        calls = event_tool_calls(event)
        if calls:
            pending_calls.extend(calls)
            continue
        results = event_tool_results(event)
        if results:
            for tr in results:
                args = {}
                for i, pc in enumerate(pending_calls):
                    if pc.get("name") == tr.get("name"):
                        args = pc.get("args", {})
                        pending_calls.pop(i)
                        break
                result.tool_events.append({
                    "name":     tr.get("name", ""),
                    "args":     args,
                    "response": tr.get("response", {}),
                })
            continue
        u = event_usage(event)
        if u.get("total_tokens"):
            result.usage_tokens += u["total_tokens"]
        if event.is_final_response() and event.content:
            parts = event.content.parts or []
            if parts:
                result.text = parts[0].text or ""
    return result
