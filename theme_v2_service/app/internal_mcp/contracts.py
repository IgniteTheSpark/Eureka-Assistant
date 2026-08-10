from __future__ import annotations

import inspect
from typing import Any, Sequence


ALL_TRUSTED_ARGUMENTS = frozenset(
    {
        "user_id",
        "session_id",
        "source_input_turn_id",
        "tool_call_id",
        "reference_datetime",
        "timezone_name",
        "intent_id",
        "intent_operation",
    }
)

ROOT_MUTATION_TOOLS = frozenset(
    {
        "tool_create_asset",
        "tool_create_todo",
        "tool_create_note",
        "tool_update_asset",
        "tool_delete_asset",
        "tool_create_contact",
        "tool_update_contact",
        "tool_delete_contact",
        "tool_create_event",
        "tool_update_event",
        "tool_delete_event",
    }
)

_CONTEXTUAL_QUERY_TOOLS = frozenset({"tool_resolve_capture_target"})
_TEMPORAL_TOOLS = frozenset(
    {
        "tool_create_asset",
        "tool_create_todo",
        "tool_create_note",
        "tool_create_event",
    }
)


def trusted_arguments_for_tool(
    tool_name: str,
    *,
    is_mutation: bool,
) -> frozenset[str]:
    names = {"user_id"}
    if is_mutation or tool_name in _CONTEXTUAL_QUERY_TOOLS:
        names.update({"session_id", "source_input_turn_id"})
    if is_mutation:
        names.add("tool_call_id")
    if tool_name in ROOT_MUTATION_TOOLS:
        names.update({"intent_id", "intent_operation"})
    if tool_name in _TEMPORAL_TOOLS:
        names.update({"reference_datetime", "timezone_name"})
    return frozenset(names)


def audit_internal_mcp_contracts(
    definitions: Sequence[dict[str, Any]],
) -> list[str]:
    from app.internal_mcp import server
    from app.internal_mcp.tools import MUTATION_TOOLS, TOOL_HANDLERS

    errors: list[str] = []
    by_name: dict[str, dict[str, Any]] = {}
    for definition in definitions:
        function = definition.get("function")
        if not isinstance(function, dict):
            continue
        name = str(function.get("name") or "")
        if name:
            by_name[name] = function

    registered_names = set(TOOL_HANDLERS)
    missing = sorted(registered_names - set(by_name))
    extra = sorted(set(by_name) - registered_names)
    if missing:
        errors.append(f"registered tools missing from MCP schema: {missing}")
    if extra:
        errors.append(f"MCP schema exposes unknown tools: {extra}")

    for name in sorted(registered_names & set(by_name)):
        transport_object = getattr(server, name, None)
        transport = getattr(transport_object, "fn", transport_object)
        if transport is None or not callable(transport):
            errors.append(f"{name} has no callable transport function")
            continue
        signature = inspect.signature(transport)
        signature_names = {
            parameter.name
            for parameter in signature.parameters.values()
            if parameter.kind
            in {
                inspect.Parameter.POSITIONAL_ONLY,
                inspect.Parameter.POSITIONAL_OR_KEYWORD,
                inspect.Parameter.KEYWORD_ONLY,
            }
        }
        trusted = trusted_arguments_for_tool(
            name,
            is_mutation=name in MUTATION_TOOLS,
        )
        for trusted_name in sorted(trusted - signature_names):
            errors.append(
                f"{name} trusted argument {trusted_name} missing from signature"
            )

        parameters = by_name[name].get("parameters")
        if not isinstance(parameters, dict):
            parameters = {}
        properties = parameters.get("properties")
        visible_names = set(properties) if isinstance(properties, dict) else set()
        for trusted_name in sorted(trusted & visible_names):
            errors.append(
                f"{name} trusted argument {trusted_name} is model-visible"
            )

        expected_visible = signature_names - trusted
        missing_visible = sorted(expected_visible - visible_names)
        unexpected_visible = sorted(visible_names - expected_visible)
        if missing_visible:
            errors.append(
                f"{name} visible signature arguments missing from schema: "
                f"{missing_visible}"
            )
        if unexpected_visible:
            errors.append(
                f"{name} schema arguments missing from signature: "
                f"{unexpected_visible}"
            )

        expected_required = {
            parameter.name
            for parameter in signature.parameters.values()
            if parameter.name not in trusted
            and parameter.default is inspect.Parameter.empty
            and parameter.kind
            in {
                inspect.Parameter.POSITIONAL_ONLY,
                inspect.Parameter.POSITIONAL_OR_KEYWORD,
                inspect.Parameter.KEYWORD_ONLY,
            }
        }
        schema_required = set(parameters.get("required") or [])
        if schema_required != expected_required:
            errors.append(
                f"{name} required schema arguments drift: "
                f"expected={sorted(expected_required)} actual={sorted(schema_required)}"
            )
    return errors
