"""Regression checks for fuzzy period handling in typed todo tools.

No DB/backend dependencies: parses source AST so this can run in a bare Python
environment while still guarding the API shape agents rely on.
"""

from __future__ import annotations

import ast
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _module(path: str) -> ast.Module:
    return ast.parse((ROOT / path).read_text(), filename=path)


def _async_fn(tree: ast.Module, name: str) -> ast.AsyncFunctionDef:
    for node in tree.body:
        if isinstance(node, ast.AsyncFunctionDef) and node.name == name:
            return node
    raise AssertionError(f"{name} not found")


def _arg_names(fn: ast.AsyncFunctionDef) -> list[str]:
    return [a.arg for a in fn.args.args]


def _calls(fn: ast.AsyncFunctionDef, name: str) -> list[ast.Call]:
    return [
        n
        for n in ast.walk(fn)
        if isinstance(n, ast.Call)
        and isinstance(n.func, ast.Name)
        and n.func.id == name
    ]


def _assert_todo_signature_and_delegation() -> None:
    tools = _module("mcp_server/tools.py")
    create_todo = _async_fn(tools, "create_todo")
    args = _arg_names(create_todo)
    assert "period" in args, "create_todo must accept period"
    assert "occurred_at" in args, "create_todo must accept occurred_at"

    calls = _calls(create_todo, "create_asset")
    assert calls, "create_todo must delegate to create_asset"
    call = calls[-1]
    keyword_names = {kw.arg for kw in call.keywords}
    assert "period" in keyword_names, "create_todo must pass period by keyword"
    assert "occurred_at" in keyword_names, "create_todo must pass occurred_at by keyword"


def _assert_mcp_tool_signature_and_delegation() -> None:
    server = _module("mcp_server/server.py")
    tool_create_todo = _async_fn(server, "tool_create_todo")
    args = _arg_names(tool_create_todo)
    assert "period" in args, "tool_create_todo must accept period"
    assert "occurred_at" in args, "tool_create_todo must accept occurred_at"

    calls = _calls(tool_create_todo, "create_todo")
    assert calls, "tool_create_todo must delegate to create_todo"
    call = calls[-1]
    keyword_names = {kw.arg for kw in call.keywords}
    assert "period" in keyword_names, "tool_create_todo must pass period by keyword"
    assert "occurred_at" in keyword_names, "tool_create_todo must pass occurred_at by keyword"


def _assert_manual_asset_create_period_passthrough() -> None:
    api = _module("api/assets.py")
    create_req = next(
        (
            node
            for node in api.body
            if isinstance(node, ast.ClassDef) and node.name == "CreateAssetRequest"
        ),
        None,
    )
    assert create_req is not None, "CreateAssetRequest not found"
    fields = {
        stmt.target.id
        for stmt in create_req.body
        if isinstance(stmt, ast.AnnAssign) and isinstance(stmt.target, ast.Name)
    }
    assert "period" in fields, "CreateAssetRequest must accept period"
    assert "occurred_at" in fields, "CreateAssetRequest must accept occurred_at"

    manual_create = _async_fn(api, "manual_create_asset")
    calls = _calls(manual_create, "mcp_create_asset")
    assert calls, "manual_create_asset must delegate to mcp_create_asset"
    keyword_names = {kw.arg for kw in calls[-1].keywords}
    assert "period" in keyword_names, "manual_create_asset must pass period"
    assert "occurred_at" in keyword_names, "manual_create_asset must pass occurred_at"


def _assert_skill_prompts_period_rules() -> None:
    expense = (ROOT / "skills/flash-expense-skill/SKILL.md").read_text()
    todo = (ROOT / "skills/flash-todo-skill/SKILL.md").read_text()

    assert "早上 canonical" not in expense
    assert "下午 → 15:00" not in expense
    assert "payload 不再写 `at`" in expense
    assert 'period="下午"' in expense
    assert 'occurred_at=""' in expense

    assert 'source_text: "下午要开一个会"' in todo
    assert 'tool_create_todo(content="开一个会", due_date="", period="下午", occurred_at="")' in todo
    assert 'source_text: "明天下午要开一个会"' in todo
    assert 'due_date="<tomorrow YYYY-MM-DD>", period="下午", occurred_at=""' in todo
    assert "Do not manufacture default clocks" in todo


def _assert_custom_skill_agent_period_rules() -> None:
    factory_src = (ROOT / "agents/skill_factory.py").read_text()
    assert "asset 级落段参数也必须抽取" in factory_src
    assert "上午/中午/下午/晚上" in factory_src
    assert "YYYY-MM-DDTHH:mm:ss+08:00" in factory_src
    assert "那天T00:00:00+08:00" in factory_src
    assert "严禁" in factory_src and "下午" in factory_src and "15:00" in factory_src

    pipeline = _module("agents/flash_pipeline.py")
    fallback = _async_fn(pipeline, "_force_create_custom_asset")
    assert "today_str" in _arg_names(fallback), "_force_create_custom_asset must receive today_str"
    calls = _calls(fallback, "mcp_create_asset")
    assert calls, "_force_create_custom_asset must delegate to mcp_create_asset"
    keyword_names = {kw.arg for kw in calls[-1].keywords}
    assert "period" in keyword_names, "custom fallback must pass period"
    assert "occurred_at" in keyword_names, "custom fallback must pass occurred_at"
    assert "created_at" in keyword_names, "custom fallback must pass created_at"

    run_intent = _async_fn(pipeline, "_run_intent")
    calls = _calls(run_intent, "_force_create_custom_asset")
    assert calls, "_run_intent must call custom fallback"
    keyword_names = {kw.arg for kw in calls[-1].keywords}
    assert "today_str" in keyword_names or len(calls[-1].args) >= 7, (
        "_run_intent must pass today_str into custom fallback"
    )

    apply_hints = _async_fn(pipeline, "_apply_custom_time_hints")
    assert "today_str" in _arg_names(apply_hints), "_apply_custom_time_hints must receive today_str"
    calls = _calls(run_intent, "_apply_custom_time_hints")
    assert calls, "_run_intent must apply custom time hints after successful create"


if __name__ == "__main__":
    _assert_todo_signature_and_delegation()
    _assert_mcp_tool_signature_and_delegation()
    _assert_manual_asset_create_period_passthrough()
    _assert_skill_prompts_period_rules()
    _assert_custom_skill_agent_period_rules()
