#!/usr/bin/env python3
import ast
import re
import unicodedata
from pathlib import Path
from typing import Optional


SKILL = Path(__file__).resolve().parents[1] / "skills" / "flash-event-skill" / "SKILL.md"


def section(text: str, start: str, end: str) -> str:
    start_at = text.index(start)
    end_at = text.index(end, start_at)
    return text[start_at:end_at]


CALL_LINE = re.compile(
    r"^\s*(?:\d+\.\s*)?`?(tool_query_contact|tool_add_event_attendee)\("
)


def actual_call_lines(text: str) -> list[str]:
    return [line.strip() for line in text.splitlines() if CALL_LINE.match(line)]


def tool_calls(text: str, tool: str) -> list[str]:
    return [line for line in actual_call_lines(text) if CALL_LINE.match(line).group(1) == tool]


def literal_argument(call: str, argument: str) -> Optional[str]:
    match = re.search(rf"\b{re.escape(argument)}\s*=\s*(['\"])(.*?)\1", call)
    return match.group(2) if match else None


def main() -> None:
    text = SKILL.read_text()
    step_3b = section(text, "**Step 3b", "### Update")
    branch_markers = ("#### 0 命中", "#### 1 命中", "#### 2+ 命中")
    for marker in branch_markers:
        assert marker in step_3b, f"missing structured attendee branch: {marker}"

    zero_match = section(step_3b, branch_markers[0], branch_markers[1])
    one_match = section(step_3b, branch_markers[1], branch_markers[2])
    many_matches = section(step_3b, branch_markers[2], "**抽取规则**")

    forbidden_conflicts = (
        "不查 contacts",
        "不查询 contacts",
        "永不查询 contacts",
        "不要尝试匹配 contact",
        "不要传 contact_id",
        "不做智能匹配",
        "重复 add 没关系",
        "重复 attendee(同一个名字出现多次)不去重",
    )
    for conflict in forbidden_conflicts:
        assert conflict not in text, f"legacy attendee guidance remains: {conflict}"

    assert "tool_query_contact" in step_3b
    assert "不创建 contact" in step_3b

    branches = {
        "0": zero_match,
        "1": one_match,
        "2+": many_matches,
    }
    for label, block in branches.items():
        queries = tool_calls(block, "tool_query_contact")
        adds = tool_calls(block, "tool_add_event_attendee")
        assert len(queries) == 1, f"{label} match branch query count: {queries}"
        assert len(adds) == 1, f"{label} match branch add count: {adds}"
        assert literal_argument(queries[0], "name_query") == "<原文里的称呼>"

    zero_add = tool_calls(zero_match, "tool_add_event_attendee")[0]
    assert literal_argument(zero_add, "name") == "<原文里的称呼>"
    assert "contact_id=" not in zero_add

    one_add = tool_calls(one_match, "tool_add_event_attendee")[0]
    assert 'name=exact_contacts[0]["name"]' in one_add
    assert 'contact_id=exact_contacts[0]["contact_id"]' in one_add

    many_add = tool_calls(many_matches, "tool_add_event_attendee")[0]
    assert literal_argument(many_add, "name") == "<原文里的称呼>"
    assert "contact_id=" not in many_add
    assert "exact_contacts[0]" in many_matches and "第一条" in many_matches
    assert "不得" in many_matches or "不使用" in many_matches
    for call in actual_call_lines(many_matches):
        assert "exact_contacts[0]" not in call and "第一条" not in call

    assert "len(contacts)" not in step_3b
    assert "exact_contacts" in step_3b
    assert "Alex Chen" in step_3b and "Alexander" in step_3b
    assert "Alex" in step_3b

    tools_source = (SKILL.parents[2] / "mcp_server" / "tools.py").read_text()
    query_contact = section(tools_source, "async def query_contact", "async def update_contact")
    assert "exact_contacts" in query_contact
    assert "_normalize_contact_name" in query_contact
    assert 'search_query = (name_query or "").strip()' in query_contact
    assert 'f"%{search_query}%"' in query_contact
    tools_module = ast.parse(tools_source)
    normalize_node = next(
        node
        for node in tools_module.body
        if isinstance(node, ast.FunctionDef)
        and node.name == "_normalize_contact_name"
    )
    namespace = {"unicodedata": unicodedata}
    exec(
        compile(ast.Module(body=[normalize_node], type_ignores=[]), "normalize_subset", "exec"),
        namespace,
    )
    normalize = namespace["_normalize_contact_name"]
    assert normalize("  Ａｌｅｘ  ") == "alex"
    assert normalize("Straße") == normalize("STRASSE")

    dedupe_at = step_3b.index("完全重复")
    first_call_at = min(step_3b.index(call) for call in actual_call_lines(step_3b))
    assert dedupe_at < first_call_at

    examples = section(text, "## Examples", "## Notes")
    kevin_example = section(
        examples,
        "**输入:** `周五晚上7点跟Kevin、Kevin和刘洋老师一起吃饭`",
        "**输入:** `明天早上 9 点站会`",
    )
    kevin_queries = [
        call
        for call in tool_calls(kevin_example, "tool_query_contact")
        if "Kevin" in (literal_argument(call, "name_query") or "")
    ]
    kevin_adds = [
        call
        for call in tool_calls(kevin_example, "tool_add_event_attendee")
        if "Kevin" in (literal_argument(call, "name") or "")
    ]
    assert len(kevin_queries) == 1, f"Kevin query calls: {kevin_queries}"
    assert len(kevin_adds) == 1, f"Kevin add calls: {kevin_adds}"

    print("ok - flash event attendee safety contract")


if __name__ == "__main__":
    main()
