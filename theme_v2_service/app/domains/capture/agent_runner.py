from __future__ import annotations

import asyncio
import hashlib
import json
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from typing import Any

import litellm

from app.domains.sessions.tools import SessionToolExecutor
from app.internal_mcp.runtime import InternalMCPUnavailable
from app.internal_mcp.contracts import ROOT_MUTATION_TOOLS
from app.domains.capture.tool_results import tool_effect_for_name


Completion = Callable[..., Awaitable[Any]]
_TRUSTED_ARGUMENT_FIELDS = frozenset(
    {
        "user_id",
        "session_id",
        "source_input_turn_id",
        "tool_call_id",
        "intent_id",
        "intent_operation",
    }
)


class RetryableAgentRunError(Exception):
    """The model provider or trusted tool runtime is temporarily unavailable."""


class PermanentAgentRunError(Exception):
    """The provider returned a response that cannot be executed safely."""


@dataclass(frozen=True)
class FlashAgentDefinition:
    name: str
    instruction: str
    allowed_tools: frozenset[str] | None = None


@dataclass(frozen=True)
class AgentRunResult:
    text: str = ""
    tool_events: tuple[dict[str, Any], ...] = field(default_factory=tuple)
    usage_tokens: int = 0


def _model_arguments(arguments: dict[str, Any]) -> dict[str, Any]:
    return {
        key: value
        for key, value in arguments.items()
        if key not in _TRUSTED_ARGUMENT_FIELDS
    }


def stable_capture_tool_call_id(
    *,
    recording_id: str,
    intent_ordinal: int,
    tool_name: str,
    arguments: dict[str, Any],
) -> str:
    canonical = json.dumps(
        _model_arguments(arguments),
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
        default=str,
    )
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:20]
    return f"capture:{recording_id}:{intent_ordinal}:{tool_name}:{digest}"


def _message(response: Any) -> Any:
    try:
        return response.choices[0].message
    except AttributeError:
        try:
            return response["choices"][0]["message"]
        except (KeyError, IndexError, TypeError) as exc:
            raise PermanentAgentRunError(
                "flash agent provider returned no message"
            ) from exc


def _message_content(message: Any) -> str:
    value = (
        message.get("content")
        if isinstance(message, dict)
        else getattr(message, "content", None)
    )
    return value.strip() if isinstance(value, str) else ""


def _tool_calls(message: Any) -> list[tuple[str, str, dict[str, Any]]]:
    raw_calls = (
        message.get("tool_calls", [])
        if isinstance(message, dict)
        else getattr(message, "tool_calls", []) or []
    )
    calls: list[tuple[str, str, dict[str, Any]]] = []
    for index, call in enumerate(raw_calls[:4]):
        model_call_id = (
            call.get("id") if isinstance(call, dict) else getattr(call, "id", None)
        ) or f"tool-{index}"
        function = (
            call.get("function")
            if isinstance(call, dict)
            else getattr(call, "function", None)
        )
        name = (
            function.get("name")
            if isinstance(function, dict)
            else getattr(function, "name", "")
        )
        raw_arguments = (
            function.get("arguments", "{}")
            if isinstance(function, dict)
            else getattr(function, "arguments", "{}")
        )
        try:
            arguments = (
                json.loads(raw_arguments)
                if isinstance(raw_arguments, str)
                else raw_arguments
            )
        except (json.JSONDecodeError, TypeError) as exc:
            raise PermanentAgentRunError(
                "flash agent provider returned invalid tool arguments"
            ) from exc
        if not isinstance(name, str) or not name:
            continue
        if not isinstance(arguments, dict):
            raise PermanentAgentRunError(
                "flash agent provider returned invalid tool arguments"
            )
        calls.append((str(model_call_id), name, _model_arguments(arguments)))
    return calls


def _tokens(response: Any) -> int:
    usage = getattr(response, "usage", None)
    if usage is None and isinstance(response, dict):
        usage = response.get("usage")
    value = (
        usage.get("total_tokens")
        if isinstance(usage, dict)
        else getattr(usage, "total_tokens", None)
    )
    return int(value) if isinstance(value, (int, float)) else 0


def _definition_name(definition: dict[str, Any]) -> str:
    function = definition.get("function")
    if not isinstance(function, dict):
        return ""
    name = function.get("name")
    return name if isinstance(name, str) else ""


async def _complete(
    completion: Completion,
    *,
    model: str,
    messages: list[dict[str, Any]],
    definitions: list[dict[str, Any]],
    api_key: str | None,
    timeout_seconds: float,
) -> Any:
    kwargs: dict[str, Any] = {
        "model": model,
        "messages": list(messages),
        "timeout": timeout_seconds,
        "temperature": 0,
    }
    if definitions:
        kwargs["tools"] = definitions
        kwargs["tool_choice"] = "auto"
    if api_key:
        kwargs["api_key"] = api_key
    try:
        return await completion(**kwargs)
    except Exception as exc:
        raise RetryableAgentRunError(
            "flash agent provider unavailable"
        ) from exc


async def run_agent_once(
    agent: FlashAgentDefinition,
    message: str,
    executor: SessionToolExecutor | None,
    *,
    model: str,
    api_key: str | None,
    timeout_seconds: float,
    recording_id: str,
    intent_ordinal: int,
    completion: Completion = litellm.acompletion,
    max_rounds: int = 6,
) -> AgentRunResult:
    if not model:
        raise PermanentAgentRunError("flash agent model is not configured")

    definitions: list[dict[str, Any]] = []
    if executor is not None:
        try:
            available = await executor.definitions()
        except Exception as exc:
            raise RetryableAgentRunError(
                "flash tool runtime unavailable"
            ) from exc
        definitions = [
            definition
            for definition in available
            if isinstance(definition, dict)
            and (
                agent.allowed_tools is None
                or _definition_name(definition) in agent.allowed_tools
            )
        ]

    allowed_names = frozenset(
        name for name in map(_definition_name, definitions) if name
    )
    conversation: list[dict[str, Any]] = [
        {"role": "system", "content": agent.instruction},
        {"role": "user", "content": message},
    ]
    tool_events: list[dict[str, Any]] = []
    usage_tokens = 0
    root_mutation_succeeded = False

    for _round in range(max(1, max_rounds)):
        response = await _complete(
            completion,
            model=model,
            messages=conversation,
            definitions=definitions,
            api_key=api_key,
            timeout_seconds=timeout_seconds,
        )
        usage_tokens += _tokens(response)
        provider_message = _message(response)
        calls = _tool_calls(provider_message)
        if not calls or executor is None:
            return AgentRunResult(
                text=_message_content(provider_message),
                tool_events=tuple(tool_events),
                usage_tokens=usage_tokens,
            )

        conversation.append(
            {
                "role": "assistant",
                "content": _message_content(provider_message),
                "tool_calls": [
                    {
                        "id": model_call_id,
                        "type": "function",
                        "function": {
                            "name": name,
                            "arguments": json.dumps(
                                arguments,
                                ensure_ascii=False,
                                separators=(",", ":"),
                                default=str,
                            ),
                        },
                    }
                    for model_call_id, name, arguments in calls
                ],
            }
        )

        first_root_index = next(
            (
                index
                for index, (_call_id, name, _arguments) in enumerate(calls)
                if name in ROOT_MUTATION_TOOLS
            ),
            None,
        )

        async def execute_tool(
            index: int,
            call: tuple[str, str, dict[str, Any]],
        ) -> tuple[str, str, dict[str, Any], str, dict[str, Any]]:
            model_call_id, name, arguments = call
            trusted_call_id = stable_capture_tool_call_id(
                recording_id=recording_id,
                intent_ordinal=intent_ordinal,
                tool_name=name,
                arguments=arguments,
            )
            if name not in allowed_names:
                return (
                    model_call_id,
                    name,
                    arguments,
                    trusted_call_id,
                    {"ok": False, "error": "tool unavailable"},
                )
            if name in ROOT_MUTATION_TOOLS and (
                root_mutation_succeeded or index != first_root_index
            ):
                return (
                    model_call_id,
                    name,
                    arguments,
                    trusted_call_id,
                    {
                        "ok": False,
                        "error": "one root mutation is allowed per atomic intent",
                    },
                )
            try:
                outcome = await executor.execute(
                    name,
                    arguments,
                    tool_call_id=trusted_call_id,
                )
            except InternalMCPUnavailable as exc:
                raise RetryableAgentRunError(
                    "flash tool runtime unavailable"
                ) from exc
            except Exception as exc:
                raise RetryableAgentRunError(
                    "flash tool runtime unavailable"
                ) from exc
            return (
                model_call_id,
                name,
                arguments,
                trusted_call_id,
                dict(outcome.response),
            )

        outcomes = await asyncio.gather(
            *(execute_tool(index, call) for index, call in enumerate(calls))
        )
        if any(
            name in ROOT_MUTATION_TOOLS and payload.get("ok") is True
            for _model_id, name, _args, _trusted_id, payload in outcomes
        ):
            root_mutation_succeeded = True
        for model_call_id, name, arguments, trusted_call_id, payload in outcomes:
            tool_events.append(
                {
                    "name": name,
                    "effect": tool_effect_for_name(name),
                    "args": arguments,
                    "response": payload,
                    "tool_call_id": trusted_call_id,
                }
            )
            conversation.append(
                {
                    "role": "tool",
                    "tool_call_id": model_call_id,
                    "content": json.dumps(
                        payload,
                        ensure_ascii=False,
                        separators=(",", ":"),
                        default=str,
                    ),
                }
            )

    conversation.append(
        {
            "role": "system",
            "content": (
                "工具轮次已经用完。只能根据已有真实工具结果总结，"
                "不得声称未执行的操作成功。"
            ),
        }
    )
    response = await _complete(
        completion,
        model=model,
        messages=conversation,
        definitions=[],
        api_key=api_key,
        timeout_seconds=timeout_seconds,
    )
    usage_tokens += _tokens(response)
    return AgentRunResult(
        text=_message_content(_message(response)),
        tool_events=tuple(tool_events),
        usage_tokens=usage_tokens,
    )
