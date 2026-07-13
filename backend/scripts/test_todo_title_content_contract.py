from __future__ import annotations

import ast
import inspect
from pathlib import Path

from mcp_server import server, tools


ROOT = Path(__file__).resolve().parents[1]


def _async_fn(module, name: str) -> ast.AsyncFunctionDef:
    tree = ast.parse(Path(inspect.getsourcefile(module)).read_text())
    for node in tree.body:
        if isinstance(node, ast.AsyncFunctionDef) and node.name == name:
            return node
    raise AssertionError(f"{name} not found")


def _arg_names(fn: ast.AsyncFunctionDef) -> list[str]:
    return [arg.arg for arg in fn.args.args]


def _calls(fn: ast.AsyncFunctionDef, call_name: str) -> list[ast.Call]:
    out: list[ast.Call] = []
    for node in ast.walk(fn):
        if not isinstance(node, ast.Call):
            continue
        target = node.func
        if isinstance(target, ast.Name) and target.id == call_name:
            out.append(node)
        elif isinstance(target, ast.Attribute) and target.attr == call_name:
            out.append(node)
    return out


def test_create_todo_accepts_and_persists_title() -> None:
    create_todo = _async_fn(tools, "create_todo")
    args = _arg_names(create_todo)
    assert "title" in args, "create_todo must accept a title separate from content"

    calls = _calls(create_todo, "create_asset")
    assert calls, "create_todo must delegate to create_asset"

    payload_assigns = []
    for node in ast.walk(create_todo):
        if isinstance(node, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id == "payload" for t in node.targets
        ):
            payload_assigns.append(node.value)
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.target.id == "payload":
            payload_assigns.append(node.value)
    assert payload_assigns, "create_todo must build a payload"
    payload_src = ast.unparse(payload_assigns[0])
    assert "'title': title" in payload_src, payload_src
    assert "'content': content" in payload_src, payload_src


def test_mcp_tool_forwards_title() -> None:
    tool_create_todo = _async_fn(server, "tool_create_todo")
    args = _arg_names(tool_create_todo)
    assert "title" in args, "tool_create_todo must expose title to the LLM"

    calls = _calls(tool_create_todo, "create_todo")
    assert calls, "tool_create_todo must delegate to create_todo"
    keyword_names = {kw.arg for kw in calls[0].keywords}
    assert "title" in keyword_names, "tool_create_todo must pass title by keyword"


def test_flash_todo_prompt_defines_title_content_split() -> None:
    prompt = (ROOT / "skills/flash-todo-skill/SKILL.md").read_text()
    assert "**title**" in prompt
    assert "**content**" in prompt
    assert "title=\"给张总打电话\"" in prompt
    assert "content=\"沟通报价和合同风险\"" in prompt


def main() -> None:
    test_create_todo_accepts_and_persists_title()
    test_mcp_tool_forwards_title()
    test_flash_todo_prompt_defines_title_content_split()
    print("ok - todo title/content contract")


if __name__ == "__main__":
    main()
