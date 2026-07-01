"""Regression checks for Flash Reply Agent boundaries.

Avoids importing ADK by AST-loading pure helpers and statically checking the
pipeline wiring.
"""

from __future__ import annotations

import ast
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _module(path: str) -> ast.Module:
    return ast.parse((ROOT / path).read_text(), filename=path)


def _fn(tree: ast.Module, name: str) -> ast.FunctionDef:
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == name:
            return node
    raise AssertionError(f"{name} not found")


def _async_fn(tree: ast.Module, name: str) -> ast.AsyncFunctionDef:
    for node in tree.body:
        if isinstance(node, ast.AsyncFunctionDef) and node.name == name:
            return node
    raise AssertionError(f"{name} not found")


def _load_reply_helpers() -> dict:
    src = (ROOT / "agents/flash_reply.py").read_text()
    mod = ast.parse(src)
    body = []
    for node in mod.body:
        if isinstance(node, ast.Import) and any(a.name == "re" for a in node.names):
            body.append(node)
        elif isinstance(node, ast.FunctionDef) and node.name in {"_slim_card", "_clean_reply"}:
            body.append(node)
    ns: dict = {}
    exec(compile(ast.Module(body=body, type_ignores=[]), "flash_reply_subset", "exec"), ns)
    return ns


def _assert_reply_cleaning_and_slimming() -> None:
    ns = _load_reply_helpers()
    clean = ns["_clean_reply"]
    slim = ns["_slim_card"]

    assert clean("包子这笔 8 块我帮你记好了。") == "包子这笔 8 块我帮你记好了。"
    assert clean("已记录 1 项内容。") == ""
    assert clean('{"asset_id":"x","payload":{}}') == ""
    assert clean("tool_create_asset 调好了") == ""

    card = slim({
        "card_type": "expense",
        "title": "¥8",
        "subtitle": "包子",
        "asset_id": "secret",
        "payload": {"amount": 8},
        "meta_fields": [{"value": "生活"}],
    })
    assert card == {
        "type": "expense",
        "title": "¥8",
        "subtitle": "包子",
        "meta": ["生活"],
    }


def _assert_reply_agent_boundaries() -> None:
    reply = _module("agents/flash_reply.py")
    src = (ROOT / "agents/flash_reply.py").read_text()
    assert "tools=[]" in src, "Flash Reply Agent must not get tools"
    assert "asyncio.wait_for" in src, "Flash Reply Agent must be timeout-bounded"
    assert "asset_id" in src and "_slim_card" in src, "Reply input must be slimmed"
    assert "不要说「已记录 N 项内容」" in src

    gen = _async_fn(reply, "generate_flash_summary")
    args = [a.arg for a in gen.args.args]
    for required in ("source_text", "cards", "derived_assets", "pending", "suggest_skill", "user_id"):
        assert required in args


def _assert_pipeline_uses_reply_agent_and_fallback() -> None:
    pipeline = _module("agents/flash_pipeline.py")
    aggregate = _async_fn(pipeline, "_aggregate")
    calls = [
        n for n in ast.walk(aggregate)
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
    ]
    names = {c.func.id for c in calls}
    assert "generate_flash_summary" in names, "_aggregate must call Flash Reply Agent"
    assert "_fallback_flash_summary" in names, "_aggregate must keep non-mechanical fallback"

    fallback = _fn(pipeline, "_fallback_flash_summary")
    constants = {
        n.value for n in ast.walk(fallback)
        if isinstance(n, ast.Constant) and isinstance(n.value, str)
    }
    assert "我帮你记好了。" in constants
    assert "这些我都帮你记好了。" in constants
    assert all("已记录" not in c for c in constants)


if __name__ == "__main__":
    _assert_reply_cleaning_and_slimming()
    _assert_reply_agent_boundaries()
    _assert_pipeline_uses_reply_agent_and_fallback()
